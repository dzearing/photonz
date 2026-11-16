import CoreGraphics
import Foundation

/// Which clips a busy lane paints as one layer instead of building a view for
/// each (`the-timeline-of-an-hour-long-edit-scrolls-zooms`).
///
/// A clip's bar is a big view: pieces, grips, a level line you can drag, fade
/// diamonds, popover anchors, a right-click menu. On the 60 minute reference
/// edit about 800 of them are in sight near the whole-hour view, and every
/// frame of a zoom built each one again, about 570 ms a frame against 8 ms
/// (2026-11-14). With the bars taken out the same zoom ran at 24 ms.
///
/// So a lane with many clips in sight paints the plain ones (the same fill,
/// edge, name, waveform, level line, fade diamonds and picture fades the bar
/// draws, and the cuts between them) and builds a full bar only for a clip
/// somebody is working on: picked, in a hand, trimmed, renamed or under the
/// pointer. Anything the painting does not draw (pieces, a still, a speed
/// badge, keys, points on the level line) keeps the clip a view, so what the
/// timeline shows never changes. Pictures along a clip are painted too, from
/// the pictures the timeline has read (2026-11-15).
///
/// A long track paints whatever of it is in sight at any zoom: zoomed to half
/// a minute, a lane of the hour-long edit holds a handful of clips, and each
/// was a full bar of pictures slid along on every frame of a scroll. A short
/// track with few clips in sight builds them all, as it always has.
///
/// The painting is laid against a fixed origin, where the drawn stretch
/// starts (`Canvas`), and slid into place: a scroll inside one stretch moves
/// it without painting it again.
public enum TimelinePaint {
    /// A lane with fewer clips than this in sight builds every one as a view,
    /// unless its track holds at least this many clips in all.
    public static let busyLane = 24

    public static func lanePaints(clipsInSight: Int, clipsOnTrack: Int = 0) -> Bool {
        clipsInSight >= busyLane || clipsOnTrack >= busyLane
    }

    /// What a lane's painting is laid on: a canvas as wide as the drawn
    /// stretch, measured from where the stretch starts, so it stays the same
    /// for every frame of a scroll inside one stretch and is slid into place
    /// by `offset(in:laneWidth:scale:)`.
    public struct Canvas: Hashable, Sendable {
        /// The window's scale, measured from the start of the stretch.
        public let ruler: MotionStripRuler
        /// How wide the stretch is across the lane, in points.
        public let width: CGFloat

        public init(drawnMS: ClosedRange<Double>, ruler window: MotionStripRuler, laneWidth: CGFloat) {
            ruler = window.measured(fromMS: drawnMS.lowerBound)
            width = laneWidth * window.fraction(spanningMS: drawnMS.upperBound - drawnMS.lowerBound)
        }

        /// Where the canvas's left edge sits across the lane under `window`,
        /// on a whole pixel so the painting never falls between two.
        public func offset(in window: MotionStripRuler, laneWidth: CGFloat, scale: CGFloat) -> CGFloat {
            let scale = max(1, scale)
            return (laneWidth * window.fraction(ofMS: ruler.startMS) * scale).rounded() / scale
        }
    }

    /// Whether a clip's name may be pushed along by the lane's left edge
    /// while the edge is anywhere in `leftEdgeMS`: a clip that starts before
    /// the edge can reach and ends after it can. Its name is drawn against
    /// the window, every frame; every other name rides on the canvas.
    public static func nameFollowsTheEdge(fromMS: Double, toMS: Double, leftEdgeMS: ClosedRange<Double>) -> Bool {
        fromMS < leftEdgeMS.upperBound && toMS > leftEdgeMS.lowerBound
    }

    /// What decides whether one clip's bar can be painted.
    public struct Clip: Hashable, Sendable {
        /// Picked, in a hand, being trimmed or renamed, or under the pointer.
        public var isKept = false
        /// A picture or its own sound: the kinds the painting draws.
        public var isPlainKind = true
        public var pieceCount = 1
        /// A held frame: drawn as a still.
        public var isHeld = false
        public var pictureHidden = false
        /// A speed or hold badge in its corner.
        public var hasBadge = false
        public var hasKeys = false
        /// Out of step with the picture after a hold elsewhere.
        public var hasDrift = false
        /// Pinned points on its sound's level line, each a dot to drag.
        public var levelHasPoints = false
        /// A gain, a cleaned sound or a cleaning in progress, as a badge.
        public var soundHasBadge = false
        /// Its sound's shape is not read yet: the bar asks for it.
        public var waveformMissing = false

        public init() {}
    }

    public static func paints(_ clip: Clip) -> Bool {
        !clip.isKept && clip.isPlainKind && clip.pieceCount == 1 && !clip.isHeld && !clip.pictureHidden
            && !clip.hasBadge && !clip.hasKeys && !clip.hasDrift
            && !clip.levelHasPoints && !clip.soundHasBadge && !clip.waveformMissing
    }
}
