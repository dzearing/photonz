import AppKit
import Carbon.HIToolbox
import Observation

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
    var isHistoryVisible = false
    /// Set when a capture attempt is blocked on the Screen Recording permission.
    var needsScreenRecordingPermission = false

    @ObservationIgnored private let hotkeys = HotkeyCenter()
    @ObservationIgnored private var rectSelection: RectSelectionController?

    /// Called once at app launch.
    func start() {
        store.loadFromDisk()
        hotkeys.register(.commandShift(kVK_ANSI_3)) { [weak self] in self?.captureFullScreen() }
        hotkeys.register(.commandShift(kVK_ANSI_4)) { [weak self] in self?.beginRectCapture() }
        hotkeys.register(.commandShift(kVK_ANSI_H)) { [weak self] in self?.revealHistory() }
    }

    // MARK: - Modes

    func captureFullScreen() {
        guard ensurePermission() else { return }
        Task {
            do {
                for image in try await ScreenCapturer.captureAllScreens() {
                    store.add(image)
                }
                flashHistoryIfActive()
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

    func toggleHistory() {
        isHistoryVisible.toggle()
    }

    /// Global-hotkey path: surface the app, then show the panel.
    private func revealHistory() {
        if NSApp.isActive {
            toggleHistory()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            isHistoryVisible = true
        }
    }

    // MARK: - Internals

    private func captureRect(screen: NSScreen, rect: CGRect) {
        Task {
            // One runloop hop so the dismissed overlay is gone from the
            // window server before we sample the screen.
            try? await Task.sleep(for: .milliseconds(60))
            do {
                store.add(try await ScreenCapturer.capture(screen: screen, sourceRect: rect))
                flashHistoryIfActive()
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
        isHistoryVisible = true // the panel hosts the permission hint
        ScreenCapturer.requestPermission()
        return false
    }

    private func flashHistoryIfActive() {
        if NSApp.isActive { isHistoryVisible = true }
    }
}
