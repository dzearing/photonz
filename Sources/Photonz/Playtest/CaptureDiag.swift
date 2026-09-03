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

        // How long one screenshot of this display takes, measured on a warm
        // client. Every reading below is quantised by this number, so it is
        // printed rather than assumed.
        let tShot = Date()
        _ = try? await ScreenCapturer.capture(screen: screen)
        let shotMS = Date().timeIntervalSince(tShot) * 1000
        say(String(format: "one screen capture costs: %.0f ms (the resolution of every "
                   + "reading below)", shotMS))

        // The freeze changed capture APIs to leave our own panels out, so check
        // the new one returns the same picture as the old: same pixel size (the
        // crop maths rides on it) and the same content when nothing of ours is
        // on screen to exclude.
        if let plain = try? await ScreenCapturer.capture(screen: screen),
           let filtered = try? await ScreenCapturer.capture(screen: screen,
                                                            excludingWindowNumbers: []) {
            say("freeze capture vs plain capture: \(filtered.width)x\(filtered.height) against "
                + "\(plain.width)x\(plain.height), "
                + (filtered.width == plain.width && filtered.height == plain.height
                   ? "same size" : "SIZE MISMATCH, crops would land in the wrong place"))
            say(String(format: "  mean luma %.4f against %.4f", luma(of: filtered), luma(of: plain)))
        } else {
            say("freeze capture vs plain capture: could not take both shots")
        }

        var selection: RectSelectionController?
        selection = RectSelectionController(
            windowPicking: true,
            onComplete: { _, _, _ in selection = nil },
            onCancel: { selection = nil })

        let t0 = Date()
        selection?.begin()
        say(String(format: "shortcut to dim (overlay on every display): %.1f ms",
                   Date().timeIntervalSince(t0) * 1000))

        // Poll rather than sleep a fixed span: the question is WHEN another
        // capture tool starts seeing the dim, and a single reading at an
        // arbitrary moment cannot tell "it never does" from "it does, later" —
        // which is how a 600 ms sleep once reported a working dim as broken.
        //
        // Two readings, interleaved, because they fail independently. The
        // window server's own sharing state for the overlay says whether
        // another tool is ALLOWED to see it; the pixels say whether one
        // actually would. On a locked screen only the first means anything.
        let overlays = Set(selection?.overlayWindowNumbers ?? [])
        var dimmed = -1.0
        var ratio = 1.0
        var polls = 0
        var sawDimAfter: Double?
        var sharedAfter: Double?
        while Date().timeIntervalSince(t0) < 3.0 {
            if sharedAfter == nil, sharingState(of: overlays).allSatisfy({ $0 != 0 }) {
                sharedAfter = Date().timeIntervalSince(t0) * 1000
            }
            dimmed = await luma(of: screen)
            polls += 1
            ratio = dimmed / max(clean, 0.0001)
            if ratio < 0.9 {
                sawDimAfter = Date().timeIntervalSince(t0) * 1000
                break
            }
            if sharedAfter != nil && sawDimAfter != nil { break }
        }
        if let sharedAfter {
            say(String(format: "overlay becomes visible to other capture tools after %.0f ms "
                       + "(window server sharing state)", sharedAfter))
        } else {
            say("overlay STAYS hidden from other capture tools: the window server still has it "
                + "at sharing state 0 after 3 s")
        }
        if let sawDimAfter {
            say(String(format: "dim shows up in another tool's screenshot after %.0f ms (%d "
                       + "polls): mean luma %.4f, %.3f of clean (0.75 = one dim, 0.56 = the "
                       + "freeze photographed our own dim)", sawDimAfter, polls, dimmed, ratio))
        } else {
            say(String(format: "dim NEVER shows up in another tool's screenshot: still %.3f of "
                       + "clean after 3 s and %d polls", ratio, polls))
        }
        if let landed = selection?.freezeFinished {
            let frozen = selection?.frozenCount ?? (landed: 0, displays: 0)
            say(String(format: "freeze landed at %.0f ms: %d of %d displays got a picture",
                       landed.timeIntervalSince(t0) * 1000, frozen.landed, frozen.displays))
        } else {
            say("freeze had not landed within 3 s")
        }

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

    /// What the window server itself thinks each of these windows is worth to a
    /// capture: 0 none (invisible), 1 read only, 2 read write. A window that has
    /// gone missing reads 0, which is the honest answer for "can another tool
    /// see it".
    private static func sharingState(of windowNumbers: Set<Int>) -> [Int] {
        guard !windowNumbers.isEmpty,
              let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID)
                as? [[String: Any]] else { return [0] }
        let byNumber = Dictionary(
            info.compactMap { w -> (Int, Int)? in
                guard let n = w[kCGWindowNumber as String] as? Int else { return nil }
                return (n, w[kCGWindowSharingState as String] as? Int ?? 0)
            }, uniquingKeysWith: { a, _ in a })
        return windowNumbers.sorted().map { byNumber[$0] ?? 0 }
    }

    /// Mean luminance of a screen, freshly captured.
    private static func luma(of screen: NSScreen) async -> Double {
        guard let image = try? await ScreenCapturer.capture(screen: screen) else { return -1 }
        return luma(of: image)
    }

    /// Mean luminance of one picture.
    private static func luma(of image: CGImage) -> Double {
        guard let data = image.dataProvider?.data as Data? else { return -1 }
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
