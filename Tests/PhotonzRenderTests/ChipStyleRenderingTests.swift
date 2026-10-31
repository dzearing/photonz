import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PhotonzCore
@testable import PhotonzRender

/// The ten chip styles as they are really drawn: legible over any picture
/// (measured off the pixels), identical between the canvas and an export, and
/// (when asked) laid out on a sheet for the audit:
/// `PHOTONZ_CHIP_SHEET=/some/dir Scripts/test.sh --filter ChipStyleRendering`.
@Suite("Chip style rendering")
struct ChipStyleRenderingTests {

    private static let folder = ProcessInfo.processInfo.environment["PHOTONZ_CHIP_SHEET"]
    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    // MARK: Backdrops

    enum Backdrop: String, CaseIterable {
        case white, black, photo, saturated, lightUI, darkUI
    }

    /// A picture to put the chips on. The photo is busy on purpose: bright
    /// sky, dark foliage and saturated flowers in small patches, so whatever
    /// the chip lands on changes from pixel to pixel.
    static func backdrop(_ kind: Backdrop, size: CGSize) -> CGImage {
        let w = Int(size.width), h = Int(size.height)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func fill(_ hex: String, _ rect: CGRect) {
            let c = RGBA(hex: hex)!
            ctx.setFillColor(CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1))
            ctx.fill(rect)
        }
        let all = CGRect(x: 0, y: 0, width: w, height: h)
        switch kind {
        case .white: fill("#FFFFFF", all)
        case .black: fill("#000000", all)
        case .saturated: fill("#00C2FF", all)
        case .lightUI, .darkUI:
            let light = kind == .lightUI
            fill(light ? "#F5F5F7" : "#1E1E1F", all)
            var y = 12.0
            while y < Double(h) - 20 {
                fill(light ? "#FFFFFF" : "#2C2C2E", CGRect(x: 14, y: y, width: Double(w) - 28, height: 34))
                fill(light ? "#C7C7CC" : "#48484A", CGRect(x: 26, y: y + 12, width: Double(w) * 0.4, height: 10))
                fill(light ? "#0A84FF" : "#0A84FF", CGRect(x: Double(w) - 74, y: y + 9, width: 46, height: 16))
                y += 44
            }
        case .photo:
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(1 << 31)
            }
            let colours = ["#BFD9F2", "#F4E7D0", "#2E4A2B", "#4F7A3A", "#D94E6A", "#F2C14E", "#1B2430", "#8FA6B8", "#FFFFFF"]
            let cell = 7
            for gy in stride(from: 0, to: h, by: cell) {
                for gx in stride(from: 0, to: w, by: cell) {
                    let band = Double(gy) / Double(h)
                    let pick = Int((next() * 3 + band * 6)) % colours.count
                    fill(colours[pick], CGRect(x: gx, y: gy, width: cell, height: cell))
                }
            }
        }
        return ctx.makeImage()!
    }

    // MARK: Building a captioned arrow

    static func arrow(style: ChipStyle?, ink: String = "#ff375f", marker: ChipMarker = .accent,
                      caption: String = "Save button 48 pt", from: CGPoint = CGPoint(x: 262, y: 46),
                      to: CGPoint = CGPoint(x: 326, y: 46)) -> Layer {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: ink)
        content.caption = caption
        if let style { content.applyChipStyle(style) }
        content.chipMarker = marker
        return AnnotationBuilder.layer(content: content, from: from, to: to)
    }

    /// The chip's rectangle on the canvas, in points.
    static func chipRect(_ layer: Layer) -> CGRect {
        let a = layer.annotation!
        let size = CaptionMetrics.pillSize(for: a.caption ?? "", in: a)
        let c = a.captionPillCenter(forPillSize: size)
        return CGRect(x: layer.frame.minX + c.x - size.width / 2, y: layer.frame.minY + c.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    static func document(_ backdrop: Backdrop, _ layers: [Layer], store: ImageStore,
                         size: CGSize = CGSize(width: 340, height: 92)) -> PhotonzDocument {
        let ref = store.register(Self.backdrop(backdrop, size: size))
        var doc = PhotonzDocument(canvasSize: size, layers: [
            Layer(name: "Picture", content: .image(ref), frame: CGRect(origin: .zero, size: size), isLocked: true)
        ])
        for layer in layers { doc.addLayer(layer) }
        return doc
    }

    struct Pixels {
        var data: [UInt8]
        var width: Int
        var height: Int
        init(_ image: CGImage) {
            width = image.width
            height = image.height
            data = [UInt8](repeating: 0, count: width * height * 4)
            let ctx = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: ChipStyleRenderingTests.srgb,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        func at(_ x: Int, _ y: Int) -> RGBA {
            let i = (y * width + x) * 4
            return RGBA(r: Double(data[i]) / 255, g: Double(data[i + 1]) / 255, b: Double(data[i + 2]) / 255)
        }
    }

    /// The worst contrast between the words' colour and the plate right beside
    /// them: two points in the chip's trailing padding, one in the upper band
    /// the letters reach and one in the lower (on Highlighter, the swipe).
    static func measuredContrast(_ layer: Layer, in image: CGImage) -> Double {
        let a = layer.annotation!
        let rect = chipRect(layer)
        let px = Pixels(image)
        let pad = a.captionPadding
        let words = a.chipLook?.text ?? RGBA(hex: a.captionTextHex)!
        let points = [CGPoint(x: rect.maxX - pad * 0.6, y: rect.midY - rect.height * 0.25),
                      CGPoint(x: rect.maxX - pad * 0.8, y: rect.midY + rect.height * 0.2)]
        return points.map { InkPlate.contrast(words, px.at(Int($0.x), Int($0.y))) }.min() ?? 0
    }

    // MARK: Legibility, measured

    @Test("Every style's words read at 4.5:1 or better over white, black, a busy photo and a saturated colour")
    func legibleOverAnyPicture() throws {
        let store = ImageStore()
        for style in ChipStyle.allCases {
            for ink in InkPlate.palette {
                for backdrop in [Backdrop.white, .black, .photo, .saturated] {
                    let layer = Self.arrow(style: style, ink: ink)
                    let doc = Self.document(backdrop, [layer], store: store)
                    let image = try #require(DocumentRenderer().render(doc, store: store))
                    let ratio = Self.measuredContrast(layer, in: image)
                    #expect(ratio >= 4.5, "\(style) \(ink) over \(backdrop): \(String(format: "%.2f", ratio)):1")
                }
            }
        }
    }

    // MARK: Canvas and export agree

    /// Mean and worst channel difference over the chip, canvas against export.
    static func difference(_ layer: Layer, _ backdrop: Backdrop, store: ImageStore) -> (mean: Double, worst: Int)? {
        let doc = document(backdrop, [layer], store: store)
        guard let export = DocumentRenderer().render(doc, store: store),
              let canvas = DocumentRenderer().renderInteractive(doc, store: store) else { return nil }
        let a = Pixels(export), b = Pixels(canvas)
        let rect = chipRect(layer).insetBy(dx: -4, dy: -4).integral
        var total = 0, worst = 0, count = 0
        for y in max(0, Int(rect.minY))..<min(a.height, Int(rect.maxY)) {
            for x in max(0, Int(rect.minX))..<min(a.width, Int(rect.maxX)) {
                for c in 0..<3 {
                    let d = abs(Int(a.data[(y * a.width + x) * 4 + c]) - Int(b.data[(y * b.width + x) * 4 + c]))
                    total += d
                    worst = max(worst, d)
                    count += 1
                }
            }
        }
        return (Double(total) / Double(max(count, 1)), worst)
    }

    @Test("The exported chip matches the canvas's, style by style")
    func exportMatchesCanvas() throws {
        let store = ImageStore()
        for style in ChipStyle.allCases {
            let layer = Self.arrow(style: style, marker: style == .solid ? .warning : .accent)
            let diff = try #require(Self.difference(layer, .photo, store: store))
            #expect(diff.mean < 1.0, "\(style): mean \(diff.mean)")
            #expect(diff.worst <= 24, "\(style): worst \(diff.worst)")
        }
    }

    @Test("A styled chip is drawn differently from the old pill, and the old pill is untouched")
    func oldPillUntouched() throws {
        let store = ImageStore()
        let legacy = Self.arrow(style: nil)
        #expect(legacy.annotation?.chipStyle == nil)
        #expect(legacy.annotation?.chipLook == nil)
        let doc = Self.document(.white, [legacy], store: store)
        let image = try #require(DocumentRenderer().render(doc, store: store))
        let px = Pixels(image)
        let rect = Self.chipRect(legacy)
        // The old dark red plate, just inside the top padding.
        let plate = px.at(Int(rect.midX), Int(rect.minY + 5))
        #expect(plate.r > 0.4 && plate.r < 0.65 && plate.g < 0.25)
    }

    @Test("A marker draws its icon at the chip's front, in its meaning colour")
    func markerDraws() throws {
        let store = ImageStore()
        let layer = Self.arrow(style: .paper, ink: "#0a84ff", marker: .error)
        let doc = Self.document(.white, [layer], store: store)
        let image = try #require(DocumentRenderer().render(doc, store: store))
        let px = Pixels(image)
        let a = try #require(layer.annotation)
        let look = try #require(a.chipLook)
        let rect = Self.chipRect(layer)
        let icon = try #require(look.layout(in: rect, fontSize: a.captionFontSize, padding: a.captionPadding).icon)
        // The disc's rim, clear of the glyph: red.
        let p = px.at(Int(icon.midX), Int(icon.minY + icon.height * 0.12))
        #expect(p.r > 0.85 && p.g < 0.4 && p.b < 0.4, "\(p)")
    }

    // MARK: The audit's sheet

    @Test("Writes the style sheet, the marker sheet, the contrast table and the export comparison",
          .enabled(if: folder != nil))
    func writeSheets() throws {
        guard let folder = Self.folder else { return }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let store = ImageStore()
        let columns: [Backdrop] = [.lightUI, .darkUI, .photo]
        let rows: [(String, ChipStyle?)] = [("Baseline: the pill shipped today", nil)]
            + ChipStyle.allCases.map { ("\(ChipStyle.allCases.firstIndex(of: $0)! + 1). \($0.title)", $0) }
        try sheet(folder + "/chip-styles-sheet.png", rows: rows.map { row in
            (row.0, columns.map { column in
                (column, Self.arrow(style: row.1, ink: "#ff375f"))
            })
        }, store: store)
        // Every style in four inks, on the photo.
        try sheet(folder + "/chip-styles-inks.png", rows: ChipStyle.allCases.map { style in
            (style.title, ["#0a84ff", "#30d158", "#ffd60a", "#1d1d1f"].map { ink in
                (Backdrop.photo, Self.arrow(style: style, ink: ink, caption: "12 pt gap"))
            })
        }, store: store)
        // Markers.
        try sheet(folder + "/chip-markers.png", rows: ChipMarker.allCases.map { marker in
            (marker.title, [ChipStyle.solid, .paper, .twotone].map { style in
                (Backdrop.lightUI, Self.arrow(style: style, ink: "#0a84ff", marker: marker, caption: "Not aligned"))
            })
        }, store: store)

        // Contrast, measured off the pixels.
        var table = "style\tink\twhite\tblack\tphoto\tsaturated\tworst\n"
        for style in ChipStyle.allCases {
            for ink in InkPlate.palette {
                var cells: [Double] = []
                for backdrop in [Backdrop.white, .black, .photo, .saturated] {
                    let layer = Self.arrow(style: style, ink: ink)
                    let doc = Self.document(backdrop, [layer], store: store)
                    let image = try #require(DocumentRenderer().render(doc, store: store))
                    cells.append(Self.measuredContrast(layer, in: image))
                }
                table += "\(style.rawValue)\t\(ink)\t" + cells.map { String(format: "%.1f", $0) }.joined(separator: "\t")
                    + "\t" + String(format: "%.1f", cells.min() ?? 0) + "\n"
            }
        }
        var legacyRow = "baseline\t#ff375f\t"
        for backdrop in [Backdrop.white, .black, .photo, .saturated] {
            let layer = Self.arrow(style: nil)
            let image = try #require(DocumentRenderer().render(Self.document(backdrop, [layer], store: store), store: store))
            legacyRow += String(format: "%.1f\t", Self.measuredContrast(layer, in: image))
        }
        table += legacyRow + "\n"
        try table.write(toFile: folder + "/chip-contrast.tsv", atomically: true, encoding: .utf8)

        var parity = "style\tmean channel difference\tworst channel difference (of 255)\n"
        for style in ChipStyle.allCases {
            if let d = Self.difference(Self.arrow(style: style), .photo, store: store) {
                parity += "\(style.rawValue)\t\(String(format: "%.3f", d.mean))\t\(d.worst)\n"
            }
        }
        try parity.write(toFile: folder + "/chip-export-parity.tsv", atomically: true, encoding: .utf8)

        // Any colour: a custom light green and a custom indigo in every
        // style on a pure white, a pure black and a busy photo, read off the
        // pixels by the probe's own reader (`ChipContrastReader`).
        let custom = ["#7FD18B", "#3A2E8F"]
        let grounds: [Backdrop] = [.white, .black, .photo]
        try sheet(folder + "/chip-custom-inks.png", rows: ChipStyle.allCases.flatMap { style in
            custom.map { ink in
                ("\(style.title), \(ink)", grounds.map { ($0, Self.arrow(style: style, ink: ink)) })
            }
        }, store: store)
        var read = "style\tink\twhite\tblack\tphoto\tworst\n"
        for style in ChipStyle.allCases {
            for ink in custom {
                var cells: [Double] = []
                for ground in grounds {
                    let layer = Self.arrow(style: style, ink: ink)
                    let image = try #require(DocumentRenderer().render(Self.document(ground, [layer], store: store),
                                                                       store: store))
                    cells.append(ChipContrastReader.read(layer, in: image)?.contrast ?? 0)
                }
                read += "\(style.rawValue)\t\(ink)\t" + cells.map { String(format: "%.2f", $0) }.joined(separator: "\t")
                    + "\t" + String(format: "%.2f", cells.min() ?? 0) + "\n"
            }
        }
        try read.write(toFile: folder + "/chip-custom-inks.tsv", atomically: true, encoding: .utf8)
    }

    /// A grid of rendered cells, each a captioned arrow on a backdrop, with a
    /// label down the left.
    private func sheet(_ path: String, rows: [(String, [(Backdrop, Layer)])], store: ImageStore) throws {
        let cell = CGSize(width: 340, height: 92)
        let labelWidth: CGFloat = 230
        let scale: CGFloat = 2
        let columns = rows.first?.1.count ?? 0
        let w = Int((labelWidth + cell.width * CGFloat(columns)) * scale)
        let h = Int(cell.height * CGFloat(rows.count) * scale)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: Self.srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.97, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        for (r, row) in rows.enumerated() {
            let top = CGFloat(h) - CGFloat(r + 1) * cell.height * scale
            let label = NSAttributedStringLabel.line(row.0, size: 13 * scale)
            ctx.textPosition = CGPoint(x: 12 * scale, y: top + cell.height * scale / 2 - 4 * scale)
            CTLineDraw(label, ctx)
            for (c, entry) in row.1.enumerated() {
                let doc = Self.document(entry.0, [entry.1], store: store, size: cell)
                guard let image = DocumentRenderer().render(doc, store: store, scale: scale) else { continue }
                ctx.draw(image, in: CGRect(x: (labelWidth + CGFloat(c) * cell.width) * scale, y: top,
                                           width: cell.width * scale, height: cell.height * scale))
            }
        }
        let image = try #require(ctx.makeImage())
        let url = URL(fileURLWithPath: path) as CFURL
        let dest = try #require(CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
    }
}

private enum NSAttributedStringLabel {
    static func line(_ text: String, size: CGFloat) -> CTLine {
        let font = CTFontCreateUIFontForLanguage(.system, size, nil)!
        let attrs: [CFString: Any] = [kCTFontAttributeName: font,
                                      kCTForegroundColorAttributeName: CGColor(gray: 0.15, alpha: 1)]
        let string = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
        return CTLineCreateWithAttributedString(string)
    }
}
