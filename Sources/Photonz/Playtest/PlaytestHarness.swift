// The scripted playtest harness: drives the real editor from a JSON script
// with synthesized keys and clicks, renders the window offscreen, and leaves
// a log. It exists so an unmanned audit starts from a working walk instead of
// rebuilding one by hand each time. How to run one: docs/design/playtest-harness.md.
//
// Two gates, on purpose:
//  * PHOTONZ_PLAYTEST is defined by Scripts/build-app.sh for the dev and probe
//    variants only, so the shipping build does not contain this file at all.
//  * At runtime only the probe bundle (AppInfo.flavor == .probe) ever reads a
//    script. The dev app a person works in carries the code but never runs it.
#if PHOTONZ_PLAYTEST
import AppKit
import ScreenCaptureKit
import PhotonzCore
import PhotonzRender

@MainActor
enum PlaytestHarness {
    /// `Photonz Probe.app --playtest <script.json>` (via `open --args`).
    static let argument = "--playtest"

    private static var editors: [EditorState] = []
    private static var run: Run?

    /// Every editor announces itself when its canvas lands in a window, so
    /// the run can find the one it just opened.
    static func register(_ editor: EditorState) {
        guard AppInfo.flavor == .probe else { return }
        if !editors.contains(where: { $0 === editor }) { editors.append(editor) }
    }

    /// Called once at launch. Does nothing unless this is the probe and a
    /// script was named on the command line.
    static func startIfRequested(coordinator: AppCoordinator) {
        guard AppInfo.flavor == .probe else { return }
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: argument), flag + 1 < arguments.count else { return }
        let scriptURL = URL(fileURLWithPath: arguments[flag + 1]).standardizedFileURL
        let run = Run(scriptURL: scriptURL, coordinator: coordinator)
        self.run = run
        Task { await run.start() }
    }

    /// The editors that are open and ready to be driven, oldest first.
    fileprivate static var readyEditors: [EditorState] {
        editors.filter { $0.document != nil && $0.hostWindow != nil && $0.viewport != nil }
    }
}

/// One script, executed top to bottom. Stops at the first step that fails and
/// always finishes by writing `done.json`, which is what the launching script
/// waits for.
@MainActor
private final class Run {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    let scriptURL: URL
    let coordinator: AppCoordinator
    var out: URL
    private let startedAt = Date()
    private var log: [[String: Any]] = []

    /// The editor the last `open` produced; every later step targets it.
    private var editor: EditorState?
    private var window: NSWindow?
    private var canvas: CanvasNSView?
    /// The control the last `hover` rested on, so the next one can leave it.
    private var hovered: HintAnchorView?

    init(scriptURL: URL, coordinator: AppCoordinator) {
        self.scriptURL = scriptURL
        self.coordinator = coordinator
        self.out = scriptURL.deletingLastPathComponent().appendingPathComponent("out")
    }

    func start() async {
        let script: PlaytestScript
        do {
            script = try PlaytestScript.decode(try Data(contentsOf: scriptURL))
        } catch {
            prepareOutput()
            finish(status: "failed", steps: 0, error: "\(error)")
            return
        }
        out = script.outputDirectory(besides: scriptURL)
        prepareOutput()
        note(0, "start", "script \(scriptURL.path); \(script.steps.count) steps; release \(Experiments.shared.release.rawValue)")
        var completed = 0
        for (index, step) in script.steps.enumerated() {
            let number = index + 1
            do {
                try await perform(step, number: number)
                completed = number
            } catch {
                note(number, step.name, "FAILED: \(error)")
                finish(status: "failed", steps: completed, error: "step \(number) (\(step.name)): \(error)")
                return
            }
        }
        finish(status: "ok", steps: completed, error: nil)
    }

    // MARK: - Output

