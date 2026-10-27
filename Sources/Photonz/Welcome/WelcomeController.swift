import AppKit
import AVFoundation
import Observation
import PhotonzCore
import SwiftUI

/// First-run setup: a friendly window that walks through the one-time macOS
/// settings Photonz needs — Screen Recording (required), Microphone (optional,
/// for narrated recordings), and freeing ⇧⌘3/⇧⌘4/⇧⌘5 (plus ⇧⌘6 on a Touch Bar
/// Mac) from the system's own screenshot shortcuts. Presented at launch until finished; reachable any
/// time from the menu-bar menu and the history overlay's permission hint.
///
/// "Finished" means the window was closed with Screen Recording granted (or
/// the user clicked the primary button in that state). Where the release takes
/// no for an answer (`next-setup-takes-no-for-an-answer`), closing it earlier
/// is remembered too and the window stops opening itself: capture then explains
/// itself at the moment somebody tries it, which is where the explanation is
/// worth something. Without that flag, closing it earlier re-presents it on the
/// next launch for ever.
///
/// This window also carries the one and only offer of the guided tour (`FirstRunOffer`, PhotonzCore, where the rules and their traps
/// are written down). It lives here rather than in a second welcome surface
/// because this window already owns first launch, and a new person should be
/// asked once, by one thing.
@MainActor
final class WelcomeController: NSObject, NSWindowDelegate {
    static let completedDefaultsKey = "welcome.setupCompleted"
    /// Set the first time the setup window is closed at all, granted or not.
    /// It is what makes a no stick: `completedDefaultsKey` only ever records
    /// the screen being switched ON, so before this existed there was no
    /// dismissal the app would remember (`FirstRunOffer`). Written and read
    /// only where the release takes no for an answer.
    static let dismissedDefaultsKey = "welcome.setupDismissed"
    /// The one remembered answer to "shall I show you around": `tour`, `skip`,
    /// or absent for somebody who has never been asked.
    static let firstRunOfferKey = "tutorials.firstRunOffer"
    /// Set the first time a build that knows about tutorials launches. Its only
    /// job is to make the migration below happen exactly once: run every
    /// launch, it would stamp the new person as answered the moment they
    /// restart for the Screen Recording grant, and eat the offer they were owed.
    static let firstRunMigratedKey = "tutorials.firstRunOffer.migrated"
    /// The setup steps this person has seen, one name each (`SetupFlow`).
    /// Stored per step so a step added later shows once and nothing else
    /// comes back.
    static let stepsSeenKey = "setup.stepsSeen"
    /// Set the first time a build that shows setup as steps launches, so the
    /// old one page setup is read into `stepsSeenKey` exactly once.
    static let stepsMigratedKey = "setup.stepsMigrated"

    private var panel: NSPanel?
    private var poll: Timer?
    private var state: WelcomeState?
    private weak var capture: CaptureCenter?
    /// Screen Recording granted mid-session only takes effect after a relaunch,
    /// so remember what the process started with (the controller is created
    /// during `AppCoordinator.init`, i.e. at launch).
    private let hadScreenPermissionAtLaunch = ScreenCapturer.hasPermission

    /// Starts the guided tour, set by `AppCoordinator`. The tour opens a
    /// window of its own holding a sample picture, so it never begins on an
    /// empty canvas with nothing to point at.
    var startTour: (() -> Void)?

    /// What was answered during THIS presentation, so closing the window does
    /// not overwrite a button that was just pressed.
    private var answeredThisRun: FirstRunAnswer?

