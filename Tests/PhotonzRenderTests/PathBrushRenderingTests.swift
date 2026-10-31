import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A path's brushed line as it lands in pixels (`docs/design/brushes.md`,
/// decision 9): the path's curve walked into brush strokes and painted by the
/// same engine a paint layer's strokes are, so the line reads as charcoal or
/// watercolour rather than as a plain vector stroke, and follows the anchors.
@Suite("A path's brushed line, rendered")
struct PathBrushRenderingTests {

    private let scale: CGFloat = 2
    private let box = CGSize(width: 320, height: 120)

    /// A straight open line across the box, 16 points thick.
    private func line(_ medium: BrushMedium?, width: CGFloat = 16) -> PathContent {
        var path = PathContent(anchors: [PathAnchor(point: CGPoint(x: 10, y: 60)),
                                         PathAnchor(point: CGPoint(x: 310, y: 60))],
                               isClosed: false, strokeWidth: width, fill: nil)
        path.brush = medium.map { PathBrush(settings: BrushSettings(medium: $0)) }
        return path
    }

    private func render(_ path: PathContent) throws -> CGImage {
        try #require(PathRasterizer.rasterize(path, size: box, scale: scale))
    }

    @Test("Every medium paints the line, and none of them is the plain stroke", arguments: BrushMedium.allCases)
    func everyMedium(_ medium: BrushMedium) throws {
        let brushed = try render(line(medium))
        let pad = line(medium).strokeOutset
        let middle = CGPoint(x: 160 + pad, y: 60 + pad)
        #expect(PaintMeasures.meanAlpha(brushed, around: middle, radius: 3, scale: scale) > 0.15)
        // Far off the line there is nothing.
        #expect(PaintMeasures.meanAlpha(brushed, around: CGPoint(x: 160 + pad, y: 5), radius: 3, scale: scale) < 0.02)
        // The plain line drawn into the same sized bitmap, to compare with.
        let plain = try #require(Self.plain(line(nil), pad: pad, size: box, scale: scale))
        #expect(plain.width == brushed.width && plain.height == brushed.height)
        #expect(PaintMeasures.changedShare(plain, brushed) > 0.2)
    }

    @Test("The line is the paint engine's own stroke, pixel for pixel")
    func sameEngine() throws {
        let path = line(.charcoal)
        let pad = path.strokeOutset
        let brushed = try render(path)
        let strokes = path.brushStrokes.map { $0.offsetBy(dx: pad, dy: pad) }
        let painted = try #require(PaintRasterizer.replay(
            PaintContent(strokes: strokes),
            size: CGSize(width: box.width + 2 * pad, height: box.height + 2 * pad), scale: scale))
        #expect(PaintMeasures.changedShare(brushed, painted, block: 1) == 0)
    }

    @Test("An open line tapers at both ends", arguments: [BrushMedium.charcoal, .marker, .watercolour])
    func tapers(_ medium: BrushMedium) throws {
        let path = line(medium)
        let pad = path.strokeOutset
        let image = try render(path)
        func width(_ from: CGFloat, _ to: CGFloat) -> Double {
            PaintMeasures.lineProfile(image, from: CGPoint(x: from + pad, y: 60 + pad),
                                      to: CGPoint(x: to + pad, y: 60 + pad), reach: 40, scale: scale).width
        }
        let middle = width(140, 180)
        #expect(middle > 8)
        #expect(width(10, 14) < middle * 0.8)
        #expect(width(306, 310) < middle * 0.8)
    }

    @Test("Moving an anchor repaints the line along the new curve")
    func follows() throws {
        var path = line(.chalk)
        path.anchors[1].point = CGPoint(x: 310, y: 60)
        let pad = path.strokeOutset
        let before = try render(path)
        path.anchors.insert(PathAnchor(point: CGPoint(x: 160, y: 20), kind: .corner), at: 1)
        let after = try render(path)
        let lifted = CGPoint(x: 160 + pad, y: 22 + pad)
        #expect(PaintMeasures.meanAlpha(before, around: lifted, radius: 3, scale: scale) < 0.02)
        #expect(PaintMeasures.meanAlpha(after, around: lifted, radius: 3, scale: scale) > 0.15)
    }

    @Test("A closed brushed shape keeps its fill under the line")
    func fillUnder() throws {
        var path = PathContent(anchors: [PathAnchor(point: CGPoint(x: 20, y: 20)),
                                         PathAnchor(point: CGPoint(x: 300, y: 20)),
                                         PathAnchor(point: CGPoint(x: 300, y: 100)),
                                         PathAnchor(point: CGPoint(x: 20, y: 100))],
                               isClosed: true, paint: Paint(hex: "#000000"), strokeWidth: 10,
                               fill: Paint(hex: "#33AA55"))
        path.brush = PathBrush(settings: BrushSettings(medium: .crayon))
        let pad = path.strokeOutset
        let image = try render(path)
        #expect(PaintMeasures.meanAlpha(image, around: CGPoint(x: 160 + pad, y: 60 + pad), radius: 4, scale: scale) > 0.95)
        #expect(PaintMeasures.meanAlpha(image, around: CGPoint(x: 160 + pad, y: 20 + pad), radius: 2, scale: scale) > 0.3)
    }

    /// The plain line, drawn into a bitmap padded like the brushed one.
    private static func plain(_ path: PathContent, pad: CGFloat, size: CGSize, scale: CGFloat) -> CGImage? {
        let width = Int(((size.width + 2 * pad) * scale).rounded())
        let height = Int(((size.height + 2 * pad) * scale).rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let drawn = PathRasterizer.rasterize(path, size: size, scale: scale) else { return nil }
        let inset = (pad - path.strokeOutset) * scale
        context.draw(drawn, in: CGRect(x: inset, y: inset, width: CGFloat(drawn.width), height: CGFloat(drawn.height)))
        return context.makeImage()
    }
}
