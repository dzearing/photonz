import AppKit
import Foundation
import PhotonzCore

// Punching in on something and holding there, in the hand
// (`ClipReframe.swift`, `docs/design/mocks/pages/video-zoom-wt.html`).
//
// The arithmetic is all in `PhotonzCore`; this is the thin layer between it and
// a person: which clip the move lands on, where "that thing there" comes from,
// and making each move one step to undo.
//
// **Where it pushes in to is pointed at, not typed.** The clickthrough's answer
// was eight clicks — key a value you have not changed, scrub, drag a percentage
// up, drag the picture, pick a curve — and it admits in its own words that the
// third step "feels odd for a second". The app already has one gesture that
// means "this part of the picture": the marquee. So a punch-in is drag a box,
// stand on the moment, Punch In. The box is consumed by the move, because it
// has said what it had to say.
extension EditorState {

    // MARK: What the move lands on

    /// The clip a reframe acts on: the one picked, else the one under the
    /// playhead, and only where it is something a camera could be pointed at.
    var reframeClipID: UUID? {
        guard Experiments.shared.punchInEnabled, let id = clipInHandID,
              document?.layer(id: id)?.takesAReframe == true else { return nil }
        return id
    }

    /// Whether the panel has a Reframe section to show at all.
    var canReframeAClip: Bool { reframeClipID != nil }

    /// How the clip is framed at the moment on screen: how far in, what is in
    /// the middle, and how much of the recording's own detail is left.
    var reframeReading: ReframeReading? {
        guard let id = reframeClipID, let document = shownDocument,
              let layer = document.layer(id: id) else { return nil }
        return layer.reframeReading(atDocumentTimeMS: documentTimeMS,
                                    documentCycleMS: max(1, document.documentDurationMS))
    }

    /// The box the punch-in would go to, in document points: the marquee's
    /// bounds, clipped to the clip's own picture so a box dragged off the edge
    /// cannot ask for frames that were never recorded.
    var reframeRegion: CGRect? {
        guard let id = reframeClipID, let layer = document?.layer(id: id),
              let bounds = selection?.bounds else { return nil }
        let inside = bounds.standardized.intersection(layer.frame.standardized)
        guard !inside.isNull,
              ClipReframe.scalePercent(fitting: inside, into: layer.frame) != nil
        else { return nil }
        return inside
    }

    // MARK: The two moves

    var canPunchIn: Bool { reframeRegion != nil }

    /// Push in on the box, arriving at the playhead.
    func punchInOnRegion() {
        guard let id = reframeClipID, let region = reframeRegion else { return }
        let at = documentTimeMS
        perform { $0.punchIn(layerID: id, onRegion: region, atTimeMS: at) }
        // The box has said what it had to say. Leaving it up would put a
        // marching outline over the very detail the move just went to, and the
        // next punch-in would inherit the last one's aim.
        setSelection(nil, recording: false)
        selectLayer(id)
        isMotionStripOpen = true
        reframeChanged()
    }

    var canPullBackOut: Bool {
        guard let id = reframeClipID else { return false }
        return document?.layer(id: id)?.isReframed == true
    }

    /// Leave, from the playhead. Everything between the last move and here is
    /// the hold, and nobody had to ask for it.
    func pullReframeBackOut() {
        guard let id = reframeClipID, canPullBackOut else { return }
        let at = documentTimeMS
        perform { $0.pullBackOut(layerID: id, atTimeMS: at) }
        reframeChanged()
    }

    var canResetReframe: Bool { canPullBackOut }

    func resetReframeInHand() {
        guard let id = reframeClipID, canResetReframe else { return }
        perform { $0.resetReframe(layerID: id) }
        reframeChanged()
    }

    /// The camera moved, so the canvas draws this moment again.
    ///
    /// **Not `motionChanged()`, which starts the motion PREVIEW.** That loop is
    /// an icon's: it runs its own lap clock and hands the canvas a document
    /// drawn at a moment of the lap, while the transport is still pointing at a
    /// frame of the recording. With both running the canvas drew two different
    /// moments at once and tore down the middle (seen on the first walk). A
    /// document that finishes has one clock, and it is the playhead's.
    func reframeChanged() {
        if documentHasTime { pauseMotionPreview() }
        documentMomentChanged()
    }

    // MARK: What the section says when it cannot do anything

    /// The one line under the buttons, which always says the NEXT thing to do
    /// rather than what is wrong.
    var reframeHint: String {
        guard let id = reframeClipID, let layer = document?.layer(id: id) else {
            return "Pick a clip to move the camera on it."
        }
        if canPunchIn {
            return "Punch In takes the camera to the box by the playhead, and holds it there."
        }
        if selection != nil {
            return "That box is too small, or it is off the picture. "
                + "Drag one round the part of the frame that should fill it."
        }
        if layer.isReframed {
            return "Drag a box with M round the next thing to look at, or Pull Back Out "
                + "to go wide from the playhead."
        }
        return "Drag a box with M round the part of the picture that should fill the frame, "
            + "then Punch In."
    }
}
