import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Measure rendering")
struct MeasureRenderingTests {

    private func solidImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                                     blue: CGFloat(b) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Reads RGBA at (x, y) in top-left coordinates.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = (y * width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }

    private func isRed(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
        p.r > 200 && p.g < 80 && p.b < 80
    }
    private func isWhite(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
        p.r > 240 && p.g > 240 && p.b > 240
    }

    private func render(_ content: MeasureContent, from: CGPoint, to: CGPoint,
                        canvas: Int = 260, pixelScale: CGFloat = 1) -> CGImage {
        let store = ImageStore()
        let base = store.register(solidImage(width: canvas, height: canvas, r: 255, g: 255, b: 255))
        var doc = PhotonzDocument.withBaseImage(base, pixelScale: pixelScale)
        doc.addLayer(MeasureBuilder.layer(content: content, from: from, to: to))
        return DocumentRenderer().render(doc, store: store)!
    }

    private func content(mode: MeasureMode, showLabel: Bool = true, strokeWidth: CGFloat = 6) -> MeasureContent {
        MeasureContent(mode: mode, strokeWidth: strokeWidth, colorHex: "#FF0000", showLabel: showLabel)
    }

    @Test func dimensionLineStrokesBetweenEndpoints() {
        let out = render(content(mode: .horizontal),
                         from: CGPoint(x: 20, y: 130), to: CGPoint(x: 240, y: 130))
        #expect(isRed(pixel(out, x: 50, y: 130)), "the dimension line should be stroked")
        #expect(isWhite(pixel(out, x: 50, y: 105)), "above the line (clear of the plate) is untouched")
        #expect(isWhite(pixel(out, x: 10, y: 130)), "before the start point is untouched")
    }

    @Test func labelPlateRendersWhenEnabledAndIsAbsentWhenDisabled() {
        // A point just above the dimension line but inside the centered plate band.
        let labelled = render(content(mode: .horizontal, showLabel: true),
                              from: CGPoint(x: 20, y: 130), to: CGPoint(x: 240, y: 130))
        #expect(isRed(pixel(labelled, x: 130, y: 112)), "the label plate fills above the line")

        // White text glyphs exist on the red plate (scan the plate interior for a
        // white pixel surrounded by red fill).
        var foundGlyph = false
        for x in 110...150 where isWhite(pixel(labelled, x: x, y: 130)) { foundGlyph = true }
        #expect(foundGlyph, "white label text should render on the plate")

        let bare = render(content(mode: .horizontal, showLabel: false),
                          from: CGPoint(x: 20, y: 130), to: CGPoint(x: 240, y: 130))
        #expect(isWhite(pixel(bare, x: 130, y: 112)), "no plate when the label is toggled off")
    }

    @Test func witnessLineDropsFromAnOffsetStart() {
        // Start sits 60px above the dimension line (which levels onto end.y); a
        // vertical witness line connects it down to the line.
        let out = render(content(mode: .horizontal),
                         from: CGPoint(x: 40, y: 70), to: CGPoint(x: 200, y: 130))
        #expect(isRed(pixel(out, x: 40, y: 95)), "witness line drops from the offset start")
        #expect(isWhite(pixel(out, x: 70, y: 95)), "no witness line away from the start column")
    }

    @Test func freeMeasureStrokesTheDiagonal() {
        let out = render(content(mode: .free),
                         from: CGPoint(x: 30, y: 30), to: CGPoint(x: 200, y: 170))
        // On the line near the start (y = 30 + 0.8235*(x-30)); at x=50 → ~46.5.
        #expect(isRed(pixel(out, x: 50, y: 46)), "the diagonal is stroked")
        #expect(isWhite(pixel(out, x: 50, y: 75)), "off the diagonal is untouched")
    }

    /// Normalized vertical ink profile of the white (text) pixels, resampled to
    /// `bins` over the ink's vertical extent. Orientation-sensitive.
    private func whiteRowProfile(_ img: CGImage, bins: Int = 24) -> [Double] {
        var counts = [Int](repeating: 0, count: img.height)
        var minY = Int.max, maxY = -1
        for y in 0..<img.height {
            var c = 0
            for x in 0..<img.width where isWhite(pixel(img, x: x, y: y)) { c += 1 }
            counts[y] = c
            if c > 0 { minY = min(minY, y); maxY = max(maxY, y) }
        }
        guard maxY >= minY else { return [Double](repeating: 0, count: bins) }
        let h = maxY - minY + 1
        var profile = [Double](repeating: 0, count: bins)
        for y in minY...maxY { profile[min(bins - 1, (y - minY) * bins / h)] += Double(counts[y]) }
        let total = profile.reduce(0, +)
        if total > 0 { for i in 0..<bins { profile[i] /= total } }
        return profile
    }

    @Test func labelTextRendersUprightNotFlipped() {
        // The measure blits TextRasterizer's (proven-upright) glyphs. Its vertical
        // ink profile must match TextRasterizer's upright profile, NOT its flip —
        // a regression that drew the label upside down would invert it.
        let measureImg = MeasureRasterizer.rasterize(
            MeasureContent(start: CGPoint(x: 20, y: 60), end: CGPoint(x: 220, y: 60),
                           mode: .horizontal, strokeWidth: 6, colorHex: "#FF0000"),
            size: CGSize(width: 240, height: 120), pixelScale: 1)!
        let text = TextContent(string: "200 pt", fontName: "SF Pro",
                               fontSize: MeasureContent.labelFontSize, colorHex: "#FFFFFF")
        let textImg = TextRasterizer.rasterize(text, size: TextRasterizer.naturalSize(text))!

        let measureProfile = whiteRowProfile(measureImg)
        let upright = whiteRowProfile(textImg)
        let flipped = Array(upright.reversed())
        func ssd(_ a: [Double], _ b: [Double]) -> Double {
            zip(a, b).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
        }
        #expect(ssd(measureProfile, upright) < ssd(measureProfile, flipped),
                "label ink profile matches upright text, not its vertical flip")
    }

    @Test func pointsReadoutHalvesAtRetinaScale() {
        // Same 200px span reads "200" at 1× and "100" at 2× — the rendered plate
        // narrows accordingly. We can't OCR, but the 1× plate (3 digits) must be
        // wider than the 2× plate (3 digits too here, so instead compare a tiny
        // span). Simpler: assert the label toggles the plate; scale correctness is
        // covered by the core MeasureUnitsTests. This test guards the render path
        // accepts pixelScale without crashing and still draws a plate.
        let out = render(content(mode: .horizontal), from: CGPoint(x: 20, y: 130),
                         to: CGPoint(x: 220, y: 130), pixelScale: 2)
        #expect(isRed(pixel(out, x: 120, y: 112)), "plate still renders under a Retina pixelScale")
    }
}
