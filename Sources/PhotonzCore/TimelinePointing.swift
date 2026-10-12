import CoreGraphics
import Foundation

/// A click or a right click on something on the timeline also moves the
/// playhead to the moment it landed on, the way Premiere and Final Cut do: the
/// press picks the thing AND says when. This is the "when".
public enum TimelinePointing {

    /// The moment under `laneX` points along a lane `laneWidth` wide, measured
    /// the way the ruler above it is drawn. Nil off either end of the lane.
    public static func ms(atLaneX laneX: CGFloat, laneWidth: CGFloat, ruler: MotionStripRuler) -> Int? {
        guard laneWidth > 0, laneX >= 0, laneX <= laneWidth else { return nil }
        return Int(ruler.ms(atFraction: Double(laneX / laneWidth)).rounded())
    }
}

extension PhotonzDocument {

    /// Split at Playhead from a right click inside a pick of several clips:
    /// every one the moment runs through is cut there, as one edit. A clip on
    /// a locked track, or one the moment misses, is left whole. Answers
    /// whether anything was cut.
    @discardableResult
    public mutating func splitClips(_ ids: [UUID], atMS ms: Int) -> Bool {
        var cut = false
        for id in ids where !isClipOnLockedTrack(id) {
            if splitClip(id, atMS: ms) { cut = true }
        }
        return cut
    }
}
