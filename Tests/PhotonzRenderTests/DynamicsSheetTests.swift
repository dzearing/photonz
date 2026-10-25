import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PhotonzCore
@testable import PhotonzRender

/// Writes the pressure sheet the audit shows (`docs/design/brushes.md`,
/// decision 6): a row per medium, and across it a pen pressed lightly, at a
/// middle press and hard, a pen swelling from nothing to a full press and
/// back, a pen leaned across the stroke, and a mouse moved slowly and fast.
/// Synthetic pens painted through the real placement and rasterizer, the path
/// a tablet's samples take. Only when asked:
/// `PHOTONZ_DYNAMICS_SHEET=/some/dir Scripts/test.sh --filter DynamicsSheet`.
@Suite("Dynamics sheet")
struct DynamicsSheetTests {

    private static let folder = ProcessInfo.processInfo.environment["PHOTONZ_DYNAMICS_SHEET"]

    private static let columns = ["Light", "Medium", "Heavy", "Swell", "Leaned", "Mouse slow", "Mouse fast"]
    private static let cell = CGSize(width: 150, height: 84)
    private static let margin: CGFloat = 120

    private func size(_ medium: BrushMedium) -> Double {
        switch medium {
        case .pencil: 5
        case .crayon, .marker: 14
        case .airbrush: 30
        default: 18
        }
    }

    /// A gentle curve across one cell, `x0` points from the row's left.
    private func stroke(_ medium: BrushMedium, x0: CGFloat, y: CGFloat, pressure: ((Double) -> Double)?,
                        tilt: CGPoint? = nil, speed: Double = 0.3, seed: UInt32) -> BrushStroke {
        let width = Self.cell.width - 30
        let count = 40
        let samples = (0...count).map { i -> StrokeSample in
            let t = Double(i) / Double(count)
            let point = CGPoint(x: x0 + 15 + width * CGFloat(t), y: y + CGFloat(sin(t * .pi * 2)) * 8)
            return StrokeSample(point: point, pressure: pressure.map { $0(t) }, tilt: tilt,
                                ms: Double(width) * t / speed)
        }
        let settings = BrushSettings(medium: medium, values: ["size": size(medium)])
        return BrushStroke(samples: samples, settings: settings, colorHex: "#1E1E1E", seed: seed)
    }

    private func row(_ medium: BrushMedium) -> [BrushStroke] {
        let y = Self.cell.height / 2
        func x(_ column: Int) -> CGFloat { Self.margin + CGFloat(column) * Self.cell.width }
        return [
            stroke(medium, x0: x(0), y: y, pressure: { _ in 0.2 }, seed: 1),
            stroke(medium, x0: x(1), y: y, pressure: { _ in 0.5 }, seed: 2),
            stroke(medium, x0: x(2), y: y, pressure: { _ in 0.95 }, seed: 3),
            stroke(medium, x0: x(3), y: y, pressure: { t in sin(t * .pi) }, seed: 4),
            stroke(medium, x0: x(4), y: y, pressure: { _ in 0.6 }, tilt: CGPoint(x: 0.25, y: 0.8), seed: 5),
            stroke(medium, x0: x(5), y: y, pressure: nil, speed: 0.25, seed: 6),
            stroke(medium, x0: x(6), y: y, pressure: nil, speed: 4, seed: 7),
        ]
    }

    @Test(.enabled(if: folder != nil))
    func writeSheet() throws {
        let folder = try #require(Self.folder)
        let media = BrushMedium.allCases
        let scale: CGFloat = 2
        let header: CGFloat = 30
        let size = CGSize(width: Self.margin + Self.cell.width * CGFloat(Self.columns.count),
                          height: header + Self.cell.height * CGFloat(media.count))
        let context = try #require(CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.98, green: 0.97, blue: 0.95, alpha: 1))
        context.fill(CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
        for (column, title) in Self.columns.enumerated() {
            draw(title, at: CGPoint(x: (Self.margin + CGFloat(column) * Self.cell.width + 15) * scale,
                                    y: (size.height - 21) * scale), in: context)
        }
        var lines = ["medium\tlight w/paint\tmedium w/paint\theavy w/paint\tmouse start/middle/end width"]
        for (index, medium) in media.enumerated() {
            let box = CGSize(width: size.width, height: Self.cell.height)
            let strokes = row(medium)
            let raster = try #require(PaintRasterizer.rasterize(PaintContent(strokes: strokes),
                                                                size: box, scale: scale))
            let top = header + CGFloat(index) * Self.cell.height
            context.draw(raster, in: CGRect(x: 0, y: (size.height - top - Self.cell.height) * scale,
                                            width: box.width * scale, height: box.height * scale))
            draw(medium.title, at: CGPoint(x: 12 * scale, y: (size.height - top - Self.cell.height / 2 - 6) * scale),
                 in: context)
            lines.append(try measures(medium, box: box, scale: scale))
        }
        let image = try #require(context.makeImage())
        let url = URL(fileURLWithPath: folder).appendingPathComponent("dynamics-sheet.png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString,
                                                                       1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        try lines.joined(separator: "\n").write(toFile: folder + "/dynamics-sheet-measures.txt", atomically: true,
                                                encoding: .utf8)
    }

    /// One medium's numbers, read off straight strokes: the width and the
    /// paint in the middle at each press, and a mouse stroke's width near its
    /// start, in its middle and near its end.
    private func measures(_ medium: BrushMedium, box: CGSize, scale: CGFloat) throws -> String {
        func straight(_ pressure: Double?) -> BrushStroke {
            let samples = (0...60).map { i in
                StrokeSample(point: CGPoint(x: 20 + Double(i) * 5, y: 42), pressure: pressure, ms: Double(i) * 16)
            }
            return BrushStroke(samples: samples, settings: BrushSettings(medium: medium, values: ["size": size(medium)]),
                               colorHex: "#1E1E1E", seed: 9)
        }
        func image(_ s: BrushStroke) throws -> CGImage {
            try #require(PaintRasterizer.rasterize(PaintContent(strokes: [s]), size: box, scale: scale))
        }
        func width(_ image: CGImage, _ x: CGFloat, half: CGFloat = 4) -> Double {
            PaintMeasures.lineProfile(image, from: CGPoint(x: x - half, y: 42), to: CGPoint(x: x + half, y: 42),
                                      reach: 40, scale: scale).width
        }
        var cells: [String] = [medium.title]
        for p in [0.2, 0.5, 0.95] {
            let i = try image(straight(p))
            let paint = PaintMeasures.meanCoreAlpha(i, from: CGPoint(x: 120, y: 42), to: CGPoint(x: 220, y: 42),
                                                    diameter: 6, scale: scale)
            cells.append(String(format: "%.1f pt / %.2f", width(i, 170, half: 50), paint))
        }
        let mouse = try image(straight(nil))
        cells.append(String(format: "%.1f / %.1f / %.1f", width(mouse, 25), width(mouse, 170), width(mouse, 315)))
        return cells.joined(separator: "\t")
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
