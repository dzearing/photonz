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

    /// What they have finished, and where they stopped in anything they left
    /// part way. Written on every step, so quitting mid guide loses nothing.
    private(set) var progress: TutorialProgress

    @ObservationIgnored private weak var editor: EditorState?
    @ObservationIgnored private var cardPanel: NSPanel?
    @ObservationIgnored private var cuePanel: NSPanel?
    @ObservationIgnored private var cardHost: NSHostingView<TutorialCalloutView>?
    @ObservationIgnored private var follow: Timer?
    @ObservationIgnored private var lastAnchorFrame: CGRect?
    @ObservationIgnored private var lastWindowFrame: CGRect?
    /// The step the panels are currently DRAWING. Compared before anything is
    /// skipped as unchanged: without it, moving from a step whose control is on
    /// screen to one whose control is not left the previous step's callout up,
    /// unchanged and wrong, because "no anchor" and "no anchor yet" look the
    /// same from here.
    @ObservationIgnored private var drawnStepID: String?
    /// Passes left to keep asking for the step's target to be scrolled into
    /// view. Counted down in `place`, so the ask survives the section arriving
    /// a beat late.
    @ObservationIgnored private var revealTries = 0
    @ObservationIgnored private var closeObserver: NSObjectProtocol?
    /// Steps whose anchor never turned up, for the log and the audit.
    @ObservationIgnored private(set) var unresolvedSteps: [String] = []
    /// The window each guide last ran in, so picking the same tutorial again
    /// comes back to the window already holding its sample.
    @ObservationIgnored private var editorsByGuide: [String: WeakEditor] = [:]

    private final class WeakEditor {
        weak var value: EditorState?
        init(_ value: EditorState) { self.value = value }
    }

    private static let progressKey = "tutorials.progress"
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

    /// The guide running right now, for a menu that wants to say so.
    var runningGuideID: String? { run?.guide.id }

    /// The guide's own panels while they float over `window`, so an offscreen
    /// render of that window can include them. Same hook the tooltip offers,
    /// for the same reason.
    func panels(over window: NSWindow?) -> [NSPanel] {
        guard let window, run != nil else { return [] }
        return [cuePanel, cardPanel].compactMap { $0 }
            .filter { $0.isVisible && $0.parent === window }
    }

    /// What a guide is doing, in one line, for a walk's log: the step, where
    /// its anchor resolved to, and where the card ended up. "none" when no
    /// guide is running. This is what lets a walk FAIL on a callout pointing at
    /// nothing instead of a person noticing it in a picture later.
    func liveDescription(in window: NSWindow?) -> String {
        guard let run else { return "none" }
        let anchor = run.step.anchor
        let where_ = TutorialAnchorRegistry.shared.screenFrame(of: anchor, in: window)
            .map { "(\(Int($0.minX)), \(Int($0.minY))) \(Int($0.width))x\(Int($0.height))" }
            ?? "NOT ON SCREEN"
        return "\(run.guide.id)/\(run.step.id) \(run.number) of \(run.count); "
            + "\(anchor.name) at \(where_); card \(cardPanel.map { "\(Int($0.frame.minX)), \(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "none")"
    }

    /// The editor a guide last ran in, while that window is still around.
    func lastEditor(forGuide id: String) -> EditorState? { editorsByGuide[id]?.value }

    // MARK: - Starting and stopping

    /// Runs `guide` over `editor`. Picks up where the person left off if they
    /// stopped part way through this one before.
    func start(_ guide: TutorialGuide, in editor: EditorState) {
        stop(remembering: true)
        self.editor = editor
        unresolvedSteps = []
        editorsByGuide[guide.id] = WeakEditor(editor)
        run = TutorialRun(guide: guide, startingAt: progress.startIndex(for: guide))
        beginStep()
        startFollowing()
    }

    /// Starts the guide over again from the top, forgetting where you were.
    func restart(_ guide: TutorialGuide, in editor: EditorState) {
        progress.restart(guide.id)
        saveProgress()
        start(guide, in: editor)
    }

    /// Closes the guide. Keeps your place unless the guide finished.
    func close() {
        stop(remembering: true)
    }

    private func finish() {
        if let guide = run?.guide {
            progress.complete(guide.id)
            saveProgress()
        }
        stop(remembering: false)
    }

    private func stop(remembering: Bool) {
        if remembering, let run {
            progress.record(guide: run.guide.id, step: run.index)
            saveProgress()
        }
        run = nil
        editor = nil
        lastAnchorFrame = nil
        lastWindowFrame = nil
        drawnStepID = nil
        follow?.invalidate()
        follow = nil
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        tearDown(&cardPanel)
        tearDown(&cuePanel)
        cardHost = nil
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
    func note(_ trigger: TutorialTrigger, from editor: EditorState) {
        guard let run, self.editor === editor, run.isSatisfied(by: trigger) else { return }
        // Let the editor finish the change that produced the event before the
        // callout jumps to a new control.
        DispatchQueue.main.async { [weak self] in
            guard let self, let current = self.run, current.isSatisfied(by: trigger) else { return }
            self.next()
        }
    }

    /// Applies the step's prepare actions and puts the callout up. Prepare may
    /// only REVEAL: showing the panel so a step can point at the Layers list is
    /// fine, picking the tool for a step that says "pick the tool" is the timer
    /// lie in another costume, which is why the list is closed.
    private func beginStep() {
        guard let run, let editor else { return }
        progress.record(guide: run.guide.id, step: run.index)
        saveProgress()
        for prep in run.step.prepare {
            switch prep {
            case .showPanel: if !editor.isInspectorShown { editor.setInspectorVisible(true) }
            case .showLibrary: if !editor.isLibraryVisible { editor.setLibraryVisible(true) }
            case .revealTarget:
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
        DispatchQueue.main.async { [weak self] in self?.place() }
    }

    // MARK: - Following the control

    private func startFollowing() {
        follow?.invalidate()
        let timer = Timer(timeInterval: Self.followInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        RunLoop.main.add(timer, forMode: .common)
        follow = timer
    }

    private var hostWindow: NSWindow? { editor?.hostWindow }

    private func place() {
        guard let run, let window = hostWindow else { return }
        watchForClose(window)
        guard !window.isMiniaturized, window.occlusionState.contains(.visible) else {
            cardPanel?.orderOut(nil)
            cuePanel?.orderOut(nil)
            return
        }
        if revealTries > 0 {
            revealTries -= 1
            if run.step.prepare.contains(.revealTarget) {
                TutorialAnchorRegistry.shared.reveal(run.step.anchor, in: window)
            }
        }
        let anchor = TutorialAnchorRegistry.shared.screenFrame(of: run.step.anchor, in: window)
        // On screen: stop asking, so a person who scrolls somewhere else is not
        // fought by a guide that got what it wanted a moment ago.
        if anchor != nil { revealTries = 0 }
        let container = window.frame
        // Nothing moved: do not touch the panels, so a still window is a still
        // callout rather than a frame being reset thirty times a second.
        if anchor == lastAnchorFrame, container == lastWindowFrame,
           drawnStepID == run.step.id, cardPanel?.isVisible == true { return }
        lastAnchorFrame = anchor
        lastWindowFrame = container
        drawnStepID = run.step.id

        guard let anchor else {
            // The control is not on screen. Nobody gets stranded: the card goes
            // to the middle of the window with no beak and no ring, and the way
            // on still works. A test is what should have caught this, and a
            // live walk is what catches the rest (queue task: a renamed control
            // breaks the build).
            noteUnresolved(run.step)
            placeCentred(in: container, window: window)
            cuePanel?.orderOut(nil)
            return
        }
        placeCallout(anchor: anchor, container: container, window: window, run: run)
        placeCue(anchor: anchor, window: window)
    }

    private func noteUnresolved(_ step: TutorialStep) {
        let name = "\(run?.guide.id ?? "?")/\(step.id) -> \(step.anchor.name)"
        guard !unresolvedSteps.contains(name) else { return }
        unresolvedSteps.append(name)
    }

    private func placeCallout(anchor: CGRect, container: CGRect, window: NSWindow,
                              run: TutorialRun) {
        let flippedAnchor = TutorialGeometry.flip(anchor, in: container)
        let flippedContainer = TutorialGeometry.flip(container, in: container)
        let cardSize = CGSize(width: TutorialCalloutView.width, height: measuredCardHeight(run))
        let placed = TutorialCalloutLayout.place(anchor: flippedAnchor, size: cardSize,
                                                 container: flippedContainer,
                                                 preferred: run.step.side)
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
        show(view(for: run, side: placed.side, beakOffset: placed.beakOffset),
             at: TutorialGeometry.flip(frame, in: container), in: window)
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
                      beakOffset: CGFloat?) -> TutorialCalloutView {
        TutorialCalloutView(
            number: run.number, count: run.count,
            title: run.step.title, message: run.step.body,
            buttonTitle: run.buttonTitle, canGoBack: run.canGoBack,
            side: side, beakOffset: beakOffset,
            onBack: { [weak self] in self?.back() },
            onNext: { [weak self] in self?.next() },
            onClose: { [weak self] in self?.close() })
    }

    /// The card's height at its fixed width. Measured with no beak, so the
    /// number is the plate alone and the beak is added on the side it points
    /// from.
    private func measuredCardHeight(_ run: TutorialRun) -> CGFloat {
        let probe = NSHostingView(rootView: view(for: run, side: .above, beakOffset: nil))
        probe.frame.size.width = TutorialCalloutView.width
        let fitted = probe.fittingSize.height
        return max(80, fitted - TutorialCalloutView.beakHeight)
    }

    private func show(_ view: TutorialCalloutView, at frame: CGRect, in window: NSWindow) {
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

    private func placeCue(anchor: CGRect, window: NSWindow) {
        let panel = cuePanel ?? makePanel(ignoresMouse: true)
        if cuePanel == nil {
            panel.contentView = NSHostingView(rootView: TutorialCueView(cornerRadius: 10))
            cuePanel = panel
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
