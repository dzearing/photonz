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
    /// Red ink at ANY coverage: premultiplied components stay red-dominant even
    /// where a hairline stroke only partly covers the pixel.
    private func isRedInk(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
        p.a > 40 && Int(p.r) > Int(p.g) + 60 && Int(p.r) > Int(p.b) + 60
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
                        canvas: Int = 300, pixelScale: CGFloat = 1) -> CGImage {
        let store = ImageStore()
        let base = store.register(solidImage(width: canvas, height: canvas, r: 255, g: 255, b: 255))
        var doc = PhotonzDocument.withBaseImage(base, pixelScale: pixelScale)
        doc.addLayer(MeasureBuilder.layer(content: content, from: from, to: to))
        return DocumentRenderer().render(doc, store: store)!
    }

    private func content(mode: MeasureMode, showLabel: Bool = true, strokeWidth: CGFloat = 6) -> MeasureContent {
        MeasureContent(mode: mode, strokeWidth: strokeWidth, strokeColorHex: "#FF0000",
                       textColorHex: "#FF0000", showLabel: showLabel)
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

    @Test func pillFillsTheHeadGapWithColoredText() {
        // The head-line center carries the pill (colored text + hairline
        // border), so the chip band shows caliper-colored ink.
        let out = render(content(mode: .horizontal, showLabel: true),
                         from: CGPoint(x: 20, y: 130), to: CGPoint(x: 240, y: 130))
        #expect(anyPixel(out, xs: 105...155, ys: 150...166, where: isRed),
                "the baked pill draws caliper-colored ink at the head")
    }

    @Test func theHeadLineIsCutForTheChipButThePillFillsTheGap() {
        // The head line is split around the chip so a translucent pill never
        // reveals a stroke behind it — and the pill itself closes the gap.
        let transparentChip = MeasureContent(start: CGPoint(x: 20, y: 60), end: CGPoint(x: 220, y: 60),
                                             headOffset: 28, mode: .horizontal, strokeWidth: 6,
                                             strokeColorHex: "#FF0000", chipOpacity: 0)
        let img = MeasureRasterizer.rasterize(transparentChip, size: CGSize(width: 240, height: 120),
                                              pixelScale: 1)!
        // Probe the chip's padding band (clear of the centered readout).
        let gap = chipFillProbe(chipWidth: chipWidth(for: transparentChip))
        #expect(pixel(img, x: gap.x, y: gap.y).a == 0, "a fully transparent chip leaves the gap empty")
        #expect(isRed(pixel(img, x: 40, y: 88)), "the head line still strokes outside the gap")

        let filled = MeasureRasterizer.rasterize(
            MeasureContent(start: CGPoint(x: 20, y: 60), end: CGPoint(x: 220, y: 60),
                           headOffset: 28, mode: .horizontal, strokeWidth: 6,
                           strokeColorHex: "#FF0000"),
            size: CGSize(width: 240, height: 120), pixelScale: 1)!
        #expect(pixel(filled, x: 120, y: 88).a > 0, "the pill fills the head gap")
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
                           headOffset: 28, mode: .horizontal, strokeWidth: 6,
                           strokeColorHex: "#FF0000", textColorHex: "#FF0000"),
            size: CGSize(width: 240, height: 120), pixelScale: 1)!
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

    // MARK: The caliper is ONE object

    /// The measure layer plus a style, composited over the white base.
    private func render(_ content: MeasureContent, from: CGPoint, to: CGPoint,
                        style: LayerStyle, interactive: Bool = false) -> CGImage {
        let store = ImageStore()
        let base = store.register(solidImage(width: 300, height: 300, r: 255, g: 255, b: 255))
        var doc = PhotonzDocument.withBaseImage(base)
        var layer = MeasureBuilder.layer(content: content, from: from, to: to)
        layer.style = style
        doc.addLayer(layer)
        let renderer = DocumentRenderer()
        return (interactive ? renderer.renderInteractive(doc, store: store)
                            : renderer.render(doc, store: store))!
    }

    private func opaqueChipCaliper() -> MeasureContent {
        MeasureContent(mode: .horizontal, strokeWidth: 6, strokeColorHex: "#FF0000",
                       chipColorHex: "#0000FF", chipOpacity: 1, textColorHex: "#00FF00")
    }

    @Test func layerOpacityFadesTheChipToo() {
        // The Effects panel's opacity is an OBJECT-level setting: it must fade
        // the chip exactly as much as it fades the legs, not leave a solid pill
        // floating over a ghosted caliper.
        let solid = render(opaqueChipCaliper(), from: CGPoint(x: 20, y: 130),
                           to: CGPoint(x: 240, y: 130), style: LayerStyle())
        let faded = render(opaqueChipCaliper(), from: CGPoint(x: 20, y: 130),
                           to: CGPoint(x: 240, y: 130), style: LayerStyle(opacity: 0.4))
        let probe = chipFillProbe(chipWidth: chipWidth(for: opaqueChipCaliper()), centerX: 130, centerY: 158)
        let s = pixel(solid, x: probe.x, y: probe.y)
        let f = pixel(faded, x: probe.x, y: probe.y)
        #expect(s.b > 200 && s.r < 60, "the chip is solid blue at full opacity")
        // Faded over white: blue stays dominant but the pill washes out.
        #expect(Int(f.r) > Int(s.r) + 60 && f.b > 150,
                "40% layer opacity must wash the chip out too (solid r=\(s.r), faded r=\(f.r))")
    }

    @Test func theInteractiveCanvasShowsTheSameChipTheExportBakes() {
        // The canvas used to omit the pill and paint an AppKit overlay on top —
        // which no layer style could reach. One raster now serves both.
        let content = opaqueChipCaliper()
        let interactive = render(content, from: CGPoint(x: 20, y: 130), to: CGPoint(x: 240, y: 130),
                                 style: LayerStyle(), interactive: true)
        let exported = render(content, from: CGPoint(x: 20, y: 130), to: CGPoint(x: 240, y: 130),
                              style: LayerStyle())
        let probe = chipFillProbe(chipWidth: chipWidth(for: content), centerX: 130, centerY: 158)
        let live = pixel(interactive, x: probe.x, y: probe.y)
        let baked = pixel(exported, x: probe.x, y: probe.y)
        #expect(live.b > 200 && live.r < 60, "the interactive composite carries the chip")
        #expect(live.r == baked.r && live.g == baked.g && live.b == baked.b,
                "live and baked must be the same pixels")
    }

    // MARK: Three independent colors (stroke / chip fill / text)

    /// A 240×120 caliper whose feet run at y=60 (x 20..220), head +28 below at
    /// y=88 — the chip centers at (120, 88). Hairline stroke so the chip border
    /// stays out of the fill probe.
    private func colored(stroke: String, chip: String, chipOpacity: CGFloat,
                         text: String) -> CGImage {
        MeasureRasterizer.rasterize(
            MeasureContent(start: CGPoint(x: 20, y: 60), end: CGPoint(x: 220, y: 60),
                           headOffset: 28, mode: .horizontal, strokeWidth: 1,
                           strokeColorHex: stroke, chipColorHex: chip,
                           chipOpacity: chipOpacity, textColorHex: text),
            size: CGSize(width: 240, height: 120), pixelScale: 1)!
    }

    /// A point inside the pill's fill but clear of the centered text: the left
    /// padding band on the chip's vertical center line.
    private func chipFillProbe(chipWidth: CGFloat, centerX: CGFloat = 120,
                               centerY: Int = 88) -> (x: Int, y: Int) {
        (x: Int((centerX - chipWidth / 2 + 4).rounded()), y: centerY)
    }

    private func chipWidth(for content: MeasureContent) -> CGFloat {
        // Same footprint the rasterizer measures: text + padding on all sides.
        let text = TextContent(string: content.label(pixelScale: 1), fontName: "SF Pro",
                               fontSize: content.labelPointSize)
        return TextRasterizer.naturalSize(text).width + 2 * content.labelPadding
    }

    private var probeContent: MeasureContent {
        MeasureContent(start: CGPoint(x: 20, y: 60), end: CGPoint(x: 220, y: 60),
                       headOffset: 28, mode: .horizontal, strokeWidth: 1)
    }

    @Test func chipFillUsesItsOwnColorNotTheStroke() {
        let img = colored(stroke: "#FF0000", chip: "#0000FF", chipOpacity: 1, text: "#00FF00")
        let probe = chipFillProbe(chipWidth: chipWidth(for: probeContent))
        let p = pixel(img, x: probe.x, y: probe.y)
        #expect(p.b > 200 && p.r < 80 && p.g < 80 && p.a > 250, "the pill fills with the chip color")
        // The hairline leg is antialiased (partial coverage), so match its HUE
        // rather than a solid-red threshold.
        #expect(anyPixel(img, xs: 18...22, ys: 70...80, where: isRedInk),
                "the leg keeps the stroke color")
    }

    @Test func chipOpacityZeroLeavesThePillFillFullyTransparent() {
        let img = colored(stroke: "#FF0000", chip: "#0000FF", chipOpacity: 0, text: "#00FF00")
        let probe = chipFillProbe(chipWidth: chipWidth(for: probeContent))
        #expect(pixel(img, x: probe.x, y: probe.y).a == 0, "a 0-opacity chip paints nothing")
        // The readout and the caliper itself must survive a transparent chip.
        #expect(anyPixel(img, xs: 100...140, ys: 78...98,
                         where: { $0.g > 200 && $0.r < 80 && $0.b < 80 }),
                "the text still draws over a transparent chip")
        // The hairline leg is antialiased (partial coverage), so match its HUE
        // rather than a solid-red threshold.
        #expect(anyPixel(img, xs: 18...22, ys: 70...80, where: isRedInk),
                "the leg keeps the stroke color")
    }

    @Test func chipOpacityBlendsBetweenZeroAndOne() {
        let img = colored(stroke: "#FF0000", chip: "#0000FF", chipOpacity: 0.5, text: "#00FF00")
        let probe = chipFillProbe(chipWidth: chipWidth(for: probeContent))
        let a = pixel(img, x: probe.x, y: probe.y).a
        #expect(a > 100 && a < 160, "a half-opacity chip is half transparent (got \(a))")
    }

    @Test func textUsesItsOwnColorNotTheStrokeOrChip() {
        let img = colored(stroke: "#FF0000", chip: "#0000FF", chipOpacity: 1, text: "#00FF00")
        #expect(anyPixel(img, xs: 100...140, ys: 80...96,
                         where: { $0.g > 180 && $0.r < 90 && $0.b < 90 }),
                "the readout draws in the text color")
    }

    @Test func chipBorderFollowsTheStrokeColor() {
        // Border at full strength (see MeasureRasterizer.drawPill): the chip
        // outline reads as one continuous line with the head line it sits in.
        // Rendered over a transparent chip so the probe sees the border alone.
        var content = probeContent
        content.strokeWidth = 3
        content.strokeColorHex = "#FF0000"
        content.chipOpacity = 0
        content.textColorHex = "#00FF00"
        let img = MeasureRasterizer.rasterize(content, size: CGSize(width: 240, height: 120),
                                              pixelScale: 1)!
        let half = chipWidth(for: content) / 2
        #expect(anyPixel(img, xs: Int((120 - half - 1).rounded())...Int((120 - half + 1).rounded()),
                         ys: 86...90, where: isRed),
                "the pill border is stroked in the stroke color")
    }

    @Test func retinaScaleStillRendersAPill() {
        let out = render(content(mode: .horizontal), from: CGPoint(x: 20, y: 130),
                         to: CGPoint(x: 220, y: 130), pixelScale: 2)
        #expect(anyPixel(out, xs: 100...160, ys: 150...166, where: isRed),
                "the baked pill still renders under a Retina pixelScale")
    }
}
