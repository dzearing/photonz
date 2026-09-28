import Foundation

// A box over the tracks, and a range on just the tracks it crosses.
//
// Final Cut and Premiere both draw a box when a drag starts in empty timeline
// space: every clip it touches, on the tracks it crosses, is picked. Hold
// Option (or take Final Cut's Range tool, R) and the same drag picks a stretch
// of time on those tracks alone. Delete lifts that stretch, Shift-Delete takes
// it out and closes the gap, Cmd-T puts a transition on every cut inside it,
// and every other track is left exactly as it was: that is the difference from
// a range drawn on the ruler, which is every track (`RulerRange.swift`).
//
// A recording cut with the blade is ONE layer in several pieces, so a box over
// part of it picks the pieces it touches, not the whole recording: Delete on a
// box over one piece must never take the other two with it.
//
// A clip's own sound is drawn on an audio track under its picture, but it is
// the clip: a box or a range over only that sound takes the clip, the way
// Premiere's linked selection does.

/// One thing a box over the tracks picked: a whole clip, or one piece of a
/// clip cut into several.
public struct TimelinePick: Hashable, Sendable {
    public let layerID: UUID
    /// The piece, in play order; nil for the clip as a whole.
    public let piece: Int?

    public init(layerID: UUID, piece: Int?) {
        self.layerID = layerID
        self.piece = piece
    }
}

/// A stretch of time on some of the tracks, picked with Option held or the
/// Range tool.
public struct TrackRange: Hashable, Sendable {
    public var range: Range<Int>
    public var trackIDs: Set<UUID>

    public init(range: Range<Int>, trackIDs: Set<UUID>) {
        self.range = range
        self.trackIDs = trackIDs
    }
}

/// The geometry of a box drawn over the tracks.
public enum TimelineMarquee {

    /// One track's row, top and bottom, in the tracks' own space.
    public struct Row: Hashable, Sendable {
        public let trackID: UUID
        public let minY: Double
        public let maxY: Double

        public init(trackID: UUID, minY: Double, maxY: Double) {
            self.trackID = trackID
            self.minY = minY
            self.maxY = maxY
        }
    }

    /// The tracks whose rows a box from `span.lowerBound` to `span.upperBound`
    /// reaches, top to bottom. The gap between two rows is nobody's.
    public static func tracks(crossing span: ClosedRange<Double>, rows: [Row]) -> [UUID] {
        rows.filter { $0.minY <= span.upperBound && $0.maxY >= span.lowerBound }
            .sorted { $0.minY < $1.minY }
            .map(\.trackID)
    }

    /// The stretch of time a box covers, earliest end first, on the timeline.
    /// A box with no width still touches the moment it stands on.
    public static func stretch(fromMS anchor: Int, toMS ms: Int, lengthMS: Int) -> Range<Int> {
        let length = max(1, lengthMS)
        let lower = min(max(0, min(anchor, ms)), length - 1)
        let upper = min(max(anchor, ms), length)
        return lower..<max(lower + 1, upper)
    }
}

extension PhotonzDocument {

    // MARK: What is on a track

    /// Every layer on these tracks: the clips on each, the clips whose own
    /// sound is drawn on one, and everything inside them. From one laying
    /// out of the tracks.
    public func layerIDs(onTracks trackIDs: Set<UUID>) -> Set<UUID> {
        guard !trackIDs.isEmpty else { return [] }
        let layout = trackLayout()
        var tops = Set<UUID>()
        for track in trackIDs {
            tops.formUnion(layout.clips[track] ?? [])
            tops.formUnion(layout.linked[track] ?? [])
        }
        var ids = Set<UUID>()
        for layer in layers where tops.contains(layer.id) {
            ids.formUnion(layer.selfAndDescendants.map(\.id))
        }
        return ids
    }

    // MARK: What a box picks

