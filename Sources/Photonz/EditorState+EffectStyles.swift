import CoreGraphics
import Foundation
import Observation
import PhotonzCore
import SwiftUI

// Named effects: saving a shadow, a glow, a border or a blur you have tuned
// under a name, putting it on other layers, and re-setting every layer wearing
// it at once (Next, `next-styles`). The colour half of the same shelf is
// `EditorState+ColorStyles.swift` and the text half is
// `EditorState+TextStyles.swift`.
//
// It is deliberately the same shape as the text one, with one difference that
// runs through everything here: an effect sits at a PLACE in a list, so nearly
// every call carries the row it is about (`EffectStyles.swift` says why the
// binding names the place).
extension EditorState {

    /// Whether an effect can be saved under a name at all. The same switch the
    /// saved colours and text styles are behind, because to a person they are
    /// one feature: a style is a name you can put on things.
    var effectStylesEnabled: Bool { Experiments.shared.colorStylesEnabled }

    /// The named effects this document holds.
    var namedEffectStyles: [EffectStyle] { document?.effectStyles ?? [] }

    /// The saved effects a given row may wear: only the ones of its own kind,
    /// so a row titled Shadow can never quietly become a border. Adding an
    /// effect of another kind is what the plus on the header is for.
    func effectStyles(for kind: EffectKind) -> [EffectStyle] {
        namedEffectStyles.filter { $0.kind == kind }
    }

    /// What the Style row inside one effect shows, and what a pick in it
    /// re-sets.
    func effectStyleSelection(row: LayerEffectRow) -> EffectStyleSelection {
        guard let document else { return EffectStyleSelection(members: [], selectionCount: 0) }
        return document.effectStyleSelection(layerIDs: colorStyleTargetIDs,
                                             at: row.index, kind: row.kind)
    }

    /// The style the picked layers' effect wears, when they all wear one.
    func boundEffectStyle(row: LayerEffectRow) -> EffectStyle? {
        effectStyleSelection(row: row).boundStyleID
            .flatMap { id in namedEffectStyles.first { $0.id == id } }
    }

    /// The name a fresh style opens on: one nobody is using yet, so naming it
    /// is typing and Return is enough.
    func suggestedEffectStyleName(kind: EffectKind) -> String {
        let base = PhotonzDocument.effectStyleNameBase(for: kind)
        return document?.freshEffectStyleName(base: base) ?? base
    }

    /// Save as Style on an effect's Style row: opens the name field under it.
    /// One field at a time, wherever it was opened from.
    func beginNamingEffectStyle(row: LayerEffectRow) {
        guard effectStylesEnabled else { return }
        colorStyleNaming = nil
        isNamingTextStyle = false
        namingEffectStyleRow = row.id
    }

    /// Escape, or the name landing: the field closes.
    func endNamingEffectStyle() {
        namingEffectStyleRow = nil
    }

    /// Whether this row's name field is the one open right now.
    func isNamingEffectStyle(row: LayerEffectRow) -> Bool {
        namingEffectStyleRow == row.id
    }

    /// Saves the effect on this row under a name and points every layer the row
    /// reaches at it, then **shows the Library on the Styles shelf**, because a
    /// style you cannot see is a button that appears to do nothing.
    ///
    /// Nothing on the canvas changes: the effect is exactly what it was, it
    /// just says where it came from now.
    @discardableResult
    func saveEffectStyle(row: LayerEffectRow, name: String? = nil) -> UUID? {
        guard effectStylesEnabled else { return nil }
        namingEffectStyleRow = nil
        let targets = effectStyleSelection(row: row).layerIDs
        guard !targets.isEmpty else { return nil }
        discardDragPreview()
        var saved: UUID?
        perform { saved = $0.saveEffectStyle(from: targets, at: row.index, name: name) }
        guard let styleID = saved else { return nil }
        showStylesShelf()
        pendingLibraryTileID = styleID.uuidString
        return styleID
    }

