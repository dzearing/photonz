// Which layers a control in the right hand panel edits, NAMED rather than listed, so a control the panel left alone still edits what is picked now.

import PhotonzCore
import SwiftUI

/// What a control in the right hand panel reaches, said as a NAME rather than
/// as a list of layers.
///
/// This is what lets the panel leave a control alone. A slider that was handed
/// `[arrow A]` is a different slider the moment arrow B is picked, even when
/// both arrows are 4 points thick and the knob does not move, so every control
/// in Appearance was rebuilt on every click: about two frames of work for a
/// panel that ends up looking exactly the same (measured 2026-09-17, the
/// comment above `arrivals` in `InspectorPanel.swift`).
///
/// A control handed "the Thickness under the Outline row" instead is the SAME
/// control across that click as long as the number on it has not changed, so
/// SwiftUI can skip it — and skipping is safe, because the control looks up
/// which layers that name reaches at the moment somebody uses it rather than
/// remembering the ones that happened to be picked when it was drawn.
///
/// `fixed` is the way out for the rows where the layers really are the answer:
/// a saved effect's own row edits the layers it was built for and nothing else.
/// It compares by those layers, so those rows behave exactly as they always
/// have.
enum PanelReach: Hashable, Sendable {
    /// These layers and no others. Changes with the selection, which is
    /// correct wherever the row is ABOUT a particular set of layers.
    case fixed([UUID])
    /// Every picked layer that carries a style: what Opacity, Blur and the
    /// rest of the whole-selection rows reach.
    case layerStyle
    /// The layers the part row with this id speaks for — the Fill row's fills,
    /// the Outline row's outlines, the Head row's arrows.
    case partRow(String)
    /// ...and of those, the ones that have a line with a weight of its own.
    case partThickness(String)
    /// ...the ones that are paths the Pen drew, whose pattern, ends and
    /// corners are all choosable.
    case partPathLine(String)
    /// ...the ones that are shapes, which is what the single Ends row over a
    /// line or an arrow reaches.
    case partShapes(String)
    /// The one picked arrow whose label the Caption block edits.
    case captionArrow
}

extension EditorState {
    /// The layers a named reach reaches RIGHT NOW. Every control that was
    /// drawn for an earlier selection asks this before it changes anything, so
    /// a control the panel skipped is behaviourally identical to one it rebuilt.
    func layerIDs(reaching reach: PanelReach) -> [UUID] {
        switch reach {
        case .fixed(let ids): return ids
        case .layerStyle: return layerStyleSelection.layerIDs
        case .partRow(let id): return partRowReach(rowID: id)
        case .partThickness(let id):
            return outlineThicknessSelection.of(partRowReach(rowID: id)).layerIDs
        case .partPathLine(let id):
            return pathLineStyleSelection.of(partRowReach(rowID: id)).layerIDs
        case .partShapes(let id):
            let wanted = Set(partRowReach(rowID: id))
            return shapeSelection.members.map(\.id).filter { wanted.contains($0) }
        case .captionArrow:
            let selection = shapeSelection
            guard selection.count == 1, let only = selection.members.first,
                  only.content.shape == .arrow else { return [] }
            return [only.id]
        }
    }

    /// The picked layers ONE part row speaks for, which is not always the whole
    /// selection: pick an arrow and a box together and the Line row reaches the
    /// arrow alone.
    func partRowReach(_ row: LayerPartRow) -> [UUID] {
        // The Head row over an arrow that ends in nothing has no colour and so
        // no layers named on one, but its Ending picker still has to reach that
        // arrow: it is the control that gives it an ending back.
        if let ids = row.colors.first?.layerIDs, !ids.isEmpty { return ids }
        guard row.part == .arrowHead else { return [] }
        return shapeSelection.members.filter { $0.content.shape == .arrow }.map(\.id)
    }

    /// The same, looked up by the row's id, which is the part of a row that
    /// outlives a change of selection (`LayerPartRow.id`).
    func partRowReach(rowID: String) -> [UUID] {
        guard let row = layerPartRows.first(where: { $0.id == rowID }) else { return [] }
        return partRowReach(row)
    }
}
