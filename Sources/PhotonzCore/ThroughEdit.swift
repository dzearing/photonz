import CoreGraphics
import Foundation

// Join Through Edit: a cut with nothing removed, put back into one piece.
//
// B cuts a clip in two and nothing is lost: both halves read the same
// recording, straight on across the cut, at the same speed. Premiere calls such
// a cut a through edit and joins it from its right-click. Without this, the
// only way back to one piece was Undo, which also threw away everything done
// since.
//
// **What counts** is exactly `ClipCut.isContinuous`: one recording, nothing
// held either side, one speed, and the second side starting on the very frame
// the first one stopped on. A transition on the cut does not stop it: it is
// taken off with the join, since it was blending a picture with itself.
//
// **The earlier side wins.** Inside one clip that is its piece's marks (a
// hidden picture, a cleaned sound); between two clips it is the whole earlier
// clip, its name, effects and keys, with the later clip's zooms and clicks
// carried over because they are on the recording's own clock. Nothing on any
// other layer moves.

extension PhotonzDocument {

    /// Whether the cut at `place` is a through edit that can be joined.
    public func canJoinThroughEdit(at place: TimelineCutPlace) -> Bool {
        guard let found = documentCut(at: place), found.cut.isContinuous else { return false }
        switch place {
        case let .join(clip, _):
            return !isClipOnLockedTrack(clip)
        case let .edit(outgoing, incoming):
            guard !isClipOnLockedTrack(outgoing), !isClipOnLockedTrack(incoming),
                  let out = layer(id: outgoing), let into = layer(id: incoming) else { return false }
            return out.merged == nil && into.merged == nil
                && out.trackID == into.trackID
                && out.sound == into.sound
                && (out.soundDetached ?? false) == (into.soundDetached ?? false)
        }
    }

    /// Join the through edit at `place` back into one piece. Refused, with
    /// nothing changed, on any cut that is not one.
    @discardableResult
    public mutating func joinThroughEdit(at place: TimelineCutPlace) -> Bool {
        guard canJoinThroughEdit(at: place) else { return false }
        switch place {
        case let .join(clip, index):
            return editClip(clip) { pieces, _ in pieces.joinThroughEdit(atCut: index) }
        case let .edit(outgoing, incoming):
            return joinClips(outgoing, incoming, at: place)
        }
    }

    /// Two clips that read one recording straight on, as the earlier one.
    private mutating func joinClips(_ outgoing: UUID, _ incoming: UUID, at place: TimelineCutPlace) -> Bool {
        // A dip that held on black put real time between the two; taking it
        // off first gives that time back and butts them, everywhere.
        if documentCut(at: place)?.cut.transition != nil {
            guard setTransition(nil, at: place) else { return false }
        }
        guard let out = layer(id: outgoing), let into = layer(id: incoming),
              let outPieces = out.clipPieces, let inPieces = into.clipPieces,
              out.time?.outMS == into.time?.inMS else { return false }
        var pieces = ClipPieces(pieces: outPieces.pieces + inPieces.pieces,
                                sourceLengthMS: outPieces.sourceLengthMS)
        guard pieces.joinThroughEdit(atCut: outPieces.count) else { return false }
        updateLayer(id: outgoing) { layer in
            layer.setClipPieces(pieces)
            // On the recording's clock, so they stay where they were.
            let zooms = (layer.zooms ?? []) + (into.zooms ?? []).filter { zoom in
                !(layer.zooms ?? []).contains { $0.id == zoom.id }
            }
            layer.zooms = zooms.isEmpty ? nil : zooms
            let clicks = (layer.addedClicks ?? []) + (into.addedClicks ?? []).filter { click in
                !(layer.addedClicks ?? []).contains(click)
            }
            layer.addedClicks = clicks.isEmpty ? nil : clicks
            // The fade out was at the end of the later clip, which is the end
            // of this one now; the fade in stays where it was.
            if layer.pictureFade != nil || into.pictureFade != nil {
                var fade = PictureFade(inMS: layer.pictureFade?.inMS ?? 0,
                                       outMS: into.pictureFade?.outMS ?? 0)
                fade.curve = layer.pictureFade?.curve ?? into.pictureFade?.curve
                layer.pictureFade = fade.isNone ? nil : fade
            }
        }
        removeLayer(id: incoming)
        refreshDuration()
        return true
    }
}
