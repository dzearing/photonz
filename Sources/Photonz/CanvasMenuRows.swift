// What a right click on the picture offers (`next-canvas-menu`).
//
// Two menus in one, chosen by what the pointer was over when the click landed
// (`CanvasMenuAim`):
//
// - Over a layer: the layer's own commands, which are literally the layers
//   list's rows (`LayerCommandList`). Same names, same order, same shortcuts
//   printed — one list drawn twice, because the same command in two places
//   under two names is one feature learned twice.
// - Over bare picture: what belongs to the picture as a whole. Never an empty
//   menu, and never a menu about a layer that is not there.
//
// Rename is the one row of the layer menu the canvas leaves out, and it is
// deliberate: the name is typed into the row itself in the layers list, so with
// the dock shut there would be nowhere for the field to appear and the row
// would do nothing. Everything else carries across.

import AppKit
import PhotonzCore

extension EditorState {

    /// The rows for the menu the last right click on the picture asked for.
    /// Read at the moment the menu is built, so it is about where the pointer
    /// was and not about whatever was picked last.
    var canvasMenuRows: [MenuRow] {
        guard let display = canvasMenuDisplay else { return bareCanvasMenuRows }
        let components = Experiments.shared.componentsEnabled
        return LayerCommandList.rows(
            for: display,
            // Both component rows act on the selection, and a right click has
            // already made what you pointed at part of it, so the only question
            // left is whether components exist at all.
            offersMakeComponent: components && canMakeComponent,
            offersDetachInstance: components && canDetachInstance,
            beginRename: nil,
            editorState: self)
    }

    /// The picture as a whole: what you can put on it, what you can pick on it,
    /// and how you are looking at it. Same names and same shortcuts as the menu
    /// bar rows these come from, so learning one teaches the other.
    private var bareCanvasMenuRows: [MenuRow] {
        var rows: [MenuRow] = []
        if clipboardHasALayer {
            rows.append(.command("Paste", .command("v")) { self.paste() })
        }
        rows.append(.command("New Layer", .command("n")) { self.newEmptyLayer() })
        rows.append(.separator)
        rows.append(.command("Select All", .command("a")) { self.selectAll() })
        // Only while there IS a marked region to drop, which is the only time
        // it would do anything.
        if selection != nil {
            rows.append(.command("Deselect", .command("d")) { self.deselect() })
        }
        rows.append(.separator)
        rows.append(.command("Zoom to Fit", .command("0")) { self.zoomToFit() })
        rows.append(.command("Actual Size", .command("1")) { self.zoomToActualSize() })
        rows.append(.separator)
        rows.append(.command("Canvas Size…") { self.isCanvasSizeDialogPresented = true })
        return rows
    }
}