    /// What a box over `range` of time on `onTracks` picks: every clip it
    /// touches, whole where it touches every piece of it (or it is in one),
    /// else each piece it touches. Nothing on a locked track, or locked
    /// itself. Top track first, then left to right; a clip reached through its
    /// own track and its sound's track is picked once.
    ///
    /// Touching means overlapping: a piece that only meets the box at an edge
    /// is not touched.
    public func marqueePicks(within range: Range<Int>, onTracks trackIDs: Set<UUID>) -> [TimelinePick] {
        guard !range.isEmpty, !trackIDs.isEmpty else { return [] }
        let layout = trackLayout()
        let byID = Dictionary(layers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<UUID>()
        var picks: [TimelinePick] = []
        for track in layout.tracks where trackIDs.contains(track.id) && !track.isLocked {
            let ids = (layout.clips[track.id] ?? []) + (layout.linked[track.id] ?? [])
            let found = ids.compactMap { id -> (start: Int, picks: [TimelinePick])? in
                guard !seen.contains(id), let layer = byID[id], !layer.isLocked,
                      let time = layer.time else { return nil }
                let touched = touchedPieces(of: layer, time: time, range: range)
                guard !touched.isEmpty else { return nil }
                seen.insert(id)
                let count = layer.clipPieces?.count ?? 1
                if touched.count == count || count <= 1 {
                    return (time.inMS, [TimelinePick(layerID: id, piece: nil)])
                }
                let start = time.inMS + (layer.clipPieces?.startMS(ofPiece: touched[0]) ?? 0)
                return (start, touched.map { TimelinePick(layerID: id, piece: $0) })
            }
            picks += found.sorted { $0.start < $1.start }.flatMap(\.picks)
        }
        return picks
    }

    /// The pieces of a clip that overlap `range`, in play order. A clip in one
    /// piece (or none written down) answers `[0]` where it overlaps at all.
    private func touchedPieces(of layer: Layer, time: LayerTime, range: Range<Int>) -> [Int] {
        guard let pieces = layer.clipPieces, pieces.count > 1 else {
            return time.inMS < range.upperBound && time.outMS > range.lowerBound ? [0] : []
        }
        return (0..<pieces.count).filter { index in
            guard let span = pieces.rangeMS(ofPiece: index) else { return false }
            return time.inMS + span.start < range.upperBound && time.inMS + span.end > range.lowerBound
        }
    }

    /// Where a pick sits on the document's clock, or nil where it is not there.
    public func span(of pick: TimelinePick) -> Range<Int>? {
        guard let layer = layer(id: pick.layerID), let time = layer.time else { return nil }
        guard let index = pick.piece else { return time.inMS..<time.outMS }
        guard let pieces = layer.clipPieces, let span = pieces.rangeMS(ofPiece: index) else { return nil }
        return (time.inMS + span.start)..<(time.inMS + span.end)
    }

    // MARK: Acting on picks

    /// Delete: every pick goes and leaves its gap, as one edit. Answers
    /// whether anything changed.
    @discardableResult
    public mutating func liftPicks(_ picks: [TimelinePick]) -> Bool {
        var changed = false
        for (id, span) in pickSpansLatestFirst(picks) {
            if liftStretch(fromMS: span.lowerBound, toMS: span.upperBound, onlyLayers: [id]) { changed = true }
        }
        return changed
    }

    /// Ripple Delete: every pick goes and the gap closes on its own track,
    /// every other track left where it was. Answers whether anything changed.
    @discardableResult
    public mutating func rippleDeletePicks(_ picks: [TimelinePick]) -> Bool {
        var changed = false
        for (id, span) in pickSpansLatestFirst(picks) {
            guard let track = trackID(ofClip: id) else { continue }
            if extractStretch(fromMS: span.lowerBound, toMS: span.upperBound, onTracks: [track]) { changed = true }
        }
        return changed
    }

    /// The picks as spans of their layers, pieces side by side run together,
    /// latest first: taking a later stretch out never moves an earlier one,
    /// so each is still where it was read when its turn comes.
    private func pickSpansLatestFirst(_ picks: [TimelinePick]) -> [(UUID, Range<Int>)] {
        var byLayer: [UUID: [Range<Int>]] = [:]
        for pick in Set(picks) {
            guard let span = span(of: pick) else { continue }
            byLayer[pick.layerID, default: []].append(span)
        }
        var out: [(UUID, Range<Int>)] = []
        for (id, spans) in byLayer {
            var merged: [Range<Int>] = []
            for span in spans.sorted(by: { $0.lowerBound < $1.lowerBound }) {
                if let last = merged.last, span.lowerBound <= last.upperBound {
                    merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, span.upperBound)
                } else {
                    merged.append(span)
                }
            }
            out += merged.map { (id, $0) }
        }
        return out.sorted { $0.1.lowerBound > $1.1.lowerBound }
    }

    // MARK: A range on some tracks

    /// Split at Range Edges on some tracks: a cut through every unlocked clip
    /// on them at both ends of `range`. Answers how many cuts were made.
    @discardableResult
    public mutating func splitEveryClip(atEdgesOf range: Range<Int>, onTracks trackIDs: Set<UUID>) -> Int {
        let only = layerIDs(onTracks: trackIDs)
        let locked = layerIDsOnLockedTracks()
        var cut = 0
        for ms in [range.lowerBound, range.upperBound] {
            for layer in allLayers where layer.holdsMedia && only.contains(layer.id) {
                guard let time = layer.time, ms > time.inMS, ms < time.outMS,
                      !locked.contains(layer.id) else { continue }
                if splitClip(layer.id, atMS: ms) { cut += 1 }
            }
        }
        return cut
    }

    /// The cuts a transition can go on inside `range`, on `onTracks` alone:
    /// a join inside a clip on one of them, or two clips on one of them that
    /// meet.
    public func transitionCuts(within range: Range<Int>, onTracks trackIDs: Set<UUID>) -> [DocumentCut] {
        let only = layerIDs(onTracks: trackIDs)
        return transitionCuts(within: range).filter { cut in
            switch cut.place {
            case let .join(clip, _): only.contains(clip)
            case let .edit(outgoing, incoming): only.contains(outgoing) && only.contains(incoming)
            }
        }
    }

    /// `kind` on every cut inside `range` on `onTracks`, each fitted to what it
    /// can pay for.
    @discardableResult
    public mutating func putTransitionOnEveryCut(_ kind: ClipTransitionKind, within range: Range<Int>,
                                                 onTracks trackIDs: Set<UUID>) -> EveryCutOutcome {
        putTransition(kind, onEvery: transitionCuts(within: range, onTracks: trackIDs).map(\.place))
    }
}
