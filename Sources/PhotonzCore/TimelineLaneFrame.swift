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
    /// A zoom's frame, not a scroll's. A lane's picture that moves to a new
    /// canvas on a zoom shows the last one for the frame the new one takes to
    /// lay, the first frame of a zoom from rest included (it moves from the
    /// drawn stretch to the window at the same scale); on a scroll's step it
    /// lays at once (`TimelinePaintedPicture`, pass 23).
    public let isZoom: Bool
    /// A lane's layout at rest: the window it is seen through, or while a
    /// scroll or a zoom has begun and its turn has not come, the window it
    /// was last at rest in, slid (`TimelineLaneWaves`).
    public let isRest: Bool

    public init(ruler: MotionStripRuler, paintedMS: ClosedRange<Double>, drawnMS: ClosedRange<Double>,
                sightMargin: Double, leftEdgeMS: ClosedRange<Double>, zoomScale: Double, isZoom: Bool = false,
                isRest: Bool = false) {
        self.isRest = isRest
        self.ruler = ruler
        self.paintedMS = paintedMS
        self.drawnMS = drawnMS
        self.sightMargin = sightMargin
        self.leftEdgeMS = leftEdgeMS
        self.zoomScale = zoomScale
        self.isZoom = isZoom
    }

    /// How far a scroll's frame builds past each side of its window: its
    /// window starts where the stretch's left edge can first be, and the
    /// edge goes up to a whole window further before the stretch moves, so
    /// half a window past the furthest of those is a window and a half.
    public static let scrollSightMargin = 1.5

    /// The frame while a zoom stretches the painting laid under `held`, the
    /// window it was laid at, with the edge's reach then.
    ///
    /// `painted` is what the lane painted at rest when the hold began from a
    /// lane painting the drawn stretch (after a scroll, or as a file opens):
    /// kept as the painting and the bars' stretch, the first frame of a zoom
    /// lays out and paints exactly what the lane at rest did, and nothing is
    /// built or laid again for it. The first zoom frame from Fit on the
    /// hour-long reference edit built every lane and laid every picture
    /// again for a stretch it then threw away, a 28 ms pass (2026-11-22,
    /// pass 23). Nil paints the window and a sliver, as a fresh zoom frame.
    public static func holding(_ held: MotionStripRuler, leftEdgeMS: ClosedRange<Double>,
                               zoomScale: Double, painted kept: ClosedRange<Double>? = nil) -> TimelineLaneFrame {
        let painted = kept ?? TimelinePaint.paintedMS(window: held, stretch: 0...0, isZooming: true)
        return TimelineLaneFrame(ruler: held, paintedMS: painted, drawnMS: painted,
                                 sightMargin: TimelineSight.margin, leftEdgeMS: leftEdgeMS, zoomScale: zoomScale,
                                 isZoom: true)
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

    /// The layout of a lane at rest in `window`, painted across `painted`.
    public static func resting(_ window: MotionStripRuler, painted: ClosedRange<Double>,
                               drawnMS: ClosedRange<Double>, leftEdgeMS: ClosedRange<Double>,
                               zoomScale: Double) -> TimelineLaneFrame {
        TimelineLaneFrame(ruler: window, paintedMS: painted, drawnMS: drawnMS, sightMargin: TimelineSight.margin,
                          leftEdgeMS: leftEdgeMS, zoomScale: zoomScale, isRest: true)
    }

    /// Whether a lane laid out against this frame can stand for `window` a
    /// frame longer: its painting and what it built still cover the window,
    /// and it is stretched no more than two steps past what a hold is let, not
    /// at all for a scroll. What a lane stands on while the others take a new
    /// frame: all at once, ten lanes were 10 to 11 ms of a zoom's fresh frame
    /// on a 50 track timeline, and 25 to 40 ms of a scroll's first
    /// (2026-11-24, 2026-11-25).
    public func stands(for window: MotionStripRuler) -> Bool {
        guard ruler.spanMS > 0, window.spanMS > 0 else { return false }
        let allowed = isZoom || isRest ? TimelinePaint.quickHeldStretch + 0.10 : 1e-9
        guard abs(ruler.spanMS / window.spanMS - 1) <= allowed else { return false }
        let from = window.startMS, to = window.startMS + window.spanMS
        guard from >= paintedMS.lowerBound - 1e-6, to <= paintedMS.upperBound + 1e-6 else { return false }
        let built = ruler.spanMS * sightMargin
        return from >= ruler.startMS - built && to <= ruler.startMS + ruler.spanMS + built
    }

    /// Whether a lane laid out against `other` shows what one laid out
    /// against this would.
    public func laysOut(as other: TimelineLaneFrame) -> Bool {
        ruler == other.ruler && paintedMS == other.paintedMS && sightMargin == other.sightMargin
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

/// Which frame each lane stands on while the timeline moves.
///
/// The lanes are dealt into groups, and a frame that changes what they are
/// laid out against is not taken by all of them at once: a lane can be slid,
/// and for a zoom stretched a little, from the layout it has, so the ones
/// whose turn has not come stand on it while it covers the window. The first
/// frame of a scroll on a 50 track timeline laid ten lanes out again in one
/// pass, 25 to 40 ms; now none of them is laid out again for the first frame
/// and a few are for each after it (2026-11-25).
public struct TimelineLaneWaves: Equatable, Sendable {
    public static let groupCount = 8

    /// The newest frame, or nil at rest.
    public private(set) var frame: TimelineLaneFrame?
    /// What each group stands on; nil for its layout at rest.
    public private(set) var groups: [TimelineLaneFrame?] = Array(repeating: nil, count: groupCount)
    /// How many steps ago `frame` came, and the one it took over from.
    private var age = 0
    private var before: TimelineLaneFrame?
    /// The window the last step came to, for how far a scroll goes a step.
    private var lastWindow: MotionStripRuler?

    public init() {}

    /// A group still stands on its layout at rest, so that layout must not
    /// move with the window yet.
    public var someRest: Bool { groups.contains { $0 == nil } }

    /// The timeline stepped to `window`, and a lane laid out now would be
    /// laid out against `frame`; `rest` is how the resting ones are.
    /// `clips` is how many clips each group's lanes hold, which is what
    /// laying them out costs: every group the same where it is not said.
    public mutating func step(to new: TimelineLaneFrame, window: MotionStripRuler, rest: TimelineLaneFrame,
                              clips: [Int] = []) {
        let isFresh = new != frame
        if isFresh { before = frame }
        age = isFresh ? 0 : age + 1
        frame = new
        let due = new.isZoom ? [] : dueNow(new, window: window, rest: rest, clips: clips)
        lastWindow = window
        for group in groups.indices where groups[group] != new {
            let standing = groups[group] ?? rest
            let waits: Bool
            if new.isZoom {
                // A hold that begins at rest shows the layout at rest.
                if groups[group] == nil, standing.laysOut(as: new), standing.stands(for: window) { continue }
                // A fresh frame: a third now, a third a step later, and the
                // last a step after. Half and half, the two steps were each
                // over a 120 Hz frame on the hour long edit, whose few lanes
                // hold hundreds of clips (2026-11-25).
                waits = age < group % 3 && (groups[group] == nil || groups[group] == before)
            } else {
                // A scroll's frame stands for many steps: a group a step, and
                // more where it will not stand that long.
                waits = age <= group && !due.contains(group)
            }
            if !waits || !standing.stands(for: window) { groups[group] = new }
        }
    }

    /// The groups a fast scroll takes to `new` this step so the ones behind
    /// are not all taken by the last step they can stand for. A scroll of a
    /// third of a window a step moves the stretch every third step, and left
    /// to a group a step, six of eight went in one. Shared out by clips, not
    /// groups: the hour long edit's are nearly all on four lanes (2026-11-25).
    private func dueNow(_ new: TimelineLaneFrame, window: MotionStripRuler, rest: TimelineLaneFrame,
                        clips: [Int]) -> Set<Int> {
        guard let lastWindow, lastWindow.spanMS == window.spanMS else { return [] }
        let step = window.startMS - lastWindow.startMS
        guard step != 0 else { return [] }
        let behind = groups.indices.filter { groups[$0] != new }
        // How many steps more like this one the first of them stands for.
        var stepsLeft = Self.groupCount
        for group in behind {
            let standing = groups[group] ?? rest
            var steps = 0
            while steps < stepsLeft, standing.stands(for: window.measured(fromMS: window.startMS + step * Double(steps + 1))) {
                steps += 1
            }
            stepsLeft = min(stepsLeft, steps)
        }
        guard stepsLeft < behind.count else { return [] }
        func weight(_ group: Int) -> Double { clips.count == groups.count ? Double(clips[group]) : 1 }
        let share = behind.reduce(0) { $0 + weight($1) } / Double(stepsLeft + 1)
        var due: Set<Int> = [], taken = 0.0
        for group in behind {
            guard taken + weight(group) / 2 <= share || due.isEmpty else { continue }
            due.insert(group)
            taken += weight(group)
        }
        return due
    }

    /// The timeline has come to rest: the next group goes back to its layout
    /// at rest. False once none is left on a frame.
    public mutating func restNext() -> Bool {
        frame = nil
        guard let group = groups.firstIndex(where: { $0 != nil }) else { return false }
        groups[group] = nil
        return someOnAFrame
    }

    /// All of them back at once.
    public mutating func restAll() {
        self = TimelineLaneWaves()
    }

    public var someOnAFrame: Bool { groups.contains { $0 != nil } }
}
