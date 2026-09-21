import AppKit
import Foundation
import PhotonzCore

// Cutting, arranging and retiming on the timeline (`ClipBarDrag.swift`,
// `docs/design/video-surface.md` §10.4).
//
// The bar in the timeline is where a recording is cut about, and this is the
// thin layer between the hand and the arithmetic. Everything that decides a
// number lives in `PhotonzCore`; everything here is about which clip, which
// piece, and making a whole drag one step to undo.
//
// The three things a person does, and where each one is:
//
//  - **Cut.** The playhead is the cut line. B splits the clip under it, ⌫
//    throws the piece you are on away and the join closes. No blade to pick up
//    and no mode to get out of: you were already looking at the frame.
//  - **Trim.** Every edge on the bar can be dragged and every one of them
//    follows the hand (`ClipBarDrag`). Nothing is thrown away, so an edge
//    pulled in can always be pulled back out.
//  - **Arrange.** A piece can be picked up and dropped somewhere else in the
//    order, with the place it would land drawn while you hold it.
extension EditorState {

    // MARK: Which clip, and which piece of it

    /// The clip the timeline's edits act on: the one picked when it occupies
    /// time, else the topmost thing with time under the playhead.
    ///
    /// The same rule Trim uses, for the same reason: in a just-opened
    /// recording there is one clip and the playhead is on it, so cutting needs
    /// no click first.
    var clipInHandID: UUID? {
        document?.clipToTrim(pickedLayerID: selectedLayerID, atTimeMS: documentTimeMS)
    }

    /// Its pieces, as the document has them.
    var clipInHandPieces: ClipPieces? {
        guard let id = clipInHandID else { return nil }
        return document?.layer(id: id)?.clipPieces
    }

    /// Which piece the edits act on: the one picked, else the one the playhead
    /// is standing on. A person watching a frame and pressing ⌫ means that
    /// frame's piece, and asking them to click it first would be asking them
    /// to say twice what they have already said once.
    var clipPieceInHand: Int? {
        guard let id = clipInHandID, let pieces = clipInHandPieces,
              let time = document?.layer(id: id)?.time else { return nil }
        if let picked = selectedClipPieceIndex, picked < pieces.count { return picked }
        return pieces.pieceIndex(atMS: documentTimeMS - time.inMS)
    }

    /// The piece itself, for a surface that wants to read it rather than edit
    /// it: the Time section reads its length, its speed and its silence
    /// straight off it (`SpeedInspector`).
    var clipPieceInHandPiece: ClipPiece? {
        guard let index = clipPieceInHand else { return nil }
        return clipInHandPieces?.piece(at: index)
    }

    /// Pick a piece. Picking one picks its clip too, so the panel and the
    /// timeline are talking about the same thing.
    func selectClipPiece(layerID: UUID, index: Int?) {
        if selectedLayerID != layerID { selectLayer(layerID) }
        selectedClipPieceIndex = index
    }

    /// Put the Trim tool down before cutting, because the two cannot both be
    /// true of the same bar.
    ///
    /// A trim session lays the clip out at its FULL length so the spare at
    /// each end can be seen, and cutting a bar that is being shown at a length
    /// it does not have would put the cut in the wrong place. A recording
    /// opens with Trim already in hand (§10.3), so this runs on the first B
    /// almost every time.
    ///
    /// A session nobody has touched is simply dropped. One whose handles HAVE
    /// been moved is committed instead: that trim is a thing the person did,
    /// and it lands as its own history step before the cut lands as another.
    func endTrimBeforeCutting() {
        guard let session = trimSession else { return }
        session.isChanged ? commitTrim() : cancelTrim()
    }

    /// How near a drop has to land to catch on an edge already on the
    /// timeline. A share of the document rather than a fixed number of
    /// milliseconds, so it is about the same few points of travel whether the
    /// recording is eight seconds or eight minutes.
    var clipSnapMS: Int { max(16, documentLengthMS / 150) }

