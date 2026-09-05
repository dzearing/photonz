#if PHOTONZ_PLAYTEST
import AppKit

/// Probe-only check of the region capture overlay (`--capture-diag`). The
/// overlay covers every display and owns the pointer, so a playtest walk cannot
/// reach it; this drives it directly instead and answers the four things that
/// decide whether it behaves:
///
/// 1. How long from "start a capture" to the screen being dim, both to another
///    capture tool's pixels and to the window server's own sharing state.
/// 2. When each display's frozen picture lands underneath.
/// 3. Whether that picture is the true screen or a photograph of our own dim,
///    measured on the picture itself. A doubly dimmed one reads 0.75 of clean.
/// 4. Whether a window's drop shadow survives the capture API the freeze uses,
///    checked against a window this puts on screen for the purpose.
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
        let cleanShot = try? await ScreenCapturer.capture(screen: screen)
        let clean = cleanShot.map { luma(of: $0) } ?? -1
        say(String(format: "clean screen: mean luma %.4f", clean))
        if let cleanShot {
            write(cleanShot, to: "/tmp/photonz-capture-diag-clean.png")
            say("clean screenshot: /tmp/photonz-capture-diag-clean.png")
        }

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

        await shadowCheck(on: screen)

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
        //
        // The pixel reading is a COVERAGE measure, not a mean over the display,
        // and that distinction is the whole reason this run exists. Window
        // picking opens the dim with a hole over the window under the pointer,
        // so the dimmed part of the screen is whatever that window does not
        // cover. On 2026-09-05 the pointer sat over a 1728x1027 window on a
        // 1728x1117 screen: the dim was there, correct, and plainly visible in
        // the screenshot, but it fell only on the menu bar and a sliver below
        // the window, so a mean over the display read 0.979 of clean and this
        // run reported "the dim NEVER shows up" three times in a row. Compare
        // against the clean shot cell by cell instead and the hole stops
        // hiding the thing being measured.
        let overlays = Set(selection?.overlayWindowNumbers ?? [])
        var dim = (covered: 0.0, ratio: 1.0)
        var polls = 0
        var sawDimAfter: Double?
        var sharedAfter: Double?
        while Date().timeIntervalSince(t0) < 3.0 {
            if sharedAfter == nil, sharingState(of: overlays).allSatisfy({ $0 != 0 }) {
                sharedAfter = Date().timeIntervalSince(t0) * 1000
            }
            guard let shot = try? await ScreenCapturer.capture(screen: screen),
                  let cleanShot else { break }
            polls += 1
            dim = dimCoverage(of: shot, against: cleanShot)
            // A fiftieth of the display washed to about three quarters is far
            // more than any anti-aliasing or clock tick can fake, and far less
            // than the smallest hole the overlay ever opens.
            if dim.covered > 0.02 {
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
                       + "polls): %.0f%% of the display is washed to %.3f of clean (0.75 = one "
                       + "dim, 0.56 = the freeze photographed our own dim). The rest is the hole "
                       + "the overlay opens over the window under the pointer.",
                       sawDimAfter, polls, dim.covered * 100, dim.ratio))
        } else {
            say(String(format: "dim NEVER shows up in another tool's screenshot: only %.0f%% of "
                       + "the display is washed after 3 s and %d polls", dim.covered * 100, polls))
        }
        // The poll above stops the moment it has its answer, which is now well
        // inside the time the freeze takes to land, so wait for it rather than
        // reporting "no display froze one" about a freeze that simply had not
        // happened yet.
        while selection?.freezeFinished == nil, Date().timeIntervalSince(t0) < 3.0 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        if let landed = selection?.freezeFinished {
            let frozen = selection?.frozenCount ?? (landed: 0, displays: 0)
            say(String(format: "freeze landed at %.0f ms: %d of %d displays got a picture",
                       landed.timeIntervalSince(t0) * 1000, frozen.landed, frozen.displays))
        } else {
            say("freeze had not landed within 3 s")
        }

        // The overlay as another tool sees it BEFORE the pointer has done
        // anything. The drag shot at the end of this run cannot answer "is the
        // dim there from the first instant", because a drag repaints the
        // overlay and a repaint is itself a way the dim can arrive; this one is
        // taken with the overlay simply sitting there.
        if let shot = try? await ScreenCapturer.capture(screen: screen), let cleanShot {
            write(shot, to: "/tmp/photonz-capture-diag-predrag.png")
            let still = dimCoverage(of: shot, against: cleanShot)
            say(String(format: "screenshot before any pointer event: "
                       + "/tmp/photonz-capture-diag-predrag.png, %.0f%% of the display washed to "
                       + "%.3f of clean", still.covered * 100, still.ratio))
        }

        // The picture itself, measured rather than inferred. Everything above
        // reads the LIVE screen, which answers "what does another tool see";
        // this answers "is the picture we froze the true screen", and the two
        // fail independently. A freeze that photographed our own dim reads
        // about 0.75 of clean here and would show the world twice as dark the
        // moment the dim is drawn over it.
        if let frozen = selection?.frozenImages.first {
            let frozenLuma = luma(of: frozen)
            let frozenRatio = frozenLuma / max(clean, 0.0001)
            say(String(format: "frozen picture under the overlay: mean luma %.4f, %.3f of clean "
                       + "(%@)", frozenLuma, frozenRatio,
                       frozenRatio > 0.9
                       ? "the true screen, so the world is never dimmed twice"
                       : "OUR OWN DIM IS IN THE PICTURE, the world would look twice as dark"))
        } else {
            say("frozen picture under the overlay: no display froze one, nothing to measure")
        }

        // A drag, photographed for real: the box, its size pill, and nothing
        // else beside the pointer.
        selection?.simulateDrag(from: CGPoint(x: 320, y: 260), to: CGPoint(x: 900, y: 620))
        try? await Task.sleep(for: .milliseconds(250))
        if let shot = try? await ScreenCapturer.capture(screen: screen), let cleanShot {
            write(shot, to: "/tmp/photonz-capture-diag-drag.png")
            let dragged = dimCoverage(of: shot, against: cleanShot)
            say(String(format: "drag screenshot: /tmp/photonz-capture-diag-drag.png, %.0f%% of "
                       + "the display washed to %.3f of clean, the clean part being the box "
                       + "being dragged", dragged.covered * 100, dragged.ratio))
        } else {
            say("drag screenshot FAILED")
        }

        selection?.dismiss()
        selection = nil
        try? await Task.sleep(for: .milliseconds(200))
        // Also the control for the dim reading above: with the overlay gone
        // there is nothing left to wash, so this has to come back at nearly
        // zero. If it ever reports a real percentage, the dim numbers above are
        // measuring the screen changing under them and mean nothing.
        if let shot = try? await ScreenCapturer.capture(screen: screen), let cleanShot {
            let left = dimCoverage(of: shot, against: cleanShot)
            say(String(format: "overlay gone: mean luma %.4f, %.3f of clean; %.0f%% of the "
                       + "display still washed (this is the control, it has to be 0%%)",
                       luma(of: shot), luma(of: shot) / max(clean, 0.0001), left.covered * 100))
        }

        try? out.joined(separator: "\n").write(toFile: "/tmp/photonz-capture-diag.txt",
                                               atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    /// Whether a window's drop shadow survives the capture API the freeze now
    /// uses. This is the one thing the switch put at risk and the one thing
    /// nothing else here can see: the old path
    /// (`SCScreenshotManager.captureImage(in:)`) photographs the display the way
    /// the system screenshot does, shadows and all, while the filter path
    /// re-composites windows from their own buffers and was measured on
    /// 2026-07-03 to synthesize no shadows at all. `ignoreShadows = false` is
    /// meant to have fixed that, and nobody has checked.
    ///
    /// A previous run could not check, because it compared two shots of a screen
    /// with no windows on it, where "shadows are missing" and "there is nothing
    /// to cast one" look identical. So put a window there: a plain grey backdrop
    /// with a white card floating above it, and read the band of backdrop just
    /// below the card's bottom edge, where the shadow falls, against a band far
    /// enough below to be clean. Our own two windows are the only thing being
    /// compared, so the wallpaper, the time of day and the menu bar cannot
    /// change the answer.
    private static func shadowCheck(on screen: NSScreen) async {
        // Screen-local points, top-left origin. The card sits high in the
        // backdrop so there is room below it for both bands.
        let backdrop = CGRect(x: 160, y: 160, width: 700, height: 600)
        let card = CGRect(x: backdrop.minX + 60, y: backdrop.minY + 60, width: 360, height: 240)
        // A window shadow reaches tens of points below the sill; 200 points down
        // is backdrop and nothing else.
        let shadowBand = CGRect(x: card.minX + 40, y: card.maxY + 4,
                                width: card.width - 80, height: 10)
        let cleanBand = CGRect(x: card.minX + 40, y: card.maxY + 200,
                               width: card.width - 80, height: 10)

        let back = panel(at: backdrop, on: screen, color: .init(white: 0.45, alpha: 1),
                         shadow: false)
        let front = panel(at: card, on: screen, color: .init(white: 0.95, alpha: 1), shadow: true)
        defer {
            front.orderOut(nil)
            back.orderOut(nil)
        }
        // Give the window server time to draw both and settle the shadow.
        try? await Task.sleep(for: .milliseconds(400))

        guard let plain = try? await ScreenCapturer.capture(screen: screen),
              let filtered = try? await ScreenCapturer.capture(screen: screen,
                                                               excludingWindowNumbers: []) else {
            say("window shadow through the freeze's capture path: could not take both shots")
            return
        }

        func depth(_ image: CGImage) -> Double {
            luma(of: image, in: cleanBand, on: screen) - luma(of: image, in: shadowBand, on: screen)
        }
        let plainDepth = depth(plain)
        let freezeDepth = depth(filtered)
        // The shadow is a fraction of the backdrop's brightness, so judge the
        // freeze against the old path rather than against an absolute number.
        let kept = plainDepth > 0.01 ? freezeDepth / plainDepth : -1
        say(String(format: "window shadow below a test window: old path darkens the band by "
                   + "%.4f, freeze path by %.4f", plainDepth, freezeDepth))
        if plainDepth <= 0.01 {
            say("  INCONCLUSIVE: the old path found no shadow either, so there was nothing to "
                + "compare (a locked screen does this)")
        } else if kept > 0.75 {
            say(String(format: "  shadow survives the freeze: %.0f%% as deep as before", kept * 100))
        } else {
            say(String(format: "  SHADOW LOST: only %.0f%% as deep as before, so frozen windows "
                       + "look pasted on", kept * 100))
        }
    }

    /// A plain coloured window at a screen-local, top-left-origin points rect.
    private static func panel(at local: CGRect, on screen: NSScreen, color: NSColor,
                              shadow: Bool) -> NSWindow {
        let frame = CGRect(x: screen.frame.minX + local.minX,
                           y: screen.frame.maxY - local.maxY,
                           width: local.width, height: local.height)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.backgroundColor = color
        window.isOpaque = true
        window.hasShadow = shadow
        window.animationBehavior = .none
        window.orderFrontRegardless()
        return window
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

    /// How much of the display a shot has washed darker than the clean screen,
    /// and how dark that washed part is.
    ///
    /// The overlay never dims the whole display: it always holds a hole open,
    /// over the window under the pointer or over the box being dragged. So a
    /// mean over the display answers a question nobody asked, and answers it
    /// wrong whenever the hole is large. This compares the two shots cell by
    /// cell and reports only the cells that actually went darker: `covered` is
    /// the fraction of the display the dim fell on, `ratio` is how dark it went
    /// there, which is the number the dim's own alpha predicts (0.75 for one
    /// 25% black wash, about 0.56 if it ever got applied twice).
    ///
    /// Cells that are near black to begin with are skipped: three quarters of
    /// almost nothing is still almost nothing, so their ratio is noise.
    private static func dimCoverage(of shot: CGImage,
                                    against clean: CGImage) -> (covered: Double, ratio: Double) {
        guard shot.width == clean.width, shot.height == clean.height,
              let shotData = shot.dataProvider?.data as Data?,
              let cleanData = clean.dataProvider?.data as Data? else { return (0, 1) }
        let cols = 64, rows = 40
        var washed = 0.0
        var cells = 0.0
        var ratioTotal = 0.0
        for r in 0..<rows {
            for c in 0..<cols {
                let x0 = shot.width * c / cols, x1 = shot.width * (c + 1) / cols
                let y0 = shot.height * r / rows, y1 = shot.height * (r + 1) / rows
                let before = mean(cleanData, of: clean, x0, y0, x1, y1)
                let after = mean(shotData, of: shot, x0, y0, x1, y1)
                guard before > 0.04 else { continue }
                cells += 1
                let ratio = after / before
                // Wide enough to catch a dim laid over changing content (a
                // clock, a cursor blink), tight enough that redrawn content
                // cannot masquerade as one.
                if ratio > 0.45 && ratio < 0.88 {
                    washed += 1
                    ratioTotal += ratio
                }
            }
        }
        guard cells > 0 else { return (0, 1) }
        return (washed / cells, washed > 0 ? ratioTotal / washed : 1)
    }

    /// Mean luminance of a pixel-rect block, read straight out of a buffer that
    /// the caller already holds, so a per-cell sweep does not re-fetch it.
    private static func mean(_ data: Data, of image: CGImage,
                             _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Double {
        let bpr = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8
        var total = 0.0
        var count = 0.0
        for y in stride(from: y0, to: y1, by: 3) {
            for x in stride(from: x0, to: x1, by: 3) {
                let i = y * bpr + x * bpp
                guard i + 2 < data.count else { continue }
                total += (Double(data[i]) + Double(data[i + 1]) + Double(data[i + 2])) / 765.0
                count += 1
            }
        }
        return count > 0 ? total / count : 0
    }

    /// Mean luminance of a screen, freshly captured.
    private static func luma(of screen: NSScreen) async -> Double {
        guard let image = try? await ScreenCapturer.capture(screen: screen) else { return -1 }
        return luma(of: image)
    }

    /// Mean luminance of one screen-local, top-left-origin points rect inside a
    /// full-screen shot. The scale is read off the picture rather than the
    /// display, the way the freeze's own crop does it.
    private static func luma(of image: CGImage, in local: CGRect, on screen: NSScreen) -> Double {
        guard screen.frame.width > 0 else { return -1 }
        let scale = CGFloat(image.width) / screen.frame.width
        let rect = CGRect(x: local.minX * scale, y: local.minY * scale,
                          width: local.width * scale, height: local.height * scale).integral
        guard let crop = image.cropping(to: rect) else { return -1 }
        return luma(of: crop, step: 1)
    }

    /// Mean luminance of one picture.
    private static func luma(of image: CGImage, step: Int = 8) -> Double {
        guard let data = image.dataProvider?.data as Data? else { return -1 }
        let bpr = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8
        var total = 0.0
        var count = 0.0
        for y in stride(from: 0, to: image.height, by: step) {
            for x in stride(from: 0, to: image.width, by: step) {
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
