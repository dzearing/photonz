import AppKit
import ScreenCaptureKit

/// One-shot screen captures via ScreenCaptureKit.
/// Requires the Screen Recording permission (TCC); callers check/request first.
@MainActor
enum ScreenCapturer {

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Triggers the system permission prompt (no-op if already decided).
    /// Returns whether access is currently granted.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// Gets Photonz listed under System Settings → Privacy & Security → Screen &
    /// System Audio Recording and surfaces the prompt. `CGRequestScreenCaptureAccess`
    /// alone covers the legacy path; modern macOS only lists a ScreenCaptureKit
    /// client once it actually issues an SCK query, so we do both. The SCK call
    /// throws when undetermined/denied — that's expected; the side effect
    /// (registration + prompt) is the point.
    static func primePermissionRegistration() async {
        _ = CGRequestScreenCaptureAccess()
        // Issuing an SCK query is what registers a ScreenCaptureKit client in
        // System Settings → Screen & System Audio Recording. It throws until
        // access is granted — expected; the registration is the point.
        _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// Opens the Screen Recording pane in System Settings so the user can grant
    /// access (and see Photonz listed) without hunting through the panes.
    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Captures one screen. `sourceRect` is in the screen's own coordinate
    /// space, points, top-left origin (i.e. exactly what a flipped overlay
    /// view covering the screen reports); nil captures the whole screen.
    ///
    /// Uses the WYSIWYG `captureImage(in:)` API, NOT the
    /// `captureImage(contentFilter:configuration:)` one: the filter-based call
    /// re-composites windows from their individual buffers and synthesizes no
    /// window shadows at all (verified 2026-07-03 against `screencapture`:
    /// filter path Δ0 luma under every window edge, WYSIWYG path matches the
    /// system exactly), so frozen modals/windows looked pasted-on. The WYSIWYG
    /// call includes shadows, omits the cursor, and returns native backing scale.
    static func capture(screen: NSScreen, sourceRect: CGRect? = nil) async throws -> CGImage {
        let local = sourceRect ?? CGRect(origin: .zero, size: screen.frame.size)
        return try await SCScreenshotManager.captureImage(in: cgGlobalRect(for: local, on: screen))
    }

    /// Converts a screen-local, top-left-origin points rect to the CG global
    /// (primary-display top-left origin, y-down) space `captureImage(in:)` expects.
    private static func cgGlobalRect(for local: CGRect, on screen: NSScreen) -> CGRect {
        // NSScreen frames are global Cocoa coords (primary bottom-left origin,
        // y-up); screens[0] is always the primary. X is shared between spaces.
        let primaryMaxY = NSScreen.screens[0].frame.maxY
        return CGRect(x: screen.frame.minX + local.minX,
                      y: (primaryMaxY - screen.frame.maxY) + local.minY,
                      width: local.width,
                      height: local.height)
    }

    /// Captures one window on its own, the way the built-in window capture
    /// does: rendered by the window server from the window's own buffer, so
    /// the rounded corners are transparent and nothing in front of or behind
    /// the window is in the shot. With the shadow, the image is larger than
    /// the window and the margin around it is transparent. The window is
    /// captured whole even where it hangs off the display. Throws when the
    /// window is no longer on screen or the capture fails; the caller falls
    /// back to the frozen crop.
    static func captureWindow(id: Int, includeShadow: Bool) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { Int($0.windowID) == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCScreenshotConfiguration()
        config.showsCursor = false
        config.ignoreShadows = !includeShadow
        config.ignoreClipping = true
        config.dynamicRange = .sdr
        let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: config)
        guard let image = output.sdrImage else { throw CocoaError(.fileReadCorruptFile) }
        return image
    }

    /// Captures every attached screen (system ⇧⌘3 behavior: one image per display).
    static func captureAllScreens() async throws -> [CGImage] {
        var images: [CGImage] = []
        for screen in NSScreen.screens {
            images.append(try await capture(screen: screen))
        }
        return images
    }
}
