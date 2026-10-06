import Foundation

// Several picked clips carried up or down the timeline together, the way a
// multi-selection moves in Premiere and Final Cut: the clip in the hand says
// where it is going, and every other picked clip goes the same number of
// tracks the same way and the same time, as one edit.
//
// Tracks are counted in the timeline's own list, top to bottom, so a clip of
// sound carried up with picture lands on whatever is above it. When that is
// the wrong kind of track, or a locked one, or one with something already
// there, nothing changes track at all: the clips only slide in time.

extension PhotonzDocument {

    /// Whether the picked clips `ids` may be carried together with `hand` in
    /// the hand aimed at `drop`, and slid `byMS` in time.
    public func canMoveClips(_ ids: [UUID], carrying hand: UUID, to drop: TrackDrop,
                             byMS delta: Int = 0) -> Bool {
        carryingClips(ids, hand: hand, to: drop, byMS: delta) != nil
    }

    /// Carry the picked clips `ids` with `hand` in the hand onto `drop`, and
    /// slide them all `byMS`, as one edit. A move left stops when the earliest
    /// of them reaches nought, as `moveClips(_:byMS:)` does. False, and nothing
    /// changed, when any of them cannot land on its track.
    @discardableResult
    public mutating func moveClips(_ ids: [UUID], carrying hand: UUID, to drop: TrackDrop,
                                   byMS delta: Int = 0) -> Bool {
        guard let carried = carryingClips(ids, hand: hand, to: drop, byMS: delta) else { return false }
        self = carried
        return true
    }

    /// The document with the clips carried, or nil where the move is refused.
    private func carryingClips(_ ids: [UUID], hand: UUID, to drop: TrackDrop,
                               byMS delta: Int) -> PhotonzDocument? {
        let picked = Array(Set(ids + [hand]))
        let layout = trackLayout()
        var trackOf: [UUID: UUID] = [:]
        for (track, clips) in layout.clips { for clip in clips { trackOf[clip] = track } }
        let locked = Set(layout.tracks.filter(\.isLocked).map(\.id))
        guard let handTrack = trackOf[hand],
              picked.allSatisfy({ trackOf[$0].map { !locked.contains($0) } ?? false }),
              let earliest = picked.compactMap({ layer(id: $0)?.time?.inMS }).min()
        else { return nil }
        let moved = max(delta, -earliest)

        var document = self
        document.materializeTracks()
        // Where the hand's track goes, as a row in the list, making the new
        // track a drop between two asks for.
        var order = document.tracks.map(\.id)
        let handRow: Int
        switch drop {
        case .onto(let target):
            guard target != handTrack, let row = order.firstIndex(of: target) else { return nil }
            handRow = row
        case .newTrack(let at):
            guard let kind = layer(id: hand)?.clipTrackKind else { return nil }
            let made = document.addTrack(kind, at: at)
            order = document.tracks.map(\.id)
            guard let row = order.firstIndex(of: made) else { return nil }
            handRow = row
        }
        guard let from = order.firstIndex(of: handTrack) else { return nil }
        let shift = handRow - from

        // Each track a picked clip is on, and the row it goes to. Rows over
        // the top or under the bottom get tracks of their own, made there.
        let sources = Set(picked.compactMap { trackOf[$0] })
        var rowOf: [UUID: Int] = [:]
        for source in sources {
            guard let row = order.firstIndex(of: source) else { return nil }
            rowOf[source] = row + shift
        }
        var targetOf: [UUID: UUID] = [:]
        for (source, row) in rowOf where order.indices.contains(row) { targetOf[source] = order[row] }
        let kindOf = { (source: UUID) -> DocumentTrack.Kind? in
            picked.first { trackOf[$0] == source }.flatMap { self.layer(id: $0)?.clipTrackKind }
        }
        // Over the top: the row furthest up ends up topmost.
        for (source, _) in rowOf.filter({ $0.value < 0 }).sorted(by: { $0.value > $1.value }) {
            guard let kind = kindOf(source) else { return nil }
            targetOf[source] = document.addTrack(kind, at: 0)
        }
        for (source, _) in rowOf.filter({ $0.value >= order.count }).sorted(by: { $0.value < $1.value }) {
            guard let kind = kindOf(source) else { return nil }
            targetOf[source] = document.addTrack(kind, at: document.tracks.count)
        }

        // Every clip has to fit where it lands: the right kind of track,
        // unlocked, and clear of everything there that is not moving too.
        let moving = Set(picked)
        let landedLayout = document.trackLayout()
        for id in picked {
            guard let clip = layer(id: id), let source = trackOf[id], let target = targetOf[source],
                  let track = document.tracks.first(where: { $0.id == target }),
                  !track.isLocked, track.kind.accepts(clip.clipTrackKind) else { return nil }
            let span = clipSpan(clip, movedTo: clip.time.map { $0.inMS + moved })
            let blocked = (landedLayout.clips[target] ?? []).contains { other in
                guard !moving.contains(other), let layer = layer(id: other) else { return false }
                let theirs = clipSpan(layer, movedTo: nil)
                return span.lowerBound < theirs.upperBound && theirs.lowerBound < span.upperBound
            }
            guard !blocked else { return nil }
        }

        if moved != 0 { document.moveClips(picked, byMS: moved) }
        for id in picked {
            guard let source = trackOf[id], let target = targetOf[source] else { continue }
            document.updateLayer(id: id) { $0.trackID = target }
        }
        document.restackByTracks()
        return document
    }
}
