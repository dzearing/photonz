import AppKit
import Foundation
import PhotonzCore

/// An open value graph zooms its value range (task
/// `the-value-graph-zooms-its-value-range-and-the-ti`).
///
/// A graph opens fitted to its own values. ⌥ and the wheel over it zoom it
/// taller or shorter about the value under the pointer, the way ⌥ and the
/// wheel zoom time anywhere else on the timeline; the readings on its left
/// follow, and a double click on them goes back to the fit. The arithmetic is
/// `GraphValueRange`'s; this keeps one range per graph, by the motion it
/// draws, and forgets it when the graph shuts.
extension EditorState {

    /// The values a graph shows, top to bottom: its zoom where it has one,
    /// else its fit.
    func keyGraphRange(motionID: UUID, fit graph: KeyGraph) -> GraphValueRange {
        keyGraphZoom[motionID] ?? GraphValueRange(low: graph.low, high: graph.high)
    }

    func isKeyGraphZoomed(_ motionID: UUID) -> Bool { keyGraphZoom[motionID] != nil }

    /// Zooms a graph by `factor` (above one closer in) about the value
    /// `fraction` of the way down its drawn range.
    func zoomKeyGraph(layerID: UUID, motionID: UUID, by factor: Double, aboutFractionFromTop fraction: Double) {
        guard let graph = keyGraph(layerID: layerID, motionID: motionID) else { return }
        let fit = GraphValueRange(low: graph.low, high: graph.high)
        let now = keyGraphRange(motionID: motionID, fit: graph)
        let anchor = now.value(atFractionFromTop: min(max(fraction, 0), 1))
        keyGraphZoom[motionID] = now.zoomed(by: factor, about: anchor, fit: fit)
    }

    /// A double click on the readings: back to the fit.
    func fitKeyGraph(_ motionID: UUID) {
        if keyGraphZoom[motionID] != nil { keyGraphZoom[motionID] = nil }
    }

    /// ⌥ and the wheel at `point` in the timeline wheel's space: zooms the
    /// open graph under it, if one is. False when the pointer is over no
    /// graph, so the wheel zooms time as it does everywhere else.
    func wheelOverKeyGraph(at point: CGPoint, deltaY: Double) -> Bool {
        guard let (row, frame) = keyGraphFrames.first(where: { $0.value.contains(point) }),
              isKeyLaneGraphed(row.motionID) else { return false }
        let pad = KeyLanesView.graphPad
        let fraction = Double((point.y - frame.minY - pad) / max(1, frame.height - pad * 2))
        zoomKeyGraph(layerID: row.layerID, motionID: row.motionID,
                     by: GraphValueRange.wheelFactor(deltaY: deltaY), aboutFractionFromTop: fraction)
        return true
    }
}
