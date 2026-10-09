import Foundation
import PhotonzCore

// MARK: - Center on the Artboard, Union, Outline Stroke (Next flag `next-icon-shape-commands`)

extension EditorState {

    /// Whether the three are offered here at all. Pictures and icons only,
    /// like Mirror Across Center beside them: on a video a layer's place is
    /// its movement over time, and moving or remaking it in one go would
    /// leave that movement behind.
    var offersIconShapeCommands: Bool {
        Experiments.shared.iconShapeCommandsEnabled && !documentHasTime
    }

    /// Union and Outline Stroke both hand back a path, so they ride on the
    /// Pen's flag as Combine Shapes does: a path you cannot reshape is a
    /// command with no payoff.
    var offersPathRemaking: Bool {
        offersIconShapeCommands && Experiments.shared.penEnabled
    }

    // MARK: Center on the Artboard

    /// Whether Layer ▸ Center on the Artboard would move what is picked.
    var canCenterSelectionOnArtboard: Bool { canCenter(ids: actionableLayerIDs) }

    /// Whether the right-click menu's row has something to move: the whole
    /// selection when the clicked layer is in it, else that layer alone.
    func canCenterRowOnArtboard(id: UUID) -> Bool { canCenter(ids: rowMenuTargets(id)) }

    /// Layer ▸ Center on the Artboard: moves what is picked, as one piece,
    /// onto the middle of its frame, in one undo step. The selection stays,
    /// so the next nudge lands on what just moved.
    func centerSelectionOnArtboard() { center(ids: actionableLayerIDs) }

    /// The right-click menu's Center on the Artboard.
    func centerRowOnArtboard(id: UUID) { center(ids: rowMenuTargets(id)) }

    private func canCenter(ids: Set<UUID>) -> Bool {
        guard offersIconShapeCommands, let document else { return false }
        return document.canCenterOnArtboard(ids: ids)
    }

    private func center(ids: Set<UUID>) {
        guard canCenter(ids: ids) else { return }
        discardDragPreview()
        perform { $0.centerOnArtboard(ids: ids) }
    }

    // MARK: Union

    /// Whether Layer ▸ Union has two shapes with an inside to join.
    var canUnionSelection: Bool { canUnion(ids: actionableLayerIDs) }

    /// Whether the right-click menu's Union has two shapes to join.
    func canUnionRow(id: UUID) -> Bool { canUnion(ids: rowMenuTargets(id)) }

    /// Layer ▸ Union (⌥⌘U): Combine Shapes ▸ Join under the name the icon
    /// mock and every other drawing program give it.
    func unionSelection() {
        guard canUnionSelection else { return }
        combineSelection(.join)
    }

    /// The right-click menu's Union.
    func unionRow(id: UUID) {
        guard canUnionRow(id: id) else { return }
        combineLayers(id: id, .join)
    }

    private func canUnion(ids: Set<UUID>) -> Bool {
        guard offersPathRemaking, let document else { return false }
        return document.combinableLayers(ids: ids).count >= 2
    }

    // MARK: Outline Stroke

    /// Whether Layer ▸ Outline Stroke has a line to turn into a shape.
    var canOutlineSelectionStroke: Bool { canOutline(ids: actionableLayerIDs) }

    /// Whether the right-click menu's Outline Stroke has a line to turn.
    func canOutlineRowStroke(id: UUID) -> Bool { canOutline(ids: rowMenuTargets(id)) }

    /// Layer ▸ Outline Stroke (⇧⌘O): every picked line becomes a filled
    /// shape, in one undo step, and the outlines are picked, so their points
    /// are on them and the panel shows the fill they now wear.
    func outlineSelectionStroke() { outline(ids: actionableLayerIDs) }

    /// The right-click menu's Outline Stroke.
    func outlineRowStroke(id: UUID) { outline(ids: rowMenuTargets(id)) }

    private func canOutline(ids: Set<UUID>) -> Bool {
        guard offersPathRemaking, let document else { return false }
        return document.canOutlineStroke(ids: ids)
    }

    private func outline(ids: Set<UUID>) {
        guard canOutline(ids: ids) else { return }
        discardDragPreview()
        var made: [UUID] = []
        perform { made = $0.outlineStroke(ids: ids) }
        guard !made.isEmpty else { return }
        selectLayers(Set(made))
    }
}
