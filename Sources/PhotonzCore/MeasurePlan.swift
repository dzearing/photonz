import CoreGraphics
import Foundation

/// The label plate as a SHAPE to run into: the capsule a readout is drawn in,
/// so a line meeting it lands on the actual curve rather than on a bounding box
/// corner that is not there.
///
/// It is here, in the pure layer, because two different things draw the same
/// caliper now: the rasterizer that bakes it into a picture, and the SVG writer
/// that writes it out as shapes. A second copy of this arithmetic would be a
/// second answer to "where does the line stop", and the file would disagree
/// with the canvas by a pixel nobody could explain.
public struct LabelCapsule: Equatable, Sendable {
    public var rect: CGRect
    public var radius: CGFloat

    public init(rect: CGRect, radius: CGFloat) {
        self.rect = rect
        self.radius = radius
    }

    /// A capsule centred on `center`, `size` across, rounded the way every
    /// readout is.
    public init(center: CGPoint, size: CGSize) {
        self.init(rect: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                               width: size.width, height: size.height),
                  radius: Self.capsuleRadius(for: size))
    }

    /// The radius a readout's plate is rounded by: half its short side, so a
    /// readout (always wider than it is tall) is a capsule with semicircular
    /// caps.
    public static func capsuleRadius(for size: CGSize) -> CGFloat {
        min(size.width, size.height) / 2
    }

    public var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    public var clampedRadius: CGFloat {
        max(0, min(radius, rect.width / 2, rect.height / 2))
    }

    /// True while `p` is within the outline.
    ///
    /// A capsule is every point no further than `radius` from the rect shrunk
    /// by `radius`, which is one test for the flat sides and the round caps
    /// alike.
    public func contains(_ p: CGPoint) -> Bool {
        let r = clampedRadius
        let core = rect.insetBy(dx: r, dy: r)
        let dx = max(core.minX - p.x, 0, p.x - core.maxX)
        let dy = max(core.minY - p.y, 0, p.y - core.maxY)
        return dx * dx + dy * dy <= r * r
    }

    /// Where the straight run `from → toward` crosses the outline, or nil when
    /// there is no crossing to find — `from` is already inside, which is the
    /// caller's signal that the plate has swallowed it.
    ///
    /// The shape is convex and `toward` is inside it, so there is exactly one
    /// crossing and halving the run converges straight onto it.
    public func entry(from: CGPoint, toward: CGPoint) -> CGPoint? {
        guard !contains(from), contains(toward) else { return nil }
        func point(_ t: CGFloat) -> CGPoint {
            CGPoint(x: from.x + (toward.x - from.x) * t, y: from.y + (toward.y - from.y) * t)
        }
        var outside: CGFloat = 0, inside: CGFloat = 1
        for _ in 0..<32 {
            let mid = (outside + inside) / 2
            if contains(point(mid)) { inside = mid } else { outside = mid }
        }
        return point(inside)
    }
}

/// Everything drawing a measurement needs to know about its readout: where the
/// plate centres, the outline the measurement's own line has to stop on while
/// the plate still rides it, and the leader that keeps a relocated plate
/// attached to its subject (UX-PATTERNS D14).
public struct MeasurePlan: Equatable, Sendable {
    public struct Leader: Equatable, Sendable {
        public var from: CGPoint
        public var to: CGPoint

        public init(from: CGPoint, to: CGPoint) {
            self.from = from
            self.to = to
        }
    }

    public var center: CGPoint
    public var size: CGSize
    /// The plate's outline while it still rides the line; nil = the line is
    /// drawn whole, because the readout has moved off it.
    public var pill: LabelCapsule?
    public var leader: Leader?

    public init(center: CGPoint, size: CGSize, pill: LabelCapsule? = nil,
                leader: Leader? = nil) {
        self.center = center
        self.size = size
        self.pill = pill
        self.leader = leader
    }

    /// A relocated readout has to keep reading as part of its measurement. Up
    /// to this far (px) plain adjacency does that on its own; past it, a leader
    /// line draws the connection.
    public static let adjacencyReach: CGFloat = 10

    /// The segments a relocated readout's leader may hang from: the strokes
    /// this kind of measurement actually draws.
    public static func attachments(for measure: MeasureContent,
                                   geometry g: CaliperGeometry) -> [(CGPoint, CGPoint)] {
        measure.alignment == nil
            ? [(g.footA, g.headA), (g.headA, g.headB), (g.headB, g.footB)]
            : [(g.footA, g.footB)]
    }

    /// Where this measurement's readout lands, given the size its words came
    /// out at. The size is handed in because measuring glyphs needs a type
    /// engine and this layer has none.
    public static func make(_ measure: MeasureContent, geometry g: CaliperGeometry,
                            chipSize: CGSize) -> MeasurePlan {
        guard measure.showLabel else {
            return MeasurePlan(center: g.labelAnchor, size: .zero)
        }
        let center = measure.labelPosition(chipSize: chipSize)
        let outline = LabelCapsule(center: center, size: chipSize)

        // The measurement's own line stops on the outline only while the plate
        // is still riding it; once the readout has moved, the line is whole.
        let rides = measure.labelRidesTheLine(chipSize: chipSize)

        // Attach: from the closest point of the measurement's own strokes to
        // where that line meets the plate.
        var leader: Leader?
        if !rides,
           let anchor = nearestPoint(on: attachments(for: measure, geometry: g), to: center),
           let entry = outline.entry(from: anchor, toward: center),
           hypot(entry.x - anchor.x, entry.y - anchor.y) > adjacencyReach {
            leader = Leader(from: anchor, to: entry)
        }
        return MeasurePlan(center: center, size: chipSize, pill: rides ? outline : nil,
                           leader: leader)
    }

    /// The stretch of an alignment check's guide the plate is sitting on, if it
    /// still is: the solid runs and the dashes alike have to leave it alone, so
    /// a translucent plate never shows a stroke through it.
    public func guideGap(vertical: Bool) -> ClosedRange<CGFloat>? {
        guard let pill else { return nil }
        let centre = vertical ? pill.center.y : pill.center.x
        let half = vertical ? pill.rect.height / 2 : pill.rect.width / 2
        return (centre - half)...(centre + half)
    }

    /// Closest point on any of the measurement's own segments to `p`.
    public static func nearestPoint(on segments: [(CGPoint, CGPoint)], to p: CGPoint) -> CGPoint? {
        var best: CGPoint?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (a, b) in segments {
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared > 0
                ? min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1)
                : 0
            let q = CGPoint(x: a.x + dx * t, y: a.y + dy * t)
            let d = hypot(q.x - p.x, q.y - p.y)
            if d < bestDistance { bestDistance = d; best = q }
        }
        return best
    }

    /// `run` with `gap` cut out of it: nothing, one piece or two.
    public static func clip(_ run: ClosedRange<CGFloat>,
                            around gap: ClosedRange<CGFloat>?) -> [ClosedRange<CGFloat>] {
        guard let gap, gap.overlaps(run) else { return [run] }
        var pieces: [ClosedRange<CGFloat>] = []
        if run.lowerBound < gap.lowerBound { pieces.append(run.lowerBound...gap.lowerBound) }
        if gap.upperBound < run.upperBound { pieces.append(gap.upperBound...run.upperBound) }
        return pieces
    }

    /// A point from guide-relative coordinates: `cross` is the guide's own axis
    /// position (x for a vertical guide), `along` the span axis.
    public static func point(cross: CGFloat, along: CGFloat, vertical: Bool) -> CGPoint {
        vertical ? CGPoint(x: cross, y: along) : CGPoint(x: along, y: cross)
    }
}
