import Foundation

// Q and W: Premiere's Ripple Trim Previous Edit to Playhead, and Next Edit.
//
// Tightening a talking recording in Premiere is parking the playhead where the
// good part starts and pressing Q, then where it ends and pressing W. The piece
// under the playhead loses everything from its own start up to the playhead
// (Q), or from the playhead to its own end (W), and the gap closes.
//
// The gap closes on EVERY unlocked track, exactly as Extract does
// (`MarkedStretch.swift`), which is Premiere's trim with sync lock on: a sound
// taken off the picture, the captions, the titles and the music all lose the
// same stretch, so nothing after the trim is left out of step with the picture.
// A locked track is left alone, and a clip on one is not trimmed at all.
//
// "The clip under the playhead" is the picked one where the playhead is on it,
// otherwise the topmost clip or sound under the playhead. A picked caption or
// title is not a clip to trim, so the recording under it is.

/// Which end of the piece under the playhead Q and W trim.
public enum RippleTrimEnd: Hashable, Sendable {
    /// Q: from the piece's start up to the playhead.
    case start
    /// W: from the playhead to the piece's end.
    case end
}

extension PhotonzDocument {

    /// The clip Q and W act on at a moment: the picked one if it has pieces
    /// and runs through the moment, else the topmost one that does. Nil where
    /// no clip or sound is under the playhead.
    public func rippleTrimClip(pickedLayerID: UUID?, atMS ms: Int) -> UUID? {
        func trimmable(_ layer: Layer) -> Bool {
            guard layer.holdsMedia, layer.clipPieces != nil, let time = layer.time else { return false }
            return time.inMS <= ms && ms < time.outMS
        }
        if let pickedLayerID, let picked = layer(id: pickedLayerID), trimmable(picked) {
            return pickedLayerID
        }
        return allLayers.last(where: trimmable)?.id
    }

    /// The stretch of the document a Q or a W at `ms` would take out of this
    /// clip, on the document's clock. Nil where there is nothing to take: the
    /// playhead is outside the clip or on the piece's edge, the clip is
    /// locked, or what would be left of the piece is a sliver too short to
    /// hold.
    public func rippleTrimStretch(clip id: UUID, atMS ms: Int, _ end: RippleTrimEnd) -> Range<Int>? {
        guard let layer = layer(id: id), layer.holdsMedia, !layer.isLocked, let time = layer.time,
              let pieces = layer.clipPieces, !layerIDsOnLockedTracks().contains(id),
              ms >= time.inMS, ms <= time.outMS else { return nil }
        let at = ms - time.inMS
        // On a cut the playhead belongs to the piece that starts there, so Q
        // has nothing before it in that piece; W trims the one it is in.
        guard let index = pieces.pieceIndex(atMS: at),
              let range = pieces.rangeMS(ofPiece: index) else { return nil }
        let kept = end == .start ? range.end - at : at - range.start
        let taken = end == .start ? at - range.start : range.end - at
        guard taken > 0, kept >= ClipPiece.shortestMS else { return nil }
        return end == .start ? (time.inMS + range.start)..<ms : ms..<(time.inMS + range.end)
    }

    /// Q or W: take the stretch out of every unlocked track and close the
    /// gap. Markers and the In and the Out move with the picture they were
    /// dropped on; one inside the stretch lands on the join. Answers whether
    /// anything changed.
    @discardableResult
    public mutating func rippleTrim(clip id: UUID, atMS ms: Int, _ end: RippleTrimEnd) -> Bool {
        guard let stretch = rippleTrimStretch(clip: id, atMS: ms, end),
              extractStretch(fromMS: stretch.lowerBound, toMS: stretch.upperBound) else { return false }
        let squeeze = { (at: Int) -> Int in
            at <= stretch.lowerBound ? at
                : (at >= stretch.upperBound ? at - stretch.count : stretch.lowerBound)
        }
        moveMarkers(squeeze)
        markInMS = markInMS.map(squeeze)
        markOutMS = markOutMS.map(squeeze)
        // An In and an Out that both sat inside the stretch named something
        // that is gone.
        if let markIn = markInMS, let markOut = markOutMS, markOut <= markIn { clearMarkInOut() }
        return true
    }
}
