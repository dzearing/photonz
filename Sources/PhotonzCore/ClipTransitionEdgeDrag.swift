import Foundation

/// One end of a transition's band in a hand: how long the transition is for
/// how far the hand has travelled, and whether something stopped it.
///
/// The promise is the one every drag on the timeline makes: **the end you took
/// hold of stays under the pointer.** Across the cut both ends move away from
/// it together, so the band grows by twice what the hand travelled and each
/// end by exactly that. To one side of the cut, the end on the cut cannot
/// leave it, so only the far end is a grip and the band grows by what the hand
/// travelled. When the spare media runs out, or the band is as short as one is
/// worth having, the end stops and the pointer moves on.
///
/// Every landing is worked out from where the drag STARTED, never from the
/// landing before, so coming back from a stop picks the end up at the hand
/// again rather than wherever it was left.
public struct ClipTransitionEdgeDrag: Hashable, Sendable {

    /// What stopped the end short of the pointer.
    public enum Stop: Hashable, Sendable {
        /// The longest the cut's spare media can pay for.
        case longest
        /// The shortest a transition is worth having.
        case shortest
    }

    public let startedAtMS: Int
    public let grabbedLeadingEdge: Bool
    /// Where the band is drawn against its cut (`drawnAlignment`).
    public let alignment: ClipTransitionAlignment
    public let longestMS: Int

    public init(startedAtMS: Int, grabbedLeadingEdge: Bool,
                alignment: ClipTransitionAlignment, longestMS: Int) {
        self.startedAtMS = startedAtMS
        self.grabbedLeadingEdge = grabbedLeadingEdge
        self.alignment = alignment
        self.longestMS = longestMS
    }

    /// Whether this end of the band is a grip. The end sitting ON the cut of a
    /// band placed before or after it is not: it cannot move off the cut, and
    /// a grip there could only move the other end, away from the hand.
    public static func canGrab(leadingEdge: Bool, of transition: ClipTransition) -> Bool {
        switch transition.drawnAlignment {
        case .across: true
        case .before: leadingEdge
        case .after: !leadingEdge
        }
    }

    /// Where one end of the band is drawn, in milliseconds from the cut:
    /// negative before it. The far end counts a dip's hold.
    public static func edgeOffsetMS(of transition: ClipTransition, leadingEdge: Bool) -> Int {
        leadingEdge ? -transition.beforeMS : transition.holdMS + transition.afterMS
    }

    /// How long the transition is with the hand `travelledMS` from where it
    /// took hold (positive is to the right), and what stopped it, if anything.
    public func landing(travelledMS: Int) -> (lengthMS: Int, stop: Stop?) {
        let outward = grabbedLeadingEdge ? -travelledMS : travelledMS
        let growth = alignment == .across ? outward * 2 : outward
        let wanted = startedAtMS + growth
        let longest = max(ClipTransition.shortestMS, longestMS)
        if wanted > longest { return (longest, .longest) }
        if wanted < ClipTransition.shortestMS { return (ClipTransition.shortestMS, .shortest) }
        return (wanted, nil)
    }
}

extension ClipTransitionCopy {

    /// What the bubble by the pointer says while a band's end is dragged: the
    /// length, in tenths of a second, or hundredths once the ruler is counting
    /// in hundredths itself, with the word for a stop when one is holding it.
    public static func dragReadout(_ ms: Int, stop: ClipTransitionEdgeDrag.Stop?, fine: Bool) -> String {
        let length = fine ? String(format: "%.2fs", Double(ms) / 1000) : seconds(ms)
        switch stop {
        case .longest: return "\(length) max"
        case .shortest: return "\(length) min"
        case nil: return length
        }
    }
}
