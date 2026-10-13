import CoreGraphics
import Foundation

/// A click on something on the timeline also moves the playhead to the moment
/// it landed on, the way Premiere and Final Cut do: the press picks the thing
/// AND says when. This is the "when". A right click never moves it (the user,
/// 2026-10-13), so a menu row that acts at the playhead says where that is.
public enum TimelinePointing {

    /// The moment under `laneX` points along a lane `laneWidth` wide, measured
    /// the way the ruler above it is drawn. Nil off either end of the lane.
    public static func ms(atLaneX laneX: CGFloat, laneWidth: CGFloat, ruler: MotionStripRuler) -> Int? {
        guard laneWidth > 0, laneX >= 0, laneX <= laneWidth else { return nil }
        return Int(ruler.ms(atFraction: Double(laneX / laneWidth)).rounded())
    }

    /// A right-click row that acts at the playhead, saying where it is:
    /// "Add Key at 0:02.00", in the transport's own minutes, seconds and
    /// hundredths, so a person who parked the playhead and right clicked
    /// somewhere else reads where the row will act.
    public static func atPlayhead(_ verb: String, ms: Int) -> String {
        let clamped = max(0, ms)
        let seconds = clamped / 1000
        let hundredths = (clamped % 1000) / 10
        return verb + String(format: " at %d:%02d.%02d", seconds / 60, seconds % 60, hundredths)
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
