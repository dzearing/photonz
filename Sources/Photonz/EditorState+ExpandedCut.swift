import Foundation
import PhotonzCore

// Expand the Cut (`video-transition-wt.html`, the Edit point group's
// "Expand the cut ⌥E", `#rowA` and `#rowB`): the cut in hand opened into the
// two clips it is made of, one row each under its track, so an editor can see
// what a transition borrows. A view, not an edit: it moves nothing, and it is
// not a step to undo.

extension EditorState {

    /// Whether ⌥E has a cut to open or close: a cut is picked.
    var canExpandCut: Bool {
        Experiments.shared.transitionsAtACutEnabled && documentHasTime && cutInHand != nil
    }

    /// Whether the cut in hand is the one open, which ticks the menu rows.
    var isCutInHandExpanded: Bool {
        guard let place = cutInHand?.place else { return false }
        return expandedCutPlace == place
    }

    /// Open the cut in hand, or `place` when a right-click on a cut asks;
    /// pressed again on the open one, close it. One cut is open at a time.
    func toggleExpandedCut(at place: TimelineCutPlace? = nil) {
        guard Experiments.shared.transitionsAtACutEnabled,
              let place = place ?? cutInHand?.place,
              document?.documentCut(at: place) != nil else { return }
        expandedCutPlace = expandedCutPlace == place ? nil : place
        timelineTrackRowsMemo = nil
    }

    /// The open cut's rows when they belong under `trackID`, as drawn now:
    /// with the length a hand is dragging its band to, so the rows keep up.
    func expandedCutRows(onTrack trackID: UUID) -> (place: TimelineCutPlace, rows: ExpandedCut)? {
        guard Experiments.shared.transitionsAtACutEnabled, let place = expandedCutPlace,
              let document, document.trackID(ofClip: place.arrivingClip) == trackID,
              let cut = document.documentCut(at: place)?.cut else { return nil }
        let drawing = drawnClipTransition(cut, at: place)
        guard let rows = document.expandedCut(at: place, drawing: drawing) else { return nil }
        return (place, rows)
    }

    /// Whether a track has the open cut under it, which makes it two rows
    /// taller (`TimelineDock.height(of:)`).
    func trackHasExpandedCut(_ trackID: UUID) -> Bool {
        guard let place = expandedCutPlace, let document,
              document.trackID(ofClip: place.arrivingClip) == trackID else { return false }
        return document.documentCut(at: place) != nil
    }
}
