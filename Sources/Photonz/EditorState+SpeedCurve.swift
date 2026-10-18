import Foundation
import PhotonzCore

/// A stop on the speed curve in the hand: which one, which handle of it, and
/// where the hand has it. Nothing is written until it is let go, so the whole
/// drag is one step to undo, and the picture and the curve read the document
/// as shown (`withDraggedSpeedStop`) so they follow the hand.
struct SpeedStopDragSession: Equatable {
    let layerID: UUID
    let piece: Int
    let stop: Int
    let kind: SpeedCurve.HandleKind
    /// Where along the clip the hand has a stop, nil for a drag straight up
    /// or down; how long the hold is, for the second zero of a freeze.
    var toClipMS: Int?
    var percent: Int
    /// The stop's speed when it was taken, which a hand back on its height
    /// returns to.
    let percentBefore: Int
    var holdMS: Int?
    /// The timeline's length when the drag began, held so the ruler does
    /// not rescale under the hand as the clip grows and shrinks.
    let heldCycleMS: Int
}

// The speed curve under a clip (`SpeedCurveLane`, `SpeedCurve.swift`,
// `docs/design/mocks/pages/video-speed.html`): picking a stop on it, dragging
// one, adding one with a Command-click, and the mock's Freeze.
extension EditorState {

    /// The curve of a clip as the timeline is drawing it: with a stop in the
    /// hand where there is one. Nil for a clip with no stops at all, which
    /// takes no room.
    func speedCurve(layerID: UUID) -> SpeedCurve? {
        guard documentHasTime,
              let pieces = (shownDocument(forClip: layerID) ?? document)?.layer(id: layerID)?.clipPieces,
              pieces.pieces.contains(where: { $0.speedRamp != nil }) else { return nil }
        return SpeedCurve(pieces)
    }

    /// Whether any clip on a track has speed stops: their curve opens under
    /// it with the track's arrow, like its key lanes.
    func trackHasSpeedCurves(_ layerIDs: [UUID]) -> Bool {
        guard documentHasTime, let document else { return false }
        return layerIDs.contains { document.layer(id: $0)?.clipPieces?.pieces.contains { $0.speedRamp != nil } == true }
    }

    // MARK: Picking

    /// A click on a stop: its clip and piece picked, the stop picked for the
    /// panel's rows, and the playhead on it so the picture shows its frame.
    func pickSpeedStopOnCurve(layerID: UUID, piece: Int, stop: Int) {
        selectClipPiece(layerID: layerID, index: piece)
        pickedSpeedStop = PickedSpeedStop(layerID: layerID, piece: piece, stop: stop)
        landOnSpeedStop(layerID, piece: piece, stop: stop)
    }

    func isSpeedStopPicked(layerID: UUID, piece: Int, stop: Int) -> Bool {
        guard let picked = pickedSpeedStop, picked.layerID == layerID, picked.piece == piece,
              picked.stop == stop else { return false }
        return selectedLayerID == layerID
    }

    /// A Command-click on the curve: a stop there, at the speed the curve
    /// already has, so nothing moves until it is dragged.
    func addSpeedStopOnCurve(layerID: UUID, atClipMS ms: Int) {
        guard !isClipLocked(layerID), let time = document?.layer(id: layerID)?.time else { return }
        endTrimBeforeCutting()
        pauseDocument()
        let at = time.inMS + ms
        var added: (piece: Int, stop: Int)?
        perform { added = $0.addSpeedStop(layerID, atMS: at) }
        guard let added else { return }
        pickSpeedStopOnCurve(layerID: layerID, piece: added.piece, stop: added.stop)
    }

    // MARK: Dragging

    func beginSpeedStopDrag(layerID: UUID, piece: Int, stop: Int, kind: SpeedCurve.HandleKind) {
        guard !isClipLocked(layerID),
              let ramp = document?.layer(id: layerID)?.clipPieces?.piece(at: piece)?.speedRamp,
              ramp.stops.indices.contains(stop) else { return }
        endTrimBeforeCutting()
        pauseDocument()
        selectClipPiece(layerID: layerID, index: piece)
        pickedSpeedStop = PickedSpeedStop(layerID: layerID, piece: piece, stop: stop)
        speedStopDrag = SpeedStopDragSession(layerID: layerID, piece: piece, stop: stop, kind: kind,
                                             toClipMS: nil, percent: ramp.stops[stop].speedPercent,
                                             percentBefore: ramp.stops[stop].speedPercent,
                                             holdMS: kind == .holdEnd ? ramp.stops[stop].holdMS : nil,
                                             heldCycleMS: motionStripCycleMS)
    }

    /// The hand moved: a stop to this moment of the clip and this speed, or
    /// a freeze's second zero to this moment.
    func updateSpeedStopDrag(toClipMS ms: Int?, speed: Double?) {
        guard var session = speedStopDrag else { return }
        switch session.kind {
        case .stop:
            session.toClipMS = ms
            session.percent = speed.map { SpeedCurve.percent(forSpeed: SpeedCurve.snapped($0)) } ?? session.percentBefore
        case .holdEnd:
            guard let ms, let pieces = document?.layer(id: session.layerID)?.clipPieces,
                  let start = pieces.timelineMS(ofStop: session.stop, inPiece: session.piece) else { return }
            session.holdMS = max(0, ms - start)
        }
        guard session != speedStopDrag else { return }
        speedStopDrag = session
        followSpeedStopInHand()
    }

