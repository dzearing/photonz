import AppKit

/// Mirrors the system "Double-click a window's title bar to" preference for
/// surfaces that hide the real title bar (the canvas surround, the video
/// preview's empty areas): double-clicking them should zoom/minimize the
/// window exactly like a real title bar would.
@MainActor
enum WindowTitleBarAction {
    static func perform(on window: NSWindow?) {
        guard let window else { return }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize":
            window.performMiniaturize(nil)
        case "None":
            break
        default: // "Maximize" (Zoom) is the modern default.
            window.performZoom(nil)
        }
    }
}
