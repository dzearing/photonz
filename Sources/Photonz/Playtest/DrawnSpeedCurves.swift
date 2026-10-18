// What each clip's speed curve last drew and where, so a walk can read the
// ink the lane put down (the bands, the 1x line) against what the stops say,
// rather than photograph it and guess. Probe-only, like the rest of the
// harness.
#if PHOTONZ_PLAYTEST
import CoreGraphics
import Foundation
import PhotonzCore

@MainActor
final class DrawnSpeedCurves {
    static let shared = DrawnSpeedCurves()

    struct Curve {
        /// The lane's plot, in the window's own points, top left.
        var laneFrame: CGRect
        /// Each band's stretch, in the plot's own points from its left edge.
        let bands: [(band: SpeedBand, x0: CGFloat, x1: CGFloat)]
        /// The band strip along the floor, down from the plot's top.
        let strip: ClosedRange<CGFloat>
        /// Where the scale puts 1x, down from the plot's top.
        let oneX: CGFloat
        /// The part of the plot under the clip, along the lane.
        let plot: ClosedRange<CGFloat>
    }

    private var curves: [UUID: Curve] = [:]

    func showing(_ layer: UUID, _ curve: Curve) { curves[layer] = curve }
    func gone(_ layer: UUID) { curves[layer] = nil }
    func moved(_ layer: UUID, to frame: CGRect) { curves[layer]?.laneFrame = frame }
    func curve(of layer: UUID) -> Curve? { curves[layer] }
}
#endif
