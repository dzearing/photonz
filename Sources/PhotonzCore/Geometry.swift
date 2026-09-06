import CoreGraphics
import Foundation

/// Pure geometry helpers used by crop, resize, skew, and the zoom-callout tool.
/// Everything in this file is deterministic and unit-tested.
public enum Geometry {

    /// Scales `size` to fit inside `bounds` preserving aspect ratio.
    public static func aspectFit(_ size: CGSize, in bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Scales `size` down to fit inside a square of side `maxDimension`,
    /// preserving aspect ratio and **never upscaling** (a small image stays
    /// small), rounded to whole pixels. The export planners' output-size cap.
    public static func downscaledToFit(_ size: CGSize, maxDimension: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0, maxDimension > 0 else { return .zero }
        let scale = min(1, min(maxDimension / size.width, maxDimension / size.height))
        return CGSize(width: (size.width * scale).rounded(),
                      height: (size.height * scale).rounded())
    }

    /// Scales `size` to fill `bounds` preserving aspect ratio (may overflow one axis).
    public static func aspectFill(_ size: CGSize, in bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = max(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Clamps a crop rectangle so it stays fully inside the canvas.
    public static func clampCrop(_ rect: CGRect, toCanvas canvas: CGSize) -> CGRect {
        let canvasRect = CGRect(origin: .zero, size: canvas)
        var r = rect.standardized.intersection(canvasRect)
        if r.isNull || r.isEmpty {
            r = CGRect(x: 0, y: 0, width: min(1, canvas.width), height: min(1, canvas.height))
        }
        return r
    }

    /// Resizes a canvas, returning the scale factors applied to layer frames.
    public static func resizeScale(from old: CGSize, to new: CGSize) -> CGPoint {
        guard old.width > 0, old.height > 0 else { return CGPoint(x: 1, y: 1) }
        return CGPoint(x: new.width / old.width, y: new.height / old.height)
    }

    /// An affine transform that skews around the rect's center.
    /// Angles are in radians; positive x-skew slants the top edge to the right.
    public static func skewTransform(xAngle: CGFloat, yAngle: CGFloat, around center: CGPoint) -> CGAffineTransform {
        let skew = CGAffineTransform(a: 1, b: tan(yAngle), c: tan(xAngle), d: 1, tx: 0, ty: 0)
        return CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(skew)
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    }

    /// Where a zoom-callout's magnified box should land given the source box,
    /// the canvas, and the callouts already on the picture.
    ///
    /// The box goes to the side of the source with the most free space, which
    /// is where it has always gone. `avoiding` is what changed on 2026-09-04:
    /// placement used to see the picture as empty, so a second callout drawn
    /// near the first landed squarely on top of it and neither could be read
    /// until one was dragged away. Now each side also offers spots slid a box
    /// further along it, and the first one clear of everything in `avoiding`
    /// wins.
    ///
    /// Scoring is `LabelPlacer`'s, the same ladder the measurement readout, the
    /// arrow caption and the legend go through, so "never cover what is already
    /// there" stays one rule in one place. Every candidate is clamped onto the
    /// canvas first, so the answer is always somewhere you can see it; when
    /// they are all covered the box keeps the spot it would have taken anyway,
    /// rather than hopping to whichever candidate happens to be least buried.
    public static func zoomCalloutPlacement(source: CGRect, magnification: CGFloat,
                                            canvas: CGSize, margin: CGFloat = 24,
                                            avoiding occupied: [CGRect] = []) -> CGRect {
        let target = CGSize(width: source.width * magnification, height: source.height * magnification)
        /// Each side of the source: how much room it has, where the box sits
        /// centred on it, and which way the box steps to make room for another.
        let sides: [(space: CGFloat, origin: CGPoint, step: CGPoint)] = [
            (canvas.width - source.maxX,
             CGPoint(x: source.maxX + margin, y: source.midY - target.height / 2),
             CGPoint(x: 0, y: target.height + margin)),
            (source.minX,
             CGPoint(x: source.minX - margin - target.width, y: source.midY - target.height / 2),
             CGPoint(x: 0, y: target.height + margin)),
            (canvas.height - source.maxY,
             CGPoint(x: source.midX - target.width / 2, y: source.maxY + margin),
             CGPoint(x: target.width + margin, y: 0)),
            (source.minY,
             CGPoint(x: source.midX - target.width / 2, y: source.minY - margin - target.height),
             CGPoint(x: target.width + margin, y: 0)),
        ]
        // Roomiest side first, and ties broken by the listed order — right,
        // left, below, above — which is the order the tool has always used.
        // (Sorting on space alone is not stable, so the tie is spelled out.)
        let ranked = sides.enumerated().sorted {
            $0.element.space == $1.element.space ? $0.offset < $1.offset
                                                 : $0.element.space > $1.element.space
        }
        // Centred on the source first, then a box out either way, then two.
        let steps: [CGFloat] = [0, 1, -1, 2, -2]
        var candidates: [LabelCandidate<CGRect>] = []
        for (sideRank, side) in ranked.enumerated() {
            for (stepRank, step) in steps.enumerated() {
                let origin = CGPoint(x: side.element.origin.x + side.element.step.x * step,
                                     y: side.element.origin.y + side.element.step.y * step)
                let rect = onCanvas(origin: origin, size: target, canvas: canvas)
                candidates.append(LabelCandidate(rect: rect, payload: rect,
                                                 cost: CGFloat(sideRank * steps.count + stepRank) * LabelPlacer.rankCost))
            }
        }
        let firstChoice = candidates.first?.rect ?? CGRect(origin: .zero, size: target)
        let avoid = [LabelAvoidance(rects: occupied, weight: .flat(LabelPlacer.subjectCost))]
        return LabelPlacer.best(among: candidates, avoiding: avoid) ?? firstChoice
    }

    /// A `size` box at `origin`, slid the least it can be to sit on the canvas.
    private static func onCanvas(origin: CGPoint, size: CGSize, canvas: CGSize) -> CGRect {
        CGRect(x: min(max(0, origin.x), max(0, canvas.width - size.width)),
               y: min(max(0, origin.y), max(0, canvas.height - size.height)),
               width: size.width, height: size.height)
    }

    /// Distance from `p` to the closest point on segment `a`–`b`.
    public static func distance(from p: CGPoint, toSegmentFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lengthSquared = abx * abx + aby * aby
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * abx + (p.y - a.y) * aby) / lengthSquared))
        return hypot(p.x - (a.x + t * abx), p.y - (a.y + t * aby))
    }

