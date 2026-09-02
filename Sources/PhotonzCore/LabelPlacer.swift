import CoreGraphics
import Foundation

/// A spot a label could take: where it would land, what the surface calls it,
/// and what the surface has already decided it costs.
///
/// `cost` carries everything only the surface can judge: its own preference
/// order (first choice cheapest), how far it had to nudge, and whether the
/// leader line home would run across something. Everything a spot costs
/// because of what is UNDER it is `LabelPlacer`'s job, not the surface's.
public struct LabelCandidate<Payload> {
    public var rect: CGRect
    public var payload: Payload
    public var cost: CGFloat

    public init(rect: CGRect, payload: Payload, cost: CGFloat = 0) {
        self.rect = rect
        self.payload = payload
        self.cost = cost
    }
}

/// Something a label should keep off, and how strongly.
public struct LabelAvoidance: Sendable {
    public enum Weight: Sendable {
        /// Never. A spot touching one of these is out of the running, not
        /// merely expensive: chrome drawn on top of a label makes it invisible,
        /// and an invisible label is not a worse spot, it is no spot at all.
        case forbidden
        /// One flat charge for touching any of them, however many and however
        /// deeply. This is what a subject costs: covering two is no worse than
        /// covering one, so when every spot is on something the label stays
        /// where you look for it instead of hopping to the least-bad one.
        case flat(CGFloat)
        /// Charged in proportion to how far the label reaches IN, measured
        /// across one axis as a share of the label's own extent on it — the
        /// full charge when a neighbour swallows the label, a quarter when it
        /// dips a quarter of its height past the neighbour's near edge.
        ///
        /// Depth rather than area, because what decides whether a number reads
        /// as the next row's is how far into that row it hangs. Sliding the
        /// same label ALONG its line does not move it into or out of that row,
        /// so it must not change the price either, or the label buys itself a
        /// discount by drifting off centre.
        case depth(CGFloat, horizontal: Bool)
    }

    public var rects: [CGRect]
    public var weight: Weight

    public init(rects: [CGRect], weight: Weight) {
        self.rects = rects
        self.weight = weight
    }
}

/// The one place that decides where a label goes.
///
/// Every label Photonz draws on the picture — a measurement's readout, an
/// arrow's caption, the roles legend — comes through here. Each surface knows
/// its own geometry and lists the spots it would accept, in the order it
/// prefers them; this scores them against what is underneath and returns the
/// winner. So UX-PATTERNS D14 ("a callout never covers what it is talking
/// about") is one rule in one place, and a fix to it reaches all three at once.
///
/// The costs below are a ladder, and the gaps between the rungs are the point:
/// falling off the picture beats covering the subject, which beats clipping a
/// neighbour, which beats dragging a leader across something, which beats
/// taking a lower-ranked spot. Nothing lower can ever outvote something higher,
/// however many times it is charged.
public enum LabelPlacer {

    /// Running off the picture is the worst thing a label can do: one you
    /// cannot read is not a label at all.
    public static let offBoundsCost: CGFloat = 500
    /// Covering what the label is describing. Charged flat — see
    /// `LabelAvoidance.Weight.flat`.
    public static let subjectCost: CGFloat = 400
    /// Covering a neighbour: another readout, the row next door. Charged by
    /// depth — see `LabelAvoidance.Weight.depth`.
    public static let overlapCost: CGFloat = 120
    /// Dragging the leader line home across something it should not cross.
    /// About what clipping a neighbour costs, which is what makes staying put
    /// the better trade whenever the clip is a shallow one.
    public static let crossingCost: CGFloat = 100
    /// Each step down a surface's own preference order.
    public static let rankCost: CGFloat = 4
    /// Each step a label slides along its line away from centre.
    public static let nudgeCost: CGFloat = 1
    /// A gentle pull back toward the thing being labelled, so of two clear
    /// spots the closer one wins. Per point of travel, so it stays a
    /// tie-breaker: even a thousand points of it cannot buy a spot on the
    /// subject.
    public static let travelCost: CGFloat = 0.02

    /// The best of `candidates`, or nil when every one of them is forbidden.
    ///
    /// Ties go to the earliest candidate, so a surface's preference order is
    /// still what decides between two equally good spots.
    ///
    /// - Parameters:
    ///   - candidates: every spot the surface would accept, best first.
    ///   - avoiding: what is under the label and what each kind of hit costs.
    ///   - bounds: the picture. Nil skips the edge check entirely, for a
    ///     surface that has already clamped its candidates.
    ///   - anchor: the thing being labelled. Nil skips the pull toward it, for
    ///     a surface whose spots are fixed slots rather than a distance from
    ///     something.
    public static func best<Payload>(among candidates: [LabelCandidate<Payload>],
                                     avoiding: [LabelAvoidance],
                                     within bounds: CGRect? = nil,
                                     anchoredAt anchor: CGPoint? = nil) -> Payload? {
        var best: Payload?
        var bestScore = CGFloat.greatestFiniteMagnitude
        for candidate in candidates {
            let rect = candidate.rect
            var score = candidate.cost
            var vetoed = false
            for avoidance in avoiding {
                switch avoidance.weight {
                case .forbidden:
                    if avoidance.rects.contains(where: { $0.intersects(rect) }) { vetoed = true }
                case .flat(let cost):
                    if avoidance.rects.contains(where: { $0.intersects(rect) }) { score += cost }
                case .depth(let cost, let horizontal):
                    score += cost * intrusion(of: rect, into: avoidance.rects,
                                              horizontal: horizontal)
                }
                if vetoed { break }
            }
            if vetoed { continue }
            if let bounds, !bounds.contains(rect) { score += offBoundsCost }
            if let anchor {
                score += hypot(rect.midX - anchor.x, rect.midY - anchor.y) * travelCost
            }
            if score < bestScore {
                bestScore = score
                best = candidate.payload
            }
        }
        return best
    }

    /// How far `rect` reaches into each of `others` across one axis, as a share
    /// of its own extent on that axis. Counted once per rect rather than as a
    /// union, so two neighbours over the same spot cost twice.
    static func intrusion(of rect: CGRect, into others: [CGRect],
                          horizontal: Bool) -> CGFloat {
        let extent = horizontal ? rect.height : rect.width
        guard extent > 0 else { return others.contains { $0.intersects(rect) } ? 1 : 0 }
        return others.reduce(0) { total, other in
            let hit = rect.intersection(other)
            guard !hit.isNull, !hit.isEmpty else { return total }
            return total + (horizontal ? hit.height : hit.width) / extent
        }
    }

    /// Whether the straight run from `a` to `b` passes through any of `rects`.
    /// Liang-Barsky, so a diagonal run (a nudged sideways readout, an arrow
    /// drawn at any angle) is judged as honestly as a square one.
    public static func segment(from a: CGPoint, to b: CGPoint, crosses rects: [CGRect]) -> Bool {
        let dx = b.x - a.x, dy = b.y - a.y
        guard dx != 0 || dy != 0 else { return false }
        return rects.contains { rect in
            var enter: CGFloat = 0, exit: CGFloat = 1
            for (p, q) in [(-dx, a.x - rect.minX), (dx, rect.maxX - a.x),
                           (-dy, a.y - rect.minY), (dy, rect.maxY - a.y)] {
                if p == 0 {
                    if q < 0 { return false }
                    continue
                }
                let t = q / p
                if p < 0 { enter = max(enter, t) } else { exit = min(exit, t) }
                if enter > exit { return false }
            }
            return true
        }
    }
}
