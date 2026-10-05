import Foundation

// A range of time drawn on the ruler, and what it acts on.
//
// Final Cut's Range tool and Premiere's In and Out in one gesture. Drag along
// the ruler and the stretch you dragged over is marked across every track: the
// In and the Out ARE the range, so the keys, the Mark menu, Extract and Lift and
// an export all read the same two numbers (`TimelineMarks.swift`).
//
// A press on the ruler means one of five things, decided by where it lands:
//
// - on an end of the marked stretch: that end moves (the band's handles);
// - on the playhead: it scrubs, the way the ruler always has;
// - on a marker: the marker moves, and a click puts the playhead on it;
// - anywhere else: a new range, from where the press landed to where the hand
//   lets go. A press that never moves is a click, which puts the playhead
//   there and, outside the marked stretch, clears it; a double-click there
//   clears marks set with I and O too.
//
// Then the stretch is something to act on, and those actions live here too: a
// cut at both of its ends, a transition on every cut inside it, and captions
// written for just that stretch.

/// What a press on the ruler takes hold of.
public enum RulerGrip: Hashable, Sendable {
    /// The playhead: the drag scrubs.
    case playhead
    /// The start of the marked stretch.
    case inEdge
    /// The end of the marked stretch.
    case outEdge
    /// A marker: a drag moves it, a click puts the playhead on it.
    case marker(UUID)
    /// Nothing yet: a drag draws a new range, a click moves the playhead.
    case newRange
}

public enum RulerRange {

    /// What a press at `ms` takes hold of. `reachMS` is how near it has to be
    /// to be ON something, a few points of ruler in time.
    ///
    /// An end of the stretch wins over the playhead: its handle is what is
    /// drawn under the pointer, and the transport's scrub bar still scrubs.
    /// The playhead wins over a marker, as in Premiere, so a marker just
    /// dropped under it with M never stops the playhead being dragged off it;
    /// the nearest marker wins over drawing a range.
    public static func grip(atMS ms: Int, playheadMS: Int, markInMS: Int?, markOutMS: Int?,
                            markers: [TimelineMarker] = [], reachMS: Int) -> RulerGrip {
        let reach = max(1, reachMS)
        var edges: [(grip: RulerGrip, distance: Int)] = []
        if let markInMS, abs(ms - markInMS) <= reach { edges.append((.inEdge, abs(ms - markInMS))) }
        if let markOutMS, abs(ms - markOutMS) <= reach { edges.append((.outEdge, abs(ms - markOutMS))) }
        if let nearest = edges.min(by: { $0.distance < $1.distance }) { return nearest.grip }
        if abs(ms - playheadMS) <= reach { return .playhead }
        if let marker = markers.filter({ abs(ms - $0.atMS) <= reach })
            .min(by: { abs(ms - $0.atMS) < abs(ms - $1.atMS) }) {
            return .marker(marker.id)
        }
        return .newRange
    }

    /// Where a marker dragged to `ms` lands: snapped to the nearest of
    /// `snapTo` within `reachMS`, and never off either end of the ruler.
    public static func markerMoved(toMS ms: Int, lengthMS: Int,
                                   snapTo moments: [Int] = [], reachMS: Int = 0) -> Int {
        min(max(0, KeySnap.snapped(ms, to: moments, withinMS: reachMS)), max(0, lengthMS))
    }

    /// The range a drag from `anchor` to `ms` draws: earliest end first, on the
    /// ruler, the moving end snapped to the nearest of `snapTo` within
    /// `reachMS`. Nil where it is too short to take hold of.
    public static func drawn(fromMS anchor: Int, toMS ms: Int, lengthMS: Int,
                             snapTo moments: [Int] = [], reachMS: Int = 0) -> Range<Int>? {
        let length = max(0, lengthMS)
        let fixed = min(max(0, anchor), length)
        let moving = min(max(0, KeySnap.snapped(ms, to: moments, withinMS: reachMS)), length)
        let range = min(fixed, moving)..<max(fixed, moving)
        return range.count >= LayerTime.shortestMS ? range : nil
    }

