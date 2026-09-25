import AppKit
import Observation
import PhotonzCore
import SwiftUI

// Runs one guide over the real app.
//
// The idiom this is built on is the app's own tooltip (`HintTooltip.swift`): a
// borderless child panel floating over the editor window, placed against an
// invisible marker on a control, drawn with the same beak. Not the zoom
// callout's leader lines, which are drawn INTO the picture and belong to the
// document, and not a popover, which is attached to one control and closes the
// moment you touch anything else. A guide has to survive you using the app.
//
// Two panels, because they want opposite things from the mouse: the cue ring
// ignores it completely so the control under it is pressed exactly as it would
// be with no guide running, and the card takes clicks for its own buttons. The
// app is never dimmed, never blocked, and never modal.
//
// Following: the anchor is read fresh on a timer rather than subscribed to.
// There is no one notification for "the panel scrolled, the window resized, a
// section collapsed, the tool bar shed a button"; reading the marker's frame a
// few dozen times a second covers all of them and costs one coordinate
// conversion.
@MainActor
@Observable
final class TutorialController {
    static let shared = TutorialController()

    /// Where the person is, or nil when no guide is running.
    private(set) var run: TutorialRun?

    /// The card a finished guide leaves behind, or nil.
    ///
    /// A guide used to end by vanishing: the callout disappeared on Done and
    /// whoever had just been shown round was left alone in the little made up
    /// picture it had opened to teach in, with nothing saying what to do next.
    /// So the last press swaps the step card for this one, in the same plate,
    /// in the middle of the guide's own window (`TutorialFinish`).
    private(set) var finished: TutorialFinish?

    /// What they have finished, and where they stopped in anything they left
    /// part way. Written on every step, so quitting mid guide loses nothing.
    private(set) var progress: TutorialProgress

    /// The window's own state, asked for a window, for a reveal, and for
    /// whether a step's trigger is already true. A picture editor or a
    /// recording's window: the controller never asks which.
    @ObservationIgnored private weak var host: (any TutorialHost)?
    @ObservationIgnored private var cardPanel: NSPanel?
    @ObservationIgnored private var cuePanel: NSPanel?
    @ObservationIgnored private var cardHost: NSHostingView<AnyView>?
    @ObservationIgnored private var cueHost: NSHostingView<TutorialCueView>?
    @ObservationIgnored private var follow: Timer?
    @ObservationIgnored private var lastAnchorFrame: CGRect?
    @ObservationIgnored private var lastWindowFrame: CGRect?
    /// The step the panels are currently DRAWING. Compared before anything is
    /// skipped as unchanged: without it, moving from a step whose control is on
    /// screen to one whose control is not left the previous step's callout up,
    /// unchanged and wrong, because "no anchor" and "no anchor yet" look the
    /// same from here.
    @ObservationIgnored private var drawnStepID: String?
    /// The anchor the panels are currently drawing ON, which is not always the
    /// one the step named: a tool that is not on the bar is rung through the
    /// slot or the More button holding it. Compared before anything is skipped
    /// as unchanged, so a step that moves from the family slot to the tool's
    /// own button redraws even if the two happen to sit at the same rectangle.
    @ObservationIgnored private var drawnStandIn: TutorialAnchor?
    /// Passes left to keep asking for the step's target to be scrolled into
    /// view. Counted down in `place`, so the ask survives the section arriving
    /// a beat late.
    @ObservationIgnored private var revealTries = 0
    @ObservationIgnored private var closeObserver: NSObjectProtocol?
    /// What each step of each guide run this launch saw when it pointed at its
    /// control: whether the control was ever found on screen, and how long the
    /// step was up. A walk reads this back and FAILS on a step that pointed at
    /// nothing, which is how a renamed control breaks the build instead of
    /// somebody's tour (`TutorialAnchorAudit`).
    @ObservationIgnored private(set) var anchorVerdicts: [TutorialAnchorVerdict] = []
    /// The step that is up right now, still being judged.
    @ObservationIgnored private var openStep: OpenStep?