    /// Launch hook: present while setup is unfinished, or once more when setup
    /// is done but nobody has ever been offered the tour.
    func presentIfNeeded(capture: CaptureCenter) {
        Self.migrateFirstRunOfferOnce()
        if Self.stepped {
            Self.migrateStepsOnce()
            Task { @MainActor in
                // Give the menu-bar agent a beat to settle before taking focus.
                try? await Task.sleep(for: .milliseconds(600))
                let agents = await WelcomeState.readAgentStatuses()
                let facts = WelcomeState.facts(agents: agents)
                let steps = SetupFlow.steps(facts: facts, seen: Self.stepsSeen)
                let tourPending = Experiments.shared.tutorialsEnabled && Self.firstRunAnswer == nil
                guard SetupFlow.presentsAtLaunch(steps: steps, tourPending: tourPending) else { return }
                self.open(capture: capture,
                          run: SetupRun(pages: steps, endsWithTour: tourPending), agents: agents)
            }
            return
        }
        let defaults = UserDefaults.standard
        guard FirstRunOffer.presentsAtLaunch(
            setupCompleted: defaults.bool(forKey: Self.completedDefaultsKey),
            setupDismissed: Self.takesNoForAnAnswer
                && defaults.bool(forKey: Self.dismissedDefaultsKey),
            answer: Self.firstRunAnswer,
            tutorialsEnabled: Experiments.shared.tutorialsEnabled) else { return }
        // Give the menu-bar agent a beat to settle before taking focus.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            self.present(capture: capture)
        }
    }

    /// Menu re-entry ("Welcome & Permissions…"): always presents. As steps,
    /// it shows what is still needed whatever was seen, or every step as done
    /// when nothing is, and never the tour offer.
    func present(capture: CaptureCenter) {
        if let panel {
            AppFront.activate()
            AppFront.present(panel)
            return
        }
        guard Self.stepped else {
            open(capture: capture, run: nil, agents: [:])
            return
        }
        Task { @MainActor in
            let agents = await WelcomeState.readAgentStatuses()
            let steps = SetupFlow.reopenedSteps(
                facts: WelcomeState.facts(agents: agents),
                agentToolOnThisMac: agents.values.contains { $0.state != .notFound })
            self.open(capture: capture,
                      run: SetupRun(pages: steps, endsWithTour: false, passesOverDone: false),
                      agents: agents)
        }
    }

    /// Puts the window up: the stepped setup when `run` is given, the one
    /// page window otherwise.
    private func open(capture: CaptureCenter, run: SetupRun?,
                      agents: [AgentSetup.Tool: AgentInstaller.Status]) {
        if let panel {
            AppFront.activate()
            AppFront.present(panel)
            return
        }
        self.capture = capture
        answeredThisRun = nil
        let state = WelcomeState(screenGrantedAtLaunch: hadScreenPermissionAtLaunch,
                                 tourAlreadyAnswered: Self.firstRunAnswer != nil)
        state.run = run
        state.agentStatuses = agents
        self.state = state
        // Seen the moment it is on screen: quitting with it up does not bring
        // it back (`SetupRun.shown`).
        if let run { Self.recordSeen(run.shown) }

        let onGrantScreenRecording: () -> Void = { [weak self] in
            self?.state?.noteScreenRecordingGrantAttempt()
            self?.capture?.requestScreenRecordingAccess()
        }
        let rootView: AnyView
        if run != nil {
            rootView = AnyView(SetupStepsView(
                state: state,
                onTakeTour: { [weak self] in self?.takeTheTour() },
                onGrantScreenRecording: onGrantScreenRecording,
                onGrantMicrophone: { [weak self] in self?.grantMicrophone() },
                onOpenKeyboardSettings: { Self.openKeyboardSettings() },
                onRelaunch: { [weak self] in self?.relaunch() },
                onMoveOn: { [weak self] in self?.moveOn() },
                onFinish: { [weak self] in self?.panel?.close() }))
        } else {
            rootView = AnyView(WelcomeView(
                state: state,
                onTakeTour: { [weak self] in self?.takeTheTour() },
                onGrantScreenRecording: onGrantScreenRecording,
                onGrantMicrophone: { [weak self] in self?.grantMicrophone() },
                onOpenKeyboardSettings: { Self.openKeyboardSettings() },
                onRelaunch: { [weak self] in self?.relaunch() },
                onFinish: { [weak self] in self?.panel?.close() }))
        }

        let panel = WelcomeKeyPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 480, height: 560)),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        // Named so anything that finds a window by its name can find this one.
        // Nothing draws it: the title bar text is hidden.
        panel.title = FirstRunOffer.windowTitle
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        // Floating panels hide when the app deactivates BY DEFAULT — which made
        // this window vanish the instant the microphone TCC prompt (a separate
        // process) took focus, stranding the user mid-walkthrough.
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let hosting = FirstClickHostingView(rootView: rootView)
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        panel.center()
        AppFront.activate()
        AppFront.present(panel)
        self.panel = panel

        // Register with TCC right away (we're frontmost) so the Screen
        // Recording pane already lists Photonz when the user opens it —
        // they should never have to add the bundle by hand.
        capture.registerScreenRecordingClient()

        // Live status: flip rows to green the moment the user grants access in
        // System Settings, without them having to come back and click anything.
        poll = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.state?.refresh() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        poll?.invalidate()
        poll = nil
        // Closing is a no to every step in this run, except the close that is
        // a restart, which leaves the steps after it for the other side
        // (`SetupRun.seenOnClose`).
        if let run = state?.run {
            Self.recordSeen(run.seenOnClose(needsRelaunch: state?.needsRelaunch ?? false))
        }
        // Setup counts as done once the required permission is in place; until
        // then, keep offering the walkthrough at launch.
        if state?.screenRecordingGranted == true {
            UserDefaults.standard.set(true, forKey: Self.completedDefaultsKey)
        }
        // Closing the window is also an answer to the SETUP, and the answer is
        // no. Before this, the only dismissal the app remembered was one that
        // granted the screen, so somebody who came to draw got this window at
        // every launch for ever. The one close that means nothing is the one
        // carrying a pending restart: that close IS the restart.
        if FirstRunOffer.dismissalEndsFirstRun(
            takesNoForAnAnswer: Self.takesNoForAnAnswer,
            needsRelaunch: state?.needsRelaunch ?? false) {
            UserDefaults.standard.set(true, forKey: Self.dismissedDefaultsKey)
        }
        // Closing the window while the question is up IS an answer, and the
        // answer is skip. Without this, somebody who reaches for the red button
        // instead of either offered button gets asked again on every launch.
        // `tourOfferPending` is the same value `showsTourChoice` passes as
        // tutorialsEnabled. It also carries "nobody has answered yet", which is
        // harmless here because the answer below is checked anyway, and which
        // keeps the two rules reading off one thing.
        if let recorded = FirstRunOffer.answerOnDismiss(
            tutorialsEnabled: state?.tourOfferPending ?? false,
            screenRecordingGranted: state?.screenRecordingGranted ?? false,
            needsRelaunch: state?.needsRelaunch ?? false,
            answer: answeredThisRun ?? Self.firstRunAnswer) {
            Self.recordFirstRunAnswer(recorded)
        }
        // Reflect the possibly-changed status in the capture UI's hint.
        capture?.needsScreenRecordingPermission = !ScreenCapturer.hasPermission
        state = nil
        panel = nil
    }

    /// "Take the Tour": remember it, get this window out of the way, and only
    /// then start the guide.
    ///
    /// The order matters. This is a floating panel that sits above every editor
    /// window, so a guide started underneath it would be putting a ring round
    /// controls hidden behind it, which is the one thing a walkthrough cannot
    /// survive. Same rule the Tutorials window follows.
    private func takeTheTour() {
        answeredThisRun = .tour
        Self.recordFirstRunAnswer(.tour)
        panel?.close()
        DispatchQueue.main.async { [weak self] in self?.startTour?() }
    }

    /// Skip or Continue: the page is seen from this moment, so a restart
    /// halfway through does not show it again, and the next page comes up.
    private func moveOn() {
        guard let state, var run = state.run else { return }
        run.advance(facts: state.facts)
        Self.recordSeen(run.shown)
        state.run = run
        if run.isFinished { panel?.close() }
    }

    // MARK: - The steps seen

    /// Whether this release shows setup as steps (`next-setup-steps`).
    static var stepped: Bool { Experiments.shared.setupStepsEnabled }

    static var stepsSeen: Set<SetupStep> {
        SetupFlow.decode(UserDefaults.standard.stringArray(forKey: stepsSeenKey) ?? [])
    }

    private static func recordSeen(_ seen: Set<SetupStep>) {
        let all = stepsSeen.union(seen)
        UserDefaults.standard.set(SetupFlow.encode(all), forKey: stepsSeenKey)
    }

    /// An install that finished (or waved away) the one page setup has seen
    /// its permission steps. Once ever: see `SetupFlow` for why not every
    /// launch.
    private static func migrateStepsOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: stepsMigratedKey) else { return }
        let seen = SetupFlow.migratedSeen(
            seen: stepsSeen,
            setupCompleted: defaults.bool(forKey: completedDefaultsKey),
            setupDismissed: defaults.bool(forKey: dismissedDefaultsKey))
        defaults.set(SetupFlow.encode(seen), forKey: stepsSeenKey)
        defaults.set(true, forKey: stepsMigratedKey)
    }

    // MARK: - The remembered answer

    /// Whether this release remembers a no to the setup window
    /// (`next-setup-takes-no-for-an-answer`). Read in one place so the write
    /// and the read can never disagree.
    static var takesNoForAnAnswer: Bool { Experiments.shared.setupTakesNoForAnAnswer }

    static var firstRunAnswer: FirstRunAnswer? {
        UserDefaults.standard.string(forKey: firstRunOfferKey)
            .flatMap(FirstRunAnswer.init(rawValue:))
    }

    private static func recordFirstRunAnswer(_ answer: FirstRunAnswer) {
        UserDefaults.standard.set(answer.rawValue, forKey: firstRunOfferKey)
    }

    /// An install that finished its setup before any of this existed has had
    /// its first run, so it is marked answered and never sees this window
    /// again. Once ever, whatever the tutorials flag says: the fact being
    /// recorded is about the install, not about the release it is running.
    private static func migrateFirstRunOfferOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: firstRunMigratedKey) else { return }
        if let stamp = FirstRunOffer.migratedAnswer(
            setupCompleted: defaults.bool(forKey: completedDefaultsKey),
            answer: firstRunAnswer) {
            recordFirstRunAnswer(stamp)
        }
        defaults.set(true, forKey: firstRunMigratedKey)
    }

    /// Microphone is the one permission macOS lets us request entirely in-app.
    private func grantMicrophone() {
        // A TCC request without a usage description kills the process — bare
        // `swift build` dev runs have no Info.plist, so fall back to Settings.
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
            Self.openMicrophoneSettings()
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            // Photonz is an accessory app, so without activating first the
            // system prompt appears behind whatever is frontmost — easy to
            // never see, and until it's answered macOS doesn't list Photonz in
            // the Microphone settings pane at all.
            AppFront.activate()
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor [weak self] in self?.state?.refresh() }
            }
        case .denied, .restricted:
            Self.openMicrophoneSettings()
        default:
            state?.refresh()
        }
    }

    /// A Screen Recording grant only takes effect in a fresh process. macOS
    /// usually offers "Quit & Reopen" itself; this covers users who chose
    /// "Later" there so they aren't left with a granted-but-broken capture.
    private func relaunch() {
        AppRelauncher.relaunch()
    }

    private static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The setup window's buttons answer the first click even while the window