    // MARK: Cutting

    /// Whether the playhead is somewhere a cut would mean anything: inside a
    /// clip, and not already on one of its joins.
    var canSplitClipAtPlayhead: Bool {
        guard Experiments.shared.cutRecordingEnabled, documentHasTime,
              let id = clipInHandID, let time = document?.layer(id: id)?.time,
              let pieces = clipInHandPieces else { return false }
        guard documentTimeMS > time.inMS, documentTimeMS < time.outMS else { return false }
        var trial = pieces
        return trial.split(atMS: documentTimeMS - time.inMS)
    }

    /// B, and Video ▸ Split at Playhead. One clip becomes two pieces of the
    /// same clip, both reading the same recording.
    func splitClipAtPlayhead() {
        endTrimBeforeCutting()
        guard canSplitClipAtPlayhead, let id = clipInHandID else { return }
        pauseDocument()
        perform { $0.splitClip(id, atMS: documentTimeMS) }
        // **The piece you are left holding is the one BEFORE the cut**, and
        // the model does not decide that — the surface does.
        //
        // It is chosen for the job people actually come here for: getting rid
        // of a fumble in the middle of a take. Cut where it starts, cut where
        // it ends, and the second cut leaves you holding exactly the bad bit,
        // so ⌫ throws it away with no click in between. Picking the half after
        // the cut instead would cost a click on every single one of those.
        // Cutting the dead air off an end does not need this at all: the bar's
        // own ends are draggable, and dragging one throws nothing away.
        if let time = document?.layer(id: id)?.time,
           let landed = document?.layer(id: id)?.clipPieces?
               .pieceIndex(atMS: documentTimeMS - time.inMS - 1) {
            selectClipPiece(layerID: id, index: landed)
        }
        documentMomentChanged()
    }

    /// Whether ⌫ means "throw this piece away" rather than "delete this
    /// layer".
    ///
    /// It takes an explicitly PICKED piece, never the one the playhead happens
    /// to be standing on. ⌫ already means delete the layer, and a key that
    /// silently means something else because of where the playhead is would be
    /// the most expensive surprise in the app. Cutting hands you the piece
    /// after the cut, so the common job — two cuts and throw the middle away —
    /// still costs no clicks.
    var canDeleteClipPieceInHand: Bool {
        guard Experiments.shared.cutRecordingEnabled, documentHasTime,
              let id = clipInHandID, selectedLayerID == id,
              let index = selectedClipPieceIndex,
              let pieces = clipInHandPieces else { return false }
        return pieces.canRemove(at: index)
    }

    /// ⌫ on a piece of a clip: this piece goes and the join closes. Everything
    /// after it slides back, which is the one ripple rule the whole timeline
    /// obeys.
    func deleteClipPieceInHand() {
        endTrimBeforeCutting()
        guard canDeleteClipPieceInHand, let id = clipInHandID,
              let index = selectedClipPieceIndex else { return }
        pauseDocument()
        let landing = document?.layer(id: id)?.clipPieces?.startMS(ofPiece: index) ?? 0
        let start = document?.layer(id: id)?.time?.inMS ?? 0
        perform { $0.removeClipPiece(id, at: index) }
        // The playhead lands on the join the delete just closed, which is the
        // frame that now plays where the thrown-away piece used to start.
        selectClipPiece(layerID: id, index: nil)
        documentTimeMS = min(max(0, start + landing), lastDocumentTimeMS)
        documentMomentChanged()
    }

    var canHoldFrameAtPlayhead: Bool {
        guard Experiments.shared.cutRecordingEnabled, documentHasTime,
              let id = clipInHandID, let time = document?.layer(id: id)?.time else { return false }
        return time.contains(ms: documentTimeMS)
    }

