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

    /// Paints the line of every picked path with a brush, or gives it back its
    /// plain line with nil (`PathBrush.swift`). A brush picked here starts as
    /// that medium was last left in the Brush tool, so a charcoal tuned there
    /// is the charcoal a line gets. One choice, one undo step.
    func setPathBrush(ids: [UUID], _ medium: BrushMedium?) {
        guard !ids.isEmpty else { return }
        discardDragPreview()
        let brush = medium.map { annotationStyles.brush(for: $0) }
        perform { _ = $0.setPathBrush(layerIDs: ids, to: brush) }
    }

    /// One of the line's brush settings while its slider is held: shown on
    /// the canvas, filed nowhere yet.
    func previewPathBrushSetting(ids: [UUID], _ settingID: String, _ value: Double) {
        guard var doc = document, !ids.isEmpty else { return }
        stylePreview = nil
        discardDragPreview()
        guard doc.setPathBrushSetting(layerIDs: ids, id: settingID, to: value) > 0 else { return }
        submit(doc)
    }

    /// ...and let go: ONE undo step however many lines it reached.
    func commitPathBrushSetting(ids: [UUID], _ settingID: String, _ value: Double) {
        guard !ids.isEmpty else { return }
        stylePreview = nil
        discardDragPreview()
        perform { _ = $0.setPathBrushSetting(layerIDs: ids, id: settingID, to: value) }
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
