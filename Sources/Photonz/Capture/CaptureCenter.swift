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
    /// Set when a capture attempt is blocked on the Screen Recording permission.
    var needsScreenRecordingPermission = false

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

    /// Called once at app launch.
    func start() {
        store.loadFromDisk()
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
        hotkeys.register(.commandShift(kVK_ANSI_H)) { [weak self] in self?.onToggleHistory?() }
    }

    // MARK: - Modes

    func captureFullScreen() {
        guard ensurePermission() else { return }
        Task {
            do {
                for image in try await ScreenCapturer.captureAllScreens() {
                    onCaptureComplete?(store.add(image))
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
                onCaptureComplete?(store.add(try await ScreenCapturer.capture(screen: screen, sourceRect: rect)))
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