    /// Hold on the frame under the playhead. It drops onto the timeline as an
    /// ordinary piece, which is the whole point: a freeze is not a special
    /// object, it is a piece whose in and out are the same frame.
    func holdFrameAtPlayhead() {
        endTrimBeforeCutting()
        guard canHoldFrameAtPlayhead, let id = clipInHandID else { return }
        pauseDocument()
        perform { $0.holdFrame(id, atMS: documentTimeMS) }
        if let time = document?.layer(id: id)?.time,
           let held = document?.layer(id: id)?.clipPieces?.pieceIndex(atMS: documentTimeMS - time.inMS) {
            selectClipPiece(layerID: id, index: held)
        }
        documentMomentChanged()
    }

    /// What is being held at the moment the canvas is drawing, or nil while the
    /// picture is playing. The canvas says so on the picture
    /// (`EditorView.heldFrameBadge`), because a picture that has stopped moving
    /// while the clock carries on looks exactly like one that has stalled.
    var heldFrameNow: HeldFrame? {
        guard Experiments.shared.cutRecordingEnabled, documentHasTime else { return nil }
        return document?.heldFrame(atTimeMS: documentTimeMS)
    }

    /// How long the held piece in hand is on screen for, or nil where the piece
    /// in hand is one that plays.
    var holdLengthInHand: Int? {
        guard let piece = clipPieceInHandPiece, piece.isHeld else { return nil }
        return piece.lengthMS
    }

    func canSetHoldLength(_ ms: Int) -> Bool {
        guard Experiments.shared.cutRecordingEnabled, documentHasTime,
              let current = holdLengthInHand else { return false }
        return current != ms
    }

    /// Hold the frame in hand for a chosen length. Everything after it moves
    /// along, exactly as it does when the hold's own end is dragged on the
    /// timeline — this is the same edit, reached by clicking rather than by
    /// dragging.
    func setHoldLengthInHand(_ ms: Int) {
        endTrimBeforeCutting()
        guard canSetHoldLength(ms), let id = clipInHandID,
              let index = clipPieceInHand else { return }
        pauseDocument()
        perform { $0.setHoldLength(id, ofPiece: index, toMS: ms) }
        selectClipPiece(layerID: id, index: index)
        documentTimeMS = min(documentTimeMS, lastDocumentTimeMS)
        documentMomentChanged()
    }

    // MARK: Retiming

    /// The speeds on offer, which live in the model beside everything else a
    /// speed means, so the menu and the panel offer the same list
    /// (`ClipSpeed.stops`).
    static var clipSpeeds: [Int] { ClipSpeed.stops }

    /// What the piece in hand is playing at, or nil where there is no piece to
    /// ask about. A held frame answers nil: it reads no stretch of the
    /// recording, so it has no speed. The Time section reads the piece itself
    /// through `clipPieceInHandPiece`, so it can say "a held frame" rather
    /// than showing nothing at all.
    var clipSpeedInHand: Int? {
        guard let pieces = clipInHandPieces, let index = clipPieceInHand,
              let piece = pieces.piece(at: index), !piece.isHeld else { return nil }
        return piece.speedPercent
    }

    /// Whether there is anything to retime at all, which is what decides
    /// whether the Time section is in the panel.
    ///
    /// Any clip with time under it, cut or not: an uncut recording is one
    /// piece and one piece can be sped up. That is looser than Transition next
    /// to it, which needs a join, and it is right: retiming is the first thing
    /// somebody does to a recording, long before they cut one.
    var canRetimeAClip: Bool {
        Experiments.shared.cutRecordingEnabled && documentHasTime
            && clipPieceInHandPiece != nil
    }

    func canSetClipSpeed(_ percent: Int) -> Bool {
        guard Experiments.shared.cutRecordingEnabled, documentHasTime,
              let current = clipSpeedInHand else { return false }
        return current != percent
    }

