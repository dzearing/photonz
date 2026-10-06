import Foundation

// Premiere's Nudge Clip Selection: ⌘← and ⌘→ move the picked clips a frame
// earlier or later, ⇧⌘ five. It is how a clip is lined up to a beat or a word,
// a job a drag at any zoom does worse than a key pressed three times.
//
// A nudge is a small exact move, so it never lands one clip on top of
// another: it stops at the clip next door on the same track, and at the start
// of the document. A clip on a locked track stays where it is, and the rest
// of what is picked still goes.

extension PhotonzDocument {

    /// Whether any of `ids` is a clip on the timeline a nudge could move.
    public func canNudgeClips(_ ids: [UUID]) -> Bool {
        !nudgeable(ids).isEmpty
    }

    /// Move the clips `ids` by `frames` frames, as far as they can go towards
    /// it, as one edit. False, and nothing changed, when none of them can move
    /// at all.
    @discardableResult
    public mutating func nudgeClips(_ ids: [UUID], byFrames frames: Int) -> Bool {
        let moving = nudgeable(ids)
        guard !moving.isEmpty else { return false }
        let reach = nudgeReach(moving, byMS: frames * MovieRef.frameStepMS)
        guard reach != 0 else { return false }
        return moveClips(moving, byMS: reach)
    }

    /// The clips in `ids` that are on the timeline, with times of their own,
    /// and not on a locked track. In the order asked, each once.
    private func nudgeable(_ ids: [UUID]) -> [UUID] {
        guard !ids.isEmpty else { return [] }
        let onTimeline = Set(timelineClipLayers.map(\.id))
        let locked = layerIDsOnLockedTracks()
        var seen = Set<UUID>()
        return ids.filter { id in
            onTimeline.contains(id) && !locked.contains(id) && layer(id: id)?.time != nil
                && seen.insert(id).inserted
        }
    }

    /// How much of `delta` the clips `moving` can travel together: stopped by
    /// the start of the document and by the nearest clip in the way on each of
    /// their tracks. Clips moving together never stop each other, and one that
    /// already overlaps a clip it shares a track with is not stopped by it.
    private func nudgeReach(_ moving: [UUID], byMS delta: Int) -> Int {
        let layout = trackLayout()
        var trackOf: [UUID: UUID] = [:]
        for (track, clips) in layout.clips { for clip in clips { trackOf[clip] = track } }
        let movingSet = Set(moving)
        var reach = delta
        for id in moving {
            guard let clip = layer(id: id) else { continue }
            let span = clipSpan(clip, movedTo: nil)
            if delta < 0 { reach = max(reach, -span.lowerBound) }
            guard let track = trackOf[id] else { continue }
            for other in layout.clips[track] ?? [] where !movingSet.contains(other) {
                guard let neighbour = layer(id: other) else { continue }
                let theirs = clipSpan(neighbour, movedTo: nil)
                if delta > 0, theirs.lowerBound >= span.upperBound {
                    reach = min(reach, theirs.lowerBound - span.upperBound)
                } else if delta < 0, theirs.upperBound <= span.lowerBound {
                    reach = max(reach, theirs.upperBound - span.lowerBound)
                }
            }
        }
        return reach
    }
}