    private struct OpenStep {
        let guide: String
        let step: String
        let anchor: TutorialAnchor
        var resolved = false
        /// Seconds this step was really ON SCREEN: the window up, in front of
        /// the person, with the callout being placed. Not the same as how long
        /// the step was current. A guide whose window is covered draws nothing
        /// and can find nothing, and counting that time would turn a covered
        /// window into a missing control.
        var shown: CFTimeInterval = 0
        /// The last pass that counted, for the running total.
        var lastTick: CFTimeInterval?

        mutating func tick() {
            let now = CACurrentMediaTime()
            // Capped, so a gap while the window was covered is not billed to
            // the step as time on screen.
            if let last = lastTick { shown += min(now - last, 0.2) }
            lastTick = now
        }
    }
    /// Where progress is written. Not private: a walk that photographs the
    /// Tutorials window forgets this key first, and it reads the name off here
    /// rather than spelling it again.
    static let progressKey = "tutorials.progress"
    /// Fast enough that the card reads as attached to the control while a
    /// window is being dragged, cheap enough to be free: one frame conversion.
    private static let followInterval: TimeInterval = 1.0 / 30.0
    /// About a second of passes. Long enough for a panel section that arrives
    /// with the selection, short enough that it stops asking once a person has
    /// scrolled somewhere else on purpose.
    private static let revealTries = 30

    private init() {
        progress = Self.loadProgress()
    }

    var isRunning: Bool { run != nil }

    /// Whether anything of the guide is still on screen, a running step or the
    /// card it ended on. What decides whether the panels are drawn at all.
    private var isShowing: Bool { run != nil || finished != nil }

    /// The guide running right now, for a menu that wants to say so.
    var runningGuideID: String? { run?.guide.id }

    /// The guide's own panels while they float over `window`, so an offscreen
    /// render of that window can include them. Same hook the tooltip offers,
    /// for the same reason.
    func panels(over window: NSWindow?) -> [NSPanel] {
        guard let window, isShowing else { return [] }
        return [cuePanel, cardPanel].compactMap { $0 }
            .filter { $0.isVisible && $0.parent === window }
    }

    /// What a guide is doing, in one line, for a walk's log: the step, where
    /// its anchor resolved to, and where the card ended up. "none" when no
    /// guide is running. This is what lets a walk FAIL on a callout pointing at
    /// nothing instead of a person noticing it in a picture later.
    func liveDescription(in window: NSWindow?) -> String {
        if let finished {
            return "finished \(finished.guideID); card \"\(finished.title)\" offering "
                + finished.choices.map(\.name).joined(separator: ", ")
                + (cardPanel?.isVisible == true ? "" : "; CARD NOT UP")
        }
        guard let run else { return "none" }
        let anchor = run.step.anchor
        // Through the stand-in chain, the same way the ring is placed, and it
        // SAYS when it went through one: "tool.frame via moreTools" is the
        // difference between a step pointing at nothing and a step pointing at
        // the button the tool is inside.
        let found = window.flatMap { standIn(for: anchor, in: $0) }
        let where_ = found.map { standIn in
            let via = standIn.anchor == anchor ? "" : " via \(standIn.anchor.name)"
            let box = standIn.frame
            return "\(via) (\(Int(box.minX)), \(Int(box.minY))) \(Int(box.width))x\(Int(box.height))"
        } ?? " NOT ON SCREEN"
        let host = hostWindow.map {
            "; host window \($0.isMiniaturized ? "miniaturized" : "up"), "
                + "occlusion \($0.occlusionState.contains(.visible) ? "visible" : "HIDDEN")"
        } ?? "; NO HOST WINDOW"
        let verdict = openStep.map {
            "; \($0.resolved ? "found" : "NOT FOUND YET") after "
                + String(format: "%.1fs on screen", $0.shown)
        } ?? ""
        return "\(run.guide.id)/\(run.step.id) \(run.number) of \(run.count); "
            + "\(anchor.name) at\(where_); card \(cardPanel.map { "\(Int($0.frame.minX)), \(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "none")"
            + host + verdict
    }

    /// The window the running guide is teaching in. What a walk asks the anchor
    /// registry about, because the guide's own window is not always the one the
    /// walk opened: a guide with a sample brings its own.
    var guideWindow: NSWindow? { host?.tutorialWindow }

    /// Whether the step that is up has found its control on screen yet. Read by
    /// a walk that is giving a step its moment before calling the control
    /// missing.
    var currentStepFoundItsControl: Bool { openStep?.resolved ?? false }

