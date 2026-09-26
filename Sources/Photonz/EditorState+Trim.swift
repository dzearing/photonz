import AppKit
import Foundation
import PhotonzCore

// Trim, the tool (`docs/design/video-surface.md` §10).
//
// It is Crop with a different axis, and it is built to read that way: pick it
// up, handles appear on the thing whose bounds you are changing, one glass
// capsule says the numbers, ⏎ commits and ⎋ cancels. Crop puts its handles on
// the picture because the picture is what it bounds; Trim puts them on the
// clip's bar in the timeline for exactly the same reason.
//
// The session is held here, not in the document, so ⎋ costs nothing: nothing
// was written, so there is nothing to put back. While it runs the canvas and
// the timeline are shown the clip at its FULL length, which is what lets you
// scrub into the part a previous trim put out of play and decide to take it
// back (`PhotonzDocument.openedForTrim`).
extension EditorState {

    // MARK: Whether there is anything to trim

    /// Whether this document has anything a trim could act on. One fact, the
    /// same one that puts the timeline and the transport on screen (D19).
    var offersTrim: Bool { documentHasTime }

    /// The members of Crop's slot this document can use. In a screenshot that
    /// is Crop alone, so C twice does nothing new.
    var boundsToolsOffered: Set<Tool> { offersTrim ? [.crop, .trim] : [.crop] }

    /// The clip the session is on, where one is running.
    var trimmingLayerID: UUID? { trimSession?.layerID }

    /// True where Trim is in hand but there is nothing under it to trim: a
    /// background, an adjustment, a layer that occupies no time. The tool does
    /// not hide — a tool that vanishes per selection is a slot that moves — so
    /// the capsule says so instead (§10.5).
    var trimNeedsAClip: Bool { activeTool == .trim && trimSession == nil }

    // MARK: The session

    /// Pick the tool up: open a session on the clip you are on, or on the
    /// topmost one under the playhead when nothing is picked.
    ///
    /// The timeline comes up with it, because that is where the handles are
    /// and a tool whose handles are behind a closed dock is a tool that does
    /// nothing. Playing stops, the way it does for a crop.
    func beginTrim() {
        guard let document else { return }
        pauseDocument()
        guard let id = document.clipToTrim(pickedLayerID: selectedLayerID,
                                           atTimeMS: documentTimeMS),
              let layer = document.layer(id: id),
              let session = ClipTrimSession(layer: layer) else {
            trimSession = nil
            return
        }
        trimSession = session
        selectedLayerID = id
        isMotionStripOpen = true
        // The playhead keeps pointing at the frame it was pointing at: the
        // clip has just been laid out at full length, so everything after its
        // first frame has moved along by however much a previous trim had put
        // out of play at the front.
        documentTimeMS = min(documentTimeMS + session.openedInMS, lastDocumentTimeMS)
        documentMomentChanged()
    }

    /// Drag the in handle, in the shown timeline's own milliseconds. A hand on
    /// the handle (`catching`) catches on a cut while the timeline snaps, the
    /// way a clip dragged along the track does (`clipSnapMS`).
    func dragTrimIn(toMS ms: Int, catching: Bool = false) {
        guard var session = trimSession, let start = trimmedClipStartMS else { return }
        session.dragIn(toMS: catching ? session.caught(ms - start, withinMS: clipSnapMS) : ms - start)
        trimSession = session
        scrubDocument(toMS: start + session.keepInMS)
    }

    /// Drag the out handle, the same way round. The playhead lands on the last
    /// frame that is being kept rather than the first one that is not.
    func dragTrimOut(toMS ms: Int, catching: Bool = false) {
        guard var session = trimSession, let start = trimmedClipStartMS else { return }
        session.dragOut(toMS: catching ? session.caught(ms - start, withinMS: clipSnapMS) : ms - start)
        trimSession = session
        scrubDocument(toMS: max(start, start + session.keepOutMS - MovieRef.frameStepMS))
    }

    /// Give the whole recording back, without leaving the session.
    func resetTrimSelection() {
        guard var session = trimSession else { return }
        session.reset()
        trimSession = session
        documentMomentChanged()
    }

    /// ⏎, and the capsule's Trim button: keep what is between the handles.
    func commitTrim() {
        guard let session = trimSession else { return }
        let landed = documentTimeMS - (trimmedClipStartMS ?? 0) - session.keepInMS
        let piecesBefore = document?.layer(id: session.layerID)?.clipPieces?.count
        trimSession = nil
        if session.isChanged {
            perform { $0.applyTrim(session) }
        }
        TutorialController.shared.note(.trimApplied, from: self)
        setTool(.select)
        selectedLayerID = session.layerID
        // A trim across a cut throws pieces away, so the piece picked before
        // it is not at the same place in the list any more, or not there at
        // all. Nothing picked is the honest answer; the playhead still says
        // which piece the next edit acts on.
        if document?.layer(id: session.layerID)?.clipPieces?.count != piecesBefore {
            selectedClipPieceIndex = nil
        }
        // Land on the frame that was under the playhead, now that the frames
        // before the in point are not on the timeline any more.
        documentTimeMS = max(0, min(landed + (trimmedClipStartMS ?? 0), lastDocumentTimeMS))
        documentMomentChanged()
    }

    /// ⎋, and the capsule's Cancel: the clip goes back the way it was, which
    /// costs nothing because nothing was written. Putting the tool down is the
    /// whole of it (`setTool`), so every way out of the session — the capsule,
    /// the key, another tool, V — ends it the same way.
    func cancelTrim() {
        setTool(.select)
    }

    // MARK: What the window is being shown

    /// The document the canvas and the timeline are drawing RIGHT NOW.
    ///
    /// The same document, except while a trim runs: then it is that document
    /// with the clip laid out at full length, so the strip can draw the spare
    /// at both ends and the playhead can be taken into it. Nothing here is
    /// ever written down (`PhotonzDocument.openedForTrim`).
    var shownDocument: PhotonzDocument? {
        guard let document else { return nil }
        // A bar under a hand is drawn where the HAND has it, not where the
        // document still says it is, which is the same bargain the timing
        // strip and the pivot crosshair strike (`EditorState+ClipBar`).
        guard let session = trimSession else { return withDraggedCaptionWord(withDraggedClipBar(document)) }
        return document.openedForTrim(session)
    }

    /// Where the clip being trimmed sits on the shown timeline.
    var trimmedClipStartMS: Int? {
        guard let id = trimmingLayerID else { return nil }
        return shownDocument?.layer(id: id)?.time?.inMS
    }

    // MARK: What the capsule says

    /// `In 0:02 · Out 0:11 · 0:09 kept`, the three numbers a trim is about.
    var trimReadout: String {
        guard let session = trimSession else { return "" }
        return "In \(Self.timecode(ms: session.keepInMS)) · "
            + "Out \(Self.timecode(ms: session.keepOutMS)) · "
            + "\(Self.timecode(ms: session.keptMS)) kept"
    }

    /// Whether Reset has anything to give back.
    var canResetTrim: Bool { trimSession?.canReset ?? false }
}
