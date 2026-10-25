import CoreGraphics
import Foundation
import PhotonzCore

/// Turns a paint layer's strokes into pixels (`docs/design/brushes.md`,
/// decision 4, the marking half).
///
/// Every stroke is replayed in order: its dabs come from `BrushPlacement`
/// (PhotonzCore), and each is stamped with the tip. For now that tip is one
/// plain round with a soft edge, whatever the medium; the medium slices give
/// each medium its own marking here, and nothing else has to change.
///
/// The live stroke on the canvas stamps with `mark(_:tip:in:)` too, so what
/// lands when the pointer comes up is what was drawn while it moved.
public enum PaintRasterizer {

    /// How far off its line a dab may wander, as a fraction of its radius.
    /// The plain tip keeps to the line.
    public static func jitter(for medium: BrushMedium) -> CGFloat { 0 }

    /// Draws `content` inside `size` (the layer's box, in document points),
    /// `scale` pixels per point. Nil for a box with no pixels in it.
    public static func rasterize(_ content: PaintContent, size: CGSize,
                                 scale: CGFloat = 1) -> CGImage? {
        guard scale > 0, scale.isFinite else { return nil }
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width >= 1, height >= 1,
              let context = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Top-left points, the space the samples are stored in.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        let visible = CGRect(origin: .zero, size: size)
        for stroke in content.strokes where stroke.bounds.intersects(visible) {
            paint(stroke, in: context, scale: scale)
        }
        return context.makeImage()
    }

    /// One whole stroke onto `context` (already in the stroke's points).
    ///
    /// A stroke is as opaque as its Opacity everywhere it covers, however many
    /// of its own dabs overlap: the dabs are stamped fully inside a
    /// transparency layer and the layer is laid down at the stroke's opacity.
    /// Two separate strokes DO build on each other, the way two passes of a
    /// brush do.
    public static func paint(_ stroke: BrushStroke, in context: CGContext, scale: CGFloat) {
        let dabs = BrushPlacement.dabs(for: stroke, jitter: jitter(for: stroke.settings.medium))
        guard let tip = Tip(stroke: stroke, scale: scale) else { return }
        context.saveGState()
        context.setAlpha(CGFloat(stroke.settings.opacity / 100))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        mark(dabs, tip: tip, in: context)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// Stamps `dabs` with `tip`, at full strength: the caller lays the result
    /// down at the stroke's opacity.
    public static func mark(_ dabs: [BrushDab], tip: Tip, in context: CGContext) {
        for dab in dabs {
            let r = dab.diameter / 2
            context.draw(tip.image, in: CGRect(x: dab.center.x - r, y: dab.center.y - r,
                                               width: dab.diameter, height: dab.diameter))
        }
    }

    /// A stroke's tip, drawn once in its colour and stamped at every dab.
    public struct Tip: @unchecked Sendable {
        // CGImage is immutable and thread-safe; it is only not marked Sendable.
        public let image: CGImage

        /// The plain round: solid to half its radius, then falling smoothly
        /// to nothing at the edge, so a line of them reads as one soft stroke.
        /// Drawn at the pixels it will be shown at (`scale` per point).
        public init?(stroke: BrushStroke, scale: CGFloat) {
            let side = max(2, Int((CGFloat(stroke.settings.size) * scale).rounded(.up)))
            guard let rgba = RGBA(hex: stroke.colorHex),
                  let context = CGContext(
                    data: nil, width: side, height: side,
                    bitsPerComponent: 8, bytesPerRow: side * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            let solid = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
            let clear = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: 0)
            guard let ramp = CGGradient(colorsSpace: space, colors: [solid, solid, clear] as CFArray,
                                        locations: [0, 0.5, 1]) else { return nil }
            let centre = CGPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
            context.drawRadialGradient(ramp, startCenter: centre, startRadius: 0,
                                       endCenter: centre, endRadius: CGFloat(side) / 2, options: [])
            guard let image = context.makeImage() else { return nil }
            self.image = image
        }
    }
}