    /// Every verdict including the step that is up, so a walk can ask at the
    /// end without closing the guide first.
    var anchorVerdictsSoFar: [TutorialAnchorVerdict] {
        guard let open = openStep else { return anchorVerdicts }
        return anchorVerdicts + [verdict(for: open)]
    }

    private func verdict(for open: OpenStep) -> TutorialAnchorVerdict {
        TutorialAnchorVerdict(guide: open.guide, step: open.step, anchor: open.anchor,
                              resolved: open.resolved, shownSeconds: open.shown)
    }

    /// Closes the book on the step that was up. Called wherever a step is left:
    /// moving on, going back, finishing, and closing part way.
    private func closeStepVerdict() {
        guard let open = openStep else { return }
        anchorVerdicts.append(verdict(for: open))
        openStep = nil
    }

    /// Forget what earlier guides saw. A walk that drives several guides in one
    /// run has no reason to, and does not.
    func clearAnchorVerdicts() {
        openStep = nil
        anchorVerdicts = []
    }

    // MARK: - Starting and stopping

    /// Runs `guide` over `host`. Picks up where the person left off if they
    /// stopped part way through this one before.
    func start(_ guide: TutorialGuide, in host: any TutorialHost) {
        stop(remembering: true)
        self.host = host
        host.tutorialRunning(true)
        run = TutorialRun(guide: guide, startingAt: progress.startIndex(for: guide))
        beginStep()
        startFollowing()
    }

    /// Starts the guide over again from the top, forgetting where you were.
    func restart(_ guide: TutorialGuide, in host: any TutorialHost) {
        progress.restart(guide.id)
        saveProgress()
        start(guide, in: host)
    }

    /// Closes the guide. Keeps your place unless the guide finished.
    func close() {
        stop(remembering: true)
    }

    /// The last step's Done. The guide is over, but the person is not: the
    /// step card is swapped for the finish card and the window it was teaching
    /// in is kept, so there is something on screen saying what just happened
    /// and where to go (`TutorialFinish`).
    private func finish() {
        guard let guide = run?.guide, let host else {
            stop(remembering: false)
            return
        }
        progress.complete(guide.id)
        saveProgress()
        closeStepVerdict()
        run = nil
        finished = TutorialFinish.make(after: guide, offered: TutorialLauncher.offered,
                                       inSampleWindow: host.isTutorialSampleWindow)
        // The ring belonged to a step, and there is no step now.
        tearDown(&cuePanel)
        cueHost = nil
        revealTries = 0
        lastAnchorFrame = nil
        lastWindowFrame = nil
        drawnStepID = nil
        drawnStandIn = nil
        place()
    }

    // MARK: - What a finished guide offers

    /// The person pressed one of the rows on the finish card.
    func choose(_ choice: TutorialFinishChoice) {
        guard finished != nil else { return }
        switch choice {
        case .nextGuide(let id, _):
            guard let guide = TutorialCatalog.guide(id: id),
                  let coordinator = AppDelegate.coordinator else { return }
            // Straight into the next one. `start` closes this card itself, and
            // a guide sharing this guide's sample carries on in this very
            // window rather than opening a second one (`TutorialLauncher`).
            TutorialLauncher.start(guide, coordinator: coordinator,
                                   editor: host as? EditorState)
        case .startYourOwn:
            startYourOwn()
        case .moreGuides:
            let coordinator = AppDelegate.coordinator
            dismissFinish()
            coordinator?.showTutorials()
        }
    }

    /// Leave the practice picture behind for an empty window, which is the one
    /// place in the app where every way of getting a picture in is a row you
    /// can press rather than a key you have to already know.
    ///
    /// The new window is opened FIRST and the sample closed after, so the
    /// person is never looking at an empty screen in between, and the sample is
    /// only closed when closing it would lose nothing. A practice picture
    /// somebody has drawn on is still something they made, and throwing it away
    /// on their behalf, or asking them to save "Tutorial Sample" in a sheet
    /// they did not go looking for, are both worse than one extra window.
    private func startYourOwn() {
        let sample = host?.isTutorialSampleWindow == true ? hostWindow : nil
        dismissFinish()
        AppDelegate.coordinator?.newDocumentWindow()
        guard let sample, !sample.isDocumentEdited else { return }
        // One turn later, so the empty window asked for above has arrived
        // before this one leaves. Closing first would take the app down to no
        // windows for a beat, and an app with no windows hands focus to
        // whatever was behind it (`AppCoordinator.editorWindowWillClose`).
        DispatchQueue.main.async {
            // Through the window's own close, not straight past it: if
            // anything still thinks there is something in there worth keeping,
            // the person gets asked rather than losing it.
            sample.performClose(nil)
        }
    }