/// is not key: somebody coming back from System Settings clicks Continue once,
/// not once to bring the window forward and again to press it.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class WelcomeKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Live permission/setup statuses backing `WelcomeView`; refreshed by the
/// controller's poll timer while the window is up.
@MainActor
@Observable
final class WelcomeState {
    private(set) var screenRecordingGranted: Bool
    private(set) var microphone: AVAuthorizationStatus
    private(set) var conflictingShortcuts: [SystemScreenshotShortcuts.Shortcut]
    /// Granted during this process's lifetime — capture won't actually work
    /// until Photonz relaunches, so surface a relaunch affordance.
    private(set) var needsRelaunch = false

    /// The user tried granting and it hasn't stuck. The usual cause is a TCC
    /// grant recorded for a differently-signed build of Photonz at the same
    /// path — Settings shows the toggle ON, but macOS ignores it and re-prompts.
    /// The card escalates to remove-and-re-add guidance in that state.
    private(set) var screenRecordingGrantAttempted = false

    /// Whether this presentation is the one that carries the tour offer: the
    /// tutorials are switched on and nobody has ever answered. Fixed when the
    /// window opens, because the answer can only change by being given here.
    let tourOfferPending: Bool

    /// Whether closing this window is a remembered no. It changes what the
    /// window SAYS as well as what it does: a step badged Required and a way
    /// out labelled "Not Now" are both false in a window you can leave for good
    /// (`FirstRunOffer`).
    let takesNoForAnAnswer: Bool

