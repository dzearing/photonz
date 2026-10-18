// What the open cut's two rows last drew and where, so a walk can measure
// their ink against the ruler rather than photograph it and guess. Probe-only,
// like the rest of the harness.
#if PHOTONZ_PLAYTEST
import CoreGraphics
import Foundation
import PhotonzCore

@MainActor
final class DrawnExpandedCut {
    static let shared = DrawnExpandedCut()

    struct Rows {
        /// The rows' lane, both rows, in the window's own points, top left.
        var laneFrame: CGRect
        let laneWidth: CGFloat
        let rowHeight: CGFloat
        /// How far down the lane B's row starts.
        let bTop: CGFloat
        /// What they were drawn from.
        let rows: ExpandedCut
        let label: String?
    }

    private(set) var rows: Rows?

    func showing(_ drawn: Rows) { rows = drawn }
    func gone() { rows = nil }
    func moved(to frame: CGRect) { rows?.laneFrame = frame }
}
#endif