    /// Take the finish card down and leave the window as it is.
    func dismissFinish() {
        guard finished != nil else { return }
        stop(remembering: false)
    }

    private func stop(remembering: Bool) {
        closeStepVerdict()
        finished = nil
        if remembering, let run {
            progress.record(guide: run.guide.id, step: run.index)
            saveProgress()
        }
        run = nil
        host?.tutorialRunning(false)
        host = nil
        lastAnchorFrame = nil
        lastWindowFrame = nil
        drawnStepID = nil
        drawnStandIn = nil
        follow?.invalidate()
        follow = nil
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        tearDown(&cardPanel)
        tearDown(&cuePanel)
        cardHost = nil
        cueHost = nil
    }

    private func tearDown(_ panel: inout NSPanel?) {
        guard let existing = panel else { return }
        existing.parent?.removeChildWindow(existing)
        existing.orderOut(nil)
        panel = nil
    }

    // MARK: - Moving through it

    func next() {
        guard var current = run else { return }
        if current.advance() {
            run = current
            beginStep()
        } else {
            finish()
        }
    }

    func back() {
        guard var current = run, current.back() else { return }
        run = current
        beginStep()
    }

    /// Something happened in the editor. A step that was waiting for exactly
    /// this moves on by itself; anything else is ignored.
    ///
    /// Nothing here is on a timer. A step that says "pick the Measure tool" and
    /// moves on five seconds later whether or not you did is a lie, and the
    /// person notices.
    func note(_ trigger: TutorialTrigger, from host: any TutorialHost) {
        guard let run, self.host === host, run.isSatisfied(by: trigger) else { return }
        // Let the editor finish the change that produced the event before the
        // callout jumps to a new control.
        DispatchQueue.main.async { [weak self] in
            guard let self, let current = self.run, current.isSatisfied(by: trigger) else { return }
            self.next()
        }
    }

    /// An edit landed in `host`'s document. A step waiting on a KIND of edit
    /// (a cut, a clip brought in, a transition put on) asks the document
    /// before and after whether that is what just happened
    /// (`TutorialDocumentChange`). Only the question the waiting step asks is
    /// worked out, so an edit made while no such step is up costs nothing.
    func noteDocumentChange(from before: PhotonzDocument, to after: PhotonzDocument,
                            in host: any TutorialHost) {
        guard let run, self.host === host, let trigger = run.step.advance.trigger,
              trigger.isDocumentChange,
              TutorialDocumentChange.happened(trigger, from: before, to: after) else { return }
        note(trigger, from: host)
    }

    /// A step waiting on a VALUE is answered by READING the document, not by
    /// being told something happened.
    ///
    /// "Pull Strength up until the address cannot be read at all" is a question
    /// about where the slider is NOW, and every event that could carry it is
    /// raised just as loudly one point in as it is at the far end, so the step
    /// used to move on at the first flicker. The question is asked again on
    /// every pass while the step is up instead.
    ///
    /// Asking on a repeat is not advancing on a timer, and the difference is
    /// the whole rule. A timer moves the step on whether or not the person did
    /// the thing; this reads the real document and moves on only when it really
    /// holds the value, waiting as long as it takes otherwise, with Skip This
    /// Step on the card the whole while.
    private func checkWatchedValue() {
        guard let run, let host, run.waitsOnAValue,
              // Already there when the step came up, so the card is showing
              // Next and the person has not been asked for anything. Moving on
              // by ourselves here would flash the step past them unread.
              !run.stepWasAlreadyTrue,
              let trigger = run.step.advance.trigger,
              host.tutorialIsAlreadyTrue(trigger)
        else { return }
        next()
    }

