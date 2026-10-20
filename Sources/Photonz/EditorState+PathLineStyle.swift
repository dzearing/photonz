import Foundation
import PhotonzCore

// What KIND of line a path is drawn with, set from Appearance: whether it has
// an outline at all, how its ends and its corners are shaped, and whether it is
// solid, dashed or dotted (`PhotonzCore/PathLineStyle.swift`).
//
// Every one of these is a whole answer rather than a drag, so each goes through
// `History.perform` outright: one choice, one undo step.

extension EditorState {

    /// The Outline switch on a closed path: takes the line away, or hands one
    /// back at the weight a freshly drawn shape wears.
    func setPathOutline(ids: [UUID], on: Bool) {
        guard !ids.isEmpty else { return }
        discardDragPreview()
        perform { _ = $0.setPathOutline(layerIDs: ids, on: on) }
    }

    /// What the ends of the line look like.
    func setPathLineEnd(ids: [UUID], _ end: PathLineEnd) {
        guard !ids.isEmpty else { return }
        discardDragPreview()
        perform { _ = $0.setPathLineEnd(layerIDs: ids, to: end) }
        rememberLines(of: ids)
    }

    /// How the line turns a corner.
    func setPathLineCorner(ids: [UUID], _ corner: PathLineCorner) {
        guard !ids.isEmpty else { return }
        discardDragPreview()
        perform { _ = $0.setPathLineCorner(layerIDs: ids, to: corner) }
        rememberLines(of: ids)
    }

    /// Solid, dashed or dotted.
    func setPathLinePattern(ids: [UUID], _ pattern: PathLinePattern) {
        guard !ids.isEmpty else { return }
        discardDragPreview()
        perform { _ = $0.setPathLinePattern(layerIDs: ids, to: pattern) }
        rememberLines(of: ids)
    }

    /// Inside, centred on or outside the edge, on every picked closed path.
    func setPathStrokePosition(ids: [UUID], _ position: BorderPosition) {
        guard !ids.isEmpty else { return }
        discardDragPreview()
        perform { _ = $0.setPathStrokePosition(layerIDs: ids, to: position) }
        rememberLines(of: ids)
    }

    /// What the ends of a LINE or an ARROW look like. The same three answers
    /// and the same one step, on a shape the Pen did not draw.
    func setShapeLineEnd(ids: [UUID], _ end: PathLineEnd) {
        guard !ids.isEmpty else { return }
        discardDragPreview()
        perform { _ = $0.setShapeLineEnd(layerIDs: ids, to: end) }
        rememberLines(of: ids)
    }

    /// The next arrow, line or path of each picked kind is drawn with the
    /// line these were just given (`RememberedLooks`).
    private func rememberLines(of ids: [UUID]) {
        guard let document else { return }
        for id in ids {
            if let layer = document.layer(id: id) { rememberedLooks.rememberLine(of: layer) }
        }
        saveRememberedLooks()
    }

    /// What the three pickers read across the picked layers: the paths among
    /// them, and what they agree about.
    var pathLineStyleSelection: PathLineStyleSelection {
        guard let document else { return PathLineStyleSelection(members: [], selectionCount: 0) }
        return document.pathLineStyleSelection(layerIDs: colorStyleTargetIDs)
    }
}
