import Foundation

// The expanded cut (`docs/design/mocks/pages/video-transition-wt.html`,
// `#rowA` and `#rowB`, steps 5 to 9): a cut opened into the two clips it is
// made of, one row each, under the track. It is where an overlap stops being a
// metaphor: a dissolve is A running on past the cut while B comes up early,
// and the hatched frames are the spare each side spends. A dip spends none:
// each side fades inside the time it already had, and a hold on black parts
// them by the black.
//
// Opening it moves nothing. Every number here is read off the cut as it is.

/// A cut opened into its two clips, on the document's clock.
public struct ExpandedCut: Hashable, Sendable {

    /// One of the two rows: a clip where it was cut, and what the transition
    /// does at its edge.
    public struct Row: Hashable, Sendable {
        /// The clip's name, as its bar on the track says it.
        public let name: String
        /// Where its bar is on the track. A join's side is the piece either
        /// side of it, an edit point's the whole clip.
        public let startMS: Int
        public let endMS: Int
        /// The spare frames an overlap spends past this side's edge: the
        /// outgoing side running on after the cut, the incoming one coming up
        /// before it. Nil where nothing overlaps on this side.
        public let spent: Range<Int>?
        /// A fade inside the clip's own time, for a dip: the outgoing side's
        /// last stretch, the incoming side's first.
        public let fade: Range<Int>?
    }

    /// Where the cut is: where the outgoing side stops.
    public let atMS: Int
    /// A, the clip going out, and B, the one coming in.
    public let a: Row
    public let b: Row
    /// The stretch where both are on screen at once. Nil for a hard cut and
    /// for a dip, which never overlaps.
    public let both: Range<Int>?
    /// The colour a dip holds on between the two, which is real time.
    public let hold: Range<Int>?

    /// How the mock's dashed box over the overlap labels itself.
    public var bothLabel: String? {
        both.map { "both on screen · " + ClipTransitionCopy.seconds($0.count) }
    }

    /// The rows for a cut at `atMS` between a side that starts at
    /// `outgoingStartMS` and one that ends at `incomingEndMS`, with
    /// `transition` on it (nil for a hard cut).
    public init(atMS: Int, outgoing: (name: String, startMS: Int), incoming: (name: String, endMS: Int),
                transition: ClipTransition?) {
        self.atMS = atMS
        let holdMS = transition?.holdMS ?? 0
        let inStart = atMS + holdMS
        var aSpent: Range<Int>?, bSpent: Range<Int>?, aFade: Range<Int>?, bFade: Range<Int>?
        var both: Range<Int>?
        if let transition {
            if transition.kind.needsOverlap {
                if transition.afterMS > 0 { aSpent = atMS..<(atMS + transition.afterMS) }
                if transition.beforeMS > 0 { bSpent = (atMS - transition.beforeMS)..<atMS }
                both = (atMS - transition.beforeMS)..<(atMS + transition.afterMS)
            } else {
                if transition.beforeMS > 0 { aFade = (atMS - transition.beforeMS)..<atMS }
                if transition.afterMS > 0 { bFade = inStart..<(inStart + transition.afterMS) }
            }
        }
        a = Row(name: outgoing.name, startMS: outgoing.startMS, endMS: atMS, spent: aSpent, fade: aFade)
        b = Row(name: incoming.name, startMS: inStart, endMS: max(inStart, incoming.endMS),
                spent: bSpent, fade: bFade)
        self.both = both
        hold = holdMS > 0 ? atMS..<inStart : nil
    }
}

extension PhotonzDocument {

    /// The cut at `place` opened into its two rows, or nil where there is no
    /// cut. `drawing` stands in for what is written on the cut while a hand
    /// is dragging its length, so the rows keep up with the band.
    public func expandedCut(at place: TimelineCutPlace, drawing: ClipTransition? = nil) -> ExpandedCut? {
        guard let cut = documentCut(at: place) else { return nil }
        let transition = drawing ?? cut.cut.drawnTransition
        switch place {
        case .join:
            let outStart = cut.atMS - cut.cut.outgoing.lengthMS
            let inEnd = cut.atMS + cut.cut.incoming.lengthMS
            return ExpandedCut(atMS: cut.atMS, outgoing: (cut.outgoingName, outStart),
                               incoming: (cut.incomingName, inEnd), transition: transition)
        case let .edit(outgoing, incoming):
            guard let out = layer(id: outgoing)?.time, let into = layer(id: incoming)?.time else { return nil }
            return ExpandedCut(atMS: cut.atMS, outgoing: (cut.outgoingName, out.inMS),
                               incoming: (cut.incomingName, into.outMS), transition: transition)
        }
    }
}