    /// Whether the two ways on are showing right now. It waits for a pending
    /// restart and nothing else, because a tour the restart kills is worse than
    /// no tour, while a tour on a machine that never granted Screen Recording
    /// works perfectly well (`FirstRunOffer`).
    var showsTourChoice: Bool {
        FirstRunOffer.showsChoice(tutorialsEnabled: tourOfferPending,
                                  needsRelaunch: needsRelaunch,
                                  answer: nil)
    }

    private let screenGrantedAtLaunch: Bool
    /// Keep the shortcuts card visible (as a green success row) once the user
    /// has seen it, instead of vanishing mid-glance when they fix it.
    let hadShortcutConflictsAtOpen: Bool

    init(screenGrantedAtLaunch: Bool, tourAlreadyAnswered: Bool = true) {
        self.screenGrantedAtLaunch = screenGrantedAtLaunch
        tourOfferPending = Experiments.shared.tutorialsEnabled && !tourAlreadyAnswered
        takesNoForAnAnswer = WelcomeController.takesNoForAnAnswer
        screenRecordingGranted = ScreenCapturer.hasPermission
        microphone = Self.microphoneStatus()
        let conflicts = Self.setupShortcutConflicts()
        conflictingShortcuts = conflicts
        hadShortcutConflictsAtOpen = !conflicts.isEmpty
        needsRelaunch = screenRecordingGranted && !screenGrantedAtLaunch
    }