    /// Speed a stretch up or slow it down. The piece keeps the frames it reads
    /// and changes how long they take, so everything after it moves along.
    ///
    /// **Its sound goes with it**, at the same rate, because the sound is part
    /// of the piece rather than a separate thing to keep in step
    /// (`ClipPiece.soundRatePercent`) — and past double speed or below half it
    /// stops rather than squealing, which the panel says in words before and
    /// after you pick it (`ClipSpeedSound`).
    func setClipSpeedInHand(_ percent: Int) {
        endTrimBeforeCutting()
        guard canSetClipSpeed(percent), let id = clipInHandID,
              let index = clipPieceInHand else { return }
        pauseDocument()
        perform { $0.setClipSpeed(id, ofPiece: index, percent: percent) }
        selectClipPiece(layerID: id, index: index)
        documentTimeMS = min(documentTimeMS, lastDocumentTimeMS)
        documentMomentChanged()
    }

    // MARK: A bar under the hand

    /// Take hold of an edge, a piece or the bar itself.
    func beginClipBarDrag(layerID: UUID, grab: ClipBarGrab) {
        endTrimBeforeCutting()
        guard let document, let layer = document.layer(id: layerID),
              let time = layer.time, let pieces = layer.clipPieces else { return }
        pauseDocument()
        // Taking hold of a bar picks its clip, and taking hold of a piece
        // picks that piece, so the panel is talking about what is in the hand.
        if case .carry(let piece) = grab {
            selectClipPiece(layerID: layerID, index: piece)
        } else if selectedLayerID != layerID {
            selectLayer(layerID)
        }
        let drag = ClipBarDrag(grab: grab, pieces: pieces, clipStartMS: time.inMS,
                               others: document.clipBarEdges(excluding: layerID,
                                                             playheadMS: documentTimeMS),
                               snapWithinMS: clipSnapMS,
                               startIsFree: layer.startIsFree)
        clipBarDrag = ClipBarDragSession(layerID: layerID, grab: grab, drag: drag,
                                         landing: drag.landing(byMS: 0),
                                         heldTimelineMS: max(1, document.documentDurationMS))
        watchForClipBarEscape()
    }

    /// The hand moved. Nothing is written down: the strip and the canvas both
    /// read the landing, so the picture follows at once and the whole drag is
    /// still one step to undo.
    func updateClipBarDrag(byMS delta: Int) {
        guard var session = clipBarDrag else { return }
        session.landing = session.drag.landing(byMS: delta)
        clipBarDrag = session
        rerender()
    }

    /// Let go: one step for undo covering the whole drag.
    func commitClipBarDrag() {
        stopWatchingForClipBarEscape()
        guard let session = clipBarDrag else { return }
        clipBarDrag = nil
        let landing = session.landing
        let id = session.layerID
        switch session.grab {
        case .clipStart where session.drag.startIsFree:
            // Nothing behind it to trim into, so this edge is simply the moment
            // the layer arrives: it lands where the hand left it and the far
            // end does not move (`TitleTime.moveLayerStart`).
            guard landing.movedMS != 0 else { break }
            perform { $0.moveLayerStart(id, toMS: landing.clipStartMS) }
        case .clipStart:
            guard landing.movedMS != 0 else { break }
            perform { $0.trimClipStart(id, ofPiece: 0, byMS: landing.movedMS) }
        case .seam(let after):
            guard landing.movedMS != 0 else { break }
            perform { $0.trimClipEnd(id, ofPiece: after, byMS: landing.movedMS) }
        case .body:
            guard landing.movedMS != 0 else { break }
            perform { $0.moveClip(id, toInMS: landing.clipStartMS) }
        case .carry(let piece):
            guard let to = landing.dropIndex else { break }
            perform { $0.moveClipPiece(id, from: piece, to: to) }
            selectClipPiece(layerID: id, index: to)
        }
        documentTimeMS = min(documentTimeMS, lastDocumentTimeMS)
        documentMomentChanged()
    }

    /// Escape, or a drag that went nowhere. Costs nothing, because nothing was
    /// written.
    func cancelClipBarDrag() {
        stopWatchingForClipBarEscape()
        guard clipBarDrag != nil else { return }
        clipBarDrag = nil
        documentMomentChanged()
    }

