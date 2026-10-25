import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PhotonzCore
@testable import PhotonzRender

/// Writes the oil paint sheet the audit shows: rows of strokes on white paper
/// by the real rasterizer, one row per setting, beside the plain round, a close
/// look at the bristles, and the measured bars. Only when asked:
/// `PHOTONZ_STROKE_SHEET=/some/dir Scripts/test.sh --filter OilSheet`.
@Suite("Oil paint sheet")
struct OilSheetTests {

    private static let folder = ProcessInfo.processInfo.environment["PHOTONZ_STROKE_SHEET"]
    private let scale: CGFloat = 2
    private static let blue = "#2050C8", red = "#D02818", yellow = "#F2C230", white = "#F4F1E8",
                        green = "#2E8A4A", umber = "#6B3E1E"

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

    private func s(_ samples: [StrokeSample], _ values: [String: Double] = [:], hex: String,
                   seed: UInt32) -> BrushStroke {
        BrushStroke(samples: samples, settings: BrushSettings(medium: .oil, values: values),
                    colorHex: hex, seed: seed)
    }

    private func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> [StrokeSample] {
        path([CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y1)])
    }

    /// Red down, then blue across, at three Smears.
    private func crossings() -> [BrushStroke] {
        var out: [BrushStroke] = []
        for (i, smear) in [0.0, 40, 100].enumerated() {
            let x = CGFloat(i) * 330
            out.append(s(line(x + 90, 10, x + 90, 115), ["size": 30], hex: Self.red, seed: UInt32(10 + i)))
            out.append(s(line(x + 20, 62, x + 310, 62), ["smear": smear], hex: Self.blue, seed: UInt32(20 + i)))
        }
        return out
    }

    private func rows() -> [(String, [BrushStroke])] {
        let blue = Self.blue, red = Self.red, yellow = Self.yellow, green = Self.green
        return [
            ("Oil paint at its defaults", [
                s(path(wave(64, from: 40, to: 330, amplitude: 24)), hex: blue, seed: 1),
                s(line(400, 40, 640, 50), hex: yellow, seed: 2),
                s(line(420, 95, 620, 20), hex: red, seed: 3),
                s(line(720, 30, 960, 30), ["size": 40], hex: green, seed: 4),
                s(line(720, 85, 960, 85), ["size": 12], hex: Self.umber, seed: 5),
            ]),
            ("Smear 0, 40, 100", crossings()),
            ("Load 20, 70, 100", [
                s(line(30, 25, 970, 25), ["load": 20], hex: Self.umber, seed: 30),
                s(line(30, 62, 970, 62), hex: Self.umber, seed: 31),
                s(line(30, 99, 970, 99), ["load": 100], hex: Self.umber, seed: 32),
            ]),
            ("Mixing on the canvas", [
                s(line(40, 40, 300, 40), ["size": 36], hex: yellow, seed: 40),
                s(line(40, 85, 300, 85), ["size": 36], hex: blue, seed: 41),
                s(path(wave(62, from: 50, to: 290, amplitude: 30)), ["size": 30, "smear": 70], hex: Self.white,
                  seed: 42),
                s(line(380, 20, 380, 110), ["size": 34], hex: red, seed: 43),
                s(line(450, 20, 450, 110), ["size": 34], hex: yellow, seed: 44),
                s(line(520, 20, 520, 110), ["size": 34], hex: blue, seed: 45),
                s(line(340, 50, 640, 50), ["size": 26, "smear": 60], hex: Self.white, seed: 46),
                s(line(640, 85, 340, 85), ["size": 26, "smear": 60, "load": 10], hex: Self.white, seed: 47),
                s(path([CGPoint(x: 700, y: 30), CGPoint(x: 960, y: 30), CGPoint(x: 700, y: 60),
                        CGPoint(x: 960, y: 60), CGPoint(x: 700, y: 90), CGPoint(x: 960, y: 90)]),
                  ["size": 28], hex: green, seed: 48),
            ]),
            ("Round tip", PaintRasterizer.$plainRound.withValue(true) { crossings() }),
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
                let round = index == rows.count - 1
                let raster = try #require(PaintRasterizer.$plainRound.withValue(round) {
                    PaintRasterizer.rasterize(PaintContent(strokes: row.1),
                                              size: CGSize(width: width, height: rowHeight), scale: scale)
                })
                let top = CGFloat(index) * rowHeight
                context.draw(raster, in: CGRect(x: 0, y: (size.height - top - rowHeight) * scale,
                                                width: width * scale, height: rowHeight * scale))
                if labelled { draw(row.0, at: CGPoint(x: 12 * scale, y: (size.height - top - 18) * scale), in: context) }
            }
            try write(try #require(context.makeImage()),
                      to: labelled ? "oil-sheet-labelled.png" : "oil-sheet.png", in: folder)
        }
        // A close look: a crossing at four times, where the bristles show.
        let close = CGSize(width: 220, height: 130)
        let strokes = [s(line(80, 10, 80, 120), ["size": 30], hex: Self.red, seed: 60),
                       s(line(15, 65, 210, 65), hex: Self.blue, seed: 61)]
        let raster = try #require(PaintRasterizer.rasterize(PaintContent(strokes: strokes), size: close, scale: 4))
        let paper = try #require(CGContext(
            data: nil, width: raster.width, height: raster.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        paper.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        paper.fill(CGRect(x: 0, y: 0, width: raster.width, height: raster.height))
        paper.draw(raster, in: CGRect(x: 0, y: 0, width: raster.width, height: raster.height))
        try write(try #require(paper.makeImage()), to: "oil-close.png", in: folder)
        try measures().write(toFile: folder + "/oil-measures.txt", atomically: true, encoding: .utf8)
    }

    private func write(_ image: CGImage, to name: String, in folder: String) throws {
        let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString,
                                                                       1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    /// The measured bars, oil against the plain round, and how the settings
    /// move them.
    private func measures() throws -> String {
        let box = CGSize(width: 320, height: 200)
        let a = CGPoint(x: 30, y: 100), b = CGPoint(x: 290, y: 100)
        func render(_ strokes: [BrushStroke], round: Bool = false, size: CGSize? = nil) throws -> CGImage {
            try #require(PaintRasterizer.$plainRound.withValue(round) {
                PaintRasterizer.rasterize(PaintContent(strokes: strokes), size: size ?? box, scale: scale)
            })
        }
        func crossing(_ values: [String: Double]) -> [BrushStroke] {
            [s(line(110, 20, 110, 180), ["size": 30], hex: Self.red, seed: 1),
             s(path([a, b]), ["size": 24].merging(values) { $1 }, hex: Self.blue, seed: 2)]
        }
        func carried(_ image: CGImage) -> Double {
            PaintMeasures.carriedShare(image, from: a, to: b, diameter: 24, scale: scale,
                                       own: RGBA(hex: Self.blue)!, foreign: RGBA(hex: Self.red)!,
                                       start: 97, end: 143)
        }
        var out = ["Bars at defaults, Size 24, 2x, mouse press."]
        for round in [false, true] {
            let label = round ? "Round tip" : "Oil paint"
            let ridges = PaintMeasures.ridgeContrast(try render([s(path([a, b]), ["size": 24], hex: Self.blue,
                                                                   seed: 3)], round: round),
                                                     from: a, to: b, diameter: 24, scale: scale)
            let carry = carried(try render(crossing([:]), round: round))
            out.append(String(format: "%@\tridge contrast %.3f (bar %.3f: %@), colour carried past a crossing %.3f (bar %.2f: %@)",
                              label, ridges, PaintMeasures.oilRidgeBar,
                              ridges >= PaintMeasures.oilRidgeBar ? "passes" : "fails", carry,
                              PaintMeasures.oilCarryBar, carry >= PaintMeasures.oilCarryBar ? "passes" : "fails"))
        }
        for smear in [0.0, 20, 40, 70, 100] {
            out.append(String(format: "Smear %.0f\tcarried %.3f", smear, carried(try render(crossing(["smear": smear])))))
        }
        let wide = CGSize(width: 900, height: 80)
        let from = CGPoint(x: 20, y: 40), to = CGPoint(x: 880, y: 40)
        for load in [0.0, 20, 50, 70, 100] {
            let image = try render([s(path([from, to]), ["size": 16, "load": load], hex: Self.umber, seed: 4)],
                                   size: wide)
            let reach = PaintMeasures.reachBeforeDry(image, from: from, to: to, diameter: 16, scale: scale)
            out.append(String(format: "Load %.0f\tcovers %.0f pt (%.1f brush widths) before running dry", load, reach,
                              reach / 16))
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
