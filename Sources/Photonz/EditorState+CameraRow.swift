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

    /// A right click on a diamond.
    func cameraKeyMenuRows(atMS ms: Int) -> [MenuRow] {
        [
            .command("Go to Key") { self.pickCameraKey(atMS: ms) },
            .command("Show Camera Settings") { self.pickCameraRow() },
            .separator,
            .command("Delete Key", destructive: true) { self.deleteCameraKeys(atMS: ms) },
        ]
    }
}
