import Foundation

// ⌘ on an edge: Premiere's ripple trim, by hand.
//
// A plain drag on a clip's end edge trims that clip and nothing else, so
// pulling the end of a take in leaves a gap in front of the next one, and
// pulling it out runs it over the next one. In Premiere, holding ⌘ over an
// edit point with the Selection tool gives the Ripple Edit cursor, and the
// same drag then carries everything after the edit along with the edge: the
// gap never opens. Tightening a cut by eye is one gesture.
//
// It is the hand's version of Q and W (`RippleTrim.swift`), so it keeps their
// bargain, which is Premiere's with sync lock on: the time comes out of EVERY
// unlocked track, or goes into every one, so the music, the captions and the
// titles after the edit stay on the picture they were laid against.
//
// - **Shorter**: the stretch the clip gave up is extracted from every other
//   unlocked track (`MarkedStretch.swift`), exactly as Q or W at the new edge
//   would take it.
// - **Longer**: the time the clip gained is put into every other unlocked
//   track at the edit (`HoldPush.rippleTime`), as a hold that pushes
//   everything does: what starts after the edit starts later, and a sound or
//   a clip running across it waits there and carries on.
//
// The clip itself takes the same edit a plain drag of that edge makes, so the
// bar under the hand looks the same either way; only what is after it moves.
// The start edge of something simply placed in time (a title) has no frames
// behind it, so ⌘ there is not a ripple, and the clip's own pieces are what a
// ripple of the start trims.

extension ClipBarDrag {

    /// Whether ⌘ held as this was taken hold of makes it a ripple trim: an
    /// edge with frames behind it. A whole bar, a carried piece and a title's
    /// free start are not trims, so ⌘ keeps what it already means for them.
    public var ripples: Bool {
        switch grab {
        case .seam: return true
        case .clipStart: return !startIsFree
        case .body, .carry: return false
        }
    }
}

extension PhotonzDocument {

    /// Move a clip's edge by `delta` as a ripple trim: the clip trims as a
    /// plain drag of that edge would, and every other unlocked track loses or
    /// gains the same time at the edit, as one change. Markers and the In and
    /// the Out move with the picture they were dropped on. Refused, changing
    /// nothing, for a grab that is not an edge, a clip on a locked track, and
    /// an edge the clip's own pieces will not let go that far.
    @discardableResult
    public mutating func rippleTrimClipEdge(_ id: UUID, _ grab: ClipBarGrab, byMS delta: Int) -> Bool {
        guard delta != 0, let layer = layer(id: id), !layer.isLocked, let time = layer.time,
              let pieces = layer.clipPieces, !isClipOnLockedTrack(id) else { return false }
        // Where the edit is on the document's clock before anything moves, and
        // how much time the clip gains there (negative: gives up).
        let editMS: Int
        let gainedMS: Int
        switch grab {
        case .clipStart:
            guard !layer.startIsFree,
                  editClip(id, { pieces, _ in pieces.trimStart(ofPiece: 0, byMS: delta) }) else { return false }
            editMS = time.inMS
            gainedMS = -delta
        case .seam(let after):
            guard let range = pieces.rangeMS(ofPiece: after),
                  editClip(id, { pieces, _ in pieces.trimEnd(ofPiece: after, byMS: delta) }) else { return false }
            // Pulled in, the stretch given up ends at the old edge; pushed
            // out, the time goes in at it.
            editMS = time.inMS + range.end + min(0, delta)
            gainedMS = delta
        case .body, .carry:
            return false
        }
        if gainedMS < 0 {
            let stretch = editMS..<(editMS - gainedMS)
            extractStretch(fromMS: stretch.lowerBound, toMS: stretch.upperBound, exceptLayers: [id])
            let squeeze = { (at: Int) -> Int in
                at <= stretch.lowerBound ? at
                    : (at >= stretch.upperBound ? at - stretch.count : stretch.lowerBound)
            }
            moveMarkers(squeeze)
            markInMS = markInMS.map(squeeze)
            markOutMS = markOutMS.map(squeeze)
            if let markIn = markInMS, let markOut = markOutMS, markOut <= markIn { clearMarkInOut() }
        } else {
            rippleTime(atMS: editMS, byMS: gainedMS, exceptLayer: id, sparingLocked: true)
            let push = { (at: Int) -> Int in at >= editMS ? at + gainedMS : at }
            moveMarkers(push)
            markInMS = markInMS.map(push)
            markOutMS = markOutMS.map(push)
        }
        refreshDuration()
        return true
    }
}
