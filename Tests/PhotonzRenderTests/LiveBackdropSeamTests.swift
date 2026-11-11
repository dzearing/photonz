import CoreGraphics
import Foundation
import ImageIO
import PhotonzCore
import PhotonzRender
import Testing

/// A moving title background never shows the edges of the grid it is drawn
/// on (task `the-keynote-clean-title-page-draws-its-starfield`).
///
/// Particles are scattered one to a cell of a grid. A glow that spills past
/// its own cell was cut off at the cell's edge, so the Keynote Clean page
/// drew a dark box round many of its specks of light, at 1920 by 1080 and at
/// Retina size, in the very frames export writes.
///
/// Measured as straight seams: a step between two neighbouring pixels much
/// sharper than the steps on either side of it (a cut, not a slope), lined up
/// down a column or along a row for longer than any round speck could make
/// one. A soft glow has no such run; a box has four.
@Suite("Moving title backgrounds draw no grid seams")
struct LiveBackdropSeamTests {

    /// A cut lined up for this many pixels is an edge, not the rim of a
    /// speck: the largest speck is about 20 pixels across at 1080p.
    static let seamRun = 24

    static func frame(_ doc: PhotonzDocument, atMS ms: Int) throws -> CGImage {
        try #require(DocumentRenderer().render(doc.drawn(atTimeMS: ms), store: ImageStore()))
    }

