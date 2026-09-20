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
import AVFoundation
import AppKit
import ScreenCaptureKit
import PhotonzCore
import PhotonzMedia
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

    /// Every editor a window has made, picture or no picture. A guide can open
    /// an EMPTY window on purpose (the card offering the ways to get a picture
    /// in only exists there), and `readyEditors` leaves that window out because
    /// it insists on a document and a viewport.
    static var allEditors: [EditorState] { editors }

    private static var recordings: [VideoEditorState] = []

    /// A recording's window announces itself the same way a picture editor
    /// does. It is a different kind of window entirely (one picture and one
    /// floating controller, no canvas and no layers), and the video guides
    /// teach in it, so a walk has to be able to find one.
    static func register(_ recording: VideoEditorState) {
        guard AppInfo.flavor == .probe else { return }
        if !recordings.contains(where: { $0 === recording }) { recordings.append(recording) }
    }

    /// Every recording window that is loaded and drivable, oldest first.
    static var readyRecordings: [VideoEditorState] {
        recordings.filter { $0.isReady && $0.hostWindow != nil }
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
    /// A colour row remembered exactly as the row on screen holds it, so a walk
    /// can paint through it after picking something else. See
    /// `PlaytestAction.holdColorRow`.
    private var heldColorRow: ColorTarget?
    /// The recording's window a video guide opened, when the walk is in one.
    /// Nil in every other walk, and the two are never both set: a window holds
    /// a picture or a recording, never both.
    private var recording: VideoEditorState?
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
    /// Guide steps this walk says have nothing to ring, as "<guide>/<step>".
    /// Named in the walk's setup block, and turned into the opposite check.
    private var expectNoControl: Set<String> = []

    /// How a `wait` step spends its seconds: watching for the editor to go
    /// quiet, or sleeping the whole number the way walks used to.
    /// `PHOTONZ_PLAYTEST_PACE=full` puts every wait back on the clock, which is
    /// how a walk that has turned flaky says whether the pacing is what moved
    /// under it.
    private let pace = PlaytestSettle.named(ProcessInfo.processInfo.environment["PHOTONZ_PLAYTEST_PACE"])
    /// Seconds of sleeping the watched waits gave back over this walk, so the
    /// saving is on the record rather than inferred from a stopwatch.
    private var pacedAway: Double = 0
    /// What every attempt to photograph the real window came back with, and
    /// therefore whether this run has a picture an audit may ship. The rule it
    /// is judged by lives in `PlaytestCaptureLedger`, where it is unit tested.
    private var captures = PlaytestCaptureLedger()
    /// True when this walk went ahead with the screen LOCKED because nothing in
    /// it looks a control up through accessibility, which is the half of the
    /// walk set a lock cannot touch (`PlaytestLockSafety`). Such a run is a
    /// real answer about the app, and the pictures it takes are the real
    /// window; it is only labelled, not withheld.
    private var ranLockSafe = false

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
        // The pointer starts nowhere. Whatever the last walk in this process
        // was resting on is gone with its window, so there is nothing to leave.
        PlaytestPointer.forget()
        // Before anything is driven: a locked screen strips the NAME off every
        // control, and finding a control by name is how a walk does anything at
        // all, so whatever this run found would be a fact about the lock and
        // not about the app (`PlaytestScreenState`). Stop here rather than
        // spend five seconds producing an answer nobody may use.
        if PlaytestScreenState.isLocked {
            // ...unless this walk never asks for a name. Half the walk set
            // clicks points, drags, presses keys, photographs the window and
            // finds panel controls through the app's own register of them, and
            // a lock touches none of that. Those walks run, so a task that
            // lands while the Mac is locked still has a picture of the app to
            // show for itself (`PlaytestLockSafety`).
            if PlaytestLockSafety.canRunLocked(script.steps) {
                ranLockSafe = true
                note(0, "start", "the screen is LOCKED, and nothing in this walk looks a control "
                    + "up by name, so it runs: the app is drawn, driven and photographed normally. "
                    + PlaytestLockSafety.pictureLabel)
            } else {
                guard PlaytestScreenState.isAllowedAnyway else {
                    finish(status: PlaytestScreenState.lockedStatus, steps: 0,
                           error: PlaytestLockSafety.refusal(for: script.steps)
                               ?? PlaytestScreenState.lockedExplanation)
                    return
                }
                note(0, "start", PlaytestScreenState.allowedAnywayNote)
            }
        }
        // Watching the main thread from step ZERO. A `wait` judges the editor
        // finished from two signals, and one of them is this meter; it used to
        // be installed by the first press or drag, so every wait before that —
        // the wait after `blank`, the wait after the first key — read "mainBusy
        // 0.0ms over 0 passes" and went quiet after 0.1s no matter how hard the
        // app was working. That is a walk reading the dock while it is still
        // being built, which is the whole of the flake this was written for.
        MainThreadMeter.shared.install()
        MainThreadMeter.shared.reset()
        // Whatever the walk said it needs, before step one — and, however this
        // run ends, everything it borrowed goes back.
        do {
            let said = try setupRunner.perform(script.setup, besides: scriptURL)
            note(0, "setup", said)
        } catch {
            finish(status: "failed", steps: 0, error: "setup: \(error)")
            return
        }
        // Nothing an earlier walk in this probe saw counts against this one.
        TutorialController.shared.clearAnchorVerdicts()
        expectNoControl = Set(script.setup.expectNoControl)
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
        // Every step of every guide this walk drove had to point at a control
        // that was really on screen. A step that pointed at nothing fails the
        // walk here even when the walk itself never looked, which is the
        // backstop under the check made at each step as the walk lands on it.
        if let said = guideAnchorReading() { note(completed, "done", said) }
        if let missing = guidePointedAtNothing() {
            note(completed, "done", "FAILED: \(missing)")
            finish(status: "failed", steps: completed, error: missing)
            return
        }
        finish(status: "ok", steps: completed, error: nil)
    }

    /// How many of the steps this walk drove were really judged, for the log.
    /// A guide whose window stayed covered draws nothing and finds nothing, and
    /// a walk that checked no steps at all should say so rather than read as a
    /// clean run.
    private func guideAnchorReading() -> String? {
        let verdicts = TutorialController.shared.anchorVerdictsSoFar
        guard !verdicts.isEmpty else { return nil }
        let found = verdicts.filter(\.resolved).count
        let unjudged = verdicts.filter { !$0.resolved && $0.shownSeconds < TutorialAnchorAudit.grace }
        return "guide steps that found their control: \(found) of \(verdicts.count)"
            + (unjudged.isEmpty ? "" : "; \(unjudged.count) never on screen long enough to judge ("
               + unjudged.map { "\($0.guide)/\($0.step)" }.joined(separator: ", ") + ")")
    }

    /// What a guide this walk drove pointed at and could not find, or nil when
    /// every step found its control.
    private func guidePointedAtNothing() -> String? {
        let judged = TutorialController.shared.anchorVerdictsSoFar
            .filter { !expectNoControl.contains("\($0.guide)/\($0.step)") }
        let problems = TutorialAnchorAudit.problems(
            in: judged, namesOnScreen: TutorialAnchorRegistry.shared.liveNames)
        guard !problems.isEmpty else { return nil }
        return "a guide points at a control that is not there: "
            + problems.joined(separator: "; ")
    }

    /// How long a step gets to produce its control once the walk has landed on
    /// it. The rule's own grace, and a second on top for a panel section that
    /// arrives with a selection or has to be scrolled to.
    private static let anchorGrace = TutorialAnchorAudit.grace + 1.0

    /// The step a walk has just landed on has to be pointing at something real.
    /// Waits out the grace, then fails naming the guide, the step and the name
    /// nothing carries, so the fix needs no reading of the framework.
    private func requireStepFoundItsControl() async throws {
        let controller = TutorialController.shared
        guard let run = controller.run else { return }
        // The probe's windows are invisible and never active, so the window a
        // guide is teaching in can be sitting behind whatever else is on the
        // machine. A guide over a covered window draws nothing on purpose, the
        // same as it would for a person who buried the window, so it is put in
        // front first: the check is about the control, not about what else is
        // open.
        controller.guideWindow?.orderFrontRegardless()
        // A step the walk SAID has nothing to ring: the check turns around.
        if expectNoControl.contains("\(run.guide.id)/\(run.step.id)") {
            await sleep(Self.anchorGrace)
            guard !controller.currentStepFoundItsControl else {
                throw Failure(description: "this walk says \(run.guide.id) step \(run.step.id) "
                    + "has nothing to ring, and it rings \(run.step.anchor.name); "
                    + "take it out of the walk's expectNoControl")
            }
            note(0, "expectNoControl",
                 "\(run.guide.id)/\(run.step.id) points at \(run.step.anchor.name), "
                 + "which is not there, as the walk said")
            return
        }
        let deadline = Date().addingTimeInterval(Self.anchorGrace)
        while !controller.currentStepFoundItsControl {
            guard Date() < deadline else {
                let live = controller.anchorVerdictsSoFar.last {
                    $0.guide == run.guide.id && $0.step == run.step.id
                }
                let verdict = TutorialAnchorVerdict(
                    guide: run.guide.id, step: run.step.id, anchor: run.step.anchor,
                    resolved: false,
                    shownSeconds: max(live?.shownSeconds ?? 0, TutorialAnchorAudit.grace))
                let said = TutorialAnchorAudit.problems(
                    in: [verdict], namesOnScreen: TutorialAnchorRegistry.shared.liveNames)
                throw Failure(description: said.joined(separator: "; "))
            }
            await sleep(0.05)
        }
    }

    // MARK: - Output

    /// Empties the folder this run writes into, BEFORE it writes anything.
    ///
    /// Everything left here is read afterwards as this run's: an audit ships a
    /// real `<name>-sc.png` picked out of this folder by name. A run used to
    /// delete only `done.json`, so a walk that stopped at step 17 sat among the
    /// pictures of a healthier run days earlier with nothing to tell them
    /// apart, and the picture an audit shipped could be of an app that worked.
    ///
    /// How much of the folder this run may claim is decided in
    /// `PlaytestOutputFolder`, where it is unit tested: its own folder under
    /// the scratch root goes whole, a folder shared with anything else loses
    /// only the files a run writes under a fixed name.
    private func prepareOutput() {
        let fm = FileManager.default
        try? fm.createDirectory(at: out, withIntermediateDirectories: true)
        let entries = (try? fm.contentsOfDirectory(atPath: out.path)) ?? []
        let leftovers = PlaytestOutputFolder.leftovers(in: out, named: entries)
        for name in leftovers {
            try? fm.removeItem(at: out.appendingPathComponent(name))
        }
        // Said in the log's FIRST line, before the script is even parsed, so a
        // walk too broken to run still says on the record that what is in its
        // folder is its own.
        if let said = PlaytestOutputFolder.clearedSaid(count: leftovers.count, in: out) {
            note(0, "output", said)
        }
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
        // A screen that locked WHILE the walk ran takes the answer with it,
        // whichever way the walk was going to land. That is how the 20:42 sweep
        // on 2026-09-14 turned into nineteen failures: it started on an unlocked
        // screen and was four minutes in when the Mac locked. So the verdict is
        // re-read here as well as before step one, and a locked run reports
        // neither pass nor failure.
        var status = status
        var error = error
        // Whether the screen was locked is recorded either way. Only the
        // VERDICT is withheld, and only when nobody asked for this run on
        // purpose (`PlaytestScreenState.isAllowedAnyway`).
        let locked = status == PlaytestScreenState.lockedStatus || PlaytestScreenState.isLocked
        if locked, !PlaytestScreenState.isAllowedAnyway, !ranLockSafe,
           status != PlaytestScreenState.lockedStatus {
            status = PlaytestScreenState.lockedStatus
            error = PlaytestScreenState.lockedExplanation
                + (error.map { " (what it had got to: \($0))" } ?? "")
        }
        // A walk that asked for a photograph of the window, could have taken
        // one, and did not, FAILS. Until 2026-09-15 a refused capture was a log
        // line and nothing else: the walk stayed green, the offscreen drawing
        // was written under the name the audit copies, and two mornings of
        // audits carried drawings of the window in place of the window with
        // nothing in the run to say so. Withheld in the one case where no
        // picture was ever possible, which is this copy of the app holding no
        // Screen Recording grant. A locked screen is NOT such a case: it still
        // photographs fine, it only stops control names arriving
        // (`PlaytestScreenState`).
        let granted = CGPreflightScreenCaptureAccess()
        if status == "ok", let missed = captures.failure(granted: granted) {
            status = "failed"
            error = missed
        }
        // Anything the setup lent goes back first, so a walk that failed
        // halfway leaves nothing of its own in a person's Screenshots folder.
        if let returned = setupRunner.returnCaptures() { note(steps, "setup", returned) }
        if let cleared = setupRunner.clearScratch() { note(steps, "setup", cleared) }
        // Then every remembered setting, so the walk after this one starts from
        // the machine this one did rather than from whatever this one left.
        note(steps, "setup", setupRunner.restoreSettings())
        if let flags = setupRunner.restoreFlags() { note(steps, "setup", flags) }
        if let shelf = setupRunner.restoreSharedShelf() { note(steps, "setup", shelf) }
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
        if locked { done["screenLocked"] = true }
        // What this run photographed, by file name, plus the one line that says
        // it in words, so whoever writes the audit can see at a glance whether
        // there is a real picture of the app to ship or only a drawing of one.
        done["captures"] = captures.written
        // A picture taken under a lock is a real picture of the window and says
        // so with the label that also says what it costs, so nothing shows a
        // dimmed colour or a missing tutorial card as if it were the app on an
        // ordinary day.
        var said = captures.report(granted: granted)
        if locked, !captures.written.isEmpty {
            said += " " + PlaytestLockSafety.pictureLabel
            done["pictureLabel"] = PlaytestLockSafety.pictureLabel
        }
        done["capturesSaid"] = said
        if locked { done["lockSafe"] = ranLockSafe }
        if !captures.refusals.isEmpty { done["capturesRefused"] = captures.refusals }
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

    /// What the four corners of a picture a walk just wrote are, and whether
    /// they are what the walk claimed.
    ///
    /// The corners are where a canvas that should have been left out shows up,
    /// and where no drawing ever reaches. Read off the FILE rather than off the
    /// render that made it, because a format that cannot hold transparency
    /// quietly fills it in and that is the thing worth catching.
    private func cornersOf(_ data: Data, named file: String,
                           claim: PictureCorners?) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure(description: "\(file) could not be read back to check its corners")
        }
        let width = image.width, height = image.height
        let spots = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
        let alphas = spots.map { alpha(of: image, x: $0.0, y: $0.1) }
        let found: PictureCorners? = alphas.allSatisfy { $0 == 0 } ? .empty
            : alphas.allSatisfy { $0 == 255 } ? .painted : nil
        let said: String
        switch found {
        case .empty: said = "nothing behind the drawing"
        case .painted: said = "a background behind the drawing"
        case nil: said = "corners \(alphas.map(String.init).joined(separator: "/")) opaque"
        }
        if let claim, claim != found {
            throw Failure(description: "\(file) was to have \(claim == .empty ? "nothing" : "a background") "
                          + "behind the drawing in every corner, and it has \(said)")
        }
        return said
    }

    /// How opaque one pixel of `image` is, counting y from the TOP the way the
    /// document counts. One pixel is drawn, not the whole picture: a 12
    /// megapixel export would be 48 MB of buffer to read four numbers.
    private func alpha(of image: CGImage, x: Int, y: Int) -> Int {
        var pixel: [UInt8] = [0, 0, 0, 0]
        pixel.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: 1, height: 1,
                                          bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)
                                              ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            // Core Graphics draws from the bottom up, so the row wanted is
            // counted back from the far side.
            context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y),
                                           width: image.width, height: image.height))
        }
        return Int(pixel[3])
    }

    // MARK: - Steps

    private func perform(_ step: PlaytestStep, number: Int) async throws {
        switch step {
        case .blank(let canvas, let size, let card, let pixelScale):
            try await blank(canvas: canvas, window: size, card: card, pixelScale: pixelScale,
                            number: number)

        case .open(let file, let size):
            let url = try fileURL(file)
            try await open(url, size: size, number: number)

        case .wait(let seconds, let onTheClock):
            // On the clock, the whole time is spent: a walk waiting out
            // something that leaves BY ITSELF is not waiting for the app to
            // finish anything, and an app with nothing to do goes quiet in a
            // tenth of a second.
            let said: String
            if onTheClock {
                await sleep(seconds)
                said = "\(seconds)s on the clock, spent in full"
            } else {
                said = await settle(for: seconds)
            }
            note(number, step.name, "\(said); \(MainThreadMeter.shared.report)")

        case .key(let key, let modifiers):
            // A sheet is a window of its own sitting on the editor's, and it is
            // the one holding the keyboard while it is up: a person answering
            // "Turn this shape into a picture?" with ⏎ is pressing the sheet's
            // default button, not typing at the canvas. Sending the press to
            // the editor instead did nothing at all, so a walk could raise a
            // question, "answer" it, and carry on reporting passes over a
            // document that never changed. Found on 2026-09-08.
            let window = try keyTarget(key)
            // Look the item up BEFORE the press: after it, an item that has
            // just been ticked or unticked reports its new state and the log
            // describes the wrong thing.
            let destination = modifiers.isEmpty ? nil : Self.menuItem(carrying: key, modifiers: modifiers)
            let takenBy = press(key, modifiers: modifiers, in: window)
            await sleep(0.05)
            try await requireAnsweredSheet(key, modifiers: modifiers, aimedAt: window, takenBy: takenBy)
            let chord = "\(modifiers.map(\.rawValue).joined(separator: "+"))\(modifiers.isEmpty ? "" : "+")\(key.name)"
            // A plain press usually just goes to the window, and saying so
            // adds nothing. When something else took it — the field being
            // typed in, or a sheet's default button — the walk's log has to
            // say which, or a press that answered a question reads exactly
            // like one that went nowhere.
            var detail = modifiers.isEmpty && takenBy == "window"
                ? chord : "\(chord) taken by \(takenBy)"
            // "taken by menu" on its own has read like a pass for chords that
            // did nothing at all, which is how ⌘Z came to look checked when it
            // was not. Name the item and say when there is nothing behind it.
            //
            // The warning cannot hang off "taken by menu", which is the one
            // case where it is not needed: a DEAD item does not take the press
            // at all. `NSApp.mainMenu.performKeyEquivalent` returns false for
            // it, so the press falls through to the responder chain and the
            // line read "command+z taken by responder chain" with nothing
            // more — which is exactly what sent two runners hunting a panel
            // bug that was never there (2026-09-12, 2026-09-16). So the item
            // is named however the press was routed.
            if let destination {
                if destination.item.action == nil {
                    detail += " (\(destination.path) carries this chord, but that item is dimmed and"
                        + " empty, so the MENU did not run: \(Self.frozenMenuBar)"
                        + " Whatever this press did came from the window itself, and for the command"
                        + " use an `action` step.)"
                } else if takenBy == "menu" {
                    detail += " (\(destination.path), which ran)"
                } else {
                    detail += " (\(destination.path) carries this chord and is live, but \(takenBy)"
                        + " took the press first)"
                }
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
                // The item is dead because of how a WALK is launched, not
                // because of anything the app did: the same item is live the
                // moment a person has the window. So stopping here told a walk
                // nothing it could act on, and every walk that reached for
                // ⌘Z failed on the same macOS fact. Where the chord has a
                // stand-in, run what the press meant and say so in one line
                // nobody can misread as the press having worked.
                guard let standIn = PlaytestMenuStandIn.action(for: key, modifiers: modifiers) else {
                    throw Failure(description: "\(chord) is \(destination.path), but that item has no action behind it, "
                        + "so pressing it does nothing, and no stand-in is written down for this chord. "
                        + "\(Self.frozenMenuBar) "
                        + "Use an `action` step for the outcome and keep a `key` step if you want the press on record, "
                        + "or add the chord to PlaytestMenuStandIn so every walk gets it.")
                }
                note(number, step.name,
                     "\(chord) is \(destination.path). THE PRESS DID NOT RUN IT: \(Self.frozenMenuBar) "
                     + "The item carries the chord, so the walk ran what the press meant, `action \(standIn.rawValue)`, "
                     + "directly instead. This says nothing about whether the menu would be live for a person.")
                try await perform(.action(standIn), number: number)
                return
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
            let window = try appKeyTarget()
            let flags = eventFlags(modifiers)
            for down in [true, false] {
                guard let event = keyEvent(key, flags: flags, down: down, in: window) else { continue }
                NSApp.sendEvent(event)
            }
            await sleep(0.2)
            note(number, step.name, "\(Self.chord(key, modifiers)) sent through the app",
                 state: describe())

        case .move(let target, let modifiers):
            let canvas = try requireCanvas()
            let flags = eventFlags(modifiers)
            // Where the pointer is going, and what to call the place in the
            // log. A control is found through the app's own register, and
            // scrolled to if the dock has it below the fold, exactly as a
            // `press` finds one — so a walk resting on something whose words
            // changed fails with the list of what IS on screen rather than
            // coming to rest beside it and proving nothing.
            let place: String
            let inWindow: CGPoint
            switch target {
            case .point(let at):
                inWindow = canvas.convert(try viewPoint(at), to: nil)
                place = "to \(short(at.point)) \(at.space.rawValue) = view \(short(try viewPoint(at)))"
            case .control(let name, let row):
                let (found, effort) = try await reachableTarget(name, in: row)
                let settledTarget = await settled(found, named: name, in: row).target
                guard let itsWindow = settledTarget.window, itsWindow === (try requireWindow()) else {
                    throw Failure(description: "the control \"\(settledTarget.name)\" is not in the "
                        + "editor window, so a move cannot reach it; use a \"hover\" step with a "
                        + "\"window\" for a control in one of the app's other windows")
                }
                inWindow = settledTarget.point
                let where_ = settledTarget.detail.isEmpty ? "" : " in \(settledTarget.detail)"
                place = "onto \"\(settledTarget.name)\"\(where_) at window \(short(settledTarget.point))"
                    + (effort.isEmpty ? "" : "; \(effort)")
            }
            // The canvas learns about held modifiers from `flagsChanged`, not
            // from the mouse event, so a walk that wants ⌥ held while the
            // pointer rests has to put it where the real key would have left
            // it. Setting it here and letting `mouseMoved` read it lands the
            // canvas in the same state a person holding ⌥ would.
            canvas.pointerModifiers = flags
            let inCanvas = canvas.convert(inWindow, from: nil)
            if let event = mouseEvent(.mouseMoved, at: inCanvas, on: canvas, flags: flags) {
                canvas.mouseMoved(with: event)
            }
            // The canvas works out for itself what a pointer over IT means.
            // What is drawn OVER the canvas — the line at the foot of it, a
            // tool chip, a row in a panel — reacts through `.onHover`, and no
            // synthesized event on this machine reaches that, so the pointer
            // runs those closures itself. See `PlaytestPointer`.
            let pointer = window.map { PlaytestPointer.rest(at: inWindow, in: $0) }
            await sleep(0.05)
            let held = modifiers.isEmpty ? "" : " holding " + modifiers.map(\.rawValue).joined(separator: "+")
            note(number, step.name, place + held + (pointer.map { "; \($0)" } ?? ""))

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
            // A control that reacts to the pointer resting on it does so
            // through `.onHover`, which no synthesized event reaches, so this
            // step moves the walk's pointer as `move` does as well as raising
            // the tooltip.
            let pointer = PlaytestPointer.rest(at: location, in: window)
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
            note(number, step.name,
                 "\(place) via \(path) events: \(controller.visibleDescription ?? "no tooltip"); \(pointer)",
                 state: describe())

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

        case .drag(let from, let to, let steps, let modifiers, let halfway, let hold,
                   let readout, let wobble, let cancel, let showsBox):
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
                // Changing your mind half way, with the button still down.
                // Handed to the canvas the way AppKit hands a key to whatever
                // holds the keyboard, and then the travel CARRIES ON, because
                // half of what Escape promises is that the rest of the drag
                // does nothing.
                if cancel, i == max(1, steps / 2),
                   let window = canvas.window,
                   let key = keyEvent(.escape, flags: [], down: true, in: window) {
                    canvas.keyDown(with: key)
                    await sleep(0.05)
                }
            }
            // Anything that lives only while the button is down — the yellow
            // snap guide, a live preview — has to be photographed here.
            var held = ""
            if let hold, let window = try? requireWindow(), let content = window.contentView {
                try snapshot(content, name: hold)
                await screenCapture(window, name: hold)
                held = ", held \(hold).png"
            }
            // The numbers the drag is carrying, read with the button STILL
            // DOWN. After the picture, so a walk that fails this claim has
            // already photographed what it is complaining about.
            var said = ""
            if let readout {
                said = ", " + (try checkDragReadout(says: readout, absent: false))
            }
            // The box the canvas is outlining for the container in hand, read
            // with the button still down and settled against where the thing
            // actually lands, once it is up. See `checkResizeBox`.
            let outlined = canvas.liveResizeBox
            let resized = canvas.resizeDrag?.layerID
            // The pointer's shape WHILE the button is down: the only moment a
            // closed-hand grab cue exists, and a walk cannot photograph it.
            let heldCursor = Self.cursorName()
            if let event = mouseEvent(.leftMouseUp, at: b, on: canvas, flags: laterFlags) { canvas.mouseUp(with: event) }
            await sleep(0.05)
            var boxed = ""
            if let showsBox {
                boxed = ", " + (try checkResizeBox(outlined: outlined, of: resized,
                                                   expected: showsBox))
            }
            var keys = ""
            if let later = halfway {
                func spell(_ list: [PlaytestModifier]) -> String {
                    let names: [String] = list.map { $0.rawValue }
                    return names.isEmpty ? "none" : names.joined(separator: "+")
                }
                keys = ", keys " + spell(modifiers) + " then " + spell(later)
            }
            note(number, step.name,
                 "\(short(from.point)) to \(short(to.point)) \(from.space.rawValue)\(held)\(keys)\(said)\(boxed)"
                     + "\(cancel ? ", called off with Escape half way and carried on to the end" : ""), "
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
            // What TYPING costs, from the key landing to the app standing
            // still. Zeroed here so the `wait` right after a `type` step
            // reports the keystroke's own main-thread cost and nothing else:
            // it used to carry everything since the last press or action,
            // which on a walk that photographs the window first meant the
            // screen capture's own 300ms read as the keystroke's
            // (`typing-in-the-find-field-does-not-freeze-a-long`).
            MainThreadMeter.shared.install()
            MainThreadMeter.shared.reset()
            ViewBuildMeter.shared.reset()
            field.insertText(text, replacementRange: field.selectedRange())
            await sleep(0.05)
            note(number, step.name, "\"\(text)\" into \(type(of: field)); "
                + ViewBuildMeter.shared.report + "; " + MainThreadMeter.shared.report)

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

        case .toolFlyout(let tool, let choose, let ticked):
            _ = try requireEditor()
            let probe = ToolModeFlyoutProbe.shared
            guard let rows = probe.rows(of: tool), !rows.isEmpty else {
                let seen = probe.tools
                throw Failure(description: "no tool called \"\(tool)\" is keeping a list in its own button; "
                    + "the ones that are: " + (seen.isEmpty ? "none" : seen.joined(separator: ", ")))
            }
            func describeRow(_ row: ToolFlyoutRow) -> String {
                var words = row.title
                if row.isLive { words += " (ticked)" }
                if row.isCommand { words += " (command)" }
                if !row.isEnabled { words += " (greyed)" }
                return words
            }
            let reading = rows.map(describeRow).joined(separator: ", ")
            let live = rows.first(where: \.isLive)?.title ?? "nothing"
            if let ticked, live != ticked {
                throw Failure(description: "\(tool)'s list has \(live) ticked and it should be \"\(ticked)\"; "
                    + "it reads: \(reading)")
            }
            var detail = "\(tool) lists \(reading)"
            if let choose {
                // A command row prints its ellipsis ("Resize Image…") because
                // that is what a person reads, and a walk should not have to
                // type one to name it. Exact words win; the forgiving match is
                // only reached when nothing answered to them.
                guard let row = rows.first(where: { $0.title == choose })
                        ?? rows.first(where: { Self.sameRowWords($0.title, choose) }) else {
                    throw Failure(description: "\(tool)'s list has no row called \"\(choose)\"; it reads: \(reading)")
                }
                // Firing what the pointer could not is how a walk comes to
                // report a dialog opening in a build where the row is greyed.
                guard row.isEnabled else {
                    throw Failure(description: "\(tool)'s row \"\(row.title)\" is greyed, so a click on it would do "
                        + "nothing; the list reads: \(reading)")
                }
                row.choose()
                await sleep(0.2)
                detail += "; chose \(describeRow(row))"
            }
            note(number, step.name, detail, state: describe())

        case .waitFor(let condition, let timeout):
            // Where a guide has got to is a fact about the guide, not about a
            // window: the video guides teach in a recording's window, which has
            // no editor in it at all. Everything else is asked of the editor.
            var editorForCondition: EditorState?
            if case .tutorialStep = condition {
                editorForCondition = editor
            } else {
                editorForCondition = try requireEditor()
            }
            let editor = editorForCondition
            let deadline = Date().addingTimeInterval(timeout)
            while !holds(condition, editor: editor) {
                guard Date() < deadline else {
                    throw Failure(description: "\(condition) did not happen within \(timeout)s"
                                  + conditionHint(condition))
                }
                await sleep(0.1)
            }
            // Landing on a step is the moment to hold it to its own promise:
            // the control it points at has to be on screen.
            if case .tutorialStep = condition { try await requireStepFoundItsControl() }
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

        case .writeSVG(let name, let background):
            let editor = try requireEditor()
            // A drawing that moves writes the file that moves: one lap of the
            // loop, in the file (`SVGMotionExport.swift`). A still one writes
            // exactly what it always did.
            let animation: SVGExport.Animation = editor.document?.hasMotion == true
                ? .moving(cycleMS: editor.document?.motionCycleLengthMS ?? 1) : .still
            guard let document = editor.document,
                  let written = SVGExporter.data(document, store: editor.store,
                                                 animation: animation,
                                                 background: background) else {
                throw Failure(description: "the document did not write as SVG")
            }
            try written.data.write(to: out.appendingPathComponent("\(name).svg"))
            let pictured = written.fallbacks.isEmpty
                ? "every layer as shapes"
                : written.fallbacks.map { "\($0.layerName) as a picture" }.joined(separator: ", ")
            let text = String(data: written.data, encoding: .utf8) ?? ""
            let animations = text.components(separatedBy: "<animate").count - 1
            let motion = animations > 0
                ? ", \(animations) moving \(animations == 1 ? "part" : "parts")"
                : ""
            // What happened to the canvas the drawing was made on, so a walk's
            // log says whether the file has a white box in it without anybody
            // having to open it.
            let canvas: String
            if let backdrop = SVGExporter.backdrop(in: document, store: editor.store) {
                canvas = background == .drop
                    ? ", nothing behind the drawing"
                    : ", the \(backdrop.color.hexString) canvas behind the drawing"
            } else {
                canvas = ""
            }
            note(number, step.name,
                 "\(name).svg \(written.data.count) bytes, \(pictured)\(motion)\(canvas)")

        case .writePicture(let name, let format, let quality, let scale, let background,
                           let behind):
            let editor = try requireEditor()
            guard let picture = ImageCodec.Format(rawValue: format) else {
                throw Failure(description: "\(format) is not a picture format Export writes")
            }
            guard let document = editor.document else {
                throw Failure(description: "there is no document to write")
            }
            // The very path the sheet weighs with, so the bytes in this log
            // line and the size on the sheet are one number, not two that
            // happen to agree.
            let sizer = ExportSizer(renderer: editor.previewRenderer, store: editor.store)
            let started = Date()
            guard let data = await sizer.data(of: document, frameID: editor.selectedFrameID,
                                              scale: scale, format: picture,
                                              quality: ExportQuality.fraction(quality),
                                              background: background) else {
                throw Failure(description: "the document did not write as \(format)")
            }
            let file = "\(name).\(picture.fileExtension)"
            try data.write(to: out.appendingPathComponent(file))
            let took = Int(Date().timeIntervalSince(started) * 1000)
            // What happened to the canvas the drawing was made on, read off the
            // file that just landed rather than off what was asked for, and
            // checked where the walk made a claim.
            let corners = try cornersOf(data, named: file, claim: behind)
            note(number, step.name,
                 "\(file) at \(quality)% is \(data.count) bytes "
                 + "(\(ExportQuality.fileSize(bytes: data.count))), weighed in \(took) ms"
                 + ", \(corners)")

        case .writeRecording(let name, let format, let quality, let seconds, let within,
                             let width, let height, let copied):
            note(number, step.name,
                 try await writeRecordingFile(name: name, format: format, quality: quality,
                                              seconds: seconds, within: within,
                                              width: width, height: height, copied: copied),
                 state: describe())

        case .exportQuality(let format, let percent):
            guard ExportQuality.applies(toFormat: format) else {
                throw Failure(description: "\(format) has no quality to set")
            }
            ExportQualityMemory.remember(percent, format: format)
            note(number, step.name,
                 "\(format) is remembered at \(ExportQualityMemory.remembered(format: format))%")

        case .panelMenu(let menu, let row, let shot, let choose, let clicking):
            try await openPanelMenu(menu, in: row, shot: shot, choose: choose, clicking: clicking,
                                    number: number)

        case .menuShot(let menu, let name, let ticked, let unticked):
            try await photographMenuBarMenu(menu, name: name, ticked: ticked,
                                            unticked: unticked, number: number)

        case .rightClick(let on, let at, let shot, let choose, let ticked, let unticked):
            try await openRowMenu(on, at: at, shot: shot, choose: choose, ticked: ticked,
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

        case .pickUpTile(let tile, let to):
            try await pickUpTile(tile, to: to, number: number)

        case .dragRow(let row, let onto, let zone, let hold):
            try await dragRow(row, onto: onto, zone: zone, hold: hold, number: number)
        case .dragColor(let from, let onto, let hold, let expect, let says):
            try await dragColor(from, onto: onto, hold: hold, expect: expect, says: says,
                                number: number)

        case .selectRow(let row, let modifiers):
            let editor = try requireEditor()
            let rows = editor.layerRows
            let click: RowClick = if modifiers.contains(.shift) { .extend }
                else if modifiers.contains(.command) { .toggle } else { .plain }
            // The layers list first, because that is the list most walks are
            // crawling down. A name it does not know goes to the Measurements
            // list, which holds the same layers in its own order and whose rows
            // nothing could click at all before.
            guard let match = rows.first(where: { $0.name == row })
                    ?? rows.first(where: { $0.name.caseInsensitiveCompare(row) == .orderedSame }) else {
                try await clickMeasurementRow(row, click: click, modifiers: modifiers,
                                              layerNames: rows.map(\.name), number: number)
                break
            }
            // What picking a row costs, on the main thread, from the click to
            // the panel standing still. The same pair of meters a real press
            // carries, because this IS the press's handler: the walk that
            // guards layer picking reads these two numbers
            // (`layer-pick-latency-walk`).
            MainThreadMeter.shared.install()
            MainThreadMeter.shared.reset()
            ViewBuildMeter.shared.reset()
            EditorReadWatch.arm(editor)
            EditorReadWatch.reset()
            editor.clickRow(match.id, click, in: editor.panelRows.map(\.id))
            await sleep(0.2)
            note(number, step.name,
                 "picked \"\(match.name)\" out of the layers list"
                    + (match.isLocked ? " (locked)" : "")
                    + " with a \(click) click"
                    + "; " + MainThreadMeter.shared.report + "; " + ViewBuildMeter.shared.report
                    + "; " + ViewBuildMeter.shared.traced
                    + "; " + EditorReadWatch.report,
                 state: describe())

        case .press(let control, let row, let count, let modifiers, let across):
            try await pressControl(control, in: row, count: count, modifiers: modifiers,
                                   across: across, number: number)

        case .dragSection(let section, let past, let stop, let hold, let cancel):
            try await dragSection(section, past: past, stop: stop, hold: hold,
                                  cancel: cancel, number: number)

        case .dragHandle(let area, let by, let expect, let hold):
            try await dragHandle(area, by: by, expect: expect, hold: hold, number: number)

        case .dragTiming(let bar, let grab, let byMS, let hold, let cancel, let cancelBy):
            try await dragTiming(bar, grab: grab, byMS: byMS, hold: hold, cancelBy: cancelBy,
                                 cancel: cancel, number: number)

        case .panel(let stage):
            let inventory = try readPanel()
            write(json: inventory, to: "panel-\(stage).json")
            note(number, step.name, Self.outlinePanel(inventory), state: inventory)

        case .expect(let thing, let named, let inRow, let reads, let present):
            // Kept looking rather than read once: a claim about the panel made
            // at the instant a relayout started answered about a panel that was
            // half built, and a switch that reads "on" for three frames while
            // its section re-lays out is not a switch that is on. The claim
            // still has to come true, only not in the first frame it is asked
            // about (`patiently`).
            note(number, step.name,
                 try await patiently {
                     try self.checkPanel(thing, named: named, inRow: inRow,
                                         reads: reads, present: present)
                 },
                 state: describe())

        case .expectBuilds(let view, let atMost, let atLeast):
            guard let subject = ViewBuildMeter.Subject(rawValue: view) else {
                throw Failure(description: "there is no view called \"\(view)\" to count; the ones "
                    + "the probe counts are: "
                    + ViewBuildMeter.Subject.allCases.map(\.rawValue).joined(separator: ", "))
            }
            let built = ViewBuildMeter.shared.count(subject)
            let times = "\(built) time\(built == 1 ? "" : "s")"
            if let atMost, built > atMost {
                throw Failure(description: "\"\(view)\" built \(times) "
                    + "since the step before this one, and this walk allows at most \(atMost). "
                    + "Something the step just did is read by that view, so SwiftUI rebuilt it and "
                    + "re-measured everything inside it. The whole count: "
                    + ViewBuildMeter.shared.report)
            }
            // The other side of the same claim: a ceiling of nothing is met
            // just as well by a view that has stopped being drawn at all, so a
            // walk asserting one wants to assert somewhere that the view still
            // builds when something really changed.
            if let atLeast, built < atLeast {
                throw Failure(description: "\"\(view)\" built \(times) "
                    + "since the step before this one, and this walk expects at least \(atLeast). "
                    + "Either the step did not change what that view shows, or the view is not on "
                    + "screen at all. The whole count: " + ViewBuildMeter.shared.report)
            }
            let bounds = [atLeast.map { "at least \($0)" }, atMost.map { "at most \($0)" }]
                .compactMap { $0 }.joined(separator: " and ")
            note(number, step.name,
                 "\"\(view)\" built \(times), \(bounds) allowed; "
                 + ViewBuildMeter.shared.report,
                 state: describe())

        case .expectListStill(let moved):
            note(number, step.name, try checkListStill(moved: moved), state: describe())

        case .expectEdited(let edited):
            note(number, step.name, try checkEdited(edited), state: describe())

        case .expectPicked(let layers):
            note(number, step.name, try checkPicked(layers), state: describe())

        case .expectIconPreviews(let sides, let absent):
            note(number, step.name, try checkIconPreviews(sides: sides, absent: absent),
                 state: describe())

        case .expectMeasures(let count):
            note(number, step.name, try checkMeasures(count), state: describe())

        case .expectSVG(let pictured, let contains):
            note(number, step.name, try checkSVG(pictured: pictured, contains: contains),
                 state: describe())

        case .expectWindows(let titled, let count):
            note(number, step.name, try checkWindows(titled: titled, count: count),
                 state: describe())

        case .expectRecording(let pieces, let picked, let keeps, let seconds,
                              let starts, let caught):
            note(number, step.name,
                 try checkRecording(pieces: pieces, picked: picked, keeps: keeps,
                                    seconds: seconds, starts: starts, caught: caught),
                 state: describe())

        case .expectStoredRecording(let seconds, let within, let original):
            note(number, step.name,
                 try await checkStoredRecording(seconds: seconds, within: within,
                                                original: original),
                 state: describe())

        case .expectFeet(let layerName, let start, let end, let reads, let within):
            note(number, step.name,
                 try checkFeet(layerName, start: start, end: end, reads: reads, within: within),
                 state: describe())

        case .expectPath(let layerName, let anchors, let closed, let curves, let smooth,
                         let halfSmooth, let rings, let width, let fill, let ink, let picked,
                         let anchorAt):
            note(number, step.name,
                 try checkPath(layerName, anchors: anchors, closed: closed, curves: curves,
                               smooth: smooth, halfSmooth: halfSmooth, rings: rings, width: width,
                               fill: fill, ink: ink, picked: picked, anchorAt: anchorAt),
                 state: describe())

        case .expectReadout(let says, let absent):
            note(number, step.name, try checkDragReadout(says: says, absent: absent),
                 state: describe())

        case .expectChrome(let within):
            let canvas = try requireCanvas()
            let peak = canvas.pathChromeDriftPeak
            let now = canvas.pathChromeDrift
            guard peak <= within else {
                throw Failure(description: "the points on the path came off the shape while it was "
                    + "being dragged: worst \(Self.round1(peak))pt away from where the shape the "
                    + "canvas was drawing had them, and a walk asked for \(Self.round1(within))pt. "
                    + "The drag draws the live shape and something behind it is painting the old "
                    + "points back over the top.")
            }
            note(number, step.name,
                 "the points stayed on the shape: worst \(Self.round1(peak))pt over the last drag, "
                     + "\(Self.round1(now))pt now, asked for \(Self.round1(within))pt",
                 state: describe())

        case .expectSharp(let absent, let within):
            note(number, step.name, try await checkSharp(absent: absent, within: within),
                 state: describe())

        case .expectLanding(let near, let within, let absent):
            note(number, step.name, try checkLanding(near: near, within: within, absent: absent),
                 state: describe())

        case .expectHint(let contains):
            note(number, step.name, try checkHint(contains: contains), state: describe())

        case .expectCue(let says):
            note(number, step.name, try checkCue(says: says), state: describe())

        case .expectClickReaches(let at, let what):
            note(number, step.name, try checkClickReaches(at, what: what), state: describe())

        case .expectToast(let says, let absent):
            note(number, step.name, try checkToast(says: says, absent: absent), state: describe())

        case .expectNotice(let says, let absent, let held):
            note(number, step.name, try checkNotice(says: says, absent: absent, held: held),
                 state: describe())

        case .expectLayers(let atLeast, let atMost):
            note(number, step.name, try checkLayers(atLeast: atLeast, atMost: atMost),
                 state: describe())

        case .expectBox(let layer, let at, let size, let corner, let onScreen, let reachable, let within):
            note(number, step.name,
                 try checkBox(layer, at: at, size: size, corner: corner, onScreen: onScreen,
                              reachable: reachable,
                              within: within),
                 state: describe())

        case .expectField(let onScreen, let degrees, let within):
            note(number, step.name,
                 try checkField(onScreen: onScreen, degrees: degrees, within: within),
                 state: describe())

        case .expectRegion(let reads, let present):
            note(number, step.name, try checkRegion(reads: reads, present: present),
                 state: describe())

        case .expectCaption(let aligned, let caret, let caretHeight, let outline):
            note(number, step.name,
                 try checkCaption(aligned: aligned, caret: caret,
                                  caretHeight: caretHeight, outline: outline),
                 state: describe())

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
                // Kept looking, like a press. The layers list builds its rows
                // lazily, so the row a walk wants to scroll from can be a
                // moment behind the step that asked for it
                // (layers-lazy-rows-walk, 2026-09-09 and again 2026-09-13).
                target = try await patiently { try self.panelScrollTarget(row) }
            } else if let any = rows.first {
                target = any
            } else {
                throw Failure(description: "there are no rows in the panel to scroll")
            }
            let before = rows.map(\.name)
            ViewBuildMeter.shared.reset()
            MainThreadMeter.shared.install()
            MainThreadMeter.shared.reset()
            // In rounds, not one turn. A lazily built list only has as much
            // length as it has built, so one big turn stops at a content size
            // that is still growing: the walk that scrolls a hundred and
            // twenty layers by -4000 landed a third of the way down about one
            // run in three, and the step after it, looking for the row at the
            // bottom, found no such row. Each round asks for what is left, and
            // it stops as soon as a round moves nothing.
            var moved = try scroll(from: target, by: by)
            await sleep(0.4)
            var left = by - Self.distance(scrolled: moved, asked: by)
            for _ in 0..<5 where abs(left) > 1 {
                let again = try scroll(from: panelScrollTarget(target), by: left)
                let delivered = Self.distance(scrolled: again, asked: left)
                await sleep(0.3)
                guard abs(delivered) > 1 else { break }
                moved += ", then " + again
                left -= delivered
            }
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

        // Both places a tutorial shelf shows, asked together. The menu bar is
        // built once at launch and the window every time it is drawn, so a
        // feature switched off that reaches one and not the other is exactly
        // what this is here to catch.
        case .expectTutorialTracks(let wanted, let unwanted):
            let inMenu = Self.tutorialTracksInHelpMenu()
            guard let hub = TutorialHubProbe.window() else {
                throw Failure(description: "expectTutorialTracks reads the Tutorials window as well as "
                              + "the menu, and it is not open; run the showTutorials action first")
            }
            let said = WindowReadProbe.fullReading(in: hub).map(\.label).filter { !$0.isEmpty }
            let inWindow = TutorialTrack.allCases
                .filter { Self.tutorialTrack($0, isReadableIn: said) }
                .map(\.title)
            var wrong: [String] = []
            for track in wanted {
                if !inMenu.contains(track) { wrong.append("\(track) is not in Help, and should be") }
                if !inWindow.contains(track) { wrong.append("\(track) is not in the Tutorials window, and should be") }
            }
            for track in unwanted {
                if inMenu.contains(track) { wrong.append("\(track) is still in Help") }
                if inWindow.contains(track) { wrong.append("\(track) is still in the Tutorials window") }
            }
            guard wrong.isEmpty else {
                throw Failure(description: wrong.joined(separator: "; ")
                              + ". Help offers \(inMenu.joined(separator: ", ")); "
                              + "the window offers \(inWindow.joined(separator: ", "))")
            }
            note(number, step.name,
                 "Help ▸ Tutorials offers \(inMenu.joined(separator: ", ")); "
                 + "the Tutorials window offers \(inWindow.joined(separator: ", "))")

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

        // The Tutorials window is not an editor and carries no playtest markers,
        // so it is read and pressed through the accessibility tree: the same
        // tree VoiceOver reads, asked of our own process, which needs no grant.
        case .action(let action) where action == .readTutorialWindow:
            guard let hub = TutorialHubProbe.window() else {
                throw Failure(description: "the Tutorials window is not open")
            }
            // Read all the way down rather than once: the list scrolls, and a
            // row that has scrolled away has no words worked out for it yet.
            let read = WindowReadProbe.fullReading(in: hub)
            let buttons = read.filter { $0.role == NSAccessibility.Role.button.rawValue }
            guard !buttons.isEmpty else {
                throw Failure(description: "the Tutorials window has no buttons a screen reader can find")
            }
            // Every guide in the catalogue has to be readable in here, and its
            // own button has to say which guide it belongs to. "Start" on its
            // own is four identical buttons to somebody listening.
            let said = read.map(\.label)
            let spoken = Set(buttons.map(\.label))
            let ways = [TutorialHubModel.startTitle, TutorialHubModel.continueTitle,
                        TutorialHubModel.againTitle]
            let silent = TutorialLauncher.offered.filter { guide in
                !said.contains { $0.contains(guide.title) }
                    || !ways.contains { spoken.contains("\($0) \(guide.title)") }
            }
            guard silent.isEmpty else {
                throw Failure(description: "the Tutorials window never says, or offers no button naming: "
                              + silent.map(\.title).joined(separator: ", "))
            }
            note(number, step.name,
                 "the Tutorials window reads:\n  " + WindowReadProbe.reading(in: hub))

        case .action(let action) where action == .pressTutorialStart:
            guard TutorialHubProbe.window() != nil else {
                throw Failure(description: "the Tutorials window is not open")
            }
            guard let pressed = TutorialHubProbe.pressFirstGuideButton() else {
                throw Failure(description: "no guide row in the Tutorials window offers a button to press")
            }
            await sleep(1.2)
            note(number, step.name,
                 "pressed \"\(pressed)\"; the hub is \(TutorialHubProbe.window() == nil ? "closed" : "STILL OPEN") "
                 + "and the guide is \(TutorialController.shared.isRunning ? "running" : "NOT running")")

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

        // The first run, walked from a clean slate. None of these need an
        // editor: the setup window belongs to the menu-bar agent and comes up
        // before there is any document at all.
        case .action(let action) where action == .freshInstall:
            for key in Self.firstRunKeys { UserDefaults.standard.removeObject(forKey: key) }
            UserDefaults.standard.removeObject(forKey: TutorialController.progressKey)
            TutorialController.shared.forgetAllProgress()
            note(number, step.name,
                 "forgot \(Self.firstRunKeys.count) first run settings and any tutorial progress: "
                 + "the next launch is this machine's first")

        case .action(let action) where action == .oldInstall:
            // An install that finished its setup months ago, before any of this
            // existed. Nothing has ever been asked, and nothing ever should be.
            for key in Self.firstRunKeys { UserDefaults.standard.removeObject(forKey: key) }
            UserDefaults.standard.set(true, forKey: WelcomeController.completedDefaultsKey)
            note(number, step.name,
                 "pretended an install that finished setup before tutorials existed")

        // Be the person who never gives Photonz the screen, on a machine that
        // long since granted it. Nothing about macOS changes: this is the
        // app's own reading of the grant, in the probe build only, so a walk
        // can drive the half of the first run the probe machine can never
        // reach by itself.
        case .action(let action) where action == .screenRecordingOff
            || action == .screenRecordingOn:
            let granted = action == .screenRecordingOn
            ScreenCapturer.playtestPretendedPermission = granted
            note(number, step.name,
                 "from here Photonz reads Screen Recording as "
                 + (granted ? "granted" : "never granted") + "; \(Self.firstRunReading)")

        case .action(let action) where action == .tryToCapture:
            coordinator.capture.beginRectCapture()
            await sleep(0.9)
            guard coordinator.capture.needsScreenRecordingPermission else {
                throw Failure(description: "the capture went ahead, so there is nothing to "
                              + "explain; this step wants screenRecordingOff before it")
            }
            note(number, step.name,
                 "reached for a screenshot with the screen never granted; "
                 + "the app should now be saying what is missing")

        case .action(let action) where action == .launchHook:
            coordinator.runWelcomeLaunchHook()
            // The hook waits out the beat the menu-bar agent needs to settle
            // before taking focus, so the walk waits with it.
            await sleep(1.4)
            note(number, step.name, "ran the launch hook; \(Self.firstRunReading)")

        case .action(let action) where action == .expectWelcome:
            guard WelcomeProbe.window() != nil else {
                throw Failure(description: "the setup window did not come up; \(Self.firstRunReading)")
            }
            note(number, step.name, "the setup window is up; \(Self.firstRunReading)")

        case .action(let action) where action == .expectNoWelcome:
            guard WelcomeProbe.window() == nil else {
                throw Failure(description: "the setup window came back after it had been answered; "
                              + "\(Self.firstRunReading)")
            }
            note(number, step.name, "nothing came up; \(Self.firstRunReading)")

        case .action(let action) where action == .readWelcome:
            guard let welcome = WelcomeProbe.window() else {
                throw Failure(description: "the setup window is not open")
            }
            let said = WindowReadProbe.elements(in: welcome).map(\.label)
            let missing = [FirstRunOffer.tourButtonTitle, FirstRunOffer.skipButtonTitle]
                .filter { title in !said.contains { $0 == title } }
            guard missing.isEmpty else {
                throw Failure(description: "the setup window never offers: "
                              + missing.joined(separator: ", "))
            }
            let unnamed = WindowReadProbe.buttons(in: welcome).filter { $0.label.isEmpty }
            guard unnamed.isEmpty else {
                throw Failure(description: "\(unnamed.count) button(s) in the setup window say nothing")
            }
            note(number, step.name,
                 "the setup window reads:\n  " + WindowReadProbe.reading(in: welcome))

        // Pressing "Take the Tour" closes the setup window and opens the
        // guide's own sample window, so the walk moves over to it: everything
        // after this step is aimed at the window the person is looking at.
        case .action(let action) where action == .takeTheTour:
            guard WelcomeProbe.window() != nil else {
                throw Failure(description: "the setup window is not open")
            }
            guard let pressed = WelcomeProbe.press(FirstRunOffer.tourButtonTitle) else {
                throw Failure(description: "the setup window offers no \(FirstRunOffer.tourButtonTitle) button")
            }
            var opened: EditorState?
            try await poll("the tutorial window", within: 8) {
                opened = PlaytestHarness.readyEditors.last {
                    $0.untitledName == TutorialSampleScreen.documentName
                }
                return opened != nil
            }
            guard let opened else {
                throw Failure(description: "\(pressed) opened no window for the guide to run in")
            }
            guard WelcomeProbe.window() == nil else {
                throw Failure(description: "the setup window is still up over the guide it started")
            }
            try await adopt(opened, window: nil, step: step.name,
                            subject: "the tour, started from the first run offer", number: number)

        case .action(let action) where action == .startWorking:
            guard WelcomeProbe.window() != nil else {
                throw Failure(description: "the setup window is not open")
            }
            guard let pressed = WelcomeProbe.press(FirstRunOffer.skipButtonTitle) else {
                throw Failure(description: "the setup window offers no \(FirstRunOffer.skipButtonTitle) button")
            }
            await sleep(0.8)
            guard WelcomeProbe.window() == nil else {
                throw Failure(description: "\(pressed) left the setup window up")
            }
            guard !TutorialController.shared.isRunning else {
                throw Failure(description: "\(pressed) started a guide anyway")
            }
            note(number, step.name, "pressed \"\(pressed)\"; \(Self.firstRunReading)")

        case .action(let action) where action == .showWelcomeAgain:
            coordinator.runWelcomeMenuEntry()
            await sleep(0.8)
            guard let welcome = WelcomeProbe.window() else {
                throw Failure(description: "Welcome & Permissions... opened nothing")
            }
            let says = WindowReadProbe.elements(in: welcome).map(\.label)
            let offered = [FirstRunOffer.tourButtonTitle, FirstRunOffer.skipButtonTitle]
                .filter { title in says.contains { $0 == title } }
            guard offered.isEmpty else {
                throw Failure(description: "reopening the setup window asks again: "
                              + offered.joined(separator: ", "))
            }
            note(number, step.name,
                 "Welcome & Permissions... reopened the plain setup window, no tour offer in it:\n  "
                 + WindowReadProbe.reading(in: welcome))
            welcome.close()
            await sleep(0.4)

        // Any guide in the catalogue, started by id the way picking it off the
        // Help menu does, and followed into the window it teaches in. Always
        // from step one: a guide picks up where it was left, and a walk always
        // means the beginning.
        case .setLensAmount(let value, let hold):
            let editor = try requireEditor()
            guard let lens = editor.selectedLens else {
                throw Failure(description: "no lens layer is picked, so there is no Strength "
                              + "slider to put on \(value)")
            }
            let range = lens.content.adjustment.range
            guard range.contains(value) else {
                throw Failure(description: "\(lens.content.adjustment.title) offers "
                              + "\(range.lowerBound) to \(range.upperBound), so its slider "
                              + "cannot be put on \(value)")
            }
            // The same two calls a finger makes: previews on the way down, one
            // committed undo step when it is let go. `hold` stops before the
            // letting go.
            editor.previewLensAmount(value)
            if !hold { editor.commitLensAmount() }
            await sleep(0.2)
            // What the SLIDER reads, which is where the pull has got to while
            // one is live and the document's own number the rest of the time.
            let now = lens.content.adjustment.label(editor.selectedLensAmount ?? value)
            note(number, step.name,
                 "\(lens.content.adjustment.title) is now \(now)"
                 + (hold ? ", with the slider still under the finger" : ""),
                 state: describe())

        case .expectTutorialStep(let id):
            guard let run = TutorialController.shared.run else {
                throw Failure(description: "no guide is running, so nothing is on step \"\(id)\"")
            }
            guard run.step.id == id else {
                throw Failure(description: "the guide moved on: it is on step "
                              + "\"\(run.step.id)\" (\(run.number) of \(run.count)), "
                              + "not \"\(id)\"")
            }
            note(number, step.name,
                 "still on \"\(id)\", \(run.number) of \(run.count)", state: describe())

        case .startGuide(let id, let size):
            guard let guide = TutorialCatalog.guide(id: id) else {
                throw Failure(description: "there is no guide called \"\(id)\" in the catalogue")
            }
            TutorialController.shared.forgetProgress(guide.id)
            TutorialLauncher.start(guide, coordinator: coordinator, editor: editor)
            if guide.sample?.isVideo == true {
                // A recording's window, not a picture editor's. It writes a
                // fresh sample MP4 first and opens once the clip has loaded,
                // so the wait is longer than a drawing's.
                var opened: VideoEditorState?
                try await poll("the recording \(id) brought", within: 20) {
                    opened = PlaytestHarness.readyRecordings.last {
                        $0.url?.lastPathComponent == TutorialSampleRecording.fileName
                    }
                    return opened != nil
                }
                guard let opened else { throw Failure(description: "\(id) opened no recording") }
                try await adoptRecording(opened, step: step.name,
                                         subject: "\(guide.title), in the recording it brought",
                                         number: number)
            } else if guide.sample != nil {
                var opened: EditorState?
                try await poll("the window \(id) opened for itself", within: 8) {
                    opened = PlaytestHarness.allEditors.last {
                        $0.untitledName == TutorialSampleScreen.documentName
                            && $0.hostWindow != nil
                    }
                    return opened != nil
                }
                guard let opened else { throw Failure(description: "\(id) opened no window") }
                if opened.document == nil {
                    try await adoptEmpty(opened, step: step.name,
                                         subject: "\(guide.title), in the empty window it brought",
                                         number: number)
                } else {
                    try await adopt(opened, window: size, step: step.name,
                                    subject: "\(guide.title), in the window it brought",
                                    number: number)
                }
            }
            try await poll("\(id) to start", within: 5) {
                TutorialController.shared.runningGuideID == id
            }

        // Take the Tour opens a window of its own holding the guide's sample
        // picture, so the walk moves over to that window: everything after this
        // step is aimed at the window the person would really be looking at.
        case .action(let action) where action == .startTour:
            guard let tour = TutorialLauncher.tour else {
                throw Failure(description: "there is no tour in the catalogue")
            }
            TutorialLauncher.start(tour, coordinator: coordinator, editor: editor)
            var opened: EditorState?
            try await poll("the tutorial window", within: 8) {
                opened = PlaytestHarness.readyEditors.last {
                    $0.untitledName == TutorialSampleScreen.documentName
                }
                return opened != nil
            }
            guard let opened else { throw Failure(description: "the tour opened no window") }
            try await adopt(opened, window: nil, step: step.name,
                            subject: "Take the Tour in its own window", number: number)

        // A recording's window, driven the way its own buttons drive it. Ahead
        // of the general case because every action below it asks for a picture
        // editor, and there is not one in here.
        // The callout's own buttons, when the guide is running somewhere there
        // is no picture editor to ask for. An image walk keeps these in the
        // general branch below, where they read the editor's state back.
        case .action(let action) where action.drivesGuide && editor == nil:
            switch action {
            case .tutorialNext: TutorialController.shared.next()
            case .tutorialBack: TutorialController.shared.back()
            case .tutorialClose: TutorialController.shared.close()
            default: try pressFinishRow(action)
            }
            await sleep(0.3)
            note(number, step.name,
                 "\(action.rawValue): \(TutorialController.shared.liveDescription(in: window))",
                 state: describe())

        // A recording window with no guide in front of it, on the sample clip
        // the video guides bring. The walk moves into it, exactly as it would
        // into the window a guide opened.
        case .action(let action) where action == .openSampleRecording:
            guard let url = TutorialSampleRecording.fresh() else {
                throw Failure(description: "couldn't write the sample recording")
            }
            coordinator.openWindow(.video(standardizing: url))
            var opened: VideoEditorState?
            try await poll("the sample recording to open", within: 20) {
                opened = PlaytestHarness.readyRecordings.last {
                    $0.url?.lastPathComponent == TutorialSampleRecording.fileName
                }
                return opened != nil
            }
            guard let opened else { throw Failure(description: "no recording window opened") }
            try await adoptRecording(opened, step: step.name,
                                     subject: "the sample recording", number: number)

        // Saving is its own case because it has to be WAITED for: a commit
        // re-encodes, and every one of these steps is only worth anything once
        // the file on disk has actually changed.
        // What Command S runs, on whatever window is in front. The chord itself
        // cannot reach File > Save in a walk (the probe never comes to the
        // front, so that item is dimmed and empty for the whole run), so the
        // chord stands in for this and this does what the item does.
        case .action(.save):
            let target: any SaveableEditor = try recording ?? requireEditor()
            let kind = recording == nil ? "document" : "recording"
            let before = target.saveAffordance
            var answer: Bool?
            target.performSave { answer = $0 }
            try await poll("the save to finish", within: 120) { answer != nil }
            guard answer == true else {
                throw Failure(description: "Command S reported that it did NOT save the \(kind) "
                    + "(it was \(before.rawValue) before the press)")
            }
            note(number, step.name,
                 "save: the \(kind) was \(before.rawValue), now \(target.saveAffordance.rawValue)",
                 state: describe())

        case .action(let action) where action == .videoSave || action == .videoCloseAndSave:
            let video = try requireRecording()
            let before = video.saveAffordance
            let window = video.hostWindow
            let started = Date()
            var answer: Bool?
            if action == .videoSave {
                video.performSave { answer = $0 }
            } else {
                // Exactly what pressing Save in the close confirmation runs,
                // window close and all — the path the 2026-09-18 report says
                // did nothing.
                video.performSave { saved in
                    answer = saved
                    if saved { window?.close() }
                }
            }
            try await poll("the save to finish", within: 120) { answer != nil }
            let took = Date().timeIntervalSince(started)
            guard answer == true else {
                throw Failure(description: "\(action.rawValue) reported that it did NOT save "
                    + "(it was \(before.rawValue) before the press). The window keeps its edits; "
                    + "a person sees a dialog that will not go away.")
            }
            note(number, step.name,
                 "\(action.rawValue): was \(before.rawValue), saved in "
                     + "\(String(format: "%.1f", took))s, now \(video.saveAffordance.rawValue)"
                     + (action == .videoCloseAndSave
                        ? ", and the window closed" : ""),
                 state: describe())

        // The Export sheet a recording leaves through. Opening it is what a
        // person does with ⇧⌘S or File ▸ Export…; the format is asked for here
        // rather than pressed, so a walk can photograph GIF with the screen
        // locked and so photographing one format never decides what the next
        // walk opens on.
        case .action(let action) where action == .videoExportSheet
            || action == .videoExportSheetAsGIF || action == .videoExportSheetAsHEIC:
            let video = try requireRecording()
            guard Experiments.shared.recordingExportSheetEnabled else {
                throw Failure(description: "the Export sheet for a recording is switched off "
                    + "(\(FeatureCatalog.recordingExportSheetFlag)), so ⇧⌘S still opens the bare "
                    + "save box and there is no sheet to open")
            }
            let asked: RecordingFormat = switch action {
            case .videoExportSheetAsGIF: .gif
            case .videoExportSheetAsHEIC: .heic
            default: .mp4
            }
            video.playtestOpensExportOnRecordingFormat = asked
            video.isExportSheetPresented = true
            await sleep(0.6)
            note(number, step.name, "the Export sheet is up on \(asked.displayName)",
                 state: describe())

        case .action(let action) where action == .videoExportSheetCancel:
            let video = try requireRecording()
            guard video.isExportSheetPresented else {
                throw Failure(description: "there is no Export sheet up to cancel")
            }
            video.isExportSheetPresented = false
            await sleep(0.4)
            note(number, step.name, "the Export sheet is closed", state: describe())

        case .action(let action) where action == .videoRevertToOriginal:
            let video = try requireRecording()
            guard video.canRevertToOriginal else {
                throw Failure(description: "Revert to Original is not offered: there is no preserved "
                    + "original to go back to yet, so nothing has ever been saved over this recording")
            }
            video.revertToOriginal()
            note(number, step.name, "put the whole recording back: \(video.saveAffordance.rawValue)",
                 state: describe())

        case .action(let action) where action.drivesRecording:
            let video = try requireRecording()
            switch action {
            case .videoBeginTrim: video.beginTrim()
            case .videoTrimStart: video.setTrimIn(video.duration * 0.25)
            case .videoTrimEnd: video.setTrimOut(video.duration * 0.75)
            case .videoTrimDone: video.commitTrim()
            case .videoTrimCancel: video.cancelTrim()
            case .videoCopyGIF: coordinator.copyRecording(video, as: .gif)
            case .videoSeekQuarter: video.scrub(to: video.duration * 0.25)
            case .videoSeekMiddle: video.scrub(to: video.duration * 0.5)
            case .videoSeekThreeQuarters: video.scrub(to: video.duration * 0.75)
            case .videoCut: video.cutAtPlayhead()
            case .videoDeletePiece: video.deleteSelectedPiece()
            case .videoUndoEdit: video.undoLastEdit()
            case .videoPlay: video.play()
            case .videoPause: video.pause()
            case .videoDragTrimNearCut: try dragTrimHandle(video, .start, pointsFromCut: 5)
            case .videoDragTrimJustPastCut: try dragTrimHandle(video, .start, pointsFromCut: 12)
            case .videoDragTrimClearOfCut: try dragTrimHandle(video, .start, pointsFromCut: 24)
            case .videoDragTrimFreedNearCut:
                try dragTrimHandle(video, .start, pointsFromCut: 3, freed: true)
            case .videoDragTrimEndNearCut: try dragTrimHandle(video, .end, pointsFromCut: 5)
            case .videoDragTrimRelease: video.endTrimHandleDrag()
            case .videoCropMiddle:
                let whole = video.naturalSize
                video.beginCrop()
                video.setCropRect(CGRect(x: whole.width / 4, y: whole.height / 4,
                                         width: whole.width / 2, height: whole.height / 2))
                video.commitCrop()
            case .videoSave, .videoCloseAndSave, .videoRevertToOriginal, .save: break // handled above
            case .videoExportSheet, .videoExportSheetAsGIF, .videoExportSheetAsHEIC,
                 .videoExportSheetCancel: break // handled above
            default: break
            }
            // Cutting re-points the player at a composition of the kept
            // pieces, which is asynchronous, so give it longer to land than a
            // trim handle move needs.
            await sleep(action == .videoCut || action == .videoDeletePiece
                        || action == .videoUndoEdit ? 1.2 : 0.3)
            note(number, step.name,
                 "\(action.rawValue): \(String(format: "%.2f", video.trim.inPoint)) to "
                 + "\(String(format: "%.2f", video.trim.outPoint)) of "
                 + "\(String(format: "%.2f", video.duration))s"
                 + ", \(video.cuts.pieceCount) piece\(video.cuts.pieceCount == 1 ? "" : "s") ["
                 + video.cuts.pieces.map { String(format: "%.2f-%.2f", $0.start, $0.end) }
                        .joined(separator: " | ") + "]"
                 + ", playhead \(String(format: "%.2f", video.currentTime))"
                 + (video.selectedPieceIndex.map { ", piece \($0 + 1) picked" } ?? "")
                 + (video.isPlaying ? ", playing" : "")
                 + (video.isTrimming ? ", trim open" : "")
                 + (video.hasUnsavedChanges ? ", unsaved" : ""),
                 state: describe())

        // The one colour check that needs no control to carry a name, so it
        // still answers on a locked Mac. See `PlaytestAction.holdColorRow`.
        case .action(let action) where action == .holdColorRow:
            let editor = try requireEditor()
            guard let row = editor.layerPartRows.first,
                  let target = ColorTarget(row.colors, rowID: row.id) else {
                throw Failure(description: "nothing picked has a colour row to hold; the panel "
                    + "has \(editor.layerPartRows.count) part rows")
            }
            heldColorRow = target
            let over = row.colors.flatMap { $0.layerIDs ?? [] }
                .compactMap { editor.document?.layer(id: $0)?.name }
            note(number, step.name,
                 "holding the colour row \"\(row.title)\" (\(row.id)), which reaches "
                 + (over.isEmpty ? "nothing" : over.joined(separator: ", ")) + " right now",
                 state: describe())

        case .action(let action) where action == .paintHeldColorRow:
            let editor = try requireEditor()
            guard let held = heldColorRow else {
                throw Failure(description: "no colour row is being held; a holdColorRow step has "
                    + "to come first")
            }
            guard let before = editor.document else {
                throw Failure(description: "there is no document to paint")
            }
            let slot = held.lead
            let hex = "#B0184A"
            let was = Dictionary(uniqueKeysWithValues:
                                    before.allLayers.map { ($0.id, $0.colorHex(for: slot)) })
            // Worked out from the SELECTION rather than from the row, so the
            // claim does not lean on the very lookup it is checking.
            let picked = Set(editor.actionableLayerIDs)
            let owed = Set(before.allLayers
                .filter { picked.contains($0.id) && !$0.isLocked && $0.colorSlots.contains(slot) }
                .map(\.id))
            // First: what the held row SAYS it reaches. A row the panel left
            // alone still carries the layers it was drawn over, so this is the
            // lookup that has to happen before anything else does.
            let reaches = Set(editor.colorStyleSelection(held).layerIDs)
            guard reaches == owed else {
                let names = { (ids: Set<UUID>) -> String in
                    ids.isEmpty ? "nothing"
                        : ids.compactMap { before.layer(id: $0)?.name }.sorted()
                            .joined(separator: ", ")
                }
                throw Failure(description: "the held colour row still speaks for "
                    + "\(names(reaches)), and what is picked now is \(names(owed)). A row the "
                    + "panel left alone has to look its layers up again by name rather than "
                    + "keeping the ones it was drawn over (`EditorState.resolved(_:)`)")
            }
            editor.setSelectionPaint(held, paint: Paint(hex: hex))
            await sleep(0.3)
            guard let after = editor.document else {
                throw Failure(description: "the document went away while painting")
            }
            var wrong: [String] = []
            for layer in after.allLayers {
                let now = layer.colorHex(for: slot)
                let wears = now?.caseInsensitiveCompare(hex) == .orderedSame
                if owed.contains(layer.id) {
                    if !wears {
                        wrong.append("\(layer.name) is picked and has a \(slot.rawValue), and the "
                            + "row left it as \(now ?? "nothing")")
                    }
                } else if now != was[layer.id] {
                    wrong.append("\(layer.name) is not picked and the row painted it anyway: "
                        + "\(was[layer.id] ?? "nothing") became \(now ?? "nothing")")
                }
            }
            guard wrong.isEmpty else {
                throw Failure(description: "the colour row painted the wrong layers. "
                    + wrong.joined(separator: "; ")
                    + ". A row the panel left alone is still holding the layers it was drawn "
                    + "over; it has to look them up again before it paints "
                    + "(`EditorState.resolved(_:)`)")
            }
            note(number, step.name,
                 "painted \(slot.rawValue) \(hex) through the held row: it reached "
                 + (owed.isEmpty ? "nothing" : owed.compactMap { after.layer(id: $0)?.name }
                        .sorted().joined(separator: ", "))
                 + " and left every other layer alone",
                 state: describe())

        case .action(let action):
            let editor = try requireEditor()
            // Zeroed here so `showInspector` reports the cost of the panel
            // ARRIVING: the number of layer rows the list builds when it comes
            // back on screen, which is the thing a lazy list is claiming.
            ViewBuildMeter.shared.reset()
            // ...and the main thread with it, so an action that stands in for
            // a click (`selectCanvas` is the Canvas row) carries the same cost
            // reading a real press does.
            MainThreadMeter.shared.install()
            MainThreadMeter.shared.reset()
            switch action {
            // Handled in full above, where they can refuse the walk. Named
            // here only because this switch covers every action.
            case .holdColorRow, .paintHeldColorRow, .save: break
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
            case .positionAndSize:
                // The command can quietly do nothing — there is nothing picked
                // and nothing marqueed — and a walk that then fails at `focus`
                // would blame the field rather than the empty selection.
                let subject = editor.exactPlacementSubject
                editor.openExactPlacement()
                actionDetail = subject == nil
                    ? "nothing picked and no marquee, so the menu row is dimmed and nothing opened"
                    : "open over \(editor.exactPlacementHeading)"
            case .closePositionAndSize: editor.closeExactPlacement()
            case .newCanvasDialog: editor.isBlankCanvasDialogPresented = true
            case .createCanvas:
                editor.isBlankCanvasDialogPresented = false
                editor.createBlankCanvas(size: BlankCanvas.defaultPreset.size)
            case .group: editor.groupSelection()
            case .ungroup: editor.ungroupSelection()
            case .stackSelection: editor.stackSelection(.stack)
            case .gridSelection: editor.stackSelection(.grid)
            case .roomAroundContents:
                if let id = editor.selectedLayerID, editor.document?.layer(id: id)?.isGroup == true {
                    editor.updateArrangement(id: id) { $0.padding = GroupPadding(20) }
                    actionDetail = "20 points of room inside the group"
                } else {
                    actionDetail = "nothing picked that holds anything, so no room was added"
                }
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
            case .shareSelectedComponent:
                if let id = editor.selectedLayerID,
                   let componentID = editor.document?.layer(id: id)?.componentID {
                    editor.setComponentShared(componentID, true)
                }
            case .unshareSelectedComponent:
                if let id = editor.selectedLayerID,
                   let componentID = editor.document?.layer(id: id)?.componentID {
                    editor.setComponentShared(componentID, false)
                }
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
            case .turnKnob:
                turnKnob(editor, through: [5, 12, 18, 20])
            case .turnKnobStraight:
                turnKnob(editor, through: [14, 7, 0])
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
            case .armLensBlur:
                // The KIND, not just the adjustment: a walk arming Blur after
                // one that armed Magnify must actually get a blur.
                editor.lensToolKind = .blur
            case .armLensPixelate:
                editor.lensToolKind = .pixelate
            case .armLensMagnify:
                editor.lensToolKind = .magnify
            case .lensMagnify:
                editor.setLensKind(.magnify)
            case .lensBlur:
                editor.setLensAdjustment(.blur)
            case .lensPixelate:
                editor.setLensAdjustment(.pixelate)
            case .lensGreyscale:
                editor.setLensAdjustment(.greyscale)
            case .lensInvert:
                editor.setLensAdjustment(.invert)
            case .lensBrightness:
                editor.setLensAdjustment(.brightness)
            case .pullLensAmount, .pullLensAmountBack:
                // Exactly what a pull on the slider does: live previews on the
                // way, one undo step when it is let go.
                if let lens = editor.selectedLens {
                    let range = lens.content.adjustment.range
                    let target = action == .pullLensAmount
                        ? range.upperBound
                        : range.lowerBound + (range.upperBound - range.lowerBound) / 4
                    let from = lens.content.amount
                    for step in 1...4 {
                        editor.previewLensAmount(from + (target - from) * CGFloat(step) / 4)
                    }
                    editor.commitLensAmount()
                }
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
                // Every picked layer with a line of its own, which since the
                // Pen landed includes a path it drew (`OutlineWidth.swift`).
                let ids = editor.outlineThicknessSelection.layerIDs
                if !ids.isEmpty {
                    for width in [5.0, 7.0, 9.0] as [CGFloat] {
                        editor.previewOutlineWidth(ids: ids, width)
                    }
                    editor.commitOutlineWidth(ids: ids, 9)
                }
            case .dragThicknessThin:
                let ids = editor.outlineThicknessSelection.layerIDs
                if !ids.isEmpty { editor.commitOutlineWidth(ids: ids, 3) }
            case .dragThicknessFat:
                let ids = editor.outlineThicknessSelection.layerIDs
                if !ids.isEmpty { editor.commitOutlineWidth(ids: ids, 24) }
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
            case .useFirstBorrowedColor:
                // The second list in a colour row's menu: the colours it can
                // paint with but not wear the name of. The first pairing that
                // is actually on offer, for the same reason `useFirstColorStyle`
                // pairs slot and style rather than taking the first of each.
                if let pair = editor.colorRowSlots.lazy.compactMap({ slot in
                    editor.borrowedColors(for: slot).first.map { (slot, $0.id) }
                }).first {
                    editor.useBorrowedColor(ColorTarget(pair.0), styleID: pair.1)
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
            case .togglePathOutline:
                // The Outline switch over every picked path: one click, every
                // one of them, exactly as the row's own switch does.
                let paths = editor.pathLineStyleSelection
                if !paths.isEmpty {
                    editor.setPathOutline(ids: paths.layerIDs, on: !paths.hasALine)
                }
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
            case .exportDialogAsPNG:
                editor.playtestOpensExportOnPicture = .png
                editor.isExportDialogPresented = true
            case .exportDialogAsJPEG:
                // Asked for on the sheet itself, the same way SVG is, so a walk
                // that photographs the quality slider cannot change what the
                // NEXT walk's Export opens on.
                editor.playtestOpensExportOnPicture = .jpeg
                editor.isExportDialogPresented = true
            case .exportDialogAsWebP:
                editor.playtestOpensExportOnPicture = .webp
                editor.isExportDialogPresented = true
            case .exportDialogAsSVG:
                // Asked for on the sheet itself rather than written into the
                // app's memory, so a walk that photographs Export on SVG
                // cannot change what the NEXT walk's Export opens on.
                editor.playtestOpensExportOnSVG = true
                editor.isExportDialogPresented = true
            case .exportDialogToWebPage:
                editor.playtestExportDestination = .webPage
                editor.isExportDialogPresented = true
            case .exportDialogToReadme:
                editor.playtestExportDestination = .readme
                editor.isExportDialogPresented = true
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
            case .startTour:
                break // handled above: it retargets the walk at the guide's window
            case .startTourHere:
                if let tour = TutorialLauncher.tour {
                    TutorialController.shared.restart(tour, in: editor)
                }
            case .showTutorials: coordinator.showTutorials()
            case .turnIntoPicture: editor.rasterizeSelection()
            case .showSettings: coordinator.showSettings()
            case .closeSettings:
                NSApp.windows.first { $0.title == SettingsWindowModel.windowTitle }?.close()
            case .showExperiments: coordinator.showExperiments()
            case .closeExperiments:
                NSApp.windows.first { $0.title == ExperimentsWindowController.windowTitle }?.close()
            case .readTutorialWindow, .pressTutorialStart:
                break // handled above: neither needs an editor
            case .freshInstall, .oldInstall, .launchHook, .expectWelcome,
                 .expectNoWelcome, .readWelcome, .takeTheTour, .startWorking,
                 .showWelcomeAgain, .screenRecordingOff, .screenRecordingOn, .tryToCapture:
                break // handled above: the first run happens before any document
            case .closeTutorials:
                NSApp.windows.first { $0.title == TutorialHubModel.windowTitle }?.close()
            case .tutorialNext: TutorialController.shared.next()
            case .tutorialBack: TutorialController.shared.back()
            case .tutorialClose: TutorialController.shared.close()
            case .tutorialFinishNext, .tutorialFinishStartYourOwn, .tutorialFinishMoreGuides:
                try pressFinishRow(action)
            case .toggleGrid: editor.toggleCanvasGrid()
            case .showGrid: if !editor.canvasGrid.isVisible { editor.toggleCanvasGrid() }
            case .hideGrid: if editor.canvasGrid.isVisible { editor.toggleCanvasGrid() }
            case .showIconKeylines:
                if !editor.iconKeylinesShowing { editor.toggleIconKeylines() }
            case .hideIconKeylines:
                if editor.iconKeylinesShowing { editor.toggleIconKeylines() }
            case .adjustGrid: editor.beginGridAdjustment()
            case .showGridSettings: editor.showGridSettings()
            case .selectCanvas: editor.selectCanvas()
            case .duplicateLayer: editor.duplicateSelectedLayers()
            case .newLayerViaCopy: editor.newLayerViaCopy()
            case .newLayerViaCut: editor.newLayerViaCut()
            case .newLayer: editor.newEmptyLayer()
            case .separateIntoLayers:
                if let id = editor.selectedLayerID { editor.separateIntoLayers(id: id) }
            case .turnIntoText:
                editor.turnIntoTextForSelection()
            case .fillWithForeground: editor.fillSelectedLayer(useBackground: false)
            case .fillWithBackground: editor.fillSelectedLayer(useBackground: true)
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
            case .floatSelectionInFront:
                editor.toggleFloating()
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
            case .videoBeginTrim, .videoTrimStart, .videoTrimEnd, .videoTrimDone, .videoTrimCancel,
                 .videoCopyGIF,
                 .videoSeekQuarter, .videoSeekMiddle, .videoSeekThreeQuarters,
                 .videoCut, .videoDeletePiece, .videoUndoEdit, .videoPlay, .videoPause,
                 .videoDragTrimNearCut, .videoDragTrimJustPastCut, .videoDragTrimClearOfCut,
                 .videoDragTrimFreedNearCut,
                 .videoDragTrimEndNearCut, .videoDragTrimRelease,
                 .videoSave, .videoCloseAndSave, .videoRevertToOriginal,
                 .videoExportSheet, .videoExportSheetAsGIF, .videoExportSheetAsHEIC,
                 .videoExportSheetCancel, .videoCropMiddle,
                 .openSampleRecording:
                break  // handled above, in the branch that asks for a recording
            }
            await sleep(0.2)
            let detail = (actionDetail.map { "\(action.rawValue) · \($0)" } ?? action.rawValue)
                + "; " + ViewBuildMeter.shared.report + "; " + MainThreadMeter.shared.report
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
        // A sheet is on top of the window, not a child of it, so it fell
        // outside this list and everything a sheet showed was unreachable: a
        // walk could photograph the New Frame sizes and never pick one. Its
        // named controls read exactly like the panel's.
        let sheet = host.attachedSheet.map { [$0] } ?? []
        // The Settings window is neither a child nor a sheet — it opens with no
        // document on screen at all, which is the state somebody is in when they
        // go looking for a setting — but its controls carry the same markers the
        // dock's do, so `press` and `expect` reach them the ordinary way. It is
        // in this list only while it is open.
        let settings = NSApp.windows.filter {
            $0.title == SettingsWindowModel.windowTitle && $0.isVisible
        }
        return [host] + attached + sheet + settings
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
        guard let match = ofKind.first(where: { PlaytestSteadyName.matches(name, steady: $0.steady) })
                ?? ofKind.first(where: { $0.name == name })
                ?? ofKind.first(where: { $0.detail == name })
                ?? ofKind.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            let seen = ofKind.map { target -> String in
                let names = target.everyName.joined(separator: " / ")
                return target.detail.isEmpty ? names : "\(names) / \(target.detail)"
            }.joined(separator: ", ")
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
    /// The same row, looked up again after a scroll: the view a lazily built
    /// list hands back is not the one it handed back before.
    private func panelScrollTarget(_ was: PanelTargetView) throws -> PanelTargetView {
        (try? panelScrollTarget(was.name)) ?? was
    }

    /// How far a scroll really went, out of what it was asked for. `scroll`
    /// reports in words for the log; this reads the number back out of it, and
    /// gives up and claims the whole ask when it cannot, so an unreadable
    /// report ends the rounds rather than repeating them.
    private static func distance(scrolled report: String, asked: Double) -> Double {
        guard let match = report.firstMatch(of: /(-?[0-9]+(?:\.[0-9]+)?)pt/) else { return asked }
        let size = Double(match.1) ?? abs(asked)
        return asked < 0 ? -abs(size) : abs(size)
    }

    private func panelScrollTarget(_ name: String) throws -> PanelTargetView {
        let all = try panelTargets()
        if let steady = all.first(where: { PlaytestSteadyName.matches(name, steady: $0.steady) }) {
            return steady
        }
        if let row = all.first(where: { $0.kind == .row && $0.name == name }) { return row }
        if let other = all.first(where: { $0.name == name })
            ?? all.first(where: { $0.detail == name })
            ?? all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return other
        }
        let seen = all.map { target -> String in
            let names = target.everyName.joined(separator: " / ")
            return target.detail.isEmpty ? names : "\(names) / \(target.detail)"
        }.joined(separator: ", ")
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
        // Waited for and scrolled to, the way a person does it: look for the
        // control, and if the dock has it below the fold, scroll until it is
        // where a press could land. A walk used to have to say `reveal` for
        // that, which means every walk goes stale the next time the dock grows
        // a section — which is exactly what happened to border-effect-walk and
        // three others.
        var (target, effort) = try await reachableTarget(name, in: row)
        // ...and not pressed until it has stopped moving, so the event lands
        // on the control rather than on whatever slid into its place.
        let steady = await settled(target, named: name, in: row)
        target = steady.target
        if !steady.effort.isEmpty { effort += (effort.isEmpty ? "" : ", ") + steady.effort }
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
             + (effort.isEmpty ? "" : "; " + effort)
             + "; " + MainThreadMeter.shared.report + "; " + ViewBuildMeter.shared.report,
             state: describe())
    }

    /// Clicks a row of the Measurements list by the name it shows, the way a
    /// person does.
    ///
    /// `selectRow` looked only at the layers list, and a press looks only for
    /// controls, so the Measurements rows were reachable for a right click and
    /// for nothing else. The most ordinary thing anyone does with that list
    /// went unproved, and the Redlining tutorial walk had to pick the same
    /// measurement out of the Layers list and explain itself in a note
    /// (tutorial-measurements-panel-walk, 2026-09-13).
    ///
    /// Real mouse events first, because a row covered by something, or
    /// scrolled until the panel's edge cuts across it, should fail a walk the
    /// way it fails a person. When the click does not take, the row's own
    /// handler runs instead and the log says so, which is what the layers list
    /// has always done. That second path is not a nicety:
    ///
    /// A synthesized click reaches a SwiftUI view only where something AppKit
    /// answers for it. A layer row can be picked up, so `onDrag` puts a real
    /// drag source under it and the click lands; a measurement row cannot be
    /// picked up and has nothing under it but SwiftUI, so while the app is not
    /// the active one the click reaches the row's buttons and never its
    /// `onTapGesture`. Measured on 2026-09-17 with a counter in the gesture:
    /// twenty clicks across the row fired it 0 times and fired the eye button
    /// beside it every time, and adding an `onDrag` to the row made the very
    /// first click fire it. So on a locked Mac — where nothing can be the
    /// active app — an honest-only step would report this list broken on every
    /// walk, which is the failure `PlaytestScreenState` exists to stop.
    ///
    /// Either way the selection is READ BACK afterwards, so a click that
    /// changed nothing is a walk that stops rather than a walk reporting a
    /// pass.
    private func clickMeasurementRow(_ name: String, click: RowClick,
                                     modifiers: [PlaytestModifier],
                                     layerNames: [String], number: Int) async throws {
        let editor = try requireEditor()
        let measurements = editor.measurePanelLayers
        func shown(_ layer: Layer) -> String { MeasureSpecList.displayName(for: layer) }
        guard let layer = measurements.first(where: { shown($0) == name })
                ?? measurements.first(where: {
                    shown($0).caseInsensitiveCompare(name) == .orderedSame
                }) else {
            func list(_ names: [String]) -> String {
                names.isEmpty ? "none" : names.joined(separator: ", ")
            }
            throw Failure(description: "no row called \"\(name)\" is in either list of rows. "
                + "The layers list has: " + list(layerNames) + ". "
                + "The Measurements list has: " + list(measurements.map(shown)) + ".")
        }
        let wanted = shown(layer)
        // Waited for and scrolled to, exactly as a press is: the Measurements
        // section sits low in the dock, so a walk that opened it and clicked
        // straight away would be clicking the panel's edge.
        var target = try await patiently { try self.measurementRowTarget(wanted) }
        var effort = ""
        if !Self.isInReach(target) {
            let moved = try await bringIntoReach(wanted) { try self.measurementRowTarget(wanted) }
            target = try measurementRowTarget(wanted)
            if moved > 0.5 { effort = "scrolled \(Int(moved))pt to reach it" }
        }
        // ...and not clicked until the row has stopped moving, or the event
        // lands on whatever slid into its place. A scroll down the dock is
        // exactly the thing that keeps a row moving.
        let steady = await settled(target, named: wanted) {
            try self.measurementRowTarget(wanted)
        }
        target = steady.target
        if !steady.effort.isEmpty { effort += (effort.isEmpty ? "" : ", ") + steady.effort }
        guard let window = target.window, window.contentView != nil else {
            throw Failure(description: "the row \"\(wanted)\" is in no window to click")
        }
        // A command click on a row already picked LETS IT GO, so what the
        // click promised is not always "selected": it is that this row's place
        // in the selection changed the way that click means.
        let before = editor.actionableLayerIDs
        let ends = click == .toggle ? !before.contains(layer.id) : true
        func landed() -> Bool { editor.actionableLayerIDs.contains(layer.id) == ends }

        MainThreadMeter.shared.install()
        MainThreadMeter.shared.reset()
        ViewBuildMeter.shared.reset()
        let flags = eventFlags(modifiers)
        let stamp = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(
                with: .leftMouseDown, location: target.point, modifierFlags: flags, timestamp: stamp,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(
                with: .leftMouseUp, location: target.point, modifierFlags: flags,
                timestamp: stamp + 0.05, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 0) else {
            throw Failure(description: "could not make a mouse event for the row \"\(wanted)\"")
        }
        NSApp.postEvent(down, atStart: false)
        NSApp.postEvent(up, atStart: false)
        await sleep(0.35)
        var how = "clicked at window \(short(target.point))"
        if !landed() {
            // Nothing under the row answered the click. Its own handler is what
            // the tap would have called, over this list's order, so shift and
            // command still mean here what they mean in the layers list.
            editor.clickRow(layer.id, click, in: editor.measurePanelLayers.map(\.id))
            await sleep(0.2)
            how = "the click at window \(short(target.point)) did not land"
                + (NSApp.isActive ? "" : " (Photonz is not the active app, so a row with nothing "
                   + "AppKit answers for takes no synthesized click)")
                + ", so the row's own handler ran instead"
        }
        try await patiently {
            guard landed() else {
                let now = editor.actionableLayerIDs
                throw Failure(description: "the row \"\(wanted)\" was clicked at window "
                    + "\(self.short(target.point)) and the selection did not move: it is still "
                    + (now.isEmpty ? "empty" : "\(now.count) layer\(now.count == 1 ? "" : "s")")
                    + ". Something is covering the row, or the panel slid under the click.")
            }
        }
        let picked = editor.actionableLayerIDs
        note(number, "selectRow",
             "picked \"\(wanted)\" out of the Measurements list"
                + (layer.isVisible ? "" : " (hidden)")
                + " with a \(click) click; " + how
                + (effort.isEmpty ? "" : "; " + effort)
                + "; \(picked.count) layer\(picked.count == 1 ? "" : "s") picked now"
                + "; " + MainThreadMeter.shared.report + "; " + ViewBuildMeter.shared.report,
             state: describe())
    }

    /// One row of the Measurements list, as something a click can land on.
    /// The marker behind the row is a position only, so this is the same
    /// reading a press makes of a control's marker.
    private func measurementRowTarget(_ name: String) throws -> PlaytestPressTarget {
        let rows = try panelTargets().filter {
            $0.kind == .row && $0.detail.hasPrefix("measurement")
        }
        guard let row = rows.first(where: { $0.name == name })
                ?? rows.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            let seen = rows.map(\.name).joined(separator: ", ")
            throw Failure(description: "the Measurements list is not showing a row called "
                + "\"\(name)\"; it is showing: " + (seen.isEmpty ? "none" : seen)
                + ". Is the panel open and the Measurements section unfolded?")
        }
        let frame = row.convert(row.bounds, to: nil)
        return PlaytestPressTarget(name: row.name, detail: row.detail,
                                   point: CGPoint(x: frame.midX, y: frame.midY),
                                   box: frame,
                                   visible: row.convert(row.visibleRect, to: nil),
                                   isEnabled: true, window: row.window)
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
    /// One bar on the timing strip, dragged (`next-motion-strip`).
    ///
    /// It drives the strip's own drag rather than posting mouse events, for the
    /// reason written on `PanelAreaHandleProbe`: SwiftUI gestures do not answer
    /// synthesized ones. Everything the drag DECIDES is real — where the bar
    /// lands, what it caught on, what the gap reads, whether the lap was held
    /// so the bar could overrun it, and that the whole thing is one step to
    /// undo — and only the pointer that would have started it is not.
    /// One Escape, put into the app's own event queue and left to arrive the
    /// way every other key does: dequeued by the run loop, offered to whatever
    /// is watching, then dispatched. A key handed straight to a window skips
    /// the watching part, which is exactly the part a cancel has to prove.
    private func postEscapeThroughTheApp() async throws {
        let window = try keyTarget(.escape)
        guard let down = keyEvent(.escape, flags: [], down: true, in: window),
              let up = keyEvent(.escape, flags: [], down: false, in: window) else {
            throw Failure(description: "could not build an Escape press")
        }
        NSApp.postEvent(down, atStart: false)
        NSApp.postEvent(up, atStart: false)
        await sleep(0.2)
    }

    private func dragTiming(_ bar: String, grab: PlaytestTimingGrab, byMS: Int,
                            hold: String?, cancelBy: PlaytestTimingCancel,
                            cancel: Bool, number: Int) async throws {
        let editor = try requireEditor()
        guard editor.hasMotionStrip else {
            throw Failure(description: "there is no timing strip: either nothing in this document "
                + "moves, or next-motion-strip is off")
        }
        guard editor.isMotionStripShown else {
            throw Failure(description: "the timing strip is put away, so its bars are not on "
                + "screen to be dragged. Show it with \u{2325}\u{2318}T first.")
        }
        let lanes = editor.motionStripGroups.flatMap { group in
            group.lanes.map { (name: "\(group.layerName) \($0.title)", lane: $0) }
        }
        guard let found = lanes.first(where: {
            $0.name.compare(bar, options: .caseInsensitive) == .orderedSame
        }) else {
            throw Failure(description: "there is no bar called \"\(bar)\" on the timing strip; "
                + "there is \(lanes.isEmpty ? "none at all" : lanes.map(\.name).joined(separator: ", "))")
        }
        let before = found.lane.timing
        let heldCycle = editor.document?.motionCycleLengthMS ?? 0

        editor.beginMotionTimingDrag(motionID: found.lane.motionID, grab: grab.grab)
        // Carried in a handful of moves rather than one jump, the way a hand
        // does it, so anything that only shows up mid-drag — the bracket, the
        // preview pausing, the side column following — really happens.
        for fraction in [0.35, 0.7, 1.0] {
            editor.updateMotionTimingDrag(byMS: Int((Double(byMS) * fraction).rounded()))
            await sleep(0.05)
        }
        let inHand = editor.motionTimingDrag
        if let hold, let window = try? requireWindow(), let content = window.contentView {
            try snapshot(content, name: hold)
            await screenCapture(window, name: hold)
        }
        if cancel {
            switch cancelBy {
            case .strip:
                editor.cancelMotionTimingDrag()
            case .escape:
                // A real press, posted into the app rather than handed to a
                // view, because what is being tested is whether ANYTHING is
                // listening: the strip's watch sits on the app's own event
                // stream, which is where a key off a keyboard arrives.
                try await postEscapeThroughTheApp()
            }
            await sleep(0.3)
            let after = editor.motionStripGroups.flatMap(\.lanes)
                .first { $0.motionID == found.lane.motionID }?.timing
            let how = cancelBy == .escape ? "Escape" : "the strip's own call-off"
            guard editor.motionTimingDrag == nil else {
                throw Failure(description: "\(how) did not let go of \(bar): it is still in hand "
                    + "at \(editor.motionTimingDrag?.timing.startMS ?? -1) ms")
            }
            guard after == before else {
                throw Failure(description: "the drag was called off with \(how) and \(bar) did "
                    + "not go back: it started at \(before.startMS)-\(before.endMS) ms and is "
                    + "now at \(after.map { "\($0.startMS)-\($0.endMS)" } ?? "gone")")
            }
            note(number, "dragTiming",
                 "\(bar) carried \(byMS) ms and called off with \(how); it is back at "
                 + "\(before.startMS) to \(before.endMS) ms",
                 state: describe())
            return
        }
        editor.commitMotionTimingDrag()
        await sleep(0.4)
        guard let after = editor.motionStripGroups.flatMap(\.lanes)
            .first(where: { $0.motionID == found.lane.motionID })?.timing else {
            throw Failure(description: "\(bar) is not on the strip any more after the drag")
        }
        let cycle = editor.document?.motionCycleLengthMS ?? 0
        var said = "\(bar) \(grab.rawValue) dragged \(byMS) ms: "
            + "\(before.startMS)-\(before.endMS) ms became \(after.startMS)-\(after.endMS) ms"
        if let snap = inHand?.snappedTo { said += "; caught on \(snap.name) at \(snap.ms) ms" }
        if let gap = inHand?.gap { said += "; gap read \"\(gap.reading)\"" }
        said += "; one cycle \(heldCycle) ms became \(cycle) ms"
            + (editor.motionCycleIsAutomatic ? " (follows the longest)" : " (held)")
        if after.endMS > cycle { said += "; the bar runs \(after.endMS - cycle) ms past the restart" }
        if let hold { said += "; held \(hold).png" }
        note(number, "dragTiming", said, state: describe())
    }

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
        // An "in" may name more than one row at once, outermost first, because
        // a Border holds a Width and so does the Border under it: `"@border,
        // Width"`. Each piece is asked for on its own and every one has to
        // hold, so the pieces may be words, steady names, or a mix -- which is
        // what lets the steady name be used on the rows that need it without
        // rewriting the word beside it.
        let pieces = wanted.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !pieces.isEmpty else { return targets }
        func holds(_ target: PlaytestPressTarget, _ piece: String) -> Bool {
            if PlaytestSteadyName.isSteady(piece) {
                return target.steadyRows.contains { $0.caseInsensitiveCompare(piece) == .orderedSame }
            }
            return target.detail.split(separator: ",").contains {
                $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(piece) == .orderedSame
            }
        }
        let whole = targets.filter { target in pieces.allSatisfy { holds(target, $0) } }
        // The loose pass is words only, and it is what lets `in: "Border"`
        // reach the controls of a row the panel is calling "Border 2" because
        // a second one arrived. A steady name never takes it: it is the one
        // thing a walk can write that promises to mean exactly one row, and
        // handing "@shadow" the second shadow because nothing matched outright
        // would break the only promise it makes (`PlaytestSteadyName`).
        guard whole.isEmpty, !pieces.contains(where: PlaytestSteadyName.isSteady) else { return whole }
        return targets.filter { $0.detail.range(of: wanted, options: .caseInsensitive) != nil }
    }

    private func pressTarget(_ name: String, in row: String?) throws -> PlaytestPressTarget {
        // A steady name belongs to a labelled ROW, never to the control on it:
        // Switch, Color and Slider are structural words that no copy edit
        // touches, so they have nothing steadier to be. Left to fall through,
        // "@border" would match the row's name sitting in every one of its
        // controls' details and press whichever came first, which is the silent
        // wrong press this whole idea exists to stop.
        if PlaytestSteadyName.isSteady(name) {
            throw Failure(description: "\"\(name)\" is a steady name, and a steady name names the ROW "
                + "a control sits on, not the control. Put it in \"in\" and name the control by its "
                + "own word: { \"control\": \"Switch\", \"in\": \"\(name)\" }.")
        }
        let everything = try pressTargets()
        let all = Self.narrow(everything, to: row)
        let inRow = row.map { " in \"\($0)\"" } ?? ""
        // A steady name that reaches no row at all is its own failure, and it
        // has to read as one: "there is no such row", not "there is no such
        // control", which is what an empty narrowing leaves behind. The steady
        // names that ARE on screen go in the message, because that is the list
        // the author needs and they are spelled ready to paste.
        if let row, PlaytestSteadyName.isSteady(row), all.isEmpty {
            let seen = Array(Set(everything.flatMap(\.steadyRows))).sorted().joined(separator: ", ")
            throw Failure(description: "no row called \"\(row)\" is in the panel, so there is nothing "
                + "on it to press; the steady names on screen: " + (seen.isEmpty ? "none" : seen)
                + ". A `panel` step lists everything.")
        }
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
                                       says: target.detail,
                                       steadyRows: PlaytestPanelPress.steadyFields(of: target,
                                                                                   among: fields),
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
        let target = try await patiently { try self.pressTarget(name, in: row) }
        guard !Self.isInReach(target) else {
            note(number, "reveal",
                 "\"\(target.name)\"\(target.detail.isEmpty ? "" : " in \(target.detail)") "
                 + "was already where a person could press it; nothing scrolled",
                 state: describe())
            return
        }
        ViewBuildMeter.shared.reset()
        MainThreadMeter.shared.reset()
        let moved = try await bringIntoReach(name, in: row)
        let landed = try pressTarget(name, in: row)
        note(number, "reveal",
             "\"\(landed.name)\"\(landed.detail.isEmpty ? "" : " in \(landed.detail)") "
             + "brought into reach by scrolling \(Int(moved))pt, now at window \(short(landed.point))"
             + "; " + ViewBuildMeter.shared.report + "; " + MainThreadMeter.shared.report,
             state: describe())
    }

    /// Scrolls whatever the named control sits in until a press could land on
    /// it, and says how many points that took. Throws when nothing can bring
    /// it in, with the reason.
    ///
    /// Split out of `reveal` because a press does this for itself now: a
    /// person who cannot see the control they want scrolls to it without
    /// being told to, and a walk that has to be told is a walk that goes stale
    /// the next time the dock grows a section (`pressControl`).
    @discardableResult
    private func bringIntoReach(_ name: String, in row: String?) async throws -> Double {
        try await bringIntoReach(name) { try self.pressTarget(name, in: row) }
    }

    /// The same, for anything a walk can point at. `look` reads where the
    /// thing is RIGHT NOW, because each turn of a scroll moves it and a lazily
    /// built list hands back a different view every time. A row of the
    /// Measurements list is found its own way and scrolls to exactly like a
    /// control (`clickMeasurementRow`).
    @discardableResult
    private func bringIntoReach(_ name: String,
                                look: () throws -> PlaytestPressTarget) async throws -> Double {
        let target = try look()
        guard !Self.isInReach(target) else { return 0 }
        guard let window = target.window, let content = window.contentView else {
            throw Failure(description: "the control \"\(name)\" is in no window to scroll")
        }
        var moved = 0.0
        var stuck = ""
        // Six rounds is generous: each one closes the whole measured gap, and
        // the rounds after the first are for the row heights that changed
        // under it. A dock that has not arrived in six is not going to.
        for _ in 0..<6 {
            let current = try look()
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
        let landed = try look()
        guard Self.isInReach(landed) else {
            throw Failure(description: "scrolled \(Int(moved))pt and \"\(name)\" is still not "
                + "where a person could press it"
                + (stuck.isEmpty ? "" : ": " + stuck)
                + ". The window may be too short for the section it is in.")
        }
        return moved
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
                              inRow: String?) throws
    -> (found: Bool, reads: String, says: String, others: [String]) {
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
                // A number a person can see but cannot type into is not a box
                // at all: it is a readout, and it says its words to the probe
                // rather than to accessibility (`PanelReadoutProbe`). Ask
                // those too, or a field that goes read-only goes dark to a
                // walk at the very moment what it says matters most — which is
                // how the Position & Size numbers vanished from a walk the day
                // a layer with nothing on it started reporting dashes.
                let readings = try namedPanelReadings()
                func lastPart(_ name: String) -> String {
                    name.components(separatedBy: " \u{25B8} ").last ?? name
                }
                if let reading = readings.first(where: { matches(lastPart($0.name)) }) {
                    return (true, reading.reads, reading.reads, [])
                }
                let names = boxes.compactMap { labels($0).first }.filter { !$0.isEmpty }
                return (false, "", "", names + readings.map { lastPart($0.name) })
            }
            // While a field is being typed into, the words live in the window's
            // field editor and the control still holds the value it had before
            // the caret arrived. Read the editor when there is one, or a walk
            // can never claim what a `key` step just typed.
            let showing = match.currentEditor()?.string ?? match.stringValue
            return (true, showing, showing, [])
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
                return (false, "", "", menus.map(\.0))
            }
            return (true, match.1, match.1, [])
        case .control:
            let everything = try pressTargets()
            let controls = Self.narrow(everything, to: inRow)
            guard let match = controls.first(where: { matches($0.name) }) else {
                // An "in" that reached no row leaves nothing to list, and "the
                // ones that are: none" tells an author nothing. Name the steady
                // rows that ARE on screen instead, spelled ready to paste.
                if let inRow, PlaytestSteadyName.isSteady(inRow), controls.isEmpty {
                    return (false, "", "", Array(Set(everything.flatMap(\.steadyRows))).sorted())
                }
                return (false, "", "", controls.map(\.name))
            }
            return (true, match.detail, match.says, [])
        case .row, .tile:
            let kind: PanelTargetKind = thing == .row ? .row : .tile
            let targets = try panelTargets().filter { $0.kind == kind }
            return (targets.contains { matches($0.name) }, named, named, targets.map(\.name))
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
                    if let inRow {
                        let names = PlaytestSteadyName.isSteady(inRow)
                            ? PlaytestPanelPress.steadyFields(of: button, among: fields)
                            : PlaytestPanelPress.fields(of: button, among: fields)
                        guard names.contains(where: { $0.caseInsensitiveCompare(inRow) == .orderedSame })
                        else { continue }
                    }
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
                return (false, "", "", talking.map(\.name))
            }
            return (true, match.says, match.says, [])
        }
    }

    /// Hold the panel to what the walk says it is showing.
    /// What the app is HOLDING, checked by name: every layer a menu row would
    /// act on, in draw order. A snapshot cannot photograph a pick that is
    /// missing — the rows simply sit there unhighlighted — so this is the step
    /// that fails a walk when an undo hands back the drawing without the
    /// picking.
    /// Whether the layers list moved under the last pick, and whether that is
    /// what the walk claimed.
    ///
    /// The list's first rule is that a row you can ALREADY see wins: picking
    /// something near the top must not jolt the panel. That decision is
    /// arithmetic done once and thrown away, so a picture taken after the
    /// scroll has settled looks the same whether the list moved or stood
    /// still. This is the only way to ask.
    private func checkListStill(moved wanted: Bool) throws -> String {
        guard let happened = LayersListProbe.shared.lastRevealMoved,
              let said = LayersListProbe.shared.lastReveal else {
            throw Failure(description: "the layers list has not been asked to reveal anything yet, "
                + "so there is nothing to claim about it. Pick a layer before this step, and "
                + "check the layers follow a pick at all in this release.")
        }
        guard happened == wanted else {
            throw Failure(description: wanted
                ? "the layers list was expected to follow the pick and bring the row in, and it "
                    + "stayed where it was: \(said)"
                : "the layers list was expected to stay exactly where the reader left it, and it "
                    + "moved: \(said). A row you can already see wins; a click that jolts the "
                    + "panel is the complaint that rule exists for.")
        }
        return wanted ? "the list followed the pick: \(said)" : "the list did not move: \(said)"
    }

    /// Fails the run unless the window's unsaved state is what the walk claims.
    ///
    /// The promise worth pinning with it: what the app works out on its own —
    /// the words read off a separated picture — is kept with the document but
    /// never counts as work the person has to save.
    private func checkEdited(_ edited: Bool) throws -> String {
        let editor = try requireEditor()
        guard editor.hasUnsavedChanges == edited else {
            throw Failure(description: edited
                ? "closing this window would lose nothing, and the walk says it should be holding unsaved changes"
                : "this window is holding unsaved changes, and the walk says nothing should be unsaved here")
        }
        return edited ? "unsaved changes, as claimed" : "nothing unsaved, as claimed"
    }

    /// Fails the run unless the icon previews strip is showing exactly these
    /// sizes, or is not there at all.
    ///
    /// The failure says which icon frame the strip is speaking for and which
    /// ones the document holds, because the two ways this goes wrong are "the
    /// strip is gone" and "the strip is showing the wrong icon", and a bare
    /// list of numbers tells them apart from neither.
    private func checkIconPreviews(sides: [Int], absent: Bool) throws -> String {
        let editor = try requireEditor()
        let showing = editor.iconPreviewTiles.map { Int($0.side) }
        let frameID = editor.iconPreviewFrameID
        let named = frameID.flatMap { editor.document?.layer(id: $0)?.name } ?? "no icon"
        let icons = (editor.document?.allLayers ?? [])
            .filter { editor.document?.isIconFrame(id: $0.id) == true }
            .map(\.name)
        let inTheDocument = icons.isEmpty ? "none" : icons.joined(separator: ", ")
        func list(_ values: [Int]) -> String {
            values.isEmpty ? "nothing" : values.map(String.init).joined(separator: ", ")
        }
        if absent {
            guard showing.isEmpty else {
                throw Failure(description: "the icon previews strip is showing \(list(showing)) "
                    + "for \"\(named)\", and this step claims there should be no strip at all; "
                    + "icon frames in the document: \(inTheDocument)")
            }
            return "no icon previews strip, as claimed"
        }
        guard showing == sides else {
            throw Failure(description: "the icon previews strip is showing \(list(showing)), "
                + "not \(list(sides)); it is speaking for \"\(named)\", and the icon frames in "
                + "the document are: \(inTheDocument)")
        }
        return "icon previews for \"\(named)\" at \(list(showing)), as claimed"
    }

    /// Whether the canvas is showing the picture drawn at the size it is being
    /// shown at, rather than a document-sized picture blown up.
    ///
    /// Waits for it, because it never arrives with the frame: the sharp copy is
    /// asked for a tenth of a second after whatever changed and drawn off the
    /// main thread. A step that read the state the instant it ran would pass
    /// or fail on the machine's mood.
    private func checkSharp(absent: Bool, within: Double) async throws -> String {
        let editor = try requireEditor()
        func reading() -> (tile: CrispTile?, matches: Bool) {
            guard let tile = editor.crispTile else { return (nil, false) }
            return (tile, editor.crispTileViewport == editor.viewport)
        }
        func zoom() -> String {
            guard let viewport = editor.viewport else { return "no camera" }
            return "\(Self.round1(viewport.zoom * 100))%"
        }
        if absent {
            // Nothing to wait for: give the app the same beat it would have had
            // to draw one, then claim it did not.
            await sleep(min(within, 1))
            let now = reading()
            guard now.tile == nil else {
                throw Failure(description: "the canvas IS showing a sharp copy of what is in the "
                    + "window, drawn at \(Self.round1(now.tile?.scale ?? 0)) pixels per document "
                    + "point, and this step claims there should be none at \(zoom())")
            }
            return "no sharp copy at \(zoom()), as claimed"
        }
        let began = CACurrentMediaTime()
        while CACurrentMediaTime() - began < within {
            let now = reading()
            if let tile = now.tile, now.matches {
                let waited = Self.round1(CGFloat(CACurrentMediaTime() - began))
                return "the canvas is drawn at the size it is shown at: \(Self.round1(tile.scale)) "
                    + "pixels per document point over \(Self.round1(tile.region.width))×"
                    + "\(Self.round1(tile.region.height)) points at \(zoom()), after \(waited)s"
            }
            await sleep(0.05)
        }
        let now = reading()
        let instead = now.tile == nil
            ? "there is none, so every shape on screen is the document's own pixels blown up"
            : "the one it has was drawn for a different camera and is not being shown"
        throw Failure(description: "the canvas is not showing a sharp copy of what is in the "
            + "window at \(zoom()): \(instead). Waited \(Self.round1(CGFloat(within)))s. A shape drawn on "
            + "an icon frame reads as 1-document-pixel blocks like this.")
    }

    private func checkPicked(_ layers: [String]) throws -> String {
        let editor = try requireEditor()
        let picked = editor.actionableLayerIDs
        let all = editor.document?.allLayers ?? []
        // A walk names a layer the way the layers LIST names it, which for a
        // separated run of text is the words read off its picture rather than
        // the "Text 48" it is stored under. Either answers: a walk written
        // before the rows could say their words still names them the old way,
        // and one written since names what is on screen.
        let words = editor.readWordsForRows
        let holding = all.filter { picked.contains($0.id) }
        let said = holding.map { $0.displayName(readWords: words) }
        func list(_ names: [String]) -> String { names.isEmpty ? "nothing" : names.joined(separator: ", ") }
        let asClaimed = holding.count == layers.count
            && zip(holding, layers).allSatisfy { $0.name == $1 || $0.displayName(readWords: words) == $1 }
        guard asClaimed else {
            throw Failure(description: "the layers picked are \(list(said)), not \(list(layers)); "
                + "the ones in the document: \(list(all.map { $0.displayName(readWords: words) }))")
        }
        return "picked: \(list(said)), as claimed"
    }

    /// Fails the run unless exactly `count` measurements are on the canvas.
    ///
    /// The failure names what a half-placed caliper is still waiting for, so a
    /// walk that stops one click short of landing one reads as a walk that
    /// stopped one click short, rather than as an empty list nobody explains.
    /// How many editor windows are wearing this title.
    ///
    /// Panels are left out: a guide's own callout and the app's tooltip are
    /// both panels, and neither is a window somebody was left holding. The
    /// release badge is left out too, because Next writes its name into every
    /// window title ("Tutorial Sample (Next)") and a walk claiming what is on
    /// screen is not claiming which release wrote it.
    private func checkWindows(titled: String, count: Int) throws -> String {
        func wears(_ title: String) -> Bool {
            title == titled || (title.hasPrefix(titled + " (") && title.hasSuffix(")"))
        }
        let open = NSApp.windows.filter {
            $0.isVisible && !($0 is NSPanel) && wears($0.title)
        }
        func plural(_ n: Int) -> String { n == 1 ? "window" : "windows" }
        guard open.count == count else {
            let others = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }
                .map { $0.title.isEmpty ? "(untitled)" : $0.title }
            throw Failure(description: "\(open.count) \(plural(open.count)) called "
                + "\"\(titled)\" are open, not \(count); every window up: "
                + others.joined(separator: ", "))
        }
        return count == 0
            ? "no window called \"\(titled)\" is left, as claimed"
            : "\(count) \(plural(count)) called \"\(titled)\", as claimed"
    }

    /// One of the rows on the card a guide ends on, pressed by what it does.
    private func pressFinishRow(_ action: PlaytestAction) throws {
        guard let finish = TutorialController.shared.finished else {
            throw Failure(description: "no guide has finished, so there is no card to press"
                + "; the guide is \(TutorialController.shared.liveDescription(in: window))")
        }
        let wanted: String
        switch action {
        case .tutorialFinishNext: wanted = "next"
        case .tutorialFinishStartYourOwn: wanted = "startYourOwn"
        case .tutorialFinishMoreGuides: wanted = "moreGuides"
        default: return
        }
        guard let choice = finish.choices.first(where: { $0.name == wanted }) else {
            throw Failure(description: "the card at the end of \(finish.guideID) does not offer "
                + "\"\(wanted)\"; it offers "
                + finish.choices.map(\.name).joined(separator: ", "))
        }
        TutorialController.shared.choose(choice)
    }

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

    /// What the document would be WRITTEN as, without saving anything.
    ///
    /// The whole file is built here, because the question is about the file
    /// rather than about the canvas: a mark that has quietly gone back to
    /// riding out as a picture looks exactly the same on screen.
    private func checkSVG(pictured: Int?, contains: String?) throws -> String {
        let editor = try requireEditor()
        guard let document = editor.document else {
            throw Failure(description: "there is no document to write")
        }
        let animation: SVGExport.Animation = document.hasMotion
            ? .moving(cycleMS: document.motionCycleLengthMS) : .still
        let written = SVGExporter.export(document, store: editor.store, animation: animation)
        var said: [String] = []
        if let pictured {
            let names = written.fallbacks.map(\.layerName)
            guard names.count == pictured else {
                let listed = written.fallbacks
                    .map { "\($0.layerName) (\($0.reason))" }.joined(separator: ", ")
                throw Failure(description: "\(names.count) of the drawing's layers would go out"
                    + " as pictures, not \(pictured)"
                    + (listed.isEmpty ? "" : ": \(listed)"))
            }
            said.append(pictured == 0
                ? "every layer would go out as shapes, as claimed"
                : "\(pictured) would go out as a picture, as claimed")
        }
        if let contains {
            guard written.text.contains(contains) else {
                throw Failure(description: "the file does not carry \"\(contains)\"")
            }
            said.append("the file carries \"\(contains)\"")
        }
        return said.joined(separator: "; ")
    }

    /// Where a measurement's two ends are, and what it reads.
    ///
    /// Asked of the document rather than of a picture: a foot is a dot a few
    /// points across, and "it went six right" and "it went two left" are the
    /// same screenshot to anything but a pixel count. The failure says where
    /// the feet actually are and what the thing reads, because "the foot went
    /// the wrong way" and "the foot never moved" are different bugs.
    /// Where a named layer's box actually is, held against what a walk claimed.
    ///
    /// Two spaces, because a piece inside a card that has been TURNED needs
    /// both to be pinned down. `at`/`size` are the box the layer's own panel
    /// shows, in CANVAS coordinates — the same units the tree prints and the
    /// same units a walk's clicks are written in — which is what says the piece
    /// moved by exactly what the hand moved. `corner`/`onScreen` are one corner
    /// where a person SEES it, after the layer's own turn and every card's
    /// above it, which is what says a resize held the far corner still.
    private func checkBox(_ layerName: String, at: PlaytestPoint?, size: PlaytestPoint?,
                          corner: LayerBoxCorner?, onScreen: PlaytestPoint?,
                          reachable: Bool, within: CGFloat) throws -> String {
        let editor = try requireEditor()
        guard let document = editor.document else {
            throw Failure(description: "no document is open, so there is no box to claim")
        }
        let all = document.allLayers
        guard let found = all.first(where: { $0.name.lowercased() == layerName.lowercased() }) else {
            throw Failure(description: "no layer called \"\(layerName)\" in the document"
                + (all.isEmpty ? "; it is empty"
                   : "; there is " + all.map(\.name).joined(separator: ", ")))
        }
        guard let box = document.canvasBounds(of: found.id) else {
            throw Failure(description: "\"\(layerName)\" is in the document but not on the canvas")
        }
        var held: [String] = []
        if let at {
            let off = max(abs(box.minX - at.point.x), abs(box.minY - at.point.y))
            guard off <= within else {
                throw Failure(description: "\"\(layerName)\" sits at \(short(box.origin)) and the "
                    + "step claimed \(short(at.point)): \(Self.round1(off)) points out, and the walk "
                    + "allowed \(Self.round1(within))")
            }
            held.append("at \(short(box.origin))")
        }
        if let size {
            let off = max(abs(box.width - size.point.x), abs(box.height - size.point.y))
            guard off <= within else {
                throw Failure(description: "\"\(layerName)\" is \(Self.round1(box.width)) by "
                    + "\(Self.round1(box.height)) and the step claimed \(Self.round1(size.point.x)) by "
                    + "\(Self.round1(size.point.y)): \(Self.round1(off)) points out, and the walk "
                    + "allowed \(Self.round1(within))")
            }
            held.append("size \(Self.round1(box.width))x\(Self.round1(box.height))")
        }
        if reachable {
            // The canvas is both how far the camera may scroll and how much
            // the renderer paints, so a box past its edge is a layer nothing
            // draws and nothing can be scrolled to.
            let canvas = CGRect(origin: .zero, size: document.canvasSize)
            guard canvas.contains(box) else {
                throw Failure(description: "\"\(layerName)\" is at "
                    + "\(Self.round1(box.minX)), \(Self.round1(box.minY)) and runs to "
                    + "\(Self.round1(box.maxX)), \(Self.round1(box.maxY)) on a canvas that is only "
                    + "\(Self.round1(canvas.width)) by \(Self.round1(canvas.height)). The camera "
                    + "cannot go past the canvas and the renderer does not paint past it, so that "
                    + "part of the layer is somewhere nobody can look")
            }
            held.append("on the canvas (\(Self.round1(canvas.width)) by "
                + "\(Self.round1(canvas.height)))")
        }
        if let corner, let onScreen {
            // The corners of the box as DRAWN: the layer placed on the canvas,
            // turned by its own transform, then swung by every card above it.
            var placed = found
            placed.frame = found.localBounds.offsetBy(dx: box.minX - found.localBounds.minX,
                                                      dy: box.minY - found.localBounds.minY)
            let turn = document.inheritedTurn(of: found.id)
            let corners = placed.transformedCorners.map { $0.applying(turn) }
            guard corners.indices.contains(corner.index) else {
                throw Failure(description: "\"\(layerName)\" has no corners to claim")
            }
            let point = corners[corner.index]
            let off = hypot(point.x - onScreen.point.x, point.y - onScreen.point.y)
            guard off <= within else {
                throw Failure(description: "\"\(layerName)\"'s \(corner.rawValue) corner is at "
                    + "\(short(point)) on screen and the step claimed \(short(onScreen.point)): "
                    + "\(Self.round1(off)) points out, and the walk allowed \(Self.round1(within))")
            }
            held.append("\(corner.rawValue) on screen \(short(point))")
        }
        return "\"\(layerName)\" " + held.joined(separator: ", ")
    }

    private func checkFeet(_ layerName: String?, start: PlaytestPoint?, end: PlaytestPoint?,
                           reads: String?, within: CGFloat) throws -> String {
        let editor = try requireEditor()
        guard let document = editor.document else {
            throw Failure(description: "no document is open, so nothing has been measured")
        }
        let measured = document.allLayers.filter { $0.measure != nil }
        let layer: Layer
        if let layerName {
            guard let found = measured.first(where: {
                MeasureSpecList.displayName(for: $0).lowercased() == layerName.lowercased()
            }) else {
                throw Failure(description: "no measurement called \"\(layerName)\" on the canvas"
                    + (measured.isEmpty ? "; nothing has been measured"
                       : "; there is \(measured.map { MeasureSpecList.displayName(for: $0) }.joined(separator: ", "))"))
            }
            layer = found
        } else {
            guard measured.count == 1, let only = measured.first else {
                throw Failure(description: measured.isEmpty
                    ? "nothing has been measured, so there are no feet to claim"
                    : "\(measured.count) measurements are on the canvas, so expectFeet has to say "
                      + "which one with \"layer\": \(measured.map { MeasureSpecList.displayName(for: $0) }.joined(separator: ", "))")
            }
            layer = only
        }
        guard let measure = layer.measure else {
            throw Failure(description: "that layer is not a measurement")
        }
        let feet = MeasureSnapping.documentMeasure(layer)
        let actualStart = feet?.start ?? measure.start
        let actualEnd = feet?.end ?? measure.end
        let label = measure.label(pixelScale: document.pixelScale)
        let where_ = "feet \(short(actualStart)) to \(short(actualEnd)), reading \(label)"
        func check(_ claim: PlaytestPoint?, _ actual: CGPoint, _ name: String) throws {
            guard let claim else { return }
            let want = try documentPoint(claim)
            let off = hypot(actual.x - want.x, actual.y - want.y)
            guard off <= within else {
                throw Failure(description: "the \(name) foot is \(short(actual)), not \(short(want)): "
                    + "\(Self.round1(off)) document points away and a walk allowed \(Self.round1(within)). "
                    + "The measurement is \(where_)")
            }
        }
        try check(start, actualStart, "first")
        try check(end, actualEnd, "second")
        if let reads, label != reads {
            throw Failure(description: "the measurement reads \(label), not \(reads). It is \(where_)")
        }
        return "\(where_), as claimed"
    }

    /// How many layers the document holds, groups and their children counted.
    ///
    /// The panel renders the rows you can see and no more, so a claim about a
    /// hundred layers has to be asked of the document. The failure says the
    /// number it found and the first few names, because "138, not at least
    /// 150" is a different bug from "1, not at least 150".
    /// The chip under the canvas as one line, read in the ORDER the editor
    /// stacks them (`EditorView.canvas`), so what a walk reads is what is on
    /// screen rather than the first one that happens to be true.
    static func hintReading(_ editor: EditorState) -> String {
        if editor.showsMeasureHint {
            return "\(editor.measureHintTitle ?? "") · \(editor.measureHintText)"
        }
        if editor.showsPathEditHint {
            return "\(PathEditHint.title) · \(editor.pathEditHintText)"
        }
        if editor.showsPenHint {
            return "\(PenSession.hintTitle) · \(editor.penHintText)"
        }
        return "none"
    }

    /// The words the chip must be carrying right now.
    /// What the canvas says a press would put the first point of a shape on:
    /// the document point the hover mark is sitting on, or nothing at all.
    ///
    /// It reads `liveDrawLanding`, which is the same point the press uses, so a
    /// walk that passes here has proved the mark and the press agree rather
    /// than that a ring is drawn somewhere.
    private func checkLanding(near: PlaytestPoint?, within: CGFloat,
                              absent: Bool) throws -> String {
        let canvas = try requireCanvas()
        let landing = canvas.liveDrawLanding
        if absent {
            guard landing == nil else {
                throw Failure(description: "nothing should be marking where a press would land "
                    + "right now, and the canvas is marking \(short(landing!)). Either the "
                    + "point really is being moved and the walk is wrong about it, or the mark is "
                    + "outliving the thing that put it there.")
            }
            return "no mark: a press would land exactly where the pointer is"
        }
        guard let near else { return "nothing claimed" }
        guard let landing else {
            throw Failure(description: "nothing is marking where a press would land, and the walk "
                + "expects a mark on \(short(near.point)). With the grid on, every tool that "
                + "starts a shape marks its landing; check the grid is on, Snap to grid is on, and "
                + "the pointer is over the canvas.")
        }
        let wanted = try documentPoint(near)
        let off = hypot(landing.x - wanted.x, landing.y - wanted.y)
        guard off <= within else {
            throw Failure(description: "the mark says a press would land on "
                + "\(short(landing)), and the walk expects \(short(wanted)): "
                + "\(Self.round1(off)) document points away, further than the "
                + "\(Self.round1(within)) asked for.")
        }
        return "a press would land on \(short(landing)), "
            + "\(Self.round1(off))pt from the \(short(wanted)) claimed"
    }

    /// What the pill riding under a drag says right now.
    ///
    /// It reads `liveDragReadout`, which is the string the canvas actually put
    /// on screen, so a walk that passes here has proved the words a person can
    /// see rather than that some number was computed somewhere.
    private func checkDragReadout(says: String?, absent: Bool) throws -> String {
        let canvas = try requireCanvas()
        let showing = canvas.liveDragReadout
        if absent {
            guard showing == nil else {
                throw Failure(description: "nothing is being dragged, and the canvas is still "
                    + "carrying a reading that says \"\(showing!)\". The pill belongs to a drag "
                    + "in flight: it has outlived the gesture that put it there.")
            }
            return "no reading on the canvas, which is right with nothing in hand"
        }
        guard let says else { return "nothing claimed" }
        guard let showing else {
            throw Failure(description: "nothing on the canvas is saying what this drag is doing, "
                + "and the walk expects \"\(says)\". Check the drag really moved past the click "
                + "tolerance, and that \(FeatureCatalog.dragReadoutFlag) is on.")
        }
        guard showing == says else {
            throw Failure(description: "the reading under the drag says \"\(showing)\", and the "
                + "walk expects \"\(says)\".")
        }
        return "the drag reads \"\(showing)\""
    }

    /// A walk's `showsBox` claim: while the button was still down at the end of
    /// the travel, the canvas was outlining the box the drag was making, and
    /// that box is exactly where the thing landed once the button came up.
    ///
    /// Both halves matter and neither can be settled by a picture. A container
    /// that arranges itself does not move its contents when its box changes, so
    /// a photograph of the canvas mid-drag looks the same whether the outline
    /// is live, frozen, or absent — which is how a stack went on showing
    /// nothing for a whole drag while every other check passed (2026-09-09).
    /// And an outline that tracked the pointer past a limit the stack will not
    /// go past would be a drag promising a shape the release does not give, so
    /// the landing is what it is measured against rather than the pointer.
    private func checkResizeBox(outlined: CGRect?, of layerID: UUID?,
                                expected: Bool) throws -> String {
        let editor = try requireEditor()
        guard expected else {
            guard let outlined else {
                return "nothing was outlined, which is right for a container that shows its own "
                    + "resize"
            }
            throw Failure(description: "the canvas outlined \(Self.short(outlined)) during this "
                + "drag, and this kind of container is meant to show its resize by itself: a "
                + "screen has its own live edge, and a plain group and a copy of a component both "
                + "move their contents under the hand. A second box is one edge claimed twice.")
        }
        guard let outlined, let layerID else {
            throw Failure(description: "nothing was outlined on the canvas at the end of this "
                + "drag, so there was no sign on screen that the box was changing size at all. "
                + "A container that arranges itself leaves its contents where they are, so the "
                + "box is the only thing that could have moved. Check "
                + "\(FeatureCatalog.autoLayoutFlag) is on and that the layer in hand really is a "
                + "stack or a grid (`ContainerResizeBox`).")
        }
        guard let landed = editor.document?.canvasBounds(of: layerID) else {
            throw Failure(description: "the canvas outlined \(Self.short(outlined)) during the "
                + "drag and the layer it belonged to is not in the document any more, so there is "
                + "nothing to settle the claim against.")
        }
        let drift = max(abs(outlined.minX - landed.minX), abs(outlined.minY - landed.minY),
                        abs(outlined.maxX - landed.maxX), abs(outlined.maxY - landed.maxY))
        guard drift <= 0.5 else {
            throw Failure(description: "the box outlined while the button was down was "
                + "\(Self.short(outlined)) and the layer landed at \(Self.short(landed)), "
                + "\(Self.round1(drift))pt apart at the worst edge. The drag showed a shape the "
                + "release did not give.")
        }
        return "the box under the hand, \(Self.short(outlined)), is where it landed"
    }

    /// A rect in the words a failure reads best in: whole numbers, no labels.
    private static func short(_ box: CGRect) -> String {
        "\(Int(box.minX.rounded())), \(Int(box.minY.rounded())) "
            + "\(Int(box.width.rounded())) × \(Int(box.height.rounded()))"
    }

    private func checkHint(contains: String) throws -> String {
        let editor = try requireEditor()
        let reading = Self.hintReading(editor)
        guard reading.contains(contains) else {
            throw Failure(description: reading == "none"
                ? "no chip is up under the canvas, so it cannot be saying \"\(contains)\""
                : "the chip says \"\(reading)\", which does not carry \"\(contains)\"")
        }
        return "the chip says \"\(reading)\", carrying \"\(contains)\" as claimed"
    }

    /// What the canvas says a press at the pointer would take hold of.
    ///
    /// The canvas's own answer, recorded as the cue was read, rather than the
    /// real OS cursor: a walk's pointer is synthesized while the real one is
    /// somewhere else on the screen entirely, so the cursor is corroboration
    /// and this is the claim.
    /// What the bottom-right corner is saying.
    ///
    /// Every toast is its own borderless panel, so nothing that walks a
    /// window's views can see one. This asks the controller that owns them,
    /// which is the same list a person is looking at.
    private func checkToast(says: String?, absent: Bool?) throws -> String {
        let lines = coordinator.playtestToastLines
        let corner = lines.isEmpty
            ? "nothing in the corner"
            : "the corner says " + lines.map { "\"\($0)\"" }.joined(separator: ", ")
        if absent == true, says == nil {
            guard lines.isEmpty else {
                throw Failure(description: "a walk expected no toast at all, and \(corner)")
            }
            return "nothing in the corner, as claimed"
        }
        guard let says else { return corner }
        let found = lines.contains { $0.localizedCaseInsensitiveContains(says) }
        if absent == true {
            guard !found else {
                throw Failure(description: "a walk expected nothing in the corner to say "
                    + "\"\(says)\", and \(corner)")
            }
            return "no toast says \"\(says)\", as claimed; \(corner)"
        }
        guard found else {
            throw Failure(description: "a walk expected a toast saying \"\(says)\", and "
                + "\(corner). The corner is where the app reports work that outlives the window "
                + "that asked for it, so nothing saying this means the app did the work and "
                + "never said so.")
        }
        return "a toast says \"\(says)\", as claimed"
    }

    private func checkCue(says: String) throws -> String {
        let reading = try requireCanvas().playtestPointerCue
        guard reading == says else {
            throw Failure(description: "the canvas says a press here would be \"\(reading)\", "
                + "not \"\(says)\"")
        }
        return "the canvas says a press here would be \"\(reading)\", as claimed"
    }

    /// Who a real click at a point would go to: the picture, or chrome
    /// floating over it.
    ///
    /// A walk's own `click` step hands the press to the canvas view itself, so
    /// it lands whether or not anything covers the spot. That is right for
    /// driving the picture and blind to the thing asked here, so this question
    /// goes to the WINDOW and is hit tested exactly as AppKit does it for a
    /// pointer. What comes back is what a hand would get.
    private func checkClickReaches(_ at: PlaytestPoint,
                                   what: PlaytestClickTaker) throws -> String {
        let canvas = try requireCanvas()
        let window = try requireWindow()
        // The frame view, whose coordinates ARE the window's base coordinates,
        // so a point converted out of the canvas can be handed straight to it.
        guard let root = window.contentView?.superview ?? window.contentView else {
            throw Failure(description: "the window has no content view")
        }
        let inWindow = try windowPoint(at)
        let hit = root.hitTest(inWindow)
        let reaches = hit === canvas || (hit?.isDescendant(of: canvas) ?? false)
        let took = hit.map { String(describing: type(of: $0)) } ?? "nothing at all"
        let where_ = "at \(short(at.point)) \(at.space.rawValue)"
        switch what {
        case .canvas:
            guard reaches else {
                throw Failure(description: "a click \(where_) never reaches the picture: "
                    + "\(took) takes it. Chrome over the canvas has to let a click through "
                    + "everywhere but on its own controls")
            }
            return "a click \(where_) reaches the picture"
        case .chrome:
            guard !reaches else {
                throw Failure(description: "a click \(where_) goes straight to the picture; "
                    + "nothing over the canvas takes it")
            }
            return "a click \(where_) is taken by \(took), over the picture"
        }
    }

    /// What the notice pill under the canvas is saying right now.
    private func checkNotice(says: String?, absent: Bool?, held: Bool?) throws -> String {
        let editor = try requireEditor()
        let pill = editor.copyConfirmation
        let reading = pill.map { "\($0.title) · \($0.detail)" }
        if absent == true {
            guard let reading else { return "no pill under the canvas, as claimed" }
            throw Failure(description: "a pill is up under the canvas saying \"\(reading)\"")
        }
        // Whether a pointer resting on the pill's button is stopping its clock.
        // Only a pill that HAS a button can be held, so a claim of held on an
        // inert one says which of the two is wrong.
        var about = ""
        if let held {
            guard let reading else {
                throw Failure(description: "no pill is up under the canvas, so nothing can be "
                    + "\(held ? "held open" : "let go") by a pointer")
            }
            guard editor.canvasNoticeHeld == held else {
                let has = pill?.action != nil
                throw Failure(description: "the pill \"\(reading)\" is "
                    + "\(editor.canvasNoticeHeld ? "held open by the pointer" : "not held")"
                    + ", and this step claims it is \(held ? "held" : "not held")."
                    + (has ? " Its button is \"\(pill?.action?.label ?? "")\"; rest the pointer on "
                         + "that control with a \"move\" step to hold it."
                       : " This pill carries no button, and only a pill with one can be held."))
            }
            about = editor.canvasNoticeHeld
                ? ", held open by the pointer as claimed"
                : ", not held by the pointer as claimed"
        }
        guard let says else {
            return (reading.map { "the pill says \"\($0)\"" } ?? "no pill") + about
        }
        guard let reading else {
            throw Failure(description: "no pill is up under the canvas, so it cannot be saying "
                + "\"\(says)\"")
        }
        guard reading.contains(says) else {
            throw Failure(description: "the pill says \"\(reading)\", which does not carry "
                + "\"\(says)\"")
        }
        return "the pill says \"\(reading)\", carrying \"\(says)\" as claimed" + about
    }

    private func checkLayers(atLeast: Int?, atMost: Int?) throws -> String {
        let editor = try requireEditor()
        let layers = editor.document?.allLayers ?? []
        let count = layers.count
        func plural(_ n: Int) -> String { n == 1 ? "layer" : "layers" }
        func refuse(_ claim: String) -> Failure {
            Failure(description: "\(count) \(plural(count)) in the document, \(claim)"
                + (layers.isEmpty ? ""
                   : "; the first few: " + layers.prefix(6).map(\.name).joined(separator: ", ")))
        }
        if let atLeast, count < atLeast { throw refuse("not at least \(atLeast)") }
        if let atMost, count > atMost { throw refuse("more than the \(atMost) claimed") }
        if let atLeast, let atMost, atLeast == atMost {
            return "\(count) \(plural(count)) in the document, as claimed"
        }
        let range = [atLeast.map { "at least \($0)" }, atMost.map { "at most \($0)" }]
            .compactMap { $0 }.joined(separator: " and ")
        return "\(count) \(plural(count)) in the document, \(range), as claimed"
    }

    /// Where the marquee is, spelled exactly as `describe` spells it, so a
    /// walk can claim the outline it drew is still up.
    ///
    /// Nothing else can: the ants are four dashed lines in a picture, and the
    /// log line nobody reads back is how an outline thrown away by a tool key
    /// went unnoticed for a week (2026-09-08).
    private func checkRegion(reads: String?, present: Bool?) throws -> String {
        let editor = try requireEditor()
        let found = editor.selection.map { region -> String in
            let box = region.path.boundingBoxOfPath
            return "\(Int(box.minX)),\(Int(box.minY)) \(Int(box.width))x\(Int(box.height))"
        }
        if let present {
            if present, found == nil {
                throw Failure(description: "there is no marquee on the canvas, and the walk claims there is one")
            }
            if !present, let found {
                throw Failure(description: "the marquee is still up at \(found), and the walk claims there is none")
            }
        }
        if let reads {
            guard let found else {
                throw Failure(description: "there is no marquee on the canvas, and the walk claims one reading \(reads)")
            }
            guard found == reads else {
                throw Failure(description: "the marquee reads \(found), not the \(reads) claimed")
            }
        }
        return found.map { "the marquee reads \($0), as claimed" } ?? "no marquee, as claimed"
    }

    /// What the path the Pen drew is made of, asked of the document rather than
    /// read off a picture (`PlaytestStep.expectPath`).
    private func checkPath(_ layerName: String?, anchors: Int?, closed: Bool?,
                           curves: Int?, smooth: Int?, halfSmooth: Int?, rings: Int?,
                           width: CGFloat?, fill: String?, ink: String?, picked: Int?,
                           anchorAt: PlaytestAnchorClaim?) throws -> String {
        let editor = try requireEditor()
        let layers = editor.document?.allLayers ?? []
        let paths = layers.filter { $0.path != nil }
        let layer: Layer
        if let layerName {
            guard let named = paths.last(where: { $0.name == layerName }) else {
                throw Failure(description: "no path layer called \"\(layerName)\"; "
                    + (paths.isEmpty ? "there are no paths in the document at all"
                       : "the paths are: " + paths.map(\.name).joined(separator: ", ")))
            }
            layer = named
        } else {
            guard let last = paths.last else {
                throw Failure(description: "no path in the document; the layers are: "
                    + (layers.isEmpty ? "none" : layers.map(\.name).joined(separator: ", ")))
            }
            layer = last
        }
        guard let content = layer.path else {
            throw Failure(description: "\(layer.name) is not a path")
        }
        let curved = content.segments.filter { !$0.isStraight }.count
        let shape = "\(layer.name): \(content.anchors.count) "
            + (content.anchors.count == 1 ? "anchor" : "anchors")
            + ", \(content.isClosed ? "closed" : "open"), \(curved) curved "
            + (curved == 1 ? "run" : "runs")
            + ", \(DocumentUnit.text(content.strokeWidth)) thick"
        if let anchors, content.anchors.count != anchors {
            throw Failure(description: "\(shape) — not the \(anchors) claimed")
        }
        if let closed, content.isClosed != closed {
            throw Failure(description: "\(shape) — the walk claimed it would be "
                + (closed ? "closed" : "open"))
        }
        if let curves, curved != curves {
            throw Failure(description: "\(shape) — not the \(curves) curved claimed")
        }
        if let rings, content.ringCount != rings {
            let loops = content.ringCount == 1 ? "one loop" : "\(content.ringCount) loops"
            throw Failure(description: "\(shape), made of \(loops) — not the \(rings) claimed. "
                + "A shape with a hole in it is TWO loops; one means the hole is not there.")
        }
        if let width, content.strokeWidth != width {
            throw Failure(description: "\(shape) — not the \(DocumentUnit.text(width)) claimed")
        }
        // The two colours it came out wearing. Asked of the document because a
        // picture cannot settle them: the offscreen render resolves colour
        // differently from the screen, and "blue-ish" is not the claim — the
        // claim is that it is the blue the tool bar was armed with.
        let wearing = "\(shape), inside "
            + (content.fill.map { $0.hex } ?? "none") + ", outline \(content.paint.hex)"
        if let ink, !Self.sameColour(content.paint.hex, ink) {
            throw Failure(description: "\(wearing) — the walk claimed its outline would be \(ink)")
        }
        if let fill {
            let has = content.fill.map { $0.hex }
            let matches = fill.caseInsensitiveCompare("none") == .orderedSame
                ? has == nil
                : has.map { Self.sameColour($0, fill) } ?? false
            guard matches else {
                throw Failure(description: "\(wearing) — the walk claimed its inside would be \(fill)")
            }
        }
        let bends = content.anchors.filter { $0.kind == .smooth }.count
        if let smooth, bends != smooth {
            throw Failure(description: "\(shape), \(bends) of them smooth — not the "
                + "\(smooth) claimed")
        }
        // Points curved on ONE side only: a line arrives and a curve leaves, or
        // the other way round. Counted off the handles rather than off `kind`,
        // because such a point IS a corner by kind — the two sides are not tied
        // together — and counting kinds would make it invisible.
        let halves = content.anchors.filter(\.isHalfSmooth).count
        if let halfSmooth, halves != halfSmooth {
            throw Failure(description: "\(shape), \(halves) of them curved on one side only "
                + "— not the \(halfSmooth) claimed")
        }
        // How many of its points are picked right now. Canvas state rather
        // than document state — what is picked is a fact about this window,
        // like a marquee — so it is asked of the canvas, and it is the only
        // way a walk can claim a box swept over the points took them.
        if let picked {
            let canvas = try requireCanvas()
            let holding = canvas.pathAnchorSelection.count
            guard holding == picked else {
                throw Failure(description: "\(shape), \(holding) of them picked — not the "
                    + "\(picked) claimed")
            }
        }
        // Where one named point ended up, asked in the space the walk wrote it
        // in. A path's anchors are stored against its own corner, so the claim
        // is checked on the DOCUMENT point the person would have clicked.
        if let anchorAt {
            guard content.anchors.indices.contains(anchorAt.index) else {
                throw Failure(description: "\(shape) — there is no point \(anchorAt.index) "
                    + "to be anywhere")
            }
            let local = content.anchors[anchorAt.index].point
            let here = CGPoint(x: layer.frame.minX + local.x, y: layer.frame.minY + local.y)
            let wanted = try documentPoint(anchorAt.near)
            let off = hypot(here.x - wanted.x, here.y - wanted.y)
            guard off <= anchorAt.within else {
                throw Failure(description: "\(shape) — point \(anchorAt.index) is at "
                    + "\(short(here)), which is \(String(format: "%.1f", off)) from the "
                    + "\(short(wanted)) claimed")
            }
        }
        return (fill == nil && ink == nil ? shape : wearing) + ", as claimed"
    }

    /// Whether two colours written down are the same colour, whatever case the
    /// hex was typed in.
    private static func sameColour(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }

    /// What an open caption field is doing, checked rather than photographed.
    ///
    /// The caret blinks and the outline is a dashed line beside a bubble, so a
    /// walk that only takes pictures of them proves nothing: on 2026-09-12 the
    /// caret dropped to the bubble's left edge on Return and the outline kept
    /// the shape it had when the field opened, and the two-line caption walk
    /// had been photographing both for a week.
    /// Where the inline typing field sits and how far it leans, against what the
    /// walk claims. Both in document points and degrees clockwise, the units a
    /// walk's clicks are already written in.
    private func checkField(onScreen: PlaytestPoint?, degrees: CGFloat?,
                            within: CGFloat) throws -> String {
        guard let canvas, let field = canvas.playtestTypingFieldGeometry else {
            throw Failure(description: "no typing field is open, so there is nothing to claim "
                + "about one")
        }
        var held: [String] = []
        if let onScreen {
            let want = onScreen.point
            let off = hypot(field.corner.x - want.x, field.corner.y - want.y)
            guard off <= within else {
                throw Failure(description: "the typing field's top left corner is at "
                    + "(\(Self.round1(field.corner.x)), \(Self.round1(field.corner.y))) and the step "
                    + "claimed (\(Self.round1(want.x)), \(Self.round1(want.y))): "
                    + "\(Self.round1(off)) points out, and the walk allowed \(Self.round1(within))")
            }
            held.append("corner (\(Self.round1(field.corner.x)), \(Self.round1(field.corner.y)))")
        }
        if let degrees {
            guard abs(field.degrees - degrees) <= within else {
                throw Failure(description: "the typing field leans \(Self.round1(field.degrees)) "
                    + "degrees and the step claimed \(Self.round1(degrees)): "
                    + "\(Self.round1(abs(field.degrees - degrees))) out, and the walk allowed "
                    + "\(Self.round1(within))")
            }
            held.append("leaning \(Self.round1(field.degrees)) degrees")
        }
        return held.joined(separator: ", ") + "; " + canvas.playtestTypingFieldReport
    }

    private func checkCaption(aligned: CaptionDraftAlignment?, caret: CaptionCaretSpot?,
                              caretHeight: CaptionCaretHeight?,
                              outline: CaptionOutlineClaim?) throws -> String {
        let editor = try requireEditor()
        guard let canvas, let field = canvas.playtestCaptionGeometry else {
            throw Failure(description: "no arrow caption field is open, so there is nothing to claim about one")
        }
        var held: [String] = []
        if let aligned {
            let is_ = field.centred ? CaptionDraftAlignment.centred : .left
            guard is_ == aligned else {
                throw Failure(description: "the draft is laid out \(is_.rawValue), not \(aligned.rawValue)"
                    + "; the field holds \"\(field.draft.replacingOccurrences(of: "\n", with: "\\n"))\"")
            }
            held.append("laid out \(aligned.rawValue)")
        }
        if let caret {
            guard let box = field.caret else {
                throw Failure(description: "the field will not say where its caret is")
            }
            let across = box.minX - field.bubble.minX
            let middle = field.bubble.width / 2
            // Half a character of slack: a centred line straddles the middle,
            // so the caret waiting for its first letter sits within a glyph's
            // half width of it rather than exactly on it.
            let slack: CGFloat = 6
            switch caret {
            case .centred:
                guard abs(across - middle) <= slack else {
                    throw Failure(description: "the caret sits \(Self.round1(across)) points in from the "
                        + "bubble's left edge, and the middle of a \(Self.round1(field.bubble.width)) point "
                        + "bubble is \(Self.round1(middle)): that is where the next character lands")
                }
            case .left:
                guard across < middle - slack else {
                    throw Failure(description: "the caret sits \(Self.round1(across)) points in from the "
                        + "bubble's left edge, which is not the left of a \(Self.round1(field.bubble.width)) point bubble")
                }
            }
            held.append("caret \(caret.rawValue) at \(Self.round1(across)) in of \(Self.round1(field.bubble.width))")
        }
        if let caretHeight {
            guard let box = field.caret else {
                throw Failure(description: "the field will not say where its caret is")
            }
            // A point of slack: the caret is laid out in view points and read
            // back in document ones, so a zoom that is not a whole number
            // leaves a fraction behind.
            let whole = box.height >= field.lineHeight - 1
            switch caretHeight {
            case .full:
                guard whole else {
                    throw Failure(description: "the caret is drawn \(Self.round1(box.height)) points tall "
                        + "where a line of this caption is \(Self.round1(field.lineHeight)): it is being cut "
                        + "off, most likely by a field that is not as tall as the line the caret waits on")
                }
                held.append("caret a full \(Self.round1(box.height)) point line tall")
            case .short:
                guard !whole else {
                    throw Failure(description: "the caret is drawn \(Self.round1(box.height)) points tall, "
                        + "a whole \(Self.round1(field.lineHeight)) point line, and the step claimed it would be short")
                }
                held.append("caret short at \(Self.round1(box.height)) of \(Self.round1(field.lineHeight))")
            }
        }
        if let outline {
            let drawn = canvas.playtestSelectionOutlineBox
            switch outline {
            case .none:
                guard drawn == nil else {
                    throw Failure(description: "an outline is drawn round \(drawn!.integral), and the step claimed there would be none")
                }
                held.append("no outline, as claimed")
            case .hugsTheBubble:
                guard let drawn else {
                    throw Failure(description: "no outline is drawn at all: \(canvas.playtestOutlineAbsence)")
                }
                guard let layer = editor.document?.canvasLayer(id: field.layerID) else {
                    throw Failure(description: "the arrow being captioned is not on the canvas")
                }
                let wanted = layer.drawnBounds(liveCaptionPill: field.bubble)
                let off = max(abs(drawn.minX - wanted.minX), abs(drawn.minY - wanted.minY),
                              abs(drawn.maxX - wanted.maxX), abs(drawn.maxY - wanted.maxY))
                guard off <= 1 else {
                    throw Failure(description: "the outline is drawn round \(drawn.integral) while the bubble "
                        + "being typed in is \(field.bubble.integral): together with the arrow's own ink that "
                        + "should make \(wanted.integral), and the worst edge is \(Self.round1(off)) points out")
                }
                held.append("outline \(drawn.integral) round bubble \(field.bubble.integral)")
            }
        }
        return held.joined(separator: ", ")
    }

    private static func round1(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
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
        guard let match = all.first(where: { PlaytestSteadyName.matches(name, steady: $0.steady) })
                ?? all.first(where: { $0.name == name })
                ?? all.first(where: { $0.detail == name })
                ?? all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            let seen = all.flatMap(\.everyName).joined(separator: ", ")
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
            let wanted = reads.trimmingCharacters(in: .whitespaces)
            let showing = reading.reads.trimmingCharacters(in: .whitespaces)
            // A control reads as the rows it sits in and then what it is
            // saying: "Border, off". A walk that has already said which row in
            // "in" may claim the second half alone -- `reads: "off"` -- and
            // that is the form to write, because the first half is the words on
            // the row and the words on a row change. Three walks failed a
            // rename on nothing but this, having found the row perfectly well
            // by its steady name (`PlaytestSteadyName`).
            //
            // Only WITH an "in", though. Without one there is nothing pinning
            // which switch is being read, and "off" alone would happily answer
            // for whichever the panel built first.
            let own = reading.says.trimmingCharacters(in: .whitespaces)
            let asClaimed = showing.caseInsensitiveCompare(wanted) == .orderedSame
                || (inRow != nil && !own.isEmpty && own.caseInsensitiveCompare(wanted) == .orderedSame)
            guard asClaimed else {
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
                 // What to write in "in" for a step that should survive the
                 // words on the row changing (`PlaytestSteadyName`). An author
                 // writes what they can see, so the durable name has to be
                 // visible too, spelled the way it gets pasted into a step.
                 "steadyRows": control.steadyRows,
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
                var detail = entry["detail"] as? String ?? ""
                let steady = (entry["steadyRows"] as? [String] ?? []).joined(separator: " ")
                if !steady.isEmpty { detail += detail.isEmpty ? steady : ", \(steady)" }
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
        // Both go before the picture is taken, so that afterwards the file
        // being THERE is proof this run wrote it. The folder is overwritten
        // rather than emptied between runs, and a menu shot that failed used
        // to leave yesterday's picture under today's name for an audit to
        // copy, while the step reported the file name either way.
        try? FileManager.default.removeItem(at: shotURL)
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
        // The picture is the deliverable, so whether there IS one is answered
        // by the file rather than by the step's good intentions.
        if FileManager.default.fileExists(atPath: shotURL.path) {
            captures.photographed(shotName)
            shot = shotURL.lastPathComponent
        } else {
            captureFailed(shotName, outcome)
        }
        // A picture nobody checks proves nothing, so the rows the step named
        // are held to what they wore.
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
    /// The row a walk asked to pick, wherever it is in the menu.
    ///
    /// A row menu is not a flat list: commands that are one idea with several
    /// answers live in a submenu (Combine Shapes, and Arrange), and a walk that
    /// could only reach the top level could never press one of them. The name
    /// is looked for at the top first, then one step into each submenu, and
    /// "Combine Shapes > Cut Out" names the row through its parent for the day
    /// two submenus carry the same word.
    private static func find(_ title: String, in menu: NSMenu) -> (menu: NSMenu, index: Int)? {
        let parts = title.components(separatedBy: " > ").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if parts.count > 1 {
            guard let parent = menu.items.first(where: { $0.title == parts[0] })?.submenu else {
                return nil
            }
            parent.update()
            return find(parts.dropFirst().joined(separator: " > "), in: parent)
        }
        if let index = menu.items.firstIndex(where: { $0.title == title }) {
            return (menu, index)
        }
        for item in menu.items {
            guard let submenu = item.submenu else { continue }
            // A submenu SwiftUI has never opened can still be empty: its rows
            // are built when it is first asked for. Asking is what `update()`
            // is, and without it a walk would report a row that exists as
            // missing.
            submenu.update()
            guard let index = submenu.items.firstIndex(where: { $0.title == title }) else { continue }
            return (submenu, index)
        }
        return nil
    }

    /// One step, two things to right click: a row in the panel named by `name`,
    /// or a spot on the picture given by `at`. Everything after the point is
    /// worked out is identical, because a menu is a menu wherever it hangs
    /// from.
    private func openRowMenu(_ name: String?, at: PlaytestPoint?, shot: String?, choose: String?,
                             ticked: [String], unticked: [String], number: Int) async throws {
        let aimed: (name: String, detail: String, point: CGPoint, window: NSWindow)
        if let name {
            let target = try rightClickTarget(name)
            guard let window = target.window else {
                throw Failure(description: "\"\(target.name)\" is in no window, so there is nothing to right click")
            }
            guard Self.isInReach(target) else {
                throw Failure(description: "\"\(target.name)\" is not where a person could right click it: it is "
                    + "off the window, or the dock has scrolled it far enough that the panel's edge cuts across "
                    + "it. Scroll to it with a \"scrollPanel\" step first.")
            }
            aimed = (target.name, target.detail, target.point, window)
        } else if let at {
            aimed = ("the picture at \(short(at.point))", "", try windowPoint(at), try requireWindow())
        } else {
            throw Failure(description: "a rightClick step needs a row to click (\"on\") or a spot on the "
                + "picture (\"at\")")
        }
        let (window, target) = (aimed.window, aimed)
        guard let content = window.contentView else {
            throw Failure(description: "the window has no content view, so there is nothing to right click")
        }
        guard let (menu, view) = PlaytestPanelMenu.menu(rightClickingAt: target.point, in: content,
                                                        window: window) else {
            throw Failure(description: "right clicking \"\(target.name)\" raises no menu: nothing under that "
                + "point offers one. Is there a `.contextMenu` on it?")
        }
        let shotURL = shot.map { out.appendingPathComponent("\($0)-sc.png") }
        let noteURL = out.appendingPathComponent("row-menu-shot.txt")
        // The old picture goes FIRST, so afterwards the file being there is
        // proof this run wrote it (see `menuShot`).
        if let shotURL { try? FileManager.default.removeItem(at: shotURL) }
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
            } else if shotURL != nil {
                reading.problem = "it showed in no window this app can see, so there is no picture"
            }
            // Picking happens LAST, after the reading and the picture: choosing
            // a row can rebuild the very list being read.
            if let choose {
                if let found = Self.find(choose, in: menu) {
                    if found.menu.items[found.index].isEnabled {
                        found.menu.performActionForItem(at: found.index)
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
        if let shotURL, let askedFor = shot {
            if FileManager.default.fileExists(atPath: shotURL.path) {
                captures.photographed(askedFor)
                reading.shot = shotURL.lastPathComponent
            } else {
                captureFailed(askedFor, outcome)
            }
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

    /// The menu button a `panelMenu` step names, found the way a press finds a
    /// control. Pulled out on its own so the step can keep asking for it while
    /// the dock is still laying itself out (`patiently`).
    private func panelMenuButton(_ name: String, in row: String?,
                                 of content: NSView) throws -> NSPopUpButton {
        let fields = Self.findAll(PanelTargetView.self, in: content)
            .filter { $0.kind == .field && $0.window != nil && !$0.isHiddenOrHasHiddenAncestor }
        var buttons = PlaytestPanelMenu.buttons(in: content)
        // Narrowed to one row FIRST, the way a press is, so "the Color menu in
        // Border 2" is one thing to say rather than a search through every menu
        // in the panel that happens to be called Color.
        if let row {
            let inside = buttons.filter { button in
                let names = PlaytestSteadyName.isSteady(row)
                    ? PlaytestPanelPress.steadyFields(of: button, among: fields)
                    : PlaytestPanelPress.fields(of: button, among: fields)
                return names.contains { $0.caseInsensitiveCompare(row) == .orderedSame }
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
        let byRow = PlaytestSteadyName.isSteady(name)
            ? buttons.filter { button in
                PlaytestPanelPress.steadyField(of: button, among: fields)
                    .contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            }
            : buttons.filter { PlaytestPanelMenu.naming(of: $0, among: fields).name == name }
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
        return button
    }

    private func openPanelMenu(_ name: String, in row: String?, shot: String?, choose: String?,
                               clicking: String?, number: Int) async throws {
        let host = try requireWindow()
        guard let content = host.contentView else {
            throw Failure(description: "the window has no content view")
        }
        // Kept looking for rather than read once. The plus that opens Add
        // Effect is built with no name at all for the first frames of a
        // relayout, so a walk that looked at the wrong instant was told there
        // was no such menu in a window the menu was plainly in
        // (panel-edge-column-walk, 2026-09-13).
        let button = try await patiently { try self.panelMenuButton(name, in: row, of: content) }
        guard button.isEnabled else {
            throw Failure(description: "the \"\(name)\" menu is dimmed, so it has nothing to open")
        }
        let shotURL = shot.map { out.appendingPathComponent("\($0)-sc.png") }
        let noteURL = out.appendingPathComponent("panel-menu-shot.txt")
        // The old picture goes FIRST, so afterwards the file being there is
        // proof this run wrote it (see `menuShot`).
        if let shotURL { try? FileManager.default.removeItem(at: shotURL) }
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
            } else if shotURL != nil {
                reading.problem = "the menu opened but showed in no window this app can see, so there is no picture"
            }
            if let choose {
                // A steady name works here too, so "add a border" is one
                // vocabulary from the plus menu through to the row it makes:
                // `choose: "@border"` then `in: "@border"`, and neither one is
                // the word on screen (`PlaytestSteadyName`). SwiftUI leaves
                // nothing on a menu row to hang an id off, so the name is
                // resolved through the model that built the menu and then
                // matched by title like any other.
                let wanted = PlaytestSteadyName.isSteady(choose)
                    ? (AddableEffect.steadyNamed(choose)?.title ?? choose)
                    : choose
                // A row that carries a VALUE as well as a name — "Rotation
                // 0°" on the Motion plus, where the number is the thing you
                // would be animating away from — cannot be named by the words
                // on it, because the words change the moment anything moves.
                // So a name that matches no row exactly is tried as the start
                // of one, and only accepted when exactly one row begins with
                // it: an ambiguous name is still an error rather than a guess.
                var landed = menu?.items.firstIndex {
                    PlaytestPanelMenu.readable($0.title) == wanted
                }
                if landed == nil, let items = menu?.items {
                    let beginning = items.indices.filter {
                        PlaytestPanelMenu.readable(items[$0].title).hasPrefix(wanted)
                    }
                    if beginning.count == 1 { landed = beginning[0] }
                }
                if let index = landed {
                    if menu?.items[index].isEnabled == true {
                        menu?.performActionForItem(at: index)
                        reading.chose = wanted
                    } else {
                        reading.problem = "the row \"\(wanted)\" is dimmed, so picking it would do nothing"
                    }
                } else {
                    reading.problem = "no row called \"\(wanted)\"; the rows are: "
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
        if let shotURL, let askedFor = shot {
            if FileManager.default.fileExists(atPath: shotURL.path) {
                captures.photographed(askedFor)
                reading.shot = shotURL.lastPathComponent
            } else {
                captureFailed(askedFor, outcome)
            }
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

    /// A tile on the Library shelf, found the way a person finds one: if it is
    /// not showing, scroll the shelf and look again.
    ///
    /// The shelf draws its tiles in a lazy grid, so a tile below its own fold
    /// is not merely out of view — nothing is built for it, so nothing answers
    /// to its name and the step reads exactly like the component being gone.
    /// That is not a corner case: drop one starter and the sections the
    /// selection opens push the Library off the bottom of the dock, which
    /// squeezes the shelf to a single row of three, and the two starters on the
    /// row under it stop existing. words-down-the-box-walk failed on "Nav Bar"
    /// that way on 2026-09-17, and the audit that hit it concluded the app had
    /// lost its Nav Bar component.
    ///
    /// So the shelf is wound back to the top and walked down a row at a time,
    /// looking again after each turn, until the tile builds or the shelf runs
    /// out of length. Same reasoning as `pressControl` scrolling the dock for
    /// itself: a walk that has to be TOLD to scroll is a walk that goes stale
    /// the next time the dock grows a section.
    private func tileTarget(_ name: String) async throws -> PanelTargetView {
        if let showing = try? panelTarget(name, kind: .tile) { return showing }
        // Any tile at all gives us the shelf: the marker is a real view inside
        // the scroll view SwiftUI built for the grid, so its nearest scrolling
        // ancestor IS the shelf. With no tile built there is no shelf to scroll
        // and the original failure is the true one.
        guard let anyTile = try panelTargets().first(where: { $0.kind == .tile }),
              let clip = anyTile.enclosingScrollView?.contentView else {
            return try panelTarget(name, kind: .tile)
        }
        var turns = 0
        // To the top first, so a tile ABOVE where the shelf happens to be
        // sitting is not walked away from.
        while turns < Self.shelfTurnLimit,
              Self.scrollClip(clip, by: Self.shelfRowStep * 4) > 0.5 {
            turns += 1
            await sleep(0.05)
        }
        if let found = try? panelTarget(name, kind: .tile) {
            note(0, "shelf", "wound the shelf back to the top to reach the tile \"\(name)\"")
            return found
        }
        var scrolled = 0.0
        while turns < Self.shelfTurnLimit {
            let moved = Self.scrollClip(clip, by: -Self.shelfRowStep)
            guard moved > 0.5 else { break }
            scrolled += moved
            turns += 1
            await sleep(0.06)
            if let found = try? panelTarget(name, kind: .tile) {
                note(0, "shelf",
                     "scrolled the Library shelf \(Int(scrolled))pt to bring the tile "
                        + "\"\(name)\" into it, the way a person would")
                return found
            }
        }
        // Still nothing, with the shelf at the end of its own length: the tile
        // really is not on this shelf, and `panelTarget` writes the list.
        return try panelTarget(name, kind: .tile)
    }

    /// One row of tiles plus the gap under it: how far one turn of the shelf's
    /// wheel goes.
    private static let shelfRowStep =
        LibraryShelfLayout.tileHeight + LibraryShelfLayout.tileSpacing

    /// The most turns a tile hunt may take. `LibraryPanel.maxTiles` is 60, and
    /// the narrowest shelf draws one to a row, so this covers the longest shelf
    /// the app will build and then stops rather than spinning.
    private static let shelfTurnLimit = 70

    /// Picks a tile up off the Library shelf and lets it go on the picture,
    /// through the canvas's own drag destination — the same calls a drag from
    /// the Finder makes, pasteboard and all.
    private func dragTile(_ name: String, to at: PlaytestPoint, hold: String?,
                          expect: PlaytestColorDropExpectation, says: String?,
                          number: Int) async throws {
        let canvas = try requireCanvas()
        let window = try requireWindow()
        let target = try await tileTarget(name)
        guard let payload = target.payload else {
            throw Failure(description: "the tile \"\(name)\" cannot be picked up")
        }
        let board = try await PlaytestPanelDrag.pasteboard(from: payload(), named: "tile")
        let viewPoint = try self.viewPoint(at)
        let windowPoint = canvas.convert(viewPoint, to: nil)
        // The gate AppKit puts in front of every drag, put back: a view is only
        // told about the types it registered for, and calling the destination
        // by hand walks straight past it. Without this a drop the picture
        // answers beautifully, behind a registration list that never names its
        // type, passes every walk and does nothing at all under a real pointer.
        // That is exactly what a saved text style did until 2026-09-16.
        //
        // A type the picture never registered for is a REFUSAL, not an error:
        // the pointer shows the no-entry sign, which is what a walk expecting
        // one should see. It is only a failure when the walk expected the
        // picture to take it, or to say something about it, because a picture
        // that was never told has nothing to say.
        if !PlaytestPanelDrag.canReceive(canvas, carrying: board) {
            let carried = (board.types ?? []).map(\.rawValue).joined(separator: ", ")
            let asked = canvas.registeredDraggedTypes.map(\.rawValue).joined(separator: ", ")
            let why = "the picture never hears about the tile \"\(name)\": it carries \(carried), "
                + "and the canvas only registered for \(asked), so under a real pointer AppKit "
                + "would not deliver this drag to the canvas at all"
            if expect == .takes {
                throw Failure(description: why)
            }
            if let says {
                throw Failure(description: "\(why), and the walk expected it to say \"\(says)\"")
            }
            note(number, "dragTile",
                 "\"\(name)\" held over \(short(at.point)) \(at.space.rawValue): \(why)",
                 state: describe())
            return
        }
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

    /// Presses a tile on the Library shelf and pulls it towards the picture,
    /// and says whether a drag came of it.
    ///
    /// This is the half of a tile drag `dragTile` cannot reach. `dragTile`
    /// starts with the payload already in the air and proves everything from
    /// there; nothing in it proves the tile ever left the shelf. So this posts
    /// a press and a pull at the tile itself and watches for AppKit being asked
    /// to start a drag, which is what a tile with a handle does and what a tile
    /// without one does not.
    ///
    /// The session asked for is then refused rather than started, because a
    /// real one runs a loop of its own that only a mouse coming up on a real
    /// desk can end. So what this proves is the pick up, not the picture that
    /// would follow the pointer afterwards: see `PlaytestTilePickUp.swift`.
    private func pickUpTile(_ name: String, to at: PlaytestPoint, number: Int) async throws {
        let canvas = try requireCanvas()
        let target = try await tileTarget(name)
        guard let window = target.window, let content = window.contentView else {
            throw Failure(description: "the tile \"\(name)\" is in no window, so nothing could press it")
        }
        let box = target.convert(target.bounds, to: nil)
        let inWindow = content.convert(content.bounds, to: nil)
        // The same reach a press has to have: the whole tile inside the window
        // AND inside whatever the shelf's own scrolling has left showing of it.
        // A tile with a sliver out is a tile a person scrolls to first.
        let showing = target.convert(target.visibleRect, to: nil)
        guard inWindow.contains(box), showing.contains(box) else {
            throw Failure(description: "the tile \"\(name)\" is not all the way where a person "
                + "could pull on it: it is at \(short(box.origin)) "
                + "\(short(CGPoint(x: box.width, y: box.height))) and the window is "
                + "\(short(CGPoint(x: inWindow.width, y: inWindow.height))). "
                + "A `reveal` step scrolls the shelf until it is.")
        }
        let alreadyPickedSomethingUp = PlaytestDragWatch.hasCaughtAnything
        let from = CGPoint(x: box.midX, y: box.midY)
        let to = canvas.convert(try viewPoint(at), to: nil)

        PlaytestDragWatch.start()
        defer { _ = PlaytestDragWatch.stop() }
        var stamp = ProcessInfo.processInfo.systemUptime
        func post(_ type: NSEvent.EventType, at point: CGPoint, pressure: Float) {
            stamp += 0.016
            guard let event = NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: stamp,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                    clickCount: 1, pressure: pressure) else { return }
            NSApp.postEvent(event, atStart: false)
        }
        // The pointer arrives first. A tile fired at out of nowhere came away
        // two times in three: the shelf has to have the pointer over it before
        // the press, the way it does under a hand, or SwiftUI has nothing to
        // begin a gesture from.
        post(.mouseMoved, at: from, pressure: 0)
        await sleep(0.15)
        post(.leftMouseDown, at: from, pressure: 1)
        await sleep(0.15)
        // Then the pull, in the steps a hand makes and spread over real time
        // rather than fired in a burst, far enough past the couple of points
        // AppKit calls a twitch that no threshold can swallow it.
        let pullSteps = 8
        for step in 1...pullSteps {
            let t = Double(step) / Double(pullSteps)
            post(.leftMouseDragged,
                 at: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t),
                 pressure: 1)
            await sleep(0.04)
        }
        post(.leftMouseUp, at: to, pressure: 0)
        await sleep(0.4)
        let asks = PlaytestDragWatch.stop()

        guard let ask = asks.first else {
            // Which of the two this is matters more than anything else the step
            // says, so it is the first thing said.
            guard !alreadyPickedSomethingUp else {
                throw Failure(description: "a walk gets ONE pick up per run of the app, and this "
                    + "one has had its: after a tile has come away SwiftUI starts no further drag, "
                    + "so nothing can be read into \"\(name)\" staying on the shelf. Put this step "
                    + "in a walk of its own. See Sources/Photonz/Playtest/PlaytestTilePickUp.swift.")
            }
            throw Failure(description: "the tile \"\(name)\" did not come away: it was pressed at "
                + "\(short(from)) and pulled to \(short(to)) in the window, and nothing asked to "
                + "start a drag. A tile that cannot be picked up is a tile nothing can be done with.")
        }
        guard !ask.types.isEmpty else {
            throw Failure(description: "the tile \"\(name)\" came away carrying nothing, so there "
                + "would be nothing to let go of")
        }
        note(number, "pickUpTile",
             "\"\(name)\" pressed at \(short(from)) and pulled to \(short(to)) = \(short(at.point)) "
                + "\(at.space.rawValue): it came away carrying \(ask.items) "
                + "thing\(ask.items == 1 ? "" : "s") (\(ask.types.joined(separator: ", ")))",
             state: ["view": ask.view, "items": ask.items, "types": ask.types])
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
        let source = try await tileTarget(name)
        let destination = try panelTarget(ontoRow, kind: .row)
        guard let payload = source.payload else {
            throw Failure(description: "the tile \"\(name)\" cannot be picked up")
        }
        let board = try await PlaytestPanelDrag.pasteboard(from: payload(), named: "style")
        // Both, because a row takes both kinds of tile and each reads its own
        // payload off the DRAG pasteboard, which a walk cannot start. Standing
        // in for both is safe: each reader looks for its own type on the board
        // and a board carrying a colour is nothing to the text style reader.
        TextStyleDrag.playtestPasteboard = board
        ColorDrag.playtestPasteboard = board
        defer {
            TextStyleDrag.playtestPasteboard = nil
            ColorDrag.playtestPasteboard = nil
        }
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
        let sentence = editor?.layerRowStyleDrop?.note
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
        let source = try await pickUpSource(carry)
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
    private func pickUpSource(_ name: String) async throws -> PanelTargetView {
        if let row = try? panelTarget(name, kind: .row) { return row }
        if let tile = try? panelTarget(name, kind: .tile) { return tile }
        do {
            return try colorDragSource(name)
        } catch {
            // Nothing showing answers to the name, so the last place to look is
            // under the shelf's own fold. Last on purpose: hunting there means
            // scrolling the shelf, and a colour swatch that was going to be
            // found anyway must not move the shelf on its way past.
            if let tile = try? await tileTarget(name) { return tile }
            throw error
        }
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
                           expect: PlaytestColorDropExpectation, says: String?,
                           number: Int) async throws {
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
        // The line the target is saying about this drag, read while the colour
        // is still in the air: it is the whole of what a refusal owes
        // somebody, and it is the only place the crowd a drop reaches is said
        // out loud. Read from the editor's own state, which is the very value
        // the pill on screen is drawn from.
        let sentence = editor?.colorDropNote?.note
        var held = ""
        if let hold {
            try snapshot(content, name: hold)
            await screenCapture(window, name: hold)
            held = ", held \(hold).png"
        }
        if let says {
            guard let sentence else {
                throw Failure(description: "nothing was said about the colour off "
                    + "\"\(from)\" over \"\(onto)\", and the walk expected \"\(says)\"")
            }
            guard sentence.localizedCaseInsensitiveContains(says) else {
                throw Failure(description: "\"\(onto)\" said \"\(sentence)\" about the colour "
                    + "off \"\(from)\", and the walk expected \"\(says)\"")
            }
        }
        let lightsUp = operation != []
        if lightsUp != (expect == .takes) {
            dropView.draggingExited(info)
            throw Failure(description: "\"\(onto)\" \(lightsUp ? "lit up" : "stayed dark")"
                + " for the colour off \"\(from)\""
                + (sentence.map { ", saying \"\($0)\"" } ?? "")
                + ", and the walk expected it to \(expect.rawValue)")
        }
        let landed = lightsUp ? dropView.performDragOperation(info) : false
        if !lightsUp { dropView.draggingExited(info) }
        await sleep(0.4)
        note(number, "dragColor",
             "the colour off \"\(from)\" let go on \"\(onto)\": the swatch "
                + (lightsUp ? "lit up" : "stayed dark")
                + (sentence.map { ", saying \"\($0)\"" } ?? "")
                + ", drop \(landed ? "landed" : "did not land")\(held)",
             state: describe())
    }

    /// Where a colour can be picked up: a swatch, named by the row it sits on,
    /// or a saved colour's tile on the Library shelf, named by the name it was
    /// saved under. The swatch wins a tie, because every swatch answers to the
    /// word Color and a tile answers to a name somebody typed.
    private func colorDragSource(_ name: String) throws -> PanelTargetView {
        if PlaytestSteadyName.isSteady(name) {
            guard let well = try steadyColorWell(name) else {
                throw Failure(description: "the row \"\(name)\" has no colour swatch to pick a "
                    + "colour up from; a part that is switched off shows none.")
            }
            return well
        }
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
        // A steady name says which ROW, so it finds that row's swatch if the
        // part is on and the row itself if it is off -- the same two answers
        // the word gives, and the same thing a pointer would be over
        // (`PlaytestSteadyName`).
        if PlaytestSteadyName.isSteady(name) {
            if let well = try steadyColorWell(name) { return well }
            return try steadyField(name)
        }
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
    /// The labelled row carrying this steady name.
    private func steadyField(_ name: String) throws -> PanelTargetView {
        let fields = try panelTargets().filter { $0.kind == .field }
        guard let match = fields.first(where: { PlaytestSteadyName.matches(name, steady: $0.steady) })
        else {
            let seen = fields.flatMap(\.steady).map(PlaytestSteadyName.written).joined(separator: ", ")
            throw Failure(description: "no row called \"\(name)\" is in the panel; the steady names "
                + "on screen: " + (seen.isEmpty ? "none" : seen) + ". A `panel` step lists everything.")
        }
        return match
    }

    /// The colour swatch on the row carrying this steady name, or nil when
    /// that row is showing none because its part is switched off.
    private func steadyColorWell(_ name: String) throws -> PanelTargetView? {
        let all = try panelTargets()
        let fields = all.filter { $0.kind == .field }
        return all.first { target in
            target.kind == .control && target.name == "Color"
                && PlaytestPanelPress.steadyFields(of: target, among: fields)
                    .contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
    }

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
    private func blank(canvas size: CGSize, window: CGSize?, card: String?,
                       pixelScale: CGFloat, number: Int) async throws {
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
        // A document that counts in twos, the way one opened from a Retina
        // capture does. Set through the same call the capture-scale control
        // uses, so the walk is driving a real setting rather than a state only
        // a walk can reach.
        if pixelScale != 1 { fresh.setDocumentPixelScale(pixelScale) }
        let unit = pixelScale == 1 ? "" : " at \(pixelScale)x"
        try await adopt(fresh, window: window, step: "blank",
                        subject: "blank \(Int(size.width))x\(Int(size.height))\(unit)",
                        number: number)
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

    /// Take over a window a guide opened that has NOTHING in it.
    ///
    /// The empty sample is a sample: it is the only state that shows the card
    /// offering the ways to get a picture in, which is the one thing in a
    /// window a guide about capturing can point at. There is no canvas to find
    /// and no document to measure, so everything a canvas gives a walk (points
    /// in document space, zoom, the viewport) is unavailable here. The window
    /// is not, and that is enough to photograph it and to drive the guide.
    private func adoptEmpty(_ opened: EditorState, step: String, subject: String,
                            number: Int) async throws {
        try await poll("the editor's window", within: 5) { opened.hostWindow != nil }
        guard let window = opened.hostWindow else {
            throw Failure(description: "the editor lost its window")
        }
        _ = try? await poll("reveal", within: 2) { window.alphaValue >= 1 }
        // Hidden for the rest of the walk, like any other window a walk drives.
        // Unlike the others, nothing ever reveals this one again — opening a
        // document is what does that, and nothing is open — so it is still at
        // zero alpha when a picture is asked for, and the compositor has
        // nothing to hand over for a window at zero alpha. `screenCapture`
        // shows it for the length of the one photograph and puts it back, so a
        // picture of the empty window is a real photograph like any other.
        window.alphaValue = 0
        window.makeKey()
        await sleep(0.5)
        editor = opened
        self.window = window
        canvas = nil
        note(number, step,
             "\(subject): nothing open, so the onboarding card is what is on screen; "
             + "window \(Int(window.frame.width))x\(Int(window.frame.height)) pt",
             state: describe())
    }

    /// Take over the window a video guide opened for itself.
    ///
    /// A recording's window is not a picture editor: there is no canvas, no
    /// document and no viewport, so everything a walk usually measures in
    /// document points is unavailable. The window is there, the clip is loaded
    /// and the floating controller is up, and that is what the guide teaches
    /// over, so that is what gets driven and photographed.
    private func adoptRecording(_ opened: VideoEditorState, step: String, subject: String,
                                number: Int) async throws {
        try await poll("the recording's window", within: 8) { opened.hostWindow != nil }
        guard let window = opened.hostWindow else {
            throw Failure(description: "the recording lost its window")
        }
        // It opens invisible and is revealed once it has sized itself to the
        // clip. Unlike every other walk, it is then LEFT visible.
        //
        // Two things in this window only exist while it is really on screen.
        // The offscreen render draws the video as a black rectangle (the frame
        // lives in a layer the render never sees) and draws the glass
        // controller as very nearly nothing, so a picture taken that way shows
        // neither the clip nor most of the controls a guide is pointing at. The
        // screen capture shows both, and a capture of a window at zero alpha
        // comes back blank. So the probe's own window stays up for the length
        // of the walk, which nobody is watching anyway.
        _ = try? await poll("reveal", within: 4) { window.alphaValue >= 1 }
        window.alphaValue = 1
        window.makeKey()
        window.orderFront(nil)
        await sleep(0.6)
        editor = nil
        canvas = nil
        recording = opened
        self.window = window
        note(number, step,
             "\(subject): \(opened.windowTitle), \(String(format: "%.1f", opened.duration))s of "
             + "\(Int(opened.naturalSize.width))x\(Int(opened.naturalSize.height)); "
             + "window \(Int(window.frame.width))x\(Int(window.frame.height)) pt",
             state: describe())
    }

    /// What the recording in front of the walk is made of, checked rather than
    /// photographed. The video walks were written as describe-and-snapshot
    /// scripts, which means a run on a Mac that cannot photograph anything
    /// proves nothing at all; this is the step that fails.
    private func checkRecording(pieces: Int?, picked: Int?, keeps: Int?,
                                seconds: Double?, starts: Double? = nil,
                                caught: Bool? = nil) throws -> String {
        let video = try requireRecording()
        let counted = video.trimmedPieceCount
        // 1-based on the way in and on the way out, because "piece 2" is what
        // the strip, the readout and a person all say; 0 means none is picked.
        let picking = (video.selectedPieceIndex.map { $0 + 1 } ?? 0)
        let window = video.trim.effectiveDuration
        let saying = "\(video.cuts.pieceCount) piece\(video.cuts.pieceCount == 1 ? "" : "s")"
            + ", \(picking == 0 ? "none picked" : "piece \(picking) picked")"
            + ", \(counted.kept) of \(counted.total) kept"
            + ", window \(String(format: "%.2f", window))s"
            + ", starts at \(String(format: "%.2f", video.trim.inPoint))s"
            + (video.caughtCut.map { ", caught on the cut at \(String(format: "%.2f", $0))s" }
                ?? ", caught on nothing")
            + (video.isTrimming ? ", trim open" : ", trim closed")

        var wrong: [String] = []
        if let pieces, pieces != video.cuts.pieceCount {
            wrong.append("it is in \(video.cuts.pieceCount) pieces, not \(pieces)")
        }
        if let picked, picked != picking {
            wrong.append(picking == 0
                ? "no piece is picked, not piece \(picked)"
                : "piece \(picking) is picked, not piece \(picked)")
        }
        if let keeps, keeps != counted.kept {
            wrong.append("the window keeps \(counted.kept) pieces, not \(keeps)")
        }
        if let seconds, abs(seconds - window) > 0.05 {
            wrong.append("the window is \(String(format: "%.2f", window))s long, not "
                + "\(String(format: "%.2f", seconds))s")
        }
        // Tighter than the window's own tolerance on purpose: a handle that
        // caught on a cut is ON it, and landing a twentieth of a second away
        // is exactly the miss this claim exists to catch.
        if let starts, abs(starts - video.trim.inPoint) > 0.005 {
            wrong.append("the start handle is at \(String(format: "%.3f", video.trim.inPoint))s, "
                + "not \(String(format: "%.3f", starts))s")
        }
        if let caught, caught != (video.caughtCut != nil) {
            wrong.append(caught
                ? "no handle is caught on a cut"
                : "a handle is caught on the cut at "
                    + "\(String(format: "%.2f", video.caughtCut ?? 0))s")
        }
        guard wrong.isEmpty else {
            throw Failure(description: wrong.joined(separator: "; ") + " (the recording reads: "
                + saying + ")")
        }
        return "the recording reads \(saying), as claimed"
    }

    private enum TrimHandle { case start, end }

    /// Drag a trim handle to a spot a given number of POINTS ON SCREEN away
    /// from the cut it is approaching, through exactly the call a pointer
    /// makes. The start handle comes up on the FIRST cut from the left, the end
    /// handle on the LAST one from the right, which is the direction each of
    /// them is actually travelling.
    ///
    /// Points rather than seconds because points are what the magnet measures,
    /// and read off the live track width because that is what a hand would be
    /// looking at. A walk therefore never has to know how long the sample
    /// recording is or how wide the window came up.
    ///
    /// `freed` is ⌘ being held for this event, which is the one thing a walk
    /// cannot press for itself: the key is read off the keyboard at the moment
    /// of the drag, and a scripted run has no hand on it.
    private func dragTrimHandle(_ video: VideoEditorState, _ handle: TrimHandle,
                                pointsFromCut points: CGFloat,
                                freed: Bool = false) throws {
        guard video.isTrimming else {
            throw Failure(description: "the trim handles are not open, so there is no handle to "
                + "drag; add a \"videoBeginTrim\" step first")
        }
        let cuts = VideoCutSnapping.candidates(in: video.cuts)
            .filter { $0 > 1e-6 && $0 < video.duration - 1e-6 }
        guard let target = handle == .start ? cuts.first : cuts.last else {
            throw Failure(description: "the recording has no cut in it to drag a handle towards; "
                + "add a \"videoCut\" step first")
        }
        guard video.trimTrackWidth > 0, video.duration > 0 else {
            throw Failure(description: "the trim track has no width on screen yet, so a distance "
                + "in points is not a distance in time; give the window a moment to lay out")
        }
        let away = TimeInterval(points / (video.trimTrackWidth / CGFloat(video.duration)))
        switch handle {
        case .start: video.dragTrimIn(toTimeline: target - away, freed: freed)
        case .end: video.dragTrimOut(toTimeline: target + away, freed: freed)
        }
    }

    /// How long the file on disk is given to catch up with a save before the
    /// claim about it is called wrong.
    ///
    /// A commit re-encodes, off the main thread, and the step that started it
    /// comes back the instant the work is handed over rather than when the
    /// file changes. `videoSave` waits for its own completion and so never had
    /// this problem; a save pressed the way a PERSON presses it — ⌘S through
    /// the File menu — has nobody to wait on, and `wait` is no help because it
    /// ends as soon as the app goes quiet and an encode keeps the app quiet.
    /// So save-is-live-after-a-trim-walk read the file about a tenth of a
    /// second after ⌘S, found the old eight seconds still there and reported
    /// that Save had done nothing, on a build where it worked: giving it eight
    /// tenths more was enough for the same file to read four seconds. A claim
    /// that is going to come true is now waited for instead of raced.
    ///
    /// Twenty seconds is far longer than the sample has ever taken (about half
    /// a second for a four second clip) and short enough that a save which
    /// genuinely never lands still fails the walk quickly.
    private static let storedRecordingSettles: Double = 20

    /// What the recording's FILE says, which is the only thing that settles
    /// whether a save saved. The app is not asked: the media on disk is opened
    /// and measured, and the hidden original beside it is looked for by hand.
    ///
    /// The file is read again until it agrees with the claim or
    /// `storedRecordingSettles` runs out, so a walk that checks straight after
    /// ⌘S is answered by the save that finishes rather than by the one that
    /// has not started. A claim that is ALREADY true — "the file is still
    /// eight seconds, nothing was committed" — is answered on the first read
    /// and costs nothing.
    private func checkStoredRecording(seconds: Double?, within: Double,
                                      original: Bool?) async throws -> String {
        let video = try requireRecording()
        guard let url = video.url else {
            throw Failure(description: "the recording has no file yet, so there is nothing on disk to read")
        }
        let started = Date()
        let deadline = started.addingTimeInterval(Self.storedRecordingSettles)
        var saying = ""
        var wrong: [String] = []
        while true {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw Failure(description: "there is no file at \(url.path): the recording the walk "
                    + "trimmed is not on disk at all")
            }
            // A fresh asset every pass: AVURLAsset remembers what it read the
            // first time, and the whole point here is to see the file change.
            let asset = AVURLAsset(url: url)
            let stored = try await asset.load(.duration).seconds
            let hasOriginal = VideoOriginals.exists(for: url)
            saying = "\(url.lastPathComponent) on disk is "
                + "\(String(format: "%.2f", stored))s long"
                + (hasOriginal ? ", with the untouched original preserved beside it"
                               : ", with no original preserved beside it")

            wrong = []
            if let seconds, abs(seconds - stored) > within {
                wrong.append("the stored recording is \(String(format: "%.2f", stored))s long, not "
                    + "\(String(format: "%.2f", seconds))s — what the app believes it saved and what "
                    + "is actually in the file are different things")
            }
            if let original, original != hasOriginal {
                wrong.append(hasOriginal
                    ? "the untouched original IS preserved beside it, and the walk said it would not be"
                    : "the untouched original is NOT preserved beside it, so the edit cannot be undone")
            }
            if wrong.isEmpty { break }
            guard Date() < deadline else {
                throw Failure(description: wrong.joined(separator: "; ")
                    + ". \(saying), and it still read that way "
                    + "\(String(format: "%.0f", Self.storedRecordingSettles))s later, so this is "
                    + "a save that did not happen rather than one still encoding")
            }
            await sleep(0.1)
        }
        let waited = Date().timeIntervalSince(started)
        guard waited >= 0.15 else { return saying }
        return saying + ", after \(String(format: "%.1f", waited))s of waiting for the save to land"
    }

    /// Write the open recording out and then READ BACK what landed.
    ///
    /// The save box cannot be driven by a walk, so this hands the exporter the
    /// same recording, format and preset the sheet's Export… button hands it,
    /// and then opens the file: how long it runs, how big its picture is, what
    /// it weighs. A walk that only asked the app whether it had saved would
    /// never notice a trim that did not reach the file.
    private func writeRecordingFile(name: String, format: String, quality: String,
                                    seconds: Double?, within: Double,
                                    width: Double?, height: Double?,
                                    copied: Bool?) async throws -> String {
        let video = try requireRecording()
        guard let recordingFormat = RecordingFormat(rawValue: format) else {
            throw Failure(description: "\(format) is not a format a recording is written as: "
                + RecordingExport.formats.map(\.rawValue).joined(separator: ", "))
        }
        guard let preset = VideoExportQuality(rawValue: quality) else {
            throw Failure(description: "\(quality) is not a size preset: "
                + VideoExportQuality.allCases.map(\.rawValue).joined(separator: ", "))
        }
        guard let sourceURL = video.editSourceURL else {
            throw Failure(description: "the recording has no file to read from yet")
        }
        let source = video.exportSource
        let said = RecordingExport.sizeLine(format: recordingFormat, source: source)
        let destination = out.appendingPathComponent("\(name).\(recordingFormat.fileExtension)")
        let started = Date()
        do {
            try await coordinator.writeRecording(video, as: recordingFormat,
                                                 quality: preset, to: destination)
        } catch {
            throw Failure(description: "writing the recording as \(format) failed: \(error)")
        }
        let took = Int(Date().timeIntervalSince(started) * 1000)

        guard let landed = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              landed > 0 else {
            throw Failure(description: "nothing usable landed at \(destination.lastPathComponent)")
        }
        var facts = ["\(destination.lastPathComponent) is "
                     + "\(ExportQuality.fileSize(bytes: landed)) (\(landed) bytes), "
                     + "written in \(took) ms"]
        var wrong: [String] = []

        // Length and picture size read off the file, not off the app.
        if recordingFormat == .mp4 {
            let asset = AVURLAsset(url: destination)
            let ran = (try? await asset.load(.duration).seconds) ?? 0
            let size = await VideoExporter.orientedNaturalSize(of: destination)
            facts.append("it runs \(Self.round2(ran))s at "
                         + "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) px")
            if let seconds, abs(seconds - ran) > within {
                wrong.append("the file that landed runs \(Self.round2(ran))s, not "
                    + "\(Self.round2(seconds))s, so the trim did not reach it")
            }
            if let width, abs(width - Double(size.width)) > 2 {
                wrong.append("the file that landed is \(Int(size.width.rounded())) px wide, not "
                    + "\(Int(width.rounded())), so the crop did not reach it")
            }
            if let height, abs(height - Double(size.height)) > 2 {
                wrong.append("the file that landed is \(Int(size.height.rounded())) px tall, not "
                    + "\(Int(height.rounded())), so the crop did not reach it")
            }
        } else {
            // An animated picture: how many frames and how big each one is,
            // read out of the file the same way a viewer would.
            let (frames, size) = animatedFacts(of: destination)
            facts.append("it holds \(frames) frame\(frames == 1 ? "" : "s") at "
                         + "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) px")
            if let width, abs(width - Double(size.width)) > 2 {
                wrong.append("each frame is \(Int(size.width.rounded())) px wide, not "
                    + "\(Int(width.rounded()))")
            }
            if let height, abs(height - Double(size.height)) > 2 {
                wrong.append("each frame is \(Int(size.height.rounded())) px tall, not "
                    + "\(Int(height.rounded()))")
            }
        }

        // The fast path claim: an untouched recording going out as MP4 is a
        // file copy, so it must weigh exactly what the recording weighs.
        if let copied {
            let sourceBytes = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let identical = landed == sourceBytes && sourceBytes > 0
            facts.append(identical
                ? "byte for byte the recording itself, so nothing was re-encoded"
                : "re-encoded: the recording itself is "
                    + "\(ExportQuality.fileSize(bytes: sourceBytes))")
            if copied != identical {
                wrong.append(copied
                    ? "this was supposed to be the fast path, a verbatim copy, and the file that "
                        + "landed is \(landed) bytes against the recording's \(sourceBytes): "
                        + "something is re-encoding a recording nobody edited"
                    : "this was supposed to be a re-encode and the file that landed is byte for "
                        + "byte the recording, so the edits were dropped")
            }
        }

        // What the sheet promised, beside what arrived, so an estimate that
        // drifts is visible in the log rather than only in somebody's inbox.
        facts.append("the sheet said \"\(said)\"")

        guard wrong.isEmpty else {
            throw Failure(description: wrong.joined(separator: "; ") + ". "
                + facts.joined(separator: "; "))
        }
        return facts.joined(separator: "; ")
    }

    /// How many frames an animated GIF or HEIC holds and how big they are,
    /// read straight out of the file.
    private func animatedFacts(of url: URL) -> (frames: Int, size: CGSize) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return (0, .zero) }
        let frames = CGImageSourceGetCount(source)
        guard let first = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return (frames, .zero)
        }
        return (frames, CGSize(width: first.width, height: first.height))
    }

    private func requireRecording() throws -> VideoEditorState {
        guard let recording else {
            throw Failure(description: "no recording is open; add a \"startGuide\" step for a video guide first")
        }
        return recording
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
    /// Whether a shelf is really on offer in the Tutorials window, read the way
    /// somebody listening to it would hear it.
    ///
    /// Two ways, because a shelf says itself twice. Its heading is one combined
    /// element reading "Redlining. Measure a screenshot and ... 0 of 5
    /// finished.", and each guide on it says its own title. Either is the shelf
    /// being there; NEITHER is it being gone, which is the claim a walk with a
    /// feature switched off is making.
    static func tutorialTrack(_ track: TutorialTrack, isReadableIn said: [String]) -> Bool {
        if said.contains(where: { $0 == track.title || $0.hasPrefix("\(track.title). ") }) {
            return true
        }
        let titles = TutorialCatalog.guides(in: track).map(\.title)
        return said.contains { line in titles.contains { line.contains($0) } }
    }

    /// The tutorial shelves Help is offering, by the name a person reads.
    /// Read off the live menu rather than off the catalogue, because the whole
    /// question is whether the menu that was BUILT agrees with the catalogue.
    static func tutorialTracksInHelpMenu() -> [String] {
        guard let help = NSApp.mainMenu?.items.first(where: { $0.title == "Help" }),
              let tutorials = help.submenu?.items
                  .first(where: { $0.title == TutorialMenuModel.menuTitle })?.submenu else {
            return []
        }
        tutorials.update()
        let titles = TutorialTrack.allCases.map(\.title)
        return tutorials.items.map(\.title).filter { titles.contains($0) }
    }

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

    /// What a person has to hold down for this item. AppKit spells ⇧⌘Z two
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

    /// How long a step keeps looking for the panel to catch up with it before
    /// it gives up and fails.
    ///
    /// A walk used to read the dock once, at whatever instant the step before
    /// it happened to end, and report whatever it found. The dock builds its
    /// rows lazily and re-lays them out whenever a section opens, so "the
    /// control is not there" and "the control is not there YET" came back as
    /// the same sentence, and the only cure an author had was to write a
    /// longer `wait` and hope. Six walks failed that way in the 2026-09-13
    /// sweeps and every one of them passed on its own straight afterwards.
    ///
    /// Two seconds is far longer than the dock has ever taken to lay itself
    /// out and far shorter than a walk's own timeout, so a control that has
    /// GENUINELY gone away still fails the walk, with the message it failed
    /// with before, two seconds later.
    private static let panelPatience = 2.0

    /// Keeps looking until the look stops failing, or the patience runs out.
    ///
    /// The LAST failure is what the walk reports, so nothing about a real
    /// break reads differently than it did: a control that was never going to
    /// arrive fails with the same sentence, naming the same neighbours.
    private func patiently<T>(_ look: @MainActor () throws -> T) async throws -> T {
        let deadline = CACurrentMediaTime() + Self.panelPatience
        var last: Error?
        while true {
            do { return try look() } catch { last = error }
            guard CACurrentMediaTime() < deadline else { break }
            await sleep(0.05)
        }
        throw last ?? Failure(description: "the panel never settled")
    }

    /// The control a step is about to act on, waited for and scrolled to the
    /// way a person would: if it is not in the panel yet, keep looking; if it
    /// is there but below the fold, scroll to it. Says what it had to do, so a
    /// dock that has started needing a scroll where it did not before shows up
    /// in the log rather than being quietly absorbed.
    private func reachableTarget(_ name: String, in row: String?) async throws
        -> (target: PlaytestPressTarget, effort: String) {
        let began = CACurrentMediaTime()
        var target = try await patiently { try self.pressTarget(name, in: row) }
        let waited = CACurrentMediaTime() - began
        var effort = waited > 0.06 ? String(format: "arrived after %.2fs of looking", waited) : ""
        guard !Self.isInReach(target) else { return (target, effort) }
        let moved = try await bringIntoReach(name, in: row)
        target = try pressTarget(name, in: row)
        if moved > 0.5 {
            effort += effort.isEmpty ? "" : ", "
            effort += "scrolled \(Int(moved))pt to reach it"
        }
        return (target, effort)
    }

    /// The same control, once it has stopped moving.
    ///
    /// A press is real mouse events posted to the app's queue, and AppKit
    /// works out what they landed on when it DELIVERS them, not when they were
    /// posted. So a control measured while the dock was still re-laying itself
    /// out is a control the press misses: the event arrives, the panel has
    /// slid, and the click lands on whatever moved into that spot. Folding one
    /// effect slides every heading below it, which is why the walk that folds
    /// a Border and reads the twist back is the one that kept answering
    /// differently two runs running.
    ///
    /// Settled means two things at once: the control's box has not moved since
    /// the look before, and the app was quiet over that same stretch. Either
    /// alone lets a press through that changes nothing. A box can sit perfectly
    /// still while SwiftUI is part way through replacing the view behind it,
    /// which is how the walk that folds an effect and opens it again came to
    /// press a chevron, watch nothing happen, and read the same chevron back
    /// unchanged one run in six.
    ///
    /// A control that never settles is pressed anyway, at its last known place,
    /// with the log saying so: failing there would turn a busy machine into a
    /// broken walk.
    private func settled(_ target: PlaytestPressTarget, named name: String, in row: String?)
        async -> (target: PlaytestPressTarget, effort: String) {
        await settled(target, named: name) { try self.pressTarget(name, in: row) }
    }

    /// The same, for anything a walk can point at: a row of the Measurements
    /// list settles exactly like a control, and for the same reason
    /// (`clickMeasurementRow`).
    private func settled(_ target: PlaytestPressTarget, named name: String,
                         look: () throws -> PlaytestPressTarget)
        async -> (target: PlaytestPressTarget, effort: String) {
        var last = target
        let deadline = CACurrentMediaTime() + Self.panelPatience
        var looks = 0
        _ = MainThreadMeter.shared.takeBusy()
        _ = MainThreadMeter.shared.takePasses()
        while CACurrentMediaTime() < deadline {
            await sleep(0.03)
            looks += 1
            let busy = MainThreadMeter.shared.takeBusy()
            let passes = MainThreadMeter.shared.takePasses()
            // Reading the panel means walking the whole view tree, which is
            // main thread work and is NOT the app's: left in, it swamped the
            // budget every slice and the answer was always "still busy". The
            // meter takes it off the pass it happened in, the same way the
            // harness's other looking is taken off.
            let began = CACurrentMediaTime()
            let restless = isRestless()
            let now = try? look()
            MainThreadMeter.shared.exclude(CACurrentMediaTime() - began)
            let quiet = passes > 0 && busy <= pace.busyBudget && restless == nil
            guard let now else { continue }
            if quiet, now.box.equalTo(last.box), Self.isInReach(now) {
                return (now, looks > 2 ? "settled after \(looks) looks" : "")
            }
            last = now
        }
        return (last, "never settled, pressed where it last was")
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
            // A slice the main run loop never came back in is not a quiet
            // slice, it is a blocked one. The two look identical through
            // `takeBusy`, which can only add up passes that finished, so the
            // count is what tells them apart: this loop's own sleeping wakes
            // the run loop every slice, so zero passes means the thread never
            // got that far.
            let passes = MainThreadMeter.shared.takePasses()
            let restless = passes == 0 ? "the main thread never came back" : isRestless()
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
        // Work the editor started and has not finished, running off the main
        // thread where the meter cannot see it: reading a picture apart, and
        // reading the words in a run (`EditorState.separationsInFlight` covers
        // both). Each lands back on the main actor and CHANGES THE DOCUMENT, so
        // a wait that goes quiet before it lands hands the next step a document
        // the command has not touched yet. That is what made
        // separate-dark-window-walk read one layer where fifty four were on
        // their way: the action fired, the main thread went idle inside 100ms
        // because the sweep was off it, and the walk's four second wait
        // collapsed to a tenth of a second (found 2026-09-20). The same walk
        // passed when it opened the row menu instead, purely because opening a
        // menu took long enough for the sweep to land.
        if let editor, !editor.separationsInFlight.isEmpty {
            let count = editor.separationsInFlight.count
            return "the editor is still reading \(count) picture\(count == 1 ? "" : "s") apart"
        }
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
        let ids = editor.shownCornerRadiusSelection.layerIDs
        guard !ids.isEmpty, let last = values.last else { return }
        for radius in values { editor.previewCornerRadius(ids: ids, radius) }
        editor.commitCornerRadius(ids: ids, last)
    }

    /// The rotate knob dragged round to `values.last`, in degrees, through the
    /// frames before it: the same preview-per-move and one-step-on-release the
    /// canvas takes, so a walk sees the panel follow the turn as well as the
    /// picture.
    private func turnKnob(_ editor: EditorState, through degrees: [CGFloat]) {
        guard let id = editor.selectedLayerID, let layer = editor.document?.layer(id: id),
              let last = degrees.last else { return }
        var transform = layer.transform
        for angle in degrees {
            transform.rotation = LayerAngle.radians(fromDegrees: angle)
            editor.previewLayerTransform(id: id, transform: transform)
        }
        transform.rotation = LayerAngle.radians(fromDegrees: last)
        editor.commitLayerTransform(id: id, transform: transform)
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

    /// The window an app-wide press is stamped with.
    ///
    /// An event carries a window number whatever it is sent through, so this is
    /// only about building one — the press itself goes to `NSApp`, where an
    /// application-wide monitor sees it whichever window it names. The editor
    /// when there is one, and otherwise whatever the app has on screen: the
    /// walks that stand on a first run have no document open at all, and
    /// never-granting could not press Escape at the capture strip because the
    /// step asked for an editor window that this person never opened
    /// (2026-09-17).
    private func appKeyTarget() throws -> NSWindow {
        if let window { return window }
        if let key = NSApp.keyWindow { return key }
        // Whatever else the app has up — the capture strip on a first run, say.
        // Asked of `windows` rather than `orderedWindows`, which is front to
        // back and would be the better answer: an app that is not the active
        // one has no ordered windows at all, and the probe is never active, so
        // that list came back empty with the strip plainly on screen. The
        // menu-bar item has a window of its own and is never what a press of
        // this kind is about.
        if let shown = NSApp.windows.first(where: {
            $0.isVisible && !String(describing: type(of: $0)).contains("StatusBar")
        }) {
            return shown
        }
        let seen = NSApp.windows.map {
            "\(type(of: $0)) \"\($0.title)\" visible=\($0.isVisible)"
        }.joined(separator: ", ")
        throw Failure(description: "the app has no window on screen to press a key at; it has: \(seen)")
    }

    private func requireWindow() throws -> NSWindow {
        guard let window else { throw Failure(description: "no editor window is open; add an \"open\" step first") }
        return window
    }

    /// The window a plain key press belongs to: the sheet on the editor when
    /// one is up, the editor itself otherwise. See the `.key` case for why.
    private func keyTarget(_ key: PlaytestKey) throws -> NSWindow {
        let editor = try requireWindow()
        if let sheet = editor.attachedSheet { return sheet }
        // ⎋ belongs to the thing standing over the panel, whether or not
        // anything in it is being typed in. A popover is a window in front of
        // the editor and the way a person puts one away is Escape, which AppKit
        // delivers to the popover because the popover is key. Aimed at the
        // editor instead, the press went to a window with no popover in it and
        // the popout stayed open: corner-drag-rounds pressed ⎋, then pressed
        // the chevron again to reopen a popout that had never shut, and so shut
        // it — reading the four corner numbers off a panel that no longer had
        // them (2026-09-17).
        if key == .escape,
           let popover = try panelWindows().first(where: {
               $0 !== editor && $0.parent === editor && Self.isPopover($0)
           }) {
            return popover
        }
        // A POPOVER is a window of its own too, and it takes the keyboard for
        // itself: the Position and Size numbers live in one now, so a walk that
        // sent Return or an arrow key to the editor after focusing a field in
        // there was pressing a key at a window with no field in it. `focus` and
        // `type` already looked across these windows; this is `key` catching up
        // (2026-09-15, when the numbers left the panel).
        if let typing = try panelWindows().first(where: { $0.firstResponder is NSTextView }) {
            return typing
        }
        return editor
    }

    /// Refuse to carry on when ⏎ or ⎋ was pressed at a question sheet and the
    /// sheet is still standing.
    ///
    /// A press that reaches nothing used to be silent, and silence here is
    /// worse than a failure: turn-into-a-picture-walk answered "Turn
    /// “Rectangle” into a picture?" with ⏎, the sheet stayed up, and every
    /// step after it described a document that had never changed — two
    /// renders taken either side of the "turn" came back byte-identical and
    /// the walk still went green (2026-09-16). A walk that proves nothing
    /// while reporting a pass is the one thing the sweep must never do.
    ///
    /// Only for a press with nothing held down that a sheet is meant to
    /// answer. Typing into a field inside a sheet is a different thing and is
    /// left alone.
    private func requireAnsweredSheet(_ key: PlaytestKey, modifiers: [PlaytestModifier],
                                      aimedAt window: NSWindow, takenBy: String) async throws {
        guard modifiers.isEmpty, key.characters == "\r" || key.characters == "\u{1B}" else { return }
        // A sheet leaves on an animation, so give it time to go before calling
        // it stuck. Half a second is far longer than the slide takes and costs
        // nothing at all on the answered path, which is every walk that works.
        for _ in 0..<10 {
            guard (try? requireWindow())?.attachedSheet === window else { return }
            await sleep(0.05)
        }
        guard (try? requireWindow())?.attachedSheet === window else { return }
        let button = (window.defaultButtonCell?.title as String?).flatMap { $0.isEmpty ? nil : $0 }
        let named = button.map { "\"\($0)\"" } ?? "its buttons"
        throw Failure(description:
            "\(key.name) did not answer the sheet: it is still up, so nothing after this step is"
            + " evidence about the app. The press was taken by \(takenBy); the sheet's default"
            + " button is \(named) and it is"
            + " \(window.defaultButtonCell?.isEnabled == true ? "live" : "not live"). Press the"
            + " button by name instead —"
            + " { \"do\": \"press\", \"control\": \(named), \"in\": \"Sheet\" }")
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

    /// What to add to a failed wait so the reader does not have to go hunting
    /// through the log for the numbers. A claim about where a section SITS is
    /// answered by the list of sections, and the list is short.
    private func conditionHint(_ condition: PlaytestCondition) -> String {
        // A dialog named wrong waits out its whole timeout looking like the app
        // never opened it, so say what the names are.
        if case .dialog(let name, _) = condition, !Self.knowsDialog(name) {
            return "; \"\(name)\" is not a dialog this build knows; the ones it does: "
                + Self.dialogNames.joined(separator: ", ")
        }
        guard case .sectionDirectlyUnder = condition else { return "" }
        let drawn = InspectorLayoutProbe.shared.measured.map(\.title)
        guard !drawn.isEmpty else { return "; the dock is drawing no sections at all" }
        return "; the dock draws: " + drawn.joined(separator: " > ")
    }

    /// Two rows read as the same words when only the way they trail off differs,
    /// so a walk can write "Resize Image" for a row that prints "Resize Image…".
    /// Case is forgiven with it: the words on a row are the walk's handle on it,
    /// not a password.
    private static func sameRowWords(_ a: String, _ b: String) -> Bool {
        func plain(_ s: String) -> String {
            var t = s.trimmingCharacters(in: .whitespaces)
            while t.hasSuffix("\u{2026}") || t.hasSuffix(".") { t.removeLast() }
            return t.trimmingCharacters(in: .whitespaces).lowercased()
        }
        return plain(a) == plain(b)
    }

    /// The dialogs a walk can wait on, by the words at the top of each. A sheet
    /// is drawn by the app rather than by AppKit, so there is no window in the
    /// list carrying its name: the editor is what knows.
    private static let dialogNames = ["Resize Image", "Canvas Size", "Export", "New Frame", "Blank Canvas"]

    private static func knowsDialog(_ name: String) -> Bool {
        dialogNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Whether that dialog is up. Nil when nothing in the app answers to the
    /// name, which is a walk with a typo in it rather than a dialog that
    /// refused to open, and which must never read as "it has gone".
    private static func isDialogUp(_ name: String, in editor: EditorState) -> Bool? {
        switch name.lowercased() {
        case "resize image": editor.isResizeDialogPresented
        case "canvas size": editor.isCanvasSizeDialogPresented
        case "export": editor.isExportDialogPresented
        case "new frame": editor.isNewFrameDialogPresented
        case "blank canvas": editor.isBlankCanvasDialogPresented
        default: nil
        }
    }

    private func holds(_ condition: PlaytestCondition, editor: EditorState?) -> Bool {
        // The two conditions that are about the guide rather than about a window.
        if case .tutorialStep(let id) = condition {
            return TutorialController.shared.run?.step.id == id
        }
        if case .tutorialFinished(let id) = condition {
            return TutorialController.shared.finished?.guideID == id
        }
        guard let editor else { return false }
        return switch condition {
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
        // Read off the sections the dock is actually DRAWING, in draw order, so
        // this is the claim a person could check with their eyes: the next
        // header down from Effects says Motion. A section the selection does
        // not bring is not in the way and is not counted.
        case .sectionDirectlyUnder(let title, let anchor):
            InspectorLayoutProbe.shared.measured.map(\.title)
                .firstIndex(of: anchor)
                .map { $0 + 1 < InspectorLayoutProbe.shared.measured.count
                    && InspectorLayoutProbe.shared.measured[$0 + 1].title == title } ?? false
        case .layerRowInView(let name):
            LayersListProbe.shared.isInView(name)
        case .tutorialStep(let id):
            TutorialController.shared.run?.step.id == id
        case .tutorialFinished(let id):
            TutorialController.shared.finished?.guideID == id
        case .dialog(let name, let up):
            Self.isDialogUp(name, in: editor).map { $0 == up } ?? false
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
            } else if flags.isEmpty, key.characters == "\u{1B}", !window.isKeyWindow,
                      window.parent != nil, !window.isSheet, Self.isPopover(window) {
                // A popover over the panel is put away with Escape, and AppKit
                // does that for the KEY window: it is `cancelOperation:` walking
                // the key window's responder chain. The probe is hardly ever the
                // active app, and on a locked Mac it cannot be one at all, so
                // there is no key window and the press reached the popover's
                // responder chain with nothing there to answer it — the popout
                // stayed open. corner-drag-rounds then pressed the chevron to
                // reopen a popout that had never shut, so it SHUT it, and read
                // the four corner numbers off a panel that no longer had them
                // (2026-09-17).
                //
                // So do here what AppKit does for a key window, and only when
                // it will not. The popover's own close is what runs, so SwiftUI
                // sees the dismissal and the chevron that opened it goes back
                // to shut, exactly as it does under a hand.
                window.performClose(nil)
                takenBy = "the popover it was over"
            } else if flags.isEmpty, key.characters == "\r", window.isSheet, !window.isKeyWindow,
                      let button = window.defaultButtonCell, button.isEnabled {
                // The default button of a question sheet carries NO key
                // equivalent of its own. Cancel gets a real "\u{1B}", but
                // Return is wired through `NSWindow.defaultButtonCell`, and
                // AppKit only presses that for the KEY window. The probe is
                // hardly ever the active app — it runs with its window
                // offscreen, and on a locked Mac it cannot be active at all —
                // so there is no key window, the press matched nothing, and a
                // walk that answered "Turn “Rectangle” into a path?" with ⏎
                // was answering nothing.
                //
                // That is not a guess. Printing the sheet's buttons mid-walk
                // on 2026-09-16 gave: Turn Into Path|ke="" ; Cancel|ke="␛" ;
                // DEFAULTCELL=Turn Into Path|ke="" ; key=false appActive=false.
                // And the sweeps agree about when it started: the walk was
                // "ok" every run up to 2026-09-14 16:19 and FAILED at 00:09
                // the next morning, the first sweep after the Mac locked at
                // 20:46. Nothing in the app changed; the app stopped being
                // frontmost.
                //
                // So do here what AppKit does for a key window, and only when
                // it will not: press the default button. A walk's ⏎ then
                // means the same thing whether or not anyone is looking at
                // the screen. Sheets only, on purpose: an ordinary window can
                // carry a default button cell too, and 279 walks press ⏎ at
                // the editor expecting it to go to a field.
                button.performClick(nil)
                takenBy = "the default button \"\((button.title as String?) ?? "")\""
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

    /// Whether this window is the one AppKit puts a popover in.
    ///
    /// By class, because the class is the only honest answer: a popover's
    /// window is a private AppKit type with no public marker on it, and every
    /// other test — being a child, having no title — is true of things that are
    /// not popovers.
    private static func isPopover(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)).contains("Popover")
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
    /// Everything the setup window remembers about whether it has run, so a
    /// walk can forget the lot by name rather than spelling keys again.
    static let firstRunKeys = [WelcomeController.completedDefaultsKey,
                               WelcomeController.dismissedDefaultsKey,
                               WelcomeController.firstRunOfferKey,
                               WelcomeController.firstRunMigratedKey]

    /// What is on file about the first run, for the log: this is the thing the
    /// whole feature is about, so every step that touches it says it out loud.
    static var firstRunReading: String {
        let defaults = UserDefaults.standard
        let answer = WelcomeController.firstRunAnswer.map(\.rawValue) ?? "never asked"
        let said = defaults.bool(forKey: WelcomeController.dismissedDefaultsKey)
            ? "waved away" : "never answered"
        return "setup \(defaults.bool(forKey: WelcomeController.completedDefaultsKey) ? "finished" : "unfinished"), "
            + "setup \(said), tour offer \(answer)"
    }

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

    /// The same trick for any panel hung on the window: a guide's cue ring and
    /// its card are windows of their own, so an offscreen draw of the editor
    /// alone would show a walkthrough with no walkthrough in it.
    private func draw(panel: NSPanel, over view: NSView, into rep: NSBitmapImageRep) {
        guard let window = view.window, let content = panel.contentView,
              let panelRep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: panelRep)
        let image = NSImage(size: content.bounds.size)
        image.addRepresentation(panelRep)
        var rect = view.convert(window.convertFromScreen(panel.frame), from: nil)
        if view.isFlipped { rect.origin.y = view.bounds.height - rect.maxY }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
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
        for panel in TutorialController.shared.panels(over: view.window) {
            draw(panel: panel, over: view, into: rep)
        }
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
            captures.skippedUngranted()
            note(0, "capture", "no Screen Recording grant; skipped")
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                captureFailed(name, "window \(window.windowNumber) not in shareable content")
                return
            }
            // A window at alpha 0 CANNOT be photographed: the compositor
            // holds nothing for it and the picture comes back a blank
            // rectangle. That is not about whether the window ever drew —
            // showing it, drawing it and hiding it again still photographs
            // blank — it is about what it is worth right now.
            //
            // Nearly every window a walk drives is at alpha 1 by the time a
            // picture is asked for, because opening a document reveals it
            // again after the walk hid it, so nearly every picture is taken
            // exactly as before. The one that is not is the empty editor —
            // the only window a guide about getting a picture IN can point
            // at — which is hidden before anything ever reveals it, and
            // which is why its picture used to be blank. So a window that is
            // still invisible is shown for the length of one photograph and
            // put straight back.
            let hidden = window.alphaValue == 0
            if hidden {
                window.alphaValue = 1
                window.display()
                await sleep(0.25)
            }
            let image = try await photograph(window, as: scWindow)
            if hidden { window.alphaValue = 0 }
            let rep = NSBitmapImageRep(cgImage: image)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                captureFailed(name, "the window came back but would not encode as a PNG")
                return
            }
            try png.write(to: out.appendingPathComponent("\(name)-sc.png"))
            captures.photographed(name)
            let hung = Self.hungWindows(on: window).count
            note(0, "capture", "\(name)-sc.png \(image.width)x\(image.height)"
                + (hung > 0 ? " (with \(hung) window\(hung == 1 ? "" : "s") hung on it)" : "")
                + (hidden ? "; the window was still invisible, so it was shown for the one shot" : ""))
        } catch {
            captureFailed(name, "\(error)")
        }
    }

    /// One photograph of this window, at the size of everything hanging off it.
    private func photograph(_ window: NSWindow, as scWindow: SCWindow) async throws -> CGImage {
        let scale = window.backingScaleFactor
        // A window is photographed WITH anything hanging off it, which is
        // the only way a tooltip — a window of its own, hung on the one it
        // labels — is in the picture at all. So the frame to ask for is the
        // rectangle the family fills, not the parent's: ask for the
        // parent's and the capture is squeezed to fit it.
        let bounds = Self.hungWindows(on: window).reduce(window.frame) { $0.union($1.frame) }
        let config = SCStreamConfiguration()
        config.width = Int((bounds.width * scale).rounded())
        config.height = Int((bounds.height * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// The windows hung on this one that a person would actually see: a
    /// tooltip, a toast, a guide's card. The parent is never in this list, so
    /// whether the parent happens to be invisible cannot drop the first hung
    /// window out of the frame and the count, which is what the older reading
    /// of the same list did.
    private static func hungWindows(on window: NSWindow) -> [NSWindow] {
        (window.childWindows ?? []).filter { $0.isVisible && $0.alphaValue > 0 }
    }

    /// A picture that was asked for and not taken, recorded and — this is the
    /// point — with any older picture of the same step deleted.
    ///
    /// An audit ships `<name>-sc.png` by file name, copied out of the walk's
    /// output folder, so a picture under a name nothing took this time is the
    /// one thing that must never be left lying there. Since 2026-09-19 a run
    /// empties its folder before it starts (`prepareOutput`), which covers the
    /// old way this happened — yesterday's photograph under today's name; this
    /// still covers the one inside a single run, where an earlier step
    /// photographed the same name successfully and a later one could not.
    /// Stale evidence is worse than none.
    private func captureFailed(_ name: String, _ reason: String) {
        captures.refused(name)
        let stale = out.appendingPathComponent("\(name)-sc.png")
        let hadStale = FileManager.default.fileExists(atPath: stale.path)
        if hadStale { try? FileManager.default.removeItem(at: stale) }
        note(0, "capture", "failed: \(reason)"
            + (hadStale ? "; deleted the \(name)-sc.png an earlier run left, so nothing stale gets shipped as this one" : ""))
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
        // The chip under the canvas, in the order the editor stacks the two
        // that exist: the Measure hint wins, the Pen's is next.
        let hintReport = Self.hintReading(editor)
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
                // How many anchors and whether it closes: the two things a
                // walk needs to tell one path from another without reading a
                // picture.
                case .path(let path):
                    kind = "path:\(path.anchors.count)\(path.isClosed ? " closed" : " open")"
                case .zoomCallout: kind = "callout"
                // What the lens DOES is the whole of what it is, so the tree
                // says it rather than making a walk read a picture.
                case .lens(let lens): kind = "lens:\(lens.adjustment.rawValue)"
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
                if let path = layer.path {
                    line += " stroke \(Int(path.strokeWidth.rounded()))"
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
            // The aspect the Crop tool is locked to, and the rect it is
            // holding. A lock chosen from Crop's own list has to leave a rect
            // that ALREADY fits it, so this is what a walk reads to prove the
            // tool and the lock arrived in the right order rather than
            // photographing the overlay and hoping.
            "crop": editor.cropRect.map { "\(editor.cropAspect.label) \($0.integral)" }
                ?? "\(editor.cropAspect.label), no rect",
            // What a half-placed caliper is still waiting for. A Distance
            // caliper takes three clicks, so a walk that clicks twice leaves
            // an empty `measures` list on purpose; this says so out loud.
            "measuring": canvas?.playtestMeasuringReport ?? "no canvas",
            // An open arrow caption field, in numbers: the caret, how the
            // draft is aligned, the bubble's box and the box the blue outline
            // is drawn round. Neither the caret (it blinks) nor the outline
            // (a dashed line to be eyeballed against a bubble) can be settled
            // from a picture, so a walk reads them here.
            "captionField": canvas?.playtestCaptionFieldReport ?? "no canvas",
            // The box the blue selection outline is drawn round, in document
            // points. Read beside `captionField` it says whether the outline
            // is following the bubble being typed in or standing still.
            "outline": canvas?.playtestOutlineReport ?? "no canvas",
            // The chip under the canvas, whichever tool has put one up, read
            // in the order the editor stacks them: the Measure hint, then the
            // Pen's. The Pen's is the only place its two endings are told
            // apart AND, now that the tool stays in hand, the only thing on
            // screen that says how to put it down, so a walk can claim its
            // words rather than squinting at a capture.
            "hint": hintReport,
            "copied": editor.copyConfirmation.map { "\($0.title) · \($0.detail)" } ?? "none",
            // Whether the pointer resting on the pill's button is holding its
            // clock open. Only a pill with a button holds, and only its BUTTON
            // notices the pointer, because the rest of the pill lets clicks
            // through to the picture and hovering is the same hit test as
            // clicking (`EditorView.canvasNoticeChip`).
            "noticeHeld": editor.canvasNoticeHeld,
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
            // Whether closing this window would lose work, which is the dot in
            // the close button and the save prompt. A walk reads it to prove
            // that something the app did on its own — reading the words off a
            // picture, say — did NOT leave the person holding unsaved changes
            // they never made.
            "edited": editor.hasUnsavedChanges,
            // The picker's Recent row, newest first. A colour drag must leave
            // ONE entry here for the whole gesture rather than one per frame,
            // and this is what a walk reads to prove it.
            "recentColors": editor.recentColors.colors,
            // Whether this process has focus at all. It never does in a walk,
            // and that one fact is why most menu shortcuts cannot be pressed
            // in one. See `frozenMenuBar`.
            "appActive": NSApp.isActive,
            // What a guide is doing, if one is running: which step, and where
            // the anchor it is pointing at resolved to. A walk that cannot see
            // this can only say the callout looked wrong in a picture.
            "tutorial": TutorialController.shared.liveDescription(in: window),
            // The canvas's own size, so a walk can prove a number typed into
            // the Canvas section landed on the document rather than nowhere.
            "canvas": document.map { "\(Int($0.canvasSize.width))x\(Int($0.canvasSize.height))" } ?? "none",
            // The editor WINDOW's own size in points. The app hides its title
            // bar, so a double click on bare canvas is its stand-in for double
            // clicking one, and that gesture zooms the window. This is how a
            // walk proves the window jumped, or proves it stayed exactly where
            // it was while a tool was being drawn with.
            "window": window.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "none",
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
            // The row the Appearance panel actually SHOWS, which over a group
            // is not the same row: it reads the curve on screen rather than the
            // group's own invisible mask, and its knob starts where the group's
            // contents already are rather than at the far left with a dead
            // stretch of track in front of it (`ContainerRounding.swift`).
            // Printed as "<reading> from <floor> ×<count>".
            "cornerRadiusShown": {
                let selection = editor.corneredRadiusSelection
                guard !selection.isEmpty else { return "none" }
                let reading = selection.reading
                let body = reading.isMixed
                    ? "mixed"
                    : (reading.value.map { "\(Int($0.rounded()))" } ?? "none")
                // "reaching" when the row has gone past a picked group to speak
                // for the things inside it, which is the whole of what a pull on
                // a group does now.
                let reach = selection.reachesContents ? " reaching" : ""
                // "cropping" when the row is rounding the edge a card cuts its
                // contents off at, which is the one group the row stays on.
                let crop = selection.cropsContents ? " cropping" : ""
                return "\(body) from \(Int(selection.floor.rounded()))"
                    + "\(reach)\(crop) ×\(selection.count)"
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
            // The rows of the layers list a person can see WHOLE, in order.
            // The list shows five rows of however many the document has, so
            // "the layer you just picked is one of these" is the whole claim
            // the list following a pick has to keep true.
            "layerRowsInView": LayersListProbe.shared.rowsInView,
            "layerList": LayersListProbe.shared.measurements,
            // ...and what the last pick did about it: which rows it was asked
            // for, where the list was, and where it went.
            "layerReveal": LayersListProbe.shared.lastReveal ?? "none yet",
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
            "iconKeylines": canvas?.playtestIconKeylineReport ?? "no canvas",
            // The named colors in the document, and what each one paints, so a
            // walk can prove an edit to a style reached everything wearing it.
            "styles": (editor.document?.colorStyles ?? []).map {
                "\($0.name) \($0.colorHex) · \(editor.colorStyleUsageCount(styleID: $0.id)) used"
            },
            // What the picked layer's FIRST colour row can paint with but
            // cannot wear the name of: a colour kept for other parts, a ramp
            // where no ramp can go, and the colour inside a saved border,
            // shadow, glow or way of setting text. A walk reads it here because
            // the list lives in a SwiftUI menu in the dock, which the pointer
            // cannot open (`BorrowedColors.swift`).
            "borrowedColors": editor.colorRowSlots.first
                .map { editor.borrowedColors(for: $0).map(\.label) } ?? [],
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
    /// Run loop passes over the same stretch. Zero of them is not an idle
    /// thread, it is a thread that never came back (`settle`).
    private var passesSinceAsked = 0

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
                    passesSinceAsked += 1
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
        passesSinceAsked = 0
    }

    /// How much the app did on the main thread since this was last asked, and
    /// the counter starts again. Only whole run loop passes count, so work the
    /// harness is in the middle of doing right now is not in the answer.
    func takeBusy() -> CFTimeInterval {
        let answer = max(0, sinceAsked)
        sinceAsked = 0
        return answer
    }

    /// How many whole run loop passes happened since this was last asked, and
    /// the count starts again.
    func takePasses() -> Int {
        let answer = passesSinceAsked
        passesSinceAsked = 0
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

/// Which part of a bar a walk said it was taking hold of, in the strip's own
/// terms.
extension PlaytestTimingGrab {
    var grab: MotionStripDrag.Grab {
        switch self {
        case .body: .body
        case .start: .start
        case .end: .end
        }
    }
}
#endif
