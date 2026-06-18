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

    /// Where a zoom-callout's magnified box should land given the source box and canvas.
    /// Picks the quadrant with the most free space and returns the placed rect.
    public static func zoomCalloutPlacement(source: CGRect, magnification: CGFloat, canvas: CGSize, margin: CGFloat = 24) -> CGRect {
        let target = CGSize(width: source.width * magnification, height: source.height * magnification)
        let spaceRight = canvas.width - source.maxX
        let spaceLeft = source.minX
        let spaceBelow = canvas.height - source.maxY
        let spaceAbove = source.minY
        let best = max(spaceRight, spaceLeft, spaceBelow, spaceAbove)

        var origin: CGPoint
        if best == spaceRight {
            origin = CGPoint(x: source.maxX + margin, y: source.midY - target.height / 2)
        } else if best == spaceLeft {
            origin = CGPoint(x: source.minX - margin - target.width, y: source.midY - target.height / 2)
        } else if best == spaceBelow {
            origin = CGPoint(x: source.midX - target.width / 2, y: source.maxY + margin)
        } else {
            origin = CGPoint(x: source.midX - target.width / 2, y: source.minY - margin - target.height)
        }
        // Keep the callout on-canvas.
        origin.x = min(max(0, origin.x), max(0, canvas.width - target.width))
        origin.y = min(max(0, origin.y), max(0, canvas.height - target.height))
        return CGRect(origin: origin, size: target)
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

    /// Half the arrowhead's full width — how far each wing reaches from the
    /// arrow's axis. Layer frames must pad by at least this much or
    /// rasterization clips the head. Kept in lockstep with `arrowhead`'s wing
    /// math so frame padding and drawing never drift.
    public static func arrowheadHalfWidth(strokeWidth: CGFloat, scale: CGFloat = 1) -> CGFloat {
        // Bold by default: full width ≈ 5.6x a 6px shaft, with a generous floor
        // so even a 2px line gets a head you can actually see. Half of that is
        // the per-wing reach. `scale` is the user-facing size multiplier.
        max(strokeWidth * 2.8, 12) * max(scale, 0)
    }

    /// Length of the arrowhead from tip to the line joining its wings, before
    /// the short-arrow cap.
    private static func rawArrowheadLength(strokeWidth: CGFloat, scale: CGFloat) -> CGFloat {
        max(strokeWidth * 5, 22) * max(scale, 0)
    }

    /// Head length actually drawn: capped so a bold head never overshoots the
    /// start on a short drag (keeps a sliver of visible shaft).
    private static func effectiveArrowheadLength(strokeWidth: CGFloat, scale: CGFloat,
                                                 length: CGFloat) -> CGFloat {
        min(rawArrowheadLength(strokeWidth: strokeWidth, scale: scale), length * 0.85)
    }

    /// The filled triangle for an arrow's head: `[tip, leftWing, rightWing]`.
    /// The tip sits exactly at `end`; the wings sit behind it, perpendicular to
    /// the arrow's axis. Sized proportionally to `strokeWidth`, scaled by the
    /// user-facing `scale` (1 = the default, bold proportions).
    public static func arrowhead(start: CGPoint, end: CGPoint,
                                 strokeWidth: CGFloat, scale: CGFloat = 1) -> [CGPoint] {
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
    public static func arrowShaftEnd(start: CGPoint, end: CGPoint,
                                     strokeWidth: CGFloat, scale: CGFloat = 1) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return end }
        let headLength = effectiveArrowheadLength(strokeWidth: strokeWidth, scale: scale, length: length)
        // Stop 70% of the way up the head: well past the base (so the head's
        // wide body hides the cap) but short of the tip.
        let back = headLength * 0.7
        return CGPoint(x: end.x - dx / length * back, y: end.y - dy / length * back)
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