    /// Applies the step's prepare actions and puts the callout up. Prepare may
    /// only REVEAL: showing the panel so a step can point at the Layers list is
    /// fine, picking the tool for a step that says "pick the tool" is the timer
    /// lie in another costume, which is why the list is closed.
    private func beginStep() {
        guard let run, let host else { return }
        closeStepVerdict()
        openStep = OpenStep(guide: run.guide.id, step: run.step.id, anchor: run.step.anchor)
        progress.record(guide: run.guide.id, step: run.index)
        saveProgress()
        // A step can ask for something that is already so: the Measure tool is
        // kept in the mode you left it in, so "press I until it reads Distance"
        // comes up with the button already reading Distance. Waiting on that
        // would strand somebody on a step they cannot perform, with nothing to
        // press but Skip. So the step still says its piece and the way on is a
        // plain Next.
        if let trigger = run.step.advance.trigger, host.tutorialIsAlreadyTrue(trigger) {
            self.run?.markStepAlreadyTrue()
        }
        for prep in run.step.prepare {
            host.tutorialPrepare(prep)
            if prep == .revealTarget {
                // Tried again on the next few passes as well: a section that
                // arrives with the selection is not in the panel yet at this
                // point, so one attempt here would scroll to nothing.
                revealTries = Self.revealTries
            }
        }
        // The revealed surface needs a layout pass before its marker has a
        // frame worth reading, so the first placement waits one turn.
        lastAnchorFrame = nil
        drawnStepID = nil
        drawnStandIn = nil
        DispatchQueue.main.async { [weak self] in self?.place() }
    }

    // MARK: - Following the control

