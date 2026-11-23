import Foundation
import PhotonzCore

// A colour grade on a track of its own, over every clip below it
// (`docs/design/mocks/pages/video-compositing.html`, the V4 colour grade
// track; `ColorGradeLayer.swift`). Sequence > Add Color Grade puts one on a
// new Grade track at the top from the playhead to the end; an empty picture
// track's right-click puts one on that track. It arrives picked, so its Color
// Grade rows, its Blending and its Masked by are in the panel at once.
extension EditorState {

    /// Whether this document can take a colour grade track: a video, in a
    /// release that has Color Grade.
    var canAddColorGrade: Bool {
        Experiments.shared.colorGradeEnabled && documentHasTime
    }

    /// A colour grade from the playhead to the end of the video, on
    /// `trackID` when that track is free for all of it, on a new Grade track
    /// at the top otherwise. One step to undo, and picked.
    func addColorGrade(onTrack trackID: UUID? = nil) {
        guard canAddColorGrade else { return }
        pauseDocument()
        let moment = documentTimeMS
        var added: UUID?
        perform { added = $0.addColorGrade(atMS: moment, onTrack: trackID) }
        guard let added else { return }
        selectLayer(added)
        switchToEditForAnEdit()
        rerender()
    }
}
