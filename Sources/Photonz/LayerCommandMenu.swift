// The commands that act on a layer, in the order a menu shows them.
//
// ONE list, shown in two places: the row in the layers list, and the layer
// itself on the picture. They were never allowed to disagree — the same command
// under two names, or with two shortcuts printed against it, is one feature
// learned twice — so the list is written here as plain rows (`MenuRow`) and the
// two surfaces only draw it.
//
// What it acts on is decided before it opens, not in here: a row menu reads
// `EditorState.rowMenuTargets`, and the canvas reads `CanvasMenuAim`, which is
// the same rule plus "a right click picks what you point at". By the time these
// rows are built, "this layer" means the same thing either way.
//
// A command a layer cannot take is ABSENT, not dimmed: the menu should never
// carry a dead row whose reason has to be hunted for. The exceptions are the
// two rows whose reason is IN the menu — Paste Look with nothing copied, and
// Delete on a locked layer with the Locked toggle directly above it.

import AppKit
import PhotonzCore
import SwiftUI

enum LayerCommandList {

    /// Every row the menu about `display` should carry.
    ///
    /// `beginRename` is nil where there is nowhere to type: the name is edited
    /// in place in the layers list, so the list passes its own field and the
    /// canvas passes nothing rather than offering a row that does nothing.
    @MainActor
    static func rows(for display: LayerRowDisplay,
                     offersMakeComponent: Bool,
                     offersDetachInstance: Bool,
                     beginRename: ((UUID, String) -> Void)?,
                     editorState: EditorState) -> [MenuRow] {
        let id = display.id
        var rows: [MenuRow] = []

        rows.append(.command("Duplicate", .command("d")) { editorState.duplicateLayer(id: id) })
        // Where Photoshop keeps them, under the names it uses for the same
        // pair, so the two moves that make one shape match another are one
        // right click away (`EditorState+Look.swift`).
        if Experiments.shared.copyALookEnabled {
            rows.append(.command("Copy Look") { editorState.copyLookOfRow(id: id) })
            rows.append(.command("Paste Look",
                                 enabled: editorState.canPasteLookOntoRow(id: id)) {
                editorState.pasteLookOntoRow(id: id)
            })
        }
        rows.append(.command("Select Pixels") { editorState.selectLayerPixels(id: id) })
        rows.append(.command("Merge Down", .command("e")) { editorState.mergeDown(id: id) })
        // Before "Turn Into Picture", because it is the gentler of the two: one
        // keeps the shape editable and takes away only its being a rectangle,
        // the other makes it pixels. A row that cannot take it does not show it
        // (`ShapeToPath.swift`). Not gated on THIS layer having an outline:
        // with three picked the command acts on all of them, so a picture right
        // clicked alongside two lines still offers it and leaves the picture
        // alone.
        // The row says what it will do to THIS selection: Turn Into Path while
        // something still has to be turned, Join Paths over two outlines
        // already drawn with the Pen, Close Path over one of them on its own
        // (`EditorState+LayerOps.turnIntoPathMenuItem`).
        if editorState.canTurnLayerIntoPath(id: id) {
            rows.append(.command(editorState.turnIntoPathMenuItem(id: id)) {
                editorState.turnLayerIntoPath(id: id)
            })
        }
        // The four ways two shapes become one, on the menu where every other
        // command about a layer already lives (`PathCombining.swift`). Absent
        // rather than dimmed when there are not two shapes to combine.
        if editorState.canCombineLayers(id: id) {
            rows.append(.submenu(PathCombine.menuItem,
                                 PathCombine.Operation.allCases.map { operation in
                                     .command(operation.title) {
                                         editorState.combineLayers(id: id, operation)
                                     }
                                 }))
        }
        // Not gated on THIS layer being a shape, for the same reason Turn Into
        // Path is not: with three picked the command acts on all of them, so a
        // picture right clicked alongside two rectangles still offers it and
        // leaves the picture alone.
        if editorState.canRasterizeLayer(id: id) {
            rows.append(.command(RasterizePrompt.menuItem) { editorState.rasterizeLayer(id: id) })
        }
        // On a PICTURE, including the locked Background, which is what a person
        // actually right clicks when they want a screenshot taken apart (Next,
        // `next-separate-into-layers`).
        if editorState.canSeparateIntoLayers(id: id) {
            rows.append(.command("Separate into Layers") { editorState.separateIntoLayers(id: id) })
            // Directly under it, because it is the next thing you want on the
            // layers Separate just made: the run is on its own layer, and now
            // the words in it become words you can retype.
            // On the whole selection when the row you right clicked is part of
            // it, like every other row of this menu (`rowMenuTargets`): picking
            // five labels and asking for the words must not hand back one.
            rows.append(.command("Turn into Text") { editorState.turnIntoTextForRow(id: id) })
        }
        rows.append(.separator)
        // Group and Ungroup, on Photoshop's keys, directly above the arrange
        // commands so the structure commands sit together, which is the order
        // the Layer menu already uses. They act on the whole selection when the
        // layer you right clicked is part of it, so picking three and right
        // clicking one of them makes one group of the three; on something
        // outside the selection there is nothing to group, and a row that
        // cannot act is absent rather than dimmed.
        if editorState.canGroupRow(id: id) {
            rows.append(.command("Group", .command("g")) { editorState.groupRow(id: id) })
        }
        if editorState.canUngroupRow(id: id) {
            rows.append(.command("Ungroup", .commandShift("g")) { editorState.ungroupRow(id: id) })
        }
        rows.append(.command("Bring to Front", .commandShift("]")) { editorState.bringLayerToFront(id: id) })
        rows.append(.command("Bring Forward", .command("]")) { editorState.bringLayerForward(id: id) })
        rows.append(.command("Send Backward", .command("[")) { editorState.sendLayerBackward(id: id) })
        rows.append(.command("Send to Back", .commandShift("[")) { editorState.sendLayerToBack(id: id) })
        // Only where it IS out of view, which is the only place it would do
        // anything. Same move as the mark on the row, named, for anybody who
        // goes to the menu before they go to a small orange glyph.
        if display.outOfView?.canReturn == true {
            rows.append(.separator)
            rows.append(.command("Bring into View") { editorState.bringLayerIntoView(id: id) })
        } else if let container = display.outOfView?.container,
                  display.outOfView?.growsContainer != nil {
            // It names the container because that is the thing that changes.
            rows.append(.separator)
            rows.append(.command("Make \(container) Fit") { editorState.makeRoomForLayer(id: id) })
        }
        rows.append(.separator)
        // The user's own suggestion for where these went: right click the layer
        // and ask for the numbers (`ExactPlacement`). It acts on the whole
        // selection when what you right clicked is part of it, like everything
        // else in this menu.
        if Experiments.shared.geometryFieldsEnabled {
            rows.append(.command(ExactPlacement.menuItem) {
                if !display.isSelected {
                    editorState.clickRow(id, .plain, in: editorState.panelRows.map(\.id))
                }
                editorState.openExactPlacement()
            })
        }
        rows.append(.separator)
        if let beginRename {
            rows.append(.command("Rename") { beginRename(id, display.name) })
        }
        if offersMakeComponent {
            rows.append(.command("Make Component", .commandOption("k")) { editorState.makeComponent() })
        }
        if offersDetachInstance {
            rows.append(.command("Detach Instance", .commandOption("b")) { editorState.detachInstance() })
        }
        // Only on an original, and only when it would work: a row that means
        // nothing on the layer you right clicked is a row people hunt the
        // reason for.
        if display.isMainComponent, editorState.canAddComponentVersion {
            rows.append(.command(editorState.selectedComponentVariantWording.addCommand) {
                editorState.addComponentVersion()
            })
        }
        // Only on a piece of an original that has other looks, and it names
        // them, so the row answers "what would this touch" before it is
        // pressed. Same rule as the Layer menu.
        if let title = editorState.applyToOtherComponentVersionsTitle {
            rows.append(.command(title, enabled: editorState.canApplyToOtherComponentVersions) {
                editorState.applyToOtherComponentVersions()
            })
        }
        // Settings, not actions: the row says what it IS and wears a checkmark,
        // so the menu reads the same whichever state the layer is in and the
        // Delete below it never shifts under the pointer (MenuToggleNames).
        rows.append(.toggle(MenuToggleNames.layerVisible, isOn: display.isVisible) {
            editorState.toggleLayerVisibility(id: id)
        })
        rows.append(.toggle(MenuToggleNames.layerLocked, isOn: display.isLocked) {
            editorState.toggleLayerLock(id: id)
        })
        rows.append(.separator)
        // Dimmed on a locked layer, with the Locked toggle right above it: the
        // way out of the greyed row is the line you just read.
        rows.append(.command("Delete", .commandDelete,
                             enabled: !display.isLocked, destructive: true) {
            editorState.deleteLayer(id: id)
        })
        return rows
    }
}

/// The layers list's own row menu, drawn by SwiftUI from the list above.
struct LayerCommandMenu: View {
    let display: LayerRowDisplay
    /// The two component rows, already decided by the list: both need the layer
    /// to be part of the selection, because they act on the selection.
    let offersMakeComponent: Bool
    let offersDetachInstance: Bool
    let beginRename: ((UUID, String) -> Void)?
    let editorState: EditorState

    var body: some View {
        MenuRowsView(rows: LayerCommandList.rows(for: display,
                                                 offersMakeComponent: offersMakeComponent,
                                                 offersDetachInstance: offersDetachInstance,
                                                 beginRename: beginRename,
                                                 editorState: editorState))
    }
}
