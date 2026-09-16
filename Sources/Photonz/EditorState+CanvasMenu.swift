import AppKit
import PhotonzCore
import SwiftUI

// What a right click on the picture is about, worked out the moment the menu
// is asked for. The rule itself is pure and tested (`CanvasMenuAim`); this is
// the wiring: hit test in, selection and menu contents out.
extension EditorState {

    /// The canvas has been right clicked over `hit` (nil for bare picture),
    /// resolved inside `context` when the pointer was inside a group.
    ///
    /// **A right click picks what you point at.** A shape on the canvas is a
    /// picture you are looking at, and the only thing on screen saying what the
    /// app thinks you mean is the selection outline; a menu about a box that is
    /// not wearing that outline sends every command it carries somewhere nobody
    /// pointed. So a layer outside the selection becomes the selection first,
    /// and the menu that opens is about it. A layer already IN the selection
    /// brings the rest of the selection with it and moves nothing, which is the
    /// same rule the layers list uses (`rowMenuTargets`).
    ///
    /// Bare picture leaves the selection exactly as it found it: an accidental
    /// right click on the matte must not throw away what you had picked.
    func aimCanvasMenu(at hit: UUID?, inside context: UUID?) {
        let aim = CanvasMenuAim.aim(at: hit, picked: actionableLayerIDs)
        canvasMenuAim = aim
        guard aim.picks != nil, let hit else { return }
        if let context {
            selectLayer(hit, inGroup: context)
        } else {
            selectLayer(hit)
        }
    }

    /// The layer the canvas menu is about, as the layers list would describe
    /// it, so both menus are built from exactly the same facts.
    ///
    /// Built with every group open rather than read off the rows on screen: the
    /// pointer can be inside a group whose row is shut, or over a layer while
    /// the list is showing search results, and in both cases the menu is still
    /// about the thing under the pointer.
    var canvasMenuDisplay: LayerRowDisplay? {
        guard let id = canvasMenuAim.id, let document else { return nil }
        var selected = multiSelectedLayerIDs
        if let selectedLayerID { selected.insert(selectedLayerID) }
        return document.layerRows(
            expanded: document.openableGroupIDs,
            selected: selected,
            marksOutOfView: Experiments.shared.autoLayoutEnabled,
            saysItsWords: Experiments.shared.rowSaysItsWordsEnabled,
            separations: separationLeftovers)
            .first { $0.id == id }
    }

    /// Whether Paste would land anything, so the canvas menu leaves the row out
    /// rather than offering one that does nothing.
    var clipboardHasALayer: Bool {
        let pasteboard = NSPasteboard.general
        if pasteboard.data(forType: NSPasteboard.PasteboardType(LayerTransfer.pasteboardType)) != nil {
            return true
        }
        return pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
    }
}
