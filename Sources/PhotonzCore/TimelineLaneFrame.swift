import CoreGraphics
import Foundation

/// The ruler a busy timeline's lanes are laid out against while the timeline
/// moves, and how what is laid out against it is slid and stretched to the
/// window (`the-timeline-of-an-hour-long-edit-scrolls-zooms`, pass 19).
///
/// Every frame of a scroll or a zoom moves the window, and a lane that lays
/// its clips, cuts and gaps out against the window builds itself again on
/// every one of those frames: near the whole-hour view of the hour-long
/// reference edit that was about 8 ms of the main thread a frame before
/// anything was painted (2026-11-21). A lane laid out against a frame that
/// holds still for several frames builds itself only when the frame moves,
/// and the one view that reads the window slides and stretches the whole lane
/// into place.
///
/// The frame holds still:
/// - while a zoom stretches the painting the lanes laid a frame or two ago
///   (`TimelinePaint.stretch`): the window that painting was laid at;
/// - while a scroll stays inside one drawn stretch (`TimelineDrawnStretch`):
///   the window's scale measured from where the stretch's left edge can
///   start, with a sight wide enough for every window inside the stretch.
///
/// A zoom frame that paints afresh lays out against the window itself, and
/// says the same as the held frame that follows it, so the first frame of a
/// hold builds nothing. Once the timeline rests the lanes go back to the
/// window (the app lets the frame go), so a hand always meets a lane laid out
/// against the window it sees.
public struct TimelineLaneFrame: Hashable, Sendable {
    /// What the lane lays out against.
    public let ruler: MotionStripRuler
    /// What the lane's painting covers (`TimelinePaint.paintedMS`).
    public let paintedMS: ClosedRange<Double>
    /// What a clip's bar is drawn across (`TimelineDrawnStretch`).
    public let drawnMS: ClosedRange<Double>
    /// How far past each side of the ruler's window the lane builds, as a
    /// share of the window (`TimelineSight`).
    public let sightMargin: Double
    /// Where the lane's left edge can reach while this frame stands
    /// (`TimelinePaint.nameFollowsTheEdge`).
    public let leftEdgeMS: ClosedRange<Double>
    /// How far in, for how strongly a clip's pictures show.
    public let zoomScale: Double

    public init(ruler: MotionStripRuler, paintedMS: ClosedRange<Double>, drawnMS: ClosedRange<Double>,
                sightMargin: Double, leftEdgeMS: ClosedRange<Double>, zoomScale: Double) {
        self.ruler = ruler
        self.paintedMS = paintedMS
        self.drawnMS = drawnMS
        self.sightMargin = sightMargin
        self.leftEdgeMS = leftEdgeMS
        self.zoomScale = zoomScale
    }

    /// How far a scroll's frame builds past each side of its window: its
    /// window starts where the stretch's left edge can first be, and the
    /// edge goes up to a whole window further before the stretch moves, so
    /// half a window past the furthest of those is a window and a half.
    public static let scrollSightMargin = 1.5

    /// The frame while a zoom stretches the painting laid under `held`, the
    /// window it was laid at, with the edge's reach then.
    public static func holding(_ held: MotionStripRuler, leftEdgeMS: ClosedRange<Double>,
                               zoomScale: Double) -> TimelineLaneFrame {
        let painted = TimelinePaint.paintedMS(window: held, stretch: 0...0, isZooming: true)
        return TimelineLaneFrame(ruler: held, paintedMS: painted, drawnMS: painted,
                                 sightMargin: TimelineSight.margin, leftEdgeMS: leftEdgeMS, zoomScale: zoomScale)
    }

    /// The frame of a zoom frame that paints afresh: the window itself,
    /// painted with a sliver either side. The same as `holding` the same
    /// window, so the hold that follows it builds nothing.
    public static func zooming(_ window: MotionStripRuler, leftEdgeMS: ClosedRange<Double>,
                               zoomScale: Double) -> TimelineLaneFrame {
        holding(window, leftEdgeMS: leftEdgeMS, zoomScale: zoomScale)
    }

    /// The frame of a scroll inside one drawn stretch: the window's scale
    /// measured from `anchorMS`, where the stretch's left edge can first be,
    /// so it holds still until the stretch moves.
    public static func scrolling(_ window: MotionStripRuler, anchorMS: Double, drawnMS: ClosedRange<Double>,
                                 leftEdgeMS: ClosedRange<Double>, zoomScale: Double) -> TimelineLaneFrame {
        TimelineLaneFrame(ruler: window.measured(fromMS: anchorMS), paintedMS: drawnMS, drawnMS: drawnMS,
                          sightMargin: scrollSightMargin, leftEdgeMS: leftEdgeMS, zoomScale: zoomScale)
    }

    /// How content laid out against this frame is put on the lane under
    /// `window`: stretched by `stretch` from its left edge, then moved along
    /// by `offset` points, a whole pixel at `scale`.
    public func slide(to window: MotionStripRuler, laneWidth: CGFloat, scale: CGFloat)
        -> (stretch: CGFloat, offset: CGFloat) {
        let stretch = window.spanMS > 0 ? CGFloat(ruler.spanMS / window.spanMS) : 1
        let pixels = max(1, scale)
        let offset = (laneWidth * CGFloat(window.fraction(ofMS: ruler.startMS)) * pixels).rounded() / pixels
        return (stretch, offset)
    }

    /// A point across the lane as the window has it, as the frame has it.
    public func frameX(ofWindowX x: CGFloat, window: MotionStripRuler, laneWidth: CGFloat,
                       scale: CGFloat) -> CGFloat {
        let (stretch, offset) = slide(to: window, laneWidth: laneWidth, scale: scale)
        return stretch > 0 ? (x - offset) / stretch : x
    }

    /// A point across the lane as the frame has it, as the window has it.
    public func windowX(ofFrameX x: CGFloat, window: MotionStripRuler, laneWidth: CGFloat,
                        scale: CGFloat) -> CGFloat {
        let (stretch, offset) = slide(to: window, laneWidth: laneWidth, scale: scale)
        return x * stretch + offset
    }
}
