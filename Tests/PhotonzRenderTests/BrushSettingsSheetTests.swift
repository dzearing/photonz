import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PhotonzCore
@testable import PhotonzRender

/// Writes the sheet the per-brush settings audit shows: for every brush, a row
/// per setting it declares, the same stroke painted at the low end, the
/// default and the high end, so each setting is seen to change the stroke.
/// Only when asked:
/// `PHOTONZ_STROKE_SHEET=/some/dir Scripts/test.sh --filter BrushSettingsSheet`.
@Suite("Brush settings sheet")
struct BrushSettingsSheetTests {

    private static let folder = ProcessInfo.processInfo.environment["PHOTONZ_STROKE_SHEET"]
    private let scale: CGFloat = 2
    private let ink = "#24324A"
    private let rowHeight: CGFloat = 110
    private let width: CGFloat = 1100

    /// A gentle wave from `x0` to `x1`, at a brisk hand's speed.
    /// `tilt` leans the pen the whole way; `hold` stops half way for a
    /// second with the button down.
    private func wave(_ x0: CGFloat, _ x1: CGFloat, y: CGFloat, tilt: CGPoint? = nil,
                      hold: Bool = false) -> [StrokeSample] {
        var out: [StrokeSample] = []
        var ms = 0.0
        for i in 0...40 {
            let t = CGFloat(i) / 40
            out.append(StrokeSample(point: CGPoint(x: x0 + (x1 - x0) * t, y: y + sin(t * .pi * 2) * 14),
                                    tilt: tilt, ms: ms))
            ms += 12
            if hold, i == 20 {
                for _ in 0..<33 {
                    ms += 30
                    out.append(StrokeSample(point: out[out.count - 1].point, tilt: tilt, ms: ms))
                }
            }
        }
        return out
    }

    /// The values a setting is shown at: its low end, its default, its high
    /// end. Size stops at a size a row can hold.
    private func values(_ spec: BrushSettingSpec, medium: BrushMedium) -> [Double] {
        if spec.id == "size" {
            let size = BrushSettings(medium: medium).size
            return [max(1, (size / 3).rounded()), size, min(size * 2, 80)]
        }
        if spec.id == "opacity" { return [20, 60, 100] }
        if let options = spec.options {
            return options.count <= 3 ? options.indices.map(Double.init) : [0, spec.defaultValue, Double(options.count - 1)]
        }
        return [spec.range.lowerBound, spec.defaultValue, spec.range.upperBound]
    }

    @Test(.enabled(if: folder != nil))
    func writeSheets() throws {
        let folder = try #require(Self.folder)
        for medium in BrushMedium.allCases {
            var rows: [(String, [BrushStroke], [String])] = []
            for (index, spec) in medium.settings.enumerated() {
                let shown = values(spec, medium: medium)
                // A setting that acts only in its own situation is painted in
                // it: Tilt Shading with the pen leaning, Smear across red
                // paint already there, Build-up held still half way.
                let strokes = shown.enumerated().flatMap { column, value -> [BrushStroke] in
                    let x0 = 200 + CGFloat(column) * 300
                    var under: [BrushStroke] = []
                    if spec.id == "smear" {
                        under.append(BrushStroke(samples: (0...10).map {
                            StrokeSample(point: CGPoint(x: x0 + 100 + CGFloat($0) * 5, y: 12 + CGFloat($0) * 8.5),
                                         ms: Double($0) * 12)
                        }, settings: BrushSettings(medium: .oil), colorHex: "#D0302A", seed: 7))
                    }
                    return under + [BrushStroke(
                        samples: wave(x0, x0 + 240, y: rowHeight / 2,
                                      tilt: spec.id == "tilt" ? CGPoint(x: 0.7, y: 0.3) : nil,
                                      hold: spec.id == "buildup"),
                        settings: BrushSettings(medium: medium, values: [spec.id: value]),
                        colorHex: ink, seed: UInt32(1000 + index * 10 + column))]
                }
                rows.append((spec.name, strokes, shown.map { spec.reading($0) }))
            }
            try write(folder, "settings-\(medium.rawValue).png", title: medium.title, rows: rows)
        }
    }

    private func write(_ folder: String, _ name: String, title: String,
                       rows: [(String, [BrushStroke], [String])]) throws {
        let header: CGFloat = 34
        let size = CGSize(width: width, height: header + rowHeight * CGFloat(rows.count))
        let context = try #require(CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.98, green: 0.97, blue: 0.95, alpha: 1))
        context.fill(CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        label(title, at: CGPoint(x: 12, y: size.height - 24), in: context, size: 17)
        context.restoreGState()
        for (index, row) in rows.enumerated() {
            let raster = try #require(PaintRasterizer.rasterize(PaintContent(strokes: row.1),
                                                                size: CGSize(width: width, height: rowHeight),
                                                                scale: scale))
            let top = header + CGFloat(index) * rowHeight
            context.draw(raster, in: CGRect(x: 0, y: (size.height - top - rowHeight) * scale,
                                            width: width * scale, height: rowHeight * scale))
            context.saveGState()
            context.scaleBy(x: scale, y: scale)
            label(row.0, at: CGPoint(x: 12, y: size.height - top - rowHeight / 2 - 5), in: context, size: 14)
            for (column, reading) in row.2.enumerated() {
                label(reading, at: CGPoint(x: 200 + CGFloat(column) * 300, y: size.height - top - 16),
                      in: context, size: 11)
            }
            context.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.08))
            context.stroke(CGRect(x: 0, y: size.height - top - rowHeight, width: width, height: 0.5))
            context.restoreGState()
        }
        let url = URL(fileURLWithPath: folder + "/" + name)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString,
                                                                       1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func label(_ text: String, at point: CGPoint, in context: CGContext, size: CGFloat) {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(srgbRed: 0.45, green: 0.12, blue: 0.12, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
