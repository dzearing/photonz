import CoreGraphics
import Foundation
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI

// Named text styles: saving what a piece of text is set in under a name,
// wearing it on other text, and editing every piece of text wearing it at once
// (Next, `next-styles`). The colour half of the same shelf is
// `EditorState+ColorStyles.swift`.
//
// Everything here goes through one rule the colour styles do not have to think
// about: setting text re-measures its box, and measuring words needs CoreText.
// So every route that changes type works out the new boxes FIRST, outside the
// mutation, and applies them inside the same step.
extension EditorState {

    /// Whether text can be saved under a name at all. The same switch the saved
    /// colours are behind, because to a person they are one feature: a style is
    /// a name you can put on things.
    var textStylesEnabled: Bool { Experiments.shared.colorStylesEnabled }

    /// The named text treatments this document holds. Named for what they are
    /// rather than `textStyles`, which is already taken by the tool's own
    /// current settings — what the NEXT block of text will be typed in.
    var namedTextStyles: [TextStyle] { document?.textStyles ?? [] }

    /// What the Style row in the Text section shows, and what a pick in it
    /// re-sets.
    var textStyleSelection: TextStyleSelection {
        guard let document else { return TextStyleSelection(members: [], selectionCount: 0) }
        return document.textStyleSelection(layerIDs: colorStyleTargetIDs)
    }

    /// The style the picked text wears, when they all wear one.
    var boundTextStyle: TextStyle? {
        textStyleSelection.boundStyleID.flatMap { id in namedTextStyles.first { $0.id == id } }
    }

    /// The name a fresh style opens on: one nobody is using yet, so naming it
    /// is typing and Return is enough.
    var suggestedTextStyleName: String {
        document?.freshTextStyleName() ?? PhotonzDocument.textStyleNameBase
    }

    /// Save as Style on the Style row: opens the name field under it. One field
    /// at a time, wherever it was opened from.
    func beginNamingTextStyle() {
        guard textStylesEnabled else { return }
        colorStyleNaming = nil
        isNamingTextStyle = true
    }

    /// Escape, or the name landing: the field closes.
    func endNamingTextStyle() {
        isNamingTextStyle = false
    }

    /// Saves what the picked text is set in under a name and dresses all of it
    /// in the new style, then **shows the Library on the Styles shelf**, because
    /// a style you cannot see is a button that appears to do nothing.
    ///
    /// Nothing is re-measured: the type does not change, only where it says it
    /// came from.
    @discardableResult
    func saveTextStyle(name: String? = nil) -> UUID? {
        guard textStylesEnabled else { return nil }
        isNamingTextStyle = false
        let targets = textStyleSelection.layerIDs
        guard !targets.isEmpty else { return nil }
        discardDragPreview()
        var saved: UUID?
        perform { saved = $0.saveTextStyle(from: targets, name: name) }
        guard let styleID = saved else { return nil }
        showStylesShelf()
        pendingLibraryTileID = styleID.uuidString
        return styleID
    }

    /// Dresses every picked piece of text in a style, in ONE step: pick three
    /// headings, choose Heading once, undo once.
    func useTextStyle(styleID: UUID) {
        guard textStylesEnabled, let style = document?.textStyle(id: styleID) else { return }
        let targets = textStyleSelection.layerIDs
        guard !targets.isEmpty else { return }
        discardDragPreview()
        let sizes = restyledTextSizes(ids: targets, treatment: style.treatment)
        perform { document in
            _ = document.bindTextStyle(layerIDs: targets, styleID: styleID)
            document.applyTextBoxes(sizes)
        }
        // The next block typed comes out in what you just chose, the same way
        // picking a size on the row above arms the next block with it.
        rememberTextStyleDefaults(style.treatment)
    }

    /// Dresses the text a style was let go of on, in ONE step: drop, undo once,
    /// and it is back exactly as it was.
    ///
    /// It names its own text rather than reading the selection, because a drop
    /// is aimed: the pointer said which words, and they are often words nobody
    /// has picked. For the same reason it does NOT arm the text tool with the
    /// style the way choosing a name from the Style row does — that row speaks
    /// for text you have selected and are working on, while this lands on text
    /// you may never have touched, and quietly changing what the next block
    /// comes out in would be a side effect nobody asked for.
    func dropTextStyle(styleID: UUID, onLayers ids: [UUID]) {
        guard textStylesEnabled, !ids.isEmpty,
              let style = document?.textStyle(id: styleID) else { return }
        discardDragPreview()
        let sizes = restyledTextSizes(ids: ids, treatment: style.treatment)
        perform { document in
            _ = document.bindTextStyle(layerIDs: ids, styleID: styleID)
            document.applyTextBoxes(sizes)
        }
    }

    /// Unlink: the text stays exactly as it is, it just becomes its own again,
    /// in one step. Nothing moves, so there is nothing to re-measure.
    func unlinkTextStyle() {
        guard textStylesEnabled else { return }
        let targets = textStyleSelection.layerIDs
        guard !targets.isEmpty else { return }
        perform(reportingLinkBreaks: false) { $0.unbindTextStyle(layerIDs: targets) }
    }