    private func startFollowing() {
        follow?.invalidate()
        let timer = Timer(timeInterval: Self.followInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkWatchedValue()
                self?.place()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        follow = timer
    }

    private var hostWindow: NSWindow? { host?.tutorialWindow }

    /// Whether a scripted walk is driving this app right now. Always false in
    /// the shipping build, which does not contain the harness at all.
    private static var aWalkIsDriving: Bool {
        #if PHOTONZ_PLAYTEST
        PlaytestHarness.isDrivingAWalk
        #else
        false
        #endif
    }

    /// Whether the card a guide is showing — a step's callout, or the finish
    /// card — is really on screen. What a walk asks before it photographs the
    /// window, so a picture with no card in it is never shipped as one with.
    var cardIsOnScreen: Bool { cardPanel?.isVisible == true && cardPanel?.alphaValue ?? 0 > 0 }

    /// What the guide has to show for itself right now, for a walk that is
    /// about to take a picture: the step it is on, or the finish card, or nil
    /// when no guide is showing anything at all.
    var whatTheCardIsSaying: String? {
        if let run { return "\(run.guide.id) step \(run.step.id), \(run.number) of \(run.count)" }
        if let finished { return "the card that finished \(finished.guideID)" }
        return nil
    }

    private func place() {
        guard let window = hostWindow else { return }
        watchForClose(window)
        if let finished {
            placeFinish(finished, in: window)
            return
        }
        guard let run else { return }
        if revealTries > 0 {
            revealTries -= 1
            if run.step.prepare.contains(.revealTarget) {
                TutorialAnchorRegistry.shared.reveal(run.step.anchor, in: window)
            }
        }
        // This pass counts as time the step had to find its control, and the
        // control either is in the window or it is not.
        //
        // Neither of those is a question about what is in FRONT of the window.
        // They used to be: both lines sat below the guard beneath them, so a
        // window somebody had buried, or that the login window covered while
        // the screen was locked, left every step of every guide reading "never
        // found its control" — about a tool bar plainly in the window, sitting
        // at a rectangle the registry could name. That is what made 31 of 31
        // tutorial walks fail on the night of 2026-09-14 with nothing wrong in
        // the app (`PlaytestScreenState`).
        openStep?.tick()
        // Not just the name the step gave. A tool that is not on the bar right
        // now — a shape whose slot is wearing a different member, anything a
        // narrow window has pushed into the More menu — is rung through the
        // thing it is INSIDE, and the card says which (`TutorialStandIn`).
        let standIn = standIn(for: run.step.anchor, in: window)
        let anchor = standIn?.frame
        // Found once is found: the step's verdict is settled here, before any
        // of the shortcuts below can return early on a frame where nothing
        // moved.
        if anchor != nil { openStep?.resolved = true }
        // DRAWING is the part that needs the window in front. A callout over a
        // covered window would be a card floating on top of whatever the person
        // is really looking at, so the panels go away and come back when the
        // window does.
        //
        // Unless nobody is looking at it: a walk drives a window it never
        // brings to the front and photographs that window itself, so what is
        // in front of it must not decide what is in the picture
        // (`TutorialCardPresence`).
        guard TutorialCardPresence.shouldBeOnScreen(
            miniaturized: window.isMiniaturized,
            windowVisible: window.occlusionState.contains(.visible),
            aWalkIsDriving: Self.aWalkIsDriving) else {
            cardPanel?.orderOut(nil)
            cuePanel?.orderOut(nil)
            // Nothing was placed, so the next visible pass has to place it
            // rather than deciding nothing moved.
            lastAnchorFrame = nil
            drawnStepID = nil
            drawnStandIn = nil
            return
        }
        // On screen WHOLE: stop asking, so a person who scrolls somewhere else
        // is not fought by a guide that got what it wanted a moment ago.
        //
        // Whole rather than merely visible, because something else in the app
        // scrolls the panel a beat after a command lands: Make Component sends
        // the dock to the shelf to show you the new tile, which leaves the
        // Component section hanging off the top with its Name box out of sight.
        // A sliver used to count as arrived, so the guide stopped asking and
        // rang the two rows that were left.
        if let standIn, TutorialAnchorRegistry.shared.isWhollyShown(standIn.anchor,
                                                                    in: window) {
            revealTries = 0
        }
        let container = window.frame
        // Nothing moved: do not touch the panels, so a still window is a still
        // callout rather than a frame being reset thirty times a second.
        if anchor == lastAnchorFrame, container == lastWindowFrame,
           drawnStepID == run.step.id, drawnStandIn == standIn?.anchor,
           cardPanel?.isVisible == true { return }
        lastAnchorFrame = anchor
        lastWindowFrame = container
        drawnStepID = run.step.id
        drawnStandIn = standIn?.anchor

        guard let standIn, let anchor else {
            // The control is not on screen. Nobody gets stranded: the card goes
            // to the middle of the window with no beak and no ring, and the way
            // on still works. The step's verdict stays unresolved, and a walk
            // driving this guide fails on it.
            placeCentred(in: container, window: window)
            cuePanel?.orderOut(nil)
            return
        }
        placeCallout(anchor: anchor, container: container, window: window, run: run,
                     note: note(for: standIn))
        // The ring takes the shape of what it is really round. A tool rung
        // through the More button gets the More button's outline, not the
        // outline of a button that is not on the bar.
        placeCue(anchor: anchor, shape: standIn.anchor.cueShape, window: window)
    }

    /// Where this step's control is to be found right now, and what is hiding
    /// it. Nil when nothing in the chain is on screen at all, which is the one
    /// case the card admits to by going to the middle of the window.
    private func standIn(for wanted: TutorialAnchor,
                         in window: NSWindow) -> (anchor: TutorialAnchor,
                                                  concealment: TutorialConcealment?,
                                                  frame: CGRect)? {
        for candidate in TutorialAnchorStandIns.chain(for: wanted) {
            guard let frame = TutorialAnchorRegistry.shared.screenFrame(of: candidate.anchor,
                                                                       in: window) else { continue }
            return (candidate.anchor, candidate.concealment, frame)
        }
        return nil
    }

    /// The extra line for the card, or nil when the ring is on the very control
    /// the step named and there is nothing to explain.
    private func note(for standIn: (anchor: TutorialAnchor,
                                    concealment: TutorialConcealment?,
                                    frame: CGRect)) -> String? {
        guard let concealment = standIn.concealment, let run else { return nil }
        return concealment.sentence(for: Self.subject(of: run.step.anchor))
    }

    /// What the card calls the thing the step is really about. The tool's own
    /// name where there is one, and the family's where a step names the slot.
    private static func subject(of anchor: TutorialAnchor) -> String {
        if let tool = anchor.tool { return tool.barTitle }
        if let group = anchor.toolGroup { return "\(group.title) button" }
        return "control"
    }

    private func placeCallout(anchor: CGRect, container: CGRect, window: NSWindow,
                              run: TutorialRun, note: String?) {
        let flippedAnchor = TutorialGeometry.flip(anchor, in: container)
        let flippedContainer = TutorialGeometry.flip(container, in: container)
        let cardSize = CGSize(width: TutorialCalloutView.width,
                              height: measuredCardHeight(run, note: note))
        let placed = TutorialCalloutLayout.place(anchor: flippedAnchor, size: cardSize,
                                                 container: flippedContainer,
                                                 preferred: run.step.side,
                                                 busy: busyAreas(in: window)
                                                     .map { TutorialGeometry.flip($0, in: container) })
        // Room for the beak, taken out of the gap on the side it points from.
        var frame = placed.frame
        switch placed.side {
        case .above: frame.size.height += TutorialCalloutView.beakHeight
        case .below:
            frame.origin.y -= TutorialCalloutView.beakHeight
            frame.size.height += TutorialCalloutView.beakHeight
        case .leading: frame.size.width += TutorialCalloutView.beakHeight
        case .trailing, .automatic:
            frame.origin.x -= TutorialCalloutView.beakHeight
            frame.size.width += TutorialCalloutView.beakHeight
        }
        show(view(for: run, side: placed.side, beakOffset: placed.beakOffset, note: note),
             at: TutorialGeometry.flip(frame, in: container), in: window)
    }

    /// What is drawn on the canvas at this moment, plus the app's own floating
    /// tool bar over it: everything a card PARKED on a surface has to keep off.
    /// In screen coordinates, like every other frame here.
    ///
    /// Only a step about the whole picture ever uses it, and only to choose
    /// where to sit. It is read when the step arrives rather than every frame:
    /// a card that chased the picture while you dragged a layer about would be
    /// a card that never sits still, and the placement is already left alone
    /// until the step, the window or the anchor moves.
    private func busyAreas(in window: NSWindow) -> [CGRect] {
        guard let canvas = Self.canvasView(in: window.contentView) else { return [] }
        var areas = canvas.tutorialBusyScreenRects
        // The bar floats OVER the canvas, so a card that dodged the picture by
        // sitting on the bar would have swapped one cover-up for another.
        if let bar = TutorialAnchorRegistry.shared.screenFrame(of: .toolBar, in: window) {
            areas.append(bar)
        }
        return areas
    }

    private static func canvasView(in view: NSView?) -> CanvasNSView? {
        guard let view else { return nil }
        if let canvas = view as? CanvasNSView { return canvas }
        for child in view.subviews {
            if let found = canvasView(in: child) { return found }
        }
        return nil
    }

    /// The finish card, in the middle of the window the guide taught in. No
    /// beak and no ring: it is not about a control, it is about the guide being
    /// over.
    private func placeFinish(_ finish: TutorialFinish, in window: NSWindow) {
        guard !window.isMiniaturized, window.occlusionState.contains(.visible) else {
            cardPanel?.orderOut(nil)
            lastWindowFrame = nil
            return
        }
        let container = window.frame
        // Nothing moved and the card is up: leave it alone, the same shortcut a
        // still step takes, so a still window is a still card.
        if container == lastWindowFrame, cardPanel?.isVisible == true { return }
        lastWindowFrame = container
        let view = AnyView(TutorialFinishCardView(
            finish: finish,
            onChoose: { [weak self] in self?.choose($0) },
            onClose: { [weak self] in self?.dismissFinish() }))
        let size = CGSize(width: TutorialCalloutView.width, height: measuredHeight(of: view))
        let frame = CGRect(x: container.midX - size.width / 2,
                           y: container.midY - size.height / 2,
                           width: size.width, height: size.height)
        show(view, at: frame, in: window)
    }

    private func placeCentred(in container: CGRect, window: NSWindow) {
        guard let run else { return }
        let size = CGSize(width: TutorialCalloutView.width, height: measuredCardHeight(run))
        let frame = CGRect(x: container.midX - size.width / 2,
                           y: container.midY - size.height / 2,
                           width: size.width, height: size.height)
        show(view(for: run, side: .above, beakOffset: nil), at: frame, in: window)
    }

    private func view(for run: TutorialRun, side: TutorialSide,
                      beakOffset: CGFloat?, note: String? = nil) -> TutorialCalloutView {
        TutorialCalloutView(
            number: run.number, count: run.count,
            title: run.step.title, message: run.step.body, note: note,
            buttonTitle: run.buttonTitle, canGoBack: run.canGoBack,
            side: side, beakOffset: beakOffset,
            onBack: { [weak self] in self?.back() },
            onNext: { [weak self] in self?.next() },
            onClose: { [weak self] in self?.close() })
    }

    /// The card's height at its fixed width. Measured with no beak, so the
    /// number is the plate alone and the beak is added on the side it points
    /// from.
    private func measuredCardHeight(_ run: TutorialRun, note: String? = nil) -> CGFloat {
        let probe = NSHostingView(rootView: view(for: run, side: .above, beakOffset: nil,
                                                 note: note))
        probe.frame.size.width = TutorialCalloutView.width
        let fitted = probe.fittingSize.height
        return max(80, fitted - TutorialCalloutView.beakHeight)
    }

    /// The same measurement for a card that has no beak to take back out.
    private func measuredHeight(of view: AnyView) -> CGFloat {
        let probe = NSHostingView(rootView: view)
        probe.frame.size.width = TutorialCalloutView.width
        return max(80, probe.fittingSize.height)
    }

    private func show(_ view: TutorialCalloutView, at frame: CGRect, in window: NSWindow) {
        show(AnyView(view), at: frame, in: window)
    }

    private func show(_ view: AnyView, at frame: CGRect, in window: NSWindow) {
        let panel = cardPanel ?? makePanel(ignoresMouse: false)
        cardPanel = panel
        if let host = cardHost {
            host.rootView = view
        } else {
            let host = NSHostingView(rootView: view)
            panel.contentView = host
            cardHost = host
        }
        panel.setFrame(frame, display: true)
        attach(panel, to: window)
    }

    /// The ring on the control, in the control's OWN shape.
    ///
    /// The shape is re-applied on every placement rather than only when the
    /// panel is built. The ring used to be made once and never touched again,
    /// which was invisible while every ring was the same rounded rectangle and
    /// would have left a step that moved from the tool bar to a panel section
    /// still wearing the pill it was born with.
    private func placeCue(anchor: CGRect, shape: TutorialCueShape, window: NSWindow) {
        let panel = cuePanel ?? makePanel(ignoresMouse: true)
        cuePanel = panel
        let view = TutorialCueView(shape: shape)
        if let host = cueHost {
            host.rootView = view
        } else {
            let host = NSHostingView(rootView: view)
            panel.contentView = host
            cueHost = host
        }
        let room = TutorialCueView.padding + TutorialCueView.pulseRoom
        panel.setFrame(anchor.insetBy(dx: -room, dy: -room), display: true)
        attach(panel, to: window)
    }

    private func attach(_ panel: NSPanel, to window: NSWindow) {
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        if !panel.isVisible { panel.orderFront(nil) }
    }

    private func makePanel(ignoresMouse: Bool) -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = ignoresMouse
        panel.animationBehavior = .none
        panel.collectionBehavior = [.fullScreenAuxiliary, .transient]
        // Never takes key away from the window you are working in: the whole
        // point is that you keep driving the real app.
        panel.becomesKeyOnlyIfNeeded = true
        return panel
    }

    /// A guide never outlives the window it is teaching.
    private func watchForClose(_ window: NSWindow) {
        guard closeObserver == nil else { return }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    // MARK: - Forgetting

    /// Forget one guide: its finished mark and its saved place both go, so it
    /// reads as something never run. A guide running right now is closed first,
    /// or it would write its place straight back on the next step.
    func forgetProgress(_ guideID: String) {
        if run?.guide.id == guideID { stop(remembering: false) }
        progress.forget(guideID)
        saveProgress()
    }

    /// Forget the lot. What the Tutorials window's Reset All does.
    func forgetAllProgress() {
        stop(remembering: false)
        progress.forgetAll()
        saveProgress()
    }

    // MARK: - Remembering

    private func saveProgress() {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        UserDefaults.standard.set(data, forKey: Self.progressKey)
    }

    private static func loadProgress() -> TutorialProgress {
        guard let data = UserDefaults.standard.data(forKey: progressKey),
              let saved = try? JSONDecoder().decode(TutorialProgress.self, from: data)
        else { return TutorialProgress() }
        return saved
    }
}
