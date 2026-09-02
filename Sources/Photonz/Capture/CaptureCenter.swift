import AppKit
import AVFoundation
import Carbon.HIToolbox
import Observation
import PhotonzCore

/// Coordinates the screenshot feature: global hotkeys, capture modes, and the
/// history panel's visibility.
///
/// ⇧⌘4 → rectangle grab, ⇧⌘3 → full-screen capture, ⇧⌘H → history panel.
/// These fire system-wide once the user disables macOS's own Screenshots
/// shortcuts (System Settings → Keyboard → Keyboard Shortcuts → Screenshots);
/// until then the system swallows ⇧⌘3/⇧⌘4 before any app can see them.
@MainActor
@Observable
final class CaptureCenter {
    let store = CaptureStore()
    /// Screen recording (phase 12): pipeline + stop HUD + history filing.
    let recording: RecordingCoordinator
    /// Set when a capture attempt is blocked on the Screen Recording permission.
    var needsScreenRecordingPermission = false

    /// True while a recording is in progress (menu label / state).
    var isRecording: Bool { recording.isRecording }

    /// History presentation now lives in the resident agent's global slide-down
    /// overlay (phase 11.4), not an in-editor panel — so capture just signals
    /// the coordinator. `onToggleHistory` is ⇧⌘H; `onRequestHistory` ensures the
    /// overlay is shown (e.g. to surface the permission hint).
    @ObservationIgnored var onToggleHistory: (() -> Void)?
    @ObservationIgnored var onRequestHistory: (() -> Void)?

    /// ⇧⌘6: open the newest capture in an editor. The toast is the only fast
    /// path from capture to editor and it fades, so this is the keyboard one.
    @ObservationIgnored var onEditLastCapture: (() -> Void)?

    /// Fired after a capture lands in the store, so the resident agent can pop
    /// the post-capture Quick Access Overlay (phase 11.7). Carries the new entry.
    @ObservationIgnored var onCaptureComplete: ((CaptureEntry) -> Void)?

    @ObservationIgnored private let hotkeys = HotkeyCenter()
    @ObservationIgnored private var rectSelection: RectSelectionController?
    @ObservationIgnored private let recordingSetup = RecordingSetupController()

    init() {
        recording = RecordingCoordinator(store: store)
    }

    /// Called once at app launch.
    func start() {
        store.start()
        // Recordings pop the same post-capture Quick Access Overlay screenshots do.
        recording.onRecordingComplete = { [weak self] entry in self?.onCaptureComplete?(entry) }
        // Register with TCC up front so Photonz shows up in System Settings →
        // Privacy & Security → Screen Recording before the first capture. The
        // system only lists an app once it asks; preflight alone never adds it.
        // No-op (and no prompt) once a decision has been made.
        // Only reflect the current status in the UI here — do NOT request at
        // launch. A screen-recording request made while the app is in the
        // background can be auto-declined (and the decision sticks), so we ask
        // only in response to a user-initiated capture (see ensurePermission).
        needsScreenRecordingPermission = !ScreenCapturer.hasPermission
        hotkeys.register(.commandShift(kVK_ANSI_3)) { [weak self] in self?.captureFullScreen() }
        hotkeys.register(.commandShift(kVK_ANSI_4)) { [weak self] in self?.beginRectCapture() }
        hotkeys.register(.commandShift(kVK_ANSI_5)) { [weak self] in self?.toggleRecording() }
        // Dedicated stop shortcut for recording — ⇧⌘5 collides with macOS's own
        // screenshot toolbar, so ⌃⇧F5 reliably stops a recording in progress.
        hotkeys.register(.controlShift(kVK_F5)) { [weak self] in self?.stopRecordingIfNeeded() }
        hotkeys.register(.commandShift(kVK_ANSI_H)) { [weak self] in self?.onToggleHistory?() }
        // ⇧⌘6 continues the 3/4/5 family. Global hotkeys pre-empt the app's own
        // key equivalents, so it must not reuse anything the editor binds.
        hotkeys.register(.commandShift(kVK_ANSI_6)) { [weak self] in self?.onEditLastCapture?() }
    }

    // MARK: - Recording (phase 12)

    /// ⇧⌘5 / menu: stop if recording, otherwise open the setup card.
    func toggleRecording() {
        if recording.isRecording {
            Task { await recording.stop() }
        } else {
            beginRecordingFlow()
        }
    }

