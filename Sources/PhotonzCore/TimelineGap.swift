import Foundation

// A gap between two clips on a track, and closing it.
//
// A Lift (;), or a clip dragged away, leaves an empty stretch on its track.
// Premiere and Final Cut both let a person click that stretch and press Delete,
// or right-click it and choose Ripple Delete, and the clips after it on that
// track slide back to close it. Before this the only way here was a range drawn
// over the gap and Shift-Delete.
//
// What moves is what a person pointed at, and what has to stay in step with it:
//
// - **Every clip after the gap on its track**, each by the gap's length, with
//   everything inside it. A clip's own sound is the clip, so it goes along.
// - **The captions over those clips**, on whatever track they are on: they
//   are the words of the recording that moves, and a caption left behind
//   would be under the wrong picture.
//
// Nothing else moves. Music on another track, a title over the picture: the
// person pointed at one track, as they do in Premiere with sync lock off.
//
// It is refused, rather than half done, where something that has to move
// cannot: a clip or a caption on a locked track, a locked layer, or a moved
// clip, sound or caption landing on something already there on its own track.

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
        var trial = self
        return trial.closeGap(gap)
    }

    /// Ripple Delete on a gap: every clip after it on its track, and the
    /// captions over them, move earlier by its length. One edit; answers
    /// whether it was made, and changes nothing when it was not.
    @discardableResult
    public mutating func closeGap(_ gap: TimelineGap) -> Bool {
        guard gap.lengthMS > 0, self.gap(onTrack: gap.trackID, atMS: gap.range.lowerBound) == gap
        else { return false }
        let layout = trackLayout()
        let locked = layerIDsOnLockedTracks()
        let after = occupants(onTrack: gap.trackID, layout: layout).filter { $0.span.lowerBound >= gap.range.upperBound }
        guard !after.isEmpty else { return false }
        let clipIDs = Set(after.map(\.id))
        var moving: Set<UUID> = []
        for layer in layers where clipIDs.contains(layer.id) {
            moving.formUnion(layer.selfAndDescendants.filter { $0.time != nil }.map(\.id))
        }
        let spans = after.map(\.span)
        forEachLayer { layer in
            guard layer.isCaption, let time = layer.time,
                  spans.contains(where: { $0.contains(time.inMS) }) else { return }
            moving.insert(layer.id)
        }
        // Everything that moves has to be free to.
        guard !moving.contains(where: { locked.contains($0) || layer(id: $0)?.isLocked == true })
        else { return false }
        var moved = self
        for id in moving {
            moved.updateLayer(id: id) { layer in
                guard let time = layer.time else { return }
                layer.time = time.moved(toInMS: time.inMS - gap.lengthMS)
                layer.captionWords = layer.captionWords?.map { $0.shifted(byMS: -gap.lengthMS) }
            }
        }
        guard !moved.landsOnSomething(moving) else { return false }
        moved.refreshDuration()
        self = moved
        return true
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

    /// Whether any of `moved` now covers the same time as something that did
    /// not move, on the same track.
    private func landsOnSomething(_ moved: Set<UUID>) -> Bool {
        let layout = trackLayout()
        for track in layout.tracks {
            let here = occupants(onTrack: track.id, layout: layout)
            let still = here.filter { !moved.contains($0.id) }
            for mover in here where moved.contains(mover.id) {
                if still.contains(where: { $0.span.overlaps(mover.span) }) { return true }
            }
        }
        return false
    }
}
