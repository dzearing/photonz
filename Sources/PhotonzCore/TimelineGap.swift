import Foundation

// A gap between two clips on a track, and closing it.
//
// A Lift (;), or a clip dragged away, leaves an empty stretch on its track.
// Premiere and Final Cut both let a person click that stretch and press Delete,
// or right-click it and choose Ripple Delete, and the clips after it on that
// track slide back to close it. Before this the only way here was a range drawn
// over the gap and Shift-Delete.
//
// The rest of the edit goes along, the way it does when a piece of a clip is
// deleted (`StretchRemoval.swift`) and in Premiere with sync lock on, so a
// title or a music cue is still over the moment it was placed on:
//
// - **Every clip after the gap on its track**, each by the gap's length, with
//   everything inside it. A clip's own sound is the clip, so it goes along.
// - **The captions over those clips**, on whatever track they are on: they
//   are the words of the recording that moves, and a caption left behind
//   would be under the wrong picture.
// - **Everything else that starts after the gap ends**, on any track: titles,
//   music, other clips, captions. Something that starts before it ends (music
//   under the whole take, a title over the gap) stays as it was, with what is
//   inside it; cutting into it would be cutting something nobody pointed at.
//   On a locked track, or locked itself, it stays put too: locking says so.
//
// It is refused, rather than half done, where something that has to move
// cannot: a clip or a caption on a locked track (a clip whose own sound is
// drawn on a locked track included: the sound is the clip), a locked layer, or
// a moved clip, sound, title or caption landing on something already there on
// its own track. The refusal names which (`GapCloseRefusal`), so a Delete that
// changed nothing says what is in the way rather than only beeping.

/// An empty stretch between two clips on one track, or before the first.
public struct TimelineGap: Hashable, Sendable {
    public var trackID: UUID
    /// From where the clip before it ends (or 0:00) to where the next starts.
    public var range: Range<Int>

    public init(trackID: UUID, range: Range<Int>) {
        self.trackID = trackID
        self.range = range
    }

    public var lengthMS: Int { range.upperBound - range.lowerBound }
}

/// Why a gap will not close: what a person has to unlock or move first.
public enum GapCloseRefusal: Hashable, Sendable {
    /// A track, or a layer, that has to move is locked. Its name.
    case locked(String)
    /// Something that stays where it is and that a moved clip, sound or
    /// caption would land on. Its name, or "A caption" for a caption line.
    case inTheWay(String)
    /// The gap has filled up or moved since it was picked.
    case gone

    /// `Audio is locked`, `Music is in the way`: what the notice under the
    /// canvas says, a label inside the chrome budget however long the name.
    public var reading: String {
        switch self {
        case .locked(let name): Self.fitted(name, " is locked")
        case .inTheWay(let name): Self.fitted(name, " is in the way")
        case .gone: "Nothing to close"
        }
    }

    static func fitted(_ name: String, _ tail: String) -> String {
        let room = CopyBudget.chromeLine - tail.count
        guard name.count > room else { return name + tail }
        let cut = name.prefix(max(1, room - 1)).trimmingCharacters(in: .whitespaces)
        return cut + "\u{2026}" + tail
    }
}

extension PhotonzDocument {

    /// The gap on `trackID` that `ms` stands in: empty there, with a clip
    /// after it. Nil on a clip, after the last clip, and on a Captions track,
    /// whose spaces are the pauses between lines rather than holes.
    public func gap(onTrack trackID: UUID, atMS ms: Int) -> TimelineGap? {
        guard ms >= 0, let track = track(id: trackID), track.kind != .captions else { return nil }
        let layout = trackLayout()
        let spans = occupants(onTrack: trackID, layout: layout).map(\.span)
        guard !spans.contains(where: { $0.contains(ms) }),
              let next = spans.map(\.lowerBound).filter({ $0 > ms }).min() else { return nil }
        let start = spans.map(\.upperBound).filter { $0 <= ms }.max() ?? 0
        guard next > start else { return nil }
        return TimelineGap(trackID: trackID, range: start..<next)
    }

    /// Every gap on `trackID`, earliest first: where a click picks one.
    public func gaps(onTrack trackID: UUID) -> [TimelineGap] {
        guard let track = track(id: trackID), track.kind != .captions else { return [] }
        let spans = occupants(onTrack: trackID, layout: trackLayout()).map(\.span)
            .sorted { $0.lowerBound < $1.lowerBound }
        var found: [TimelineGap] = []
        var reached = 0
        for span in spans {
            if span.lowerBound > reached {
                found.append(TimelineGap(trackID: trackID, range: reached..<span.lowerBound))
            }
            reached = max(reached, span.upperBound)
        }
        return found
    }

    /// Whether `closeGap` would close it: the gap is still there, and
    /// everything that has to move can, without landing on anything.
    public func canCloseGap(_ gap: TimelineGap) -> Bool {
        gapCloseRefusal(gap) == nil
    }

    /// Why `closeGap` would refuse it, or nil where it would close.
    public func gapCloseRefusal(_ gap: TimelineGap) -> GapCloseRefusal? {
        if case .refused(let why) = closingGap(gap) { return why }
        return nil
    }