    /// The arrowhead's fixed base dimensions at `scale` = 1, in points. Since
    /// 10.4 the head is sized from `scale` ALONE — not the shaft width — so the
    /// Thickness slider changes the line without bloating the head. (At ×1.0
    /// these match the old strokeWidth-driven head at a 4px shaft / ×1.5, so the
    /// default arrow looks unchanged.)
    private static let baseArrowheadHalfWidth: CGFloat = 16
    private static let baseArrowheadLength: CGFloat = 30

    /// Half the arrowhead's full width — how far each wing reaches from the
    /// arrow's axis. Layer frames must pad by at least this much or
    /// rasterization clips the head. Kept in lockstep with `arrowhead`'s wing
    /// math so frame padding and drawing never drift.
    public static func arrowheadHalfWidth(strokeWidth: CGFloat, scale: CGFloat = 1) -> CGFloat {
        // Driven by `scale` alone, with one floor: a very thick shaft must never
        // out-width its own head (else the arrow stops reading as an arrow), so
        // the head is at least 0.6x the stroke per wing (full width ≥ 1.2x shaft).
        max(baseArrowheadHalfWidth * max(scale, 0), strokeWidth * 0.6)
    }

    /// Length of the arrowhead from tip to the line joining its wings, before
    /// the short-arrow cap. Like the width, driven by `scale` with a thick-shaft
    /// floor so the head stays proportionate to a heavy line.
    private static func rawArrowheadLength(strokeWidth: CGFloat, scale: CGFloat) -> CGFloat {
        max(baseArrowheadLength * max(scale, 0), strokeWidth * 1.1)
    }