    // MARK: The steps (`next-setup-steps`)

    /// This showing's pages and where the person is; nil for the one page window.
    var run: SetupRun?
    /// Claude Code and Copilot as this Mac has them, for the agents step.
    var agentStatuses: [AgentSetup.Tool: AgentInstaller.Status] = [:]
    /// The tool an Install is running for.
    var agentBusy: AgentSetup.Tool?
    /// What went wrong installing, in a plain sentence, per tool.
    var agentTrouble: [AgentSetup.Tool: String] = [:]

    /// What this Mac has sorted right now, for passing over a step that got
    /// done while an earlier one was on show.
    var facts: SetupFacts {
        SetupFacts(screenRecordingGranted: screenRecordingGranted,
                   microphoneAnswered: microphone != .notDetermined,
                   screenshotKeysFree: conflictingShortcuts.isEmpty,
                   agentsToSetUp: Self.agentsToSetUp(agentStatuses))
    }

    /// Whether the step on show has nothing left to do.
    func isDone(_ step: SetupStep) -> Bool {
        switch step {
        case .screenRecording: screenRecordingGranted && !needsRelaunch
        case .microphone: microphone == .authorized
        case .screenshotKeys: conflictingShortcuts.isEmpty
        // Done once any tool has Photonz: Continue takes over from Skip, and
        // the other tool's Install stays there to press.
        case .agents: agentStatuses.values.contains { $0.state == .installed }
            || (!agentStatuses.isEmpty && !Self.agentsToSetUp(agentStatuses))
        }
    }

    /// The tools on this Mac, in the order the step lists them.
    var agentToolsHere: [AgentSetup.Tool] {
        AgentSetup.Tool.allCases.filter { (agentStatuses[$0]?.state ?? .notFound) != .notFound }
    }

    /// Install (or update) Photonz in one tool, the same install Settings >
    /// Agents runs, off the main thread.
    func installAgent(_ tool: AgentSetup.Tool) {
        agentBusy = tool
        agentTrouble[tool] = nil
        let installer = AgentInstaller.forThisApp
        Task {
            let failure: String? = await Task.detached {
                do {
                    try installer.install(tool)
                    return nil
                } catch let trouble as AgentInstaller.Trouble {
                    return trouble.words
                } catch {
                    return "Could not finish. \(error.localizedDescription)"
                }
            }.value
            agentTrouble[tool] = failure
            agentStatuses = await Self.readAgentStatuses()
            agentBusy = nil
        }
    }