    /// Let go: one step for undo, and the playhead left on the stop.
    func commitSpeedStopDrag() {
        guard let session = speedStopDrag else { return }
        speedStopDrag = nil
        perform { _ = Self.apply(session, to: &$0) }
        landOnSpeedStop(session.layerID, piece: session.piece, stop: session.stop)
    }

    func cancelSpeedStopDrag() {
        guard speedStopDrag != nil else { return }
        speedStopDrag = nil
        documentMomentChanged()
    }

    /// The document as the hand has it.
    func withDraggedSpeedStop(_ document: PhotonzDocument) -> PhotonzDocument {
        guard let session = speedStopDrag else { return document }
        var document = document
        Self.apply(session, to: &document)
        return document
    }

    @discardableResult
    private static func apply(_ session: SpeedStopDragSession, to document: inout PhotonzDocument) -> Bool {
        switch session.kind {
        case .stop:
            document.moveSpeedStop(session.layerID, ofPiece: session.piece, stop: session.stop,
                                   toClipMS: session.toClipMS, percent: session.percent)
        case .holdEnd:
            document.setSpeedStopHold(session.layerID, ofPiece: session.piece, stop: session.stop,
                                      holdMS: session.holdMS ?? 0)
        }
    }

    /// The playhead rides on the stop in the hand, so the picture shows the
    /// frame it is on as it moves.
    private func followSpeedStopInHand() {
        guard let session = speedStopDrag, let layer = shownDocument?.layer(id: session.layerID),
              let time = layer.time,
              let at = layer.clipPieces?.timelineMS(ofStop: session.stop, inPiece: session.piece) else {
            documentMomentChanged()
            return
        }
        let hold = session.kind == .holdEnd ? (session.holdMS ?? 0) : 0
        documentTimeMS = min(max(time.inMS + at + hold, time.inMS), max(time.inMS, time.outMS - 1))
        documentMomentChanged()
    }

    private func landOnSpeedStop(_ id: UUID, piece: Int, stop: Int) {
        guard let layer = document?.layer(id: id), let time = layer.time,
              let at = layer.clipPieces?.timelineMS(ofStop: stop, inPiece: piece) else { return }
        documentTimeMS = min(max(time.inMS + at, time.inMS), max(time.inMS, time.outMS - 1))
        documentMomentChanged()
    }

    // MARK: Freeze

    /// Whether the picked stop may become the mock's Freeze.
    var canFreezeSpeedStopInHand: Bool {
        guard let id = clipInHandID, !isClipLocked(id), let index = clipPieceInHand,
              let stop = speedStopInHand, let pieces = clipInHandPieces else { return false }
        return pieces.canFreezeSpeedStop(ofPiece: index, stop: stop)
            && speedRampInHand?.stops[stop].isFreeze == false
    }

    /// Freeze, from the stop's Speed list or its right click: the stop goes
    /// to nought and holds its frame a second, the mock's two zeros.
    func freezeSpeedStopInHand() {
        guard canFreezeSpeedStopInHand, let id = clipInHandID, let index = clipPieceInHand,
              let stop = speedStopInHand else { return }
        freezeSpeedStop(layerID: id, piece: index, stop: stop)
    }

    func freezeSpeedStop(layerID: UUID, piece: Int, stop: Int) {
        guard !isClipLocked(layerID) else { return }
        endTrimBeforeCutting()
        pauseDocument()
        var frozen = false
        perform { frozen = $0.freezeSpeedStop(layerID, ofPiece: piece, stop: stop, holdMS: SpeedStopNames.freezeHoldMS) }
        guard frozen else { return }
        pickSpeedStopOnCurve(layerID: layerID, piece: piece, stop: stop)
    }

    /// Delete Speed Stop on a stop's own right click.
    func deleteSpeedStop(layerID: UUID, piece: Int, stop: Int) {
        guard !isClipLocked(layerID) else { return }
        endTrimBeforeCutting()
        pauseDocument()
        perform { $0.deleteSpeedStop(layerID, ofPiece: piece, stop: stop) }
        pickedSpeedStop = nil
        selectClipPiece(layerID: layerID, index: piece)
        documentTimeMS = min(documentTimeMS, lastDocumentTimeMS)
        documentMomentChanged()
    }

    /// Ramp or Hold, from a stretch of the curve's right click.
    func setRampBlend(layerID: UUID, piece: Int, _ blend: SpeedRampBlend) {
        guard !isClipLocked(layerID) else { return }
        endTrimBeforeCutting()
        pauseDocument()
        perform { $0.setRampBlend(layerID, ofPiece: piece, blend) }
        selectClipPiece(layerID: layerID, index: piece)
        documentTimeMS = min(documentTimeMS, lastDocumentTimeMS)
        documentMomentChanged()
    }
}