    /// ⌃⇧F5: stop a recording in progress (no-op otherwise).
    func stopRecordingIfNeeded() {
        guard recording.isRecording else { return }
        Task { await recording.stop() }
    }

    /// Presents the recording setup card, then starts on the chosen source.
    func beginRecordingFlow() {
        guard !recording.isRecording, !recording.isStarting else { return }
        guard ensurePermission() else { return }
        recordingSetup.present(
            initial: recording.config,
            microphones: ScreenRecorder.availableMicrophones()
        ) { [weak self] config in
            self?.startRecording(with: config)
        }
    }

    /// Resolve microphone access BEFORE any stream exists. If SCStream is left
    /// to trip the TCC prompt inside `startCapture`, the start either blocks
    /// until the prompt is answered (stop HUD frozen at 0:00) or fails
    /// instantly and silently when access is denied and the prompt suppressed:
    /// the HUD vanished in under a second and the recording just never
    /// happened. That silent flash was reported as "recording with the
    /// microphone crashes".
    private func startRecording(with config: RecordingConfig) {
        Task { await resolveMicrophoneAccessThenStart(config) }
    }

    private func resolveMicrophoneAccessThenStart(_ config: RecordingConfig) async {
        switch MicrophonePermissionGate.decision(wantsMicrophone: config.audio.capturesMicrophone,
                                                 authorization: Self.microphoneAuthorization()) {
        case .proceed:
            launchRecording(with: config)
        case .requestAccess:
            // Accessory app: without activating first, the mic prompt can land
            // behind the frontmost app and never be seen (same reason the
            // welcome flow activates). This OS prompt only exists while the
            // status is notDetermined, so it inherently fires at most once.
            NSApp.activate(ignoringOtherApps: true)
            if await AVCaptureDevice.requestAccess(for: .audio) {
                launchRecording(with: config)
            } else {
                presentMicrophoneBlocked(for: config)
            }
        case .blocked:
            presentMicrophoneBlocked(for: config)
        }
    }

