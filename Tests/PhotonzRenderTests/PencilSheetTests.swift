import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PhotonzCore
@testable import PhotonzRender

/// Writes the pencil's sheets for the audit: one per setting (Hardness, Grain,
/// Tilt Shading) and one of pressure, each a row of real strokes on paper, plus
/// the blind sheet (an unlabelled row per dry medium and the round tip, in an
/// order written to a key beside it). Only when asked:
/// `PHOTONZ_PENCIL_SHEET=/some/dir Scripts/test.sh --filter PencilSheet`.
@Suite("Pencil sheet")
struct PencilSheetTests {

    private static let folder = ProcessInfo.processInfo.environment["PHOTONZ_PENCIL_SHEET"]
    private let scale: CGFloat = 2
    private let width: CGFloat = 900
    private let rowHeight: CGFloat = 110

    private func brush(_ medium: BrushMedium, _ set: [String: Double] = [:]) -> BrushSettings {
        BrushSettings(medium: medium, values: set)
    }

    /// A gentle wave across the row, a mouse unless `pressure` or `tilt`.
    private func wave(_ y: CGFloat, from x0: CGFloat, to x1: CGFloat, _ settings: BrushSettings,
                      pressure: ((CGFloat) -> Double)? = nil, tilt: CGPoint? = nil,
                      seed: UInt32 = 7) -> BrushStroke {
        let samples = (0...60).map { i -> StrokeSample in
            let t = CGFloat(i) / 60
            return StrokeSample(point: CGPoint(x: x0 + (x1 - x0) * t, y: y + sin(t * .pi * 2) * 10),
                                pressure: pressure?(t), tilt: tilt, ms: Double(i) * 14)
        }
        return BrushStroke(samples: samples, settings: settings, colorHex: "#000000", seed: seed)
    }

    /// Back-and-forth hatching over a patch, the way a hand shades.
    private func hatch(_ rect: CGRect, _ settings: BrushSettings, pressure: Double? = nil, tilt: CGPoint? = nil,
                       seed: UInt32 = 9) -> BrushStroke {
        let turns = 26
        var samples: [StrokeSample] = []
        for k in 0...turns * 4 {
            let t = CGFloat(k) / CGFloat(turns * 4)
            let up = (k / 4) % 2 == 0
            let phase = CGFloat(k % 4) / 4
            let y = up ? rect.maxY - phase * rect.height : rect.minY + phase * rect.height
            samples.append(StrokeSample(point: CGPoint(x: rect.minX + t * rect.width, y: y),
                                        pressure: pressure, tilt: tilt, ms: Double(k) * 18))
        }
        return BrushStroke(samples: samples, settings: settings, colorHex: "#000000", seed: seed)
    }

