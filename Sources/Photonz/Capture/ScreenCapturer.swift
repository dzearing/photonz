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

    enum CaptureError: Error {
        case displayNotFound
    }

    /// Captures one screen. `sourceRect` is in the screen's own coordinate
    /// space, points, top-left origin (i.e. exactly what a flipped overlay
    /// view covering the screen reports); nil captures the whole screen.
    static func capture(screen: NSScreen, sourceRect: CGRect? = nil) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        guard let screenNumber,
              let display = content.displays.first(where: { $0.displayID == screenNumber.uint32Value })
        else { throw CaptureError.displayNotFound }

        let rect = sourceRect ?? CGRect(x: 0, y: 0, width: display.width, height: display.height)
        let scale = screen.backingScaleFactor

        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = Int(rect.width * scale)
        config.height = Int(rect.height * scale)
        config.showsCursor = false
        config.captureResolution = .best

        let filter = SCContentFilter(display: display, excludingWindows: [])
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Captures every attached screen (system ⌘⇧3 behavior: one image per display).
    static func captureAllScreens() async throws -> [CGImage] {
        var images: [CGImage] = []
        for screen in NSScreen.screens {
            images.append(try await capture(screen: screen))
        }
        return images
    }
}
