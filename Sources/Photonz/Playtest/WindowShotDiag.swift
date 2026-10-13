#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore
import PhotonzRender

/// Probe-only drill of a clicked window's shadow (`--window-shot-diag`).
///
/// Puts real titled windows on screen (light and dark) and takes each through
/// exactly what a click in the capture overlay does: the window shot
/// (`RectSelectionController.windowShot`), then the capture history's own save
/// into a scratch folder, then the layered copy read back the way the editor
/// opens it. Along the way it shoots macOS's own shadowed picture of the same
/// window, so the two shadows can be compared number for number, and it checks:
///
/// - the window layer wears the shadow at `WindowShot.shadowStrength` of the
///   opacity macOS drew it at, with macOS's shape;
/// - the bare picture under that layer is the window and nothing past it;
/// - the saved picture is transparent in its corners and lighter than macOS's
///   at three points below the window.
///
/// Everything lands in `/tmp/photonz-window-shot-diag.json`, with a `verdict`
/// and the pictures beside it as PNGs. `--active` makes the windows key first
/// (the larger, darker shadow of a window in front); it brings the probe to
/// the front, so only run it with nobody at the Mac.
@MainActor
enum WindowShotDiag {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--window-shot-diag") else { return }
        Task { await run(active: CommandLine.arguments.contains("--active")) }
    }

    private static var failures: [String] = []

    private static func check(_ ok: Bool, _ what: String) {
        if !ok { failures.append(what) }
    }

    private static func run(active: Bool) async {
        var report: [String: Any] = ["granted": ScreenCapturer.hasPermission, "active": active]
        var shots: [[String: Any]] = []
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-window-shot-diag-\(UUID().uuidString)")
        let store = CaptureStore(directory: folder)
        for dark in [false, true] {
            let name = dark ? "dark" : "light"
            let window = NSWindow(contentRect: CGRect(x: 300, y: 300, width: 600, height: 400),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Shadow diag \(name)"
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.animationBehavior = .none
            window.isReleasedWhenClosed = false
            if active {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
            try? await Task.sleep(for: .milliseconds(600))
            let scale = window.backingScaleFactor
            var entry: [String: Any] = ["look": name, "scale": scale,
                                        "windowPoints": [window.frame.width, window.frame.height]]
            let picked = ScreenWindow(id: window.windowNumber, frame: window.frame, layer: 0, alpha: 1)
            guard let macOS = try? await ScreenCapturer.captureWindow(id: window.windowNumber, includeShadow: true),
                  let shot = await RectSelectionController.windowShot(of: picked, style: .withShadow, scale: scale),
                  let layers = shot.layers else {
                check(false, "\(name): the window could not be shot with its shadow")
                shots.append(entry)
                window.orderOut(nil)
                continue
            }
            window.orderOut(nil)
            write(macOS, to: "/tmp/photonz-window-shot-diag-\(name)-macos.png")
            entry["macos"] = profile(of: macOS)
            let reading = WindowCaptureShadow.edgeProfiles(of: macOS)
                .flatMap { WindowShot.readSystemShadow($0, pixelScale: scale) }
            if let reading {
                entry["macosReading"] = ["look": "\(reading.look)", "opacity": reading.opacity,
                                         "ringOpacity": reading.ringOpacity]
            }

            // Saved the way the capture history saves a click, and read back
            // the way the editor opens it.
            guard let saved = store.add(shot.image, scale: scale, layers: layers),
                  let flat = loadPNG(saved.url),
                  let reopened = try? PackageIO.read(from: EditorState.sidecarURL(for: saved.url),
                                                     into: ImageStore()) else {
                check(false, "\(name): the capture or its layers did not save")
                shots.append(entry)
                continue
            }
            write(flat, to: "/tmp/photonz-window-shot-diag-\(name)-ours.png")
            // The capture as history keeps it, picture and layers, for a walk to open.
            let kept = URL(fileURLWithPath: "/tmp/photonz-window-shot-diag-\(name)-capture.png")
            for (from, to) in [(saved.url, kept),
                               (EditorState.sidecarURL(for: saved.url), EditorState.sidecarURL(for: kept))] {
                try? FileManager.default.removeItem(at: to)
                try? FileManager.default.copyItem(at: from, to: to)
            }
            entry["ours"] = profile(of: flat)

            // The layer wears 40% of what macOS drew, in macOS's shape.
            let layer = reopened.layers.first
            let shadows = layer?.style.shadows ?? []
            entry["layerShadows"] = shadows.map {
                ["blur": $0.radius, "offsetY": $0.offset.height, "spread": $0.spread, "opacity": $0.opacity]
            }
            check(reopened.layers.count == 1 && layer?.isLocked == false,
                  "\(name): the reopened capture is not one pickable window layer")
            check(shadows == WindowShot.shadows(for: reading, pixelScale: scale),
                  "\(name): the layer's shadow is not 40% of the one macOS drew")
            if let reading, let soft = shadows.first {
                check(abs(soft.opacity - reading.opacity * WindowShot.shadowStrength) < 0.002,
                      "\(name): soft shadow opacity \(soft.opacity) is not 40% of macOS's \(reading.opacity)")
            }

            // The picture under the layer is the bare window, nothing past it.
            if case .image(let ref)? = layer?.content {
                let wanted = CGSize(width: (window.frame.width * scale).rounded(),
                                    height: (window.frame.height * scale).rounded())
                entry["bareSize"] = [ref.pixelSize.width, ref.pixelSize.height]
                check(ref.pixelSize == wanted,
                      "\(name): the bare window is \(ref.pixelSize), not the window's \(wanted)")
            } else {
                check(false, "\(name): the window layer holds no picture")
            }

            // Transparent corners, and lighter than macOS at three points below.
            let ours = profile(of: flat), theirs = profile(of: macOS)
            // The window's own edge, rim and all, as macOS drew it.
            if let o = ours["window"] as? [Int], let m = theirs["window"] as? [Int] {
                let oursEdge = rgbAt(flat, o[0], o[1] + o[3] / 2)
                let theirsEdge = rgbAt(macOS, m[0], m[1] + m[3] / 2)
                entry["edgePixel"] = ["ours": oursEdge, "macos": theirsEdge]
                check(zip(oursEdge, theirsEdge).allSatisfy { abs($0 - $1) <= 3 },
                      "\(name): the window's edge is \(oursEdge), macOS drew \(theirsEdge)")
            }
            let corners = [alphaAt(flat, 0, 0), alphaAt(flat, flat.width - 1, 0),
                           alphaAt(flat, 0, flat.height - 1), alphaAt(flat, flat.width - 1, flat.height - 1)]
            entry["cornerAlpha"] = corners
            check(corners.allSatisfy { $0 == 0 }, "\(name): a corner of the saved picture is not transparent")
            if let oursBelow = ours["below"] as? [Int], let theirsBelow = theirs["below"] as? [Int] {
                var points: [[String: Int]] = []
                for t in [8, 40, 80] where t < oursBelow.count && t < theirsBelow.count {
                    points.append(["px": t, "ours": oursBelow[t], "macos": theirsBelow[t]])
                    check(Double(oursBelow[t]) <= Double(theirsBelow[t]) * 0.55 + 2,
                          "\(name): \(t)px below, ours \(oursBelow[t]) is not well under macOS's \(theirsBelow[t])")
                }
                entry["threePointsBelow"] = points
            }
            shots.append(entry)
        }
        try? FileManager.default.removeItem(at: folder)
        report["shots"] = shots
        report["failures"] = failures
        report["verdict"] = failures.isEmpty ? "PASS" : "FAIL"
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/photonz-window-shot-diag.json"))
        }
        NSLog("[window-shot-diag] \(failures.isEmpty ? "PASS" : "FAIL"), wrote /tmp/photonz-window-shot-diag.json")
        NSApp.terminate(nil)
    }

    private static func loadPNG(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func pixels(of image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h,
                                          bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? pixels : nil
    }

    /// Red, green and blue 0...255 at a pixel, y from the top.
    private static func rgbAt(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
        guard let pixels = pixels(of: image) else { return [] }
        let i = (y * image.width + x) * 4
        return [Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2])]
    }

    /// Alpha 0...255 at a pixel, y from the top.
    private static func alphaAt(_ image: CGImage, _ x: Int, _ y: Int) -> Int {
        guard let pixels = pixels(of: image) else { return -1 }
        return Int(pixels[(y * image.width + x) * 4 + 3])
    }

    /// Size, where the opaque window sits inside the picture, and the alpha
    /// (0...255) read outward from the middle of each edge to the picture's own
    /// edge.
    private static func profile(of image: CGImage) -> [String: Any] {
        let w = image.width, h = image.height
        guard let pixels = pixels(of: image) else { return ["error": "unreadable"] }
        // Row 0 is the TOP of the picture in this buffer (CGContext memory order).
        func alpha(_ x: Int, _ y: Int) -> Int { Int(pixels[(y * w + x) * 4 + 3]) }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where alpha(x, y) >= 250 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return ["size": [w, h], "error": "nothing opaque"] }
        let midX = (minX + maxX) / 2, midY = (minY + maxY) / 2
        return ["size": [w, h], "window": [minX, minY, maxX - minX + 1, maxY - minY + 1],
                "below": ((maxY + 1)..<h).map { alpha(midX, $0) },
                "above": (0..<minY).reversed().map { alpha(midX, $0) },
                "left": (0..<minX).reversed().map { alpha($0, midY) },
                "right": ((maxX + 1)..<w).map { alpha($0, midY) }]
    }

    private static func write(_ image: CGImage, to path: String) {
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