    /// Points this row's effect at a saved name, on every layer the row
    /// reaches, in ONE step: pick three cards, choose Card lift once, undo once.
    func useEffectStyle(row: LayerEffectRow, styleID: UUID) {
        guard effectStylesEnabled else { return }
        let targets = effectStyleSelection(row: row).layerIDs
        guard !targets.isEmpty else { return }
        stylePreview = nil
        discardDragPreview()
        perform { _ = $0.bindEffectStyle(layerIDs: targets, at: row.index, styleID: styleID) }
    }

    /// The plus on the Effects header with a saved name chosen: every picked
    /// layer gains that effect, wearing the name.
    ///
    /// This is the route by which a name reaches a layer that has nothing like
    /// it yet, which is why it lives on the plus rather than on a row: a row's
    /// own menu can only reach layers that already hold that effect there.
    func addEffectStyle(styleID: UUID) {
        guard effectStylesEnabled else { return }
        let ids = layerStyleSelection.layerIDs
        guard !ids.isEmpty else { return }
        stylePreview = nil
        discardDragPreview()
        // The rows below the new one are about to shift a place, and a fold is
        // known by its place (`foldedEffectRows`).
        forgetEffectFolds()
        perform { _ = $0.useEffectStyle(layerIDs: ids, styleID: styleID) }
    }

    /// Unlink: the effect stays exactly as it is, it just becomes the layer's
    /// own again, in one step. Nothing on the canvas moves.
    func unlinkEffectStyle(row: LayerEffectRow) {
        guard effectStylesEnabled else { return }
        let targets = effectStyleSelection(row: row).layerIDs
        guard !targets.isEmpty else { return }
        perform(reportingLinkBreaks: false) {
            $0.unbindEffectStyle(layerIDs: targets, at: row.index)
        }
    }

    /// Re-sets a style and every effect wearing it, as one undo step.
    func setEffectStyle(styleID: UUID, effect: LayerEffect) {
        guard effectStylesEnabled, let document else { return }
        guard document.effectStyle(id: styleID)?.effect != effect else { return }
        discardDragPreview()
        perform { _ = $0.setEffectStyle(styleID: styleID, effect: effect) }
        if let hex = effect.colorHex { recordRecentColor(hex: hex) }
    }

    /// The Style section's Name field. One name in one place: the shelf tile and
    /// every row wearing it read the same string.
    func renameEffectStyle(styleID: UUID, to name: String) {
        guard effectStylesEnabled else { return }
        perform { $0.renameEffectStyle(id: styleID, to: name) }
    }

    /// Takes a style off the shelf. Nothing is re-set: every layer keeps the
    /// effect it is wearing and simply owns it again.
    func deleteEffectStyle(styleID: UUID) {
        guard effectStylesEnabled else { return }
        perform { $0.deleteEffectStyle(id: styleID) }
        if selectedLibraryItemID == styleID.uuidString { selectedLibraryItemID = nil }
    }

    /// How much of the document leans on a style, which is the question a shelf
    /// full of them raises.
    func effectStyleUsageCount(styleID: UUID) -> Int {
        document?.effectStyleUsageCount(id: styleID) ?? 0
    }

    /// Selects every layer wearing a style, so "what would this change?" is a
    /// click rather than a hunt.
    func selectLayersUsingEffectStyle(styleID: UUID) {
        guard let ids = document?.layersUsingEffectStyle(id: styleID), !ids.isEmpty else { return }
        selectLayers(Set(ids))
    }

    /// The style tile picked on the Library shelf, when the picked tile is an
    /// effect rather than a colour or a text style.
    var selectedEffectStyle: EffectStyle? {
        guard effectStylesEnabled, let raw = selectedLibraryItemID,
              let id = UUID(uuidString: raw) else { return nil }
        return document?.effectStyle(id: id)
    }

    /// The tiles the Styles shelf draws for effects, beside the saved colours
    /// and text styles.
    var effectStyleEntries: [LibraryEntry] {
        guard effectStylesEnabled else { return [] }
        return document?.effectStyleLibraryEntries ?? []
    }
}
