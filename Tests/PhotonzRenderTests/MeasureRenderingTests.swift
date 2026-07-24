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
        p.r > 200 && p.g < 80 && p.b < 80 && p.a > 40
    }
    private func isWhite(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
        p.r > 240 && p.g > 240 && p.b > 240
    }
    /// Scans a rectangular band for any pixel matching `predicate`.
    private func anyPixel(_ img: CGImage, xs: ClosedRange<Int>, ys: ClosedRange<Int>,
                          where predicate: ((r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool) -> Bool {
        for y in ys where y >= 0 && y < img.height {
            for x in xs where x >= 0 && x < img.width {
                if predicate(pixel(img, x: x, y: y)) { return true }
            }
        }
        return false
    }

    private func render(_ content: MeasureContent, from: CGPoint, to: CGPoint,
                        canvas: Int = 300, pixelScale: CGFloat = 1, bakeLabels: Bool = true) -> CGImage {
        let store = ImageStore()
        let base = store.register(solidImage(width: canvas, height: canvas, r: 255, g: 255, b: 255))
        var doc = PhotonzDocument.withBaseImage(base, pixelScale: pixelScale)
        doc.addLayer(MeasureBuilder.layer(content: content, from: from, to: to))
        return DocumentRenderer().render(doc, store: store, bakeMeasureLabels: bakeLabels)!
    }

    private func content(mode: MeasureMode, showLabel: Bool = true, strokeWidth: CGFloat = 6) -> MeasureContent {
        MeasureContent(mode: mode, strokeWidth: strokeWidth, colorHex: "#FF0000", showLabel: showLabel)
    }

    // Feet run at y=130 from x=20..240; head sits +28 below at y=158.

    @Test func caliperStrokesTheLegsAndHeadLine() {
        let out = render(content(mode: .horizontal, showLabel: false),
                         from: CGPoint(x: 20, y: 130), to: CGPoint(x: 240, y: 130))
        #expect(isRed(pixel(out, x: 20, y: 145)), "the left leg should be stroked")
        #expect(isRed(pixel(out, x: 240, y: 145)), "the right leg should be stroked")
        #expect(isRed(pixel(out, x: 130, y: 158)), "the head line spans the middle (no label ⇒ no gap)")
        #expect(isWhite(pixel(out, x: 130, y: 100)), "above the caliper is untouched")
    }

    @Test func bakedPillFillsTheHeadGapWithColoredText() {
        // With the label baked, the head-line center carries the pill (colored
        // text + hairline border), so the chip band shows caliper-colored ink.
        let out = render(content(mode: .horizontal, showLabel: true),
                         from: CGPoint(x: 20, y: 130), to: CGPoint(x: 240, y: 130), bakeLabels: true)
        #expect(anyPixel(out, xs: 105...155, ys: 150...166, where: isRed),
                "the baked pill draws caliper-colored ink at the head")
    }

    @Test func interactiveOmitsThePillAndCutsTheHeadLine() {
        // bakeLabel:false is the on-screen path — the head line is cut for the
        // (live overlay) chip, so its center is transparent, not a baked pill.
        let img = MeasureRasterizer.rasterize(
            MeasureContent(start: CGPoint(x: 20, y: 60), end: CGPoint(x: 220, y: 60),
                           headOffset: 28, mode: .horizontal, strokeWidth: 6, colorHex: "#FF0000"),
            size: CGSize(width: 240, height: 120), pixelScale: 1, bakeLabel: false)!
        #expect(pixel(img, x: 120, y: 88).a == 0, "the head-line gap is empty on the interactive path")
        #expect(isRed(pixel(img, x: 40, y: 88)), "the head line still strokes outside the gap")
    }

    @Test func bakedPillIsPresentAndAbsentWithTheFlag() {
        let baked = MeasureRasterizer.rasterize(
            MeasureContent(start: CGPoint(x: 20, y: 60), end: CGPoint(x: 220, y: 60),
                           headOffset: 28, mode: .horizontal, strokeWidth: 6, colorHex: "#FF0000"),
            size: CGSize(width: 240, height: 120), pixelScale: 1, bakeLabel: true)!
        #expect(pixel(baked, x: 120, y: 88).a > 0, "the baked pill fills the head gap")
    }

    @Test func labelHiddenLeavesAContinuousHeadLine() {
        let out = render(content(mode: .horizontal, showLabel: false),
                         from: CGPoint(x: 20, y: 130), to: CGPoint(x: 240, y: 130))
        #expect(isRed(pixel(out, x: 130, y: 158)), "no label ⇒ the head line is continuous")
    }

    /// Normalized red-ink row profile within a central column band (excludes the
    /// legs at the far edges), over the ink's vertical extent. Orientation-sensitive.
    private func redRowProfile(_ img: CGImage, xRange: ClosedRange<Int>, bins: Int = 24) -> [Double] {
        var counts = [Int](repeating: 0, count: img.height)
        var minY = Int.max, maxY = -1
        for y in 0..<img.height {
            var c = 0
            for x in xRange where x >= 0 && x < img.width {
                if isRed(pixel(img, x: x, y: y)) { c += 1 }
            }
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
        // The pill blits TextRasterizer's (proven-upright) glyphs. Its red-ink
        // profile in the chip band must match upright text, not its vertical flip.
        let measureImg = MeasureRasterizer.rasterize(
            MeasureContent(start: CGPoint(x: 20, y: 60), end: CGPoint(x: 220, y: 60),
                           headOffset: 28, mode: .horizontal, strokeWidth: 6, colorHex: "#FF0000"),
            size: CGSize(width: 240, height: 120), pixelScale: 1, bakeLabel: true)!
        let text = TextContent(string: "200 px", fontName: "SF Pro",
                               fontSize: MeasureContent.labelFontSize, colorHex: "#FF0000")
        let textImg = TextRasterizer.rasterize(text, size: TextRasterizer.naturalSize(text))!

        let measureProfile = redRowProfile(measureImg, xRange: 95...145)
        let upright = redRowProfile(textImg, xRange: 0...(textImg.width - 1))
        let flipped = Array(upright.reversed())
        func ssd(_ a: [Double], _ b: [Double]) -> Double {
            zip(a, b).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
        }
        #expect(ssd(measureProfile, upright) < ssd(measureProfile, flipped),
                "label ink profile matches upright text, not its vertical flip")
    }

    @Test func retinaScaleStillRendersAPill() {
        let out = render(content(mode: .horizontal), from: CGPoint(x: 20, y: 130),
                         to: CGPoint(x: 220, y: 130), pixelScale: 2)
        #expect(anyPixel(out, xs: 100...160, ys: 150...166, where: isRed),
                "the baked pill still renders under a Retina pixelScale")
    }
}
