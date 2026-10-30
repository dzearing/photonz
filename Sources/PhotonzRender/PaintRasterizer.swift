import CoreGraphics
import Foundation
import PhotonzCore
import Synchronization

/// Turns a paint layer's strokes into pixels (`docs/design/brushes.md`,
/// decision 4, the marking half).
///
/// Every stroke is replayed in order: its dabs come from `BrushPlacement`
/// (PhotonzCore), and each medium marks them its own way. Charcoal, chalk and
/// crayon catch on a paper grain (`DryMedia.swift`); the marker lays flat ink
/// multiplied over what is there and the airbrush sprays a cloud that builds
/// (`MarkerAirbrush.swift`); watercolour lays a wash that pools at its edge,
/// bleeds, and blooms into washes still wet (`Watercolour.swift`); a smudge
/// drags what is already painted; oil paint is a loaded bristle brush that
/// picks up and smears the paint under it and leaves lit ridges
/// (`OilPaint.swift`).
///
/// The live stroke on the canvas marks with `LiveMarker`, which runs the same
/// code dab for dab, so what lands when the pointer comes up is what was drawn
/// while it moved.
public enum PaintRasterizer {

    /// How far off its line a dab may wander, as a fraction of its radius.
    /// The plain tip keeps to the line.
    public static func jitter(for medium: BrushMedium) -> CGFloat { 0 }

    /// When set, every stroke is stamped with the foundation slice's plain
    /// soft round instead of its medium: the yardstick each medium's measured
    /// bar is set against (a bar the plain round passes measures nothing).
    @TaskLocal public static var plainRound = false

    /// How many strokes have been simulated in full since launch: marked onto
    /// a layer, or replayed for their water alone so a later wash can bloom
    /// into them. A walk reads it to say how often one drag re-ran strokes it
    /// never touched (`expectBrushResponsive`).
    public static var strokesSimulated: Int { simulated.withLock { $0 } }
    private static let simulated = Mutex<Int>(0)
    static func countSimulated(_ strokes: Int = 1) { simulated.withLock { $0 += strokes } }

    /// Draws `content` inside `size` (the layer's box, in document points),
    /// `scale` pixels per point. Nil for a box with no pixels in it.
    ///
    /// Served from the shared `PaintRasterCache`: a layer asked for again with
    /// strokes added since is painted from the raster kept for it, only the
    /// new strokes simulated.
    public static func rasterize(_ content: PaintContent, size: CGSize,
                                 scale: CGFloat = 1) -> CGImage? {
        // The yardstick is drawn fresh every time and never kept.
        if plainRound { return replay(content, size: size, scale: scale) }
        return PaintRasterCache.shared.raster(content, size: size, scale: scale)
    }

    /// Every stroke of `content` replayed from blank paper, keeping nothing.
    static func replay(_ content: PaintContent, size: CGSize, scale: CGFloat) -> CGImage? {
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
        countSimulated()
        let dabs = BrushPlacement.dabs(for: stroke, jitter: jitter(for: stroke.settings.medium))
        let toPixels = CGAffineTransform(scaleX: scale, y: scale)
        if plainRound {
            stamp(stroke, dabs: dabs, in: context, scale: scale)
            return
        }
        if stroke.settings.mode == .smudge {
            guard let plane = PixelPlane(context) else { return }
            var smudge = SmudgeStroke(settings: stroke.settings, toPixels: toPixels, limit: plane.box)
            for dab in dabs { _ = smudge.mark(dab, target: plane, mirror: nil) }
            return
        }
        if let look = DryLook(stroke.settings) {
            guard let plane = PixelPlane(context), let colour = RGBA(hex: stroke.colorHex) else { return }
            var dry = DryStroke(look: look, seed: stroke.seed, toPixels: toPixels, limit: plane.box)
            _ = dry.mark(dabs)
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
        case .oil:
            guard let plane = PixelPlane(context), let colour = RGBA(hex: stroke.colorHex) else { return }
            var oil = OilStroke(settings: stroke.settings, colour: colour, seed: stroke.seed, toPixels: toPixels,
                                limit: plane.box)
            // The plane is not written until the stroke is done, so every dab
            // picks up the layer's paint as it stood before this stroke.
            for dab in dabs { _ = oil.mark(dab, under: plane) }
            _ = oil.finish(under: plane)
            oil.composite(into: plane)
            return
        default:
            stamp(stroke, dabs: dabs, in: context, scale: scale)
        }
    }