    /// A tool here that Photonz is not set up in, in a release that lets
    /// agents in at all.
    static func agentsToSetUp(_ statuses: [AgentSetup.Tool: AgentInstaller.Status]) -> Bool {
        #if PHOTONZ_PLAYTEST
        if let pretended = PlaytestSetupPretend.agentsToSetUp { return pretended }
        #endif
        guard Experiments.shared.agentChannelEnabled else { return false }
        return statuses.values.contains { $0.state == .notInstalled }
    }

    /// Both tools' rows, read off the main thread (files, and looking for the
    /// tools themselves). Empty where the release does not let agents in.
    static func readAgentStatuses() async -> [AgentSetup.Tool: AgentInstaller.Status] {
        guard Experiments.shared.agentChannelEnabled else { return [:] }
        let installer = AgentInstaller.forThisApp
        return await Task.detached {
            Dictionary(uniqueKeysWithValues: AgentSetup.Tool.allCases.map { ($0, installer.status($0)) })
        }.value
    }

    /// The facts read fresh, for deciding at launch which steps show.
    static func facts(agents: [AgentSetup.Tool: AgentInstaller.Status]) -> SetupFacts {
        SetupFacts(screenRecordingGranted: ScreenCapturer.hasPermission,
                   microphoneAnswered: microphoneStatus() != .notDetermined,
                   screenshotKeysFree: setupShortcutConflicts().isEmpty,
                   agentsToSetUp: agentsToSetUp(agents))
    }

    static func microphoneStatus() -> AVAuthorizationStatus {
        #if PHOTONZ_PLAYTEST
        if let pretended = PlaytestSetupPretend.microphoneAnswered {
            return pretended ? .authorized : .notDetermined
        }
        #endif
        return AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// `currentShortcutConflicts`, as the setup window reads it.
    static func setupShortcutConflicts() -> [SystemScreenshotShortcuts.Shortcut] {
        #if PHOTONZ_PLAYTEST
        if let pretended = PlaytestSetupPretend.screenshotKeysFree {
            return pretended ? [] : [.fullScreen, .region]
        }
        #endif
        return currentShortcutConflicts()
    }

    var everythingReady: Bool {
        screenRecordingGranted && !needsRelaunch && conflictingShortcuts.isEmpty
    }

    func noteScreenRecordingGrantAttempt() {
        screenRecordingGrantAttempted = true
    }

    func refresh() {
        screenRecordingGranted = ScreenCapturer.hasPermission
        microphone = Self.microphoneStatus()
        conflictingShortcuts = Self.setupShortcutConflicts()
        needsRelaunch = screenRecordingGranted && !screenGrantedAtLaunch
    }

    /// Which of ⇧⌘3/⇧⌘4/⇧⌘5 (and ⇧⌘6 on a Touch Bar Mac) macOS's own
    /// screenshot shortcuts still swallow. Also read by the capture toast, so
    /// it only names ⇧⌘6 when Photonz actually receives it.
    static func currentShortcutConflicts() -> [SystemScreenshotShortcuts.Shortcut] {
        let value = CFPreferencesCopyValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let hotkeys = value as? [String: Any]
        let touchBar = SystemScreenshotShortcuts.hasTouchBar(
            modelIdentifier: modelIdentifier, hotkeys: hotkeys)
        return SystemScreenshotShortcuts.conflicting(in: hotkeys, touchBar: touchBar)
    }

    /// `hw.model`, e.g. "MacBookPro17,1"; empty if the kernel will not say.
    private static let modelIdentifier: String = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }()
}

#if PHOTONZ_PLAYTEST
/// What a walk has told the setup window to read the microphone, the
/// screenshot keys and the agents step as, or nil to read the real thing. The
/// same idea as `ScreenCapturer.playtestPretendedPermission`: nothing about
/// macOS or the tools is touched, and it exists so a walk can stand on a brand
/// new Mac and on one with everything done. Probe builds only.
@MainActor
enum PlaytestSetupPretend {
    static var microphoneAnswered: Bool?
    static var screenshotKeysFree: Bool?
    static var agentsToSetUp: Bool?

    static func forget() {
        microphoneAnswered = nil
        screenshotKeysFree = nil
        agentsToSetUp = nil
    }
}
#endif