    /// The red, green and blue of each pixel added up, row by row.
    static func light(_ image: CGImage) -> (values: [Int], width: Int, height: Int) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var values = [Int](repeating: 0, count: w * h)
        for index in 0..<(w * h) {
            values[index] = Int(data[index * 4]) + Int(data[index * 4 + 1]) + Int(data[index * 4 + 2])
        }
        return (values, w, h)
    }

    /// How many straight seams the picture has, inside `region` (pixels), and
    /// the longest.
    ///
    /// `least` is the smallest step counted, in levels of red, green and blue
    /// added up. Three is one level a channel, which a smooth glow also makes
    /// wherever 8-bit rounding ticks over along a nearly straight slope: that
    /// is banding, not a box. The boxes this suite was written for stepped by
    /// 31 to 33.
    static func seams(_ image: CGImage, in region: CGRect? = nil,
                      least: Int = 3) -> (count: Int, longest: Int, at: String, step: Int) {
        let (v, w, h) = light(image)
        let area = (region ?? CGRect(x: 0, y: 0, width: w, height: h)).integral
        let x0 = max(Int(area.minX), 1), x1 = min(Int(area.maxX), w - 2)
        let y0 = max(Int(area.minY), 1), y1 = min(Int(area.maxY), h - 2)
        func cut(_ before: Int, _ step: Int, _ after: Int) -> Int {
            // The sign of a step that stands out from its neighbours, else 0.
            guard abs(step) >= least, abs(step) >= 3 * max(abs(before), abs(after)) else { return 0 }
            return step > 0 ? 1 : -1
        }
        var count = 0, longest = 0, at = "", step = 0, biggest = 0
        func close(_ run: Int, _ place: @autoclosure () -> String) {
            if run > longest { longest = run; at = place(); step = biggest }
            if run >= seamRun { count += 1 }
        }
        // Down each column boundary.
        for x in x0..<x1 {
            var run = 0, sign = 0
            for y in y0..<y1 {
                let row = y * w
                let s = cut(v[row + x] - v[row + x - 1], v[row + x + 1] - v[row + x], v[row + x + 2] - v[row + x + 1])
                if s != 0, s == sign { run += 1; biggest = max(biggest, abs(v[row + x + 1] - v[row + x])) } else {
                    close(run, "column \(x) ending row \(y)"); run = s == 0 ? 0 : 1; sign = s
                    biggest = abs(v[row + x + 1] - v[row + x])
                }
            }
            close(run, "column \(x) at the bottom")
        }
        // Along each row boundary.
        for y in y0..<y1 {
            var run = 0, sign = 0
            for x in x0..<x1 {
                let s = cut(v[y * w + x] - v[(y - 1) * w + x], v[(y + 1) * w + x] - v[y * w + x],
                            v[(y + 2) * w + x] - v[(y + 1) * w + x])
                let here = abs(v[(y + 1) * w + x] - v[y * w + x])
                if s != 0, s == sign { run += 1; biggest = max(biggest, here) } else {
                    close(run, "row \(y) ending column \(x)"); run = s == 0 ? 0 : 1; sign = s; biggest = here
                }
            }
            close(run, "row \(y) at the right")
        }
        return (count, longest, at, step)
    }

    static func write(_ image: CGImage, to url: URL) {
        guard let out = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(out, image, nil)
        CGImageDestinationFinalize(out)
    }

    /// A video `size` big holding a Keynote Clean page from the start.
    static func keynote(_ size: CGSize) throws -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: size)
        doc.durationMS = 6000
        let placed = doc.insertTitle(.keynote, atTimeMS: 0, motionBlur: true)
        _ = try #require(placed)
        return doc
    }

    @Test("A Keynote Clean page 2.5 s in has no box round any glow, at 1080p and at Retina size",
          arguments: [CGSize(width: 1920, height: 1080), CGSize(width: 3456, height: 2234)])
    func keynoteHasNoBoxes(_ size: CGSize) throws {
        let image = try Self.frame(Self.keynote(size), atMS: 2500)
        if let folder = ProcessInfo.processInfo.environment["PHOTONZ_SEAM_FRAMES"] {
            Self.write(image, to: URL(fileURLWithPath: folder).appendingPathComponent("keynote-\(Int(size.width)).png"))
        }
        // The upper third: background only, above the words.
        let found = Self.seams(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.33))
        #expect(found.count == 0, "\(Int(size.width))x\(Int(size.height)): \(found.count) straight seams, longest \(found.longest) px at \(found.at), step \(found.step)")
    }

    /// The looks made of soft light. Architectural Sketch and Grid Horizon
    /// draw crisp straight lines on purpose (a blueprint grid, a floor grid
    /// and a sun setting behind the horizon), and every one of them reads as
    /// a seam here; they were looked at on 2026-11-11 and have no boxes.
    static let softLooks = LiveLook.allCases.filter { $0 != .sketch && $0 != .gridHorizon }

    @Test("No soft moving look draws a seam, at its defaults and at its strongest", arguments: softLooks)
    func noLookHasSeams(_ look: LiveLook) throws {
        let size = CGSize(width: 1920, height: 1080)
        for depth in [nil, 100.0] as [Double?] {
            var live = LiveBackdrop(look: look)
            if let depth { live.shape = depth }
            let theme = TitleTheme.curated[0]
            let paint = Paint(hex: theme.ground, kind: .live, stops: theme.liveStops, live: live)
            var content = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: paint.hex,
                                            start: .zero, end: CGPoint(x: size.width, y: size.height))
            content.fill = paint
            var layer = Layer(name: "Background", content: .annotation(content), frame: CGRect(origin: .zero, size: size))
            layer.time = LayerTime(inMS: 0, outMS: 6000, sourceInMS: 0)
            var doc = PhotonzDocument(canvasSize: size, layers: [layer])
            doc.durationMS = 6000
            let image = try Self.frame(doc, atMS: 2500)
            let found = Self.seams(image, least: 6)
            if let folder = ProcessInfo.processInfo.environment["PHOTONZ_SEAM_FRAMES"] {
                Self.write(image, to: URL(fileURLWithPath: folder)
                    .appendingPathComponent("\(look.rawValue)-\(depth.map { String(Int($0)) } ?? "default").png"))
            }
            #expect(found.count == 0,
                    "\(look.rawValue) shape \(depth.map { String($0) } ?? "default"): \(found.count) straight seams, longest \(found.longest) px at \(found.at), step \(found.step)")
        }
    }
}
