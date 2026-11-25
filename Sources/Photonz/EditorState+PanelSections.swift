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
        // A picture's window keeps the Library out until it is turned on
        // there, whatever the app-wide switch says
        // (`WindowMode.libraryWaitsToBeTurnedOn`).
        situation.isLibraryAskedFor = activeWindowMode?.libraryAsked(isLibraryVisible) ?? isLibraryVisible
        guard let document else { return situation }
        // Kept with the document, since this is asked on every pass the dock
        // draws. A frame counts whether or not it has been given any columns
        // yet: the tick box that gives it some is inside the section this
        // decides (`PanelSectionVisibility`).
        let facts = document.panelFacts
        if facts.measurement { situation.documentHasMeasurement = true }
        if facts.component { situation.documentHasComponent = true }
        if facts.container { situation.documentHasContainer = true }
        if facts.frame { situation.documentHasFrame = true }
        return situation
    }

    /// Whether the Library may be offered to the panel at all: the app-wide
    /// switch is on, or this window's mode has had it turned on by hand, or
    /// it is a video's, which shows the shelf until it is turned off
    /// (`WindowMode.libraryShowsUntilTurnedOff`). The panel's visibility rule
    /// then has the last word (`isLibraryShown`).
    var libraryMayShow: Bool {
        let chosen = panelChoices.choice(for: InspectorSectionID.library.rawValue)
        guard hasDocument, let mode = activeWindowMode else {
            return isLibraryVisible || chosen == true
        }
        return mode.libraryOffered(switchIsOn: isLibraryVisible, chosen: chosen)
    }

    /// Whether this window's panel is showing the Library: what View ▸
    /// Library ticks, and what everything that brings the shelf forward asks.
    var isLibraryShown: Bool {
        guard Experiments.shared.libraryEnabled, hasDocument, libraryMayShow else { return false }
        guard Experiments.shared.panelSectionsEnabled else { return true }
        return PanelSectionVisibility.isShown(InspectorSectionID.library.rawValue,
                                              choices: panelChoices, in: panelSectionSituation)
    }
}
