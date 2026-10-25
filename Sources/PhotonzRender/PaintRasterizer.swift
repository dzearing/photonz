import CoreGraphics
import Foundation
import PhotonzCore

/// Turns a paint layer's strokes into pixels (`docs/design/brushes.md`,
/// decision 4, the marking half).
///
/// Every stroke is replayed in order: its dabs come from `BrushPlacement`
/// (PhotonzCore), and each medium marks them its own way. Charcoal, chalk and
/// crayon catch on a paper grain (`DryMedia.swift`); the marker lays flat ink
/// multiplied over what is there and the airbrush sprays a cloud that builds
/// (`MarkerAirbrush.swift`); watercolour lays a wash that pools at its edge,
/// bleeds, and blooms into washes still wet (`Watercolour.swift`); a smudge
/// drags what is already painted; oil paint is still stamped with one plain
/// round with a soft edge until its slice gives it its own marking here.
///
/// The live stroke on the canvas marks with `LiveMarker`, which runs the same
/// code dab for dab, so what lands when the pointer comes up is what was drawn
/// while it moved.
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
        // The watercolour washes still wet as the strokes go down in order.
        var wet = WetWashes()
        for stroke in content.strokes where stroke.bounds.intersects(visible) {
            paint(stroke, in: context, scale: scale, wet: &wet)
        }
        return context.makeImage()
    }

    /// One whole stroke onto `context`, a bitmap that `rasterize` made: top-left
    /// points at `scale` pixels each.
    ///
    /// A stroke is as opaque as its Opacity everywhere it covers, however many
    /// of its own dabs overlap: the dabs are marked fully on their own and the
    /// result is laid down at the stroke's opacity. Two separate strokes DO
    /// build on each other, the way two passes of a brush do. The airbrush is
    /// the one medium whose own dabs build, as a spray does.
    public static func paint(_ stroke: BrushStroke, in context: CGContext, scale: CGFloat) {
        var wet = WetWashes()
        paint(stroke, in: context, scale: scale, wet: &wet)
    }

    /// The same, for a stroke replayed among its layer's others: `wet` holds
    /// the watercolour washes still wet when it begins, and takes this one if
    /// it is watercolour.
    static func paint(_ stroke: BrushStroke, in context: CGContext, scale: CGFloat, wet: inout WetWashes) {
        let dabs = BrushPlacement.dabs(for: stroke, jitter: jitter(for: stroke.settings.medium))
        let toPixels = CGAffineTransform(scaleX: scale, y: scale)
        if stroke.settings.mode == .smudge {
            guard let plane = PixelPlane(context) else { return }
            var smudge = SmudgeStroke(settings: stroke.settings, toPixels: toPixels, limit: plane.box)
            for dab in dabs { _ = smudge.mark(dab, target: plane, mirror: nil) }
            return
        }
        if let look = DryLook(stroke.settings) {
            guard let plane = PixelPlane(context), let colour = RGBA(hex: stroke.colorHex) else { return }
            var dry = DryStroke(look: look, seed: stroke.seed, toPixels: toPixels, limit: plane.box)
            for dab in dabs { _ = dry.mark(dab) }
            dry.composite(into: plane, colour: colour, opacity: Float(stroke.settings.opacity / 100))
            return
        }
        switch stroke.settings.medium {
        case .marker:
            guard let plane = PixelPlane(context), let colour = RGBA(hex: stroke.colorHex) else { return }
            var marker = MarkerStroke(settings: stroke.settings, colour: colour, toPixels: toPixels,
                                      limit: plane.box)
            for dab in dabs { _ = marker.mark(dab) }
            marker.composite(into: plane, colour: colour)
            return
        case .airbrush:
            guard let plane = PixelPlane(context), let colour = RGBA(hex: stroke.colorHex) else { return }
            var spray = AirbrushStroke(settings: stroke.settings, seed: stroke.seed, toPixels: toPixels,
                                       limit: plane.box)
            for dab in dabs { _ = spray.mark(dab) }
            spray.composite(into: plane, colour: colour, opacity: Float(stroke.settings.opacity / 100))
            return
        case .watercolour:
            guard let plane = PixelPlane(context), let colour = RGBA(hex: stroke.colorHex) else { return }
            var wash = WatercolourStroke(settings: stroke.settings, colour: colour, seed: stroke.seed,
                                         toPixels: toPixels, limit: plane.box, under: wet.under(stroke))
            for dab in dabs { _ = wash.mark(dab) }
            wash.composite(into: plane, colour: colour)
            wet.add(stroke, wash)
            return
        default:
            break
        }
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

    /// The stroke under the pointer, marked onto the canvas's overlay bitmap a
    /// few dabs at a time with the same code that lands it.
    ///
    /// The bitmap holds this stroke alone and is shown at the stroke's
    /// opacity, except for a smudge, a marker and watercolour, which are shown
    /// as they are (`showsAtFullStrength`): what they lay over the paint below
    /// them, read from `working`, a copy of that paint in the bitmap's pixels.
    /// A marker or a wash with no `working` lands on fresh paper. Watercolour
    /// also reads the `earlier` strokes of the layer it lands on (in that
    /// layer's points), for the washes still wet that it blooms into.
    public final class LiveMarker {
        private enum Kind {
            case round(Tip)
            case dry(DryStroke, RGBA)
            case marker(MarkerStroke, RGBA, under: PixelPlane?)
            case watercolour(WatercolourStroke, RGBA, under: PixelPlane?)
            case airbrush(AirbrushStroke, RGBA)
            case smudge(SmudgeStroke, PixelPlane)
        }

        /// Whether the canvas shows the bitmap as it is, rather than at the
        /// stroke's opacity: it already holds what lands, opacity and all.
        public let showsAtFullStrength: Bool
        private let bitmap: CGContext
        private let plane: PixelPlane?
        private let pointsToPixels: CGAffineTransform
        private let clip: CGRect
        private var kind: Kind
        // Kept alive for as long as `kind` reads its pixels.
        private let working: CGContext?

        /// `pointsToPixels` takes the stroke's points to the bitmap's pixels
        /// (top-left), and `clip` is the pixels the stroke may mark: the box
        /// of the layer it lands on. Nil when the bitmap is not one this can
        /// mark, or a smudge has no paint to read.
        public init?(stroke: BrushStroke, bitmap: CGContext, pointsToPixels: CGAffineTransform,
                     clip: CGRect, working: CGContext? = nil, earlier: [BrushStroke] = []) {
            self.bitmap = bitmap
            self.pointsToPixels = pointsToPixels
            self.clip = clip
            self.working = working
            plane = PixelPlane(bitmap)
            let limit = PixelBox(clip).intersection(plane?.box ?? .empty)
            showsAtFullStrength = stroke.settings.mode == .smudge || stroke.settings.medium == .marker
                || stroke.settings.medium == .watercolour
            if stroke.settings.mode == .smudge {
                guard let working, let read = PixelPlane(working), plane != nil else { return nil }
                kind = .smudge(SmudgeStroke(settings: stroke.settings, toPixels: pointsToPixels, limit: limit), read)
            } else if stroke.settings.medium == .marker {
                guard plane != nil, let colour = RGBA(hex: stroke.colorHex) else { return nil }
                kind = .marker(MarkerStroke(settings: stroke.settings, colour: colour, toPixels: pointsToPixels,
                                            limit: limit),
                               colour, under: working.flatMap { PixelPlane($0) })
            } else if stroke.settings.medium == .watercolour {
                guard plane != nil, let colour = RGBA(hex: stroke.colorHex) else { return nil }
                let under = WetWashes.under(stroke, earlier: earlier, toPixels: pointsToPixels, limit: limit)
                kind = .watercolour(WatercolourStroke(settings: stroke.settings, colour: colour, seed: stroke.seed,
                                                      toPixels: pointsToPixels, limit: limit, under: under),
                                    colour, under: working.flatMap { PixelPlane($0) })
            } else if stroke.settings.medium == .airbrush {
                guard plane != nil, let colour = RGBA(hex: stroke.colorHex) else { return nil }
                kind = .airbrush(AirbrushStroke(settings: stroke.settings, seed: stroke.seed,
                                                toPixels: pointsToPixels, limit: limit), colour)
            } else if let look = DryLook(stroke.settings) {
                guard plane != nil, let colour = RGBA(hex: stroke.colorHex) else { return nil }
                kind = .dry(DryStroke(look: look, seed: stroke.seed, toPixels: pointsToPixels, limit: limit),
                            colour)
            } else {
                guard let tip = Tip(stroke: stroke, scale: hypot(pointsToPixels.a, pointsToPixels.b))
                else { return nil }
                kind = .round(tip)
            }
        }

        /// Marks `dabs`, the next ones the walker settled.
        public func mark(_ dabs: [BrushDab]) {
            guard !dabs.isEmpty else { return }
            switch kind {
            case .round(let tip):
                bitmap.saveGState()
                bitmap.translateBy(x: 0, y: CGFloat(bitmap.height))
                bitmap.scaleBy(x: 1, y: -1)
                bitmap.clip(to: clip)
                bitmap.concatenate(pointsToPixels)
                PaintRasterizer.mark(dabs, tip: tip, in: bitmap)
                bitmap.restoreGState()
            case .dry(var dry, let colour):
                guard let plane else { return }
                var touched = PixelBox.empty
                for dab in dabs { touched = touched.union(dry.mark(dab)) }
                dry.replace(touched, in: plane, colour: colour)
                kind = .dry(dry, colour)
            case .marker(var marker, let colour, let under):
                guard let plane else { return }
                var touched = PixelBox.empty
                for dab in dabs { touched = touched.union(marker.mark(dab)) }
                marker.replace(touched, in: plane, under: under, colour: colour)
                kind = .marker(marker, colour, under: under)
            case .watercolour(var wash, let colour, let under):
                guard let plane else { return }
                var touched = PixelBox.empty
                for dab in dabs { touched = touched.union(wash.mark(dab)) }
                wash.replace(touched, in: plane, under: under, colour: colour)
                kind = .watercolour(wash, colour, under: under)
            case .airbrush(var spray, let colour):
                guard let plane else { return }
                var touched = PixelBox.empty
                for dab in dabs { touched = touched.union(spray.mark(dab)) }
                spray.replace(touched, in: plane, colour: colour)
                kind = .airbrush(spray, colour)
            case .smudge(var smudge, let read):
                guard let plane else { return }
                for dab in dabs { _ = smudge.mark(dab, target: read, mirror: plane) }
                kind = .smudge(smudge, read)
            }
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