    /// Re-sets a style and every piece of text wearing it, as one undo step.
    ///
    /// This is where the re-measure earns its place: a heading grown from 24pt
    /// to 48pt in a box measured for 24 would clip, so every box wearing the
    /// style is measured at the new type before the step and set inside it.
    func setTextStyle(styleID: UUID, treatment: TextTreatment) {
        guard textStylesEnabled, let document else { return }
        guard document.textStyle(id: styleID)?.treatment != treatment else { return }
        discardDragPreview()
        let targets = document.layersUsingTextStyle(id: styleID)
        let sizes = restyledTextSizes(ids: targets, treatment: treatment)
        perform { document in
            _ = document.setTextStyle(styleID: styleID, treatment: treatment)
            document.applyTextBoxes(sizes)
        }
        recordRecentColor(hex: treatment.colorHex)
    }

    /// The Style section's Name field. One name in one place: the shelf tile and
    /// every row wearing it read the same string.
    func renameTextStyle(styleID: UUID, to name: String) {
        guard textStylesEnabled else { return }
        perform { $0.renameTextStyle(id: styleID, to: name) }
    }

    /// Takes a style off the shelf. Nothing is re-set: every piece of text keeps
    /// the type it is wearing and simply owns it again.
    func deleteTextStyle(styleID: UUID) {
        guard textStylesEnabled else { return }
        perform { $0.deleteTextStyle(id: styleID) }
        if selectedLibraryItemID == styleID.uuidString { selectedLibraryItemID = nil }
    }

    /// How much of the document leans on a style, which is the question a shelf
    /// full of them raises.
    func textStyleUsageCount(styleID: UUID) -> Int {
        document?.textStyleUsageCount(id: styleID) ?? 0
    }

    /// Selects every piece of text wearing a style, so "what would this change?"
    /// is a click rather than a hunt.
    func selectLayersUsingTextStyle(styleID: UUID) {
        guard let ids = document?.layersUsingTextStyle(id: styleID), !ids.isEmpty else { return }
        selectLayers(Set(ids))
    }

    /// The style tile picked on the Library shelf, when the picked tile is a
    /// text style rather than a colour.
    var selectedTextStyle: TextStyle? {
        guard textStylesEnabled, let raw = selectedLibraryItemID,
              let id = UUID(uuidString: raw) else { return nil }
        return document?.textStyle(id: id)
    }

    /// The tiles the Styles shelf draws for text, beside the saved colours.
    var textStyleEntries: [LibraryEntry] {
        guard textStylesEnabled else { return [] }
        return document?.textStyleLibraryEntries ?? []
    }

    // MARK: - Measuring the boxes

    /// The box each of these layers lands in once it is set in this treatment.
    ///
    /// The same rule `setTextStyle(ids:…)` uses for a hand edit, so type
    /// arriving from a name and type chosen from the Font menu re-wrap
    /// identically: a box somebody made bigger than its words keeps the room it
    /// was given, and a box still hugging its words re-hugs them.
    private func restyledTextSizes(ids: [UUID],
                                   treatment: TextTreatment) -> [UUID: CGSize] {
        let hugsShortWords = Experiments.shared.placementEnabled
        return ids.reduce(into: [:]) { sizes, id in
            guard let layer = document?.layer(id: id), let was = layer.text else { return }
            let restyled = TextBuilder.restyled(layer: layer, fontName: treatment.fontName,
                                                fontSize: treatment.fontSize,
                                                weight: treatment.weight,
                                                colorHex: treatment.colorHex)
            guard let words = restyled.text else { return }
            guard hugsShortWords else {
                sizes[id] = TextRasterizer.naturalSize(words, maxWidth: layer.frame.width,
                                                       minWidth: TextRasterizer.minimumTextWidth)
                return
            }
            let room = TextBlockMetrics.roomyBox(for: was, frame: layer.frame)
            sizes[id] = TextBlockMetrics.frameSize(for: words, maxWidth: .greatestFiniteMagnitude,
                                                   roomyWidth: room.width,
                                                   roomyHeight: room.height,
                                                   hugsShortWords: true)
        }
    }

    /// What the next block of text starts at, so choosing a name on this row
    /// carries over the way choosing a size on the row above it does.
    private func rememberTextStyleDefaults(_ treatment: TextTreatment) {
        textStyles.fontName = treatment.fontName
        textStyles.fontSize = treatment.fontSize
        textStyles.weight = treatment.weight
        textStyles.colorHex = treatment.colorHex
        saveTextStyles()
        recordRecentColor(hex: treatment.colorHex)
    }
}

extension PhotonzDocument {

    /// Sets the boxes worked out before the step. Only the size: where a text
    /// box SITS is nobody's business but the person who put it there.
    mutating func applyTextBoxes(_ sizes: [UUID: CGSize]) {
        for (id, size) in sizes {
            updateLayer(id: id) { $0.frame = CGRect(origin: $0.frame.origin, size: size) }
        }
    }
}
