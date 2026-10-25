import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PhotonzCore
@testable import PhotonzRender

/// Writes the watercolour sheets the audit shows: rows of strokes on white
/// paper by the real rasterizer, one row per setting, beside the round tip,
/// and the measured bars. Only when asked:
/// `PHOTONZ_STROKE_SHEET=/some/dir Scripts/test.sh --filter WatercolourSheet`.
@Suite("Watercolour sheet")
struct WatercolourSheetTests {

    private static let folder = ProcessInfo.processInfo.environment["PHOTONZ_STROKE_SHEET"]
    private let scale: CGFloat = 2

    private func path(_ points: [CGPoint], every ms: Double = 16) -> [StrokeSample] {
        var out: [StrokeSample] = []
        var t = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            let steps = max(2, Int(hypot(b.x - a.x, b.y - a.y) / 10))
            for i in 0..<steps {
                let f = CGFloat(i) / CGFloat(steps)
                out.append(StrokeSample(point: CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f), ms: t))
                t += ms
            }
        }
        if let last = points.last { out.append(StrokeSample(point: last, ms: t)) }
        return out
    }

    private func wave(_ y: CGFloat, from x0: CGFloat, to x1: CGFloat, amplitude: CGFloat) -> [CGPoint] {
        (0...24).map { i in
            let t = CGFloat(i) / 24
            return CGPoint(x: x0 + (x1 - x0) * t, y: y + sin(t * .pi * 2) * amplitude)
        }
    }

    private func s(_ medium: BrushMedium, _ samples: [StrokeSample], _ values: [String: Double] = [:],
                   hex: String, seed: UInt32, at time: Double? = nil) -> BrushStroke {
        BrushStroke(samples: samples, settings: BrushSettings(medium: medium, values: values),
                    colorHex: hex, seed: seed, startedAt: time)
    }

    /// Three short strokes side by side across a row, one per value of `id`.
    private func settingRow(_ id: String, _ values: [Double], hex: String, seed: UInt32) -> [BrushStroke] {
        values.enumerated().map { k, value in
            let x0 = 40 + CGFloat(k) * 320
            return s(.watercolour, path(wave(64, from: x0, to: x0 + 250, amplitude: 14)), [id: value],
                     hex: hex, seed: seed + UInt32(k))
        }
    }

    static let blue = "#2E6FC9", red = "#C8382E", ochre = "#C89A2E", green = "#2E8A5A", violet = "#6A3E9E"

    private func rows() -> [(String, [BrushStroke])] {
        let blue = Self.blue, red = Self.red, ochre = Self.ochre, green = Self.green, violet = Self.violet
        // Times: strokes far apart in seconds have dried before the next.
        return [
            ("Watercolour at its defaults", [
                s(.watercolour, path(wave(64, from: 40, to: 330, amplitude: 22)), hex: blue, seed: 1, at: 0),
                s(.watercolour, path([CGPoint(x: 400, y: 40), CGPoint(x: 640, y: 50)]), hex: ochre, seed: 2, at: 100),
                s(.watercolour, path([CGPoint(x: 420, y: 95), CGPoint(x: 620, y: 20)]), hex: red, seed: 3, at: 200),
                s(.watercolour, path([CGPoint(x: 720, y: 60), CGPoint(x: 960, y: 60)]), hex: green, seed: 4, at: 300),
                s(.watercolour, path([CGPoint(x: 840, y: 15), CGPoint(x: 840, y: 105)]), ["size": 16], hex: violet,
                  seed: 5, at: 301.5),
            ]),
            ("Wetness 0, 50, 100", settingRow("wetness", [0, 50, 100], hex: blue, seed: 10)),
            ("Bleed 0, 50, 100", settingRow("bleed", [0, 50, 100], hex: red, seed: 20)),
            ("Granulation 0, 50, 100", settingRow("granulation", [0, 50, 100], hex: violet, seed: 30)),
            ("Into a wet wash, a dry one, a glaze", [
                s(.watercolour, path([CGPoint(x: 40, y: 60), CGPoint(x: 290, y: 60)]), ["size": 44], hex: ochre,
                  seed: 40, at: 1000),
                s(.watercolour, path([CGPoint(x: 165, y: 15), CGPoint(x: 165, y: 105)]), ["size": 18], hex: red,
                  seed: 41, at: 1001),
                s(.watercolour, path([CGPoint(x: 360, y: 60), CGPoint(x: 610, y: 60)]), ["size": 44], hex: ochre,
                  seed: 42, at: 2000),
                s(.watercolour, path([CGPoint(x: 485, y: 15), CGPoint(x: 485, y: 105)]), ["size": 18], hex: red,
                  seed: 43, at: 2100),
                s(.watercolour, path([CGPoint(x: 680, y: 45), CGPoint(x: 960, y: 45)]), ["size": 36], hex: blue,
                  seed: 44, at: 3000),
                s(.watercolour, path([CGPoint(x: 680, y: 80), CGPoint(x: 960, y: 80)]), ["size": 36], hex: blue,
                  seed: 45, at: 3100),
            ]),
            ("Into a soaking wash, a damp one", [
                s(.watercolour, path([CGPoint(x: 40, y: 60), CGPoint(x: 440, y: 60)]), ["size": 50, "wetness": 90],
                  hex: Self.ochre, seed: 46, at: 4000),
                s(.watercolour, path([CGPoint(x: 140, y: 30), CGPoint(x: 150, y: 95)]), ["size": 16], hex: blue,
                  seed: 47, at: 4000.6),
                s(.watercolour, path([CGPoint(x: 330, y: 30), CGPoint(x: 340, y: 95)]), ["size": 16], hex: blue,
                  seed: 48, at: 4005),
                s(.watercolour, path([CGPoint(x: 520, y: 60), CGPoint(x: 960, y: 60)]), ["size": 50, "wetness": 90],
                  hex: green, seed: 49, at: 5000),
                s(.watercolour, path(wave(60, from: 560, to: 920, amplitude: 14)), ["size": 12], hex: red,
                  seed: 51, at: 5000.8),
            ]),
            ("Round tip", [
                s(.oil, path(wave(64, from: 40, to: 330, amplitude: 22)), ["size": 30, "opacity": 45], hex: blue,
                  seed: 50),
            ]),
        ]
    }

    @Test(.enabled(if: folder != nil))
    func writeSheet() throws {
        let folder = try #require(Self.folder)
        let rows = rows()
        let rowHeight: CGFloat = 125, width: CGFloat = 1000
        for labelled in [false, true] {
            let size = CGSize(width: width, height: rowHeight * CGFloat(rows.count))
            let context = try #require(CGContext(
                data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
            for (index, row) in rows.enumerated() {
                let raster = try #require(PaintRasterizer.rasterize(PaintContent(strokes: row.1),
                                                                    size: CGSize(width: width, height: rowHeight),
                                                                    scale: scale))
                let top = CGFloat(index) * rowHeight
                context.draw(raster, in: CGRect(x: 0, y: (size.height - top - rowHeight) * scale,
                                                width: width * scale, height: rowHeight * scale))
                if labelled { draw(row.0, at: CGPoint(x: 12 * scale, y: (size.height - top - 18) * scale), in: context) }
            }
            let image = try #require(context.makeImage())
            let url = URL(fileURLWithPath: folder)
                .appendingPathComponent(labelled ? "watercolour-sheet-labelled.png" : "watercolour-sheet.png")
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
        }
        try measures().write(toFile: folder + "/watercolour-measures.txt", atomically: true, encoding: .utf8)
    }

    /// The two measured bars, watercolour against the round tip, and what
    /// each setting does to them.
    private func measures() throws -> String {
        let box = CGSize(width: 300, height: 160)
        let a = CGPoint(x: 30, y: 80), b = CGPoint(x: 270, y: 80)
        func render(_ strokes: [BrushStroke]) throws -> CGImage {
            try #require(PaintRasterizer.rasterize(PaintContent(strokes: strokes), size: box, scale: scale))
        }
        func line(_ medium: BrushMedium, _ values: [String: Double]) throws -> (edge: Double, spread: Double) {
            let image = try render([s(medium, path([a, b]), ["size": 40].merging(values) { $1 }, hex: "#2060E0",
                                      seed: 4)])
            return (PaintMeasures.edgeToCentre(image, from: a, to: b, diameter: 40, scale: scale),
                    PaintMeasures.spreadPastPath(image, from: a, to: b, diameter: 40, scale: scale))
        }
        var out = ["Bars on a straight stroke at Size 40, 2x, mouse press."]
        for (label, medium, values) in [("Watercolour", BrushMedium.watercolour, [String: Double]()),
                                        ("Round tip", .oil, ["opacity": 50])] {
            let m = try line(medium, values)
            out.append(String(format: "%@\tedge to centre %.2f (bar %.2f: %@), spread past the path %.2f (bar %.2f: %@)",
                              label, m.edge, PaintMeasures.watercolourEdgeBar,
                              m.edge >= PaintMeasures.watercolourEdgeBar ? "passes" : "fails", m.spread,
                              PaintMeasures.watercolourSpreadBar,
                              m.spread >= PaintMeasures.watercolourSpreadBar ? "passes" : "fails"))
        }
        for id in ["wetness", "bleed", "granulation"] {
            for value in [0.0, 50, 100] {
                let m = try line(.watercolour, [id: value])
                out.append(String(format: "Watercolour %@ %.0f\tedge to centre %.2f, spread %.2f", id, value, m.edge,
                                  m.spread))
            }
        }
        return out.joined(separator: "\n")
    }

    private func draw(_ text: String, at point: CGPoint, in context: CGContext) {
        let font = CTFontCreateWithName("Helvetica" as CFString, 22, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(srgbRed: 0.4, green: 0.1, blue: 0.1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
