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
        if case .carried = carryingClips(ids, hand: hand, to: drop, byMS: delta) { return true }
        return false
    }

    /// Why the picked clips may not be carried to `drop`: the first of them,
    /// the hand's own first, that a track turns away, and that track. Nil
    /// where the move is allowed, or refused for no reason a track gives (aimed
    /// at its own track, say).
    public func clipsMoveRefusal(_ ids: [UUID], carrying hand: UUID, to drop: TrackDrop,
                                 byMS delta: Int = 0) -> ClipPlacementRefusal? {
        if case .refused(let refusal) = carryingClips(ids, hand: hand, to: drop, byMS: delta) { return refusal }
        return nil
    }

    /// Carry the picked clips `ids` with `hand` in the hand onto `drop`, and
    /// slide them all `byMS`, as one edit. A move left stops when the earliest
    /// of them reaches nought, as `moveClips(_:byMS:)` does. False, and nothing
    /// changed, when any of them cannot land on its track.
    @discardableResult
    public mutating func moveClips(_ ids: [UUID], carrying hand: UUID, to drop: TrackDrop,
                                   byMS delta: Int = 0) -> Bool {
        guard case .carried(let carried) = carryingClips(ids, hand: hand, to: drop, byMS: delta)
        else { return false }
        self = carried
        return true
    }

    /// Where each of the picked clips `ids` would land, `hand` first, carried
    /// with `hand` in the hand aimed at `drop` and slid `byMS`, each with the
    /// refusal of the track it would land on where that track turns it away.
    /// The timeline lights every one of those lanes while the clips are in
    /// the hand. Empty where the move goes nowhere at all (aimed at the hand's
    /// own track, say) or is stopped before any clip reaches a lane.
    public func clipsCarryLandings(_ ids: [UUID], carrying hand: UUID, to drop: TrackDrop,
                                   byMS delta: Int = 0) -> [ClipCarryLanding] {
        guard case .planned(let plan) = carryPlan(ids, hand: hand, to: drop, byMS: delta) else { return [] }
        return plan.landings
    }

    /// The clips carried, or refused, with the track that said no where one did.
    private enum Carrying {
        case carried(PhotonzDocument)
        case refused(ClipPlacementRefusal?)
    }

    /// The document with the clips carried, or why the move is refused.
    private func carryingClips(_ ids: [UUID], hand: UUID, to drop: TrackDrop,
                               byMS delta: Int) -> Carrying {
        let plan: CarryPlan
        switch carryPlan(ids, hand: hand, to: drop, byMS: delta) {
        case .planned(let planned): plan = planned
        case .stopped(let refusal): return .refused(refusal)
        }
        // The hand's own refusal first, since it is listed first.
        if let refused = plan.landings.first(where: { !$0.fits }) { return .refused(refused.refusal) }
        var document = plan.document
        if plan.movedMS != 0 { document.moveClips(plan.picked, byMS: plan.movedMS) }
        for (id, target) in plan.targets { document.updateLayer(id: id) { $0.trackID = target } }
        document.restackByTracks()
        return .carried(document)
    }

    /// Every picked clip's landing worked out, with the tracks it needs made.
    private struct CarryPlan {
        /// The document with the tracks written down and any new ones made,
        /// nothing moved yet.
        var document: PhotonzDocument
        var picked: [UUID]
        var movedMS: Int
        /// Each picked clip and the track it lands on in `document`.
        var targets: [(UUID, UUID)]
        var landings: [ClipCarryLanding]
    }

    private enum Planning {
        case planned(CarryPlan)
        /// Stopped before any clip reaches a lane: a locked track under one
        /// of them, or nowhere to go.
        case stopped(ClipPlacementRefusal?)
    }

    private func carryPlan(_ ids: [UUID], hand: UUID, to drop: TrackDrop, byMS delta: Int) -> Planning {
        // The hand first, so where it is the one turned away, its track is
        // the one named.
        var seen = Set<UUID>()
        let picked = ([hand] + ids).filter { seen.insert($0).inserted }
        let layout = trackLayout()
        var trackOf: [UUID: UUID] = [:]
        for (track, clips) in layout.clips { for clip in clips { trackOf[clip] = track } }
        guard let handTrack = trackOf[hand], picked.allSatisfy({ trackOf[$0] != nil })
        else { return .stopped(nil) }
        for id in picked {
            if let locked = layout.tracks.first(where: { $0.id == trackOf[id] && $0.isLocked }) {
                return .stopped(ClipPlacementRefusal(reason: .locked, track: locked))
            }
        }
        guard let earliest = picked.compactMap({ layer(id: $0)?.time?.inMS }).min()
        else { return .stopped(nil) }
        let moved = max(delta, -earliest)
        let trackCount = layout.tracks.count

        var document = self
        document.materializeTracks()
        // Each track made, and where it goes in the list as it is now, which
        // is what the timeline draws a new track's line at.
        var madeAt: [UUID: Int] = [:]
        // Where the hand's track goes, as a row in the list, making the new
        // track a drop between two asks for.
        var order = document.tracks.map(\.id)
        let handRow: Int
        switch drop {
        case .onto(let target):
            guard target != handTrack, let row = order.firstIndex(of: target) else { return .stopped(nil) }
            handRow = row
        case .newTrack(let at):
            guard let kind = layer(id: hand)?.clipTrackKind else { return .stopped(nil) }
            let made = document.addTrack(kind, at: at)
            madeAt[made] = min(max(0, at), trackCount)
            order = document.tracks.map(\.id)
            guard let row = order.firstIndex(of: made) else { return .stopped(nil) }
            handRow = row
        }
        guard let from = order.firstIndex(of: handTrack) else { return .stopped(nil) }
        let shift = handRow - from

        // Each track a picked clip is on, and the row it goes to. Rows over
        // the top or under the bottom get tracks of their own, made there.
        let sources = Set(picked.compactMap { trackOf[$0] })
        var rowOf: [UUID: Int] = [:]
        for source in sources {
            guard let row = order.firstIndex(of: source) else { return .stopped(nil) }
            rowOf[source] = row + shift
        }
        var targetOf: [UUID: UUID] = [:]
        for (source, row) in rowOf where order.indices.contains(row) { targetOf[source] = order[row] }
        let kindOf = { (source: UUID) -> DocumentTrack.Kind? in
            picked.first { trackOf[$0] == source }.flatMap { self.layer(id: $0)?.clipTrackKind }
        }
        // Over the top: the row furthest up ends up topmost.
        for (source, _) in rowOf.filter({ $0.value < 0 }).sorted(by: { $0.value > $1.value }) {
            guard let kind = kindOf(source) else { return .stopped(nil) }
            let made = document.addTrack(kind, at: 0)
            targetOf[source] = made
            madeAt[made] = 0
        }
        for (source, _) in rowOf.filter({ $0.value >= order.count }).sorted(by: { $0.value < $1.value }) {
            guard let kind = kindOf(source) else { return .stopped(nil) }
            let made = document.addTrack(kind, at: document.tracks.count)
            targetOf[source] = made
            madeAt[made] = trackCount
        }

        // Every clip has to fit where it lands: the right kind of track,
        // unlocked, and clear of everything there that is not moving too.
        let moving = Set(picked)
        let landedLayout = document.trackLayout()
        var targets: [(UUID, UUID)] = []
        var landings: [ClipCarryLanding] = []
        for id in picked {
            guard let clip = layer(id: id), let source = trackOf[id], let target = targetOf[source],
                  let track = document.tracks.first(where: { $0.id == target }) else { return .stopped(nil) }
            targets.append((id, target))
            let place: ClipCarryLanding.Place = madeAt[target].map { .newTrack(at: $0) } ?? .track(target)
            let refusal: ClipPlacementRefusal?
            if !track.kind.accepts(clip.clipTrackKind) {
                refusal = ClipPlacementRefusal(reason: .wrongKind, track: track)
            } else if track.isLocked {
                refusal = ClipPlacementRefusal(reason: .locked, track: track)
            } else {
                let span = clipSpan(clip, movedTo: clip.time.map { $0.inMS + moved })
                let blocked = (landedLayout.clips[target] ?? []).contains { other in
                    guard !moving.contains(other), let layer = layer(id: other) else { return false }
                    let theirs = clipSpan(layer, movedTo: nil)
                    return span.lowerBound < theirs.upperBound && theirs.lowerBound < span.upperBound
                }
                refusal = blocked ? ClipPlacementRefusal(reason: .noRoom, track: track) : nil
            }
            landings.append(ClipCarryLanding(clip: id, place: place, refusal: refusal))
        }
        return .planned(CarryPlan(document: document, picked: picked, movedMS: moved,
                                  targets: targets, landings: landings))
    }
}

/// Where one of several clips carried together would land, and the refusal
/// of the track it would land on where that track turns it away
/// (`PhotonzDocument.clipsCarryLandings`).
public struct ClipCarryLanding: Hashable, Sendable {
    public enum Place: Hashable, Sendable {
        /// A track the timeline already has.
        case track(UUID)
        /// A new track, made at this place in the timeline's list of tracks as
        /// it is now: 0 over the top one, the count under the bottom one.
        case newTrack(at: Int)
    }

    public let clip: UUID
    public let place: Place
    public let refusal: ClipPlacementRefusal?

    public var fits: Bool { refusal == nil }

    public init(clip: UUID, place: Place, refusal: ClipPlacementRefusal?) {
        self.clip = clip
        self.place = place
        self.refusal = refusal
    }
}
