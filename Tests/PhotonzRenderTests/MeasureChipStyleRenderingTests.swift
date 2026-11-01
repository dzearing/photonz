import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A measurement's readout drawn in each of the ten chip styles, through the
/// same chip drawing an arrow's label uses (`ChipRasterizer`), read off the
/// pixels: the words read over any picture, and the caliper still meets the
/// chip's edge cleanly whatever its corners are.
@Suite("A measurement's chip is drawn in its style")
struct MeasureChipStyleRenderingTests {

    /// A Gap measurement across the middle of a 340 by 160 picture, its chip in
    /// `style`.
    static func gap(style: ChipStyle?, ink: String = "#3774D5", marker: ChipMarker = .accent,
                    span: CGFloat = 160, mode: MeasureMode = .horizontal) -> Layer {
        var c = MeasureStyles().content(for: .spacing)
        c.mode = mode
        c.strokeColorHex = ink
        if let style { c.applyChipStyle(style) }
        c.chipMarker = marker
        let start = mode == .horizontal ? CGPoint(x: 90, y: 50) : CGPoint(x: 60, y: 30)
        let end = mode == .horizontal ? CGPoint(x: 90 + span, y: 50) : CGPoint(x: 60, y: 30 + span)
        c.headOffset = MeasureBuilder.clearingHeadOffset(content: c, from: start, to: end)
        return MeasureBuilder.layer(content: c, from: start, to: end)
    }

    private func render(_ layer: Layer, on backdrop: ChipStyleRenderingTests.Backdrop) throws -> CGImage {
        let store = ImageStore()
        let doc = ChipStyleRenderingTests.document(backdrop, [layer], store: store,
                                                   size: CGSize(width: 340, height: 160))
        return try #require(DocumentRenderer().render(doc, store: store))
    }

