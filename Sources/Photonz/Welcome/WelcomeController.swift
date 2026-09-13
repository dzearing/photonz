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
/// the user clicked the primary button in that state). Closing it earlier
/// re-presents it on the next launch — that unfinished state is exactly the
/// scary first-capture failure this flow exists to prevent.
///
/// Once setup works, this window also carries the one and only offer of the
/// guided tour (`FirstRunOffer`, PhotonzCore, where the rules and their traps
/// are written down). It lives here rather than in a second welcome surface
/// because this window already owns first launch, and a new person should be
/// asked once, by one thing.
@MainActor
final class WelcomeController: NSObject, NSWindowDelegate {
    static let completedDefaultsKey = "welcome.setupCompleted"
    /// The one remembered answer to "shall I show you around": `tour`, `skip`,
    /// or absent for somebody who has never been asked.
    static let firstRunOfferKey = "tutorials.firstRunOffer"
    /// Set the first time a build that knows about tutorials launches. Its only
    /// job is to make the migration below happen exactly once: run every
    /// launch, it would stamp the new person as answered the moment they
    /// restart for the Screen Recording grant, and eat the offer they were owed.
    static let firstRunMigratedKey = "tutorials.firstRunOffer.migrated"

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
        guard FirstRunOffer.presentsAtLaunch(
            setupCompleted: UserDefaults.standard.bool(forKey: Self.completedDefaultsKey),
            answer: Self.firstRunAnswer,
            tutorialsEnabled: Experiments.shared.tutorialsEnabled) else { return }
        // Give the menu-bar agent a beat to settle before taking focus.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            self.present(capture: capture)
        }
    }

    /// Menu re-entry ("Welcome & Permissions…"): always presents.
    func present(capture: CaptureCenter) {
        if let panel {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        self.capture = capture
        answeredThisRun = nil
        let state = WelcomeState(screenGrantedAtLaunch: hadScreenPermissionAtLaunch,
                                 tourAlreadyAnswered: Self.firstRunAnswer != nil)
        self.state = state

        let view = WelcomeView(
            state: state,
            onTakeTour: { [weak self] in self?.takeTheTour() },
            onGrantScreenRecording: { [weak self] in
                self?.state?.noteScreenRecordingGrantAttempt()
                self?.capture?.requestScreenRecordingAccess()
            },
            onGrantMicrophone: { [weak self] in self?.grantMicrophone() },
            onOpenKeyboardSettings: { Self.openKeyboardSettings() },
            onRelaunch: { [weak self] in self?.relaunch() },
            onFinish: { [weak self] in self?.panel?.close() })

        let panel = WelcomeKeyPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 480, height: 560)),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        // Named so anything that finds a window by its name can find this one.
        // Nothing draws it: the title bar text is hidden.
        panel.title = FirstRunOffer.windowTitle
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        // Floating panels hide when the app deactivates BY DEFAULT — which made
        // this window vanish the instant the microphone TCC prompt (a separate
        // process) took focus, stranding the user mid-walkthrough.
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
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
        // Setup counts as done once the required permission is in place; until
        // then, keep offering the walkthrough at launch.
        if state?.screenRecordingGranted == true {
            UserDefaults.standard.set(true, forKey: Self.completedDefaultsKey)
        }
        // Closing the window while everything works IS an answer, and the
        // answer is skip. Without this, somebody who reaches for the red button
        // instead of either offered button gets asked again on every launch.
        if let recorded = FirstRunOffer.answerOnDismiss(
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

    // MARK: - The remembered answer

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
            NSApp.activate(ignoringOtherApps: true)
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

    /// Whether the two ways on are showing right now. It waits for Screen
    /// Recording and for any pending restart, because a tour the restart kills
    /// is worse than no tour (`FirstRunOffer`).
    var showsTourChoice: Bool {
        FirstRunOffer.showsChoice(tutorialsEnabled: tourOfferPending,
                                  screenRecordingGranted: screenRecordingGranted,
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
        screenRecordingGranted = ScreenCapturer.hasPermission
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        let conflicts = Self.currentShortcutConflicts()
        conflictingShortcuts = conflicts
        hadShortcutConflictsAtOpen = !conflicts.isEmpty
        needsRelaunch = screenRecordingGranted && !screenGrantedAtLaunch
    }

    var everythingReady: Bool {
        screenRecordingGranted && !needsRelaunch && conflictingShortcuts.isEmpty
    }

    func noteScreenRecordingGrantAttempt() {
        screenRecordingGrantAttempted = true
    }

    func refresh() {
        screenRecordingGranted = ScreenCapturer.hasPermission
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        conflictingShortcuts = Self.currentShortcutConflicts()
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