    /// Head length actually drawn: capped so a bold head never overshoots the
    /// start on a short drag (keeps a sliver of visible shaft).
    private static func effectiveArrowheadLength(strokeWidth: CGFloat, scale: CGFloat,
                                                 length: CGFloat) -> CGFloat {
        min(rawArrowheadLength(strokeWidth: strokeWidth, scale: scale), length * 0.85)
    }

    /// How far a round ending's edge sits from the point it marks. Set so the
    /// dot carries about the same weight of ink as the triangle it replaces
    /// (equal area would be ×0.77 of the half-width; ×0.75 is that, rounded to
    /// a number worth reading).
    private static let roundHeadRadiusRatio: CGFloat = 0.75

    /// A round ending's radius: driven by `scale` like every other ending, with
    /// a floor of its OWN. The triangle's floor keeps a heavy shaft from
    /// out-widening its head; a dot needs a bigger one, because a circle only
    /// a fraction wider than the line it ends reads as a bulge in the line
    /// rather than as a mark on the point. A dot is never narrower than twice
    /// the shaft.
    private static func roundHeadRadius(strokeWidth: CGFloat, scale: CGFloat) -> CGFloat {
        max(baseArrowheadHalfWidth * max(scale, 0) * roundHeadRadiusRatio, max(strokeWidth, 0))
    }

    /// The circle a round ending occupies, centred on the point it marks; nil
    /// for every ending that is not a circle.
    ///
    /// This is the ONE place that says how big a dot is, so the frame that
    /// makes room for it and the rasterizer that draws it cannot drift.
    public static func arrowheadCircle(at end: CGPoint,
                                       strokeWidth: CGFloat, scale: CGFloat = 1,
                                       style: ArrowheadStyle) -> (center: CGPoint, radius: CGFloat)? {
        guard style.isRound else { return nil }
        return (end, roundHeadRadius(strokeWidth: strokeWidth, scale: scale))
    }

    /// How far an ending's ink reaches from the point it marks, in every
    /// direction. Frame padding is this, so an ending never clips at the edge
    /// of its own layer.
    public static func arrowheadReach(strokeWidth: CGFloat, scale: CGFloat = 1,
                                      style: ArrowheadStyle) -> CGFloat {
        let cap = max(strokeWidth, 0) / 2
        switch style {
        case .plain:
            return cap
        case .triangle:
            return arrowheadHalfWidth(strokeWidth: strokeWidth, scale: scale)
        case .open:
            // An outline hangs half its own stroke outside the path it follows.
            return arrowheadHalfWidth(strokeWidth: strokeWidth, scale: scale) + cap
        case .dot:
            return roundHeadRadius(strokeWidth: strokeWidth, scale: scale)
        case .hollowDot:
            return roundHeadRadius(strokeWidth: strokeWidth, scale: scale) + cap
        }
    }

    /// The filled triangle for an arrow's head: `[tip, leftWing, rightWing]`.
    /// The tip sits exactly at `end`; the wings sit behind it, perpendicular to
    /// the arrow's axis. Sized proportionally to `strokeWidth`, scaled by the
    /// user-facing `scale` (1 = the default, bold proportions).
    ///
    /// `style` picks which ending those three points describe: the solid
    /// triangle fills them, the open head strokes the two lines through the
    /// tip, and every other ending draws no wings at all (a circle comes from
    /// `arrowheadCircle`, a plain line from nothing).
    public static func arrowhead(start: CGPoint, end: CGPoint,
                                 strokeWidth: CGFloat, scale: CGFloat = 1,
                                 style: ArrowheadStyle = .triangle) -> [CGPoint] {
        guard style == .triangle || style == .open else { return [] }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return [end, end, end] }

