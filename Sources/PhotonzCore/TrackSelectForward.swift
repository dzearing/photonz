import Foundation

// Premiere's Track Select Forward (A): a click on a clip picks it and every
// clip that starts at or after it, and the lot slides as one. It is how a gap
// is opened in the middle of an edit to make room for something, or closed
// after something came out, without touching anything before it.
//
// ⇧-click keeps the pick to the clicked clip's own track, as it does in
// Premiere. (Premiere's ⇧A is Track Select BACKWARD, which is not here yet.)

/// The tool in the timeline's hand. Select first, the way the bar draws them.
public enum TimelineTool: String, CaseIterable, Hashable, Sendable {
    /// The arrow: a press picks, a drag moves or trims.
    case select
    /// A: a press picks a clip and everything after it.
    case trackSelectForward
    /// B: a click cuts.
    case blade
}

extension PhotonzDocument {

    /// The clip at `id` and every clip on the timeline that starts at or after
    /// it, the clicked one first and the rest in the order they start.
    ///
    /// Nothing on a locked track, since nothing there can move. Empty when
    /// `id` is not a clip with times of its own on the timeline.
    public func clipsForward(from id: UUID, onItsTrackOnly: Bool) -> [UUID] {
        let clips = timelineClipLayers
        guard let clicked = clips.first(where: { $0.id == id }),
              let start = clicked.time?.inMS else { return [] }
        // One laying out of the tracks for the whole question, not one per
        // clip: a talk with 170 captions asks it of every one of them.
        let layout = trackLayout()
        let locked = Set(layout.tracks.filter(\.isLocked).map(\.id))
        var trackOf: [UUID: UUID] = [:]
        for (track, ids) in layout.clips { for clip in ids { trackOf[clip] = track } }
        let own = trackOf[id]
        let later = clips.compactMap { layer -> (id: UUID, inMS: Int)? in
            guard layer.id != id, let time = layer.time, time.inMS >= start,
                  let track = trackOf[layer.id], !locked.contains(track),
                  !onItsTrackOnly || track == own else { return nil }
            return (layer.id, time.inMS)
        }
        return [id] + later.sorted { $0.inMS < $1.inMS }.map(\.id)
    }

    /// Slide every clip in `ids` by the same amount, as one edit. A move left
    /// stops when the earliest of them reaches the start of the document, so
    /// the gaps between them never change.
    @discardableResult
    public mutating func moveClips(_ ids: [UUID], byMS delta: Int) -> Bool {
        let starts = ids.compactMap { layer(id: $0)?.time?.inMS }
        guard let earliest = starts.min() else { return false }
        let moved = max(delta, -earliest)
        guard moved != 0 else { return false }
        for id in ids {
            guard let time = layer(id: id)?.time else { continue }
            updateLayer(id: id) { $0.time = time.moved(toInMS: time.inMS + moved) }
        }
        refreshDuration()
        return true
    }
}