    private func prepareOutput() {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: out.appendingPathComponent("done.json"))
    }

    /// Appends a log line and rewrites `log.json`, so a run that dies mid-way
    /// still leaves everything it learned.
    private func note(_ step: Int, _ name: String, _ text: String, state: [String: Any]? = nil) {
        var entry: [String: Any] = [
            "step": step, "do": name, "note": text,
            "t": (Date().timeIntervalSince(startedAt) * 1000).rounded() / 1000,
        ]
        if let state { entry["state"] = state }
        log.append(entry)
        NSLog("PLAYTEST [\(step) \(name)] \(text)")
        write(json: log, to: "log.json")
    }

    private func finish(status: String, steps: Int, error: String?) {
        var done: [String: Any] = [
            "status": status, "steps": steps, "script": scriptURL.path, "out": out.path,
            "seconds": (Date().timeIntervalSince(startedAt) * 100).rounded() / 100,
        ]
        if let error { done["error"] = error }
        note(steps, "done", status == "ok" ? "walk complete" : (error ?? status))
        write(json: done, to: "done.json")
    }

    private func write(json: Any, to name: String) {
        guard JSONSerialization.isValidJSONObject(json),
              let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: out.appendingPathComponent(name))
    }

    private func writePNG(_ image: CGImage, name: String) throws {
        guard let data = ImageCodec.encode(image, format: .png) else { throw Failure(description: "could not encode \(name).png") }
        try data.write(to: out.appendingPathComponent("\(name).png"))
    }

    // MARK: - Steps

    private func perform(_ step: PlaytestStep, number: Int) async throws {
        switch step {
        case .open(let file, let size):
            // Relative to the script, like `out`, so a walk travels with its fixture.
            let url = file.hasPrefix("/")
                ? URL(fileURLWithPath: file)
                : scriptURL.deletingLastPathComponent().appendingPathComponent(file).standardizedFileURL
            try await open(url, size: size, number: number)

        case .wait(let seconds):
            await sleep(seconds)
            note(number, step.name, "\(seconds)s")

        case .key(let key, let modifiers):
            let window = try requireWindow()
            let takenBy = press(key, modifiers: modifiers, in: window)
            await sleep(0.05)
            let chord = "\(modifiers.map(\.rawValue).joined(separator: "+"))\(modifiers.isEmpty ? "" : "+")\(key.name)"
            note(number, step.name, modifiers.isEmpty ? chord : "\(chord) taken by \(takenBy)", state: describe())

        case .move(let at):
            let canvas = try requireCanvas()
            let p = try viewPoint(at)
            if let event = mouseEvent(.mouseMoved, at: p, on: canvas) { canvas.mouseMoved(with: event) }
            await sleep(0.05)
            note(number, step.name, "to \(short(at.point)) \(at.space.rawValue) = view \(short(p))")

        case .hover(let target):
            let window = try requireWindow()
            let canvas = try requireCanvas()
            guard let content = window.contentView else { throw Failure(description: "the window has no content view") }
            let anchors = Self.findAll(HintAnchorView.self, in: content)
            let anchor: HintAnchorView?
            let location: CGPoint
            let place: String
            switch target {
            case .label(let text):
                // The exact label first, then one that starts with the text,
                // then one that mentions it: "Rectangle" is the shape, not
                // Rectangle Select; "Inspector" is the toggle in either state.
                guard let found = anchors.first(where: { $0.label == text })
                        ?? anchors.first(where: { $0.label.hasPrefix(text) })
                        ?? anchors.first(where: { $0.label.range(of: text, options: .caseInsensitive) != nil }) else {
                    let names = anchors.map(\.label).sorted().joined(separator: ", ")
                    throw Failure(description: "no control with a tooltip starting \"\(text)\"; on screen: \(names)")
                }
                anchor = found
                location = found.convert(CGPoint(x: found.bounds.midX, y: found.bounds.midY), to: nil)
                place = "\"\(text)\""
            case .point(let at):
                location = canvas.convert(try viewPoint(at), to: nil)
                anchor = anchors.first { $0.convert($0.bounds, to: nil).contains(location) }
                place = "\(short(at.point)) \(at.space.rawValue)"
            }
            let controller = HintTooltipController.shared
            guard let event = NSEvent.mouseEvent(
                with: .mouseMoved, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 0, pressure: 0) else {
                throw Failure(description: "could not make a mouse event")
            }
            // Through the window, the way a real pointer's move arrives, so
            // AppKit's own tracking areas do the entering and leaving.
            window.sendEvent(event)
            await sleep(0.1)
            var path = "window"
            // If the window did not turn the move into enter and leave
            // events, deliver them by hand, and say so in the log.
            if let hovered, hovered !== anchor, controller.isWatching(hovered) {
                hovered.mouseExited(with: event)
                path = "direct"
            }
            if let anchor, !controller.isWatching(anchor) {
                anchor.mouseEntered(with: event)
                path = "direct"
            }
            hovered = anchor
            await sleep(HintTooltipController.restDelay + 0.4)
            note(number, step.name, "\(place) via \(path) events: \(controller.visibleDescription ?? "no tooltip")", state: describe())

        case .click(let at, let count, let modifiers):
            let canvas = try requireCanvas()
            let p = try viewPoint(at)
            let flags = eventFlags(modifiers)
            if let event = mouseEvent(.leftMouseDown, at: p, on: canvas, flags: flags, clicks: count) { canvas.mouseDown(with: event) }
            if let event = mouseEvent(.leftMouseUp, at: p, on: canvas, flags: flags, clicks: count) { canvas.mouseUp(with: event) }
            await sleep(0.05)
            note(number, step.name, "at \(short(at.point)) \(at.space.rawValue) = view \(short(p))", state: describe())

        case .drag(let from, let to, let steps, let modifiers, let hold):
            let canvas = try requireCanvas()
            let a = try viewPoint(from), b = try viewPoint(to)
            let flags = eventFlags(modifiers)
            if let event = mouseEvent(.leftMouseDown, at: a, on: canvas, flags: flags) { canvas.mouseDown(with: event) }
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                if let event = mouseEvent(.leftMouseDragged, at: p, on: canvas, flags: flags) { canvas.mouseDragged(with: event) }
                await sleep(0.02)
            }
            // Anything that lives only while the button is down — the yellow
            // snap guide, a live preview — has to be photographed here.
            var held = ""
            if let hold, let window = try? requireWindow(), let content = window.contentView {
                try snapshot(content, name: hold)
                await screenCapture(window, name: hold)
                held = ", held \(hold).png"
            }
            // The pointer's shape WHILE the button is down: the only moment a
            // closed-hand grab cue exists, and a walk cannot photograph it.
            let heldCursor = Self.cursorName()
            if let event = mouseEvent(.leftMouseUp, at: b, on: canvas, flags: flags) { canvas.mouseUp(with: event) }
            await sleep(0.05)
            note(number, step.name,
                 "\(short(from.point)) to \(short(to.point)) \(from.space.rawValue)\(held), cursor while down \(heldCursor)",
                 state: describe())

        case .type(let text):
            let window = try requireWindow()
            guard let field = window.firstResponder as? NSTextView else {
                let responder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
                throw Failure(description: "no text field has the keyboard (first responder is \(responder))")
            }
            field.insertText(text, replacementRange: field.selectedRange())
            await sleep(0.05)
            note(number, step.name, "\"\(text)\" into \(type(of: field))")

        case .tool(let tool):
            let editor = try requireEditor()
            editor.setTool(tool)
            await sleep(0.05)
            note(number, step.name, tool.rawValue, state: describe())

        case .measureMode(let mode):
            let editor = try requireEditor()
            let window = try requireWindow()
            guard let key = PlaytestKey("i") else { return }
            var presses = 0
            while !(editor.activeTool == .measure && editor.measureToolMode == mode), presses < 6 {
                press(key, modifiers: [], in: window)
                presses += 1
                await sleep(0.25)
            }
            if editor.activeTool != .measure || editor.measureToolMode != mode {
                editor.setTool(.measure)
                editor.measureToolMode = mode
                note(number, step.name, "I not honoured after \(presses) presses; set \(mode.rawValue) directly", state: describe())
            } else {
                note(number, step.name, "reached \(mode.rawValue) after \(presses) presses of I", state: describe())
            }

        case .waitFor(let condition, let timeout):
            let editor = try requireEditor()
            let deadline = Date().addingTimeInterval(timeout)
            while !holds(condition, editor: editor) {
                guard Date() < deadline else {
                    throw Failure(description: "\(condition) did not happen within \(timeout)s")
                }
                await sleep(0.1)
            }
            note(number, step.name, "\(condition) holds", state: describe())

        case .snapshot(let name):
            let window = try requireWindow()
            guard let content = window.contentView else { throw Failure(description: "the window has no content view") }
            try snapshot(content, name: name)
            await screenCapture(window, name: name)
            note(number, step.name, "\(name).png \(Int(content.bounds.width))x\(Int(content.bounds.height)) pt")

        case .render(let name):
            let editor = try requireEditor()
            guard let document = editor.document, let image = DocumentRenderer().render(document, store: editor.store) else {
                throw Failure(description: "the document did not render")
            }
            try writePNG(image, name: name)
            note(number, step.name, "\(name).png \(image.width)x\(image.height) px")

        case .describe(let stage, let text):
            note(number, stage, text ?? "", state: describe())

        case .clearClipboard:
            NSPasteboard.general.clearContents()
            note(number, step.name, "cleared")

        case .readClipboard(let stage):
            let types = NSPasteboard.general.types?.map(\.rawValue) ?? []
            let text = NSPasteboard.general.string(forType: .string)
            note(number, stage, "clipboard types \(types); text:\n\(text ?? "nil")",
                 state: ["types": types, "text": text ?? NSNull()])

        case .action(let action):
            let editor = try requireEditor()
            switch action {
            case .copySpecList: editor.copyMeasureSpecList()
            case .copyImage: editor.copyCompositeToClipboard()
            case .hideAllMeasurements: editor.setAllMeasurementsVisible(false)
            case .showAllMeasurements: editor.setAllMeasurementsVisible(true)
            case .hideInspector: editor.setInspectorVisible(false)
            case .showInspector: editor.setInspectorVisible(true)
            case .zoomIn: editor.zoomIn()
            case .zoomOut: editor.zoomOut()
            case .zoomToFit: editor.zoomToFit()
            case .undo: editor.undo()
            case .redo: editor.redo()
            }
            await sleep(0.2)
            note(number, step.name, action.rawValue, state: describe())
        }
    }

    // MARK: - Opening

    private func open(_ url: URL, size: CGSize?, number: Int) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Failure(description: "no file at \(url.path)")
        }
        // The menu-bar scene hands the coordinator its openWindow action a
        // beat after launch.
        try await poll("the app's window opener", within: 5) { coordinator.openWindowAction != nil }
        let before = Set(PlaytestHarness.readyEditors.map { ObjectIdentifier($0) })
        coordinator.openWindowAction?(.file(url))
        var opened: EditorState?
        try await poll("an editor for \(url.lastPathComponent)", within: 15) {
            opened = PlaytestHarness.readyEditors.last { !before.contains(ObjectIdentifier($0)) }
                ?? PlaytestHarness.readyEditors.last
            return opened != nil
        }
        guard let opened, let window = opened.hostWindow else { throw Failure(description: "the editor lost its window") }
        // Let the open-time sizing reveal the window, then hide it for the
        // whole run: it stays on screen for AppKit but invisible to a person.
        _ = try? await poll("reveal", within: 2) { window.alphaValue >= 1 }
        window.alphaValue = 0
        if let size {
            let screen = window.screen ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1600, height: 1000)
            window.setFrame(NSRect(x: visible.minX + 40, y: visible.maxY - size.height - 40,
                                   width: size.width, height: size.height), display: true)
        }
        window.makeKey()
        try await poll("the canvas", within: 5) {
            guard let content = window.contentView else { return false }
            canvas = Self.findCanvas(content)
            return canvas != nil
        }
        // The viewport settles a frame after the resize.
        await sleep(0.5)
        editor = opened
        self.window = window
        let documentSize = opened.document?.canvasSize ?? .zero
        note(number, "open", "\(url.lastPathComponent): document \(Int(documentSize.width))x\(Int(documentSize.height)) at pixelScale \(opened.document?.pixelScale ?? 0) (points are in these units); window \(Int(window.frame.width))x\(Int(window.frame.height)) pt; canvas \(Int(canvas?.bounds.width ?? 0))x\(Int(canvas?.bounds.height ?? 0)) pt; zoom \(String(format: "%.3f", opened.viewport?.zoom ?? 0))", state: describe())
    }

    private static func findAll<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        var found: [T] = []
        if let match = view as? T { found.append(match) }
        for subview in view.subviews { found += findAll(type, in: subview) }
        return found
    }

    private static func findCanvas(_ view: NSView) -> CanvasNSView? {
        if let canvas = view as? CanvasNSView { return canvas }
        for subview in view.subviews {
            if let canvas = findCanvas(subview) { return canvas }
        }
        return nil
    }

    private func poll(_ what: String, within seconds: Double, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < deadline else { throw Failure(description: "\(what) did not appear within \(seconds)s") }
            await sleep(0.1)
        }
    }

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    // MARK: - Targets

    private func requireEditor() throws -> EditorState {
        guard let editor else { throw Failure(description: "no editor is open; add an \"open\" step first") }
        return editor
    }

    private func requireWindow() throws -> NSWindow {
        guard let window else { throw Failure(description: "no editor window is open; add an \"open\" step first") }
        return window
    }

    private func requireCanvas() throws -> CanvasNSView {
        guard let canvas else { throw Failure(description: "no canvas is open; add an \"open\" step first") }
        return canvas
    }

    private func viewPoint(_ at: PlaytestPoint) throws -> CGPoint {
        switch at.space {
        case .view:
            return at.point
        case .document:
            guard let viewport = try requireEditor().viewport else { throw Failure(description: "the editor has no viewport yet") }
            return viewport.viewPoint(fromDocument: at.point)
        }
    }

    private func holds(_ condition: PlaytestCondition, editor: EditorState) -> Bool {
        switch condition {
        case .edgeMap: !editor.snappingEdgeMap.isEmpty
        case .captionField: window?.firstResponder is NSTextView
        case .tool(let tool): editor.activeTool == tool
        case .measureMode(let mode): editor.activeTool == .measure && editor.measureToolMode == mode
        }
    }

    // MARK: - Events

    private func eventFlags(_ modifiers: [PlaytestModifier]) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for modifier in modifiers {
            switch modifier {
            case .command: flags.insert(.command)
            case .shift: flags.insert(.shift)
            case .option: flags.insert(.option)
            case .control: flags.insert(.control)
            }
        }
        return flags
    }

    /// Plain keys go to the window, the way typing does. Chords are offered
    /// to the window first (a text field's own shortcuts) and then to the menu
    /// bar; they cannot go through NSApp, because the probe is never the
    /// active app and an inactive app has no key window to route them to.
    /// Returns who took a chord, for the log.
    @discardableResult
    private func press(_ key: PlaytestKey, modifiers: [PlaytestModifier], in window: NSWindow) -> String {
        let flags = eventFlags(modifiers)
        var takenBy = flags.isEmpty ? "window" : "nobody"
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: key.characters, charactersIgnoringModifiers: key.characters,
                isARepeat: false, keyCode: key.keyCode) else { continue }
            // Straight to the window, so no event monitor sees this press;
            // tell the tracker what a monitor would have.
            KeyModifierTracker.record(event)
            if flags.isEmpty || type == .keyUp {
                window.sendEvent(event)
            } else if window.performKeyEquivalent(with: event) {
                takenBy = "window"
            } else if NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
                takenBy = "menu"
            }
        }
        return takenBy
    }

    private func mouseEvent(_ type: NSEvent.EventType, at viewPoint: CGPoint, on view: NSView,
                            flags: NSEvent.ModifierFlags = [], clicks: Int = 1) -> NSEvent? {
        guard let window = view.window else { return nil }
        return NSEvent.mouseEvent(
            with: type, location: view.convert(viewPoint, to: nil), modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)
    }

    // MARK: - Rendering

    /// The window's content drawn offscreen at 2x, so the picture matches
    /// what a person would see on a Retina display.
    private func snapshot(_ view: NSView, name: String) throws {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw Failure(description: "could not make a bitmap for \(name)")
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        drawTooltip(over: view, into: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw Failure(description: "could not encode \(name).png")
        }
        try png.write(to: out.appendingPathComponent("\(name).png"))
    }

    /// A tooltip is its own little window floating over the editor's, so an
    /// offscreen draw of the editor alone would never show one. Paint it in
    /// where it sits, so the picture is what a person would see.
    private func drawTooltip(over view: NSView, into rep: NSBitmapImageRep) {
        guard let window = view.window,
              let panel = HintTooltipController.shared.panel(over: window),
              let tipView = panel.contentView,
              let tipRep = tipView.bitmapImageRepForCachingDisplay(in: tipView.bounds) else { return }
        tipView.cacheDisplay(in: tipView.bounds, to: tipRep)
        let image = NSImage(size: tipView.bounds.size)
        image.addRepresentation(tipRep)
        var rect = view.convert(window.convertFromScreen(panel.frame), from: nil)
        // The bitmap is bottom-up; a flipped view's rect is not.
        if view.isFlipped { rect.origin.y = view.bounds.height - rect.maxY }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        // The context already maps the view's points onto the 2x bitmap.
        NSGraphicsContext.current = context
        image.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The window as the screen actually shows it, beside the offscreen
    /// render: `<name>-sc.png`, from ScreenCaptureKit, of this window alone.
    /// The offscreen draw is what the harness always had, but it resolves
    /// colors per layer and gets some of them wrong (a plain tool button came
    /// out black on the dark bar), so anything judged by color or weight
    /// reads the capture instead. Only when the probe already holds Screen
    /// Recording: the preflight never prompts, so an ungranted probe just
    /// logs that it skipped and the walk goes on.
    private func screenCapture(_ window: NSWindow, name: String) async {
        guard CGPreflightScreenCaptureAccess() else {
            note(0, "capture", "no Screen Recording grant; skipped")
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                note(0, "capture", "window \(window.windowNumber) not in shareable content")
                return
            }
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            let scale = window.backingScaleFactor
            config.width = Int(scWindow.frame.width * scale)
            config.height = Int(scWindow.frame.height * scale)
            config.showsCursor = false
            config.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let rep = NSBitmapImageRep(cgImage: image)
            if let png = rep.representation(using: .png, properties: [:]) {
                try png.write(to: out.appendingPathComponent("\(name)-sc.png"))
                note(0, "capture", "\(name)-sc.png \(image.width)x\(image.height)")
            }
        } catch {
            note(0, "capture", "failed: \(error)")
        }
    }

    // MARK: - State

    private func short(_ p: CGPoint) -> String {
        "(\(Int(p.x.rounded())), \(Int(p.y.rounded())))"
    }

    /// What the editor is doing right now, in the terms an audit talks about.
    private func describe() -> [String: Any] {
        guard let editor else { return [:] }
        let document = editor.document
        let layers = document?.layers ?? []
        let measures = layers.compactMap { layer -> String? in
            guard let measure = layer.measure, let document else { return nil }
            let flags = "\(measure.role.rawValue)\(measure.alignment != nil ? ", alignment" : "")"
            // Feet and readout chip in DOCUMENT space, the same units a walk's
            // clicks are written in, so a walk can prove where things landed.
            let feet = MeasureSnapping.documentMeasure(layer)
            let chip = MeasureSnapping.chipCentre(of: layer)
            return "\(MeasureSpecList.displayName(for: layer)) = \(measure.label(pixelScale: document.pixelScale)) [\(flags)] " +
                "feet \(short(feet?.start ?? measure.start)) to \(short(feet?.end ?? measure.end)) " +
                "chip \(chip.map(short) ?? "hidden") frame \(layer.frame.integral)"
        }
        let arrows = layers.compactMap { layer -> String? in
            guard let annotation = layer.annotation else { return nil }
            var line = "\(annotation.shape) caption=\(annotation.caption ?? "nil") frame \(layer.frame.integral)"
            if annotation.hasCaption {
                // The pill's center in document space, and whether it was
                // placed by hand, so a walk can prove a drag landed.
                let anchor = annotation.captionAnchor()
                let center = CGPoint(x: layer.frame.minX + anchor.x, y: layer.frame.minY + anchor.y)
                line += " pill \(short(center))\(annotation.captionPinned ? " pinned" : "")"
            }
            return line
        }
        return [
            "tool": editor.activeTool.rawValue,
            // The floating bar's measured width, so a walk can prove a
            // change made it narrower rather than eyeballing a snapshot.
            "toolBarWidth": editor.toolBarWidth,
            "measureMode": editor.measureToolMode.rawValue,
            "hint": editor.showsMeasureHint ? "\(editor.measureHintTitle ?? "") · \(editor.measureHintText)" : "none",
            "copied": editor.copyConfirmation.map { "\($0.title) · \($0.detail)" } ?? "none",
            "layers": layers.count,
            "measures": measures,
            "arrows": arrows,
            "selected": editor.selectedLayerID?.uuidString ?? "nil",
            "legend": editor.measureLegendEntries.map(\.label),
            "legendAnchor": editor.measureLegendAnchor.rawValue,
            "legendTopInset": editor.measureLegendTopInset,
            "inspector": editor.isLayersPanelVisible,
            "tooltip": HintTooltipController.shared.visibleDescription ?? "none",
            "edgeMap": !editor.snappingEdgeMap.isEmpty,
            "firstResponder": window?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil",
            // The pointer's shape, so a walk can prove the grab cue appeared
            // over a draggable pill and nowhere else.
            "cursor": Self.cursorName(),
        ]
    }

    /// A name for whatever the pointer currently looks like. The stock cursors
    /// are shared singletons, so identity is the whole test.
    static func cursorName() -> String {
        let current = NSCursor.current
        let known: [(NSCursor, String)] = [
            (.openHand, "openHand"), (.closedHand, "closedHand"), (.arrow, "arrow"),
            (.crosshair, "crosshair"), (.iBeam, "iBeam"), (.pointingHand, "pointingHand"),
        ]
        return known.first { $0.0 === current }?.1 ?? "other"
    }
}
#endif
