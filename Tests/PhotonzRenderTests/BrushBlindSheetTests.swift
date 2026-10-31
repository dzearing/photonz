import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PhotonzCore
@testable import PhotonzRender

/// Writes the brush epic's blind test (docs/design/brushes.md): every medium
/// and the plain round tip paint the same marks in the same colour at their
/// own default settings, one unlabelled row each, in three fixed shuffles, so
/// a person or a model judge can be asked to name each row from the marks
/// alone. The key for each shuffle is written beside it. The round tip is the
/// weak version the umbrella task's bar must fail: one stamped dab with only
/// colour changing. Also writes each row on its own (`row-<medium>.png`) for a
/// close look. Only when asked:
/// `PHOTONZ_BLIND_SHEET=/some/dir Scripts/test.sh --filter BrushBlindSheet`.
@Suite("Brush blind sheet")
struct BrushBlindSheetTests {

    private static let folder = ProcessInfo.processInfo.environment["PHOTONZ_BLIND_SHEET"]
    private let scale: CGFloat = 2
    private let ink = "#2B3550"
    private let rowHeight: CGFloat = 150
    private let width: CGFloat = 1100

    /// A brisk hand's pass through `points`, 0.6 points a millisecond.
    private func path(_ points: [CGPoint], speed: Double = 0.6) -> [StrokeSample] {
        var out: [StrokeSample] = []
        var t = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            let length = Double(hypot(b.x - a.x, b.y - a.y))
            let steps = max(2, Int(length / 6))
            for i in 0..<steps {
                let f = CGFloat(i) / CGFloat(steps)
                out.append(StrokeSample(point: CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f), ms: t))
                t += length / Double(steps) / speed
            }
        }
        if let last = points.last { out.append(StrokeSample(point: last, ms: t)) }
        return out
    }

    /// The marks every row paints: a long wave, a zigzag, and two strokes
    /// crossing (where a marker darkens and a watercolour layers).
    private func marks(_ medium: BrushMedium, row: Int) -> [BrushStroke] {
        let values = ["size": BrushSettings(medium: medium).size]
        let mid = rowHeight / 2
        let wave = (0...30).map { i -> CGPoint in
            let t = CGFloat(i) / 30
            return CGPoint(x: 50 + 360 * t, y: mid + sin(t * .pi * 2) * 28)
        }
        let zigzag = (0..<8).map { CGPoint(x: 470 + CGFloat($0) * 45, y: $0.isMultiple(of: 2) ? mid - 40 : mid + 40) }
        let cross = [[CGPoint(x: 850, y: mid - 45), CGPoint(x: 1050, y: mid + 45)],
                     [CGPoint(x: 850, y: mid + 45), CGPoint(x: 1050, y: mid - 45)]]
        let seed = UInt32(500 + row * 10)
        return ([path(wave), path(zigzag)] + cross.map { path($0) }).enumerated().map { i, samples in
            BrushStroke(samples: samples, settings: BrushSettings(medium: medium, values: values),
                        colorHex: ink, seed: seed + UInt32(i))
        }
    }

    /// Every entry on the sheet: the eight media and the round tip.
    private var entries: [(name: String, medium: BrushMedium, round: Bool)] {
        BrushMedium.allCases.map { ($0.rawValue, $0, false) } + [("round tip", .oil, true)]
    }

    private func raster(_ entry: (name: String, medium: BrushMedium, round: Bool), row: Int) throws -> CGImage {
        let content = PaintContent(strokes: marks(entry.medium, row: row))
        let size = CGSize(width: width, height: rowHeight)
        if entry.round {
            return try PaintRasterizer.$plainRound.withValue(true) {
                try #require(PaintRasterizer.rasterize(content, size: size, scale: scale))
            }
        }
        return try #require(PaintRasterizer.rasterize(content, size: size, scale: scale))
    }

    @Test(.enabled(if: folder != nil))
    func writeSheets() throws {
        let folder = try #require(Self.folder)
        let entries = self.entries
        var rows: [String: CGImage] = [:]
        for (index, entry) in entries.enumerated() {
            let image = try raster(entry, row: index)
            rows[entry.name] = image
            try write([image], to: folder + "/row-\(entry.name.replacingOccurrences(of: " ", with: "-")).png",
                      numbered: false)
        }
        // Three fixed shuffles, so a judge sees the rows in a different order
        // each round and a lucky order cannot carry the answer.
        let orders: [[Int]] = [[4, 8, 1, 6, 2, 0, 7, 3, 5], [7, 2, 5, 8, 0, 3, 6, 1, 4], [1, 6, 8, 3, 5, 7, 0, 4, 2]]
        for (round, order) in orders.enumerated() {
            #expect(Set(order) == Set(entries.indices), "order \(round) covers every row once")
            let images = try order.map { try #require(rows[entries[$0].name]) }
            try write(images, to: folder + "/blind-\(round + 1).png", numbered: true)
            try order.enumerated().map { "row \($0 + 1): \(entries[$1].name)" }.joined(separator: "\n")
                .write(toFile: folder + "/blind-\(round + 1)-key.txt", atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Drawing

    private func write(_ images: [CGImage], to path: String, numbered: Bool) throws {
        let size = CGSize(width: width, height: rowHeight * CGFloat(images.count))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
        for (index, image) in images.enumerated() {
            let top = CGFloat(index) * rowHeight
            context.draw(image, in: CGRect(x: 0, y: (size.height - top - rowHeight) * scale,
                                           width: width * scale, height: rowHeight * scale))
            context.saveGState()
            context.scaleBy(x: scale, y: scale)
            if index > 0 {
                context.setStrokeColor(CGColor(srgbRed: 0.85, green: 0.85, blue: 0.85, alpha: 1))
                context.setLineWidth(0.5)
                context.move(to: CGPoint(x: 0, y: size.height - top))
                context.addLine(to: CGPoint(x: width, y: size.height - top))
                context.strokePath()
            }
            if numbered { label("\(index + 1)", at: CGPoint(x: 12, y: size.height - top - 20), in: context) }
            context.restoreGState()
        }
        let url = URL(fileURLWithPath: path)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString,
                                                                       1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func label(_ text: String, at point: CGPoint, in context: CGContext) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 15, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(srgbRed: 0.75, green: 0.1, blue: 0.1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
