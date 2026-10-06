import Foundation
import PhotonzCore

// Premiere's Nudge Clip Selection (`ClipNudge.swift` decides how far): ⌘← and
// ⌘→ move the picked clips a frame earlier or later, ⇧⌘ five, each press one
// step to undo. The whole clip goes, the way a ⌘ drag on one of its pieces
// carries the whole clip; several picked clips go together.
extension EditorState {

    /// The clips a nudge acts on: the picked ones, as Delete and the arrange
    /// commands read them. Empty with nothing picked, or in Current, where a
    /// recording is not cut on a timeline.
    var clipsToNudge: [UUID] {
        guard Experiments.shared.cutRecordingEnabled, documentHasTime, let document else { return [] }
        let picked = Array(actionableLayerIDs)
        return document.canNudgeClips(picked) ? picked : []
    }

    var canNudgeClips: Bool { !clipsToNudge.isEmpty }

    /// Nudge the picked clips `frames` frames, later when positive. False
    /// where nothing moved: nothing picked, or every clip already against
    /// the start or the clip beside it.
    @discardableResult
    func nudgeClips(byFrames frames: Int) -> Bool {
        let ids = clipsToNudge
        guard !ids.isEmpty, var trial = document, trial.nudgeClips(ids, byFrames: frames) else { return false }
        perform { $0.nudgeClips(ids, byFrames: frames) }
        return true
    }
}
