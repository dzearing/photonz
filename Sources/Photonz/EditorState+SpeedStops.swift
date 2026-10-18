import Foundation
import PhotonzCore

/// Which stop of which piece of which clip is picked.
struct PickedSpeedStop: Hashable {
    let layerID: UUID
    let piece: Int
    let stop: Int
}

// Speed stops on the piece in hand (`SpeedStops.swift`,
// `docs/design/mocks/pages/video-speed.html`).
//
// The verbs, Add Speed Stop, Delete Speed Stop and Reset Ramp, are rows of
// the clip's Speed submenu, on its right click and in the menu bar's Clip
// menu, because speed already lives there. The panel's Time section shows the
// picked stop: which of how many, its speed, and how the piece gets between
// stops. No key: the mock prints A, which is Premiere's Track Select Forward
// and already that here (UX-PATTERNS §7).
extension EditorState {

    /// The stops on the piece in hand, nil where it plays at one speed.
    var speedRampInHand: SpeedRamp? { clipPieceInHandPiece?.speedRamp }

    /// The stop the panel is talking about: the one picked on this piece,
    /// else the one nearest the playhead, which is the one just added after
    /// Add Speed Stop and the one a person scrubbing onto a stop means.
    var speedStopInHand: Int? {
        guard let ramp = speedRampInHand, let id = clipInHandID, let index = clipPieceInHand,
              let pieces = clipInHandPieces, let time = document?.layer(id: id)?.time else { return nil }
        if let picked = pickedSpeedStop, picked.layerID == id, picked.piece == index,
           ramp.stops.indices.contains(picked.stop) { return picked.stop }
        let here = documentTimeMS - time.inMS
        func distance(_ stop: Int) -> Int { abs((pieces.timelineMS(ofStop: stop, inPiece: index) ?? 0) - here) }
        return ramp.stops.indices.min { distance($0) < distance($1) }
    }

    // MARK: Add Speed Stop

    /// Whether a stop can go on this clip where the playhead is.
    func canAddSpeedStop(_ id: UUID) -> Bool {
        guard Experiments.shared.cutRecordingEnabled, documentHasTime, !isClipLocked(id),
              var trial = document, trial.layer(id: id)?.hasMediaBehindIt == true else { return false }
        return trial.addSpeedStop(id, atMS: documentTimeMS) != nil
    }

    var canAddSpeedStopInHand: Bool { clipInHandID.map(canAddSpeedStop) ?? false }

    /// Put a stop on the frame under the playhead and pick it.
    func addSpeedStop(_ id: UUID) {
        endTrimBeforeCutting()
        guard canAddSpeedStop(id) else { return }
        pauseDocument()
        switchToEditForAnEdit()
        let at = documentTimeMS
        var added: (piece: Int, stop: Int)?
        perform { added = $0.addSpeedStop(id, atMS: at) }
        guard let added else { return }
        selectClipPiece(layerID: id, index: added.piece)
        pickedSpeedStop = PickedSpeedStop(layerID: id, piece: added.piece, stop: added.stop)
        documentTimeMS = min(documentTimeMS, lastDocumentTimeMS)
        documentMomentChanged()
    }

    func addSpeedStopInHand() {
        if let id = clipInHandID { addSpeedStop(id) }
    }

    // MARK: Delete Speed Stop, Reset Ramp

    var canDeleteSpeedStopInHand: Bool {
        guard let id = clipInHandID, !isClipLocked(id) else { return false }
        return speedStopInHand != nil
    }

    func deleteSpeedStopInHand() {
        endTrimBeforeCutting()
        guard canDeleteSpeedStopInHand, let id = clipInHandID, let index = clipPieceInHand,
              let stop = speedStopInHand else { return }
        pauseDocument()
        perform { $0.deleteSpeedStop(id, ofPiece: index, stop: stop) }
        pickedSpeedStop = nil
        settleAfterRetime(id, piece: index)
    }

    var canResetRampInHand: Bool {
        guard let id = clipInHandID, !isClipLocked(id) else { return false }
        return speedRampInHand != nil
    }

    /// Every stop off: the piece plays at one speed again.
    func resetRampInHand() {
        endTrimBeforeCutting()
        guard canResetRampInHand, let id = clipInHandID, let index = clipPieceInHand else { return }
        pauseDocument()
        perform { $0.resetRamp(id, ofPiece: index) }
        pickedSpeedStop = nil
        settleAfterRetime(id, piece: index)
    }

    // MARK: The picked stop, in the panel

    /// Pick another stop, and put the playhead on its frame so the picture
    /// shows what the stop is on.
    func pickSpeedStop(_ stop: Int) {
        guard let id = clipInHandID, let index = clipPieceInHand,
              speedRampInHand?.stops.indices.contains(stop) == true else { return }
        pickedSpeedStop = PickedSpeedStop(layerID: id, piece: index, stop: stop)
        landOnPickedStop(id, piece: index, stop: stop)
    }

    func canSetSpeedStopInHand(_ percent: Int) -> Bool {
        guard let id = clipInHandID, !isClipLocked(id), let ramp = speedRampInHand,
              let stop = speedStopInHand else { return false }
        return ramp.stops[stop].speedPercent != percent
    }

    /// The picked stop at another speed. The clip's length follows, and the
    /// playhead stays on the stop's frame, which has moved with it.
    func setSpeedStopInHand(_ percent: Int) {
        endTrimBeforeCutting()
        guard canSetSpeedStopInHand(percent), let id = clipInHandID, let index = clipPieceInHand,
              let stop = speedStopInHand else { return }
        pauseDocument()
        perform { $0.setSpeedStop(id, ofPiece: index, stop: stop, percent: percent) }
        pickedSpeedStop = PickedSpeedStop(layerID: id, piece: index, stop: stop)
        selectClipPiece(layerID: id, index: index)
        landOnPickedStop(id, piece: index, stop: stop)
    }

    /// Ease between the stops, or keep each stretch flat.
    func setRampBlendInHand(_ blend: SpeedRampBlend) {
        endTrimBeforeCutting()
        guard let id = clipInHandID, !isClipLocked(id), let index = clipPieceInHand,
              let ramp = speedRampInHand, ramp.blend != blend else { return }
        pauseDocument()
        let stop = speedStopInHand
        perform { $0.setRampBlend(id, ofPiece: index, blend) }
        if let stop {
            pickedSpeedStop = PickedSpeedStop(layerID: id, piece: index, stop: stop)
            landOnPickedStop(id, piece: index, stop: stop)
        } else {
            settleAfterRetime(id, piece: index)
        }
    }

    private func landOnPickedStop(_ id: UUID, piece index: Int, stop: Int) {
        guard let layer = document?.layer(id: id), let time = layer.time,
              let at = layer.clipPieces?.timelineMS(ofStop: stop, inPiece: index) else { return }
        documentTimeMS = min(max(time.inMS + at, time.inMS), max(time.inMS, time.outMS - 1))
        documentMomentChanged()
    }

    private func settleAfterRetime(_ id: UUID, piece index: Int) {
        selectClipPiece(layerID: id, index: index)
        documentTimeMS = min(documentTimeMS, lastDocumentTimeMS)
        documentMomentChanged()
    }
}
