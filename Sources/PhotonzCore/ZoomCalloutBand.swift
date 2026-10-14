import CoreGraphics
import Foundation

/// The beam a zoom callout draws from the region it magnifies to the box it
/// magnifies it into: two leader lines, and the band of space between them,
/// tinted with the line colour (`ZoomCalloutContent.fillOpacity`).
///
/// A box callout's lines join nearest corners, as they always have. A circle
/// callout's lines are the two lines that just touch both circles (capsules on
/// a box that is not square), so they run from round edge to round edge rather
/// than dangling off the corners of the boxes the circles sit in. Either way
/// the band is the four ends of the two lines, so its edges ARE the lines.
extension Geometry {

    /// The box `corners` (top-left, top-right, bottom-right, bottom-left, as
    /// `corners(of:)` and `Layer.transformedCorners` give them) are drawn from:
    /// its upright size, and the transform that takes that upright box, with
    /// its top-left at the origin, onto them. Nil for a box with no width or
    /// no height.
    public static func boxPlacement(corners: [CGPoint]) -> (size: CGSize, transform: CGAffineTransform)? {
        guard corners.count == 4 else { return nil }
        let across = CGVector(dx: corners[1].x - corners[0].x, dy: corners[1].y - corners[0].y)
        let down = CGVector(dx: corners[3].x - corners[0].x, dy: corners[3].y - corners[0].y)
        let width = hypot(across.dx, across.dy)
        let height = hypot(down.dx, down.dy)
        guard width > 0, height > 0 else { return nil }
        let transform = CGAffineTransform(a: across.dx / width, b: across.dy / width,
                                          c: down.dx / height, d: down.dy / height,
                                          tx: corners[0].x, ty: corners[0].y)
        return (CGSize(width: width, height: height), transform)
    }

    /// The outline of a callout box (or its source) as points, for working out
    /// the lines that touch it. A rectangle is its four corners; a circle is
    /// the capsule `ZoomCalloutContent.effectiveCornerRadius` draws, finely
    /// enough that a line through two neighbouring points is within a
    /// hundredth of a point of the curve on any box a screen holds.
    public static func zoomCalloutOutline(corners: [CGPoint], shape: ZoomCalloutShape) -> [CGPoint] {
        guard shape == .circle, let placed = boxPlacement(corners: corners) else { return corners }
        let w = placed.size.width, h = placed.size.height
        let r = min(w, h) / 2
        let steps = 48
        let arcs: [(center: CGPoint, start: CGFloat)] = [
            (CGPoint(x: w - r, y: r), -.pi / 2),       // top right
            (CGPoint(x: w - r, y: h - r), 0),          // bottom right
            (CGPoint(x: r, y: h - r), .pi / 2),        // bottom left
            (CGPoint(x: r, y: r), .pi),                // top left
        ]
        var points: [CGPoint] = []
        points.reserveCapacity(arcs.count * (steps + 1))
        for arc in arcs {
            for step in 0...steps {
                let angle = arc.start + CGFloat(step) / CGFloat(steps) * .pi / 2
                let local = CGPoint(x: arc.center.x + r * cos(angle), y: arc.center.y + r * sin(angle))
                points.append(local.applying(placed.transform))
            }
        }
        return points
    }

    /// The two leader lines of a callout of `shape`, each running from the
    /// source to the box as it is DRAWN (`calloutCorners`). Empty when there
    /// is no line to draw, such as a circle sitting wholly inside the other.
    public static func leaderLines(source: CGRect, calloutCorners: [CGPoint],
                                   shape: ZoomCalloutShape) -> [(from: CGPoint, to: CGPoint)] {
        switch shape {
        case .rectangle:
            return leaderLines(source: source, calloutCorners: calloutCorners)
        case .circle:
            return touchingLines(
                zoomCalloutOutline(corners: corners(of: source.standardized), shape: .circle),
                zoomCalloutOutline(corners: calloutCorners, shape: .circle))
        }
    }

    /// The band between a callout's two leader lines: the source end of the
    /// first, its box end, the box end of the second, its source end. The
    /// shapes themselves are cut out of it where it is drawn, so it reaches
    /// their facing edges and never tints either picture. Empty when there are
    /// not two lines.
    public static func zoomCalloutBand(source: CGRect, calloutCorners: [CGPoint],
                                       shape: ZoomCalloutShape) -> [CGPoint] {
        let lines = leaderLines(source: source, calloutCorners: calloutCorners, shape: shape)
        guard lines.count == 2 else { return [] }
        return [lines[0].from, lines[0].to, lines[1].to, lines[1].from]
    }

    /// The two lines that touch both outlines from outside: the edges of the
    /// smallest convex shape round the pair that cross from one to the other.
    /// Each runs from a point of `first` to a point of `second`, in order round
    /// that shape, so the four ends make a band without a twist in it.
    static func touchingLines(_ first: [CGPoint], _ second: [CGPoint]) -> [(from: CGPoint, to: CGPoint)] {
        let tagged = first.map { ($0, 0) } + second.map { ($0, 1) }
        guard tagged.count >= 3 else { return [] }
        let sorted = tagged.sorted { $0.0.x != $1.0.x ? $0.0.x < $1.0.x : $0.0.y < $1.0.y }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        func chain(_ points: [(CGPoint, Int)]) -> [(CGPoint, Int)] {
            var hull: [(CGPoint, Int)] = []
            for point in points {
                while hull.count >= 2, cross(hull[hull.count - 2].0, hull[hull.count - 1].0, point.0) <= 0 {
                    hull.removeLast()
                }
                hull.append(point)
            }
            return hull
        }
        let lower = chain(sorted)
        let upper = chain(sorted.reversed())
        let hull = Array(lower.dropLast()) + Array(upper.dropLast())
        guard hull.count >= 3 else { return [] }
        var lines: [(from: CGPoint, to: CGPoint)] = []
        for index in hull.indices {
            let a = hull[index], b = hull[(index + 1) % hull.count]
            guard a.1 != b.1 else { continue }
            lines.append(a.1 == 0 ? (from: a.0, to: b.0) : (from: b.0, to: a.0))
        }
        return lines.count == 2 ? lines : []
    }
}
