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
@MainActor
final class WelcomeController: NSObject, NSWindowDelegate {
    static let completedDefaultsKey = "welcome.setupCompleted"

    private var panel: NSPanel?
    private var poll: Timer?
    private var state: WelcomeState?
    private weak var capture: CaptureCenter?
    /// Screen Recording granted mid-session only takes effect after a relaunch,
    /// so remember what the process started with (the controller is created
    /// during `AppCoordinator.init`, i.e. at launch).
    private let hadScreenPermissionAtLaunch = ScreenCapturer.hasPermission

    /// Launch hook: present only while setup is unfinished.
    func presentIfNeeded(capture: CaptureCenter) {
        guard !UserDefaults.standard.bool(forKey: Self.completedDefaultsKey) else { return }
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
        let state = WelcomeState(screenGrantedAtLaunch: hadScreenPermissionAtLaunch)
        self.state = state

        let view = WelcomeView(
            state: state,
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
        // Reflect the possibly-changed status in the capture UI's hint.
        capture?.needsScreenRecordingPermission = !ScreenCapturer.hasPermission
        state = nil
        panel = nil
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

    private let screenGrantedAtLaunch: Bool
    /// Keep the shortcuts card visible (as a green success row) once the user
    /// has seen it, instead of vanishing mid-glance when they fix it.
    let hadShortcutConflictsAtOpen: Bool

    init(screenGrantedAtLaunch: Bool) {
        self.screenGrantedAtLaunch = screenGrantedAtLaunch
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
    /// screenshot shortcuts still swallow.
    private static func currentShortcutConflicts() -> [SystemScreenshotShortcuts.Shortcut] {
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
