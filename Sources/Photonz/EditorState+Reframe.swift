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

    /// Whether a right-click Punch In preset can land on this clip.
    func canPunchIn(layerID: UUID) -> Bool {
        guard Experiments.shared.punchInEnabled, documentHasTime, !isClipLocked(layerID),
              let layer = document?.layer(id: layerID), let time = layer.time else { return false }
        return layer.takesAReframe && time.contains(ms: documentTimeMS)
    }

    /// Punch In as a preset: `percent` of the way in, around `point` (the
    /// middle of the picture when nil), arriving at the playhead.
    func punchIn(layerID: UUID, percent: Int, around point: CGPoint?) {
        guard canPunchIn(layerID: layerID), let layer = document?.layer(id: layerID) else { return }
        let region = ClipReframe.presetRegion(percent: percent, around: point, in: layer.frame)
        let at = documentTimeMS
        perform { $0.punchIn(layerID: layerID, onRegion: region, atTimeMS: at) }
        selectLayer(layerID)
        isMotionStripOpen = true
        reframeChanged()
    }

    /// Pull back out on one clip, from the playhead.
    func pullBackOut(layerID: UUID) {
        guard canPunchIn(layerID: layerID), document?.layer(id: layerID)?.isReframed == true else { return }
        let at = documentTimeMS
        perform { $0.pullBackOut(layerID: layerID, atTimeMS: at) }
        reframeChanged()
    }

    /// Put the camera back on the whole frame on one clip.
    func resetReframe(layerID: UUID) {
        guard document?.layer(id: layerID)?.isReframed == true else { return }
        perform { $0.resetReframe(layerID: layerID) }
        reframeChanged()
    }

    /// The Punch In submenu for a clip: the presets, the box you drew with M
    /// when there is one, and the ways back out once it is in.
    func punchInMenuRows(layerID: UUID, around point: CGPoint?) -> [MenuRow] {
        guard Experiments.shared.punchInEnabled,
              document?.layer(id: layerID)?.takesAReframe == true else { return [] }
        let can = canPunchIn(layerID: layerID)
        var rows: [MenuRow] = ClipReframe.punchInPresets.map { percent in
            .command("\(percent)%", enabled: can) {
                self.punchIn(layerID: layerID, percent: percent, around: point)
            }
        }
        if reframeClipID == layerID, canPunchIn {
            rows.append(.command("To the Box") { self.punchInOnRegion() })
        }
        if document?.layer(id: layerID)?.isReframed == true {
            rows.append(.separator)
            rows.append(.command("Pull Back Out", enabled: can) { self.pullBackOut(layerID: layerID) })
            rows.append(.command("Reset") { self.resetReframe(layerID: layerID) })
        }
        return [.submenu("Punch In", rows)]
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
}
