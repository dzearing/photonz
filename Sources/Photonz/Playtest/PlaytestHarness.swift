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
    static var readyEditors: [EditorState] {
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
    /// A colour drag left down by `holdColorDrag`, waiting for the release that
    /// turns its live frames into one recorded step.
    private var heldColorDrag: (slot: ColorSlot, paint: Paint)?
    /// Anything the action that just ran wants said in the log beside its name.
    private var actionDetail: String?
    /// The walk's `setup` block, carried out before step one and undone when
    /// the run ends however it ends.
    private var setupRunner = PlaytestSetupRunner()

    /// How a `wait` step spends its seconds: watching for the editor to go
    /// quiet, or sleeping the whole number the way walks used to.
    /// `PHOTONZ_PLAYTEST_PACE=full` puts every wait back on the clock, which is
    /// how a walk that has turned flaky says whether the pacing is what moved
    /// under it.
    private let pace = PlaytestSettle.named(ProcessInfo.processInfo.environment["PHOTONZ_PLAYTEST_PACE"])
    /// Seconds of sleeping the watched waits gave back over this walk, so the
    /// saving is on the record rather than inferred from a stopwatch.
    private var pacedAway: Double = 0

    init(scriptURL: URL, coordinator: AppCoordinator) {
        self.scriptURL = scriptURL
        self.coordinator = coordinator
        self.out = scriptURL.deletingLastPathComponent().appendingPathComponent("out")
    }

    func start() async {
        // Where to write is settled from the raw file FIRST, so a script that
        // does not parse still reports why in the folder the launcher is
        // watching. Resolving it after decoding meant a single typo left the
        // launcher waiting out its whole timeout on an empty folder while the
        // explanation sat in a default folder beside the script.
        let data = try? Data(contentsOf: scriptURL)
        out = PlaytestScript.outputDirectory(besides: scriptURL, in: data ?? Data())
        prepareOutput()
        let script: PlaytestScript
        do {
            guard let data else { throw Failure(description: "could not read \(scriptURL.path)") }
            script = try PlaytestScript.decode(data)
        } catch {
            finish(status: "failed", steps: 0, error: "\(error)")
            return
        }
        note(0, "start", "script \(scriptURL.path); \(script.steps.count) steps; release \(Experiments.shared.release.rawValue)")
        // Whatever the walk said it needs, before step one — and, however this
        // run ends, everything it borrowed goes back.
        do {
            let said = try setupRunner.perform(script.setup, besides: scriptURL)
            note(0, "setup", said)
        } catch {
            finish(status: "failed", steps: 0, error: "setup: \(error)")
            return
        }
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
        let began = CACurrentMediaTime()
        defer { MainThreadMeter.shared.exclude(CACurrentMediaTime() - began) }
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
        // Anything the setup lent goes back first, so a walk that failed
        // halfway leaves nothing of its own in a person's Screenshots folder.
        if let returned = setupRunner.returnCaptures() { note(steps, "setup", returned) }
        if let cleared = setupRunner.clearScratch() { note(steps, "setup", cleared) }
        // Then every remembered setting, so the walk after this one starts from
        // the machine this one did rather than from whatever this one left.
        note(steps, "setup", setupRunner.restoreSettings())
        var done: [String: Any] = [
            "status": status, "steps": steps, "script": scriptURL.path, "out": out.path,
            "seconds": (Date().timeIntervalSince(startedAt) * 100).rounded() / 100,
            // Sleeping the walk asked for and did not need, because the editor
            // had already finished. Worth having on the record: it is the
            // difference between this walk and the same walk under
            // PHOTONZ_PLAYTEST_PACE=full.
            "secondsSaved": (pacedAway * 100).rounded() / 100,
        ]
        if let error { done["error"] = error }
        note(steps, "done", status == "ok" ? "walk complete" : (error ?? status))
        write(json: done, to: "done.json")
    }

    /// Where a walk's file lives: its own scratch folder when the path starts
    /// with "scratch/", an absolute path as given, and anything else beside the
    /// script, so a walk travels with its fixtures.
    private func fileURL(_ file: String) throws -> URL {
        if file.hasPrefix("scratch/") {
            guard let folder = setupRunner.scratchDirectory else {
                throw Failure(description: "\"\(file)\" names the walk's own folder, and this walk never asked "
                    + "for one; add \"scratch\" to its setup block naming the files it wants a copy of")
            }
            return folder.appendingPathComponent(String(file.dropFirst("scratch/".count)))
        }
        return file.hasPrefix("/")
            ? URL(fileURLWithPath: file)
            : scriptURL.deletingLastPathComponent().appendingPathComponent(file).standardizedFileURL
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
            let url = try fileURL(file)
            try await open(url, size: size, number: number)

        case .wait(let seconds):
            let said = await settle(for: seconds)
            note(number, step.name, "\(said); \(MainThreadMeter.shared.report)")

        case .key(let key, let modifiers):
            // A sheet is a window of its own sitting on the editor's, and it is
            // the one holding the keyboard while it is up: a person answering
            // "Turn this shape into a picture?" with ⏎ is pressing the sheet's
            // default button, not typing at the canvas. Sending the press to
            // the editor instead did nothing at all, so a walk could raise a
            // question, "answer" it, and carry on reporting passes over a
            // document that never changed. Found on 2026-09-08.
            let window = try keyTarget()
            // Look the item up BEFORE the press: after it, an item that has
            // just been ticked or unticked reports its new state and the log
            // describes the wrong thing.
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

        case .shortcut(let key, let modifiers, let wanted, let checked):
            let window = try requireWindow()
            let chord = Self.chord(key, modifiers)
            guard let destination = Self.menuItem(carrying: key, modifiers: modifiers) else {
                throw Failure(description: "no menu item carries \(chord); a `menus` step lists every shortcut the app has")
            }
            let title = destination.item.title
            if let wanted, title.caseInsensitiveCompare(wanted) != .orderedSame {
                throw Failure(description: "\(chord) is \(destination.path), not \"\(wanted)\"")
            }
            // A setting's item never renames itself, so its checkmark is the
            // whole reading. Checked BEFORE the press, since that is the state
            // a person would see when they went looking for the item.
            if let checked {
                let isOn = destination.item.state == .on
                guard isOn == checked else {
                    throw Failure(description: "\(destination.path) is \(isOn ? "ticked" : "not ticked") "
                        + "and it should be \(checked ? "ticked" : "not ticked") before \(chord)")
                }
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

        case .appKey(let key, let modifiers):
            // Handed to the application, not posted into the window, because an
            // application-wide event monitor is the only thing that sees a
            // press this way — and that is what takes the history overlay down
            // on Esc or on a click outside it.
            let window = try requireWindow()
            let flags = eventFlags(modifiers)
            for down in [true, false] {
                guard let event = keyEvent(key, flags: flags, down: down, in: window) else { continue }
                NSApp.sendEvent(event)
            }
            await sleep(0.2)
            note(number, step.name, "\(Self.chord(key, modifiers)) sent through the app",
                 state: describe())

        case .move(let at, let modifiers):
            let canvas = try requireCanvas()
            let p = try viewPoint(at)
            // The canvas learns about held modifiers from `flagsChanged`, not
            // from the mouse event, so a walk that wants ⌥ held while the
            // pointer rests has to put it where the real key would have left
            // it. Setting it here and letting `mouseMoved` read it lands the
            // canvas in the same state a person holding ⌥ would.
            let flags = eventFlags(modifiers)
            canvas.pointerModifiers = flags
            if let event = mouseEvent(.mouseMoved, at: p, on: canvas, flags: flags) {
                canvas.mouseMoved(with: event)
            }
            await sleep(0.05)
            let held = modifiers.isEmpty ? "" : " holding " + modifiers.map(\.rawValue).joined(separator: "+")
            note(number, step.name, "to \(short(at.point)) \(at.space.rawValue) = view \(short(p))" + held)

        case .pinch(let to, let steps):
            let canvas = try requireCanvas()
            guard let start = canvas.viewport?.zoom, start > 0 else {
                throw Failure(description: "the canvas has no viewport to pinch")
            }
            // A trackpad moves the zoom by a small FRACTION per event, so the
            // walk does too: the same ratio every nudge, which is what makes
            // the nudges even on the screen rather than even in the numbers.
            let anchor = CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY)
            let ratio = pow(Double(to / start), 1.0 / Double(steps))
            var dark: [String] = []
            var reports: [String] = []
            for _ in 0..<steps {
                canvas.pinch(magnification: CGFloat(ratio - 1), anchorInView: anchor)
                // What is on the screen at THIS instant, before the run loop
                // gets a turn to put anything back. A grid that only goes out
                // between the gesture and the next redraw is still a grid that
                // goes out, and this is the only place it can be seen.
                let report = canvas.playtestGridReport
                reports.append(report)
                if !canvas.playtestGridIsVisible { dark.append(report) }
                await sleep(0.016)
            }
            let landed = canvas.viewport?.zoom ?? 0
            let verdict = dark.isEmpty
                ? "the grid was drawn at every one"
                : "THE GRID WENT OUT at \(dark.count) of \(steps): \(dark.prefix(4).joined(separator: " | "))"
            note(number, step.name,
                 "pinched from \(String(format: "%.4f", Double(start))) to "
                 + "\(String(format: "%.4f", Double(landed))) in \(steps) nudges; \(verdict)",
                 state: describe(extra: ["gridDuringPinch": reports]))

        case .hover(let target, let wanted):
            // `window` reaches a panel of the app's own that is not the editor
            // — the capture history is one — so its controls can be rested on
            // exactly as the tool bar's are.
            let window = try wanted.map { try requireWindow(titled: $0) } ?? (try requireWindow())
            guard let content = window.contentView else { throw Failure(description: "the window has no content view") }
            // The title bar's own controls answer a hover too.
            let anchors = Self.findAll(HintAnchorView.self, in: content)
                + Self.findAllInTitlebar(HintAnchorView.self, of: window)
            let anchor: HintAnchorView?
            let location: CGPoint
            let place: String
            switch target {
            case .label(let text):
                // The exact label first, then one that starts with the text,
                // then one that mentions it: "Rectangle" is the shape, not
                // Rectangle Select; "Panel" is the title bar toggle in either
                // state, since its tooltip flips between Show and Hide.
                guard let found = anchors.first(where: { $0.label == text })
                        ?? anchors.first(where: { $0.label.hasPrefix(text) })
                        ?? anchors.first(where: { $0.label.range(of: text, options: .caseInsensitive) != nil }) else {
                    let names = anchors.map(\.label).sorted().joined(separator: ", ")
                    let whose = wanted.map { " in \"\($0)\"" } ?? ""
                    throw Failure(description: "no control with a tooltip starting \"\(text)\"\(whose); on screen: "
                        + (names.isEmpty ? "none" : names))
                }
                anchor = found
                location = found.convert(CGPoint(x: found.bounds.midX, y: found.bounds.midY), to: nil)
                place = "\"\(text)\""
            case .point(let at):
                if wanted != nil {
                    // No canvas in another window, so a point there is in that
                    // window's own space, measured down from its top-left.
                    let y = content.isFlipped ? at.point.y : content.bounds.height - at.point.y
                    location = content.convert(CGPoint(x: at.point.x, y: y), to: nil)
                } else {
                    location = try requireCanvas().convert(try viewPoint(at), to: nil)
                }
                anchor = anchors.first { $0.convert($0.bounds, to: nil).contains(location) }
                place = "\(short(at.point)) \(wanted == nil ? at.space.rawValue : "window")"
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
            MainThreadMeter.shared.install()
            MainThreadMeter.shared.reset()
            ViewBuildMeter.shared.reset()
            // A click a person makes lands on whatever view is under the
            // pointer. Nearly always that is the canvas, but while an inline
            // text field is open it is the FIELD, and a click inside the words
            // puts the caret where it landed. Handing that click to the canvas
            // instead would commit the edit, which is not what the same click
            // does in the app.
            let target = canvas.superview.flatMap { canvas.hitTest(canvas.convert(p, to: $0)) } ?? canvas
            let t0 = CACurrentMediaTime()
            if target === canvas {
                if let event = mouseEvent(.leftMouseDown, at: p, on: canvas, flags: flags, clicks: count) { canvas.mouseDown(with: event) }
            } else {
                // A text field tracks the drag itself and does not return
                // until the button comes up, so the release is put in the
                // queue before the press is delivered.
                if let event = mouseEvent(.leftMouseUp, at: p, on: canvas, flags: flags, clicks: count) {
                    NSApp.postEvent(event, atStart: false)
                }
                if let event = mouseEvent(.leftMouseDown, at: p, on: canvas, flags: flags, clicks: count) {
                    target.mouseDown(with: event)
                }
            }
            let t1 = CACurrentMediaTime()
            if target === canvas,
               let event = mouseEvent(.leftMouseUp, at: p, on: canvas, flags: flags, clicks: count) { canvas.mouseUp(with: event) }
            let t2 = CACurrentMediaTime()
            await sleep(0.05)
            let timing = (target === canvas ? "" : "landed on the open text field; ")
                + String(format: "handler down %.1fms up %.1fms; ", (t1 - t0) * 1000, (t2 - t1) * 1000)
                + MainThreadMeter.shared.report + "; " + ViewBuildMeter.shared.report
            note(number, step.name, "at \(short(at.point)) \(at.space.rawValue) = view \(short(p)) \(timing)", state: describe())

        case .drag(let from, let to, let steps, let modifiers, let halfway, let hold, let wobble):
            let canvas = try requireCanvas()
            let a = try viewPoint(from), b = try viewPoint(to)
            let flags = eventFlags(modifiers)
            // A key pressed or let go of with the button still down. The press
            // and the first half of the travel carry `modifiers`, the second
            // half carries `halfway`, and the release carries whatever was in
            // force at the end — which is how a hand actually uses a live
            // constraint like ⇧.
            let laterFlags = halfway.map { eventFlags($0) } ?? flags
            // A hand is not a ruler: `wobble` shakes the pointer as it travels,
            // mostly BACK AND FORTH ALONG the line it is walking, which is the
            // tremor a magnet's reach actually chatters on, plus half as much
            // sideways. The guides are read after every single move, so a walk
            // can say how often a snap was taken and given back rather than
            // only where the drag ended up.
            let length = max(hypot(b.x - a.x, b.y - a.y), 0.0001)
            let along = CGPoint(x: (b.x - a.x) / length, y: (b.y - a.y) / length)
            let across = CGPoint(x: -along.y, y: along.x)
            let shake: [CGFloat] = [0, 1, -0.7, 0.4, -0.3, 0.9, -0.9, 0.2]
            var guides = SnapGuideTally()
            // The grid line the drag is standing on, read the same way: which
            // lines it stepped through, and which one it was on at the end.
            var gridLines = SnapGuideTally(label: "grid lines")
            if let event = mouseEvent(.leftMouseDown, at: a, on: canvas, flags: flags) { canvas.mouseDown(with: event) }
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let shiver = wobble * shake[i % shake.count]
                let sway = wobble * shake[(i + 3) % shake.count] / 2
                let p = CGPoint(x: a.x + (b.x - a.x) * t + along.x * shiver + across.x * sway,
                                y: a.y + (b.y - a.y) * t + along.y * shiver + across.y * sway)
                let moveFlags = t > 0.5 ? laterFlags : flags
                if let event = mouseEvent(.leftMouseDragged, at: p, on: canvas, flags: moveFlags) { canvas.mouseDragged(with: event) }
                guides.record(canvas.liveSnapGuides)
                gridLines.record(canvas.liveGridSnapLines)
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
            if let event = mouseEvent(.leftMouseUp, at: b, on: canvas, flags: laterFlags) { canvas.mouseUp(with: event) }
            await sleep(0.05)
            var keys = ""
            if let later = halfway {
                func spell(_ list: [PlaytestModifier]) -> String {
                    let names: [String] = list.map { $0.rawValue }
                    return names.isEmpty ? "none" : names.joined(separator: "+")
                }
                keys = ", keys " + spell(modifiers) + " then " + spell(later)
            }
            note(number, step.name,
                 "\(short(from.point)) to \(short(to.point)) \(from.space.rawValue)\(held)\(keys), "
                     + "cursor while down \(heldCursor), \(guides.reading), \(gridLines.reading)",
                 state: describe())

        case .type(let text):
            // Whichever of the editor's surfaces holds the keyboard: a popover
            // is a window of its own, so the field a `focus` step just took
            // hold of is not always in the editor window.
            let windows = try panelWindows()
            guard let field = windows.compactMap({ $0.firstResponder as? NSTextView }).first else {
                let responder = windows
                    .map { $0.firstResponder.map { String(describing: type(of: $0)) } ?? "nil" }
                    .joined(separator: ", ")
                throw Failure(description: "no text field has the keyboard (first responder is \(responder))")
            }
            field.insertText(text, replacementRange: field.selectedRange())
            await sleep(0.05)
            note(number, step.name, "\"\(text)\" into \(type(of: field))")

        case .focus(let name):
            // The editor window AND whatever is open above it. A number that
            // lives in a popover — the grid's spacing, since its settings moved
            // out of the panel — is in a window of its own, and a walk that
            // only ever looked at the editor could photograph that field
            // forever without typing into it.
            let windows = try panelWindows()
            let fields = windows.flatMap { window in
                window.contentView.map { Self.findAll(NSTextField.self, in: $0) } ?? []
            }
            .filter { $0.isEditable && !$0.isHiddenOrHasHiddenAncestor }
            // Either word finds it. A field usually shows its own name when it
            // is empty, so the placeholder is the word on screen; a field that
            // stands in for something else while it has no number to show
            // ("Mixed") would otherwise stop answering to its own name.
            func labels(_ field: NSTextField) -> [String] {
                [field.placeholderString, field.accessibilityLabel()].compactMap { $0 }
            }
            func label(_ field: NSTextField) -> String { labels(field).first ?? "" }
            guard let match = fields.first(where: { field in
                labels(field).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            }) else {
                let seen = fields.map(label).filter { !$0.isEmpty }
                throw Failure(description: "no editable field labelled \"\(name)\" is on screen; the ones that are: \(seen.isEmpty ? "none" : seen.joined(separator: ", "))")
            }
            // The field's OWN window: a popover takes the keyboard for itself,
            // and asking the editor to make a field in another window first
            // responder does nothing at all.
            guard let window = match.window else {
                throw Failure(description: "the field labelled \"\(name)\" is in no window")
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
            // Whatever the shelf tile is set to hand over, so a walk drags the
            // version a person would be dragging (`ComponentVersions`).
            let version = editor?.shelfComponentVersion(of: componentID)?.id
            let operation = canvas.trackComponentDrag(componentID, version: version, atViewPoint: p)
            await sleep(0.15)
            let landing = canvas.dropLandingDescription
            let answer = operation.contains(.copy) ? "would place a copy" : "refused"
            let where_ = landing.map { "box \(short($0.rect.origin)) \(short(CGPoint(x: $0.rect.width, y: $0.rect.height)))"
                                       + ($0.host.flatMap { id in editor?.document?.layer(id: id)?.name }
                                        .map { ", joining \($0)" } ?? ", loose on the canvas") } ?? "nothing shown"
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
            let version = editor?.shelfComponentVersion(of: componentID)?.id
            let board = NSPasteboard(name: NSPasteboard.Name("photonz.playtest.componentDrag"))
            board.clearContents()
            board.setData(ComponentDrag.data(componentID: componentID, version: version),
                          forType: ComponentDrag.pasteboardType)
            guard ComponentDrag.payload(on: board)
                    == ComponentDrag.Payload(componentID: componentID, version: version) else {
                throw Failure(description: "the component drag payload did not survive the pasteboard")
            }
            let p = try viewPoint(at)
            guard canvas.dropComponent(componentID, version: version, atViewPoint: p) else {
                throw Failure(description: "the canvas refused the component drop")
            }
            await sleep(0.2)
            note(number, step.name, "at \(short(at.point)) \(at.space.rawValue) = view \(short(p))",
                 state: describe())

        case .dropImage(let file, let at, let hold):
            // Through the canvas's own drag destination, carrying the file the
            // way the Finder carries it, so a walk lands a Finder drop on the
            // very calls a pointer makes — the same ones a tile off the Library
            // shelf arrives on.
            let canvas = try requireCanvas()
            let window = try requireWindow()
            let url = try fileURL(file)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw Failure(description: "there is no file at \(url.path) to drop")
            }
            guard let provider = NSItemProvider(contentsOf: url) else {
                throw Failure(description: "\(url.lastPathComponent) cannot be carried on a drag")
            }
            let board = try await PlaytestPanelDrag.pasteboard(from: provider, named: "file")
            let viewPoint = try self.viewPoint(at)
            let info = PlaytestDraggingInfo(pasteboard: board,
                                            location: canvas.convert(viewPoint, to: nil),
                                            window: window)
            guard canvas.draggingEntered(info) != [] else {
                throw Failure(description: "the canvas refused the file \(url.lastPathComponent)")
            }
            // A few frames of hovering, so the landing outline the canvas
            // draws while the file is in the air is on screen and settled
            // before the picture.
            for _ in 0..<3 {
                _ = canvas.draggingUpdated(info)
                await sleep(0.05)
            }
            var held = ""
            if let hold, let content = window.contentView {
                try snapshot(content, name: hold)
                await screenCapture(window, name: hold)
                let landing = canvas.dropLandingDescription
                held = ", held \(hold).png showing "
                    + (landing.map { "box \(short($0.rect.origin)) \(short(CGPoint(x: $0.rect.width, y: $0.rect.height)))"
                                     + ($0.host.flatMap { id in editor?.document?.layer(id: id)?.name }
                                        .map { ", joining \($0)" } ?? ", loose on the canvas") }
                       ?? "no landing box")
            }
            guard canvas.performDragOperation(info) else {
                throw Failure(description: "the canvas would not take the file \(url.lastPathComponent)")
            }
            await sleep(0.3)
            note(number, step.name,
                 "\(url.lastPathComponent) let go at \(short(at.point)) \(at.space.rawValue) = view \(short(viewPoint))\(held)",
                 state: describe())

        case .dragFile(let file, let at, let hold, let release, let leave):
            // A file held over the canvas with the button still down, so the
            // step can write down the answer the pointer is showing. It is the
            // only way to record a refusal: letting go of a file the canvas
            // will not take does nothing at all, so `dropImage` can never see
            // one.
            let canvas = try requireCanvas()
            let window = try requireWindow()
            let url = try fileURL(file)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw Failure(description: "there is no file at \(url.path) to drag")
            }
            guard let provider = NSItemProvider(contentsOf: url) else {
                throw Failure(description: "\(url.lastPathComponent) cannot be carried on a drag")
            }
            let board = try await PlaytestPanelDrag.pasteboard(from: provider, named: "file")
            let windowPoint = try self.windowPoint(at)
            let info = PlaytestDraggingInfo(pasteboard: board,
                                            location: windowPoint,
                                            window: window)
            // Every destination the pointer's drag is offered to, not just the
            // canvas: a view that answers "none" hands the drag up to the view
            // holding it, so the pointer only says no once they ALL do.
            guard let content = window.contentView else {
                throw Failure(description: "the window has no content view")
            }
            let chain = PlaytestPanelDrag.destinations(at: windowPoint, in: content)
            var operation: NSDragOperation = []
            var answered = "nothing under the pointer takes drops"
            // A few frames of hovering, the way a pointer crossing the canvas
            // keeps asking, so the answer is the settled one.
            for round in 0..<4 {
                operation = []
                for view in chain {
                    let reply = round == 0 ? view.draggingEntered(info) : view.draggingUpdated(info)
                    if reply != [] {
                        operation = reply
                        answered = "\(type(of: view))"
                        break
                    }
                }
                await sleep(0.05)
            }
            let landing = canvas.dropLandingDescription
            // What the RIGHT HAND PANEL is promising, read before the drag is
            // told to leave: the pointer's own sign lives in the window server
            // and cannot be photographed, so the panel's promise is the thing
            // a walk can actually write down.
            let promise = panelPromise()
            var held = ""
            if let hold, let content = window.contentView {
                try snapshot(content, name: hold)
                await screenCapture(window, name: hold)
                held = ", held \(hold).png"
            }
            // Letting go, when the walk asked for it: the drag goes down on the
            // very view that answered, so a step can prove a file the pointer
            // promised actually lands, not just that it was promised.
            var landed = ""
            if release, operation != [], let taker = chain.first(where: { $0.draggingUpdated(info) != [] }) {
                let took = taker.performDragOperation(info)
                await sleep(0.4)
                landed = took ? ", let go and \(type(of: taker)) took it" : ", let go and nothing took it"
            }
            // Walking away without a word, when the walk asked for it: no
            // destination is told the drag ended, which is what escape and a
            // release outside the window look like from in here. Whatever the
            // panel is wearing has to take itself off after that.
            if !leave { for view in chain { view.draggingExited(info) } }
            await sleep(leave ? PanelDropMarking.idleGrace + 0.5 : 0.1)
            let after = leave ? ", walked away without a word and then \(panelPromise())" : ""
            let answer = operation.contains(.copy)
                ? "would place a copy (\(answered) took it)"
                : "refused: the pointer shows the no-entry sign"
            let shown = landing.map { "box \(short($0.rect.origin)) \(short(CGPoint(x: $0.rect.width, y: $0.rect.height)))"
                                      + ($0.host.flatMap { id in editor?.document?.layer(id: id)?.name }
                                        .map { ", joining \($0)" } ?? ", loose on the canvas") }
                ?? "no landing box"
            note(number, step.name,
                 "\(url.lastPathComponent) held over \(short(at.point)) \(at.space.rawValue): \(answer), \(shown)"
                    + ", \(promise)"
                    + ", offered to \(chain.map { "\(type(of: $0))" }.joined(separator: " then "))\(held)\(landed)\(after)",
                 state: describe())

        case .snapshot(let name, let wanted):
            // A sheet is its own window on top of the editor's, so while one is
            // up it IS what a person is looking at, and it is what gets
            // photographed. `window` overrides that with any of the app's own
            // windows by title, which is the only way to photograph a floating
            // panel like the history overlay.
            let window = try wanted.map { try requireWindow(titled: $0) }
                ?? (try requireWindow().attachedSheet ?? (try requireWindow()))
            guard let content = window.contentView else { throw Failure(description: "the window has no content view") }
            try snapshot(content, name: name)
            await screenCapture(window, name: name)
            note(number, step.name, "\(name).png \(Int(content.bounds.width))x\(Int(content.bounds.height)) pt")

        case .render(let name, let scale):
            let editor = try requireEditor()
            guard let document = editor.document,
                  let image = DocumentRenderer().render(document, store: editor.store, scale: scale) else {
                throw Failure(description: "the document did not render")
            }
            try writePNG(image, name: name)
            note(number, step.name, "\(name).png \(image.width)x\(image.height) px at \(scale)x")

        case .panelMenu(let menu, let row, let shot, let choose, let clicking):
            try await openPanelMenu(menu, in: row, shot: shot, choose: choose, clicking: clicking,
                                    number: number)

        case .menuShot(let menu, let name, let ticked, let unticked):
            try await photographMenuBarMenu(menu, name: name, ticked: ticked,
                                            unticked: unticked, number: number)

        case .rightClick(let on, let shot, let choose, let ticked, let unticked):
            try await openRowMenu(on, shot: shot, choose: choose, ticked: ticked,
                                  unticked: unticked, number: number)

        case .dragOver(let carry, let at, let hold, let leave):
            try await dragOver(carry, at: at, hold: hold, leave: leave, number: number)

        case .dragTile(let tile, let to, let onto, let hold, let expect, let says):
            if let onto {
                try await dragTile(tile, ontoRow: onto, hold: hold, expect: expect, says: says,
                                   number: number)
            } else if let to {
                try await dragTile(tile, to: to, hold: hold, expect: expect, says: says,
                                   number: number)
            }

        case .dragRow(let row, let onto, let zone, let hold):
            try await dragRow(row, onto: onto, zone: zone, hold: hold, number: number)
        case .dragColor(let from, let onto, let hold, let expect):
            try await dragColor(from, onto: onto, hold: hold, expect: expect, number: number)

        case .selectRow(let row, let modifiers):
            let editor = try requireEditor()
            let rows = editor.layerRows
            guard let match = rows.first(where: { $0.name == row })
                    ?? rows.first(where: { $0.name.caseInsensitiveCompare(row) == .orderedSame }) else {
                let seen = rows.map(\.name).joined(separator: ", ")
                throw Failure(description: "no row called \"\(row)\" is in the layers list; the ones that are: "
                    + (seen.isEmpty ? "none" : seen))
            }
            let click: RowClick = if modifiers.contains(.shift) { .extend }
                else if modifiers.contains(.command) { .toggle } else { .plain }
            editor.clickRow(match.id, click, in: editor.panelRows.map(\.id))
            await sleep(0.2)
            note(number, step.name,
                 "picked \"\(match.name)\" out of the layers list"
                    + (match.isLocked ? " (locked)" : "")
                    + " with a \(click) click",
                 state: describe())

        case .press(let control, let row, let count, let modifiers, let across):
            try await pressControl(control, in: row, count: count, modifiers: modifiers,
                                   across: across, number: number)

        case .dragSection(let section, let past, let stop, let hold, let cancel):
            try await dragSection(section, past: past, stop: stop, hold: hold,
                                  cancel: cancel, number: number)

        case .dragHandle(let area, let by, let expect, let hold):
            try await dragHandle(area, by: by, expect: expect, hold: hold, number: number)

        case .panel(let stage):
            let inventory = try readPanel()
            write(json: inventory, to: "panel-\(stage).json")
            note(number, step.name, Self.outlinePanel(inventory), state: inventory)

        case .expect(let thing, let named, let inRow, let reads, let present):
            note(number, step.name,
                 try checkPanel(thing, named: named, inRow: inRow, reads: reads, present: present),
                 state: describe())

        case .expectPicked(let layers):
            note(number, step.name, try checkPicked(layers), state: describe())

        case .expectMeasures(let count):
            note(number, step.name, try checkMeasures(count), state: describe())

        case .expectSectionFits(let section):
            note(number, step.name, try checkSectionFits(section), state: describe())

        case .expectInView(let field, let whole):
            note(number, step.name, try checkInView(field, whole: whole), state: describe())

        case .expectOneUnit:
            note(number, step.name, try checkOneUnit(), state: describe())

        case .expectOneNumberPerName:
            note(number, step.name, try checkOneNumberPerName(), state: describe())

        case .scrollPanel(let row, let by):
            let rows = try panelTargets().filter { $0.kind == .row }
            let target: PanelTargetView
            if let row {
                target = try panelScrollTarget(row)
            } else if let any = rows.first {
                target = any
            } else {
                throw Failure(description: "there are no rows in the panel to scroll")
            }
            let before = rows.map(\.name)
            ViewBuildMeter.shared.reset()
            MainThreadMeter.shared.install()
            MainThreadMeter.shared.reset()
            let moved = try scroll(from: target, by: by)
            await sleep(0.4)
            let after = try panelTargets().filter { $0.kind == .row }.map(\.name)
            let arrived = after.filter { !before.contains($0) }
            note(number, step.name,
                 "from \"\(target.name)\" by \(Int(by))pt: \(moved); rows on screen \(before.count) -> \(after.count), "
                 + "new \(arrived.isEmpty ? "none" : arrived.joined(separator: ", "))"
                 + "; " + ViewBuildMeter.shared.report + "; " + MainThreadMeter.shared.report,
                 state: describe())

        case .reveal(let control, let inRow):
            try await reveal(control, in: inRow, number: number)

        case .toolBar(let stage):
            let row = Self.readToolBar()
            write(json: row, to: "toolbar-\(stage).json")
            note(number, step.name, Self.outlineToolBar(row), state: row)

        case .panelEdge(let stage):
            let edge = Self.readPanelEdge()
            write(json: edge, to: "panel-edge-\(stage).json")
            note(number, step.name, Self.outlinePanelEdge(edge), state: edge)

        case .panelStart(let stage):
            let start = Self.readPanelStart()
            write(json: start, to: "panel-start-\(stage).json")
            note(number, step.name, Self.outlinePanelStart(start), state: start)

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

        case .appearance(let which):
            // This app only. The machine's own setting is left alone, because a
            // walk that flipped the desktop to dark would flip it under whoever
            // is sitting at it.
            NSApp.appearance = switch which {
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            case .system: nil
            }
            await sleep(0.4)
            note(number, step.name, "drawing \(which.rawValue)", state: describe())

        case .menus(let stage, let menu):
            let tree = try readMenuBar(only: menu)
            write(json: tree, to: "menus-\(stage).json")
            let focused = tree["focused"] as? Bool ?? false
            let outline = Self.outline(tree["menus"] as? [[String: Any]] ?? [], dimming: focused)
            let heading = focused
                ? "\(tree["focus"] as? String ?? "a window") has focus; menu bar reads:"
                : "nothing in the probe has focus, so this menu bar is frozen at the state it was built in at launch: what is dimmed, and any checkmark on a window's own setting, is NOT what a person would see. Order, names and shortcuts are exact. Menu bar reads:"
            let open = (tree["windows"] as? [[String: Any]] ?? [])
                .map { $0["title"] as? String ?? "?" }.joined(separator: ", ")
            let reading = "\(heading)\n\(outline)\n  windows open: \(open)"
            // The same reading as a file you can just `cat`. The JSON is for a
            // program; nobody should have to unpick log.json to quote a menu.
            try? Data(reading.utf8).write(to: out.appendingPathComponent("menus-\(stage).txt"))
            note(number, step.name, reading, state: tree)

        case .action(let action) where action == .closeDocument:
            let closing = try requireWindow()
            closing.close()
            editor = nil
            window = nil
            canvas = nil
            hovered = nil
            await sleep(0.5)
            note(number, step.name, "closeDocument; \(PlaytestHarness.readyEditors.count) editor(s) still open",
                 state: describe())

        case .action(let action):
            let editor = try requireEditor()
            // Zeroed here so `showInspector` reports the cost of the panel
            // ARRIVING: the number of layer rows the list builds when it comes
            // back on screen, which is the thing a lazy list is claiming.
            ViewBuildMeter.shared.reset()
            switch action {
            case .copySpecList: editor.copyMeasureSpecList()
            case .copyImage: editor.copyCompositeToClipboard()
            case .copy: editor.copySelectedLayer()
            case .copyMerged: editor.copyMerged()
            case .cut: editor.cutSelectedLayer()
            case .hideAllMeasurements: editor.setAllMeasurementsVisible(false)
            case .showAllMeasurements: editor.setAllMeasurementsVisible(true)
            case .forgetThumbnails: editor.forgetLayerThumbnails()
            case .hideInspector: editor.setInspectorVisible(false)
            case .showInspector: editor.setInspectorVisible(true)
            case .toggleFullScreen:
                // A walk opens its window straight, without going through the
                // agent's own "a window is up now" hand-off, so the probe is
                // still a menu-bar accessory — and an accessory app is not
                // allowed full screen at all (its windows come back
                // `fullScreenNone`). Becoming regular first is exactly what
                // `AppCoordinator.openWindow` does for a person, so this is
                // the app as they have it, not a special case for the walk.
                NSApp.setActivationPolicy(.regular)
                // The window was BUILT while the app was still an accessory,
                // and AppKit stamps such a window `fullScreenNone` for life.
                // Putting it back to what a regular app's window is born with
                // is restoring the window a person has, not granting the walk
                // something the app cannot do.
                if let window = editor.hostWindow {
                    window.collectionBehavior.remove(.fullScreenNone)
                    window.collectionBehavior.insert(.fullScreenPrimary)
                    window.toggleFullScreen(nil)
                }
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
            case .deleteLayer:
                // Like Frame Selection above, this command can quietly do
                // nothing, and the log has to say which nothing it was: the
                // menu row was dimmed, or it ran and a locked member stayed.
                let dimmed = !editor.canDeleteSelectedLayers
                let picked = editor.actionableLayerIDs
                let before = editor.document?.flattenedLayers.count ?? 0
                editor.deleteSelectedLayers()
                let after = editor.document?.flattenedLayers.count ?? 0
                let kept = picked.compactMap { editor.document?.layer(id: $0) }
                if dimmed {
                    actionDetail = "menu row dimmed, nothing deleted"
                        + (kept.isEmpty ? "" : " (locked: \(kept.map(\.name).sorted().joined(separator: ", ")))")
                } else {
                    actionDetail = "deleted \(before - after) of \(picked.count) picked"
                        + (kept.isEmpty ? "" : ", kept locked \(kept.map(\.name).sorted().joined(separator: ", "))")
                }
            case .selectComponentOriginal: editor.selectComponentOriginal()
            case .copyLayer: editor.copySelectedLayer()
            case .pasteLayer: editor.paste()
            case .paintScreenSurface:
                if let id = editor.selectedLayerID, editor.document?.layer(id: id)?.isFrame == true {
                    editor.setFrameBackground(id: id, hex: "#3B82F6")
                }
            case .newFrameDialog: editor.isNewFrameDialogPresented = true
            case .frameSelection:
                // The log has to say what the frame ended up holding, because
                // Frame Selection quietly does nothing when the selection
                // cannot be framed, and a walk that only prints the step name
                // reads exactly the same either way.
                let asked = editor.actionableLayerIDs.count
                let refused = !editor.canFrameSelection
                editor.frameSelection()
                if refused {
                    actionDetail = "refused: nothing in the selection can be framed"
                } else if let id = editor.selectedLayerID, let frame = editor.document?.layer(id: id) {
                    actionDetail = "\(frame.name) \(Int(frame.frame.width.rounded()))x\(Int(frame.frame.height.rounded()))"
                        + " holds \(frame.children.count) of \(asked) selected"
                } else {
                    actionDetail = "no frame was made"
                }
            case .makeComponent: editor.makeComponent()
            case .exposeWording: editor.exposeFirstProperty(kind: .text)
            case .exposeChoice: editor.exposeFirstProperty(kind: .variant)
            case .exposeShow: editor.exposeFirstProperty(kind: .visible)
            case .exposeColor: editor.exposeFirstProperty(kind: .color)
            case .exposeNumber: editor.exposeFirstProperty(kind: .number)
            case .exposeRoom: editor.exposeComponentsOwnRoom()
            case .knobUsesSavedColor: editor.answerFirstColorKnobWithSavedColor()
            case .cycleChoice: editor.cycleInstanceChoice()
            case .makeChoice: editor.makeChoice()
            case .detachInstance: editor.detachInstance()
            case .addComponentVersion: editor.addComponentVersion()
            case .showNextComponentVersion: editor.showNextComponentVersion()
            case .chooseNextShelfComponentVersion:
                if let componentID = editor.selectedComponentID {
                    editor.chooseNextShelfComponentVersion(componentID: componentID)
                }
            case .applyToOtherComponentVersions: editor.applyToOtherComponentVersions()
            case .roundCorners:
                let ids = editor.cornerRadiusSelection.layerIDs
                if !ids.isEmpty { editor.commitCornerRadius(ids: ids, 24) }
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
            case .holdColorDrag:
                holdColorDrag(editor, through: ["#E0483C", "#C9A227", "#3F8F4F", "#00A870"])
            case .releaseColorDrag:
                releaseColorDrag(editor)
            case .dragCornerRadius:
                dragCornerRadius(editor, through: [4, 10, 16, 22])
            case .dragOpacity:
                dragStyleSlider(editor, through: [0.9, 0.7, 0.55, 0.45]) { style, v in
                    style.opacity = v
                }
            case .magnifyCallout:
                // Exactly what a pull on the Magnification slider does: live
                // previews through the frame, one undo step on release.
                editor.previewCalloutMagnification(4)
                editor.commitCalloutMagnification()
            case .roundCallout:
                editor.setCalloutShape(.circle)
            case .armCalloutCircle:
                editor.calloutToolShape = .circle
            case .armCalloutRectangle:
                editor.calloutToolShape = .rectangle
            case .armCalloutMagnification:
                editor.calloutToolMagnification = 4
            case .armCalloutDefaultMagnification:
                editor.calloutToolMagnification = ZoomCalloutBuilder.defaultMagnification
            case .setTextSize:
                let ids = editor.textSelection.layerIDs
                if !ids.isEmpty { editor.setTextStyle(ids: ids, fontSize: 14) }
            case .setTextWeight:
                let ids = editor.textSelection.layerIDs
                if !ids.isEmpty { editor.setTextStyle(ids: ids, weight: .bold) }
            case .setTextSizeLarge:
                let ids = editor.textSelection.layerIDs
                if !ids.isEmpty { editor.setTextStyle(ids: ids, fontSize: 40) }
            case .setTextSizeThreeDigits:
                // The one size the menu cannot be put into by hand: it offers
                // seven, all of two digits, and takes a bigger one only from a
                // label that already wears it.
                let ids = editor.textSelection.layerIDs
                if !ids.isEmpty {
                    editor.setTextStyle(ids: ids, fontSize: TextStyles.threeDigitSizeForPlaytest)
                }
            case .setTextWeightRegular:
                let ids = editor.textSelection.layerIDs
                if !ids.isEmpty { editor.setTextStyle(ids: ids, weight: .regular) }
            case .setTextFontLongName:
                // The one state the Font menu cannot be put into by hand: the
                // menu offers a family only once a label already wears it.
                let ids = editor.textSelection.layerIDs
                if !ids.isEmpty {
                    editor.setTextStyle(ids: ids, fontName: TextStyles.longNameForPlaytest)
                }
            case .setTextFontShortName:
                let ids = editor.textSelection.layerIDs
                if !ids.isEmpty {
                    editor.setTextStyle(ids: ids, fontName: TextStyles.shortNameForPlaytest)
                }
            // The line round a shape is ONE row now, so a walk that thickens a
            // box pulls the same slider a walk that thickens an arrow does.
            case .dragThickness:
                let ids = editor.shapeSelection.layerIDs
                if !ids.isEmpty {
                    for width in [5.0, 7.0, 9.0] as [CGFloat] {
                        editor.previewOutlineWidth(ids: ids, width)
                    }
                    editor.commitOutlineWidth(ids: ids, 9)
                }
            case .dragThicknessThin:
                let ids = editor.shapeSelection.layerIDs
                if !ids.isEmpty { editor.commitOutlineWidth(ids: ids, 3) }
            // Rounding is ONE row now, so a walk that rounds a shape and a walk
            // that rounds a picture pull the same slider.
            case .dragShapeCornersSquare:
                let ids = editor.cornerRadiusSelection.layerIDs
                if !ids.isEmpty { editor.commitCornerRadius(ids: ids, 0) }
            case .dragShapeCorners:
                dragCornerRadius(editor, through: [8, 14, 18])
            case .toggleShadow:
                editor.setSelectionShadowEnabled(!editor.layerStyleSelection.hasShadowEverywhere)
            case .followOriginalLook:
                if let id = editor.selectedLayerID {
                    editor.clearInstanceStyleOverrides(instance: id)
                }
            case .paintSelectionGradient:
                paintGradient(editor, kind: .linear)
            case .paintSelectionAngularGradient:
                paintGradient(editor, kind: .angular)
            case .armToolGradient:
                armTool(editor, kind: .linear)
            case .armToolAngularGradient:
                armTool(editor, kind: .angular)
            case .paintToolColor:
                paintToolPlain(editor)
            case .openToolColorPicker:
                editor.openColorWell = "tool.color"
            case .openToolFillPicker:
                editor.openColorWell = "tool.fill"
            case .openColorPicker:
                if let slot = editor.colorStyleSlots
                    .first(where: { editor.colorStyleSelection(slot: $0).members.first != nil }) {
                    editor.openColorWell = "selection.\(slot.rawValue)"
                }
            case .openShadowColorPicker:
                editor.openColorWell = "shadow"
            case .closeColorPicker:
                editor.openColorWell = nil
            case .saveStyleFromPicker:
                // The color the open picker is holding, which for the Color
                // section's rows is the color those layers share.
                if let key = editor.openColorWell,
                   let raw = key.split(separator: ".").last.map(String.init),
                   let slot = ColorSlot(rawValue: raw),
                   let paint = editor.colorStyleSelection(slot: slot).savablePaint {
                    // The whole paint, so a walk that saves a gradient gets a
                    // gradient rather than the colour it starts on.
                    editor.saveColorStyle(paint: paint, name: paint.isGradient ? "Sunset" : "Brand",
                                          slot: slot)
                }
            case .saveColorStyle:
                // The picked layers' first color that could carry a name: with
                // several picked that is the first one they all share.
                if let slot = editor.colorStyleSlots
                    .first(where: { editor.colorStyleSelection(slot: $0).savablePaint != nil }) {
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
            case .keepStylesForOutlinesOnly:
                // The Styles shelf's tickboxes, over every saved colour at
                // once: nothing is repainted, they simply stop being offered
                // on a fill row. What is already wearing one keeps it, which is
                // exactly how a tool ends up holding a name a fill can no
                // longer take.
                for style in editor.document?.colorStyles ?? [] {
                    editor.setColorStyleRoles(styleID: style.id, roles: [.ink])
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
            case .borderSelection:
                // The Effects Border slider over everything picked: this is
                // what puts a Border row in the Effects list for every one of
                // them at once. There is no Border row in Appearance any more
                // (`OutlineRetirement.swift`) — a layer's edge is a Border and
                // only a Border — so this is the one row the colour lands on.
                let ids = editor.layerStyleSelection.borders.layerIDs
                if !ids.isEmpty { editor.setLayerStyle(ids: ids) { $0.borderWidth = 4 } }
            case .paintSelectionBorderColor:
                editor.setSelectionColor(slot: .border, hex: "#B0184A")
            case .pickFirstColorStyle:
                if let first = editor.colorStyleEntries.first {
                    editor.selectLibraryItem(first.id)
                }
            case .recolorPickedColorStyle:
                if let style = editor.selectedColorStyle {
                    editor.setColorStyleHex(styleID: style.id, hex: "#00A870")
                }
            case .reaimPickedColorStyle:
                if let style = editor.selectedColorStyle {
                    var paint = style.paint
                    paint.becoming(.linear)
                    paint.angle = (paint.angle + 90).truncatingRemainder(dividingBy: 360)
                    if !paint.stops.isEmpty {
                        paint.stops[paint.stops.count - 1].hex = "#5856D6"
                    }
                    editor.setColorStylePaint(styleID: style.id, paint: paint)
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
            case .showMediaShelf:
                editor.setLibraryVisible(true)
                UserDefaults.standard.set(LibraryScope.media.rawValue,
                                          forKey: LibraryPanel.scopeKey)
            case .hideLibrary: editor.setLibraryVisible(false)
            case .placeLibraryPick: editor.placeLibraryPick()
            case .insertPickedComponent: editor.insertPickedComponent()
            case .toggleGrid: editor.toggleCanvasGrid()
            case .showGrid: if !editor.canvasGrid.isVisible { editor.toggleCanvasGrid() }
            case .hideGrid: if editor.canvasGrid.isVisible { editor.toggleCanvasGrid() }
            case .adjustGrid: editor.beginGridAdjustment()
            case .showGridSettings: editor.showGridSettings()
            case .selectCanvas: editor.selectCanvas()
            case .duplicateLayer: editor.duplicateSelectedLayers()
            case .newLayerViaCopy: editor.newLayerViaCopy()
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
            case .saveLayers:
                editor.playtestSaveLayers()
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
            case .pickFirstOwnRule:
                if let id = editor.selectedLayerID,
                   let group = editor.document?.layer(id: id),
                   let arrangement = Experiments.shared.autoLayoutEnabled ? group.group?.layout
                                                                          : nil,
                   let first = group.contentsWithTheirOwnPlacement(arrangement: arrangement)
                       .first {
                    editor.selectLayer(first.id, inGroup: id)
                }
            case .stretchSelectionAcross:
                if let id = editor.selectedLayerID {
                    editor.setPlacement(id: id, horizontal: .stretch)
                }
            case .stretchSelectionDown:
                if let id = editor.selectedLayerID {
                    editor.setPlacement(id: id, vertical: .stretch)
                }
            case .fillSelectionInTheFlow:
                editor.toggleFillsTheFlow()
            case .makeSelectionTheSurface:
                editor.toggleSurface()
            case .alignWordsLeft:
                if let id = editor.selectedLayerID {
                    editor.setTextAlignment(layerID: id, TextAlign.left)
                }
            case .stretchContentsAcross:
                if let id = editor.selectedLayerID {
                    editor.setContentPlacement(id: id, horizontal: .stretch)
                }
            case .closeDocument:
                break  // handled above, where there is still a window to close
            case .closeSheets:
                editor.isExportDialogPresented = false
                editor.isNewFrameDialogPresented = false
                editor.isBlankCanvasDialogPresented = false
                editor.isResizeDialogPresented = false
                editor.isCanvasSizeDialogPresented = false
            }
            await sleep(0.2)
            let detail = (actionDetail.map { "\(action.rawValue) · \($0)" } ?? action.rawValue)
                + "; " + ViewBuildMeter.shared.report
            actionDetail = nil
            note(number, step.name, detail, state: describe())
        }
    }

    // MARK: - The right hand panel

    /// Every surface a walk can reach right now: the editor window, and
    /// anything the editor has put on top of it.
    ///
    /// A popover is not part of the window it appears to grow out of, it is a
    /// window of its own sitting on top, attached as a child. So a search that
    /// started at the editor's content view and walked down could photograph
    /// the colour picker and never touch it: every tab, swatch and field in it
    /// was invisible to a walk, which is what made colour work something the
    /// loop could only hand back as a picture.
    private func panelWindows() throws -> [NSWindow] {
        let host = try requireWindow()
        let attached = NSApp.windows.filter { other in
            other !== host && other.isVisible
                && (other.parent === host || host.childWindows?.contains(other) == true)
        }
        return [host] + attached
    }

    /// Every named thing the panel and whatever is open above it are showing
    /// right now, read fresh.
    private func panelTargets() throws -> [PanelTargetView] {
        try panelWindows().flatMap { window in
            // The title bar counts too: the panel's own toggle lives there.
            (window.contentView.map { Self.findAll(PanelTargetView.self, in: $0) } ?? [])
                + Self.findAllInTitlebar(PanelTargetView.self, of: window)
        }
        .filter { $0.window != nil && !$0.isHiddenOrHasHiddenAncestor }
    }

    private func panelTarget(_ name: String, kind: PanelTargetKind) throws -> PanelTargetView {
        let all = try panelTargets()
        let ofKind = all.filter { $0.kind == kind }
        // The name on screen first, then the steadier one beside it: a capture
        // tile reads "10 hours ago" today and "yesterday" tomorrow, so a walk
        // that has to keep working names it by its file instead.
        guard let match = ofKind.first(where: { $0.name == name })
                ?? ofKind.first(where: { $0.detail == name })
                ?? ofKind.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            let seen = ofKind.map { $0.detail.isEmpty ? $0.name : "\($0.name) / \($0.detail)" }
                .joined(separator: ", ")
            throw Failure(description: "no \(kind.rawValue) called \"\(name)\" is in the panel; the ones that are: "
                + (seen.isEmpty ? "none" : seen) + ". A `panel` step lists everything.")
        }
        return match
    }

    /// Something in the panel to scroll from, named the way the walk names it.
    ///
    /// A row in the layers list first, since that is the list most walks are
    /// crawling down. Anything else the panel is showing after that: the dock's
    /// own column scrolls too, and a control below its fold — the alignment
    /// buttons once a second layer is picked and an Arrange section arrives —
    /// can be reached no other way, because the layers list is not the list it
    /// is in.
    private func panelScrollTarget(_ name: String) throws -> PanelTargetView {
        let all = try panelTargets()
        if let row = all.first(where: { $0.kind == .row && $0.name == name }) { return row }
        if let other = all.first(where: { $0.name == name })
            ?? all.first(where: { $0.detail == name })
            ?? all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return other
        }
        let seen = all.map { $0.detail.isEmpty ? $0.name : "\($0.name) / \($0.detail)" }
            .joined(separator: ", ")
        throw Failure(description: "nothing called \"\(name)\" is in the panel to scroll from; the ones that are: "
            + (seen.isEmpty ? "none" : seen) + ". A `panel` step lists everything.")
    }

    /// Presses a control in the panel by the words on it.
    ///
    /// The press is real mouse events, not the control's action called behind
    /// its back: a button that is dimmed, covered by something else, or wired
    /// to nothing has to fail a walk the way it fails a person, and a shortcut
    /// straight to the action would report a pass for all three.
    ///
    /// The events are POSTED to the app's queue rather than handed to the view.
    /// SwiftUI answers a press from inside its own tracking loop, which pulls
    /// the release out of that queue; a walk that called `mouseDown` directly
    /// left the release nowhere to be found and stopped for good (tried
    /// 2026-09-04). Posting both first means the loop always finds its way out.
    private func pressControl(_ name: String, in row: String?, count: Int,
                              modifiers: [PlaytestModifier], across: CGFloat?,
                              number: Int) async throws {
        var target = try pressTarget(name, in: row)
        // A press lands in the middle of the control, which for a slider means
        // the knob goes halfway and nowhere else. `across` moves the press
        // along the control's own width, so a walk can put a slider on a value
        // it names rather than only on the one in the middle.
        if let across { target = target.pressed(across: across) }
        guard target.isEnabled else {
            throw Failure(description: "the control \"\(target.name)\" is dimmed, so pressing it would do nothing")
        }
        // The control's OWN window, which for anything inside a popover is the
        // popover and not the editor: the point is in its coordinates and the
        // event has to be addressed to it, or the click lands on the editor
        // window at whatever happens to be under those numbers.
        guard let window = target.window, window.contentView != nil, Self.isInReach(target) else {
            throw Failure(description: "the control \"\(target.name)\" is not where a person could "
                + "click it: it is off the window, or the dock has scrolled it far enough that the "
                + "panel's edge cuts across the point a press would land on. Scroll to it with a "
                + "\"scrollPanel\" step first. A `panel` step lists every control with an "
                + "\"inWindow\" flag that says which ones are reachable right now.")
        }
        let flags = eventFlags(modifiers)
        let stamp = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(
                with: .leftMouseDown, location: target.point, modifierFlags: flags, timestamp: stamp,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: count, pressure: 1),
              let up = NSEvent.mouseEvent(
                with: .leftMouseUp, location: target.point, modifierFlags: flags, timestamp: stamp + 0.05,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                clickCount: count, pressure: 0) else {
            throw Failure(description: "could not make a mouse event for \"\(target.name)\"")
        }
        MainThreadMeter.shared.install()
        MainThreadMeter.shared.reset()
        ViewBuildMeter.shared.reset()
        NSApp.postEvent(down, atStart: false)
        NSApp.postEvent(up, atStart: false)
        // Long enough for the queue to drain and for whatever the press
        // changed to be laid out before the next step reads it.
        await sleep(0.35)
        let place = target.detail.isEmpty ? "" : " in \(target.detail)"
        let along = across.map { " at \(Int(($0 * 100).rounded()))% across it" } ?? ""
        note(number, "press",
             "\"\(target.name)\"\(place) at window \(short(target.point)), "
             + "\(count == 1 ? "one click" : "\(count) clicks")" + along
             + (modifiers.isEmpty ? "" : " with \(modifiers.map(\.rawValue).joined(separator: "+"))")
             + "; " + MainThreadMeter.shared.report + "; " + ViewBuildMeter.shared.report,
             state: describe())
    }

    /// Carries a dock section up or down the column, the way a person does:
    /// take hold of its header, move until the pointer has passed the middle
    /// of another section, and let go — or press Escape instead, which puts it
    /// back.
    ///
    /// It drives the dock's own carry rather than posting mouse events, for
    /// the reason written on `InspectorSectionDragProbe`: SwiftUI gestures do
    /// not answer synthesized events. Everything the reorder decides is real;
    /// the press that starts it is not.
    private func dragSection(_ title: String, past: String, stop: PlaytestSectionStop,
                             hold: String?, cancel: Bool, number: Int) async throws {
        let window = try requireWindow()
        guard let content = window.contentView else {
            throw Failure(description: "the window has no content view")
        }
        let probe = InspectorLayoutProbe.shared
        guard !probe.measured.isEmpty else {
            throw Failure(description: "the right hand panel is not on screen, so there is no section to carry")
        }
        func find(_ name: String) throws -> InspectorLayoutProbe.Section {
            guard let found = probe.measured.first(where: { $0.title == name }) else {
                throw Failure(description: "there is no section called \"\(name)\" in the panel; "
                    + "there is \(probe.measured.map(\.title).joined(separator: ", "))")
            }
            return found
        }
        let carried = try find(title), landing = try find(past)
        guard carried.id != landing.id else {
            throw Failure(description: "a section cannot be carried past itself")
        }
        let dock = InspectorSectionDragProbe.shared
        guard let carry = dock.carry, let letGo = dock.end, let putBack = dock.cancel else {
            throw Failure(description: "the dock is not offering its reorder; is the panel on screen?")
        }
        let before = probe.measured.map(\.title)
        // Take hold of the header, which is the top of the section, and travel
        // to just past the middle of the section being passed: the line that
        // one moves aside on.
        let goingDown = landing.frame.midY > carried.frame.midY
        let from = carried.frame.minY + 14
        let to = switch stop {
        case .middle: landing.frame.midY + (goingDown ? 4 : -4)
        case .touching: goingDown ? landing.frame.minY + 4 : landing.frame.maxY - 4
        }
        let steps = 12
        for i in 1...steps {
            let y = from + (to - from) * CGFloat(i) / CGFloat(steps)
            carry(carried.id, y, y - from)
            await sleep(0.02)
        }
        // What the panel is promising WHILE the section is in the air. A
        // reorder is not a drop, so the honest answer is nothing at all: this
        // is the line that catches the red dashes coming back.
        let promise = panelPromise()
        let inHand = probe.carrying ?? "nothing"
        var held = ""
        if let hold {
            try snapshot(content, name: hold)
            await screenCapture(window, name: hold)
            held = ", held \(hold).png"
        }
        if cancel { putBack() } else { letGo() }
        await sleep(0.5)
        let after = InspectorLayoutProbe.shared.measured.map(\.title)
        note(number, "dragSection",
             "\"\(title)\" carried \(goingDown ? "down" : "up") past \"\(past)\""
             + (stop == .touching ? ", only far enough to touch it," : "")
             + (cancel ? " and called off with Escape" : " and let go") + held
             + "; in hand \(inHand); while carrying, \(promise)"
             + "; order \(before.joined(separator: ", ")) -> \(after.joined(separator: ", "))",
             state: describe())
    }

    /// Drag the grab bar under a resizable panel area, and say what it did.
    ///
    /// It drives the bar's own handlers rather than posting mouse events, for
    /// the reason written on `PanelAreaHandleProbe`: SwiftUI gestures do not
    /// answer synthesized ones. What a walk drives here is the whole of the
    /// resize — where the pointer is, what the area decides to be, what gets
    /// remembered — and the one thing it does not cover is the six lines of
    /// gesture that turn a press into those calls.
    private func dragHandle(_ area: String, by: CGFloat,
                            expect: PlaytestHandleExpectation,
                            hold: String?, number: Int) async throws {
        let window = try requireWindow()
        guard let content = window.contentView else {
            throw Failure(description: "the window has no content view")
        }
        let probe = PanelAreaHandleProbe.shared
        guard let handle = probe.handle(named: area) else {
            throw Failure(description: "there is no resizable area called \"\(area)\" in the panel; "
                + "there is \(probe.names.isEmpty ? "none at all, so is the panel on screen?" : probe.names.joined(separator: ", "))")
        }
        let start = handle.reading
        func pt(_ value: CGFloat) -> String { "\(Int(value.rounded()))pt" }
        func measurements(_ reading: PanelAreaHandleReading) -> String {
            "\(pt(reading.height)) tall, content \(pt(reading.contentHeight)), "
                + "floor \(pt(reading.minHeight)), ceiling \(pt(reading.maxAllowedHeight))"
        }
        guard expect == .moves else {
            guard !start.isShown else {
                throw Failure(description: "\(area) is drawing a grab bar and this step expected none: "
                    + "the area is \(measurements(start)), so a drag has room to move it")
            }
            note(number, "dragHandle",
                 "\(area) offers no grab bar, as expected: \(measurements(start))",
                 state: describe())
            return
        }
        guard start.isShown else {
            throw Failure(description: "\(area) has no grab bar to drag: \(measurements(start))")
        }
        // Where the drag SHOULD leave it: the same arithmetic the bar itself
        // uses, so this is a claim about the area and not about the code.
        let wanted = PanelAreaResize.draggedHeight(base: start.height, translation: by,
                                                   contentHeight: start.contentHeight,
                                                   minHeight: start.minHeight,
                                                   maxAllowedHeight: start.maxAllowedHeight)
        let steps = 8
        for i in 1...steps {
            handle.carry(by * CGFloat(i) / CGFloat(steps))
            await sleep(0.02)
        }
        var held = ""
        if let hold {
            try snapshot(content, name: hold)
            await screenCapture(window, name: hold)
            held = ", held \(hold).png"
        }
        handle.end()
        await sleep(0.4)
        let after = probe.handle(named: area)?.reading ?? start
        guard abs(after.height - wanted) <= 1 else {
            throw Failure(description: "\(area) was \(pt(start.height)) tall, "
                + "the bar was dragged \(pt(abs(by))) \(by < 0 ? "up" : "down"), "
                + "and it is \(pt(after.height)) now, where it should be \(pt(wanted)) "
                + "(content \(pt(start.contentHeight)), floor \(pt(start.minHeight)), "
                + "ceiling \(pt(start.maxAllowedHeight)))")
        }
        note(number, "dragHandle",
             "\(area) dragged \(pt(abs(by))) \(by < 0 ? "up" : "down")\(held); "
                + "\(pt(start.height)) -> \(pt(after.height)) "
                + "(content \(pt(after.contentHeight)), remembered ceiling "
                + "\(pt(rememberedCeiling(for: area))))",
             state: describe())
    }

    /// What the app will read back on its next launch for this area, so a walk
    /// can prove a dragged height is remembered and not only drawn.
    private func rememberedCeiling(for area: String) -> CGFloat {
        let key = area.caseInsensitiveCompare("Library") == .orderedSame
            ? LibraryPanel.heightKey : LayersListView.heightKey
        return CGFloat(UserDefaults.standard.double(forKey: key))
    }

    /// The one thing in the panel called this, or a refusal that says what IS
    /// there. Two things wearing the same name is refused rather than guessed
    /// at: a walk that pressed the wrong one would pass and prove nothing.
    /// The controls that sit on one named row of the panel — Width's Fixed, not
    /// Height's; the blur's Switch, not the fill's.
    ///
    /// A detail is a list of words separated by commas, and a row's name is one
    /// whole item in it, so a whole item wins over a longer name that merely
    /// contains the asked-for one: `in: "Rectangle"` means the layer called
    /// Rectangle and not Rectangle 2 as well, which is otherwise how the second
    /// shape you draw makes the first one unpressable. Anything that matches
    /// nothing whole falls back to reading the detail as plain text, so half a
    /// row's name still finds it.
    ///
    /// A press and an `expect` narrow the same way, so a walk that can press a
    /// row's control can claim what that same control reads.
    static func narrow(_ targets: [PlaytestPressTarget], to row: String?) -> [PlaytestPressTarget] {
        guard let wanted = row else { return targets }
        let whole = targets.filter { target in
            target.detail.split(separator: ",").contains {
                $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(wanted) == .orderedSame
            }
        }
        return whole.isEmpty
            ? targets.filter { $0.detail.range(of: wanted, options: .caseInsensitive) != nil }
            : whole
    }

    private func pressTarget(_ name: String, in row: String?) throws -> PlaytestPressTarget {
        let all = Self.narrow(try pressTargets(), to: row)
        let inRow = row.map { " in \"\($0)\"" } ?? ""
        let exact = all.filter { $0.name == name }
        if exact.count == 1 { return exact[0] }
        if exact.count > 1 {
            throw Failure(description: "\(exact.count) controls in the panel are called \"\(name)\"\(inRow): "
                + exact.map { "\($0.name) (\($0.detail))" }.joined(separator: ", ")
                // Telling a walk to add an `in` it already has is no help, and
                // two layers really can wear one name — a component and the
                // copy of it are both called Card.
                + (row == nil
                   ? ". Add an \"in\" naming the row it is on."
                   : ". The rows wear the same name, so \"in\" cannot tell them apart; "
                     + "rename one of them first."))
        }
        if let loose = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return loose
        }
        // Then the steadier word beside it, the way a shelf tile can be named
        // by its file rather than by "10 hours ago". A swatch is called
        // "Shades 3" because the colour under it moves, but a walk that knows
        // exactly which colour it wants may say so — as long as only one
        // thing on screen is that colour, since a guess between two would
        // pass and prove nothing.
        let beside = all.filter { target in
            target.detail.split(separator: ",").contains {
                $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame
            }
        }
        if beside.count == 1 { return beside[0] }
        // Something scrolled out of the dock is still built and still listed,
        // so the list says which ones would need a scroll before a press.
        let seen = all.map { target -> String in
            var about = target.detail
            if Self.isInReach(target) == false {
                about += about.isEmpty ? "scrolled out of view" : ", scrolled out of view"
            }
            return about.isEmpty ? target.name : "\(target.name) (\(about))"
        }.joined(separator: ", ")
        throw Failure(description: "no control called \"\(name)\"\(inRow) is in the panel; the ones that are: "
            + (seen.isEmpty ? "none" : seen) + ". A `panel` step lists everything.")
    }

    /// Everything a press can land on: what the panel named for itself, and
    /// every segment of every picker, which names itself. A popover open on
    /// top of the panel is read the same way and its controls join the list,
    /// so the colour picker can be used and not only photographed.
    private func pressTargets() throws -> [PlaytestPressTarget] {
        try panelWindows().flatMap { pressTargets(in: $0) }
            + PlaytestPanelPress.sheetButtons(on: try requireWindow())
    }

    /// The same, for one surface. Rows and controls are matched up WITHIN a
    /// window: a frame means nothing across two of them, so a picker floating
    /// over the Fill row must not take that row's name.
    private func pressTargets(in window: NSWindow) -> [PlaytestPressTarget] {
        guard let content = window.contentView else { return [] }
        // The title bar's own controls press like any other.
        let everything = (Self.findAll(PanelTargetView.self, in: content)
                          + Self.findAllInTitlebar(PanelTargetView.self, of: window))
            .filter { $0.window != nil && !$0.isHiddenOrHasHiddenAncestor }
        let fields = everything.filter { $0.kind == .field }
        // A marker cannot tell whether the control in front of it is dimmed —
        // SwiftUI's `disabled` leaves no mark on the view tree — so a press on
        // one is judged by what it changes, not by asking first. A picker
        // segment is a real AppKit control and does know.
        // Tiles press too. A tile on the Library shelf is clicked to pick it,
        // exactly like a button, and a walk that can drag one off the shelf but
        // cannot click it could never prove the click still works.
        let pressable: Set<PanelTargetKind> = [.control, .tile]
        let marked = everything.filter { pressable.contains($0.kind) }.map { target -> PlaytestPressTarget in
            let frame = target.convert(target.bounds, to: nil)
            // The rows lead, widest first, and whatever the control is saying
            // right now follows, the way a picker segment reads "Width, already
            // on Fixed", so a checkbox reads "Fill, on" and not "on, Fill". A
            // control that names its own row keeps the one copy. Naming every
            // enclosing row rather than the innermost is what lets a walk say
            // which of two Borders' Width it means.
            var pieces = PlaytestPanelPress.fields(of: target, among: fields)
            if !target.detail.isEmpty, !pieces.contains(target.detail) {
                pieces.append(target.detail)
            }
            return PlaytestPressTarget(name: target.name, detail: pieces.joined(separator: ", "),
                                       point: CGPoint(x: frame.midX, y: frame.midY),
                                       box: frame,
                                       visible: target.convert(target.visibleRect, to: nil),
                                       isEnabled: true, window: window)
        }
        return marked + PlaytestPanelPress.segments(in: content, named: fields)
    }

    /// Scrolls whatever the named control is sitting in until a press could
    /// land on it, and says how far that turned out to be.
    ///
    /// The step a walk writes instead of a distance. `scrollPanel` takes a
    /// number of points, and a number of points is a fact about the dock on
    /// the day somebody measured it: the Effects section arrived on 2026-09-07
    /// and four walks that had scrolled far enough the day before were
    /// suddenly pressing a control the panel's edge cut across. Nobody scrolls
    /// by 260 points. They scroll until they can see the thing.
    ///
    /// It scrolls in rounds because the dock builds rows lazily: what arrives
    /// on screen changes the heights above it, so the distance worked out from
    /// the first measurement is only an opening bid. A control already in
    /// reach costs nothing and says so.
    private func reveal(_ name: String, in row: String?, number: Int) async throws {
        let target = try pressTarget(name, in: row)
        guard !Self.isInReach(target) else {
            note(number, "reveal",
                 "\"\(target.name)\"\(target.detail.isEmpty ? "" : " in \(target.detail)") "
                 + "was already where a person could press it; nothing scrolled",
                 state: describe())
            return
        }
        guard let window = target.window, let content = window.contentView else {
            throw Failure(description: "the control \"\(name)\" is in no window to scroll")
        }
        ViewBuildMeter.shared.reset()
        MainThreadMeter.shared.install()
        MainThreadMeter.shared.reset()
        var moved = 0.0
        var stuck = ""
        // Six rounds is generous: each one closes the whole measured gap, and
        // the rounds after the first are for the row heights that changed
        // under it. A dock that has not arrived in six is not going to.
        for _ in 0..<6 {
            let current = try pressTarget(name, in: row)
            if Self.isInReach(current) { break }
            // Each scrolling area around the control, innermost first, paired
            // with the strip of window it could actually park the control in.
            // The strip is what a section on its own cannot tell you: a list
            // inside the dock scrolls by itself and can run past the bottom of
            // the window, so a control down there is inside its own list and
            // still unpressable. Measuring against the list alone reported
            // nothing to do and scrolled 0pt, which is why a reveal into the
            // Effects list used to have to be written as a wheel turn of 120.
            let reaches = Self.scrollReaches(for: current, in: content)
            guard !reaches.isEmpty else {
                throw Failure(description: "the control \"\(name)\" is out of reach and nothing "
                    + "around it scrolls, so no step could bring it in. It may be off the window "
                    + "itself: make the window taller, or open the section it is in.")
            }
            // The innermost thing holding it turns first, because that is the
            // one a person would put the pointer over. When it is already
            // showing that stretch of its own length, or has no more to give,
            // the section around it takes the turn instead.
            var round = 0.0
            var asked = false
            for (clip, reach) in reaches {
                let by = Self.gap(from: current.box, into: reach)
                guard by != 0 else { continue }
                asked = true
                round = Self.scrollClip(clip, by: by)
                if round > 0.5 { break }
            }
            moved += round
            guard round > 0.5 else {
                stuck = asked
                    ? "everything around it is already scrolled as far as it goes"
                    : "it is already inside the part of the window a press can reach, so "
                        + "something other than a scroll is covering or cutting it"
                break
            }
            await sleep(0.35)
        }
        let landed = try pressTarget(name, in: row)
        guard Self.isInReach(landed) else {
            throw Failure(description: "scrolled \(Int(moved))pt and \"\(name)\" is still not "
                + "where a person could press it"
                + (stuck.isEmpty ? "" : ": " + stuck)
                + ". The window may be too short for the section it is in.")
        }
        note(number, "reveal",
             "\"\(landed.name)\"\(landed.detail.isEmpty ? "" : " in \(landed.detail)") "
             + "brought into reach by scrolling \(Int(moved))pt, now at window \(short(landed.point))"
             + "; " + ViewBuildMeter.shared.report + "; " + MainThreadMeter.shared.report,
             state: describe())
    }

    /// Two points of daylight, so a control resting exactly on the edge is not
    /// left one rounding error short of reachable.
    private static let revealMargin = 2.0

    /// Every scrolling area the control is inside, outermost first: the dock
    /// before the Effects list that sits inside the dock.
    ///
    /// By geometry rather than by hierarchy: a press target is a point and a
    /// box, not a view, so there is no `enclosingScrollView` to ask.
    ///
    /// A control that needs revealing is by definition NOT where the clip view
    /// is, so the two boxes do not overlap and asking whether they do finds
    /// nothing. What holds instead is the SCROLLED length: the control sits
    /// somewhere in the document the clip is a window onto, so its box lands
    /// inside that document's own bounds.
    private static func scrollableClips(for target: PlaytestPressTarget, in content: NSView) -> [NSClipView] {
        var found: [(clip: NSClipView, depth: Int)] = []
        func walk(_ view: NSView, _ depth: Int) {
            if let scroll = view as? NSScrollView, !scroll.contentView.isHidden,
               let document = scroll.documentView {
                let whole = document.convert(document.bounds, to: nil)
                let box = target.box.isEmpty
                    ? CGRect(origin: target.point, size: CGSize(width: 1, height: 1))
                    : target.box
                // Grown a little across, because a row can hang a point or two
                // outside the column it is laid out in.
                if whole.insetBy(dx: -4, dy: 0).contains(box) {
                    found.append((scroll.contentView, depth))
                }
            }
            for sub in view.subviews where !sub.isHidden && sub.alphaValue > 0 { walk(sub, depth + 1) }
        }
        walk(content, 0)
        // Shallowest first. Depth rather than width, because a list can be
        // exactly as wide as the dock it sits in and still be the inner one.
        return found.sorted { $0.depth < $1.depth }.map(\.clip)
    }

    /// Each scrolling area around the control paired with the strip of window
    /// it could park the control in, innermost first.
    ///
    /// The strip is the window narrowed by that area and by every one outside
    /// it. An area with nothing left of it is dropped: a list that has itself
    /// been carried off the window shows no part of its own length, so turning
    /// its wheel only slides the control along a strip nobody can see, and the
    /// section around it is the one that has to move. Dropping those is also
    /// what keeps a scrolling area that merely happens to be long enough, and
    /// is nowhere near the control, from narrowing the answer down to nothing.
    private static func scrollReaches(for target: PlaytestPressTarget,
                                      in content: NSView) -> [(clip: NSClipView, reach: CGRect)] {
        var region = content.convert(content.bounds, to: nil)
        var pairs: [(clip: NSClipView, reach: CGRect)] = []
        for clip in scrollableClips(for: target, in: content) {
            region = region.intersection(clip.convert(clip.bounds, to: nil))
            pairs.append((clip, region))
        }
        return pairs.reversed().filter { !$0.reach.isNull && !$0.reach.isEmpty }
    }

    /// How far the wheel has to turn to bring `box` inside `reach`, and which
    /// way round. Zero when it is already there.
    ///
    /// A window's coordinates run bottom up, so something FURTHER DOWN the
    /// list has the SMALLER y, and reaching it means going down the list,
    /// which the wheel writes as a negative number.
    private static func gap(from box: CGRect, into reach: CGRect) -> Double {
        if box.minY < reach.minY { return -(reach.minY - box.minY + revealMargin) }
        if box.maxY > reach.maxY { return box.maxY - reach.maxY + revealMargin }
        return 0
    }

    /// Scrolls one clip view and answers how far it actually went. The wheel
    /// first, the way `scrollPanel` does, because a SwiftUI scroll area that
    /// takes the wheel keeps its own momentum and edges honest.
    @discardableResult
    private static func scrollClip(_ clip: NSClipView, by points: Double) -> Double {
        // A distance is worked out from rectangles, and a rectangle that came
        // back empty carries infinity: turning that into a wheel count used to
        // bring the whole run down instead of failing the step.
        guard points.isFinite, let scrollView = clip.enclosingScrollView else { return 0 }
        let turn = Int32(min(max(points.rounded(), -30_000), 30_000))
        let start = clip.bounds.origin.y
        if let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                               wheel1: turn, wheel2: 0, wheel3: 0),
           let event = NSEvent(cgEvent: wheel) {
            scrollView.scrollWheel(with: event)
        }
        if abs(clip.bounds.origin.y - start) > 0.5 { return abs(clip.bounds.origin.y - start) }
        // Down the list is +y in a flipped clip view and -y in one that is
        // not, which is the same direction the wheel means by a negative
        // number. Same reasoning as `scroll(from:by:)`.
        let step = clip.isFlipped ? -points : points
        // Held inside its own ends, so a list already scrolled to the bottom
        // reports honestly that it did not move rather than shoving its
        // content past the edge. A reveal reads that answer to decide the
        // section around it has to take the turn instead.
        var proposed = clip.bounds
        proposed.origin.y = start + step
        let allowed = clip.constrainBoundsRect(proposed)
        clip.scroll(to: CGPoint(x: clip.bounds.origin.x, y: allowed.origin.y))
        scrollView.reflectScrolledClipView(clip)
        return abs(clip.bounds.origin.y - start)
    }

    /// Whether a press could actually land on this: something scrolled out of
    /// the dock is still built and still listed, but out of reach until the
    /// walk scrolls to it. Judged against the control's OWN window, so a
    /// popover's contents are not measured against the editor behind them.
    ///
    /// Being inside the window is not enough, and neither is the one point a
    /// press aims at. The dock scrolls, and a row pushed until only a sliver
    /// of it shows still has that sliver inside the window: a press aimed at
    /// its middle lands a couple of points off the window's own edge and
    /// changes nothing, which is how a walk pressed Corner Radius and was told
    /// it worked while the radius stayed at zero. So the whole control has to
    /// be showing before a walk may press it. Anything less is a control a
    /// person would scroll to first, and so is a walk.
    private static func isInReach(_ target: PlaytestPressTarget) -> Bool {
        guard let content = target.window?.contentView else { return false }
        let inWindow = content.convert(content.bounds, to: nil)
        guard inWindow.contains(target.point), target.visible.contains(target.point) else { return false }
        // A marker with no size of its own has only its point to go on.
        // `contains` answers no to an empty rectangle whichever side it is on,
        // so asking about one would wrongly put every such control out of reach.
        guard !target.box.isEmpty else { return true }
        return inWindow.contains(target.box) && target.visible.contains(target.box)
    }

    /// What the panel is showing, in the names a walk has to use.
    /// What one named thing in the panel is showing right now, in the words a
    /// walk would claim: nil when there is no such thing on screen.
    ///
    /// A field says the text in its box, or nothing when the box is empty and
    /// only its own name is showing. A menu says the value it wears, and a
    /// control says what it is saying right now ("Outline, off"). A row and a
    /// tile say their own names, which is why `expect` will not let a walk ask
    /// those two what they read.
    private func panelReading(_ thing: PlaytestPanelThing, named: String,
                              inRow: String?) throws -> (found: Bool, reads: String, others: [String]) {
        func matches(_ candidate: String) -> Bool {
            candidate.caseInsensitiveCompare(named) == .orderedSame
        }
        switch thing {
        case .field:
            // Not only the editable ones: a readout a person can see but not
            // type into is exactly the kind of thing a walk wants to claim.
            let boxes = try panelWindows().flatMap { window in
                window.contentView.map { Self.findAll(NSTextField.self, in: $0) } ?? []
            }
            .filter { !$0.isHiddenOrHasHiddenAncestor }
            func labels(_ box: NSTextField) -> [String] {
                [box.placeholderString, box.accessibilityLabel()].compactMap { $0 }
            }
            guard let match = boxes.first(where: { labels($0).contains(where: matches) }) else {
                return (false, "", boxes.compactMap { labels($0).first }.filter { !$0.isEmpty })
            }
            // While a field is being typed into, the words live in the window's
            // field editor and the control still holds the value it had before
            // the caret arrived. Read the editor when there is one, or a walk
            // can never claim what a `key` step just typed.
            return (true, match.currentEditor()?.string ?? match.stringValue, [])
        case .menu:
            let menus = try panelWindows().compactMap(\.contentView).flatMap { surface -> [(String, String)] in
                let fields = Self.findAll(PanelTargetView.self, in: surface)
                    .filter { $0.kind == .field && $0.window != nil && !$0.isHiddenOrHasHiddenAncestor }
                return PlaytestPanelMenu.buttons(in: surface).map {
                    let naming = PlaytestPanelMenu.naming(of: $0, among: fields)
                    return (naming.name, naming.detail)
                }
            }
            guard let match = menus.first(where: { matches($0.0) }) else {
                return (false, "", menus.map(\.0))
            }
            return (true, match.1, [])
        case .control:
            let controls = Self.narrow(try pressTargets(), to: inRow)
            guard let match = controls.first(where: { matches($0.name) }) else {
                return (false, "", controls.map(\.name))
            }
            return (true, match.detail, [])
        case .row, .tile:
            let kind: PanelTargetKind = thing == .row ? .row : .tile
            let targets = try panelTargets().filter { $0.kind == kind }
            return (targets.contains { matches($0.name) }, named, targets.map(\.name))
        case .tooltip:
            // Named by the control it belongs to, and read the way a pointer
            // reads it: at that control's own middle, smallest marker winning.
            //
            // Only the things that ACTUALLY say something are in the list, so a
            // walk whose tooltip has gone is told the menu is right there and
            // silent while its neighbours still talk, which is the shape the
            // failure really has. Menus come first because a menu is the thing
            // whose tooltip changes under a walk.
            var talking: [(name: String, says: String)] = []
            for window in try panelWindows() {
                guard let surface = window.contentView else { continue }
                let fields = Self.findAll(PanelTargetView.self, in: surface)
                    .filter { $0.kind == .field && $0.window != nil && !$0.isHiddenOrHasHiddenAncestor }
                for button in PlaytestPanelMenu.buttons(in: surface) {
                    if let inRow, !PlaytestPanelPress.fields(of: button, among: fields)
                        .contains(where: { $0.caseInsensitiveCompare(inRow) == .orderedSame }) { continue }
                    let box = button.convert(button.bounds, to: nil)
                    guard let said = PlaytestPanelHelp.tip(at: CGPoint(x: box.midX, y: box.midY),
                                                           in: surface) else { continue }
                    talking.append((PlaytestPanelMenu.naming(of: button, among: fields).name, said))
                }
            }
            // Narrowed by the row first, the same way a control is: two Colors
            // and two Locks are on screen at once on an ordinary selection, and
            // without "in" a walk would be reading whichever AppKit built first.
            for control in Self.narrow(try pressTargets(), to: inRow) {
                guard let surface = control.window?.contentView,
                      let said = PlaytestPanelHelp.tip(at: control.point, in: surface) else { continue }
                talking.append((control.name, said))
            }
            guard let match = talking.first(where: { matches($0.name) }) else {
                return (false, "", talking.map(\.name))
            }
            return (true, match.says, [])
        }
    }

    /// Hold the panel to what the walk says it is showing.
    /// What the app is HOLDING, checked by name: every layer a menu row would
    /// act on, in draw order. A snapshot cannot photograph a pick that is
    /// missing — the rows simply sit there unhighlighted — so this is the step
    /// that fails a walk when an undo hands back the drawing without the
    /// picking.
    private func checkPicked(_ layers: [String]) throws -> String {
        let editor = try requireEditor()
        let picked = editor.actionableLayerIDs
        let all = editor.document?.allLayers ?? []
        let holding = all.filter { picked.contains($0.id) }.map(\.name)
        func list(_ names: [String]) -> String { names.isEmpty ? "nothing" : names.joined(separator: ", ") }
        guard holding == layers else {
            throw Failure(description: "the layers picked are \(list(holding)), not \(list(layers)); "
                + "the ones in the document: \(list(all.map(\.name)))")
        }
        return "picked: \(list(holding)), as claimed"
    }

    /// Fails the run unless exactly `count` measurements are on the canvas.
    ///
    /// The failure names what a half-placed caliper is still waiting for, so a
    /// walk that stops one click short of landing one reads as a walk that
    /// stopped one click short, rather than as an empty list nobody explains.
    private func checkMeasures(_ count: Int) throws -> String {
        let editor = try requireEditor()
        let landed = (editor.document?.allLayers ?? []).filter { $0.measure != nil }
        func plural(_ n: Int) -> String { n == 1 ? "measurement" : "measurements" }
        guard landed.count == count else {
            throw Failure(description: "\(landed.count) \(plural(landed.count)) on the canvas, not \(count)"
                + "; the caliper is \(canvas?.playtestMeasuringReport ?? "on no canvas")"
                + (landed.isEmpty ? "" : "; landed: \(landed.map(\.name).joined(separator: ", "))"))
        }
        return count == 0
            ? "nothing has been measured, as claimed"
            : "\(count) \(plural(count)) on the canvas, as claimed"
    }

    /// Whether the dock left the named section room for the pane it promised
    /// whole: the entry you just opened, or its first open one when nothing
    /// has been opened by hand.
    ///
    /// The claim is about points, and the answer is in points, so a walk that
    /// fails here says by how much rather than leaving someone to measure a
    /// capture with a ruler.
    private func checkSectionFits(_ title: String) throws -> String {
        let probe = InspectorLayoutProbe.shared
        let showing = probe.measured.map(\.title)
        guard let section = probe.measured.first(where: { $0.title == title }) else {
            throw Failure(description: "there is no \"\(title)\" section in the dock right now; "
                + "it is showing: \(showing.isEmpty ? "nothing" : showing.joined(separator: ", "))")
        }
        guard let room = probe.listRoom[section.id] else {
            return "\(title) is not a list the dock may shorten, so nothing in it is cut"
        }
        func points(_ value: CGFloat) -> String { "\(Int(value.rounded())) pt" }
        guard let needs = room.needsForOpenPane else {
            return "\(title) has nothing open in it, so there is no control for a cut to fall in"
        }
        guard room.keepsItsFloor else {
            throw Failure(description: "\(title) was drawn \(points(room.drawn)) tall and needs "
                + "\(points(needs)) to draw \(room.openPaneName) whole, so the dock has cut a "
                + "control across the middle; the whole list wants \(points(room.natural))")
        }
        return room.drawn >= room.natural - 0.5
            ? "\(title) is drawn whole, all \(points(room.natural)) of it"
            : "\(title) is shortened to \(points(room.drawn)) of \(points(room.natural)) and scrolls, "
                + "past \(room.openPaneName) at \(points(needs))"
    }

    /// Whether one named thing in the panel is really on screen: all of it, or
    /// as much of it as there is room for, starting at its top.
    ///
    /// Two edges can cut it, and a walk has to answer for both: the window,
    /// and whatever is scrolling it. An effect opened at the foot of a squeezed
    /// Effects list is inside the window and still invisible, because the
    /// list's own scroller ends above it — the exact bug this step was written
    /// for (2026-09-08).
    ///
    /// "As much as there is room for" is not a loophole, it is the panel's
    /// promise. A shadow with 255pt of settings in a list drawn 153pt tall can
    /// never be shown whole, and the right answer is its heading at the top
    /// with its settings running down from there. So nothing may be cut off
    /// the TOP, ever, and something may only be cut off the bottom when it is
    /// taller than the room it is in.
    ///
    /// `whole` takes that allowance away, for the pane the dock promised to
    /// keep room for: too tall for the room it was given is exactly the failure
    /// there, since the room was the panel's to decide.
    private func checkInView(_ name: String, whole: Bool = false) throws -> String {
        let all = try panelTargets()
        guard let match = all.first(where: { $0.name == name })
                ?? all.first(where: { $0.detail == name })
                ?? all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            let seen = all.map(\.name).joined(separator: ", ")
            throw Failure(description: "nothing called \"\(name)\" is in the panel at all; what is: "
                + (seen.isEmpty ? "none" : seen) + ". A `panel` step lists everything.")
        }
        guard let content = match.window?.contentView else {
            throw Failure(description: "\"\(name)\" is not in a window right now")
        }
        let box = match.convert(match.bounds, to: nil)
        let shown = match.convert(match.visibleRect, to: nil)
        let inWindow = content.convert(content.bounds, to: nil)
        // How much room whatever is scrolling this has, so a thing too tall for
        // it can be told from a thing that was simply left below the fold.
        let room = match.enclosingScrollView.map {
            $0.contentView.convert($0.contentView.bounds, to: nil).height
        } ?? inWindow.height
        func points(_ value: CGFloat) -> String { "\(Int(value.rounded())) pt" }
        // In AppKit's coordinates y counts up from the bottom, so what is cut
        // off the BOTTOM of the panel is what falls below `minY`.
        let below = max(shown.minY - box.minY, inWindow.minY - box.minY)
        let above = max(box.maxY - shown.maxY, box.maxY - inWindow.maxY)
        guard above <= 0.5 else {
            throw Failure(description: "the top of \"\(name)\" is not on screen: \(points(above)) of it "
                + "is cut off above what a person can see. Whatever it is in should have scrolled "
                + "to its beginning.")
        }
        guard below <= 0.5 || (!whole && box.height > room + 0.5) else {
            throw Failure(description: "\"\(name)\" is not all on screen: it is \(points(box.height)) "
                + "tall, there is \(points(room)) of room for it, and \(points(below)) of it is past "
                + "the bottom of what a person can see. "
                + (whole && box.height > room + 0.5
                   ? "The panel should have kept it \(points(box.height)) of room and scrolled to it."
                   : "The panel should have scrolled to it."))
        }
        guard below > 0.5 else {
            return "\"\(name)\" is all on screen, \(points(box.height)) of it"
        }
        return "\"\(name)\" starts on screen and shows \(points(shown.height)) of its "
            + "\(points(box.height)), which is all the room there is"
    }

    /// Every readout the right hand panel is SHOWING, in the words a person
    /// reads off the screen.
    ///
    /// Read through accessibility rather than from the views, because a slider's
    /// number is a SwiftUI `Text` and there is no `NSTextField` to ask. What
    /// accessibility hands back is what a screen reader would say, which is as
    /// close to "what is on screen" as this process can get, and it covers a row
    /// nobody thought to instrument.
    private func panelReadouts() throws -> [String] {
        var found: [String] = []
        var seen = Set<ObjectIdentifier>()
        func walk(_ element: Any, depth: Int) {
            guard depth < 60, let object = element as? NSObject else { return }
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            if let reachable = object as? NSAccessibilityProtocol {
                for words in [reachable.accessibilityValue() as? String,
                              reachable.accessibilityLabel()] {
                    if let words, !words.isEmpty { found.append(words) }
                }
                for child in reachable.accessibilityChildren() ?? [] {
                    walk(child, depth: depth + 1)
                }
            }
            // A view that publishes no accessibility children of its own still
            // has subviews, and a SwiftUI hosting view is exactly that: walk
            // both so a readout cannot hide in the gap between the two trees.
            if let view = object as? NSView {
                for subview in view.subviews where !subview.isHiddenOrHasHiddenAncestor {
                    walk(subview, depth: depth + 1)
                }
            }
        }
        for window in try panelWindows() {
            guard let content = window.contentView else { continue }
            walk(content, depth: 0)
            // And the readouts that publish nothing to accessibility at all:
            // every slider's number is one of those. See `PanelReadoutProbe`.
            found += PlaytestPanelReadout.values(in: content)
        }
        return found.filter { !$0.isEmpty }
    }

    /// Every number the panel is showing WITH the name of the row it sits on,
    /// so two rows can be compared rather than two loose numbers.
    ///
    /// A row inside another row is named for both, owner first: a shadow's
    /// Opacity is "Shadow \u{25B8} Opacity" and the layer's own is "Opacity",
    /// which is what the bracket round a part's settings says on screen. Rows
    /// are found by containment, exactly the way a press finds which row a
    /// control is in, so nothing has to be instrumented twice.
    private func namedPanelReadings() throws -> [(name: String, reads: String)] {
        var found: [(name: String, reads: String)] = []
        for window in try panelWindows() {
            guard let content = window.contentView else { continue }
            let rows = Self.findAll(PanelTargetView.self, in: content)
                .filter { $0.kind == .field && $0.window != nil && !$0.isHiddenOrHasHiddenAncestor }
            // The sliders and the plain readouts, which say their number out
            // loud to the probe and nothing at all to accessibility.
            for anchor in PlaytestPanelReadout.anchors(in: content) {
                let owners = PlaytestPanelPress.fields(of: anchor, among: rows)
                guard !owners.isEmpty else { continue }
                found.append((owners.joined(separator: " \u{25B8} "), anchor.text))
            }
            // ...and the boxes a person types into, which name themselves.
            for box in Self.findAll(NSTextField.self, in: content)
            where !box.isHiddenOrHasHiddenAncestor {
                let name = [box.accessibilityLabel(), box.placeholderString]
                    .compactMap { $0 }.first { !$0.isEmpty }
                guard let name, !box.stringValue.isEmpty else { continue }
                // A typing box IS its row, so its own name already carries
                // whatever the row is called; only rows OUTSIDE it are owners.
                let owners = PlaytestPanelPress.fields(of: box, among: rows)
                    .filter { $0.caseInsensitiveCompare(name) != .orderedSame }
                found.append(((owners + [name]).joined(separator: " \u{25B8} "), box.stringValue))
            }
        }
        return found
    }

    /// The number a readout is showing, or nil where it is showing a word.
    /// "18", "0 px" and "18 pt" are all the same claim about how round
    /// something is; "Mixed" and "Pill" are not numbers at all.
    private static func number(in reading: String) -> Double? {
        var digits = ""
        for character in reading {
            if character.isNumber || character == "." || (digits.isEmpty && character == "-") {
                digits.append(character)
            } else if !digits.isEmpty {
                break
            } else if character != " " {
                return nil
            }
        }
        return Double(digits)
    }

    /// One name, one number. Fails naming both rows and what each is saying, so
    /// the fix is the pair rather than a hunt.
    private func checkOneNumberPerName() throws -> String {
        var byName: [String: [(name: String, reads: String, number: Double)]] = [:]
        for reading in try namedPanelReadings() {
            guard let value = Self.number(in: reading.reads) else { continue }
            byName[reading.name.lowercased(), default: []]
                .append((reading.name, reading.reads, value))
        }
        let clashes = byName.values
            .filter { rows in rows.contains { $0.number != rows[0].number } }
            .sorted { ($0.first?.name ?? "") < ($1.first?.name ?? "") }
        guard clashes.isEmpty else {
            let said = clashes.map { rows in
                rows.map { "\"\($0.name)\" reads \"\($0.reads)\"" }.joined(separator: " and ")
            }
            throw Failure(description: "the panel is saying one name over two different numbers: "
                + said.joined(separator: "; ")
                + "; a person reading the panel cannot tell which of them the thing "
                + "they are looking at is wearing")
        }
        let counted = byName.values.filter { $0.count > 1 }.count
        return "no two rows in the panel wear one name over different numbers, across "
            + "\(byName.count) named readouts"
            + (counted == 0 ? "" : ", \(counted) of which are said in more than one place")
    }

    /// One space, one word. Fails naming the readout that disagrees, quoted the
    /// way it is written on screen, so the fix is the row rather than a hunt.
    private func checkOneUnit() throws -> String {
        let readouts = try panelReadouts()
        let strays = DocumentUnit.strays(in: readouts)
        let saying = readouts.filter { $0.contains(DocumentUnit.word) }
        guard strays.isEmpty else {
            let named = strays.map { "\"\($0.text)\" says \($0.word)" }
            throw Failure(description: "the panel is measuring one space in more than one word: "
                + named.joined(separator: "; ")
                + "; the app's word is \(DocumentUnit.word), and "
                + (saying.isEmpty ? "nothing else in the panel is using it"
                                  : "these are using it: " + saying.joined(separator: ", ")))
        }
        guard !saying.isEmpty else {
            throw Failure(description: "no readout in the panel is saying a length at all, so there "
                + "is nothing here to agree or disagree; the panel is showing "
                + "\(readouts.count) readouts: \(readouts.joined(separator: " | "))")
        }
        return "every length in the panel says \(DocumentUnit.word), across \(saying.count) "
            + "readouts: " + saying.joined(separator: ", ")
    }

    private func checkPanel(_ thing: PlaytestPanelThing, named: String, inRow: String?,
                            reads: String?, present: Bool?) throws -> String {
        let reading = try panelReading(thing, named: named, inRow: inRow)
        func list(_ names: [String]) -> String {
            names.isEmpty ? "none" : names.joined(separator: ", ")
        }
        let onRow = inRow.map { " in \"\($0)\"" } ?? ""
        if let present {
            if present, !reading.found {
                throw Failure(description: "no \(thing.rawValue) called \"\(named)\"\(onRow) is in the panel; "
                    + "the ones that are: \(list(reading.others))")
            }
            if !present, reading.found {
                throw Failure(description: "the \(thing.rawValue) called \"\(named)\"\(onRow) is in the panel, "
                    + "and this step says it should not be")
            }
        }
        if let reads {
            guard reading.found else {
                throw Failure(description: "no \(thing.rawValue) called \"\(named)\"\(onRow) is in the panel to read; "
                    + "the ones that are: \(list(reading.others))")
            }
            let showing = reading.reads.trimmingCharacters(in: .whitespaces)
            guard showing.caseInsensitiveCompare(reads.trimmingCharacters(in: .whitespaces))
                    == .orderedSame else {
                throw Failure(description: "the \(thing.rawValue) called \"\(named)\"\(onRow) reads "
                    + "\"\(showing)\", not \"\(reads)\"")
            }
        }
        if let reads {
            return "the \(thing.rawValue) \"\(named)\"\(onRow) reads \"\(reads)\", as claimed"
        }
        return present == true
            ? "the \(thing.rawValue) \"\(named)\"\(onRow) is in the panel, as claimed"
            : "no \(thing.rawValue) \"\(named)\"\(onRow) in the panel, as claimed"
    }

    /// Every glass group along the bottom of the canvas, left to right, with
    /// the numbers that decide whether the row lines up.
    private static func readToolBar() -> [String: Any] {
        let groups = ToolBarLayoutProbe.shared.measured.map { group -> [String: Any] in
            ["name": group.name,
             "x": Int(group.frame.minX.rounded()), "width": Int(group.frame.width.rounded()),
             "height": Int(group.frame.height.rounded()),
             "top": Int(group.frame.minY.rounded()), "bottom": Int(group.frame.maxY.rounded()),
             "centerY": Int(group.frame.midY.rounded())]
        }
        let heights = Set(groups.compactMap { $0["height"] as? Int })
        let centers = Set(groups.compactMap { $0["centerY"] as? Int })
        let zoom = ZoomReadoutProbe.shared
        return ["groups": groups,
                "heights": heights.sorted(), "centerLines": centers.sorted(),
                "linedUp": heights.count <= 1 && centers.count <= 1,
                // What the zoom percentage has been asked to do, since it is
                // the one group in the row that answers two different clicks.
                "zoomDoubleClicks": zoom.doubleClicks,
                "zoomMenuOpens": zoom.menuOpens,
                "zoomMenuFound": zoom.foundMenu.map { $0 as Any } ?? NSNull(),
                "zoomMenuRows": zoom.menuRows,
                "zoomClicks": zoom.clicks,
                "zoomWaitsEnded": zoom.waitsEnded]
    }

    /// Every icon parked on the panel's trailing edge, with the numbers that
    /// decide whether they sit on one line. `inset` is what a person could
    /// measure with a ruler: how far the icon's centre is in from the panel's
    /// own right edge.
    private static func readPanelEdge() -> [String: Any] {
        let probe = PanelEdgeProbe.shared
        let right = probe.panel.maxX
        let icons = probe.measured.map { control -> [String: Any] in
            ["kind": control.kind, "owner": control.owner,
             "width": round2(control.frame.width),
             "centerX": round2(control.frame.midX),
             "centerY": round2(control.frame.midY),
             "inset": round2(right - control.frame.midX)]
        }
        // The column a person sees is the LAST icon on each row: the one
        // against the edge. Everything before it (the lock, a count) makes its
        // own column further in, and the two must not be averaged together.
        let byRow = Dictionary(grouping: probe.measured, by: { Int($0.frame.midY.rounded()) })
        let edgeMost = byRow.values.compactMap { $0.max(by: { $0.frame.midX < $1.frame.midX }) }
        let insets = Set(edgeMost.map { round2(right - $0.frame.midX) })
        return ["panelRight": round2(right), "panelWidth": round2(probe.panel.width),
                "icons": icons,
                "edgeInsets": insets.sorted(),
                "spread": round2((insets.max() ?? 0) - (insets.min() ?? 0)),
                "onOneLine": insets.count <= 1]
    }

    /// Everything inside the panel with a leading edge, with the numbers that
    /// decide whether they begin on one margin. `inset` is what a person could
    /// measure with a ruler: how far the thing starts in from the panel's own
    /// LEFT edge.
    private static func readPanelStart() -> [String: Any] {
        let probe = PanelStartProbe.shared
        let left = PanelEdgeProbe.shared.panel.minX
        let marks = probe.measured.map { mark -> [String: Any] in
            ["kind": mark.kind.rawValue, "owner": mark.owner,
             "startX": round2(mark.frame.minX),
             "centerY": round2(mark.frame.midY),
             "inset": round2(mark.frame.minX - left)]
        }
        // Headings and rows share the panel's margin; a subsection is the one
        // thing allowed to step in, and it steps in by exactly one leading
        // column so its content lands under its parent's name.
        let onMargin = probe.measured.filter { $0.kind != .subsection }
        let margins = Set(onMargin.map { round2($0.frame.minX - left) })
        let stepped = Set(probe.measured.filter { $0.kind == .subsection }
            .map { round2($0.frame.minX - left) })
        return ["panelLeft": round2(left),
                "panelWidth": round2(PanelEdgeProbe.shared.panel.width),
                "marks": marks,
                "margin": Double(EditorChromeLayout.panelStartInset),
                "margins": margins.sorted(),
                "subsectionMargin": Double(EditorChromeLayout.panelSubsectionStartInset),
                "subsectionInsets": stepped.sorted(),
                "spread": round2((margins.max() ?? 0) - (margins.min() ?? 0)),
                "onOneMargin": margins.count <= 1
                    && (margins.first.map { abs($0 - Double(EditorChromeLayout.panelStartInset)) < 0.5 } ?? true),
                "subsectionsStepInOnce": stepped.allSatisfy {
                    abs($0 - Double(EditorChromeLayout.panelSubsectionStartInset)) < 0.5
                }]
    }

    private static func outlinePanelStart(_ start: [String: Any]) -> String {
        let marks = start["marks"] as? [[String: Any]] ?? []
        guard !marks.isEmpty else { return "nothing in the panel is being measured" }
        let line = marks.map { mark -> String in
            "\(mark["owner"] ?? "?") (\(mark["kind"] ?? "?")) starts \(mark["inset"] ?? "?")pt in"
        }.joined(separator: "; ")
        let verdict = (start["onOneMargin"] as? Bool ?? false)
            ? "every heading and every row begins on the panel's \(start["margin"] ?? "?")pt margin"
            : "they DO NOT share a margin: rows and headings begin \(start["margins"] ?? []) in, "
              + "a spread of \(start["spread"] ?? 0)pt against a margin of \(start["margin"] ?? "?")"
        let folded = (start["subsectionInsets"] as? [Double] ?? []).isEmpty
            ? "nothing is folded under anything here"
            : ((start["subsectionsStepInOnce"] as? Bool ?? false)
                ? "every folded subsection steps in once, to \(start["subsectionMargin"] ?? "?")"
                : "a folded subsection is at the wrong indent: \(start["subsectionInsets"] ?? [])")
        return line + " — " + verdict + "; " + folded
    }

    /// Halves and quarters matter here — a glyph one point wider moves its own
    /// centre by half a point — so these numbers keep two decimals.
    private static func round2(_ value: CGFloat) -> Double {
        (Double(value) * 100).rounded() / 100
    }

    private static func outlinePanelEdge(_ edge: [String: Any]) -> String {
        let icons = edge["icons"] as? [[String: Any]] ?? []
        guard !icons.isEmpty else { return "nothing is parked on the panel's edge" }
        let line = icons.map { icon -> String in
            "\(icon["owner"] ?? "?") \(icon["kind"] ?? "?") centre \(icon["inset"] ?? "?")pt in"
        }.joined(separator: "; ")
        let verdict = (edge["onOneLine"] as? Bool ?? false)
            ? "every icon against the edge is on one line"
            : "they DO NOT share a line: centres \(edge["edgeInsets"] ?? []) in from the edge, "
              + "a spread of \(edge["spread"] ?? 0)pt"
        return line + " — " + verdict
    }

    private static func outlineToolBar(_ row: [String: Any]) -> String {
        let groups = row["groups"] as? [[String: Any]] ?? []
        guard !groups.isEmpty else { return "no groups along the bottom of the canvas" }
        let line = groups.map { group -> String in
            let name = group["name"] as? String ?? "?"
            return "\(name) \(group["height"] ?? "?")pt tall, centre \(group["centerY"] ?? "?")"
        }.joined(separator: "; ")
        let zoom = "; the zoom percentage has taken \(row["zoomDoubleClicks"] ?? 0) double "
            + "click(s) to actual size and opened its stops \(row["zoomMenuOpens"] ?? 0) time(s)"
            + ((row["zoomMenuRows"] as? [String]).map { $0.isEmpty ? "" : " (\($0.joined(separator: ", ")))" } ?? "")
        let linedUp = (row["linedUp"] as? Bool ?? false)
            ? "they line up"
            : "they DO NOT line up: heights \(row["heights"] ?? []), centres \(row["centerLines"] ?? [])"
        return line + " — " + linedUp + zoom
    }

    private func readPanel() throws -> [String: Any] {
        func describe(_ target: PanelTargetView) -> [String: Any] {
            let frame = target.convert(target.bounds, to: nil)
            return ["name": target.name, "detail": target.detail,
                    "canBeDragged": target.payload != nil,
                    "x": Int(frame.midX.rounded()), "y": Int(frame.midY.rounded())]
        }
        let targets = try panelTargets()
        return [
            "tiles": targets.filter { $0.kind == .tile }.map(describe),
            "rows": targets.filter { $0.kind == .row }.map(describe),
            "controls": try pressTargets().map { control in
                ["name": control.name, "detail": control.detail, "enabled": control.isEnabled,
                 // Something scrolled out of the dock is still built, and still
                 // listed, but a press cannot reach it until the walk scrolls.
                 "inWindow": Self.isInReach(control),
                 "x": Int(control.point.x.rounded()), "y": Int(control.point.y.rounded())]
            },
            // Read as "Size (24 pt)": the name a walk types, then what the
            // menu is showing right now, the same way every control reads.
            "menus": try panelWindows().compactMap(\.contentView).flatMap { surface in
                let fields = Self.findAll(PanelTargetView.self, in: surface)
                    .filter { $0.kind == .field && $0.window != nil && !$0.isHiddenOrHasHiddenAncestor }
                return PlaytestPanelMenu.buttons(in: surface)
                    .map { Self.menuName(of: $0, among: fields, in: surface) }.filter { !$0.isEmpty }
            },
        ]
    }

    /// One menu as a list reads it: the name a walk types, the words it is
    /// showing when those are not the same thing, and what resting on it would
    /// say.
    ///
    /// The last part is the only proof there is that a menu explains itself.
    /// SwiftUI's `.help()` leaves nothing behind for a picture or a readout to
    /// find, so a menu whose tooltip had been deleted looked exactly like one
    /// that still had it. A menu built with plain `.help()` rather than
    /// `panelHelp` reads "says nothing", which is the same answer a menu with
    /// no tooltip at all gives, and both are worth seeing in the list.
    @MainActor private static func menuName(of button: NSPopUpButton,
                                            among fields: [PanelTargetView],
                                            in surface: NSView) -> String {
        let naming = PlaytestPanelMenu.naming(of: button, among: fields)
        let head = naming.detail.isEmpty ? naming.name : "\(naming.name) (\(naming.detail))"
        let box = button.convert(button.bounds, to: nil)
        let said = PlaytestPanelHelp.tip(at: CGPoint(x: box.midX, y: box.midY), in: surface)
        // How wide the box is and where its left edge sits, in the window. "The
        // box holds one width" and "the menu beside it does not move" are claims
        // about numbers, and two pictures of a 3pt shift look identical, so the
        // numbers are written down rather than left to the eye.
        let geometry = " \(round2(box.width))pt wide at x \(round2(box.minX))"
        return head + geometry + (said.map { " says \"\($0)\"" } ?? " says nothing")
    }

    private static func outlinePanel(_ inventory: [String: Any]) -> String {
        func names(_ key: String) -> String {
            let list = (inventory[key] as? [[String: Any]] ?? []).map { entry -> String in
                let name = entry["name"] as? String ?? "?"
                let detail = entry["detail"] as? String ?? ""
                return detail.isEmpty ? name : "\(name) (\(detail))"
            }
            return list.isEmpty ? "none" : list.joined(separator: ", ")
        }
        let menus = (inventory["menus"] as? [String] ?? [])
        return "shelf tiles: \(names("tiles"))\nlayer rows: \(names("rows"))"
            + "\ncontrols: \(names("controls"))"
            + "\nmenus: \(menus.isEmpty ? "none" : menus.joined(separator: ", "))"
    }

    /// A window's frame in the coordinates the screen recorder reads: the same
    /// rectangle, measured from the TOP of the primary screen rather than the
    /// bottom, which is the one place AppKit and the recorder disagree.
    private static func screenFrame(of window: NSWindow) -> CGRect {
        let frame = window.frame
        let top = NSScreen.screens.first?.frame.maxY ?? frame.maxY
        return CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Opens a menu inside the window, photographs it, and closes it.
    ///
    /// The click never returns until the menu is closed, so the way out is
    /// arranged before the click: a hop onto the main thread that names the
    /// tracking run loop mode by hand, which is the one thing that still runs
    /// while a menu is up.
    /// Open one of the app's own menu-bar menus over the probe window and
    /// photograph it.
    ///
    /// A menu bar menu cannot be pulled down the way a person does it: that
    /// needs the app to be the front app, and macOS will not give a
    /// script-launched process focus (`Self.frozenMenuBar`). So the menu is
    /// popped up inside the window instead. It is the SAME `NSMenu` the bar
    /// holds, so every row, key, dimming and checkmark in the picture is the
    /// real one — only its position on screen is arranged.
    ///
    /// Everything about waiting for a menu's own event loop, and about why the
    /// picture has to be a real screen capture, is `PlaytestPanelMenu`.
    private func photographMenuBarMenu(_ name: String, name shotName: String,
                                       ticked: [String], unticked: [String],
                                       number: Int) async throws {
        let host = try requireWindow()
        guard let content = host.contentView else {
            throw Failure(description: "the window has no content view")
        }
        guard let bar = NSApp.mainMenu else {
            throw Failure(description: "the app has no menu bar")
        }
        bar.update()
        guard let top = bar.items.first(where: { $0.title == name }), let menu = top.submenu else {
            let names = bar.items.map(\.title).joined(separator: ", ")
            throw Failure(description: "no menu called \"\(name)\"; the menu bar has: \(names)")
        }
        // A window scoped row (View ▸ Show Grid) reads its words and its
        // checkmark off the FOCUSED window, so with nothing key it reports the
        // default it would have with no document at all: Show Grid unticked and
        // Snap to Grid ticked whatever the document says.
        //
        // macOS will not give a background app the front spot
        // (`Self.frozenMenuBar`), and asking the editor window to take key
        // itself does not work — it was tried here on 2026-09-05 and it only
        // took key AWAY from whatever had it, leaving the whole bar dead. What
        // does work is the Capture History overlay: it takes key when it opens,
        // and once ANY of the app's windows is key SwiftUI fills the focused
        // value in and every row reads the real document. So a walk that wants
        // a live View menu opens the history first (⇧⌘H is app level, so it
        // always lands) and leaves it up.
        menu.update()
        let shotURL = out.appendingPathComponent("\(shotName)-sc.png")
        let noteURL = out.appendingPathComponent("menu-shot.txt")
        try? FileManager.default.removeItem(at: noteURL)
        var rows: [String] = []
        // Not "ticked": the parameter of that name is what the step REQUIRES,
        // and a local shadowing it made the requirement check itself and pass.
        var tickedRows: [String] = []
        // The rows with something behind them. SwiftUI hangs a target and an
        // action on a command item only while it is live, so a row with neither
        // is one whose state is a leftover default, not this document's.
        var liveRows: [String] = []
        var shot: String?

        let hop = PlaytestTrackingHop {
            rows = menu.items.map { $0.isSeparatorItem ? "" : $0.title }
            tickedRows = menu.items.filter { $0.state == .on }.map(\.title)
            liveRows = menu.items.filter { $0.action != nil }.map(\.title)
            if let menuWindow = PlaytestPanelMenu.openMenuWindow() {
                let finished = DispatchSemaphore(value: 0)
                PlaytestPanelMenu.capture(menuWindow: menuWindow.windowNumber,
                                          over: host.windowNumber,
                                          host: Self.screenFrame(of: host),
                                          to: shotURL) { outcome in
                    try? Data(outcome.utf8).write(to: noteURL)
                    finished.signal()
                }
                _ = finished.wait(timeout: .now() + 3)
                shot = shotURL.lastPathComponent
            } else {
                try? Data("the menu opened in no window this app can see".utf8).write(to: noteURL)
            }
            menu.cancelTracking()
        }
        hop.schedule(after: 0.55)
        // Near the top left of the window, so a long menu has room to draw
        // downward and the picture keeps the window around it for context. A
        // SwiftUI content view is flipped, so "the top" is whichever end of
        // its bounds the view says it is.
        let corner = NSPoint(x: 24, y: content.isFlipped ? 24 : content.bounds.height - 24)
        menu.popUp(positioning: nil, at: corner, in: content)
        await sleep(0.25)

        var outcome = "the picture never finished"
        for _ in 0..<40 {
            if let data = try? Data(contentsOf: noteURL), let text = String(data: data, encoding: .utf8) {
                outcome = text
                break
            }
            await sleep(0.1)
        }
        try? FileManager.default.removeItem(at: noteURL)
        // The picture is the deliverable, but a picture nobody checks proves
        // nothing, so the rows the step named are held to what they wore.
        // Read off what the OPEN menu was wearing, not off the menu now that it
        // has closed: closing it is another event, and another chance for the
        // words to change under the reading.
        //
        // A dead row's checkmark is a leftover default, and an assertion against
        // that would be a walk agreeing with itself. Refuse it rather than pass.
        if let dead = (ticked + unticked).first(where: { !liveRows.contains($0) }) {
            throw Failure(description: "\(name) ▸ \(dead) has nothing behind it, so its checkmark is the default "
                + "it would wear with no document at all, not this one's. \(Self.frozenMenuBar) "
                + "Open the Capture History first (a `shortcut` step on ⇧⌘H): it takes key, and that is enough "
                + "for every window scoped row to read the real document.")
        }
        for row in ticked + unticked where !rows.contains(row) {
            throw Failure(description: "no row called \"\(row)\" in the \(name) menu; the rows are: "
                + rows.map { $0.isEmpty ? "—" : $0 }.joined(separator: ", "))
        }
        if let missing = ticked.first(where: { !tickedRows.contains($0) }) {
            throw Failure(description: "\(name) ▸ \(missing) should be ticked and it is not; "
                + "ticked: \(tickedRows.isEmpty ? "none" : tickedRows.joined(separator: ", "))")
        }
        if let extra = unticked.first(where: { tickedRows.contains($0) }) {
            throw Failure(description: "\(name) ▸ \(extra) should NOT be ticked and it is")
        }
        note(number, "menuShot",
             "\(name) menu, photographed over the window: \(outcome). "
             + (rows.filter { !$0.isEmpty && !liveRows.contains($0) }.isEmpty ? ""
                : "Rows with nothing behind them, whose state is a default rather than this document's: "
                + rows.filter { !$0.isEmpty && !liveRows.contains($0) }.joined(separator: ", ") + ". ")
             + "Rows: \(rows.map { $0.isEmpty ? "—" : $0 }.joined(separator: " | ")). "
             + "Ticked: \(tickedRows.isEmpty ? "none" : tickedRows.joined(separator: ", "))",
             state: ["menu": name, "rows": rows, "ticked": tickedRows, "live": liveRows,
                     "shot": shot ?? NSNull()])
    }

    /// Opens the menu you get by RIGHT CLICKING something in the panel, reads
    /// it, photographs it, and can pick a row out of it.
    ///
    /// This is the third kind of menu and the only one that hangs off nothing.
    /// A menu bar menu is on the bar and a panel menu is on a button, so both
    /// can be found by looking; a `.contextMenu` exists only once the pointer
    /// asks for it, which is why every audit that wanted to show the layer row
    /// menu had to write out its rows in prose instead.
    ///
    /// The row is found by name, the way a press finds a button, and held to
    /// the same rule: a row the dock has scrolled out of reach fails the walk
    /// rather than opening a menu nobody could have opened. From there the
    /// menu comes from the view actually under that point, so the search is
    /// the one AppKit runs on a real right click.
    ///
    /// Unlike `menuShot` there is no check for rows with nothing behind them.
    /// That rule exists because the menu BAR reads its state off the focused
    /// window and a background app has none, so its checkmarks can be a
    /// leftover default. A context menu has no such trouble: it is built fresh
    /// by the very row that was clicked, so what it wears is that row's own
    /// state.
    ///
    /// Everything about waiting for a menu's own event loop, and about why the
    /// picture has to be a real screen capture, is `PlaytestPanelMenu`.
    private func openRowMenu(_ name: String, shot: String?, choose: String?,
                             ticked: [String], unticked: [String], number: Int) async throws {
        let target = try rightClickTarget(name)
        guard let window = target.window, let content = window.contentView else {
            throw Failure(description: "\"\(target.name)\" is in no window, so there is nothing to right click")
        }
        guard Self.isInReach(target) else {
            throw Failure(description: "\"\(target.name)\" is not where a person could right click it: it is "
                + "off the window, or the dock has scrolled it far enough that the panel's edge cuts across "
                + "it. Scroll to it with a \"scrollPanel\" step first.")
        }
        guard let (menu, view) = PlaytestPanelMenu.menu(rightClickingAt: target.point, in: content,
                                                        window: window) else {
            throw Failure(description: "right clicking \"\(target.name)\" raises no menu: nothing under that "
                + "point offers one. Is there a `.contextMenu` on it?")
        }
        let shotURL = shot.map { out.appendingPathComponent("\($0)-sc.png") }
        let noteURL = out.appendingPathComponent("row-menu-shot.txt")
        try? FileManager.default.removeItem(at: noteURL)
        var reading = PlaytestMenuReading()

        // Everything below runs INSIDE the menu's own event loop.
        let hop = PlaytestTrackingHop {
            reading.rows = menu.items.map { $0.isSeparatorItem ? "" : $0.title }
            reading.dimmed = menu.items.filter { !$0.isSeparatorItem && !$0.isEnabled }.map(\.title)
            reading.ticked = menu.items.filter { $0.state == .on }.map(\.title)
            if let shotURL, let menuWindow = PlaytestPanelMenu.openMenuWindow() {
                let finished = DispatchSemaphore(value: 0)
                PlaytestPanelMenu.capture(menuWindow: menuWindow.windowNumber,
                                          over: window.windowNumber,
                                          host: Self.screenFrame(of: window),
                                          to: shotURL) { outcome in
                    try? Data(outcome.utf8).write(to: noteURL)
                    finished.signal()
                }
                _ = finished.wait(timeout: .now() + 3)
                reading.shot = shotURL.lastPathComponent
            } else if shotURL != nil {
                reading.problem = "it showed in no window this app can see, so there is no picture"
            }
            // Picking happens LAST, after the reading and the picture: choosing
            // a row can rebuild the very list being read.
            if let choose {
                if let index = menu.items.firstIndex(where: { $0.title == choose }) {
                    if menu.items[index].isEnabled {
                        menu.performActionForItem(at: index)
                        reading.chose = choose
                    } else {
                        reading.problem = "the row \"\(choose)\" is dimmed, so picking it would do nothing"
                    }
                } else {
                    reading.problem = "there is no row called \"\(choose)\"; the rows are: "
                        + reading.rows.map { $0.isEmpty ? "—" : $0 }.joined(separator: ", ")
                }
            }
            menu.cancelTracking()
        }
        // Long enough for the menu to be up and drawn, short enough that it is
        // not sitting over whatever the person at this machine is looking at.
        hop.schedule(after: 0.55)
        // At the point the click landed on, which is where a real right click
        // puts it: the picture then shows the menu joined to the row it came
        // from, rather than floating at a corner.
        menu.popUp(positioning: nil, at: view.convert(target.point, from: nil), in: view)
        await sleep(0.25)

        var outcome = "no picture asked for"
        if shot != nil {
            outcome = "the picture never finished"
            for _ in 0..<40 {
                if let data = try? Data(contentsOf: noteURL), let text = String(data: data, encoding: .utf8) {
                    outcome = text
                    break
                }
                await sleep(0.1)
            }
            try? FileManager.default.removeItem(at: noteURL)
        }
        if let problem = reading.problem {
            throw Failure(description: "the menu on \"\(target.name)\" opened but \(problem)")
        }
        // Read off what the OPEN menu was wearing, not off the menu now that it
        // has closed: closing it is another event, and another chance for the
        // words to change under the reading.
        for row in ticked + unticked where !reading.rows.contains(row) {
            throw Failure(description: "no row called \"\(row)\" in the menu on \"\(target.name)\"; "
                + "the rows are: " + reading.rows.map { $0.isEmpty ? "—" : $0 }.joined(separator: ", "))
        }
        if let missing = ticked.first(where: { !reading.ticked.contains($0) }) {
            throw Failure(description: "\(target.name) ▸ \(missing) should be ticked and it is not; "
                + "ticked: \(reading.ticked.isEmpty ? "none" : reading.ticked.joined(separator: ", "))")
        }
        if let extra = unticked.first(where: { reading.ticked.contains($0) }) {
            throw Failure(description: "\(target.name) ▸ \(extra) should NOT be ticked and it is")
        }
        let rows = reading.rows.map { $0.isEmpty ? "—" : $0 }.joined(separator: " | ")
        var detail = "right clicked \"\(target.name)\""
        if !target.detail.isEmpty { detail += " (\(target.detail))" }
        detail += " at window \(short(target.point)): \(reading.rows.count) rows: \(rows)"
        detail += "; ticked: \(reading.ticked.isEmpty ? "none" : reading.ticked.joined(separator: ", "))"
        if !reading.dimmed.isEmpty { detail += "; dimmed: \(reading.dimmed.joined(separator: ", "))" }
        if let chose = reading.chose { detail += "; picked \"\(chose)\"" }
        detail += "; picture: \(outcome)"
        note(number, "rightClick", detail,
             state: ["on": target.name, "rows": reading.rows, "ticked": reading.ticked,
                     "dimmed": reading.dimmed, "chose": reading.chose ?? NSNull(),
                     "shot": reading.shot ?? NSNull()])
    }

    /// Something in the panel a right click can land on, named the way the walk
    /// names it. A row in one of the lists first, since those are the things
    /// that carry a menu, then anything else the panel named for itself, so
    /// the day a tile or a control grows one it is reachable without a change
    /// here.
    /// Which control on a row a right click should land on when the row itself
    /// has no name of its own.
    ///
    /// The menu being opened belongs to the whole row, so any control on it
    /// would do — except one that would answer for itself. A popup opens its
    /// own list, a slider takes the press, and a grip is waiting for a drag, so
    /// the click goes to the plain buttons: the colour well, or the cross.
    static func rightClickable(in targets: [PlaytestPressTarget]) -> PlaytestPressTarget? {
        let speaksForItself: Set<String> = ["Slider", "Kind", "Position", "Reorder", "Switch"]
        return targets.first { !speaksForItself.contains($0.name) }
    }

    private func rightClickTarget(_ name: String) throws -> PlaytestPressTarget {
        let all = try panelTargets().filter { $0.kind != .field }
        guard let match = all.first(where: { $0.kind == .row && $0.name == name })
                ?? all.first(where: { $0.name == name })
                ?? all.first(where: { $0.detail == name })
                ?? all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            // A row of the Effects list is not a row of the layers list: it
            // names itself only to the press targets, which carry the row a
            // control sits on. "Shadow 2" is a name only there, and its menu is
            // the only way a walk can reorder the list at all, since a
            // synthesized press cannot start a SwiftUI drag.
            if let inRow = Self.rightClickable(in: Self.narrow(try pressTargets(), to: name)) {
                return inRow
            }
            let seen = all.map { $0.detail.isEmpty ? $0.name : "\($0.name) / \($0.detail)" }
                .joined(separator: ", ")
            throw Failure(description: "nothing called \"\(name)\" is in the panel to right click; the ones "
                + "that are: " + (seen.isEmpty ? "none" : seen) + ". A `panel` step lists everything.")
        }
        let frame = match.convert(match.bounds, to: nil)
        return PlaytestPressTarget(name: match.name, detail: match.detail,
                                   point: CGPoint(x: frame.midX, y: frame.midY),
                                   box: frame,
                                   visible: match.convert(match.visibleRect, to: nil),
                                   isEnabled: true, window: match.window)
    }

    private func openPanelMenu(_ name: String, in row: String?, shot: String?, choose: String?,
                               clicking: String?, number: Int) async throws {
        let host = try requireWindow()
        guard let content = host.contentView else {
            throw Failure(description: "the window has no content view")
        }
        let fields = Self.findAll(PanelTargetView.self, in: content)
            .filter { $0.kind == .field && $0.window != nil && !$0.isHiddenOrHasHiddenAncestor }
        var buttons = PlaytestPanelMenu.buttons(in: content)
        // Narrowed to one row FIRST, the way a press is, so "the Color menu in
        // Border 2" is one thing to say rather than a search through every menu
        // in the panel that happens to be called Color.
        if let row {
            let inside = buttons.filter { button in
                PlaytestPanelPress.fields(of: button, among: fields)
                    .contains { $0.caseInsensitiveCompare(row) == .orderedSame }
            }
            guard !inside.isEmpty else {
                let seen = buttons.map { Self.menuName(of: $0, among: fields, in: content) }
                    .filter { !$0.isEmpty }
                throw Failure(description: "no row called \"\(row)\" holds a menu; "
                    + "the menus in the window are: "
                    + (seen.isEmpty ? "none" : seen.joined(separator: ", ")))
            }
            buttons = inside
        }
        // A menu is named by the row it sits on, which holds still, or by the
        // words it happens to be showing, which do not. Both work, because a
        // menu on no named row has nothing but its words — and the words win,
        // so naming one exactly is never made ambiguous by a row elsewhere.
        let byWords = buttons.first { PlaytestPanelMenu.title(of: $0) == name }
        let byRow = buttons.filter { PlaytestPanelMenu.naming(of: $0, among: fields).name == name }
        if byWords == nil, byRow.count > 1 {
            let showing = byRow.map { PlaytestPanelMenu.title(of: $0) }
            throw Failure(description: "\(byRow.count) menus sit on a row called \"\(name)\", "
                + "so it does not say which one: they are showing \(showing.joined(separator: ", ")). "
                + "Name the one you mean by its words instead.")
        }
        guard let button = byWords ?? byRow.first
                ?? buttons.first(where: { PlaytestPanelMenu.title(of: $0).hasPrefix(name) }) else {
            let seen = buttons.map { Self.menuName(of: $0, among: fields, in: content) }.filter { !$0.isEmpty }
            throw Failure(description: "no menu called \"\(name)\" is in the window; the ones that are: "
                + (seen.isEmpty ? "none" : seen.joined(separator: ", ")))
        }
        guard button.isEnabled else {
            throw Failure(description: "the \"\(name)\" menu is dimmed, so it has nothing to open")
        }
        let shotURL = shot.map { out.appendingPathComponent("\($0)-sc.png") }
        let noteURL = out.appendingPathComponent("panel-menu-shot.txt")
        try? FileManager.default.removeItem(at: noteURL)
        var reading = PlaytestMenuReading()

        // Everything below runs INSIDE the menu's own event loop.
        let hop = PlaytestTrackingHop {
            let menu = button.menu
            // Read as a person reads them: a size row is padded out with blank
            // so every size takes the same room in the box, and that blank is
            // no part of what the row says.
            reading.rows = menu?.items.map { PlaytestPanelMenu.readable($0.title) } ?? []
            reading.dimmed = menu?.items.filter { !$0.isEnabled }
                .map { PlaytestPanelMenu.readable($0.title) } ?? []
            if let shotURL, let menuWindow = PlaytestPanelMenu.openMenuWindow() {
                // The menu has to STAY up while its picture is taken, so the
                // main thread waits here rather than letting the walk carry on
                // and photograph a menu that has already gone. The screen
                // recorder answers on its own queue, so nothing it needs is
                // being held; the wait is bounded so a walk can never stall.
                let finished = DispatchSemaphore(value: 0)
                PlaytestPanelMenu.capture(menuWindow: menuWindow.windowNumber,
                                          over: host.windowNumber,
                                          host: Self.screenFrame(of: host),
                                          to: shotURL) { outcome in
                    try? Data(outcome.utf8).write(to: noteURL)
                    finished.signal()
                }
                _ = finished.wait(timeout: .now() + 3)
                reading.shot = shotURL.lastPathComponent
            } else if shotURL != nil {
                reading.problem = "the menu opened but showed in no window this app can see, so there is no picture"
            }
            if let choose {
                if let index = menu?.items.firstIndex(where: {
                    PlaytestPanelMenu.readable($0.title) == choose
                }) {
                    if menu?.items[index].isEnabled == true {
                        menu?.performActionForItem(at: index)
                        reading.chose = choose
                    } else {
                        reading.problem = "the row \"\(choose)\" is dimmed, so picking it would do nothing"
                    }
                } else {
                    reading.problem = "no row called \"\(choose)\"; the rows are: "
                        + reading.rows.map { $0.isEmpty ? "—" : $0 }.joined(separator: ", ")
                }
            }
            menu?.cancelTracking()
        }
        // Long enough for the menu to be up and drawn, short enough that it is
        // not sitting over whatever the person at this machine is looking at.
        // A control that has to tell a single click from a double one cannot
        // open its menu on the press: it waits first. So a walk that opens the
        // menu with a real click has to leave that wait, and the walk's way
        // out, room to happen.
        let opener = try clicking.map { try pressTarget($0, in: nil) }
        hop.schedule(after: opener == nil ? 0.55 : 1.1)
        var opened = "pressed the button in code"
        if let opener {
            try clickToOpen(opener)
            opened = "opened by clicking \"\(opener.name)\" at \(short(opener.point))"
        } else {
            button.performClick(nil)
        }
        await sleep(0.25)

        // The picture is written on a background queue, so wait for its note.
        var outcome = "no picture asked for"
        if shot != nil {
            outcome = "the picture never finished"
            for _ in 0..<40 {
                if let data = try? Data(contentsOf: noteURL), let text = String(data: data, encoding: .utf8) {
                    outcome = text
                    break
                }
                await sleep(0.1)
            }
            try? FileManager.default.removeItem(at: noteURL)
        }
        if let problem = reading.problem {
            throw Failure(description: "the \"\(name)\" menu opened but \(problem)")
        }
        let rows = reading.rows.map { $0.isEmpty ? "—" : $0 }.joined(separator: " | ")
        let dimmed = reading.dimmed.filter { !$0.isEmpty }
        var detail = "\"\(name)\" opened with \(reading.rows.count) rows: \(rows)"
        if !dimmed.isEmpty { detail += "; dimmed: \(dimmed.joined(separator: ", "))" }
        if let chose = reading.chose { detail += "; picked \"\(chose)\"" }
        detail += "; picture: \(outcome)"
        detail += "; \(opened)"
        note(number, "panelMenu", detail,
             state: ["rows": reading.rows, "dimmed": reading.dimmed,
                     "chose": reading.chose ?? NSNull(), "shot": reading.shot ?? NSNull()])
    }

    /// One plain click on a control, posted and left to land: the caller is
    /// about to be taken hostage by whatever the click opens, so nothing here
    /// waits for it.
    private func clickToOpen(_ target: PlaytestPressTarget) throws {
        guard target.isEnabled else {
            throw Failure(description: "the control \"\(target.name)\" is dimmed, so clicking it would do nothing")
        }
        guard let window = target.window, Self.isInReach(target) else {
            throw Failure(description: "the control \"\(target.name)\" is not where a person could click it")
        }
        let stamp = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(
                with: .leftMouseDown, location: target.point, modifierFlags: [], timestamp: stamp,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(
                with: .leftMouseUp, location: target.point, modifierFlags: [], timestamp: stamp + 0.05,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                clickCount: 1, pressure: 0) else {
            throw Failure(description: "could not make a mouse event for \"\(target.name)\"")
        }
        NSApp.postEvent(down, atStart: false)
        NSApp.postEvent(up, atStart: false)
    }

    /// Picks a tile up off the Library shelf and lets it go on the picture,
    /// through the canvas's own drag destination — the same calls a drag from
    /// the Finder makes, pasteboard and all.
    private func dragTile(_ name: String, to at: PlaytestPoint, hold: String?,
                          expect: PlaytestColorDropExpectation, says: String?,
                          number: Int) async throws {
        let canvas = try requireCanvas()
        let window = try requireWindow()
        let target = try panelTarget(name, kind: .tile)
        guard let payload = target.payload else {
            throw Failure(description: "the tile \"\(name)\" cannot be picked up")
        }
        let board = try await PlaytestPanelDrag.pasteboard(from: payload(), named: "tile")
        let viewPoint = try self.viewPoint(at)
        let windowPoint = canvas.convert(viewPoint, to: nil)
        let info = PlaytestDraggingInfo(pasteboard: board, location: windowPoint, window: window)
        let entered = canvas.draggingEntered(info)
        var updated = entered
        // A few frames of hovering, so whatever the canvas draws while a drag
        // is in the air is on screen and settled before the picture.
        for _ in 0..<3 {
            updated = canvas.draggingUpdated(info)
            await sleep(0.05)
        }
        var held = ""
        if let hold, let content = window.contentView {
            try snapshot(content, name: hold)
            await screenCapture(window, name: hold)
            let landing = canvas.dropLandingDescription
            held = ", held \(hold).png showing "
                + (landing.map { "box \(short($0.rect.origin)) \(short(CGPoint(x: $0.rect.width, y: $0.rect.height)))"
                                 + ($0.host.flatMap { id in editor?.document?.layer(id: id)?.name }
                                        .map { ", joining \($0)" } ?? ", loose on the canvas") }
                   ?? "no landing box")
        }
        // The sentence the picture is saying about this drag, for the walk to
        // read back. Only a saved style says one; everything else is silent,
        // and a walk that asks what a file says gets told there was nothing.
        let sentence = canvas.textStyleDropNote
        if let says {
            guard let sentence else {
                throw Failure(description: "the picture said nothing about the tile "
                    + "\"\(name)\", and the walk expected \"\(says)\"")
            }
            guard sentence.localizedCaseInsensitiveContains(says) else {
                throw Failure(description: "the picture said \"\(sentence)\" about the tile "
                    + "\"\(name)\", and the walk expected \"\(says)\"")
            }
        }
        let takes = updated != []
        if takes != (expect == .takes) {
            canvas.draggingExited(info)
            throw Failure(description: "the picture \(takes ? "took" : "refused") the tile "
                + "\"\(name)\" at \(short(at.point)) \(at.space.rawValue)"
                + (sentence.map { ", saying \"\($0)\"" } ?? "")
                + ", and the walk expected it to \(expect.rawValue)")
        }
        var landed = false
        if takes {
            landed = canvas.performDragOperation(info)
            guard landed else {
                throw Failure(description: "the canvas would not take the tile \"\(name)\"")
            }
        } else {
            canvas.draggingExited(info)
        }
        await sleep(0.4)
        let types = (board.types ?? []).map(\.rawValue).joined(separator: ", ")
        note(number, "dragTile",
             "\"\(name)\" carrying \(types) held over \(short(at.point)) \(at.space.rawValue) "
                + "= view \(short(viewPoint)): the picture \(takes ? "took it" : "refused it")"
                + (sentence.map { ", saying \"\($0)\"" } ?? "")
                + ", drop \(landed ? "landed" : "did not land")\(held)",
             state: describe())
    }

    /// Picks a saved text style up off the Library shelf and lets it go on a ROW
    /// in the layers list, through the same drop delegate a pointer drives.
    ///
    /// The row is the other obvious place to aim a style, and it answers with
    /// two things a walk can read: whether the row lights up, and the one line
    /// at the foot of the panel that says what letting go would do — or why it
    /// would not.
    ///
    /// A walk cannot start a real drag session, so the board the style rides on
    /// is stood in the drag pasteboard's place for the length of the step,
    /// which is exactly the board a destination under a real pointer reads.
    private func dragTile(_ name: String, ontoRow: String, hold: String?,
                          expect: PlaytestColorDropExpectation, says: String?,
                          number: Int) async throws {
        let window = try requireWindow()
        guard let content = window.contentView else {
            throw Failure(description: "the window has no content view")
        }
        let source = try panelTarget(name, kind: .tile)
        let destination = try panelTarget(ontoRow, kind: .row)
        guard let payload = source.payload else {
            throw Failure(description: "the tile \"\(name)\" cannot be picked up")
        }
        let board = try await PlaytestPanelDrag.pasteboard(from: payload(), named: "style")
        TextStyleDrag.playtestPasteboard = board
        defer { TextStyleDrag.playtestPasteboard = nil }
        let frame = destination.convert(destination.bounds, to: nil)
        let windowPoint = CGPoint(x: frame.midX, y: frame.midY)
        guard let dropView = PlaytestPanelDrag.destination(at: windowPoint, in: content,
                                                           marker: destination) else {
            throw Failure(description: "nothing at the row \"\(ontoRow)\" takes drops")
        }
        let info = PlaytestDraggingInfo(pasteboard: board, location: windowPoint, window: window)
        _ = dropView.draggingEntered(info)
        var operation: NSDragOperation = []
        for _ in 0..<3 {
            operation = dropView.draggingUpdated(info)
            await sleep(0.06)
        }
        // The line the panel is saying about this drag, read while it is still
        // in the air: it is the whole of what a refusal owes somebody.
        let sentence = editor?.layerRowStyleDrop?.answer.note
        var held = ""
        if let hold {
            try snapshot(content, name: hold)
            await screenCapture(window, name: hold)
            held = ", held \(hold).png"
        }
        if let says {
            guard let sentence else {
                throw Failure(description: "the panel said nothing about the tile "
                    + "\"\(name)\" over the row \"\(ontoRow)\", and the walk expected "
                    + "\"\(says)\"")
            }
            guard sentence.localizedCaseInsensitiveContains(says) else {
                throw Failure(description: "the panel said \"\(sentence)\" about the tile "
                    + "\"\(name)\" over the row \"\(ontoRow)\", and the walk expected "
                    + "\"\(says)\"")
            }
        }
        let lightsUp = operation != []
        if lightsUp != (expect == .takes) {
            dropView.draggingExited(info)
            throw Failure(description: "the row \"\(ontoRow)\" "
                + (lightsUp ? "lit up" : "stayed dark") + " for the tile \"\(name)\""
                + (sentence.map { ", saying \"\($0)\"" } ?? "")
                + ", and the walk expected it to \(expect.rawValue)")
        }
        var landed = false
        if lightsUp {
            landed = dropView.performDragOperation(info)
        } else {
            dropView.draggingExited(info)
        }
        await sleep(0.4)
        note(number, "dragTile",
             "\"\(name)\" let go on the row \"\(ontoRow)\": the row "
                + (lightsUp ? "lit up" : "stayed dark")
                + (sentence.map { ", saying \"\($0)\"" } ?? "")
                + ", drop \(landed ? "landed" : "did not land")\(held)",
             state: describe())
    }

    /// Picks up one of the app's OWN things — a layer row, a shelf tile, a
    /// colour swatch — and holds it over a point, without ever letting go.
    ///
    /// It exists for the half of a drag nothing else can photograph: what the
    /// right hand panel says about a drag that is not a file at all. Carrying a
    /// colour up over the layers list used to mark the whole panel refused,
    /// because the row under the pointer answers for plain text (that is how a
    /// row being reordered travels) and answered for it as if it were a file.
    ///
    /// `leave` abandons the drag where it is without telling anything under it
    /// that it ended, which is what escape and a release outside the window
    /// look like from in here, and is how a walk proves a mark clears itself.
    private func dragOver(_ carry: String, at: PlaytestPoint, hold: String?,
                          leave: Bool, number: Int) async throws {
        let window = try requireWindow()
        guard let content = window.contentView else {
            throw Failure(description: "the window has no content view")
        }
        let source = try pickUpSource(carry)
        guard let payload = source.payload else {
            throw Failure(description: "\"\(carry)\" cannot be picked up")
        }
        let board = try await PlaytestPanelDrag.pasteboard(from: payload(), named: "panel-thing")
        // A colour reads its own payload off the drag pasteboard, which a walk
        // cannot start, so it is stood in for the length of the step.
        ColorDrag.playtestPasteboard = board
        defer { ColorDrag.playtestPasteboard = nil }
        let windowPoint = try self.windowPoint(at)
        let chain = PlaytestPanelDrag.destinations(at: windowPoint, in: content)
        guard !chain.isEmpty else {
            throw Failure(description: "nothing at \(short(at.point)) \(at.space.rawValue) takes drops")
        }
        let info = PlaytestDraggingInfo(pasteboard: board, location: windowPoint, window: window)
        var operation: NSDragOperation = []
        var answered = "nothing under the pointer takes it"
        for round in 0..<4 {
            operation = []
            for view in chain {
                let reply = round == 0 ? view.draggingEntered(info) : view.draggingUpdated(info)
                if reply != [] {
                    operation = reply
                    answered = "\(type(of: view))"
                    break
                }
            }
            await sleep(0.05)
        }
        let promise = panelPromise()
        var held = ""
        if let hold {
            try snapshot(content, name: hold)
            await screenCapture(window, name: hold)
            held = ", held \(hold).png"
        }
        if !leave { for view in chain { view.draggingExited(info) } }
        await sleep(leave ? PanelDropMarking.idleGrace + 0.5 : 0.2)
        let after = leave
            ? ", walked away without a word and then \(panelPromise())"
            : ", let go of it and then \(panelPromise())"
        let types = (board.types ?? []).map(\.rawValue).joined(separator: ", ")
        note(number, "dragOver",
             "\"\(carry)\" carrying \(types) held over \(short(at.point)) \(at.space.rawValue): "
                + (operation == [] ? "nothing takes it" : "\(answered) would take it")
                + ", \(promise)\(held)\(after), \(rowInHand())",
             state: describe())
    }

    /// Anything in the panel a drag can start from, named the way a walk names
    /// it: a layer row first, then a shelf tile, then a colour swatch.
    private func pickUpSource(_ name: String) throws -> PanelTargetView {
        if let row = try? panelTarget(name, kind: .row) { return row }
        if let tile = try? panelTarget(name, kind: .tile) { return tile }
        return try colorDragSource(name)
    }

    /// Picks a row up in the layers list and holds it over another row, then
    /// lets go. The line that says what will happen is drawn by the same drop
    /// delegate a pointer drives, so `hold` photographs the real thing.
    private func dragRow(_ name: String, onto: String, zone: PlaytestDropZone,
                         hold: String?, number: Int) async throws {
        let window = try requireWindow()
        guard let content = window.contentView else {
            throw Failure(description: "the window has no content view")
        }
        let source = try panelTarget(name, kind: .row)
        let destination = try panelTarget(onto, kind: .row)
        guard let payload = source.payload else {
            throw Failure(description: "the row \"\(name)\" cannot be picked up")
        }
        let board = try await PlaytestPanelDrag.pasteboard(from: payload(), named: "row")
        // Where in the row to aim: the list reads the pointer's height in the
        // row, a third of it for each of above, inside and below.
        let frame = destination.convert(destination.bounds, to: nil)
        let fromTop: CGFloat = switch zone {
        case .above: 0.15
        case .inside: 0.5
        case .below: 0.85
        }
        // The window's coordinates run bottom up, the row's reading runs top
        // down, so the share is measured from the row's top edge.
        let windowPoint = CGPoint(x: frame.midX, y: frame.maxY - frame.height * fromTop)
        guard let dropView = PlaytestPanelDrag.destination(at: windowPoint, in: content) else {
            throw Failure(description: "nothing at the row \"\(onto)\" takes drops")
        }
        let info = PlaytestDraggingInfo(pasteboard: board, location: windowPoint, window: window)
        _ = dropView.draggingEntered(info)
        var operation: NSDragOperation = []
        for _ in 0..<3 {
            operation = dropView.draggingUpdated(info)
            await sleep(0.06)
        }
        var held = ""
        if let hold {
            try snapshot(content, name: hold)
            await screenCapture(window, name: hold)
            held = ", held \(hold).png"
        }
        let answered = operation == [] ? "refused" : "would take it"
        let landed = dropView.performDragOperation(info)
        await sleep(0.4)
        note(number, "dragRow",
             "\"\(name)\" let go \(zone.rawValue) \"\(onto)\": the list \(answered)"
                + ", drop \(landed ? "landed" : "did not land")\(held), \(rowInHand())",
             state: describe())
    }

    /// Picks the colour up off one swatch in the panel and lets go of it on
    /// another. The ring that says the second swatch will take it is drawn by
    /// the same drop delegate a pointer drives, so `hold` photographs the real
    /// thing.
    ///
    /// A walk cannot start a real drag session — AppKit only begins one from an
    /// event that came off a real device — so the board the colour rides on is
    /// stood in the drag pasteboard's place for the length of the step, which
    /// is exactly the board a destination under a real pointer would read.
    private func dragColor(_ from: String, onto: String, hold: String?,
                           expect: PlaytestColorDropExpectation, number: Int) async throws {
        let window = try requireWindow()
        guard let content = window.contentView else {
            throw Failure(description: "the window has no content view")
        }
        let source = try colorDragSource(from)
        let destination = try colorDropTarget(onto)
        guard let payload = source.payload else {
            throw Failure(description: "the \"\(from)\" colour cannot be picked up")
        }
        let board = try await PlaytestPanelDrag.pasteboard(from: payload(), named: "color")
        ColorDrag.playtestPasteboard = board
        defer { ColorDrag.playtestPasteboard = nil }
        let frame = destination.convert(destination.bounds, to: nil)
        let windowPoint = CGPoint(x: frame.midX, y: frame.midY)
        // `destination` is the anchor behind the very view the drop is
        // attached to, so it settles which of the drop areas stacked over this
        // point is the one being named: see `PlaytestPanelDrag.destination`.
        guard let dropView = PlaytestPanelDrag.destination(at: windowPoint, in: content,
                                                          marker: destination) else {
            throw Failure(description: "nothing at the \"\(onto)\" colour takes drops")
        }
        let info = PlaytestDraggingInfo(pasteboard: board, location: windowPoint, window: window)
        _ = dropView.draggingEntered(info)
        var operation: NSDragOperation = []
        for _ in 0..<3 {
            operation = dropView.draggingUpdated(info)
            await sleep(0.06)
        }
        var held = ""
        if let hold {
            try snapshot(content, name: hold)
            await screenCapture(window, name: hold)
            held = ", held \(hold).png"
        }
        let lightsUp = operation != []
        if lightsUp != (expect == .takes) {
            throw Failure(description: "\"\(onto)\" \(lightsUp ? "lit up" : "stayed dark")"
                + " for the colour off \"\(from)\", and the walk expected it to \(expect.rawValue)")
        }
        let landed = lightsUp ? dropView.performDragOperation(info) : false
        await sleep(0.4)
        note(number, "dragColor",
             "the colour off \"\(from)\" let go on \"\(onto)\": the swatch "
                + (lightsUp ? "lit up" : "stayed dark")
                + ", drop \(landed ? "landed" : "did not land")\(held)",
             state: describe())
    }

    /// Where a colour can be picked up: a swatch, named by the row it sits on,
    /// or a saved colour's tile on the Library shelf, named by the name it was
    /// saved under. The swatch wins a tie, because every swatch answers to the
    /// word Color and a tile answers to a name somebody typed.
    private func colorDragSource(_ name: String) throws -> PanelTargetView {
        if let well = try? colorWell(name) { return well }
        let tiles = try panelTargets().filter { $0.kind == .tile && $0.detail == "Styles" }
        guard let tile = tiles.first(where: { $0.name == name })
                ?? tiles.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        else {
            let seen = tiles.map(\.name).joined(separator: ", ")
            throw Failure(description: "no colour swatch or saved colour called \"\(name)\" is "
                + "in the panel; the saved colours on the shelf: "
                + (seen.isEmpty ? "none" : seen))
        }
        return tile
    }

    /// Where a colour can be let go of: a swatch, named by the row it sits on,
    /// or the Library shelf, which is named as itself because it belongs to no
    /// row and takes a colour to KEEP it rather than to paint with it.
    private func colorDropTarget(_ name: String) throws -> PanelTargetView {
        if name.caseInsensitiveCompare(Self.libraryShelfTarget) == .orderedSame,
           let shelf = try panelTargets().first(where: {
               $0.kind == .row && $0.name == Self.libraryShelfTarget
           }) {
            return shelf
        }
        if let well = try? colorWell(name) { return well }
        // A part that is switched OFF has no swatch at all, and the whole ROW
        // takes the drop instead. So a walk that names Outline on a box with
        // no line round it finds the row, which is the very thing a pointer
        // would be over.
        if let field = try panelTargets().first(where: {
            $0.kind == .field && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return field
        }
        return try colorWell(name)
    }

    /// The name the Library shelf answers to as a drop target, which is the
    /// name it wears in the dock.
    private static let libraryShelfTarget = "Library"

    /// A colour swatch in the panel, named by the row it sits on. Every swatch
    /// answers to the word Color, so the row's own word is what tells Fill's
    /// from Shadow's.
    private func colorWell(_ part: String) throws -> PanelTargetView {
        let wells = try panelTargets().filter { $0.kind == .control && $0.name == "Color" }
        // An effect's swatch says where it lives AND what it is — "Shadow,
        // Color" — the same way a control under an effect does, and a walk
        // names the effect, not the punctuation. So the words are read one at
        // a time, exactly as `in` is read everywhere else.
        func wears(_ target: PanelTargetView) -> Bool {
            target.detail.split(separator: ",").contains {
                $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(part) == .orderedSame
            }
        }
        guard let match = wells.first(where: { $0.detail == part })
                ?? wells.first(where: { $0.detail.caseInsensitiveCompare(part) == .orderedSame })
                ?? wells.first(where: wears)
        else {
            let seen = wells.map(\.detail).filter { !$0.isEmpty }.joined(separator: ", ")
            throw Failure(description: "no colour swatch for \"\(part)\" is in the panel; "
                + "the ones that are: " + (seen.isEmpty ? "none" : seen))
        }
        return match
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
        // Wait for the window this file opened, and NOTHING else. Reaching for
        // whatever editor happened to be last as a fallback inside the poll
        // meant the very first pass always succeeded whenever a document was
        // already open, so an `open` after a `blank` (or after another `open`)
        // silently went on driving the OLD window while the log printed the new
        // file's name. Only once nothing new has arrived at all is the
        // frontmost editor a sensible answer.
        var opened: EditorState?
        do {
            try await poll("an editor for \(url.lastPathComponent)", within: 15) {
                opened = PlaytestHarness.readyEditors.last { !before.contains(ObjectIdentifier($0)) }
                return opened != nil
            }
        } catch {
            opened = PlaytestHarness.readyEditors.last
            if opened == nil { throw error }
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
        // The open windows come along because half of what a menu item says
        // depends on them (whether Show History is ticked), and a reader who
        // cannot see the screen otherwise has no way to tell.
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

    /// Everything of this kind standing in a window's TITLE BAR. Its views
    /// hang off the window frame, not off `contentView`, so a search that
    /// started at the content view would photograph the panel toggle and never
    /// touch it.
    ///
    /// The titled check is not politeness: asking a borderless window for its
    /// titlebar accessories raises, and an exception thrown out of a walk's own
    /// step is swallowed by the run loop, which strands the walk with no error
    /// and no `done.json`. The tooltip a `hover` leaves up is exactly such a
    /// window, so `hover` followed by `press` hung until this guard went in.
    private static func findAllInTitlebar<T: NSView>(_ type: T.Type,
                                                     of window: NSWindow) -> [T] {
        guard window.styleMask.contains(.titled) else { return [] }
        return window.titlebarAccessoryViewControllers.flatMap { findAll(type, in: $0.view) }
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

    /// What a walk's `wait` step really means: let the editor finish, and get
    /// on with it once the editor has. Never spends more than `asked`, so
    /// nothing waits longer than it used to. Returns the line for the log,
    /// which says whether the editor went quiet and, when it did not, what was
    /// still going on.
    ///
    /// The editor is finished when both of these hold for a beat: the main run
    /// loop has had all but nothing to do, and nothing on the walk's window is
    /// still animating. Either signal alone lies. An animation the render
    /// server runs on its own leaves the main thread idle the whole way
    /// through, and a window with nothing queued may still be mid-fade.
    ///
    /// Why this exists: across the 247 walks in `Scripts/playtest` the `wait`
    /// steps add up to 31 minutes of sleeping, which was more than half of the
    /// whole run (measured 2026-09-07). The rule itself is `PlaytestSettle` in
    /// PhotonzCore, where it is tested without an app around it.
    private func settle(for asked: Double) async -> String {
        guard pace.watches else {
            await sleep(asked)
            return "\(asked)s on the clock"
        }
        let began = CACurrentMediaTime()
        var quiet = 0.0
        var slices = 0, busySlices = 0, restlessSlices = 0
        var busiest = 0.0
        var why = ""
        _ = MainThreadMeter.shared.takeBusy()
        while true {
            let waited = CACurrentMediaTime() - began
            if pace.isOver(waited: waited, asked: asked, quiet: quiet) { break }
            let nap = pace.nap(waited: waited, asked: asked)
            if nap <= 0 { break }
            await sleep(nap)
            let busy = MainThreadMeter.shared.takeBusy()
            let restless = isRestless()
            slices += 1
            if busy > pace.busyBudget { busySlices += 1 }
            if let restless { restlessSlices += 1; why = restless }
            busiest = max(busiest, busy)
            quiet = pace.quiet(after: quiet, slice: nap, busy: busy, restless: restless != nil)
        }
        let spent = CACurrentMediaTime() - began
        pacedAway += max(0, asked - spent)
        let stopwatch = String(format: "%.2f", spent)
        // Say WHY when a wait ran its whole length: a wait that never goes
        // quiet is either an editor that really is busy or a settle rule that
        // cannot see it, and the two look identical from the outside.
        if asked - spent > 0.01 {
            return "\(asked)s asked, quiet after \(stopwatch)s"
        }
        return "\(asked)s, never went quiet ("
            + "\(busySlices) of \(slices) slices busy, \(restlessSlices) restless\(why.isEmpty ? "" : " (\(why))"), "
            + String(format: "busiest %.1fms", busiest * 1000) + ")"
    }

    /// Whether anything the walk can see is still moving: a view that has asked
    /// to be redrawn and has not been yet, or a layer part way through an
    /// animation. The walk's own window and anything hung off it, since a
    /// popover or a tooltip is a window of its own.
    private func isRestless() -> String? {
        guard let window else { return nil }
        for w in [window] + (window.childWindows ?? []) {
            if w.viewsNeedDisplay { return "viewsNeedDisplay" }
            if let layer = w.contentView?.layer, let key = Self.animating(layer) { return "animating \(key)" }
        }
        return nil
    }

    /// Any layer under this one part way through an animation that is going to
    /// END. An animation that repeats for ever is a steady state, not
    /// something to wait out: the selection marquee's marching ants crawl the
    /// whole time a layer is picked, and taking them for unfinished work made
    /// every wait in the suite run its full length (found 2026-09-07).
    ///
    /// Bounded, because a SwiftUI window's layer tree is deep and this question
    /// gets asked every 30ms: past the budget the main thread meter carries it.
    private static func animating(_ root: CALayer) -> String? {
        var stack: [CALayer] = [root]
        var seen = 0
        while let layer = stack.popLast() {
            seen += 1
            if seen > 3000 { return nil }
            for key in layer.animationKeys() ?? [] {
                guard let animation = layer.animation(forKey: key), animation.endsOnItsOwn else { continue }
                return "\(type(of: layer)) \(key)"
            }
            if let sublayers = layer.sublayers { stack.append(contentsOf: sublayers) }
        }
        return nil
    }

    // MARK: - Targets

    /// A style slider dragged over the whole selection, the way a person drags
    /// it: several live frames and then a release, so one undo step lands for
    /// the whole gesture however many layers it reached.
    /// Turns the picked layers' first gradient-taking colour into a gradient,
    /// starting from the colour they already have — exactly what pressing a
    /// tile in the picker's type row does.
    private func paintGradient(_ editor: EditorState, kind: Paint.Kind) {
        guard let slot = editor.colorStyleSlots.first(where: {
            $0.acceptsGradient && editor.colorStyleSelection(slot: $0).members.first != nil
        }) else { return }
        var paint = editor.selectionPaint(slot: slot)
            ?? Paint(hex: editor.colorStyleSelection(slot: slot).savableColorHex ?? "#3366FF")
        paint.stops = Paint.seededStops(from: paint.hex)
        paint.kind = kind
        editor.setSelectionPaint(slot: slot, paint: paint)
    }

    /// Arms the tool in your hand with a gradient out of the colour it already
    /// has — exactly what pressing a tile in the toolbar swatch's type row
    /// does. A tool with an interior takes it on the fill, which is the swatch
    /// that swatch pair puts first; anything else takes it on its outline.
    /// A plain colour picked in the toolbar swatch's picker, on whichever part
    /// of the shape that swatch paints. The point of the action is what happens
    /// to a NAME the tool was holding, so it goes through the same call the
    /// picker's own commit does.
    private func paintToolPlain(_ editor: EditorState) {
        let plain = Paint(hex: "#2D7FF9")
        if editor.activeToolFillPaint != nil {
            editor.setAnnotationFillPaint(plain)
            actionDetail = "tool fill picked plain #2D7FF9"
        } else {
            editor.setAnnotationPaint(plain)
            actionDetail = "tool outline picked plain #2D7FF9"
        }
    }

    private func armTool(_ editor: EditorState, kind: Paint.Kind) {
        if var fill = editor.activeToolFillPaint {
            fill.becoming(kind)
            editor.setAnnotationFillPaint(fill)
            actionDetail = "fill armed \(kind.rawValue) out of #\(fill.hex.dropFirst())"
        } else if var paint = editor.activeToolPaint {
            paint.becoming(kind)
            editor.setAnnotationPaint(paint)
            actionDetail = "outline armed \(kind.rawValue) out of #\(paint.hex.dropFirst())"
        } else {
            actionDetail = "this tool holds no colour of its own"
        }
    }

    /// A colour drag in the picker, still down. Pushes a few live frames at the
    /// first colour row the picked layers have, the same way sliding the
    /// square or a channel does, and STOPS THERE: nothing is recorded, so a
    /// snapshot taken now shows the canvas following a drag that has not
    /// landed. `releaseColorDrag` is the other half.
    ///
    /// Reported with the main-thread cost of the whole run of frames, so a
    /// walk over a big selection can say whether the pull stayed smooth.
    private func holdColorDrag(_ editor: EditorState, through hexes: [String]) {
        guard let slot = editor.colorStyleSlots.first else { return }
        heldColorDrag = nil
        MainThreadMeter.shared.install()
        MainThreadMeter.shared.reset()
        var last: Paint?
        for hex in hexes {
            var paint = editor.previewedPaint(slot: slot) ?? Paint(hex: hex)
            if paint.isGradient, !paint.stops.isEmpty {
                paint.stops[0].hex = hex
            } else {
                paint.hex = hex
            }
            editor.previewSelectionPaint(slot: slot, paint: paint)
            last = paint
        }
        guard let last else { return }
        heldColorDrag = (slot, last)
        actionDetail = "\(hexes.count) live frames on \(slot.rawValue) over "
            + "\(editor.colorStyleSelection(slot: slot).count) layers, ending #\(last.hex.dropFirst()); "
            + MainThreadMeter.shared.report
    }

    /// Letting the same drag go: ONE undo step and ONE recents entry for every
    /// frame `holdColorDrag` pushed.
    private func releaseColorDrag(_ editor: EditorState) {
        guard let held = heldColorDrag else { return }
        heldColorDrag = nil
        editor.commitSelectionPaint(slot: held.slot, paint: held.paint)
        actionDetail = "let go on #\(held.paint.hex.dropFirst())"
    }

    /// The one Corner Radius row, dragged and let go: the same path the panel
    /// takes, so a walk proves the row a person pulls rather than a field.
    private func dragCornerRadius(_ editor: EditorState, through values: [CGFloat]) {
        let ids = editor.cornerRadiusSelection.layerIDs
        guard !ids.isEmpty, let last = values.last else { return }
        for radius in values { editor.previewCornerRadius(ids: ids, radius) }
        editor.commitCornerRadius(ids: ids, last)
    }

    private func dragStyleSlider(_ editor: EditorState, through values: [Double],
                                 apply: (inout LayerStyle, Double) -> Void) {
        let ids = editor.layerStyleSelection.layerIDs
        guard !ids.isEmpty else { return }
        for value in values {
            editor.previewLayerStyle(ids: ids) { apply(&$0, value) }
        }
        editor.commitLayerStyle(ids: ids)
    }

    private func requireEditor() throws -> EditorState {
        guard let editor else { throw Failure(description: "no editor is open; add an \"open\" step first") }
        return editor
    }

    private func requireWindow() throws -> NSWindow {
        guard let window else { throw Failure(description: "no editor window is open; add an \"open\" step first") }
        return window
    }

    /// The window a plain key press belongs to: the sheet on the editor when
    /// one is up, the editor itself otherwise. See the `.key` case for why.
    private func keyTarget() throws -> NSWindow {
        let editor = try requireWindow()
        return editor.attachedSheet ?? editor
    }

    /// One of the app's own windows, by title. Exact first, then a prefix, so
    /// "Untitled 1" finds "Untitled 1 (Next)".
    private func requireWindow(titled title: String) throws -> NSWindow {
        let open = NSApp.windows.filter(\.isVisible)
        guard let found = open.first(where: { $0.title == title })
                ?? open.first(where: { $0.title.hasPrefix(title) }) else {
            let names = open.map { $0.title.isEmpty ? "(untitled)" : $0.title }.joined(separator: ", ")
            throw Failure(description: "no window called \"\(title)\" is open; these are: \(names)")
        }
        return found
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
        case .window:
            return try requireCanvas().convert(windowPoint(at), from: nil)
        }
    }

    /// The same point in WINDOW coordinates, which is the space a drag is
    /// offered in. A window-space point is written the way a person reads the
    /// window — down from the top-left corner — and turned here into the
    /// bottom-left origin AppKit hands a destination.
    private func windowPoint(_ at: PlaytestPoint) throws -> CGPoint {
        guard case .window = at.space else {
            return try requireCanvas().convert(viewPoint(at), to: nil)
        }
        guard let content = try requireWindow().contentView else {
            throw Failure(description: "the window has no content view")
        }
        let y = content.isFlipped ? at.point.y : content.bounds.height - at.point.y
        return content.convert(CGPoint(x: at.point.x, y: y), to: nil)
    }

    /// The same point in DOCUMENT coordinates, which is the space a drop
    /// lands in.
    private func documentPoint(_ at: PlaytestPoint) throws -> CGPoint {
        switch at.space {
        case .document:
            return at.point
        case .view, .window:
            guard let viewport = try requireEditor().viewport else { throw Failure(description: "the editor has no viewport yet") }
            return viewport.documentPoint(fromView: try viewPoint(at))
        }
    }

    private func holds(_ condition: PlaytestCondition, editor: EditorState) -> Bool {
        switch condition {
        case .edgeMap: !editor.snappingEdgeMap.isEmpty
        case .captionField: window?.firstResponder is NSTextView
        case .tool(let tool): editor.activeTool == tool
        case .measureMode(let mode): editor.activeTool == .measure && editor.measureToolMode == mode
        // Read off the dock's own live frames, so "without scrolling" means
        // the section's whole box is inside the scrolling viewport rather than
        // its header having appeared at the bottom edge.
        case .sectionInView(let title):
            InspectorLayoutProbe.shared.measured
                .first { $0.title == title }
                .map { InspectorLayoutProbe.shared.isFullyVisible($0) } ?? false
        case .sectionHeaderInView(let title):
            InspectorLayoutProbe.shared.measured
                .first { $0.title == title }
                .map { InspectorLayoutProbe.shared.isHeaderVisible($0) } ?? false
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
            let down = type == .keyDown
            guard let event = keyEvent(key, flags: flags, down: down, in: window) else { continue }
            // The same press as the system builds it, for asking "is this a
            // shortcut?" See `matchingEvent` for why it takes two.
            let matcher = Self.matchingEvent(key, flags: flags, down: down) ?? event
            if type == .keyUp {
                window.sendEvent(event)
            } else if Self.isTyping(in: window, flags: flags, typed: event.charactersIgnoringModifiers) {
                // A letter typed into a field is TYPING, never a shortcut, and
                // the real app decides that before any key equivalent is
                // offered: measured on 2026-09-08 in a probe that was active
                // and key, T, X and ⇧M all went into the panel's W box and
                // none of the Text tool, the fill swap or the selection cycle
                // ran, while the very same presses fired all three with
                // nothing focused. Offering the key equivalents by hand skips
                // that rule, which is how a walk came to report that typing
                // into an inspector field switched tools. `ShortcutDiag`
                // (`--shortcut-diag`) is the run that settled it.
                window.sendEvent(event)
                takenBy = "the field being typed in"
            } else if window.performKeyEquivalent(with: matcher) {
                takenBy = "window"
            } else if NSApp.mainMenu?.performKeyEquivalent(with: matcher) == true {
                takenBy = "menu"
            } else {
                // Nothing claimed it as a shortcut, so it is ordinary typing,
                // or a press that happens to carry a modifier: ⇧↑ stepping a
                // number field, ⇧⌫, ⌥ plus a letter. AppKit walks the responder
                // chain with those after the key equivalents miss, and so must
                // this, or the press would silently vanish and a walk would
                // "prove" a feature broken that works by hand.
                window.sendEvent(event)
                takenBy = flags.isEmpty ? "window" : "responder chain"
            }
        }
        return takenBy
    }

    /// Whether this press is somebody typing rather than a shortcut, by the
    /// same rule the real app applies: a text field's editor has the keyboard,
    /// the press carries nothing but shift, and it would put a character in the
    /// box.
    ///
    /// Three conditions and each one earns its place.
    ///
    /// ⌘C over a field IS the shortcut in the real app, so a press carrying
    /// command, option or control goes on being offered to the key equivalents.
    /// Shift is the exception, because shift is how a capital letter gets into
    /// a name field rather than a way of asking for a command: measured on
    /// 2026-09-08 in an active, key probe, ⇧M with the panel's W box holding
    /// the keyboard put an "M" in the box and left the selection tool alone,
    /// exactly as plain T and X did, while the same press with nothing focused
    /// cycled the selection tool.
    ///
    /// ⏎ and ⎋ are shortcuts even mid-edit: a sheet with a text field in it
    /// answers Return with its default button while the caret is still in the
    /// box, which is what makes a dialog answerable without reaching for the
    /// mouse. Only a press that would INSERT something is typing, so Return,
    /// Tab, Escape, the arrows, delete and the function keys are all left
    /// alone — every one of them is a control character or sits in the
    /// function-key block, and none of them is a letter a tool answers to.
    private static func isTyping(in window: NSWindow, flags: NSEvent.ModifierFlags,
                                typed: String?) -> Bool {
        guard flags.subtracting(.shift).isEmpty else { return false }
        guard (window.firstResponder as? NSTextView)?.isFieldEditor == true else { return false }
        guard let typed, typed.unicodeScalars.count == 1, let scalar = typed.unicodeScalars.first
        else { return false }
        return !CharacterSet.controlCharacters.contains(scalar) && !(0xF700...0xF8FF).contains(scalar.value)
    }

    /// One key press, carrying what the keyboard would really have typed.
    ///
    /// The characters are not made up: CoreGraphics builds a real key event
    /// for this key and these modifiers, and the system fills in what the
    /// current layout types (⇧M types "M", ⇧4 types "$", and with ⌘ held the
    /// unshifted letter comes back while the shortcut-matching string stays
    /// shifted). That pair is then copied onto an event addressed to this
    /// window, because an event straight out of CoreGraphics belongs to no
    /// window and a text field will not type it.
    ///
    /// Both halves matter. Get the characters wrong and SwiftUI matches the
    /// wrong shortcut: a ⇧M that says it typed "m" fires the plain M command,
    /// which is how a walk came to "prove" the selection slot cycling that a
    /// person's keyboard could not (2026-09-03). Get the window wrong and
    /// ordinary typing stops landing in the inspector's fields.
    private func keyEvent(_ key: PlaytestKey, flags: NSEvent.ModifierFlags,
                          down: Bool, in window: NSWindow) -> NSEvent? {
        let typed = Self.typedCharacters(key, flags: flags, down: down)
        return NSEvent.keyEvent(
            with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: typed.characters,
            charactersIgnoringModifiers: typed.ignoringModifiers,
            isARepeat: false, keyCode: key.keyCode)
    }

    /// The same press as the system builds it, used only to ask the window and
    /// the menu bar whether this is a shortcut.
    ///
    /// It takes two events because neither one can do both jobs. A press built
    /// by hand is addressed to a window, so a text field will type it, but
    /// AppKit and SwiftUI will not match a chord against it properly: they
    /// read the key underneath the modifiers off the real event, and a
    /// hand-built one has no such thing, so ⇧M either misses every shortcut or
    /// lands on the plain M one. A press built by CoreGraphics carries the
    /// layout with it and matches exactly as a keyboard does, but it belongs
    /// to no window, so typing it puts nothing in a field.
    private static func matchingEvent(_ key: PlaytestKey, flags: NSEvent.ModifierFlags,
                                      down: Bool) -> NSEvent? {
        guard let source = CGEventSource(stateID: .privateState),
              let cg = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: down)
        else { return nil }
        cg.flags = CGEventFlags(rawValue: UInt64(flags.rawValue))
        return NSEvent(cgEvent: cg)
    }

    /// What the keyboard layout says this key and these modifiers type, asked
    /// of the system rather than guessed. Falls back to the layout table in
    /// `PlaytestKey` if CoreGraphics will not make an event.
    private static func typedCharacters(_ key: PlaytestKey, flags: NSEvent.ModifierFlags,
                                        down: Bool) -> (characters: String, ignoringModifiers: String) {
        if let real = matchingEvent(key, flags: flags, down: down),
           let characters = real.characters, let ignoring = real.charactersIgnoringModifiers,
           !characters.isEmpty, !ignoring.isEmpty {
            return (characters, ignoring)
        }
        let shifted = key.characters(with: flags.contains(.shift) ? [.shift] : [])
        return (shifted, shifted)
    }

    private func mouseEvent(_ type: NSEvent.EventType, at viewPoint: CGPoint, on view: NSView,
                            flags: NSEvent.ModifierFlags = [], clicks: Int = 1) -> NSEvent? {
        guard let window = view.window else { return nil }
        return NSEvent.mouseEvent(
            with: type, location: view.convert(viewPoint, to: nil), modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)
    }

    /// Turns the wheel over whatever scrolls behind `target`.
    ///
    /// A wheel event is what a person sends, so it is what this sends: the
    /// enclosing scroll view gets a real `scrollWheel(with:)`. Some SwiftUI
    /// scroll areas swallow a synthesised wheel, so if the clip view has not
    /// moved afterwards this scrolls it directly rather than reporting a pass
    /// for a walk that went nowhere. Either way it says which happened.
    private func scroll(from target: PanelTargetView, by points: Double) throws -> String {
        guard let scrollView = target.enclosingScrollView else {
            throw Failure(description: "\"\(target.name)\" is not inside anything that scrolls")
        }
        let clip = scrollView.contentView
        let start = clip.bounds.origin.y
        if let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                               wheel1: Int32(points.rounded()), wheel2: 0, wheel3: 0),
           let event = NSEvent(cgEvent: wheel) {
            scrollView.scrollWheel(with: event)
        }
        if abs(clip.bounds.origin.y - start) > 0.5 {
            return String(format: "wheel moved it %.0fpt", clip.bounds.origin.y - start)
        }
        // Down the list is +y in a flipped clip view and -y in one that is not,
        // which is the same direction the wheel means by a negative number.
        let step = clip.isFlipped ? -points : points
        let wanted = CGPoint(x: clip.bounds.origin.x, y: start + step)
        clip.scroll(to: wanted)
        scrollView.reflectScrolledClipView(clip)
        let delta = clip.bounds.origin.y - start
        return abs(delta) > 0.5
            ? String(format: "the wheel did nothing, so it was scrolled directly by %.0fpt", delta)
            : "IT DID NOT MOVE: already at the end, or nothing here scrolls"
    }

    // MARK: - Rendering

    /// The window's content drawn offscreen at 2x, so the picture matches
    /// what a person would see on a Retina display.
    private func snapshot(_ view: NSView, name: String) throws {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw Failure(description: "could not make a bitmap for \(name)")
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        drawScrollingPanels(in: view, into: rep)
        drawTitleBar(over: view, into: rep)
        drawTooltip(over: view, into: rep)
        fillBackground(of: view, into: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw Failure(description: "could not encode \(name).png")
        }
        try png.write(to: out.appendingPathComponent("\(name).png"))
    }

    /// Paints every scrolling panel back into the picture.
    ///
    /// SwiftUI puts a `ScrollView`'s content in a layer-backed subtree that
    /// AppKit's recursive draw does not reach, so `cacheDisplay` on the window's
    /// content view comes back with the whole properties dock missing — not
    /// white, but empty, which is why two snapshots either side of a panel
    /// scroll used to be byte-identical. Asked directly, the same views draw
    /// perfectly well, so each scrolling panel is drawn on its own and
    /// composited where it sits. The clip view is what gets asked: the scroll
    /// view itself draws nothing, and the clip view is also what bounds the
    /// picture to the rows actually on screen.
    private func drawScrollingPanels(in view: NSView, into rep: NSBitmapImageRep) {
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        for clip in scrollingContentViews(in: view) {
            // `visibleRect` is already what the ancestors have not clipped away,
            // so a list scrolled half out of the panel around it is drawn as the
            // half that shows rather than overflowing its own panel.
            let source = clip.visibleRect
            guard source.width > 1, source.height > 1,
                  let clipRep = clip.bitmapImageRepForCachingDisplay(in: source)
            else { continue }
            clip.cacheDisplay(in: source, to: clipRep)
            let image = NSImage(size: source.size)
            image.addRepresentation(clipRep)
            var rect = view.convert(source, from: clip)
            // The bitmap is bottom-up; a flipped view's rect is not.
            if view.isFlipped { rect.origin.y = view.bounds.height - rect.maxY }
            image.draw(in: rect)
        }
    }

    /// The clip view of every scroll view under `view`, outermost first, so a
    /// list nested inside a panel is painted over the panel it sits in.
    private func scrollingContentViews(in view: NSView) -> [NSView] {
        var found: [NSView] = []
        if let scroll = view as? NSScrollView, !scroll.contentView.isHidden {
            found.append(scroll.contentView)
        }
        for sub in view.subviews where !sub.isHidden && sub.alphaValue > 0 {
            found += scrollingContentViews(in: sub)
        }
        return found
    }

    /// The title bar, which is a sibling of the content view rather than part
    /// of it: the traffic lights and the panel toggle live there, so without
    /// this the top of every offscreen picture is an empty band.
    private func drawTitleBar(over view: NSView, into rep: NSBitmapImageRep) {
        guard let window = view.window, window.styleMask.contains(.titled),
              let bar = window.standardWindowButton(.closeButton)?.superview,
              !bar.isHidden, bar.bounds.width > 1, bar.bounds.height > 1,
              let barRep = bar.bitmapImageRepForCachingDisplay(in: bar.bounds),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        bar.cacheDisplay(in: bar.bounds, to: barRep)
        let image = NSImage(size: bar.bounds.size)
        image.addRepresentation(barRep)
        var rect = view.convert(bar.bounds, from: bar)
        // The bitmap is bottom-up; a flipped view's rect is not.
        if view.isFlipped { rect.origin.y = view.bounds.height - rect.maxY }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The window's own background, under everything drawn so far.
    ///
    /// A content view runs the full height of the window, so the band behind
    /// the title bar belongs to it, and nothing in the view tree paints there:
    /// left alone it comes out fully transparent, which reads as a white gap in
    /// any viewer. The same is true of the sliver a glass surface would have
    /// tinted. Painting the window's colour underneath is what a person sees.
    private func fillBackground(of view: NSView, into rep: NSBitmapImageRep) {
        guard let color = view.window?.backgroundColor,
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        color.setFill()
        // Under, not over: everything already drawn stays exactly as it is.
        view.bounds.fill(using: .destinationOver)
        NSGraphicsContext.restoreGraphicsState()
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
            let scale = window.backingScaleFactor
            // A window is photographed WITH anything hanging off it, which is
            // the only way a tooltip — a window of its own, hung on the one it
            // labels — is in the picture at all. So the frame to ask for is the
            // rectangle the family fills, not the parent's: ask for the
            // parent's and the capture is squeezed to fit it.
            let family = ([window] + (window.childWindows ?? [])).filter { $0.isVisible && $0.alphaValue > 0 }
            let bounds = family.dropFirst().reduce(window.frame) { $0.union($1.frame) }
            let config = SCStreamConfiguration()
            config.width = Int((bounds.width * scale).rounded())
            config.height = Int((bounds.height * scale).rounded())
            config.showsCursor = false
            config.captureResolution = .best
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let rep = NSBitmapImageRep(cgImage: image)
            if let png = rep.representation(using: .png, properties: [:]) {
                try png.write(to: out.appendingPathComponent("\(name)-sc.png"))
                let hung = family.count - 1
                note(0, "capture", "\(name)-sc.png \(image.width)x\(image.height)"
                    + (hung > 0 ? " (with \(hung) window\(hung == 1 ? "" : "s") hung on it)" : ""))
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
    /// One colour in the words a walk reads: the flat colour it stands for,
    /// and the kind of ramp when it is one. "none" is an answer too, and means
    /// the next box comes out an outline.
    private static func describe(paint: Paint?) -> String {
        guard let paint else { return "none" }
        return paint.isGradient ? "\(paint.hex) \(paint.kind.rawValue)" : paint.hex
    }

    /// What the right hand panel is saying it will do with the thing in the
    /// air, in the words its own border and drop line are drawing. This is the
    /// half of a drag a walk can record: the pointer's sign cannot be
    /// photographed, but the promise that decides it can be read.
    private func panelPromise() -> String {
        guard let editor, let offer = editor.panelDropOffer else {
            return "the panel says nothing"
        }
        switch offer {
        case .refuses:
            return "the panel says it will refuse this"
        case .accepts(let drop):
            guard let drop else { return "the panel will take it into a window of its own" }
            let name = editor.document?.layer(id: drop.targetID)?.name ?? "a layer"
            return switch drop {
            case .above: "the panel will put it in front of \"\(name)\""
            case .below: "the panel will put it behind \"\(name)\""
            case .inside: "the panel will put it inside \"\(name)\""
            }
        }
    }

    /// What the layers list is holding right now. Nothing on screen says this
    /// once the drop line has gone, so a walk that abandons a row drag reads it
    /// to prove the row was actually put down rather than merely stopped being
    /// drawn.
    private func rowInHand() -> String {
        guard let editor, let id = editor.layerRowInHand else {
            return "the list is holding no row"
        }
        let name = editor.document?.layer(id: id)?.name ?? "a layer"
        return "the list is STILL HOLDING \"\(name)\""
    }

    /// `extra` is whatever the step itself watched while it ran and nothing
    /// else can see afterwards, like what the grid did between two nudges of a
    /// pinch. It is merged over the state, so a step can name its own evidence.
    private func describe(extra: [String: Any] = [:]) -> [String: Any] {
        var state = describeState()
        for (key, value) in extra { state[key] = value }
        return state
    }

    private func describeState() -> [String: Any] {
        let began = CACurrentMediaTime()
        defer { MainThreadMeter.shared.exclude(CACurrentMediaTime() - began) }
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
                // placed by hand, so a walk can prove a drag landed. At the
                // MEASURED width, which is the label a person sees: the
                // model's own estimate is a generous guess and sits up to
                // 80pt further from the tail than the label does.
                let pill = annotation.measuredCaptionPillSize ?? annotation.estimatedCaptionSize
                let anchor = annotation.captionPillCenter(forPillSize: pill)
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
                // A ramp reads as one hex like any other colour, so the kind
                // is said out loud: otherwise a walk that pressed Linear in
                // the picker has no way to show that anything happened.
                let ramp = editor.selectionPaint(slot: slot).flatMap { paint in
                    paint.isGradient ? ", \(paint.kind.rawValue) ramp of \(paint.stops.count)" : nil
                } ?? ""
                return "\(slot.rawValue) \(body)\(ramp) ×\(selection.count)"
            }
        }()
        // What the type rows read for the picked layers, in the words the rows
        // show. With several picked this is what proves one pick reached all
        // of them, and it prints the same word the row does when they differ.
        let textRows: [String] = {
            let selection = editor.textSelection
            guard !selection.isEmpty else { return [] }
            func row<V: Hashable & Sendable>(_ name: String, _ reading: StyleReading<V>,
                                             _ text: (V) -> String) -> String {
                let body = reading.isMixed ? "mixed" : (reading.value.map(text) ?? "none")
                return "\(name) \(body) ×\(selection.count)"
            }
            return [row("font", selection.reading { $0.fontName }, { $0 }),
                    row("size", selection.number { $0.fontSize }, { "\(Int($0))" }),
                    row("weight", selection.reading { $0.weight }, { $0.rawValue }),
                    row("across", selection.reading { $0.usedAlignment }, { $0.rawValue }),
                    row("down", selection.reading { $0.usedVerticalAlignment }, { $0.rawValue })]
        }()
        // The same for the shape rows, plus which rows the picked shapes share
        // at all — a walk cannot photograph an absent row.
        let shapeRows: [String] = {
            let selection = editor.shapeSelection
            guard !selection.isEmpty else { return [] }
            func number(_ name: String, _ reading: StyleReading<CGFloat>) -> String {
                let body = reading.isMixed ? "mixed" : (reading.value.map { "\(Int($0.rounded()))" } ?? "none")
                return "\(name) \(body) ×\(selection.count)"
            }
            var rows = ["offers " + selection.rows.map(\.rawValue).joined(separator: ", ")]
            rows.append(number("thickness", selection.number { $0.strokeWidth }))
            rows.append(number("labelSize", selection.number { $0.captionFontSize }))
            return rows
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
                // The words themselves, so a walk can prove what a label says
                // without anybody having to read a picture.
                if case .text(let content) = layer.content {
                    line += " \(Int(content.fontSize))pt \"\(content.string)\""
                }
                if let annotation = layer.annotation {
                    line += " stroke \(Int(annotation.strokeWidth.rounded()))"
                }
                // How much a callout magnifies and what it is drawn in, so a
                // walk can prove what came out of a drag without reading a
                // picture.
                if let callout = layer.zoomCallout {
                    line += " \(ZoomCalloutBuilder.magnificationLabel(callout.magnification))"
                        + " \(callout.shape.rawValue)"
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
            // The tool settings capsule's measured size, so a walk can say in
            // numbers how much of the picture it covers rather than eyeballing
            // it. Zeros mean there is no capsule at all.
            "toolSettingsWidth": editor.toolSettingsSize.width,
            "toolSettingsHeight": editor.toolSettingsSize.height,
            // What the zoom readout is showing, as a whole percent, and the
            // document point in the middle of the picture. The two together
            // are how a walk proves a zoom kept its place instead of jumping
            // the picture somewhere else.
            "displayZoom": Int((editor.displayZoom * 100).rounded()),
            "viewCentre": editor.viewport.map { viewport in
                short(viewport.documentPoint(fromView: CGPoint(x: viewport.viewSize.width / 2,
                                                               y: viewport.viewSize.height / 2)))
            } ?? "none",
            // What the bucket and the fill shortcuts will paint with. The
            // swatches only appear for a tool that paints, so this is how a
            // walk proves the pair survived a spell under Select rather than
            // reading it off a picture that does not show it.
            "foregroundFill": editor.foregroundFillHex,
            "backgroundFill": editor.backgroundFillHex,
            "measureMode": editor.measureToolMode.rawValue,
            // What a half-placed caliper is still waiting for. A Distance
            // caliper takes three clicks, so a walk that clicks twice leaves
            // an empty `measures` list on purpose; this says so out loud.
            "measuring": canvas?.playtestMeasuringReport ?? "no canvas",
            "hint": editor.showsMeasureHint ? "\(editor.measureHintTitle ?? "") · \(editor.measureHintText)" : "none",
            "copied": editor.copyConfirmation.map { "\($0.title) · \($0.detail)" } ?? "none",
            "layers": layers.count,
            // Composites that have reached the canvas since the window opened.
            // Read it either side of a drag and divide by the time between the
            // two `describe` lines: that is how many pictures the drag actually
            // put on screen per second, which is the only honest answer to "is
            // this live?".
            "canvasFrames": editor.canvasFrameCount,
            // Whether Undo and Redo have anything to do, which is what the
            // Edit menu dims itself on and what a shortcut walk checks.
            "canUndo": editor.canUndo,
            "canRedo": editor.canRedo,
            // The picker's Recent row, newest first. A colour drag must leave
            // ONE entry here for the whole gesture rather than one per frame,
            // and this is what a walk reads to prove it.
            "recentColors": editor.recentColors.colors,
            // Whether this process has focus at all. It never does in a walk,
            // and that one fact is why most menu shortcuts cannot be pressed
            // in one. See `frozenMenuBar`.
            "appActive": NSApp.isActive,
            // The canvas's own size, so a walk can prove a number typed into
            // the Canvas section landed on the document rather than nowhere.
            "canvas": document.map { "\(Int($0.canvasSize.width))x\(Int($0.canvasSize.height))" } ?? "none",
            "measures": measures,
            "arrows": arrows,
            "textRows": textRows,
            "shapeRows": shapeRows,
            // The ONE Corner Radius row, in the words it shows. A rectangle
            // curving its own outline and a screenshot with its corners masked
            // off both land here, which is the point of the row.
            "cornerRadius": {
                let selection = editor.cornerRadiusSelection
                guard !selection.isEmpty else { return "none" }
                let reading = selection.reading
                let body = reading.isMixed
                    ? "mixed"
                    : (reading.value.map { "\(Int($0.rounded()))" } ?? "none")
                return "\(body) ×\(selection.count)"
            }(),
            "shapeSection": editor.shapeSelection.title,
            // What the toolbar swatch is showing: the outline and the inside
            // the tool in your hand would draw with. Painting a shape from the
            // right hand panel arms that tool, so this is what a walk reads to
            // prove the next shape comes out the colour just picked, and to
            // prove the swatch and the panel row never disagree.
            "toolPaint": Self.describe(paint: editor.activeToolPaint),
            // What the Zoom Callout tool is set to draw. A walk reads this to
            // prove the choice survives the drag and reaches the next callout.
            "calloutToolShape": editor.calloutToolShape.rawValue,
            // ...and how much it is set to magnify. A walk reads this beside
            // the callout's own magnification to prove the two are separate:
            // resizing a drawn callout must never move the tool's number.
            "calloutToolMagnification":
                ZoomCalloutBuilder.magnificationLabel(editor.calloutToolMagnification),
            "toolFillPaint": Self.describe(paint: editor.activeToolFillPaint),
            // The SAVED colour the tool is holding, outline and inside, or
            // "none". A tool holding Accent draws shapes that follow Accent
            // when it is edited later, which a colour on its own can never
            // show, so this is what a walk reads to prove the name carried
            // over and that a plain colour let go of it again.
            "toolStyle": editor.toolColorStyle(slot: .stroke)?.name ?? "none",
            "toolFillStyle": editor.toolColorStyle(slot: .fill)?.name ?? "none",
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
            // The marquee region's bounds in document points, or "none". A
            // marquee is a rectangle chosen by hand, so a walk reads this to
            // prove the corners landed exactly where the pointer went rather
            // than on something near it.
            "region": editor.selection.map {
                let box = $0.path.boundingBoxOfPath
                return "\(Int(box.minX)),\(Int(box.minY)) \(Int(box.width))x\(Int(box.height))"
            } ?? "none",
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
            // Which of the six align buttons are live. Inside a plain group an
            // axis can be dead: a piece already as wide as everything else in
            // the group has nowhere to go sideways, so those three dim.
            "alignAxes": LayerAlignment.allCases
                .filter { editor.canAlignSelection($0) }.map(\.rawValue),
            // Whether Layer ▸ Make Alternatives is there at all. That row is
            // absent rather than dimmed, and a walk cannot photograph an absent
            // row: the probe never comes to the front, so its menu bar reads
            // frozen. This is the same value the row's own `if` reads.
            "canMakeChoice": editor.canMakeChoice,
            "legend": editor.measureLegendEntries.map(\.label),
            "legendAnchor": editor.measureLegendAnchor.rawValue,
            "legendTopInset": editor.measureLegendTopInset,
            "inspector": editor.isLayersPanelVisible,
            // The dock's sections in draw order, with where each one sits in
            // the scrolling area: "Effects 612-812" reads as the section
            // starting 612 points down. A walk proves a section is reachable
            // from these numbers instead of from someone squinting at a
            // snapshot.
            "dockSections": InspectorLayoutProbe.shared.measured.map {
                "\($0.title) \(Int($0.frame.minY.rounded()))-\(Int($0.frame.maxY.rounded()))"
            },
            "dockViewport": Int(InspectorLayoutProbe.shared.viewportHeight.rounded()),
            // What the height budget did to each list: "Effects 129/129 floor
            // 129" reads as drawn/natural, and the floor it may never go under.
            "dockListRoom": InspectorLayoutProbe.shared.measured.compactMap { section in
                InspectorLayoutProbe.shared.listRoom[section.id].map {
                    "\(section.title) \(Int($0.drawn.rounded()))/\(Int($0.natural.rounded()))"
                        + ($0.needsForOpenPane.map { " needs \(Int($0.rounded()))" } ?? "")
                }
            },
            // The sections a person can see WHOLE without touching the scroll
            // wheel, which is the claim the panel order has to keep true.
            "dockInView": InspectorLayoutProbe.shared.measured
                .filter { InspectorLayoutProbe.shared.isFullyVisible($0) }.map(\.title),
            // ...and the weaker claim: the ones whose header is on screen, so
            // you at least know the section is there.
            "dockHeadersInView": InspectorLayoutProbe.shared.measured
                .filter { InspectorLayoutProbe.shared.isHeaderVisible($0) }.map(\.title),
            // What the panel last did about an effect you opened: the reveal
            // that keeps a chevron from putting its settings out of sight.
            "effectReveal": InspectorLayoutProbe.shared.effectReveal ?? "none yet",
            // ...and what it last did about the section a PICK brought up: the
            // reveal that keeps a click on a layer from leaving that layer's
            // own settings below the fold.
            "pickReveal": InspectorLayoutProbe.shared.pickReveal ?? "none yet",
            "tooltip": HintTooltipController.shared.visibleDescription ?? "none",
            "edgeMap": !editor.snappingEdgeMap.isEmpty,
            "firstResponder": window?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil",
            // The pointer's shape, so a walk can prove the cue appeared over a
            // handle and nowhere else.
            "cursor": Self.cursorName(),
            // ...and what the canvas thinks is under the pointer, which is the
            // other half: these two disagreeing means the cue was right and the
            // pointer did not follow it.
            "cue": canvas?.playtestPointerCue ?? "no canvas",
            // What the grid is drawing on the layers themselves, at this
            // instant: the zoom, the strength of every rung with a path, and
            // which side of the picture it is on. "nothing drawn" here is the
            // grid having gone out.
            "grid": canvas?.playtestGridReport ?? "no canvas",
            "guides": editor.playtestGuidesReport,
            // Where the grid counts from. The adjust bar stopped printing it
            // when it stopped explaining itself, so this is how a walk proves
            // the zero point landed where it was dragged.
            "gridStart": CanvasGridOriginLabel.text(editor.canvasGridOrigin),
            // The columns each screen is showing, whether they are actually on
            // the canvas layer, and how many a drag could catch — so one line
            // answers "does the pull match the picture" for the OTHER thing a
            // person might call a grid.
            "columns": canvas?.playtestColumnReport ?? "no canvas",
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
    /// are shared singletons, so identity is the whole test; the ones the
    /// canvas builds itself (resize, rotate, the selection crosshairs) are
    /// cached and registered by name when they are made.
    static func cursorName() -> String {
        let current = NSCursor.current
        let known: [(NSCursor, String)] = [
            (.openHand, "openHand"), (.closedHand, "closedHand"), (.arrow, "arrow"),
            (.crosshair, "crosshair"), (.iBeam, "iBeam"), (.pointingHand, "pointingHand"),
            (.dragCopy, "dragCopy"),
        ]
        if let stock = known.first(where: { $0.0 === current })?.1 { return stock }
        return CanvasCursor.name(of: current) ?? "other"
    }
}

/// Whether an animation is going to finish. One that repeats for ever, or for
/// a duration with no end, is decoration a walk should not sit and wait out.
private extension CAAnimation {
    var endsOnItsOwn: Bool {
        repeatCount.isFinite && repeatCount < .greatestFiniteMagnitude
            && repeatDuration.isFinite && repeatDuration < .greatestFiniteMagnitude
    }
}

/// How busy the main thread is after a step, from the main run loop's own
/// observer: total time on the main thread since the last `click`, how many
/// run-loop passes that took, and the longest single pass. A pass longer than
/// a frame (16ms) is a frame the app did not draw, which is what "sluggish"
/// means to a person clicking. The harness's own work (describing the editor,
/// rewriting the log) is subtracted, so the numbers are the app's alone.
///
/// `Scripts/playtest/select-click-perf-walk.json` is the walk that reads
/// these; the numbers it produced on 2026-09-03 are in its commit message.
@MainActor
final class MainThreadMeter {
    static let shared = MainThreadMeter()
    private var observer: CFRunLoopObserver?
    private var busy: CFTimeInterval = 0
    private var passes = 0
    private var longest: CFTimeInterval = 0
    private var activeSince: CFTimeInterval?
    private var excludedInPass: CFTimeInterval = 0
    /// Main thread work since the last time anyone asked. A `wait` step reads
    /// this every slice to tell a busy editor from a finished one.
    private var sinceAsked: CFTimeInterval = 0

    func install() {
        guard observer == nil else { return }
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.allActivities.rawValue, true, 0) { [unowned self] _, activity in
            let now = CACurrentMediaTime()
            switch activity {
            case .afterWaiting, .entry:
                if activeSince == nil { activeSince = now; excludedInPass = 0 }
            case .beforeWaiting, .exit:
                if let since = activeSince {
                    let d = max(0, now - since - excludedInPass)
                    busy += d
                    sinceAsked += d
                    passes += 1
                    longest = max(longest, d)
                    activeSince = nil
                    excludedInPass = 0
                }
            default: break
            }
        }
        self.observer = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    func reset() {
        busy = 0; passes = 0; longest = 0
        activeSince = CACurrentMediaTime()
        excludedInPass = 0
        sinceAsked = 0
    }

    /// How much the app did on the main thread since this was last asked, and
    /// the counter starts again. Only whole run loop passes count, so work the
    /// harness is in the middle of doing right now is not in the answer.
    func takeBusy() -> CFTimeInterval {
        let answer = max(0, sinceAsked)
        sinceAsked = 0
        return answer
    }

    /// Time the harness itself spent on the main thread, which is not the
    /// app's cost: taken off the total and off the pass it happened in.
    func exclude(_ seconds: CFTimeInterval) {
        if activeSince != nil { excludedInPass += seconds } else { busy -= seconds; sinceAsked -= seconds }
    }

    var report: String {
        var total = busy
        if let since = activeSince { total += max(0, CACurrentMediaTime() - since - excludedInPass) }
        return String(format: "mainBusy %.1fms over %d passes, longest %.1fms", total * 1000, passes, longest * 1000)
    }
}

/// What the yellow guides did across ONE drag.
///
/// A snap that is showing is a snap you get, so the telling number is not how
/// many lines a drag passed — a walk over a dense screenshot honestly crosses
/// dozens — but how often the answer WENT BACK on itself: took a line, took
/// another, then returned to the first. That is the flicker, and on a fixed
/// hold it is zero however much the hand shakes.
private struct SnapGuideTally {
    /// What these lines are called in the log: the yellow guides, or the grid
    /// lines a drag is standing on. Same counting, different meaning.
    let label: String
    private var caught = 0
    private var released = 0
    private var changes = 0
    private var reversals = 0
    private var showing: Bool?
    /// The readings so far, only where they differ from the one before.
    private var distinct: [String] = []

    init(label: String = "guides") { self.label = label }

    mutating func record(_ guides: (x: CGFloat?, y: CGFloat?)) {
        let isShowing = guides.x != nil || guides.y != nil
        if let showing, showing != isShowing {
            if isShowing { caught += 1 } else { released += 1 }
        }
        showing = isShowing

        func read(_ v: CGFloat?) -> String { v.map { String(format: "%.1f", $0) } ?? "-" }
        let reading = read(guides.x) + "/" + read(guides.y)
        guard distinct.last != reading else { return }
        if !distinct.isEmpty {
            changes += 1
            // Only a return to a LINE counts: letting go at the end of a pass
            // and catching nothing again is what a pass is supposed to do.
            if isShowing, distinct.count > 1, distinct[distinct.count - 2] == reading {
                reversals += 1
            }
        }
        distinct.append(reading)
    }

    var reading: String {
        "\(label) caught \(caught), let go \(released), changed \(changes), "
            + "went back on themselves \(reversals), last \(distinct.last ?? "-")"
    }
}
#endif
