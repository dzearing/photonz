import Foundation

// The edits a timeline's right-click menus reach that no key or gesture did
// before: Ripple Delete, Split Everything Here and Roll Edit to Playhead.
//
// Each one is a Premiere command under Premiere's own name, so an editor who
// knows that tool finds it where they look. The arithmetic of a single clip is
// `ClipPieces`; what is here is the part that has to see the whole document.

extension PhotonzDocument {

    // MARK: Ripple delete

    /// Throw a piece of a clip away and take the same stretch out of the rest
    /// of the document (`StretchRemoval.swift`), so everything stays in step
    /// with the picture: a title over the fifth second of a take is still over
    /// the same frame once a stretch before it has gone, and the captions for
    /// the words that went go with them.
    ///
    /// `removeClipPiece` on its own closes the join inside the clip and moves
    /// nothing else; nothing a person presses reaches it any more, because a
    /// talking recording cut that way leaves every caption after the cut over
    /// the wrong words.
    @discardableResult
    public mutating func rippleDeleteClipPiece(_ id: UUID, at index: Int) -> Bool {
        guard let time = layer(id: id)?.time,
              let range = layer(id: id)?.clipPieces?.rangeMS(ofPiece: index) else { return false }
        guard removeClipPiece(id, at: index) else { return false }
        removeTime(fromMS: time.inMS + range.start, toMS: time.inMS + range.end, exceptLayer: id)
        return true
    }

    /// Take a whole layer away and close the gap it leaves.
    @discardableResult
    public mutating func rippleDeleteLayer(_ id: UUID) -> Bool {
        guard let time = layer(id: id)?.time, removeLayer(id: id) != nil else { return false }
        closeGap(endingAtMS: time.outMS, lengthMS: time.lengthMS, except: id)
        refreshDuration()
        return true
    }

    /// Everything that starts at or after the end of a stretch that has gone
    /// moves back by the stretch's length.
    ///
    /// Only what starts after it. A layer running across the stretch (music
    /// under the whole take) is left exactly as it was: shortening it would be
    /// cutting something nobody pointed at. A clip on a locked track stays put,
    /// because locking a track is saying exactly that.
    private mutating func closeGap(endingAtMS end: Int, lengthMS: Int, except: UUID) {
        guard lengthMS > 0 else { return }
        for layer in allLayers {
            guard layer.id != except, let time = layer.time, time.inMS >= end,
                  !isClipOnLockedTrack(layer.id) else { continue }
            updateLayer(id: layer.id) { $0.time = time.moved(toInMS: max(0, time.inMS - lengthMS)) }
        }
        refreshDuration()
    }

    // MARK: Split everything here

    /// Cut every clip the moment runs through, on every track that is not
    /// locked: Premiere's Add Edit to All Tracks. Answers how many were cut.
    ///
    /// Only clips, meaning layers that play a recording or a sound. A title
    /// has no frames to cut between, and a piece of one would mean nothing.
    @discardableResult
    public mutating func splitEveryClip(atMS ms: Int) -> Int {
        var cut = 0
        for layer in allLayers where layer.holdsMedia {
            guard let time = layer.time, ms > time.inMS, ms < time.outMS,
                  !isClipOnLockedTrack(layer.id) else { continue }
            if splitClip(layer.id, atMS: ms) { cut += 1 }
        }
        return cut
    }

    // MARK: Roll edit

    /// Move a join to a moment of the document, keeping the clip exactly as
    /// long as it was: the piece before the join gets longer by what the piece
    /// after it loses, or the other way round. Premiere's roll edit, and its
    /// Extend Edit to Playhead.
    ///
    /// Refused where either side has no recording left to give, where it
    /// would leave a piece too short to hold, and where a transition on the
    /// join could no longer be paid for.
    @discardableResult
    public mutating func rollClipCut(_ id: UUID, atCut index: Int, toMS ms: Int) -> Bool {
        guard let time = layer(id: id)?.time,
              var pieces = layer(id: id)?.clipPieces,
              let cut = pieces.cut(at: index) else { return false }
        let delta = ms - time.inMS - cut.atMS
        guard delta != 0, pieces.trimEnd(ofPiece: index - 1, byMS: delta),
              pieces.trimStart(ofPiece: index, byMS: delta) else { return false }
        if let transition = cut.transition,
           let rolled = pieces.cut(at: index),
           rolled.longestMS(of: transition.kind) < transition.lengthMS { return false }
        updateLayer(id: id) { $0.setClipPieces(pieces) }
        return true
    }
}