    /// `range` with one end moved to `ms`, snapped like a drawn end. An end
    /// pushed past the other stops one shortest stretch short of it, so the
    /// range never turns inside out under the hand.
    public static func moving(_ edge: RulerGrip, of range: Range<Int>, toMS ms: Int, lengthMS: Int,
                              snapTo moments: [Int] = [], reachMS: Int = 0) -> Range<Int> {
        let length = max(0, lengthMS)
        let to = min(max(0, KeySnap.snapped(ms, to: moments, withinMS: reachMS)), length)
        switch edge {
        case .inEdge:
            let start = min(to, range.upperBound - LayerTime.shortestMS)
            return max(0, start)..<range.upperBound
        case .outEdge:
            let end = max(to, range.lowerBound + LayerTime.shortestMS)
            return range.lowerBound..<min(length, end)
        case .playhead, .marker, .newRange:
            return range
        }
    }
}

extension PhotonzDocument {

    // MARK: Marking one

    /// Set the In and the Out together, to a range drawn on the ruler.
    public mutating func markRange(_ range: Range<Int>) {
        let end = documentDurationMS
        let lower = min(max(0, range.lowerBound), end)
        let upper = min(max(lower, range.upperBound), end)
        markInMS = lower
        markOutMS = upper
    }

    /// Whether a plain click on the ruler at `ms` lets the marks go: it does
    /// outside the stretch they enclose, the way a click beside a Final Cut
    /// range drops it, and inside it only moves the playhead.
    public func clickOnRulerClearsMarks(atMS ms: Int) -> Bool {
        guard let range = markedRangeMS else { return false }
        return !(range.lowerBound...range.upperBound).contains(ms)
    }

    /// Whether a click of `clicks` presses on the ruler at `ms` lets the marks
    /// go. One click does beside a range drawn on the ruler that is still in
    /// hand, and only moves the playhead beside marks set with I and O, as in
    /// Premiere. A double-click beside them lets either go (user 2026-09-29).
    /// Inside the marked stretch nothing goes, however many clicks.
    public func rulerClickClearsMarks(atMS ms: Int, clicks: Int, rangeInHand: Bool) -> Bool {
        guard clickOnRulerClearsMarks(atMS: ms) else { return false }
        return clicks >= 2 || rangeInHand
    }

    /// What the ends of a range pull onto: every edit point, every marker, and
    /// both ends of the video.
    public func rangeSnapMoments() -> [Int] {
        var moments = Set(editPointMoments())
        moments.formUnion(markers.map(\.atMS))
        moments.insert(0)
        moments.insert(documentDurationMS)
        return moments.sorted()
    }

    // MARK: Split at Range Edges

    /// A cut through every unlocked clip at both ends of `range`. Answers how
    /// many cuts were made: an end already on a cut, or off a clip, makes none.
    @discardableResult
    public mutating func splitEveryClip(atEdgesOf range: Range<Int>) -> Int {
        splitEveryClip(atMS: range.lowerBound) + splitEveryClip(atMS: range.upperBound)
    }

    // MARK: Add Transition

    /// The cuts a transition can go on whose moment is inside `range`, ends
    /// included: a cut exactly on an end is the one somebody lined it up with.
    public func transitionCuts(within range: Range<Int>) -> [DocumentCut] {
        transitionCuts(among: nil).filter { (range.lowerBound...range.upperBound).contains($0.atMS) }
    }

    /// `kind` on every cut inside `range`, each fitted to what it can pay for,
    /// as `putTransitionOnEveryCut(_:among:)` does for picked clips.
    @discardableResult
    public mutating func putTransitionOnEveryCut(_ kind: ClipTransitionKind,
                                                 within range: Range<Int>) -> EveryCutOutcome {
        putTransition(kind, onEvery: transitionCuts(within: range).map(\.place))
    }
}

extension CaptionCues {

    /// Captions written again for one stretch: the lines of `existing` that
    /// start outside `range` stay, and the lines of `heard` that start inside
    /// it come in. A kept line that runs on over a new one is cut short where
    /// the new one starts, so two lines are never on screen at once.
    public static func replacing(_ existing: [CaptionCue], with heard: [CaptionCue],
                                 within range: Range<Int>) -> [CaptionCue] {
        let kept = existing.filter { !range.contains($0.inMS) }
        let taken = heard.filter { range.contains($0.inMS) }
        let sorted = (kept + taken).sorted { $0.inMS < $1.inMS }
        return sorted.enumerated().compactMap { index, cue in
            guard index + 1 < sorted.count else { return cue }
            let next = sorted[index + 1].inMS
            guard cue.outMS > next else { return cue }
            guard next - cue.inMS >= LayerTime.shortestMS else { return nil }
            return CaptionCue(words: cue.words.filter { $0.startMS < next }, inMS: cue.inMS, outMS: next)
        }
    }
}
