import Foundation
import PhotonzCore

// Saved strokes: keeping a path's line under a name, giving it to another path
// in one click, and re-setting every path wearing it at once (Next,
// `next-styles`, `PhotonzCore/SavedStrokes.swift`). The same shape as
// `EditorState+EffectStyles.swift`.
extension EditorState {

    /// The same switch the other saved styles are behind, because to a person
    /// they are one feature: a style is a name you can put on things.
    var savedStrokesEnabled: Bool { Experiments.shared.colorStylesEnabled }

    /// The strokes this document holds.
    var namedSavedStrokes: [SavedStroke] { document?.savedStrokes ?? [] }

    /// What a Style row reads over these layers: their own lines (paths and
    /// straight lines), or with `borderAt` the edge of each box and oval at
    /// that place in the Effects list.
    func savedStrokeSelection(ids: [UUID], borderAt index: Int? = nil) -> SavedStrokeSelection {
        document?.savedStrokeSelection(layerIDs: ids, borderAt: index)
            ?? SavedStrokeSelection(members: [], selectionCount: 0)
    }

    /// Save as Style: opens the name field on this row. One field at a time,
    /// wherever it was opened from.
    func beginNamingSavedStroke(rowID: String) {
        guard savedStrokesEnabled else { return }
        colorStyleNaming = nil
        isNamingTextStyle = false
        namingEffectStyleRow = nil
        namingSavedStrokeRow = rowID
    }

    /// Escape, or the name landing: the field closes.
    func endNamingSavedStroke() { namingSavedStrokeRow = nil }

    /// The name a stroke saved from these paths opens on.
    func suggestedSavedStrokeName(ids: [UUID]) -> String {
        document?.suggestedSavedStrokeName(for: ids) ?? ""
    }

    /// Saves the line these paths share and points them at it, then shows the
    /// Library on the Styles shelf, because a style you cannot see is a button
    /// that appears to do nothing. Nothing on the canvas changes.
    @discardableResult
    func saveStroke(ids: [UUID], name: String? = nil) -> UUID? {
        guard savedStrokesEnabled, !ids.isEmpty else { return nil }
        namingSavedStrokeRow = nil
        discardDragPreview()
        var saved: UUID?
        perform { saved = $0.saveStroke(from: ids, name: name) }
        guard let styleID = saved else { return nil }
        showStylesShelf()
        pendingLibraryTileID = styleID.uuidString
        return styleID
    }

    /// Gives every picked line a saved stroke in ONE step: a path all four
    /// values, a straight line its width and caps, and with `borderAt` the edge
    /// of a box or an oval its width and side.
    func useSavedStroke(ids: [UUID], styleID: UUID, borderAt index: Int? = nil) {
        guard savedStrokesEnabled, !ids.isEmpty else { return }
        stylePreview = nil
        discardDragPreview()
        perform { _ = $0.wearSavedStroke(layerIDs: ids, styleID: styleID, borderAt: index) }
    }

    /// Unlink: the line stays exactly as it is, it just becomes the layer's
    /// own again, in one step. Nothing on the canvas moves.
    func unlinkSavedStroke(ids: [UUID], borderAt index: Int? = nil) {
        guard savedStrokesEnabled, !ids.isEmpty else { return }
        perform(reportingLinkBreaks: false) { $0.unwearSavedStroke(layerIDs: ids, borderAt: index) }
    }

    /// A stroke's Width while its slider is held: every path wearing it moves
    /// on the canvas, and nothing is filed yet.
    func previewSavedStroke(styleID: UUID, look: StrokeLook) {
        guard savedStrokesEnabled, var doc = document else { return }
        stylePreview = nil
        discardDragPreview()
        doc.setSavedStroke(styleID: styleID, look: look)
        submit(doc)
    }

    /// Re-sets a stroke and every path wearing it, as ONE undo step however
    /// many glyphs it reached.
    func setSavedStroke(styleID: UUID, look: StrokeLook) {
        guard savedStrokesEnabled else { return }
        stylePreview = nil
        discardDragPreview()
        perform { _ = $0.setSavedStroke(styleID: styleID, look: look) }
    }

    /// The section's Name field. One name in one place: the shelf tile and
    /// every row wearing it read the same string.
    func renameSavedStroke(styleID: UUID, to name: String) {
        guard savedStrokesEnabled else { return }
        perform { $0.renameSavedStroke(id: styleID, to: name) }
    }

    /// Takes a stroke off the shelf. Every path keeps the line it is wearing.
    func deleteSavedStroke(styleID: UUID) {
        guard savedStrokesEnabled else { return }
        perform { $0.deleteSavedStroke(id: styleID) }
        if selectedLibraryItemID == styleID.uuidString { selectedLibraryItemID = nil }
    }

    /// How much of the document leans on a stroke.
    func savedStrokeUsageCount(styleID: UUID) -> Int {
        document?.savedStrokeUsageCount(id: styleID) ?? 0
    }

    /// Selects every path wearing a stroke, so "what would this change?" is a
    /// click rather than a hunt.
    func selectLayersUsingSavedStroke(styleID: UUID) {
        guard let ids = document?.layersUsingSavedStroke(id: styleID), !ids.isEmpty else { return }
        selectLayers(Set(ids))
    }

    /// What the Appearance header's question mark says over a line in an icon.
    var savedStrokeNote: String? {
        guard savedStrokesEnabled else { return nil }
        return document?.savedStrokeNote(for: colorStyleTargetIDs)
    }

    /// The stroke tile picked on the Library shelf, when that is what is
    /// picked.
    var selectedSavedStroke: SavedStroke? {
        guard savedStrokesEnabled, let raw = selectedLibraryItemID,
              let id = UUID(uuidString: raw) else { return nil }
        return document?.savedStroke(id: id)
    }

    /// The tiles the Styles shelf draws for strokes.
    var savedStrokeEntries: [LibraryEntry] {
        guard savedStrokesEnabled else { return [] }
        return document?.savedStrokeLibraryEntries ?? []
    }
}

// MARK: - The line the Pen's next path starts in

extension EditorState {

    /// The line the icon being worked in is using, as the Pen would take it
    /// (`IconLine.swift`), or nil with another tool in hand, off an icon, or
    /// where the icon has no line yet.
    private var penIconLine: IconLine? {
        guard activeTool == .pen, Experiments.shared.iconFramesEnabled else { return nil }
        return document?.iconLine(picked: selectedLayerID, pointerIn: pointerIconFrameID)
    }

    /// What the tool bar's swatch reads with the Pen in hand on an icon, so the
    /// colour it shows is the colour that lands. Nil where the armed ink is the
    /// answer, which includes a colour somebody just picked on it.
    var penInkFromIcon: Paint? { penKeepsOwnInk ? nil : penIconLine?.paint }

    /// ...and what the Width row reads, for the same reason.
    var penWidthFromIcon: CGFloat? { penKeepsOwnWidth ? nil : penIconLine?.look.width }
}
