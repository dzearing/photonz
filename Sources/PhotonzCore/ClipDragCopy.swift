import Foundation

// ⌥-drag on a clip's bar leaves a copy behind (`ClipBarDrag.swift`), the way
// Premiere and Final Cut do it and the way ⌥-drag on the canvas already does:
// the copy goes where the hand lets go of it and the original never moves.
//
// The copy is made when the bar is grabbed, so it has one id for the whole
// drag: the timeline draws it as a bar of its own while the hand carries it,
// and the same layer is what lands when the hand lets go. Nothing here is
// written until then, which keeps the copy and its move one step to undo.
//
// **A piece of a cut clip copies as a clip of its own.** To an editor every
// stretch between two cuts is a clip, so ⌥-dragging the second half of a
// recording that was split with B brings out the second half, not the whole
// recording.

extension PhotonzDocument {

    /// A copy of clip `id`, or of its piece `piece` alone, as ⌥-drag would lift
    /// it: the same name, the same recording, the same track, starting at the
    /// moment the thing copied starts. Not in the document; `placeClipCopy`
    /// puts it there. Nil for a layer with no time, a piece that is not there,
    /// and a clip on a locked track, which nothing drags.
    public func clipDragCopy(of id: UUID, piece: Int? = nil) -> Layer? {
        guard let original = layer(id: id), let time = original.time,
              let pieces = original.clipPieces, !isClipOnLockedTrack(id) else { return nil }
        var copy = original.duplicated()
        // The timeline names a clip by what it plays, and a copy plays the
        // same thing, as a pasted clip keeps its name too (`ClipPaste.swift`).
        copy.name = original.name
        copy.trackID = trackID(ofClip: id)
        guard let piece else { return copy }
        guard let kept = pieces.piece(at: piece) else { return nil }
        // Laid where the piece itself sits, so the copy starts out exactly
        // over what it was lifted from and the drag moves it from there.
        copy.time = time.moved(toInMS: time.inMS + pieces.startMS(ofPiece: piece))
        copy.setClipPieces(ClipPieces(pieces: [kept], sourceLengthMS: pieces.sourceLengthMS))
        return copy
    }

    /// Put a copy made by `clipDragCopy` in the document directly over
    /// `original`, on its track, starting at `atInMS`. A copy already in is
    /// only moved, so a drag drawn twice over the same document still holds one
    /// copy. False where the original is not a clip at the top of the stack.
    @discardableResult
    public mutating func placeClipCopy(_ copy: Layer, over original: UUID, atInMS: Int) -> Bool {
        guard copy.time != nil else { return false }
        if layer(id: copy.id) == nil {
            guard let index = layers.firstIndex(where: { $0.id == original }) else { return false }
            // The original's track is written down first, so a recording on a
            // track the timeline only worked out has a real one for the copy
            // to share rather than each getting a track of its own.
            materializeTracks()
            var arriving = copy
            arriving.trackID = trackID(ofClip: original) ?? copy.trackID
            layers.insert(arriving, at: index + 1)
        }
        updateLayer(id: copy.id) { $0.time = $0.time?.moved(toInMS: max(0, atInMS)) }
        // A document that knows how long it is grows to hold the copy.
        if let written = durationMS {
            durationMS = max(written, allLayers.compactMap { $0.time?.outMS }.max() ?? written)
        }
        return true
    }

    /// Every one of `ids` that sits over something on its own track goes up
    /// onto a new track straight over that track, the way a pasted clip does
    /// (`ClipPaste.swift`), so a copy never covers what was already cut and two
    /// clips never share a moment of one track. Copies off the same track
    /// share the one new track wherever they fit on it side by side.
    ///
    /// The new track's id comes from the clip's, so a copy carried with ⌥ is
    /// shown on the same track for the whole of the drag and lands on it: the
    /// timeline's row for it is one row from the grab to the let go.
    public mutating func liftClipsOffOverlaps(_ ids: [UUID]) {
        var made: [UUID: UUID] = [:]
        for id in ids {
            guard let own = trackID(ofClip: id), !canPlace(id, onTrack: own) else { continue }
            if let lifted = made[own], canPlace(id, onTrack: lifted) {
                moveClip(id, toTrack: lifted)
                continue
            }
            guard let index = timelineTracks.firstIndex(where: { $0.id == own }),
                  let track = moveClipToNewTrack(id, at: index,
                                                 newTrackID: Self.liftedTrackID(for: id, avoiding: Set(timelineTracks.map(\.id))))
            else { continue }
            made[own] = track
        }
    }

    /// The id of the track a clip is lifted onto: the clip's own id with its
    /// LAST byte turned (a clip's own sound track turns its first), the same
    /// every time it is worked out.
    static func liftedTrackID(for id: UUID, avoiding used: Set<UUID>) -> UUID {
        var bytes = id.uuid
        let last = bytes.15
        for salt in UInt8(0x3C)...UInt8(0xFF) {
            bytes.15 = last ^ salt
            let candidate = UUID(uuid: bytes)
            if !used.contains(candidate) { return candidate }
        }
        return UUID()
    }
}