    /// Ripple Delete on a gap: every clip after it on its track, the
    /// captions over them, and everything else that starts after it, move
    /// earlier by its length. One edit; answers
    /// whether it was made, and changes nothing when it was not.
    @discardableResult
    public mutating func closeGap(_ gap: TimelineGap) -> Bool {
        guard case .closed(let closed) = closingGap(gap) else { return false }
        self = closed
        return true
    }

    /// The gap closed, or why not.
    private enum Closing {
        case closed(PhotonzDocument)
        case refused(GapCloseRefusal)
    }

    private func closingGap(_ gap: TimelineGap) -> Closing {
        guard gap.lengthMS > 0, self.gap(onTrack: gap.trackID, atMS: gap.range.lowerBound) == gap
        else { return .refused(.gone) }
        let layout = trackLayout()
        let after = occupants(onTrack: gap.trackID, layout: layout).filter { $0.span.lowerBound >= gap.range.upperBound }
        guard !after.isEmpty else { return .refused(.gone) }
        let clipIDs = Set(after.map(\.id))
        // What has to move: the clips after the gap and the words over them.
        var bound: Set<UUID> = []
        for layer in layers where clipIDs.contains(layer.id) {
            bound.formUnion(layer.selfAndDescendants.filter { $0.time != nil }.map(\.id))
        }
        let spans = after.map(\.span)
        forEachLayer { layer in
            guard layer.isCaption, let time = layer.time,
                  spans.contains(where: { $0.contains(time.inMS) }) else { return }
            bound.insert(layer.id)
        }
        // Everything that has to move has to be free to: the gap's own track
        // named first, then the rest top to bottom.
        let locked = layout.tracks.filter(\.isLocked)
        var pinned: Set<UUID> = []
        for track in locked.filter({ $0.id == gap.trackID }) + locked.filter({ $0.id != gap.trackID }) {
            let tops = Set((layout.clips[track.id] ?? []) + (layout.linked[track.id] ?? []))
            let held = layers.filter { tops.contains($0.id) }.flatMap { $0.selfAndDescendants.map(\.id) }
            if held.contains(where: bound.contains) { return .refused(.locked(track.name)) }
            pinned.formUnion(held)
        }
        if let held = allLayers.first(where: { bound.contains($0.id) && $0.isLocked }) {
            return .refused(.locked(Self.named(held)))
        }
        let moving = bound.union(carriedAlong(after: gap.range.upperBound, except: pinned))
        var moved = self
        for id in moving {
            moved.updateLayer(id: id) { layer in
                guard let time = layer.time else { return }
                layer.time = time.moved(toInMS: time.inMS - gap.lengthMS)
                layer.captionWords = layer.captionWords?.map { $0.shifted(byMS: -gap.lengthMS) }
            }
        }
        if let still = moved.landedOn(moving) {
            return .refused(.inTheWay(layer(id: still).map(Self.named) ?? "Something"))
        }
        moved.refreshDuration()
        return .closed(moved)
    }

    /// Everything that starts at or after `end` and is free to move, with
    /// what is inside it. Something that starts earlier stays, and so does
    /// what is inside it; so does anything on a locked track (`pinned`) or
    /// locked itself.
    private func carriedAlong(after end: Int, except pinned: Set<UUID>) -> Set<UUID> {
        var found: Set<UUID> = []
        func walk(_ list: [Layer]) {
            for layer in list {
                guard let time = layer.time else {
                    walk(layer.children)
                    continue
                }
                guard time.inMS >= end, !layer.isLocked, !pinned.contains(layer.id) else { continue }
                found.formUnion(layer.selfAndDescendants.filter { $0.time != nil }.map(\.id))
            }
        }
        walk(layers)
        return found
    }

    /// A layer as a refusal names it: a caption line by what it is, since
    /// its name is its words.
    private static func named(_ layer: Layer) -> String {
        layer.isCaption ? "A caption" : layer.name
    }

    // MARK: What is on a track

    /// One thing on a track, and the stretch it covers.
    private struct Occupant {
        let id: UUID
        let span: Range<Int>
    }

    /// The clips on a track and the clips whose own sound is drawn on it. On
    /// a Captions track, each caption line rather than the layer holding them.
    private func occupants(onTrack trackID: UUID, layout: TrackLayout) -> [Occupant] {
        let ids = (layout.clips[trackID] ?? []) + (layout.linked[trackID] ?? [])
        var found: [Occupant] = []
        for id in ids {
            guard let layer = layer(id: id) else { continue }
            if layer.isCaptionsLayer || (layer.time == nil && layer.selfAndDescendants.contains(where: \.isCaption)) {
                for line in layer.selfAndDescendants where line.isCaption {
                    if let time = line.time { found.append(Occupant(id: line.id, span: time.inMS..<time.outMS)) }
                }
            } else {
                found.append(Occupant(id: id, span: clipSpan(layer, movedTo: nil)))
            }
        }
        return found
    }

    /// What any of `moved` now covers the same time as, on the same track,
    /// that did not move: the first, top track first. Nil where nothing.
    private func landedOn(_ moved: Set<UUID>) -> UUID? {
        let layout = trackLayout()
        for track in layout.tracks {
            let here = occupants(onTrack: track.id, layout: layout)
            let still = here.filter { !moved.contains($0.id) }
            for mover in here where moved.contains(mover.id) {
                if let hit = still.first(where: { $0.span.overlaps(mover.span) }) { return hit.id }
            }
        }
        return nil
    }
}