    /// Escape, for as long as there is a bar in hand. A key WATCH rather than a
    /// binding, for the reason the timing strip's one is: SwiftUI hands a
    /// gesture no key events at all, so a bar taken hold of could otherwise
    /// only be let go of by finishing the drag and undoing it.
    private func watchForClipBarEscape() {
        guard clipBarEscapeWatch == nil else { return }
        clipBarEscapeWatch = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, clipBarDrag != nil else { return event }
            cancelClipBarDrag()
            return nil
        }
    }

    private func stopWatchingForClipBarEscape() {
        guard let watch = clipBarEscapeWatch else { return }
        NSEvent.removeMonitor(watch)
        clipBarEscapeWatch = nil
    }

    /// `document` with the bar under the hand written into it.
    ///
    /// Read by the strip AND by the canvas, which is the whole of "one model,
    /// two views": the bar you are dragging and the frame you are looking at
    /// are the same edit, so a trim shows you the frame it is about to land on
    /// rather than the one you started from.
    func withDraggedClipBar(_ document: PhotonzDocument) -> PhotonzDocument {
        guard let session = clipBarDrag else { return document }
        var document = document
        let landing = session.landing
        document.updateLayer(id: session.layerID) { layer in
            layer.setClipPieces(landing.pieces)
            layer.time = layer.time?.moved(toInMS: landing.clipStartMS)
        }
        // **The ruler is HELD for the length of the drag.** A document that
        // grew to fit the clip being dragged would rescale the ruler under the
        // hand doing the dragging, and the bar would chase the pointer instead
        // of following it — the same bargain `motionStripCycleMS` strikes, and
        // the bug that was really there: sliding a clip two seconds later
        // stretched an eight second timeline to ten while the hand was still
        // down. A clip taken past the end simply runs off the right hand edge
        // until it is let go of, and then the ruler says the new length.
        if document.durationMS != nil { document.durationMS = session.heldTimelineMS }
        return document
    }

    // MARK: What the capsule says

    /// The numbers the drag is making, said in one line over the bar.
    var clipBarReadout: String? {
        guard let session = clipBarDrag else { return nil }
        let landing = session.landing
        switch session.grab {
        case .clipStart:
            return ClipBarCopy.trimming(pieceNumber: 1, of: landing.pieces.count,
                                        lengthMS: landing.pieces.piece(at: 0)?.lengthMS ?? 0,
                                        changeMS: -landing.movedMS)
        case .seam(let after):
            return ClipBarCopy.trimming(pieceNumber: after + 1, of: landing.pieces.count,
                                        lengthMS: landing.pieces.piece(at: after)?.lengthMS ?? 0,
                                        changeMS: landing.movedMS)
        case .body:
            return ClipBarCopy.moving(startMS: landing.clipStartMS, changeMS: landing.movedMS)
        case .carry(let piece):
            guard let to = landing.dropIndex else { return nil }
            return ClipBarCopy.carrying(pieceNumber: piece + 1, toPlace: to + 1,
                                        of: landing.pieces.count)
        }
    }

    /// What it caught on, for the line the strip draws and the words under it.
    var clipBarSnap: MotionStripEdge? { clipBarDrag?.landing.snappedTo }
}

/// A clip's bar in a hand: which clip, which edge, and where it has got to.
///
/// Kept out of the document for the reason the timing drag is: the whole drag
/// has to be one step to undo rather than forty.
struct ClipBarDragSession {
    let layerID: UUID
    let grab: ClipBarGrab
    /// The arithmetic, holding the pieces the clip had when it was grabbed.
    let drag: ClipBarDrag
    var landing: ClipBarDrag.Landing
    /// How long the document was when the bar was grabbed, held for the length
    /// of the drag so the ruler cannot rescale under the hand.
    let heldTimelineMS: Int
}