    /// The plain round: every dab stamped, laid down at the stroke's opacity.
    private static func stamp(_ stroke: BrushStroke, dabs: [BrushDab], in context: CGContext, scale: CGFloat) {
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
    /// opacity, except for a smudge, a marker, watercolour and oil, which are
    /// shown as they are (`showsAtFullStrength`): what they lay over the paint
    /// below them, read from `working`, a copy of that paint in the bitmap's
    /// pixels. A marker, a wash or oil with no `working` lands on fresh paper. Watercolour
    /// also reads the `earlier` strokes of the layer it lands on (in that
    /// layer's points), for the washes still wet that it blooms into.
    public final class LiveMarker {
        private enum Kind {
            case round(Tip)
            case dry(DryStroke, RGBA)
            case marker(MarkerStroke, RGBA, under: PixelPlane?)
            case watercolour(WatercolourStroke, RGBA, under: PixelPlane?)
            case airbrush(AirbrushStroke, RGBA)
            case oil(OilStroke, under: PixelPlane?)
            case smudge(SmudgeStroke, PixelPlane)
            /// Held for a moment while a stroke is changed, so the one being
            /// changed is the only copy of its fields and is changed in
            /// place: changed while this still held it, every move copied
            /// fields as big as the stroke.
            case none
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

        /// Whether the end of the stroke is thinned in as it goes: a mouse
        /// stroke's, which lands thinned out over its last stretch
        /// (`BrushPlacement.taperedOut`). The last stretch is drawn as if the
        /// stroke ended where the pointer is, and taken back and drawn again
        /// on the next move, so the stroke under the hand is the stroke that
        /// lands, end and all. A pen's press thins its own end.
        public var tapersItsEnd: Bool
        /// A stroke of these settings with no press, which is all
        /// `taperedOut` needs to know.
        private let taperTemplate: BrushStroke
        private let taperLength: CGFloat
        /// The dabs the walker settled that a later one could still thin: the
        /// last `taperLength` of the stroke.
        private var pending: [BrushDab] = []
        /// The stroke before its tail was drawn, and the pixels the tail drew.
        private var tail: (checkpoint: Kind, drawn: PixelBox)?

        /// `pointsToPixels` takes the stroke's points to the bitmap's pixels
        /// (top-left), and `clip` is the pixels the stroke may mark: the box
        /// of the layer it lands on. Nil when the bitmap is not one this can
        /// mark, or a smudge has no paint to read.
        public convenience init?(stroke: BrushStroke, bitmap: CGContext, pointsToPixels: CGAffineTransform,
                                 clip: CGRect, working: CGContext? = nil, earlier: [BrushStroke] = []) {
            self.init(stroke: stroke, bitmap: bitmap, pointsToPixels: pointsToPixels, clip: clip,
                      working: working, earlier: earlier, wet: nil)
        }

        /// The same, handed the washes still wet under the stroke rather than
        /// replaying the `earlier` strokes for them (`PaintLayerStroke`).
        init?(stroke: BrushStroke, bitmap: CGContext, pointsToPixels: CGAffineTransform,
              clip: CGRect, working: CGContext?, earlier: [BrushStroke], wet: [WetWash]?) {
            self.bitmap = bitmap
            self.pointsToPixels = pointsToPixels
            self.clip = clip
            self.working = working
            plane = PixelPlane(bitmap)
            // Only the live stroke on its layer thins its end as it goes; a
            // caller marking the landed dabs (already thinned) asks for none.
            let response = BrushDynamics.response(for: stroke.settings)
            tapersItsEnd = wet != nil && response.taperDepth > 0 && stroke.samples.first?.pressure == nil
            taperTemplate = BrushStroke(samples: [StrokeSample(point: .zero, ms: 0)], settings: stroke.settings,
                                        colorHex: stroke.colorHex, seed: stroke.seed)
            taperLength = CGFloat(BrushDynamics.taperLength(diameter: stroke.settings.size))
            let limit = PixelBox(clip).intersection(plane?.box ?? .empty)
            showsAtFullStrength = stroke.settings.mode == .smudge || stroke.settings.medium == .marker
                || stroke.settings.medium == .watercolour || stroke.settings.medium == .oil
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
                // Handed the washes still wet when the layer's raster was kept,
                // or worked out by replaying the earlier strokes' water.
                let under = wet ?? WetWashes.under(stroke, earlier: earlier, toPixels: pointsToPixels, limit: limit)
                kind = .watercolour(WatercolourStroke(settings: stroke.settings, colour: colour, seed: stroke.seed,
                                                      toPixels: pointsToPixels, limit: limit, under: under),
                                    colour, under: working.flatMap { PixelPlane($0) })
            } else if stroke.settings.medium == .oil {
                guard plane != nil, let colour = RGBA(hex: stroke.colorHex) else { return nil }
                kind = .oil(OilStroke(settings: stroke.settings, colour: colour, seed: stroke.seed,
                                      toPixels: pointsToPixels, limit: limit),
                            under: working.flatMap { PixelPlane($0) })
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

        /// The pointer has come up and the walker's last dabs are marked:
        /// anything a medium was holding back goes down (oil holds its first
        /// dab until it knows which way the brush is going, so a click lays
        /// it here).
        @discardableResult
        public func finish() -> CGRect {
            // The tail on screen was drawn for exactly this end: it stays.
            if tail != nil || (keepsPreviews && tapersItsEnd) {
                keepTail()
                tail = nil
                pending = []
            } else if !pending.isEmpty {
                let box = markRaw(BrushPlacement.taperedOut(pending, for: taperTemplate))
                pending = []
                redraw(box)
            }
            guard case .oil(var oil, let under) = kind, let plane else { return .null }
            let touched = oil.finish(under: under)
            oil.replace(touched, in: plane)
            kind = .oil(oil, under: under)
            return touched.rect
        }

        /// Marks `dabs`, the next ones the walker settled, and says which of
        /// the bitmap's pixels changed (top-left), or null for none.
        @discardableResult
        public func mark(_ dabs: [BrushDab]) -> CGRect {
            guard tapersItsEnd, canTakeBack else {
                guard !dabs.isEmpty else { return .null }
                let touched = markRaw(dabs)
                redraw(touched)
                return clipped(touched).rect
            }
            // No new dab, no new end: the tail on screen is already right.
            guard !dabs.isEmpty else { return .null }
            // The tail drawn for the last move comes back off, unless the
            // medium keeps the larger of what is there and what a dab lays:
            // then a thinner dab drawn early is covered by the same dab drawn
            // full, and taking it back would only cost a copy of the stroke's
            // fields (a wet wash's are 4.5 radii round, 2026-10-27).
            var touched = PixelBox.empty
            if !keepsPreviews, let drawn = takeBackTail() { touched = drawn }
            pending += dabs
            if let end = pending.last?.along {
                // Far enough from the end, a dab is never thinned however the
                // stroke ends: it goes down for good.
                let settled = pending.firstIndex { CGFloat(end - $0.along) < taperLength } ?? pending.count
                if settled > 0 {
                    touched = touched.union(markRaw(Array(pending[..<settled])))
                    pending.removeFirst(settled)
                }
                if !pending.isEmpty {
                    let checkpoint = keepsPreviews ? nil : beginTail()
                    let drawn = markRaw(BrushPlacement.taperedOut(pending, for: taperTemplate))
                    if let checkpoint { tail = (checkpoint, drawn) }
                    touched = touched.union(drawn)
                }
            }
            redraw(touched)
            return clipped(touched).rect
        }

        private func clipped(_ box: PixelBox) -> PixelBox {
            guard let plane else { return box }
            // Oil lights a pixel from its neighbours, so its redraw reaches
            // one further.
            if case .oil = kind {
                return PixelBox(minX: box.minX - 1, minY: box.minY - 1, maxX: box.maxX + 1, maxY: box.maxY + 1)
                    .intersection(plane.box)
            }
            return box.intersection(plane.box)
        }

        /// Whether a dab drawn thinner never lays more anywhere than the same
        /// dab drawn full: watercolour's water and path, and a marker's ink,
        /// only ever take the larger value, grow with the dab, and keep no
        /// other running state. Their tail is never taken back.
        private var keepsPreviews: Bool {
            switch kind {
            case .watercolour, .marker: true
            default: false
            }
        }

        /// Whether this medium's marks can be taken back: everything but the
        /// plain round, which stamps straight into the bitmap, and a smudge,
        /// which moves paint and never thins.
        private var canTakeBack: Bool {
            switch kind {
            case .round, .smudge, .none: false
            default: true
            }
        }

        /// Marks `dabs` into the stroke's fields, and the round and the smudge
        /// into the bitmap; says which pixels changed.
        private func markRaw(_ dabs: [BrushDab]) -> PixelBox {
            guard !dabs.isEmpty else { return .empty }
            var touched = PixelBox.empty
            switch kind {
            case .round(let tip):
                bitmap.saveGState()
                bitmap.translateBy(x: 0, y: CGFloat(bitmap.height))
                bitmap.scaleBy(x: 1, y: -1)
                bitmap.clip(to: clip)
                bitmap.concatenate(pointsToPixels)
                PaintRasterizer.mark(dabs, tip: tip, in: bitmap)
                bitmap.restoreGState()
                for dab in dabs {
                    let r = dab.diameter / 2
                    let rect = CGRect(x: dab.center.x - r, y: dab.center.y - r, width: dab.diameter,
                                      height: dab.diameter).applying(pointsToPixels).insetBy(dx: -1, dy: -1)
                    touched = touched.union(PixelBox(rect))
                }
                touched = touched.intersection(PixelBox(clip))
            case .dry(var dry, let colour):
                kind = .none
                touched = dry.mark(dabs)
                kind = .dry(dry, colour)
            case .marker(var marker, let colour, let under):
                kind = .none
                for dab in dabs { touched = touched.union(marker.mark(dab)) }
                kind = .marker(marker, colour, under: under)
            case .watercolour(var wash, let colour, let under):
                kind = .none
                for dab in dabs { touched = touched.union(wash.mark(dab)) }
                kind = .watercolour(wash, colour, under: under)
            case .airbrush(var spray, let colour):
                kind = .none
                for dab in dabs { touched = touched.union(spray.mark(dab)) }
                kind = .airbrush(spray, colour)
            case .oil(var oil, let under):
                kind = .none
                for dab in dabs { touched = touched.union(oil.mark(dab, under: under)) }
                kind = .oil(oil, under: under)
            case .smudge(var smudge, let read):
                guard let plane else { return .empty }
                kind = .none
                for dab in dabs { touched = touched.union(smudge.mark(dab, target: read, mirror: plane)) }
                kind = .smudge(smudge, read)
            case .none:
                break
            }
            return touched
        }

        /// Writes the stroke's fields over `box` of the bitmap.
        private func redraw(_ box: PixelBox) {
            guard let plane, !box.isEmpty else { return }
            switch kind {
            case .round, .smudge, .none: break
            case .dry(let dry, let colour): dry.replace(box, in: plane, colour: colour)
            case .marker(let marker, let colour, let under): marker.replace(box, in: plane, under: under, colour: colour)
            case .watercolour(let wash, let colour, let under): wash.replace(box, in: plane, under: under, colour: colour)
            case .airbrush(let spray, let colour): spray.replace(box, in: plane, colour: colour)
            case .oil(let oil, _): oil.replace(box, in: plane)
            }
        }

        private func beginTail() -> Kind {
            switch kind {
            case .dry(var dry, let colour):
                kind = .none
                let checkpoint = dry.beginTail()
                kind = .dry(dry, colour)
                return .dry(checkpoint, colour)
            case .marker(var marker, let colour, let under):
                kind = .none
                let checkpoint = marker.beginTail()
                kind = .marker(marker, colour, under: under)
                return .marker(checkpoint, colour, under: under)
            case .watercolour(var wash, let colour, let under):
                kind = .none
                let checkpoint = wash.beginTail()
                kind = .watercolour(wash, colour, under: under)
                return .watercolour(checkpoint, colour, under: under)
            case .airbrush(var spray, let colour):
                kind = .none
                let checkpoint = spray.beginTail()
                kind = .airbrush(spray, colour)
                return .airbrush(checkpoint, colour)
            case .oil(var oil, let under):
                kind = .none
                let checkpoint = oil.beginTail()
                kind = .oil(oil, under: under)
                return .oil(checkpoint, under: under)
            case .round, .smudge, .none:
                return kind
            }
        }

        /// Takes the drawn tail back off, and says which pixels it drew.
        private func takeBackTail() -> PixelBox? {
            guard let (checkpoint, drawn) = tail else { return nil }
            tail = nil
            // Each stroke is taken out with `if case` and `kind` emptied, so it
            // is the only copy of its fields while they are put back. Taken out
            // by a `switch` (on the pair, or on `kind` alone), a second copy
            // lived to the end of the switch and putting the fields back copied
            // every one of them whole first: 7.5 ms a move for a 500 point oil
            // stroke on a 12 megapixel layer (2026-10-27).
            if case .dry(var dry, let colour) = kind, case .dry(let back, _) = checkpoint {
                kind = .none
                dry.takeBackTail(to: back)
                kind = .dry(dry, colour)
            } else if case .marker(var marker, let colour, let under) = kind,
                      case .marker(let back, _, _) = checkpoint {
                kind = .none
                marker.takeBackTail(to: back)
                kind = .marker(marker, colour, under: under)
            } else if case .watercolour(var wash, let colour, let under) = kind,
                      case .watercolour(let back, _, _) = checkpoint {
                kind = .none
                wash.takeBackTail(to: back)
                kind = .watercolour(wash, colour, under: under)
            } else if case .airbrush(var spray, let colour) = kind, case .airbrush(let back, _) = checkpoint {
                kind = .none
                spray.takeBackTail(to: back)
                kind = .airbrush(spray, colour)
            } else if case .oil(var oil, let under) = kind, case .oil(let back, _) = checkpoint {
                kind = .none
                oil.takeBackTail(to: back)
                kind = .oil(oil, under: under)
            }
            return drawn
        }

        private func keepTail() {
            switch kind {
            case .dry(var dry, let colour):
                kind = .none
                dry.keepTail()
                kind = .dry(dry, colour)
            case .marker(var marker, let colour, let under):
                kind = .none
                marker.keepTail()
                kind = .marker(marker, colour, under: under)
            case .watercolour(var wash, let colour, let under):
                kind = .none
                wash.keepTail()
                kind = .watercolour(wash, colour, under: under)
            case .airbrush(var spray, let colour):
                kind = .none
                spray.keepTail()
                kind = .airbrush(spray, colour)
            case .oil(var oil, let under):
                kind = .none
                oil.keepTail()
                kind = .oil(oil, under: under)
            case .round, .smudge, .none:
                break
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
