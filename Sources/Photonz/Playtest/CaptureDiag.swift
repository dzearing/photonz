#if PHOTONZ_PLAYTEST
import AppKit

/// Probe-only check of the region capture overlay (`--capture-diag`). The
/// overlay covers every display and owns the pointer, so a playtest walk cannot
/// reach it; this drives it directly instead and answers the three things that
/// decide whether it behaves:
///
/// 1. How long from "start a capture" to the screen being dim.
/// 2. When each display's frozen picture lands underneath.
/// 3. Whether that picture is the true screen or a photograph of our own dim.
///    A dim screen reads 0.75 of a clean one; a doubly dimmed one reads 0.56.
///
/// It leaves a real screenshot of a drag in flight, which is the only way to
/// photograph the overlay.
///
/// A locked screen makes every one of those readings meaningless: no client can
/// see past the lock, so each capture comes back as the desktop picture and the
/// overlay is nowhere in it. The run says so on its first line; when it does,
/// throw the numbers away and run it again once somebody is logged in.
@MainActor
enum CaptureDiag {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--capture-diag") else { return }
        Task { await run() }
    }

    private static var out: [String] = []
    private static func say(_ line: String) {
        out.append(line)
        NSLog("[capture-diag] \(line)")
    }

    private static func run() async {
        guard let screen = NSScreen.main else { return }
        let locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?[
            "CGSSessionScreenIsLocked"] as? Int == 1
        say("screen recording granted: \(ScreenCapturer.hasPermission), "
            + (locked ? "SCREEN LOCKED: every reading below is of the lock screen, discard them"
               : "screen unlocked"))
        let clean = await luma(of: screen)
        say(String(format: "clean screen: mean luma %.4f", clean))

        var selection: RectSelectionController?
        selection = RectSelectionController(
            windowPicking: true,
            onComplete: { _, _, _ in selection = nil },
            onCancel: { selection = nil })

        let t0 = Date()
        selection?.begin()
        say(String(format: "shortcut to dim (overlay on every display): %.1f ms",
                   Date().timeIntervalSince(t0) * 1000))

        // Wait for the freeze to land and the overlay to stop hiding from
        // captures, then read the screen back.
        try? await Task.sleep(for: .milliseconds(600))
        let dimmed = await luma(of: screen)
        say(String(format: "overlay up: mean luma %.4f, %.3f of clean (0.75 = one dim, 0.56 = the "
                   + "freeze photographed our own dim)", dimmed, dimmed / max(clean, 0.0001)))

        // A drag, photographed for real: the box, its size pill, and nothing
        // else beside the pointer.
        selection?.simulateDrag(from: CGPoint(x: 320, y: 260), to: CGPoint(x: 900, y: 620))
        try? await Task.sleep(for: .milliseconds(250))
        if let shot = try? await ScreenCapturer.capture(screen: screen) {
            write(shot, to: "/tmp/photonz-capture-diag-drag.png")
            say("drag screenshot: /tmp/photonz-capture-diag-drag.png")
        } else {
            say("drag screenshot FAILED")
        }

        selection?.dismiss()
        selection = nil
        try? await Task.sleep(for: .milliseconds(200))
        let after = await luma(of: screen)
        say(String(format: "overlay gone: mean luma %.4f, %.3f of clean", after,
                   after / max(clean, 0.0001)))

        try? out.joined(separator: "\n").write(toFile: "/tmp/photonz-capture-diag.txt",
                                               atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    /// Mean luminance of a screen, freshly captured.
    private static func luma(of screen: NSScreen) async -> Double {
        guard let image = try? await ScreenCapturer.capture(screen: screen),
              let data = image.dataProvider?.data as Data? else { return -1 }
        let bpr = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8
        var total = 0.0
        var count = 0.0
        for y in stride(from: 0, to: image.height, by: 8) {
            for x in stride(from: 0, to: image.width, by: 8) {
                let i = y * bpr + x * bpp
                guard i + 2 < data.count else { continue }
                total += (Double(data[i]) + Double(data[i + 1]) + Double(data[i + 2])) / 765.0
                count += 1
            }
        }
        return count > 0 ? total / count : -1
    }

    private static func write(_ image: CGImage, to path: String) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
#endif
