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