        let headLength = effectiveArrowheadLength(strokeWidth: strokeWidth, scale: scale, length: length)
        let halfWidth = arrowheadHalfWidth(strokeWidth: strokeWidth, scale: scale)
        let ux = dx / length
        let uy = dy / length
        let base = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)
        // Perpendicular unit vector.
        let px = -uy
        let py = ux
        return [end,
                CGPoint(x: base.x + px * halfWidth, y: base.y + py * halfWidth),
                CGPoint(x: base.x - px * halfWidth, y: base.y - py * halfWidth)]
    }

    /// Where the arrow's shaft line should terminate so its (round) cap never
    /// pokes past the sharp arrowhead tip. Sits a little inside the head so the
    /// filled triangle covers the join with no gap. Falls back to `end` for a
    /// zero-length arrow.
    ///
    /// Each ending wants a different stop. A solid triangle hides the cap
    /// inside itself. An open head is one V the line runs INTO, so the shaft
    /// reaches the tip and the join reads as a single stroke; a solid dot
    /// covers the cap the same way a triangle does; and a hollow dot has to
    /// stay hollow, so the shaft stops dead on its near edge rather than
    /// skewering it.
    public static func arrowShaftEnd(start: CGPoint, end: CGPoint,
                                     strokeWidth: CGFloat, scale: CGFloat = 1,
                                     style: ArrowheadStyle = .triangle) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return end }
        let back: CGFloat
        switch style {
        case .open, .plain, .dot:
            return end
        case .triangle:
            // Stop 70% of the way up the head: well past the base (so the head's
            // wide body hides the cap) but short of the tip.
            back = effectiveArrowheadLength(strokeWidth: strokeWidth, scale: scale,
                                            length: length) * 0.7
        case .hollowDot:
            back = min(arrowheadCircle(at: end, strokeWidth: strokeWidth,
                                       scale: scale, style: style)?.radius ?? 0,
                       length)
        }
        return CGPoint(x: end.x - dx / length * back, y: end.y - dy / length * back)
    }

    /// The box an ending's ink actually covers, or nil when it draws none.
    /// The selection frame round an arrow follows this, so a dot's overshoot
    /// past the point it marks is inside the box the user sees.
    public static func arrowheadBounds(start: CGPoint, end: CGPoint,
                                       strokeWidth: CGFloat, scale: CGFloat = 1,
                                       style: ArrowheadStyle) -> CGRect? {
        if let circle = arrowheadCircle(at: end, strokeWidth: strokeWidth,
                                        scale: scale, style: style) {
            let reach = circle.radius + (style.isOutlined ? max(strokeWidth, 0) / 2 : 0)
            return CGRect(x: circle.center.x - reach, y: circle.center.y - reach,
                          width: 2 * reach, height: 2 * reach)
        }
        let wings = arrowhead(start: start, end: end, strokeWidth: strokeWidth,
                              scale: scale, style: style)
        guard let first = wings.first else { return nil }
        var box = CGRect(origin: first, size: .zero)
        for point in wings.dropFirst() {
            box = box.union(CGRect(origin: point, size: .zero))
        }
        return style.isOutlined ? box.insetBy(dx: -strokeWidth / 2, dy: -strokeWidth / 2) : box
    }

    /// The two leader-line segments connecting a zoom callout to its source box.
    /// Returns (from, to) pairs joining the nearest corners.
    public static func leaderLines(source: CGRect, callout: CGRect) -> [(from: CGPoint, to: CGPoint)] {
        func corners(_ r: CGRect) -> [CGPoint] {
            [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
             CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
        }
        let s = corners(source)
        let c = corners(callout)
        // Pair each source corner with its nearest callout corner; keep the two shortest pairs.
        var pairs: [(from: CGPoint, to: CGPoint, d: CGFloat)] = []
        for sc in s {
            let nearest = c.min { hypot($0.x - sc.x, $0.y - sc.y) < hypot($1.x - sc.x, $1.y - sc.y) }!
            pairs.append((sc, nearest, hypot(nearest.x - sc.x, nearest.y - sc.y)))
        }
        pairs.sort { $0.d < $1.d }
        return Array(pairs.prefix(2)).map { (from: $0.from, to: $0.to) }
    }
}
