// A capture folder made up for a walk, in place of the person's own.
//
// A walk about how history copes with a big folder (switching its filter,
// walking it with the arrow keys) is only worth anything if the folder is big
// and the same every run. The person's own Screenshots folder is neither: on
// 2026-09-30 it held 499 captures on one Mac and could hold none on the next.
// Lending 500 files into it the way `captures` lends a fixture is not on
// either. So `"history": 500` in a walk's setup points the probe's history at a
// folder of 500 made-up captures, one in three a recording, built once under
// the walk scratch root and reused.
//
// Probe builds only.
#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore
import UniformTypeIdentifiers

enum PlaytestGeneratedHistory {
    /// The folder history reads instead of the person's, when a walk asked for
    /// one. Written once in `PhotonzApp.init`, before the capture store exists
    /// or any other thread is started, and only read after that.
    nonisolated(unsafe) private(set) static var folder: URL?
    /// What the walk's setup line says about it.
    nonisolated(unsafe) private(set) static var note: String?

    @MainActor
    static func applyEarly() {
        guard AppInfo.flavor == .probe else { return }
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: PlaytestHarness.argument),
              flag + 1 < arguments.count else { return }
        let url = URL(fileURLWithPath: arguments[flag + 1]).standardizedFileURL
        guard let data = try? Data(contentsOf: url),
              let script = try? PlaytestScript.decode(data),
              let count = script.setup.history else { return }
        let started = Date()
        guard let made = make(count: count) else {
            note = "could not make a history of \(count) captures; history is the person's own folder"
            return
        }
        folder = made.folder
        let videos = PlaytestSetup.generatedHistoryKinds(count: count).filter { $0 == .video }.count
        note = "history is a made-up folder of \(count) captures, \(videos) of them recordings"
            + (made.built ? String(format: " (built in %.1fs)", Date().timeIntervalSince(started)) : "")
    }

    @MainActor
    private static func make(count: Int) -> (folder: URL, built: Bool)? {
        let folder = URL(fileURLWithPath: PlaytestScript.scratchRoot)
            .appendingPathComponent("generated-history-\(count)", isDirectory: true)
        let done = folder.appendingPathComponent(".complete")
        let fm = FileManager.default
        if fm.fileExists(atPath: done.path) { return (folder, false) }
        try? fm.removeItem(at: folder)
        do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) } catch { return nil }

        // A handful of real pictures, cloned: the shapes a person's folder
        // really holds, a full Retina screen most of all.
        let masters = folder.appendingPathComponent(".masters", isDirectory: true)
        try? fm.createDirectory(at: masters, withIntermediateDirectories: true)
        let shapes: [(CGSize, CGFloat)] = [
            (CGSize(width: 3456, height: 2234), 2),   // a whole Retina screen
            (CGSize(width: 1600, height: 1000), 2),   // a window
            (CGSize(width: 660, height: 420), 1),     // a region
            (CGSize(width: 2400, height: 300), 2),    // a toolbar, cropped by the ratio cap
        ]
        var stills: [URL] = []
        for (index, shape) in shapes.enumerated() {
            let url = masters.appendingPathComponent("still-\(index).png")
            guard let image = drawStill(shape.0, seed: index), writePNG(image, to: url, scale: shape.1) else {
                return nil
            }
            stills.append(url)
        }
        guard let sample = TutorialSampleRecording.fresh() else { return nil }
        let recording = masters.appendingPathComponent("recording.mp4")
        try? fm.removeItem(at: recording)
        guard (try? fm.copyItem(at: sample, to: recording)) != nil else { return nil }

        let now = Date()
        for (index, kind) in PlaytestSetup.generatedHistoryKinds(count: count).enumerated() {
            let source = kind == .video ? recording : stills[index % stills.count]
            let name = String(format: "%@ %04d.%@", kind == .video ? "Recording" : "Screenshot",
                              index, kind == .video ? "mp4" : "png")
            let destination = folder.appendingPathComponent(name)
            // A clone on APFS: instant, and no disk spent.
            guard (try? fm.copyItem(at: source, to: destination)) != nil else { return nil }
            // Newest first in the order the kinds were listed.
            let stamp = now.addingTimeInterval(-Double(index) * 60)
            try? fm.setAttributes([.creationDate: stamp, .modificationDate: stamp],
                                  ofItemAtPath: destination.path)
        }
        fm.createFile(atPath: done.path, contents: Data())
        return (folder, true)
    }

    /// Something shaped like a screenshot: panels, bars and rows of "text",
    /// so it compresses and decodes like one rather than like a flat colour.
    private static func drawStill(_ size: CGSize, seed: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        var rng = SeededNumbers(seed: UInt64(seed + 1))
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        for _ in 0..<60 {
            let rect = CGRect(x: rng.next() * size.width, y: rng.next() * size.height,
                              width: rng.next() * size.width / 3, height: rng.next() * size.height / 3)
            context.setFillColor(CGColor(red: rng.next(), green: rng.next(), blue: rng.next(), alpha: 1))
            context.fill(rect)
        }
        context.setFillColor(CGColor(gray: 0.85, alpha: 1))
        var y: CGFloat = 12
        while y < size.height {
            var x: CGFloat = 16
            while x < size.width {
                let word = 8 + rng.next() * 60
                context.fill(CGRect(x: x, y: y, width: word, height: 7))
                x += word + 6
            }
            y += 18
        }
        return context.makeImage()
    }

    private static func writePNG(_ image: CGImage, to url: URL, scale: CGFloat) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        let dpi = 72 * scale
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: dpi,
                                                        kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    /// The same "random" pictures every run.
    private struct SeededNumbers {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> CGFloat {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(state >> 11) / CGFloat(1 << 53)
        }
    }
}
#endif