    @Test("Every style keeps the words at 4.5:1 or better over white, black and a busy photo",
          arguments: ChipStyle.allCases)
    func everyStyleReads(style: ChipStyle) throws {
        for ink in ["#3774D5", "#FF375F", "#FFD60A", "#1D1D1F", "#7FD18B"] {
            for backdrop in [ChipStyleRenderingTests.Backdrop.white, .black, .photo] {
                let layer = Self.gap(style: style, ink: ink)
                let reading = try #require(ChipContrastReader.read(layer, in: try render(layer, on: backdrop)),
                                           "\(style) \(ink) over \(backdrop): no chip to read")
                // The audit's table is read off these lines.
                print("chip-contrast\t\(style.rawValue)\t\(ink)\t\(backdrop.rawValue)\t"
                      + String(format: "%.2f", reading.contrast))
                #expect(reading.contrast >= 4.5,
                        "\(style) \(ink) over \(backdrop): \(reading.words.hexString) on \(reading.plate.hexString) = \(reading.contrast)")
            }
        }
    }

    @Test("The words found are the words drawn")
    func findsTheWords() throws {
        let layer = Self.gap(style: .paper)
        let reading = try #require(ChipContrastReader.read(layer, in: try render(layer, on: .white)))
        let drawn = try #require(layer.measure?.chipLook?.text)
        #expect(InkPlate.contrast(reading.words, drawn) < 1.2)
    }

    @Test("Words painted by hand into the plate's own colour read as unreadable")
    func catchesABadPair() throws {
        var layer = Self.gap(style: .solid, ink: "#0A84FF")
        guard var m = layer.measure else { return }
        m.setChipPartByHand(.text, hex: "#4A90E2")
        layer.content = .measure(m)
        let reading = try #require(ChipContrastReader.read(layer, in: try render(layer, on: .white)))
        #expect(reading.contrast < 4.5)
    }

    @Test("A styled chip draws differently from the pill from before styles, and every style differently")
    func stylesAreDrawn() throws {
        var seen: [Data: ChipStyle?] = [:]
        for style in [nil] + ChipStyle.allCases.map(Optional.some) {
            let layer = Self.gap(style: style)
            let m = try #require(layer.measure)
            let image = try #require(MeasureRasterizer.rasterize(m, size: layer.frame.size, pixelScale: 1))
            let pixels = ChipStyleRenderingTests.Pixels(image)
            let data = Data(pixels.data)
            #expect(seen[data] == nil, "\(String(describing: style)) draws the same as \(String(describing: seen[data] ?? nil))")
            seen[data] = style
        }
    }

    @Test("A status marker draws its icon at the chip's front and the words move over for it")
    func markerDraws() throws {
        let plain = Self.gap(style: .paper, marker: .none)
        let warned = Self.gap(style: .paper, marker: .warning)
        let plainMeasure = try #require(plain.measure)
        let warnedMeasure = try #require(warned.measure)
        let a = try #require(MeasureRasterizer.chipRect(for: plainMeasure, pixelScale: 1))
        let b = try #require(MeasureRasterizer.chipRect(for: warnedMeasure, pixelScale: 1))
        #expect(b.width > a.width + 10, "the chip grows to hold the icon")
        // The icon's yellow is somewhere in the chip's front.
        let m = try #require(warned.measure)
        let image = try #require(MeasureRasterizer.rasterize(m, size: warned.frame.size, pixelScale: 1))
        let pixels = ChipStyleRenderingTests.Pixels(image)
        var yellow = 0
        for y in Int(b.minY)..<Int(b.maxY) {
            for x in Int(b.minX)..<Int(b.minX + b.height) {
                let p = pixels.at(x, y)
                if p.r > 0.9, p.g > 0.7, p.b < 0.3 { yellow += 1 }
            }
        }
        #expect(yellow > 20, "no warning icon at the chip's front")
    }

    // MARK: The line meets the chip

    /// The caliper's ink alone, as what changes between two drawings whose
    /// chips are pinned to the same colours by hand.
    private func caliperOnly(style: ChipStyle, span: CGFloat, mode: MeasureMode) throws
        -> (changed: (Int, Int) -> Bool, plate: CGPath, edge: CGFloat, size: CGSize) {
        func pinned(_ ink: String) -> Layer {
            var layer = Self.gap(style: style, ink: "#3774D5", marker: .none, span: span, mode: mode)
            guard var m = layer.measure else { return layer }
            let look = m
            m.setChipPartByHand(.fill, hex: look.chipFillHexWithAlpha)
            if look.hasChipBorder { m.setChipPartByHand(.edge, hex: look.chipBorderColorHex) }
            m.setChipPartByHand(.text, hex: look.textColorHex)
            m.strokeColorHex = ink
            layer.content = .measure(m)
            return layer
        }
        let red = pinned("#FF0000"), green = pinned("#00FF00")
        let m = try #require(red.measure)
        let size = red.frame.size
        let a = ChipStyleRenderingTests.Pixels(try #require(MeasureRasterizer.rasterize(m, size: size, pixelScale: 1)))
        let greenMeasure = try #require(green.measure)
        let b = ChipStyleRenderingTests.Pixels(try #require(
            MeasureRasterizer.rasterize(greenMeasure, size: size, pixelScale: 1)))
        let rect = try #require(MeasureRasterizer.chipRect(for: m, pixelScale: 1))
        let look = try #require(m.chipLook)
        let plate = ChipRasterizer.plate(look, at: CGPoint(x: rect.midX, y: rect.midY), chipSize: rect.size,
                                         cornerRadius: m.chipCornerRadius(for: rect.size)).path
        let changed: (Int, Int) -> Bool = { x, y in
            let p = a.at(x, y), q = b.at(x, y)
            return abs(p.r - q.r) + abs(p.g - q.g) + abs(p.b - q.b) + abs(p.a - q.a) > 0.12
        }
        return (changed, plate, m.hasChipBorder ? m.chipBorderWidth : 0, size)
    }

    /// Whether every point `depth` away from `p`, all round, is inside `path`.
    private func deep(_ p: CGPoint, _ depth: CGFloat, in path: CGPath) -> Bool {
        (0..<16).allSatisfy { i in
            let t = CGFloat(i) * .pi / 8
            return path.contains(CGPoint(x: p.x + depth * cos(t), y: p.y + depth * sin(t)))
        }
    }

    @Test("The caliper reaches the chip's edge and never shows inside it, in every style",
          arguments: ChipStyle.allCases)
    func lineMeetsTheEdge(style: ChipStyle) throws {
        for (mode, span) in [(MeasureMode.horizontal, CGFloat(160)), (.horizontal, 30), (.vertical, 110)] {
            let (changed, plate, edge, size) = try caliperOnly(style: style, span: span, mode: mode)
            var arrives = 0
            var inside: [(Int, Int)] = []
            for y in 0..<Int(size.height) {
                for x in 0..<Int(size.width) where changed(x, y) {
                    let p = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                    if !plate.contains(p), (0..<16).contains(where: { i in
                        let t = CGFloat(i) * .pi / 8
                        return plate.contains(CGPoint(x: p.x + 2 * cos(t), y: p.y + 2 * sin(t)))
                    }) {
                        arrives += 1
                    }
                    // The band just inside the edge, where a line running on
                    // would show. Deeper in, Highlighter's band is the ink on
                    // purpose.
                    if deep(p, max(2, edge / 2 + 1.5), in: plate), !deep(p, 4.5, in: plate) {
                        inside.append((x, y))
                    }
                }
            }
            #expect(arrives > 0, "\(style) \(mode) \(span): the caliper stops short of the chip")
            #expect(inside.isEmpty, "\(style) \(mode) \(span): the caliper shows inside the chip, first at \(inside.first ?? (0, 0))")
        }
    }

    // MARK: Glass

    @Test("A Glass readout frosts the picture behind it, in the export as on the canvas")
    func glassFrosts() throws {
        let layer = Self.gap(style: .glass)
        let m = try #require(layer.measure)
        #expect(MeasureRasterizer.frostMask(m, size: layer.frame.size, pixelScale: 1) != nil)
        let solid = try #require(Self.gap(style: .solid).measure)
        #expect(MeasureRasterizer.frostMask(solid, size: layer.frame.size, pixelScale: 1) == nil)
        let reading = try #require(ChipContrastReader.read(layer, in: try render(layer, on: .photo)))
        #expect(reading.contrast >= 4.5)
    }
}
