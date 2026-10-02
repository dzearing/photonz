import CoreGraphics
import Foundation

// An arrow that curves.
//
// Drag the handle in the middle of a selected arrow and its shaft bends into a
// smooth arc through the handle, the head turning to follow it, the way
// Keynote, Skitch and Excalidraw arrows do. Three of the four hand-made arrows
// the user drew as references on 2026-10-01 are curved.
//
// The bend is stored as WHERE THE HANDLE IS, stated against the straight line
// between the ends (`ArrowBend`), so moving either end turns and stretches the
// curve with it rather than leaving the handle behind. Nothing is baked: the
// curve is worked out from the two ends and the bend wherever the arrow is
// drawn (`AnnotationContent.spine`), which is the one spine the clean arrow,
// every hand-made style, the frame, the hit test and the SVG export all read.

/// Where an arrow's bend handle sits, as fractions of the straight line
/// between its ends: `along` from the tail (0) to the tip (1), and `across`
/// that line, positive to the left of travel in the document's top-left space
/// turned a quarter clockwise (the direction `(-dy, dx)`).
public struct ArrowBend: Hashable, Codable, Sendable {
    public var along: CGFloat
    public var across: CGFloat

    public init(along: CGFloat, across: CGFloat) {
        self.along = along
        self.across = across
    }

    /// The command that puts a bent arrow back on the straight line, on its
    /// right-click menu and in the Layer menu.
    public static let straightenTitle = "Straighten Arrow"
}

extension AnnotationContent {
    /// Whether this annotation can bend at all: arrows only.
    public var bends: Bool { shape == .arrow }

    /// The curve this annotation is drawn along, tail to tip. Straight for
    /// anything that does not bend and for an arrow nobody has bent.
    public var spine: ArrowSpine {
        guard bends, let bend else { return ArrowSpine(start: start, end: end) }
        let handle = Self.point(of: bend, start: start, end: end)
        // A quadratic passes through the point halfway along its parameter at
        // a quarter of each end plus half of its control point.
        return ArrowSpine(start: start,
                          control: CGPoint(x: 2 * handle.x - (start.x + end.x) / 2,
                                           y: 2 * handle.y - (start.y + end.y) / 2),
                          end: end)
    }

    /// Where the bend handle is drawn and grabbed, in the same space as
    /// `start` and `end`: on the curve, halfway along it.
    public var bendHandle: CGPoint {
        guard bends, let bend else {
            return CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        }
        return Self.point(of: bend, start: start, end: end)
    }

    /// The bend that puts the handle at `handle` (same space as `start`), or
    /// nil, a straight arrow, when the handle is within `straightWithin` of the
    /// straight line between the ends. That is how a person straightens an
    /// arrow by hand: drag the handle back onto the line.
    public func bend(through handle: CGPoint, straightWithin: CGFloat) -> ArrowBend? {
        guard bends else { return nil }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 1e-6 else { return nil }
        let ux = dx / length
        let uy = dy / length
        let rx = handle.x - start.x
        let ry = handle.y - start.y
        let along = (rx * ux + ry * uy) / length
        let across = rx * -uy + ry * ux
        guard abs(across) > max(straightWithin, 0) else { return nil }
        return ArrowBend(along: along, across: across / length)
    }

    static func point(of bend: ArrowBend, start: CGPoint, end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return CGPoint(x: start.x + bend.along * dx - bend.across * dy,
                       y: start.y + bend.along * dy + bend.across * dx)
    }

    /// The point a head is aimed FROM, for every piece of geometry that sizes
    /// and turns an ending by the line from a tail to a tip: a point behind the
    /// tip along the curve's own heading there, as far back as the curve is
    /// long. The tail itself when the arrow is straight, so nothing about a
    /// straight arrow moves.
    public var headAim: CGPoint {
        guard bends, bend != nil else { return start }
        let curve = spine
        let heading = curve.direction(at: 1)
        let length = curve.length
        return CGPoint(x: end.x - heading.dx * length, y: end.y - heading.dy * length)
    }

    /// The part of the spine the clean arrow's shaft is stroked along: from the
    /// tail to where the ending wants it to stop (inside a solid head, on the
    /// near edge of a hollow dot), measured back along the curve.
    public var shaftSpine: ArrowSpine {
        let stop = Geometry.arrowShaftEnd(start: headAim, end: end, strokeWidth: strokeWidth,
                                          scale: arrowheadScale, style: arrowheadStyle)
        guard bends, bend != nil else { return ArrowSpine(start: start, end: stop) }
        let curve = spine
        let back = hypot(end.x - stop.x, end.y - stop.y)
        return curve.leading(toDistance: max(curve.length - back, 0))
    }

    /// The clean arrow's shaft as a path: a straight line for a straight
    /// arrow, exactly as it has always been drawn, and one quadratic for a
    /// bent one.
    public var shaftPath: CGPath {
        let shaft = shaftSpine
        let path = CGMutablePath()
        path.move(to: shaft.start)
        if bends, bend != nil {
            path.addQuadCurve(to: shaft.end, control: shaft.control)
        } else {
            path.addLine(to: shaft.end)
        }
        return path
    }
}

extension ArrowSpine {
    /// The box the curve itself passes through (no stroke width).
    public var bounds: CGRect {
        var minX = min(start.x, end.x), maxX = max(start.x, end.x)
        var minY = min(start.y, end.y), maxY = max(start.y, end.y)
        // A quadratic's turning point on each axis, where it has one.
        func turn(_ s: CGFloat, _ c: CGFloat, _ e: CGFloat) -> CGFloat? {
            let denominator = s - 2 * c + e
            guard abs(denominator) > 1e-9 else { return nil }
            let t = (s - c) / denominator
            return t > 0 && t < 1 ? t : nil
        }
        if let t = turn(start.x, control.x, end.x) {
            let x = point(at: t).x
            minX = min(minX, x); maxX = max(maxX, x)
        }
        if let t = turn(start.y, control.y, end.y) {
            let y = point(at: t).y
            minY = min(minY, y); maxY = max(maxY, y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// How far `point` is from the nearest place on the curve.
    public func distance(to point: CGPoint) -> CGFloat {
        let steps = 64
        var best = CGFloat.infinity
        var previous = start
        for i in 1...steps {
            let next = self.point(at: CGFloat(i) / CGFloat(steps))
            best = min(best, Geometry.distance(from: point, toSegmentFrom: previous, to: next))
            previous = next
        }
        return best
    }

    /// The same curve from its start to `distance` along it, as a spine of its
    /// own (the front of a de Casteljau split).
    public func leading(toDistance distance: CGFloat) -> ArrowSpine {
        let t = parameter(atDistance: distance)
        return ArrowSpine(start: start,
                          control: CGPoint(x: start.x + (control.x - start.x) * t,
                                           y: start.y + (control.y - start.y) * t),
                          end: point(at: t))
    }
}
