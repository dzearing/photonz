import Foundation
import PhotonzCore

// The camera's keys on a thin row at the top of the timeline
// (`show-the-camera-s-keys-on-a-thin-row-at-the-top`, `CameraRow.swift`,
// `TimelineCameraRow.swift`). The camera is a setting of the frame, so picking
// the row picks the frame, and the panel shows its Camera section.

extension EditorState {

    /// Whether the timeline shows its Camera row: something about the camera
    /// is keyed, in a document that runs over time.
    var showsCameraRow: Bool {
        guard Experiments.shared.turnInDepthEnabled, documentHasTime, let document else { return false }
        return document.hasCameraKeys
    }

    /// The Camera row's diamonds.
    var cameraKeyMoments: [CameraKeyMoment] { document?.cameraKeyMoments ?? [] }

    /// A click on the row off its diamonds: the frame is picked, and the
    /// panel shows the Camera section.
    func pickCameraRow() {
        pickedCameraKeyMS = nil
        clearKeySelection()
        showCameraSettings()
    }

    /// A click on a diamond: the frame is picked, the diamond with it, and
    /// the playhead goes to it so the panel's diamonds say what is keyed
    /// there, the way a click on a layer's key does.
    func pickCameraKey(atMS ms: Int) {
        clearKeySelection()
        showCameraSettings()
        pickedCameraKeyMS = ms
        if isDocumentPlaying { pauseDocument() }
        scrubDocument(toMS: ms)
    }

    /// Whether the diamond at `ms` is the picked one, with the frame still
    /// in hand.
    func isCameraKeyPicked(_ ms: Int) -> Bool {
        guard isCanvasSelected, let picked = pickedCameraKeyMS else { return false }
        return abs(picked - ms) <= PropertyKeys.nearMS
    }

    // MARK: Dragging

    func beginCameraKeyDrag(fromMS ms: Int) {
        if !isCameraKeyPicked(ms) {
            clearKeySelection()
            showCameraSettings()
            pickedCameraKeyMS = ms
        }
        cameraKeyDrag = (ms, 0)
    }

    func updateCameraKeyDrag(byMS ms: Int) {
        guard let drag = cameraKeyDrag else { return }
        cameraKeyDrag = (drag.fromMS, ms)
    }

    /// Let go: every camera key at the diamond lands where the hand left
    /// it, as one undo step, and stays picked there.
    func commitCameraKeyDrag() {
        guard let drag = cameraKeyDrag else { return }
        cameraKeyDrag = nil
        guard drag.byMS != 0 else { return }
        var landed: Int?
        perform { landed = $0.moveCameraKeys(atMS: drag.fromMS, toMS: drag.fromMS + drag.byMS) }
        if let landed { pickedCameraKeyMS = landed }
    }

    func cancelCameraKeyDrag() { cameraKeyDrag = nil }

    // MARK: Deleting

    /// Whether ⌫ means the picked Camera row diamond.
    var canDeletePickedCameraKey: Bool {
        guard documentHasTime, let ms = pickedCameraKeyMS, isCameraKeyPicked(ms) else { return false }
        return cameraKeyMoments.contains { abs($0.ms - ms) <= PropertyKeys.nearMS }
    }

    /// Every camera key at a diamond goes, as one undo step.
    func deleteCameraKeys(atMS ms: Int) {
        if let picked = pickedCameraKeyMS, abs(picked - ms) <= PropertyKeys.nearMS { pickedCameraKeyMS = nil }
        perform { $0.removeCameraKeys(atMS: ms) }
    }

    // MARK: Easing (`camera-keys-ease-in-and-out-like-every-other-key`)

    /// Every camera key at a diamond moves through it the way `ease` says, as
    /// one undo step. The frame stays picked, with the diamond.
    func easeCameraKeys(atMS ms: Int, _ ease: KeyEase) {
        perform { $0.easeCameraKeys(atMS: ms, ease) }
    }

    /// The ease the picked Camera row diamond's keys share, for the timeline
    /// bar's Easing; nil where they differ.
    var pickedCameraKeysEase: KeyEase? {
        guard let ms = pickedCameraKeyMS, isCameraKeyPicked(ms) else { return nil }
        return document?.cameraKeysEase(atMS: ms)
    }

    /// Whether the timeline bar's Easing speaks for a Camera row diamond.
    var easesPickedCameraKey: Bool { canDeletePickedCameraKey }

    /// The Camera section's Curve row: whether the camera has a stretch at
    /// the playhead to shape.
    var cameraHasStretch: Bool {
        guard documentHasTime, let document else { return false }
        return document.cameraHasStretch(atDocumentTimeMS: documentTimeMS)
    }

    /// The curve the camera's stretch at the playhead runs on; nil where the
    /// values moving there differ (Mixed).
    var cameraStretchCurve: EasingCurve? {
        document?.cameraStretchCurve(atDocumentTimeMS: documentTimeMS)
    }

    /// The Curve row chosen: the camera's stretch at the playhead runs on
    /// `curve`, one undo step.
    func curveCameraStretch(_ curve: EasingCurve) {
        guard cameraHasStretch, cameraStretchCurve != curve else { return }
        let time = documentTimeMS
        perform { $0.curveCameraStretch(atDocumentTimeMS: time, curve) }
    }

    /// A right click on a diamond: the eases a key on a layer's track
    /// offers, ticked where every camera key there agrees, then Go to Key,
    /// the Camera section and Delete.
    func cameraKeyMenuRows(atMS ms: Int) -> [MenuRow] {
        let current = document?.cameraKeysEase(atMS: ms)
        var rows: [MenuRow] = KeyEase.allCases.map { ease in
            .toggle(ease.title, isOn: current == ease) { self.easeCameraKeys(atMS: ms, ease) }
        }
        rows += [
            .separator,
            .command("Go to Key") { self.pickCameraKey(atMS: ms) },
            .command("Show Camera Settings") { self.pickCameraRow() },
            .separator,
            .command("Delete Key", destructive: true) { self.deleteCameraKeys(atMS: ms) },
        ]
        return rows
    }
}