    private func write(_ name: String, rows: [(label: String, strokes: [BrushStroke])],
                       labelled: Bool = true) throws {
        let folder = try #require(Self.folder)
        let size = CGSize(width: width, height: rowHeight * CGFloat(rows.count))
        let context = try #require(CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.98, green: 0.97, blue: 0.95, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
        for (index, row) in rows.enumerated() {
            let raster = try #require(PaintRasterizer.rasterize(
                PaintContent(strokes: row.strokes), size: CGSize(width: width, height: rowHeight), scale: scale))
            let top = CGFloat(index) * rowHeight
            context.draw(raster, in: CGRect(x: 0, y: (size.height - top - rowHeight) * scale,
                                            width: width * scale, height: rowHeight * scale))
            if labelled {
                draw(row.label, at: CGPoint(x: 12 * scale, y: (size.height - top - 20) * scale), in: context)
            }
        }
        let image = try #require(context.makeImage())
        let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL,
                                                                       UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    @Test(.enabled(if: folder != nil))
    func writeSheets() throws {
        let folder = try #require(Self.folder)
        let grades = BrushMedium.pencilGrades
        // Hardness: a line, a hard-pressed line and a hatched patch per grade.
        try write("pencil-hardness.png", rows: grades.enumerated().map { index, grade in
            let b = brush(.pencil, ["hardness": Double(index)])
            return (grade, [wave(55, from: 70, to: 420, b),
                            wave(55, from: 450, to: 650, b, pressure: { _ in 1 }),
                            hatch(CGRect(x: 690, y: 20, width: 180, height: 70), b, seed: UInt32(index + 3))])
        })
        try write("pencil-grain.png", rows: [0.0, 50, 100].map { grain in
            let b = brush(.pencil, ["grain": grain, "size": 6, "hardness": 4])
            return ("Grain \(Int(grain))", [wave(55, from: 110, to: 520, b),
                                            hatch(CGRect(x: 600, y: 20, width: 260, height: 70), b)])
        })
        // Tilt Shading: the same leaning pen shading a patch, more each row.
        try write("pencil-tilt.png", rows: [0.0, 30, 60, 100].map { tilt in
            let b = brush(.pencil, ["tilt": tilt, "hardness": 3])
            let lean = CGPoint(x: 0.55, y: 0.35)
            return ("Tilt Shading \(Int(tilt))", [
                wave(55, from: 170, to: 470, b, pressure: { _ in 0.6 }, tilt: lean),
                hatch(CGRect(x: 520, y: 22, width: 340, height: 66), b, pressure: 0.6, tilt: lean),
            ])
        })
        // Pressure: a pen pressing from nothing to hard, then a mouse.
        let hb = brush(.pencil)
        try write("pencil-pressure.png", rows: [
            ("Pen, light to hard", [wave(55, from: 200, to: 860, hb, pressure: { 0.08 + 0.92 * Double($0) })]),
            ("Pen, light", [wave(55, from: 200, to: 860, hb, pressure: { _ in 0.2 })]),
            ("Pen, hard", [wave(55, from: 200, to: 860, hb, pressure: { _ in 1 })]),
            ("Mouse", [wave(55, from: 200, to: 860, hb)]),
        ])
        // The blind sheet: the same marks in each medium, unlabelled, in a
        // fixed shuffle. Each at its own default size.
        let media: [(String, BrushMedium)] = [("crayon", .crayon), ("pencil", .pencil), ("round tip", .marker),
                                              ("charcoal", .charcoal), ("chalk", .chalk)]
        try write("pencil-blind.png", rows: media.map { name, medium in
            let b = BrushSettings(medium: medium)
            return (name, [wave(55, from: 40, to: 420, b),
                           hatch(CGRect(x: 470, y: 18, width: 400, height: 74), b)])
        }, labelled: false)
        try media.enumerated().map { "row \($0 + 1): \($1.0)" }.joined(separator: "\n")
            .write(toFile: folder + "/pencil-blind-key.txt", atomically: true, encoding: .utf8)
        try measures().write(toFile: folder + "/pencil-measures.txt", atomically: true, encoding: .utf8)
    }

    /// The measured bars, read off straight strokes, pencil against the round tip.
    private func measures() throws -> String {
        let a = CGPoint(x: 30, y: 60), b = CGPoint(x: 270, y: 60)
        let box = CGSize(width: 300, height: 120)
        func line(_ medium: BrushMedium, _ set: [String: Double], pressure: Double? = nil,
                  tilt: CGPoint? = nil) throws -> CGImage {
            let samples = (0...24).map { i in
                StrokeSample(point: CGPoint(x: a.x + (b.x - a.x) * CGFloat(i) / 24, y: a.y),
                             pressure: pressure, tilt: tilt, ms: Double(i) * 30)
            }
            let s = BrushStroke(samples: samples, settings: BrushSettings(medium: medium, values: ["size": 4].merging(set) { $1 }),
                                colorHex: "#000000", seed: 5)
            return try #require(PaintRasterizer.rasterize(PaintContent(strokes: [s]), size: box, scale: scale))
        }
        var out: [String] = ["Straight strokes at Size 4, 2x, mouse press unless said."]
        for medium in [BrushMedium.pencil, .marker] {
            let label = medium == .pencil ? "Pencil" : "Round tip"
            for (index, grade) in BrushMedium.pencilGrades.enumerated() {
                let p = PaintMeasures.lineProfile(try line(medium, ["hardness": Double(index)]), from: a, to: b,
                                                  reach: 30, scale: scale)
                out.append(String(format: "%@ %@\twidth %.2f pt\tdarkness %.2f", label, grade, p.width, p.darkness))
            }
            for press in [0.2, 0.6, 1.0] {
                let image = try line(medium, [:], pressure: press)
                let p = PaintMeasures.lineProfile(image, from: a, to: b, reach: 30, scale: scale)
                let tooth = PaintMeasures.interiorGapFraction(image, from: a, to: b, diameter: max(1, p.width),
                                                              scale: scale)
                out.append(String(format: "%@ HB pen pressure %.1f\twidth %.2f pt\tdarkness %.2f\ttooth showing %.2f",
                                  label, press, p.width, p.darkness, tooth))
            }
            let leaning = try line(medium, [:], pressure: 0.6, tilt: CGPoint(x: 0, y: 0.7))
            let p = PaintMeasures.lineProfile(leaning, from: a, to: b, reach: 30, scale: scale)
            out.append(String(format: "%@ HB pen leaning 0.7\twidth %.2f pt\tdarkness %.2f", label, p.width, p.darkness))
        }
        out.append(String(format: "Bars: 8B at least %.1fx the width and %.1fx the darkness of 2H; tooth showing at pressure 0.2 at least %.2f",
                          PaintMeasures.pencilGradeWidthBar, PaintMeasures.pencilGradeDarknessBar,
                          PaintMeasures.pencilLightToothBar))
        return out.joined(separator: "\n")
    }

    private func draw(_ text: String, at point: CGPoint, in context: CGContext) {
        let font = CTFontCreateWithName("Helvetica" as CFString, 20, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(srgbRed: 0.4, green: 0.1, blue: 0.1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
