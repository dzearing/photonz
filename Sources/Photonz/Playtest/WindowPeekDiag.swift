#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzRender
import ScreenCaptureKit

/// Probe-only photograph of ANY on-screen window by its number
/// (`--window-peek <owner name>`), written to `/tmp/photonz-window-peek-<n>.png`.
///
/// It exists for one job: reading a system dialog nobody can see. On
/// 2026-11-26 a macOS permission dialog sat behind the person's terminal while
/// the loop ran, and the shell that had to find out what it asked holds no
/// Screen Recording or Accessibility grant of its own, so the window list could
/// say a `universalAccessAuthWarn` window was up but not what it said. The probe
/// already holds the grant, so it photographs the window on its own (never the
/// screen around it: a desktop-independent filter) and quits. It raises no
/// window, takes no key and asks macOS for nothing: without the grant it writes
/// a line saying so and stops.
@MainActor
enum WindowPeekDiag {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let at = args.firstIndex(of: "--window-peek"), at + 1 < args.count else { return }
        let owner = args[at + 1]
        Task { await run(owner: owner) }
    }

    private static func run(owner: String) async {
        var lines: [String] = []
        defer {
            try? lines.joined(separator: "\n").write(toFile: "/tmp/photonz-window-peek.txt",
                                                     atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
        // Preflight only: this diagnostic must never be the thing that asks.
        guard CGPreflightScreenCaptureAccess() else {
            lines.append("no Screen Recording grant; nothing photographed")
            return
        }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
            lines.append("shareable content refused")
            return
        }
        let windows = content.windows.filter { $0.owningApplication?.applicationName == owner
            || $0.owningApplication?.bundleIdentifier.hasSuffix(owner) == true }
        if windows.isEmpty { lines.append("no window owned by \(owner)") }
        for window in windows {
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * 2)
            config.height = Int(window.frame.height * 2)
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let path = "/tmp/photonz-window-peek-\(window.windowID).png"
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
               let data = ImageCodec.encode(image, format: .png) {
                try? data.write(to: URL(fileURLWithPath: path))
                lines.append("\(window.windowID) \(window.title ?? "") \(Int(window.frame.width))x\(Int(window.frame.height)) onScreen=\(window.isOnScreen) -> \(path)")
            } else {
                lines.append("\(window.windowID) could not be photographed")
            }
        }
    }
}
#endif
