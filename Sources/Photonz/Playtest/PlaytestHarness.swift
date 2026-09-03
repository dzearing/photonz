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

    /// Every editor that has announced itself, ready or not — an empty window
    /// has no document yet but still has to be findable, so a walk can hand it
    /// a blank canvas.
    fileprivate static var knownEditors: [EditorState] { editors }

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
        case .blank(let canvas, let size, let card):
            try await blank(canvas: canvas, window: size, card: card, number: number)

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
            // Look the item up BEFORE the press: after it, a menu that renames
            // itself ("Show History" becoming "Hide History") reports the new
            // title and the log names the wrong thing.
            let destination = modifiers.isEmpty ? nil : Self.menuItem(carrying: key, modifiers: modifiers)
            let takenBy = press(key, modifiers: modifiers, in: window)
            await sleep(0.05)
            let chord = "\(modifiers.map(\.rawValue).joined(separator: "+"))\(modifiers.isEmpty ? "" : "+")\(key.name)"
            var detail = modifiers.isEmpty ? chord : "\(chord) taken by \(takenBy)"
            // "taken by menu" on its own has read like a pass for chords that
            // did nothing at all, which is how ⌘Z came to look checked when it
            // was not. Name the item and say when there is nothing behind it.
            if takenBy == "menu", let destination {
                detail += destination.item.action != nil
                    ? " (\(destination.path), which ran)"
                    : " (\(destination.path), which has no action behind it, so NOTHING HAPPENED: \(Self.frozenMenuBar))"
            }
            note(number, step.name, detail, state: describe())

        case .shortcut(let key, let modifiers, let wanted):
            let window = try requireWindow()
            let chord = Self.chord(key, modifiers)
            guard let destination = Self.menuItem(carrying: key, modifiers: modifiers) else {
                throw Failure(description: "no menu item carries \(chord); a `menus` step lists every shortcut the app has")
            }
            let title = destination.item.title
            if let wanted, title.caseInsensitiveCompare(wanted) != .orderedSame {
                throw Failure(description: "\(chord) is \(destination.path), not \"\(wanted)\"")
            }
            // SwiftUI hangs a target and an action on a command item only while
            // it is live; a dimmed one is a bare title with nothing behind it.
            // So this is the honest test of "would pressing it do anything",
            // and it is also why a window-scoped shortcut cannot be pressed in
            // a walk at all. See `Self.frozenMenuBar` for the whole finding.
            guard destination.item.action != nil else {
                throw Failure(description: "\(chord) is \(destination.path), but that item has no action behind it, "
                    + "so pressing it does nothing. \(Self.frozenMenuBar) "
                    + "Use an `action` step for the outcome and keep a `key` step if you want the press on record.")
            }
            let takenBy = press(key, modifiers: modifiers, in: window)
            guard takenBy == "menu" else {
                throw Failure(description: "\(chord) should have gone to \(destination.path) but was taken by \(takenBy)")
            }
            await sleep(0.2)
            note(number, step.name, "\(chord) reached \(destination.path) and it ran", state: describe())

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

        case .focus(let name):
            let window = try requireWindow()
            guard let content = window.contentView else { throw Failure(description: "the window has no content view") }
            let fields = Self.findAll(NSTextField.self, in: content).filter(\.isEditable)
            func label(_ field: NSTextField) -> String {
                field.placeholderString ?? field.accessibilityLabel() ?? ""
            }
            guard let match = fields.first(where: { label($0).caseInsensitiveCompare(name) == .orderedSame }) else {
                let seen = fields.map(label).filter { !$0.isEmpty }
                throw Failure(description: "no editable field labelled \"\(name)\" is on screen; the ones that are: \(seen.isEmpty ? "none" : seen.joined(separator: ", "))")
            }
            guard window.makeFirstResponder(match) else {
                throw Failure(description: "the field labelled \"\(name)\" would not take the keyboard")
            }
            await sleep(0.05)
            note(number, step.name, "\"\(name)\" now holds \"\(match.stringValue)\"", state: describe())

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

        case .dragComponent(let at):
            let canvas = try requireCanvas()
            guard let componentID = editor?.selectedComponentID
                    ?? editor?.selectedStarterComponent?.componentID else {
                throw Failure(description: "no component is picked on the Library shelf to drag")
            }
            let p = try viewPoint(at)
            let operation = canvas.trackComponentDrag(componentID, atViewPoint: p)
            await sleep(0.15)
            let landing = canvas.componentLandingDescription
            let answer = operation.contains(.copy) ? "would place a copy" : "refused"
            let where_ = landing.map { "box \(short($0.rect.origin)) \(short(CGPoint(x: $0.rect.width, y: $0.rect.height)))"
                                       + ($0.host == nil ? ", loose on the canvas" : ", joining a frame") } ?? "nothing shown"
            note(number, step.name, "at \(short(at.point)) \(at.space.rawValue): \(answer), \(where_)",
                 state: describe())

        case .dropComponent(let at):
            let canvas = try requireCanvas()
            // A starter the document has not taken yet has no component layer
            // to answer for it, but dragging its tile onto the canvas is
            // exactly what a person does first, so the drop reads both.
            guard let componentID = editor?.selectedComponentID
                    ?? editor?.selectedStarterComponent?.componentID else {
                throw Failure(description: "no component is picked on the Library shelf to drop")
            }
            // Through the same pasteboard the real drag writes, so the type
            // identifier and the payload are exercised, not just the placing.
            let board = NSPasteboard(name: NSPasteboard.Name("photonz.playtest.componentDrag"))
            board.clearContents()
            board.setData(Data(componentID.uuidString.utf8), forType: ComponentDrag.pasteboardType)
            guard ComponentDrag.componentID(on: board) == componentID else {
                throw Failure(description: "the component drag payload did not survive the pasteboard")
            }
            let p = try viewPoint(at)
            guard canvas.dropComponent(componentID, atViewPoint: p) else {
                throw Failure(description: "the canvas refused the component drop")
            }
            await sleep(0.2)
            note(number, step.name, "at \(short(at.point)) \(at.space.rawValue) = view \(short(p))",
                 state: describe())

        case .dropImage(let file, let at):
            // Straight to the same call the canvas's drag destination makes, so
            // a walk can land a Finder drop without synthesising a drag session.
            let editor = try requireEditor()
            _ = try requireCanvas()
            let url = file.hasPrefix("/")
                ? URL(fileURLWithPath: file)
                : scriptURL.deletingLastPathComponent().appendingPathComponent(file).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw Failure(description: "there is no file at \(url.path) to drop")
            }
            let p = try documentPoint(at)
            editor.addImageLayerOrOpen(at: url, droppedAt: p)
            await sleep(0.3)
            note(number, step.name, "\(url.lastPathComponent) at \(short(p)) document", state: describe())

        case .snapshot(let name):
            // A sheet is its own window on top of the editor's, so while one is
            // up it IS what a person is looking at, and it is what gets
            // photographed.
            let window = try requireWindow().attachedSheet ?? (try requireWindow())
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

        case .menus(let stage, let menu):
            let tree = try readMenuBar(only: menu)
            write(json: tree, to: "menus-\(stage).json")
            let focused = tree["focused"] as? Bool ?? false
            let outline = Self.outline(tree["menus"] as? [[String: Any]] ?? [], dimming: focused)
            let heading = focused
                ? "\(tree["focus"] as? String ?? "a window") has focus; menu bar reads:"
                : "nothing in the probe has focus, so this menu bar is frozen at the state it was built in at launch: what is dimmed, and any title that renames itself with the document, is NOT what a person would see. Order and shortcuts are exact. Menu bar reads:"
            let open = (tree["windows"] as? [[String: Any]] ?? [])
                .map { $0["title"] as? String ?? "?" }.joined(separator: ", ")
            let reading = "\(heading)\n\(outline)\n  windows open: \(open)"
            // The same reading as a file you can just `cat`. The JSON is for a
            // program; nobody should have to unpick log.json to quote a menu.
            try? Data(reading.utf8).write(to: out.appendingPathComponent("menus-\(stage).txt"))
            note(number, step.name, reading, state: tree)

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
            case .newCanvasDialog: editor.isBlankCanvasDialogPresented = true
            case .createCanvas:
                editor.isBlankCanvasDialogPresented = false
                editor.createBlankCanvas(size: BlankCanvas.defaultPreset.size)
            case .group: editor.groupSelection()
            case .ungroup: editor.ungroupSelection()
            case .stackSelection: editor.stackSelection(.stack)
            case .gridSelection: editor.stackSelection(.grid)
            case .deleteLayer: editor.deleteSelectedLayers()
            case .selectComponentOriginal: editor.selectComponentOriginal()
            case .copyLayer: editor.copySelectedLayer()
            case .pasteLayer: editor.paste()
            case .paintScreenSurface:
                if let id = editor.selectedLayerID, editor.document?.layer(id: id)?.isFrame == true {
                    editor.setFrameBackground(id: id, hex: "#3B82F6")
                }
            case .newFrameDialog: editor.isNewFrameDialogPresented = true
            case .frameSelection: editor.frameSelection()
            case .makeComponent: editor.makeComponent()
            case .exposeWording: editor.exposeFirstProperty(kind: .text)
            case .exposeChoice: editor.exposeFirstProperty(kind: .variant)
            case .cycleChoice: editor.cycleInstanceChoice()
            case .makeChoice: editor.makeChoice()
            case .detachInstance: editor.detachInstance()
            case .roundCorners:
                if let id = editor.selectedLayerID {
                    editor.setLayerStyle(id: id) { $0.cornerRadius = 24 }
                }
            case .addShadow:
                if let id = editor.selectedLayerID {
                    editor.setLayerStyle(id: id) {
                        $0.shadow = ShadowStyle(radius: 18, offset: CGSize(width: 0, height: 10),
                                                spread: 0, colorHex: "#000000", opacity: 0.55)
                    }
                }
            case .fadeLayer:
                if let id = editor.selectedLayerID {
                    editor.setLayerStyle(id: id) { $0.opacity = 0.35 }
                }
            case .fadeLayerSlightly:
                if let id = editor.selectedLayerID {
                    editor.setLayerStyle(id: id) { $0.opacity = 0.75 }
                }
            case .borderLayer:
                if let id = editor.selectedLayerID {
                    editor.setLayerStyle(id: id) {
                        $0.borderWidth = 6
                        $0.borderColorHex = "#2B5BFF"
                    }
                }
            case .followOriginalLook:
                if let id = editor.selectedLayerID {
                    editor.clearInstanceStyleOverrides(instance: id)
                }
            case .saveColorStyle:
                // The picked layers' first color that could carry a name: with
                // several picked that is the first one they all share.
                if let slot = editor.colorStyleSlots
                    .first(where: { editor.colorStyleSelection(slot: $0).savableColorHex != nil }) {
                    editor.beginNamingColorStyle(slot: slot)
                }
            case .useFirstColorStyle:
                // The first pairing that is actually on offer. A saved color
                // only turns up on the parts it is for, so "the first style"
                // and "the first slot" are not always a pair that go together.
                if let pair = editor.colorStyleSlots.lazy.compactMap({ slot in
                    editor.colorStyles(for: slot).first.map { (slot, $0.id) }
                }).first {
                    editor.useColorStyle(slot: pair.0, styleID: pair.1)
                }
            case .unlinkColorStyle:
                if let slot = editor.colorStyleSlots
                    .first(where: { editor.colorStyleSelection(slot: $0).wearsAnyStyle }) {
                    editor.unlinkColorStyle(slot: slot)
                }
            case .paintSelectionColor:
                // The first row on screen, which is the one a person reaches
                // for: the well paints every picked layer that has that color.
                if let slot = editor.colorStyleSlots.first {
                    editor.setSelectionColor(slot: slot, hex: "#B0184A")
                }
            case .toggleFillSwitch:
                // The checkbox that used to be a shape's Fill toggle and a
                // frame's "No background": one click, every picked layer.
                let fill = editor.colorSwitch(slot: .fill)
                if fill.isOffered { editor.setColorEnabled(slot: .fill, on: !fill.isOn) }
            case .pickFirstColorStyle:
                if let first = editor.colorStyleEntries.first {
                    editor.selectLibraryItem(first.id)
                }
            case .recolorPickedColorStyle:
                if let style = editor.selectedColorStyle {
                    editor.setColorStyleHex(styleID: style.id, hex: "#00A870")
                }
            case .pickFirstComponent:
                if let first = editor.componentEntries.first {
                    editor.selectLibraryItem(first.id)
                }
            case .exportDialog: editor.isExportDialogPresented = true
            case .showLibrary: editor.setLibraryVisible(true)
            case .showComponentShelf:
                editor.setLibraryVisible(true)
                UserDefaults.standard.set(LibraryScope.components.rawValue,
                                          forKey: LibraryPanel.scopeKey)
            case .hideLibrary: editor.setLibraryVisible(false)
            case .placeLibraryPick: editor.placeLibraryPick()
            case .insertPickedComponent: editor.insertPickedComponent()
            case .selectCanvas: editor.selectCanvas()
            case .duplicateLayer: editor.duplicateSelectedLayers()
            case .renameSelectedLayer:
                if let id = editor.selectedLayerID {
                    editor.renameLayer(id: id, to: "Renamed Layer")
                }
            case .beginRenameSelectedLayer:
                if let id = editor.selectedLayerID { editor.beginRenamingLayer(id: id) }
            case .alignLeft: editor.alignSelection(.left)
            case .alignHorizontalCenter: editor.alignSelection(.horizontalCenter)
            case .alignRight: editor.alignSelection(.right)
            case .alignTop: editor.alignSelection(.top)
            case .alignVerticalCenter: editor.alignSelection(.verticalCenter)
            case .alignBottom: editor.alignSelection(.bottom)
            case .spaceEvenlyAcross: editor.distributeSelection(.horizontal)
            case .spaceEvenlyDown: editor.distributeSelection(.vertical)
            case .stepIntoSelection:
                if let id = editor.selectedLayerID,
                   let child = editor.document?.layer(id: id)?.children.first {
                    editor.selectLayer(child.id, inGroup: id)
                }
            case .pickNextSibling:
                if let context = editor.groupContextID, let id = editor.selectedLayerID,
                   let siblings = editor.document?.layer(id: context)?.children,
                   let at = siblings.firstIndex(where: { $0.id == id }) {
                    editor.selectLayer(siblings[(at + 1) % siblings.count].id, inGroup: context)
                }
            case .stretchSelectionAcross:
                if let id = editor.selectedLayerID {
                    editor.setPlacement(id: id, horizontal: .stretch)
                }
            case .stretchContentsAcross:
                if let id = editor.selectedLayerID {
                    editor.setContentPlacement(id: id, horizontal: .stretch)
                }
            case .closeSheets:
                editor.isExportDialogPresented = false
                editor.isNewFrameDialogPresented = false
                editor.isBlankCanvasDialogPresented = false
                editor.isResizeDialogPresented = false
                editor.isCanvasSizeDialogPresented = false
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
        guard let opened else { throw Failure(description: "the editor lost its window") }
        try await adopt(opened, window: size, step: "open", subject: url.lastPathComponent, number: number)
    }

    /// Start from nothing: a new window, handed a blank canvas of `canvas`,
    /// which is what the empty window's Blank canvas row does once a size has
    /// been chosen. From here on the walk drives it like any other document.
    private func blank(canvas size: CGSize, window: CGSize?, card: String?, number: Int) async throws {
        try await poll("the app's window opener", within: 5) { coordinator.openWindowAction != nil }
        let before = Set(PlaytestHarness.knownEditors.map { ObjectIdentifier($0) })
        coordinator.openWindowAction?(.fresh(UUID()))
        var fresh: EditorState?
        try await poll("an empty editor window", within: 15) {
            fresh = PlaytestHarness.knownEditors.last { !before.contains(ObjectIdentifier($0)) }
            return fresh != nil
        }
        guard let fresh else { throw Failure(description: "no empty window appeared") }
        if let card {
            try await photographEmptyWindow(fresh, window: window, name: card, number: number)
        }
        // Through the same door the sheet uses, so a walk proves the empty
        // window fills itself rather than spawning a second one.
        fresh.createBlankCanvas(size: size)
        try await adopt(fresh, window: window, step: "blank",
                        subject: "blank \(Int(size.width))x\(Int(size.height))", number: number)
    }

    /// The empty window before anything is in it: the onboarding card, which
    /// stops existing the moment a document arrives.
    private func photographEmptyWindow(_ fresh: EditorState, window size: CGSize?,
                                       name: String, number: Int) async throws {
        try await poll("the empty window", within: 5) { fresh.hostWindow != nil }
        guard let window = fresh.hostWindow else { throw Failure(description: "the empty window had no window") }
        if let size {
            let screen = window.screen ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1600, height: 1000)
            window.setFrame(NSRect(x: visible.minX + 40, y: visible.maxY - size.height - 40,
                                   width: size.width, height: size.height), display: true)
        }
        // The screen capture reads what the compositor has, so the window has
        // to have been drawn on screen at least once. It stays visible for this
        // one beat only, then goes invisible for the rest of the walk like
        // every other playtest window.
        await sleep(0.8)
        guard let content = window.contentView else { throw Failure(description: "the empty window has no content view") }
        try snapshot(content, name: name)
        await screenCapture(window, name: name)
        window.alphaValue = 0
        note(number, "blank", "\(name).png: the empty window's card")
    }

    /// Takes over a freshly filled editor: hides its window, sizes it, finds
    /// its canvas, and logs where the walk's coordinates live.
    private func adopt(_ opened: EditorState, window size: CGSize?,
                       step: String, subject: String, number: Int) async throws {
        try await poll("the editor's window", within: 5) { opened.hostWindow != nil }
        guard let window = opened.hostWindow else { throw Failure(description: "the editor lost its window") }
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
        note(number, step, "\(subject): document \(Int(documentSize.width))x\(Int(documentSize.height)) at pixelScale \(opened.document?.pixelScale ?? 0) (points are in these units); window \(Int(window.frame.width))x\(Int(window.frame.height)) pt; canvas \(Int(canvas?.bounds.width ?? 0))x\(Int(canvas?.bounds.height ?? 0)) pt; zoom \(String(format: "%.3f", opened.viewport?.zoom ?? 0))", state: describe())
    }

    // MARK: - Menus

    /// The app's own menu bar, exactly as it reads on screen.
    ///
    /// Everything here is about our OWN process, so it needs no privacy grant
    /// at all. Reading another app's menus would need Accessibility or Apple
    /// Events, which only a person can tick, and the probe is our app, so it
    /// never has to ask: it just says what is in its own menu bar.
    ///
    /// `update()` on every submenu first, because that is what runs validation.
    /// Without it an item that renames itself ("Show History" becoming "Hide
    /// History") reports whatever title it was last left with, which is exactly
    /// the sort of "verified" that is not.
    private func readMenuBar(only wanted: String?) throws -> [String: Any] {
        guard let bar = NSApp.mainMenu else { throw Failure(description: "the app has no menu bar yet") }
        bar.update()
        var top = bar.items
        if let wanted {
            // Exact title, then a prefix, then a mention: "Capture" is the
            // menu, and the app menu answers to "Photonz" whatever it is
            // suffixed with.
            guard let found = top.first(where: { $0.title == wanted })
                    ?? top.first(where: { $0.title.hasPrefix(wanted) })
                    ?? top.first(where: { $0.title.range(of: wanted, options: .caseInsensitive) != nil }) else {
                let names = top.map(\.title).joined(separator: ", ")
                throw Failure(description: "no menu called \"\(wanted)\"; the menu bar has: \(names)")
            }
            top = [found]
        }
        // Whether the reading of what is DIMMED can be trusted. A walk never
        // brings the probe to the front, because an unmanned loop that steals
        // focus from whoever is working is worse than a menu reading that
        // admits its limits, and macOS refuses a background app the activation
        // anyway. With nothing focused, SwiftUI's window-scoped commands all
        // report themselves disabled, so the step says so instead of pretending.
        let focus = NSApp.keyWindow.map { $0.title.isEmpty ? "an untitled window" : $0.title }
        // The open windows come along because half of what a menu title says
        // depends on them ("Show History" versus "Hide History"), and a reader
        // who cannot see the screen otherwise has no way to tell.
        let windows = NSApp.windows.filter(\.isVisible).map { window -> [String: Any] in
            ["title": window.title.isEmpty ? "(untitled)" : window.title,
             "key": window.isKeyWindow, "panel": window is NSPanel]
        }
        return [
            "menus": top.map { Self.describe(item: $0, depth: 0) },
            "focused": focus != nil,
            "focus": focus ?? NSNull(),
            "windows": windows,
        ]
    }

    /// A menu item found by the chord it carries, and the path a person would
    /// read to it ("Edit ▸ Undo").
    struct MenuDestination {
        let item: NSMenuItem
        let path: String
    }

    /// The chord as a person reads it in a script: "command+shift+z".
    private static func chord(_ key: PlaytestKey, _ modifiers: [PlaytestModifier]) -> String {
        (modifiers.map(\.rawValue) + [key.name]).joined(separator: "+")
    }

    /// The one menu item bound to this chord, wherever it is in the bar.
    ///
    /// `update()` runs on every menu on the way down, because that is what
    /// runs validation: without it `isEnabled` reports whatever the item was
    /// left with, and the dimmed check below would be worthless.
    static func menuItem(carrying key: PlaytestKey, modifiers: [PlaytestModifier]) -> MenuDestination? {
        guard let bar = NSApp.mainMenu else { return nil }
        bar.update()
        var wanted = NSEvent.ModifierFlags()
        for modifier in modifiers {
            switch modifier {
            case .command: wanted.insert(.command)
            case .shift: wanted.insert(.shift)
            case .option: wanted.insert(.option)
            case .control: wanted.insert(.control)
            }
        }
        return find(chord: key.characters, flags: wanted, in: bar, path: [], depth: 0)
    }

    private static func find(chord: String, flags: NSEvent.ModifierFlags,
                             in menu: NSMenu, path: [String], depth: Int) -> MenuDestination? {
        for item in menu.items where !item.isSeparatorItem && !item.isHidden {
            if !item.keyEquivalent.isEmpty,
               item.keyEquivalent.lowercased() == chord.lowercased(),
               effectiveFlags(of: item) == flags.intersection([.command, .shift, .option, .control]) {
                return MenuDestination(item: item, path: (path + [item.title]).joined(separator: " ▸ "))
            }
            if let submenu = item.submenu, depth < 4 {
                submenu.update()
                if let found = find(chord: chord, flags: flags, in: submenu,
                                    path: path + [item.title], depth: depth + 1) {
                    return found
                }
            }
        }
        return nil
    }

    /// Why a walk cannot press most of the menu bar, in one sentence a log
    /// line can carry.
    ///
    /// macOS will not let a script-launched background process take focus:
    /// `NSApp.activate(ignoringOtherApps:)`, `makeKeyAndOrderFront` and
    /// `becomeKey()` were each tried on 2026-09-03 and each left `isActive`
    /// and `keyWindow` exactly as they were, with the window visible and with
    /// it hidden. With no focus event ever arriving, SwiftUI never
    /// re-evaluates the `Commands` body: the menu bar stays frozen at the
    /// state it was built in at launch, when no editor existed. Every
    /// window-scoped item is therefore dimmed with a nil target and a nil
    /// action for the whole walk, and forcing `isEnabled` back on does not
    /// help — there is nothing behind the item to run. Proven by printing the
    /// live values into the Undo item's own title mid-walk, which came back
    /// reading the launch-time values.
    ///
    /// App-level commands (Capture, New Window, Open) are built live and stay
    /// live, so those shortcuts a walk really can press.
    static let frozenMenuBar =
        "macOS will not give a background app focus, so SwiftUI leaves the probe's menu bar frozen at its launch state: "
        + "every window-scoped command is dimmed and empty for the whole walk, however the document changes."

    /// What a person has to hold down for this item.    /// What a person has to hold down for this item. AppKit spells ⇧⌘Z two
    /// ways — an uppercase "Z" with ⌘, or a lowercase "z" with ⇧⌘ — and a
    /// lookup that knew only one of them would miss half the menu bar.
    private static func effectiveFlags(of item: NSMenuItem) -> NSEvent.ModifierFlags {
        var flags = item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control])
        if let character = item.keyEquivalent.first, character.isUppercase { flags.insert(.shift) }
        return flags
    }

    /// One item and, when it has one, its whole submenu. Depth is capped so a
    /// menu that somehow refers to itself cannot spin.
    private static func describe(item: NSMenuItem, depth: Int) -> [String: Any] {
        if item.isSeparatorItem { return ["separator": true] }
        var entry: [String: Any] = ["title": item.title, "enabled": item.isEnabled]
        if let shortcut = shortcut(for: item) { entry["shortcut"] = shortcut }
        if item.isHidden { entry["hidden"] = true }
        switch item.state {
        case .on: entry["state"] = "on"
        case .mixed: entry["state"] = "mixed"
        default: break
        }
        if let submenu = item.submenu, depth < 4 {
            submenu.update()
            entry["items"] = submenu.items.map { describe(item: $0, depth: depth + 1) }
        }
        return entry
    }

    /// The chord as a person reads it on the menu: ⇧⌘4, not "4" plus a mask.
    private static func shortcut(for item: NSMenuItem) -> String? {
        guard !item.keyEquivalent.isEmpty else { return nil }
        let flags = item.keyEquivalentModifierMask
        var chord = ""
        if flags.contains(.control) { chord += "⌃" }
        if flags.contains(.option) { chord += "⌥" }
        if flags.contains(.shift) { chord += "⇧" }
        if flags.contains(.command) { chord += "⌘" }
        let names: [String: String] = [
            "\u{8}": "⌫", "\u{7F}": "⌦", "\r": "↩", "\t": "⇥", " ": "Space", "\u{1B}": "⎋",
            "\u{F700}": "↑", "\u{F701}": "↓", "\u{F702}": "←", "\u{F703}": "→",
        ]
        return chord + (names[item.keyEquivalent] ?? item.keyEquivalent.uppercased())
    }

    /// The same tree as indented plain text, so the log line is readable
    /// without opening the JSON.
    private static func outline(_ items: [[String: Any]], dimming: Bool, indent: String = "  ") -> String {
        items.map { entry -> String in
            if entry["separator"] as? Bool == true { return indent + "---" }
            var line = indent + (entry["title"] as? String ?? "?")
            if let shortcut = entry["shortcut"] as? String { line += "  \(shortcut)" }
            if dimming, entry["enabled"] as? Bool == false { line += "  (dimmed)" }
            if let state = entry["state"] as? String { line += "  (\(state))" }
            if entry["hidden"] as? Bool == true { line += "  (hidden)" }
            if let children = entry["items"] as? [[String: Any]], !children.isEmpty {
                line += "\n" + outline(children, dimming: dimming, indent: indent + "  ")
            }
            return line
        }.joined(separator: "\n")
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

    /// The same point in DOCUMENT coordinates, which is the space a drop
    /// lands in.
    private func documentPoint(_ at: PlaytestPoint) throws -> CGPoint {
        switch at.space {
        case .document:
            return at.point
        case .view:
            guard let viewport = try requireEditor().viewport else { throw Failure(description: "the editor has no viewport yet") }
            return viewport.documentPoint(fromView: at.point)
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
            } else {
                // Nothing claimed it as a shortcut, so it is an ordinary press
                // that happens to carry a modifier: ⇧↑ stepping a number field,
                // ⇧⌫, ⌥ plus a letter. AppKit walks the responder chain with
                // those after the key equivalents miss, and so must this, or the
                // press would silently vanish and a walk would "prove" a feature
                // broken that works by hand.
                window.sendEvent(event)
                takenBy = "responder chain"
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
                // The attachment too: the point the bubble hangs from, which a
                // walk can watch stay put while the caption gets longer.
                let hang = annotation.captionAttachment()
                let attachment = CGPoint(x: layer.frame.minX + hang.x, y: layer.frame.minY + hang.y)
                line += " pill \(short(center)) hangs \(short(attachment))"
                line += annotation.captionPinned ? " pinned" : ""
            }
            return line
        }
        // One line per color row the SELECTION has: the slot, what the picked
        // layers are painted, and the style painting them. With several picked
        // this is what proves one pick reached all of them, and it prints the
        // same word the row does when they disagree.
        let selectedColors: [String] = {
            guard let document = editor.document else { return [] }
            return editor.colorStyleSlots.map { slot in
                let selection = editor.colorStyleSelection(slot: slot)
                let body: String
                switch selection.reading {
                case .empty: body = "none"
                case .mixed: body = ColorStyleSelection.mixedText.lowercased()
                case .color(let hex): body = hex
                case .style(let id):
                    let name = document.colorStyle(id: id)?.name ?? "?"
                    body = "\(selection.members.first?.colorHex ?? "?") · style \(name)"
                }
                return "\(slot.rawValue) \(body) ×\(selection.count)"
            }
        }()
        // The layer tree in CANVAS coordinates, one line per layer, indented by
        // how deep it sits. This is what a walk reads to prove a group carried
        // — or scaled — everything inside it, in the same units its clicks are
        // written in.
        var tree: [String] = []
        func walk(_ list: [Layer], origin: CGPoint, depth: Int) {
            for layer in list {
                let box = layer.localBounds.offsetBy(dx: origin.x, dy: origin.y)
                let kind: String
                switch layer.content {
                case .image: kind = "image"
                case .text: kind = "text"
                case .annotation(let a): kind = "\(a.shape)"
                case .zoomCallout: kind = "callout"
                case .measure: kind = "measure"
                case .collage: kind = "collage"
                case .group(let g): kind = g.isFrame ? "frame" : (g.instanceOf != nil ? "copy" : "group")
                }
                var line = String(repeating: "  ", count: depth)
                line += "\(layer.name) [\(kind)] \(box.integral)"
                if case .text(let content) = layer.content { line += " \(Int(content.fontSize))pt" }
                if let annotation = layer.annotation {
                    line += " stroke \(Int(annotation.strokeWidth.rounded()))"
                }
                tree.append(line)
                let inner = CGPoint(x: origin.x + layer.frame.origin.x,
                                    y: origin.y + layer.frame.origin.y)
                walk(layer.children, origin: inner, depth: depth + 1)
            }
        }
        walk(layers, origin: .zero, depth: 0)
        return [
            "tool": editor.activeTool.rawValue,
            "tree": tree,
            // The floating bar's measured width, so a walk can prove a
            // change made it narrower rather than eyeballing a snapshot.
            "toolBarWidth": editor.toolBarWidth,
            "measureMode": editor.measureToolMode.rawValue,
            "hint": editor.showsMeasureHint ? "\(editor.measureHintTitle ?? "") · \(editor.measureHintText)" : "none",
            "copied": editor.copyConfirmation.map { "\($0.title) · \($0.detail)" } ?? "none",
            "layers": layers.count,
            // Whether Undo and Redo have anything to do, which is what the
            // Edit menu dims itself on and what a shortcut walk checks.
            "canUndo": editor.canUndo,
            "canRedo": editor.canRedo,
            // Whether this process has focus at all. It never does in a walk,
            // and that one fact is why most menu shortcuts cannot be pressed
            // in one. See `frozenMenuBar`.
            "appActive": NSApp.isActive,
            // The canvas's own size, so a walk can prove a number typed into
            // the Canvas section landed on the document rather than nowhere.
            "canvas": document.map { "\(Int($0.canvasSize.width))x\(Int($0.canvasSize.height))" } ?? "none",
            "measures": measures,
            "arrows": arrows,
            "selected": editor.selectedLayerID?.uuidString ?? "nil",
            // Everything the Layers menu would act on, by name and in draw
            // order: one layer clicked, several ⇧-clicked, or a whole sweep.
            // This is what a walk reads to prove a ⇧-click added rather than
            // replaced.
            "selection": {
                let picked = editor.actionableLayerIDs
                return (editor.document?.allLayers ?? [])
                    .filter { picked.contains($0.id) }.map(\.name)
            }(),
            // The group you are inside, nil out on the canvas.
            "insideGroup": editor.groupContextID
                .flatMap { editor.document?.layer(id: $0)?.name } ?? "nil",
            // Whether Layer ▸ Group would do anything, which is exactly what
            // that menu row dims itself on.
            "canGroup": editor.canGroupSelection,
            // Whether the Arrange row is on screen. The inspector section reads
            // this same value, so a walk can prove the row arrived with the
            // second layer without measuring pixels in a snapshot.
            "canAlign": editor.canAlignSelection,
            // What the Arrange row says it is lining up against: a frame's
            // name for one layer inside a frame, "selection" when the layers
            // answer to each other. The caption and every hover tip read this
            // same value.
            "alignsTo": editor.arrangeReferenceName ?? "selection",
            // Whether Layer ▸ Make Alternatives is there at all. That row is
            // absent rather than dimmed, and a walk cannot photograph an absent
            // row: the probe never comes to the front, so its menu bar reads
            // frozen. This is the same value the row's own `if` reads.
            "canMakeChoice": editor.canMakeChoice,
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
            // The named colors in the document, and what each one paints, so a
            // walk can prove an edit to a style reached everything wearing it.
            "styles": (editor.document?.colorStyles ?? []).map {
                "\($0.name) \($0.colorHex) · \(editor.colorStyleUsageCount(styleID: $0.id)) used"
            },
            // What the selected layer's colors are, and where each came from.
            "selectedColors": selectedColors,
            // The rows the Color section is showing, by their labels, in order.
            // One layer picked or several, this is the SAME list for the same
            // kinds of layer, which is how a walk proves a color did not move
            // house when a second layer joined the selection.
            "colorRows": editor.colorRowSlots.map(\.selectionTitle),
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
