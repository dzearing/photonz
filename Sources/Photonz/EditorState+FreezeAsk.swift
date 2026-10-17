import Foundation
import PhotonzCore

/// **Freeze Frame…**: a small popover hanging from the clip at the playhead
/// that asks how long, with a length you type (any length: 10 s, 1:30, 48f)
/// and a Freeze every track box that is off, so a freeze holds the clip's own
/// track and the rest of the timeline keeps playing (the user, 2026-10-17).
///
/// The same popover opened on a freeze that is already there changes THAT
/// freeze: its length and whether every track waits for it.
struct FreezeAsk: Equatable {
    /// The clip the popover hangs from.
    let layerID: UUID
    /// Where on the document's clock it hangs.
    let atMS: Int
    /// The freeze being changed, or nil for a new one at the playhead.
    let heldPiece: Int?
    var text: String
    var everyTrack: Bool

    /// The length typed, or nil while it is not one.
    var lengthMS: Int? { FreezeLength.parse(text) }
}

extension EditorState {

    /// Open the popover for a new freeze at the playhead, on the clip in hand.
    func openFreezeFrame() {
        endTrimBeforeCutting()
        // On a freeze in hand, it changes that freeze rather than freezing
        // a frame of a frame.
        if let id = clipInHandID, let index = clipPieceInHand, clipPieceInHandPiece?.isHeld == true {
            openFreezeFrame(layerID: id, heldPiece: index)
            return
        }
        guard canHoldFrameAtPlayhead, let id = clipInHandID else { return }
        pauseDocument()
        closeTransitionPicker()
        showFreezeAsk(FreezeAsk(layerID: id, atMS: documentTimeMS, heldPiece: nil,
                                text: FreezeLength.text(FreezeLength.defaultMS),
                                everyTrack: holdPushChoice == .everything))
    }

    /// Open the popover on a freeze that is already there, to change it.
    func openFreezeFrame(layerID: UUID, heldPiece index: Int) {
        endTrimBeforeCutting()
        guard let layer = document?.layer(id: layerID), let time = layer.time,
              let pieces = layer.clipPieces, let piece = pieces.piece(at: index), piece.isHeld,
              let range = pieces.rangeMS(ofPiece: index) else { return }
        pauseDocument()
        closeTransitionPicker()
        selectClipPiece(layerID: layerID, index: index)
        showFreezeAsk(FreezeAsk(layerID: layerID, atMS: time.inMS + (range.start + range.end) / 2,
                                heldPiece: index, text: FreezeLength.text(piece.lengthMS),
                                everyTrack: piece.holdPush == .everything))
    }

    /// Put the popover up. It hangs from the clip's bar, so the tracks have
    /// to be up; when they were not (View mode, or put away), they come up
    /// first and the popover follows once the bar is on screen, since a
    /// popover asked of a bar laid out in the same pass does not open.
    private func showFreezeAsk(_ ask: FreezeAsk) {
        guard !isMotionStripOpen else {
            freezeAsk = ask
            return
        }
        isMotionStripOpen = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.freezeAsk = ask
        }
    }

    func closeFreezeFrame() {
        if freezeAsk != nil { freezeAsk = nil }
    }

    /// Insert (or change) the freeze the popover says, as one undo step, and
    /// put the popover away. Nothing happens while the length is not a length.
    func commitFreezeFrame() {
        guard let ask = freezeAsk, let length = ask.lengthMS else { return }
        let push: HoldPush = ask.everyTrack ? .everything : .thisTrack
        freezeAsk = nil
        holdPushChoice = push
        guard let index = ask.heldPiece else {
            selectLayer(ask.layerID)
            holdFrameAtPlayhead(forMS: length)
            return
        }
        guard document?.layer(id: ask.layerID)?.clipPieces?.piece(at: index)?.isHeld == true else { return }
        pauseDocument()
        perform { doc in
            _ = doc.setHoldPush(ask.layerID, ofPiece: index, to: push)
            _ = doc.setHoldLength(ask.layerID, ofPiece: index, toMS: length)
        }
        selectClipPiece(layerID: ask.layerID, index: index)
        documentTimeMS = min(documentTimeMS, lastDocumentTimeMS)
        documentMomentChanged()
    }
}
