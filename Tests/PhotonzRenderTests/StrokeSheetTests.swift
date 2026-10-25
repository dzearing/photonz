import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PhotonzCore
@testable import PhotonzRender

/// Writes the brush stroke sheet the audit shows (`docs/design/brushes.md`): a
/// row per medium of strokes on white paper, by the real rasterizer, and the
/// measured bar for each row. Only when asked:
/// `PHOTONZ_STROKE_SHEET=/some/dir Scripts/test.sh --filter StrokeSheet`.
@Suite("Stroke sheet")
struct StrokeSheetTests {

    private static let folder = ProcessInfo.processInfo.environment["PHOTONZ_STROKE_SHEET"]

    private func curve(_ y: CGFloat, from x0: CGFloat, to x1: CGFloat, wave: CGFloat, seed: UInt32,
                       settings: BrushSettings, hex: String = "#1E1E1E") -> BrushStroke {
        let samples = (0...40).map { i -> StrokeSample in
            let t = CGFloat(i) / 40
            return StrokeSample(point: CGPoint(x: x0 + (x1 - x0) * t, y: y + sin(t * .pi * 2) * wave),
                                ms: Double(i) * 12)
        }
        return BrushStroke(samples: samples, settings: settings, colorHex: hex, seed: seed)
    }

    private func brush(_ medium: BrushMedium, size: Double, _ set: [String: Double] = [:],
                       mode: BrushMode = .paint) -> BrushSettings {
        BrushSettings(medium: medium, values: ["size": size].merging(set) { $1 }, mode: mode)
    }

    /// One row: a wavy stroke, a straight one crossing a second pass, and for
    /// charcoal and chalk a smudge dragged out of the straight one.
    private func row(_ medium: BrushMedium) -> [BrushStroke] {
        let size: Double = medium == .crayon ? 14 : 24
        var strokes = [
            curve(60, from: 30, to: 330, wave: 18, seed: 11, settings: brush(medium, size: size)),
            curve(60, from: 380, to: 640, wave: 0, seed: 12, settings: brush(medium, size: size)),
            curve(60, from: 380, to: 640, wave: 0, seed: 13, settings: brush(medium, size: size)),
            curve(40, from: 700, to: 960, wave: 0, seed: 14, settings: brush(medium, size: size, ["grain": 0])),
            curve(80, from: 700, to: 960, wave: 0, seed: 15, settings: brush(medium, size: size, ["grain": 100])),
        ]
        if medium == .charcoal || medium == .chalk {
            // A finger dragged out of the straight stroke, up and away.
            let drag = [CGPoint(x: 560, y: 62), CGPoint(x: 600, y: 48), CGPoint(x: 640, y: 30),
                        CGPoint(x: 670, y: 20)].enumerated().map { StrokeSample(point: $1, ms: Double($0) * 16) }
            strokes.append(BrushStroke(samples: drag, settings: brush(medium, size: 26, mode: .smudge),
                                       colorHex: "#1E1E1E", seed: 16))
        }
        return strokes
    }

    @Test(.enabled(if: folder != nil))
    func writeSheet() throws {
        let folder = try #require(Self.folder)
        let media: [BrushMedium] = [.charcoal, .chalk, .crayon, .marker]
        let scale: CGFloat = 2, rowHeight: CGFloat = 120, width: CGFloat = 1000
        var lines: [String] = []
        for labelled in [false, true] {
            let size = CGSize(width: width, height: rowHeight * CGFloat(media.count))
            let context = try #require(CGContext(
                data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(srgbRed: 0.98, green: 0.97, blue: 0.95, alpha: 1))
            context.fill(CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
            for (index, medium) in media.enumerated() {
                let box = CGSize(width: width, height: rowHeight)
                let raster = try #require(PaintRasterizer.rasterize(PaintContent(strokes: row(medium)),
                                                                    size: box, scale: scale))
                let top = CGFloat(index) * rowHeight
                context.draw(raster, in: CGRect(x: 0, y: (size.height - top - rowHeight) * scale,
                                                width: width * scale, height: rowHeight * scale))
                if labelled {
                    draw(medium.title, at: CGPoint(x: 12 * scale, y: (size.height - top - 18) * scale),
                         in: context)
                } else {
                    // The measured bar, on the straight single stroke alone.
                    let s = curve(60, from: 30, to: 330, wave: 0, seed: 11,
                                  settings: brush(medium, size: medium == .crayon ? 14 : 24))
                    let alone = try #require(PaintRasterizer.rasterize(PaintContent(strokes: [s]), size: box,
                                                                       scale: scale))
                    let d: CGFloat = medium == .crayon ? 14 : 24
                    let gap = PaintMeasures.interiorGapFraction(alone, from: CGPoint(x: 30, y: 60),
                                                                to: CGPoint(x: 330, y: 60), diameter: d, scale: scale)
                    var smooth = s
                    smooth.settings.set("grain", to: 0)
                    let tipOnly = try #require(PaintRasterizer.rasterize(PaintContent(strokes: [smooth]),
                                                                         size: box, scale: scale))
                    let soft = PaintMeasures.edgeSoftness(tipOnly, from: CGPoint(x: 30, y: 60),
                                                          to: CGPoint(x: 330, y: 60), diameter: d, scale: scale)
                    let cover = PaintMeasures.meanCoreAlpha(alone, from: CGPoint(x: 30, y: 60),
                                                            to: CGPoint(x: 330, y: 60), diameter: d, scale: scale)
                    lines.append(String(format: "%@\tgaps %.3f (bar %.2f: %@)\ttip fall-off %.2f\tcore %.2f",
                                        medium.title, gap, PaintMeasures.dryMediaGapBar,
                                        gap >= PaintMeasures.dryMediaGapBar ? "passes" : "fails", soft, cover))
                }
            }
            let image = try #require(context.makeImage())
            let url = URL(fileURLWithPath: folder)
                .appendingPathComponent(labelled ? "stroke-sheet-labelled.png" : "stroke-sheet.png")
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
        }
        try lines.joined(separator: "\n").write(toFile: folder + "/stroke-sheet-measures.txt", atomically: true,
                                                encoding: .utf8)
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