    /// Maps AVFoundation's status into the pure gate's terms. A bundle without
    /// the mic usage description (bare `swift build` runs) counts as denied:
    /// requesting access there would get the process killed by TCC.
    private static func microphoneAuthorization() -> MicrophoneAuthorization {
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
            return .denied
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Blocked mic is surfaced, never swallowed: offer to record without the
    /// microphone, jump to Settings, or bail. User-initiated each time, so this
    /// is feedback, not a prompt loop.
    private func presentMicrophoneBlocked(for config: RecordingConfig) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Microphone access is turned off"
        alert.informativeText = "macOS is blocking Photonz from using the microphone, so the recording can't include it. You can record without the microphone, or turn it on in System Settings and try again."
        alert.addButton(withTitle: "Record Without Microphone")
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            launchRecording(with: config.withoutMicrophone)
        case .alertSecondButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    private func launchRecording(with config: RecordingConfig) {
        if case .region = config.source {
            // Drag a region first, then record exactly that rect on its screen.
            guard rectSelection == nil else { return }
            rectSelection = RectSelectionController(
                windowPicking: Experiments.shared.windowCaptureEnabled,
                windowShadow: Experiments.shared.windowCaptureIncludesShadow,
                producesImage: false,
                loupe: Experiments.shared.captureLoupeEnabled ? Experiments.shared.captureLoupePixels : nil,
                onComplete: { [weak self] screen, rect, _ in
                    // Recording wants the LIVE region, not the frozen crop — the
                    // frozen overlay is gone by the time the stream starts.
                    self?.rectSelection = nil
                    var regionConfig = config
                    regionConfig.source = .region(rect)
                    Task { await self?.recording.start(config: regionConfig, screen: screen) }
                },
                onCancel: { [weak self] in self?.rectSelection = nil })
            rectSelection?.begin()
        } else {
            Task { await recording.start(config: config, screen: activeScreen()) }
        }
    }

    private func activeScreen() -> NSScreen {
        if let screen = NSApp.keyWindow?.screen { return screen }
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) { return screen }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: - Modes

    func captureFullScreen() {
        guard ensurePermission() else { return }
        Task {
            do {
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                for image in try await ScreenCapturer.captureAllScreens() {
                    if let entry = store.add(image, scale: scale) { onCaptureComplete?(entry) }
                }
            } catch {
                NSLog("Full-screen capture failed: \(error)")
            }
        }
    }

    func beginRectCapture() {
        guard ensurePermission() else { return }
        guard rectSelection == nil else { return }
        rectSelection = RectSelectionController(
            windowPicking: Experiments.shared.windowCaptureEnabled,
            windowShadow: Experiments.shared.windowCaptureIncludesShadow,
            loupe: Experiments.shared.captureLoupeEnabled ? Experiments.shared.captureLoupePixels : nil,
            onComplete: { [weak self] screen, rect, frozenCrop in
                guard let self else { return }
                self.rectSelection = nil
                // Freeze-frame path: the selection was dragged over a frozen
                // screenshot and the crop comes straight out of that bitmap —
                // exactly what the user saw. Live re-capture only as fallback.
                if let frozenCrop {
                    if let entry = self.store.add(frozenCrop, scale: screen.backingScaleFactor) {
                        self.onCaptureComplete?(entry)
                    }
                } else {
                    self.captureRect(screen: screen, rect: rect)
                }
            },
            onCancel: { [weak self] in self?.rectSelection = nil }
        )
        rectSelection?.begin()
    }

    /// Explicit, user-invoked "register me with TCC" — fires the Screen
    /// Recording request UNCONDITIONALLY (not gated on the preflight check,
    /// which can report a stale value when the system TCC record is stuck) and
    /// opens the Settings pane. This is what gets Photonz listed so the toggle
    /// can be flipped. Must run frontmost.
    func requestScreenRecordingAccess() {
        promptedScreenRecordingThisLaunch = true
        NSApp.activate(ignoringOtherApps: true)
        Task {
            await ScreenCapturer.primePermissionRegistration()
            ScreenCapturer.openScreenRecordingSettings()
            needsScreenRecordingPermission = !ScreenCapturer.hasPermission
        }
    }

    /// Registration only — no Settings pane. Fired when the welcome window
    /// presents (the app is frontmost then), so Photonz is already listed in
    /// the Screen Recording pane by the time the user gets there; they should
    /// never have to hunt for the bundle with the + button. Shares the
    /// once-per-launch gate with `ensurePermission`.
    func registerScreenRecordingClient() {
        guard !ScreenCapturer.hasPermission, !promptedScreenRecordingThisLaunch else { return }
        promptedScreenRecordingThisLaunch = true
        Task { await ScreenCapturer.primePermissionRegistration() }
    }

    // MARK: - Internals

    private func captureRect(screen: NSScreen, rect: CGRect) {
        Task {
            // One runloop hop so the dismissed overlay is gone from the
            // window server before we sample the screen.
            try? await Task.sleep(for: .milliseconds(60))
            do {
                let shot = try await ScreenCapturer.capture(screen: screen, sourceRect: rect)
                if let entry = store.add(shot, scale: screen.backingScaleFactor) {
                    onCaptureComplete?(entry)
                }
            } catch {
                NSLog("Rect capture failed: \(error)")
            }
        }
    }

    /// TCC prompts must never storm. Each `primePermissionRegistration` call
    /// can put TWO system dialogs on screen (CGRequest via WindowServer, the
    /// SCK query via replayd) — and when the stored grant no longer matches the
    /// app's code signature (e.g. a rebuilt bundle at the same path), macOS
    /// re-prompts on EVERY attempt even though Settings shows Photonz enabled.
    /// Re-requesting can never fix that state, so we ask once per launch and
    /// after that only surface the in-app hint (verified live 2026-07-07: a
    /// stale "Photonz Dev"-pinned grant + the release-signed build produced an
    /// endless prompt loop).
    private var promptedScreenRecordingThisLaunch = false

    private func ensurePermission() -> Bool {
        if ScreenCapturer.hasPermission {
            needsScreenRecordingPermission = false
            return true
        }
        needsScreenRecordingPermission = true
        onRequestHistory?() // the overlay hosts the permission hint
        guard !promptedScreenRecordingThisLaunch else { return false }
        promptedScreenRecordingThisLaunch = true
        // User-initiated and frontmost: issue the real request that registers
        // Photonz as a ScreenCaptureKit client (CGRequest + an SCK query), then
        // open the Screen Recording pane so they can grant it.
        Task {
            await ScreenCapturer.primePermissionRegistration()
            ScreenCapturer.openScreenRecordingSettings()
        }
        return false
    }
}
