import Foundation
import PhotonzCore

extension EditorState {
    /// The facts the panel's automatic rule is allowed to read
    /// (Next, `next-panel-sections`).
    ///
    /// Every one of them is about the DOCUMENT or the window, and that is the
    /// whole point: an automatic answer that read the selection would make the
    /// panel rearrange itself as you clicked from one layer to the next, which
    /// is one of the things the panel was complained about for. See
    /// `PanelSectionVisibility` for the rule these feed.
    ///
    /// One walk of the layer tree, not four. The panel asks this on every draw,
    /// so a document with a few hundred layers should cost one pass rather than
    /// one per fact.
    var panelSectionSituation: PanelSectionVisibility.Situation {
        var situation = PanelSectionVisibility.Situation()
        situation.isLibraryAskedFor = isLibraryVisible
        guard let document else { return situation }
        // Walked rather than flattened. `Document.allLayers` builds a new array
        // holding a copy of every layer in the document, and this is asked on
        // every pass the dock draws; walking `children`, which hands back the
        // array that is already there, costs a retain instead. It also stops
        // the moment every answer is yes, which on a document that is doing all
        // of these jobs is usually within the first few layers.
        func scan(_ layers: [Layer]) {
            for layer in layers {
                if layer.measure != nil { situation.documentHasMeasurement = true }
                if layer.isMainComponent || layer.isComponentInstance {
                    situation.documentHasComponent = true
                }
                if layer.isGroup { situation.documentHasContainer = true }
                // A screen, whether or not it has been given any columns yet:
                // the tick box that gives it some is inside the section this
                // decides (`PanelSectionVisibility`).
                if layer.isFrame { situation.documentHasFrame = true }
                if situation.isSettled { return }
                scan(layer.children)
                if situation.isSettled { return }
            }
        }
        scan(document.layers)
        return situation
    }
}
