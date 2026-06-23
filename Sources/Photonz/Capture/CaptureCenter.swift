import AppKit
import Carbon.HIToolbox
import Observation
import PhotonzCore

/// Coordinates the screenshot feature: global hotkeys, capture modes, and the
/// history panel's visibility.
///
/// ⌘⇧4 → rectangle grab, ⌘⇧3 → full-screen capture, ⌘⇧H → history panel.
/// These fire system-wide once the user disables macOS's own Screenshots
/// shortcuts (System Settings → Keyboard → Keyboard Shortcuts → Screenshots);
/// until then the system swallows ⌘⇧3/⌘⇧4 before any app can see them.
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
    /// the coordinator. `onToggleHistory` is ⌘⇧H; `onRequestHistory` ensures the
    /// overlay is shown (e.g. to surface the permission hint).
    @ObservationIgnored var onToggleHistory: (() -> Void)?
    @ObservationIgnored var onRequestHistory: (() -> Void)?

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
        // Dedicated stop shortcut for recording — ⌘⇧5 collides with macOS's own
        // screenshot toolbar, so ⌃⇧F5 reliably stops a recording in progress.
        hotkeys.register(.controlShift(kVK_F5)) { [weak self] in self?.stopRecordingIfNeeded() }
        hotkeys.register(.commandShift(kVK_ANSI_H)) { [weak self] in self?.onToggleHistory?() }
    }

    // MARK: - Recording (phase 12)

    /// ⌘⇧5 / menu: stop if recording, otherwise open the setup card.
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
        guard !recording.isRecording else { return }
        guard ensurePermission() else { return }
        recordingSetup.present(
            initial: recording.config,
            microphones: ScreenRecorder.availableMicrophones()
        ) { [weak self] config in
            self?.startRecording(with: config)
        }
    }

    private func startRecording(with config: RecordingConfig) {
        if case .region = config.source {
            // Drag a region first, then record exactly that rect on its screen.
            guard rectSelection == nil else { return }
            rectSelection = RectSelectionController(
                onComplete: { [weak self] screen, rect in
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
                for image in try await ScreenCapturer.captureAllScreens() {
                    if let entry = store.add(image) { onCaptureComplete?(entry) }
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
            onComplete: { [weak self] screen, rect in
                self?.rectSelection = nil
                self?.captureRect(screen: screen, rect: rect)
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
        NSApp.activate(ignoringOtherApps: true)
        Task {
            await ScreenCapturer.primePermissionRegistration()
            ScreenCapturer.openScreenRecordingSettings()
            needsScreenRecordingPermission = !ScreenCapturer.hasPermission
        }
    }

    // MARK: - Internals

    private func captureRect(screen: NSScreen, rect: CGRect) {
        Task {
            // One runloop hop so the dismissed overlay is gone from the
            // window server before we sample the screen.
            try? await Task.sleep(for: .milliseconds(60))
            do {
                if let entry = store.add(try await ScreenCapturer.capture(screen: screen, sourceRect: rect)) {
                    onCaptureComplete?(entry)
                }
            } catch {
                NSLog("Rect capture failed: \(error)")
            }
        }
    }

    private func ensurePermission() -> Bool {
        if ScreenCapturer.hasPermission {
            needsScreenRecordingPermission = false
            return true
        }
        needsScreenRecordingPermission = true
        onRequestHistory?() // the overlay hosts the permission hint
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
