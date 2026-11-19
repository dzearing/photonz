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
/// A long track paints whatever of it is in sight at any zoom, and so does
/// every track of a long edit (`longEdit`), its quiet Title track included:
/// near the whole-hour view the reference edit's 22 titles were a full bar
/// each, about 8 ms of every frame of a zoom (2026-11-16). Zoomed to half
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

    /// An edit holding at least this many clips across its tracks paints
    /// every track, however few clips each holds. 200 until 2026-11-16, when
    /// the 20 minute reference edit (177 clips) built every clip of its quiet
    /// tracks as a full bar and the pass its rows arrived in took 120 to 135
    /// ms; painted, about 55.
    public static let longEdit = 100

    public static func lanePaints(clipsInSight: Int, clipsOnTrack: Int = 0, clipsInEdit: Int = 0) -> Bool {
        clipsInSight >= busyLane || clipsOnTrack >= busyLane || clipsInEdit >= longEdit
    }

    /// Whether a lane builds a view for a clip or cut from `fromMS` to
    /// `toMS` that is in its sight (`TimelineSight`). A lane that paints
    /// covers its drawn `stretch` (the window and at least half a window
    /// either side) and builds nothing past it but what somebody is working
    /// on: the sight reaches up to half a window past the stretch, and near
    /// the whole-hour view of the reference edit dozens of full bars and cut
    /// views were built there, off screen, on every frame of a zoom
    /// (2026-11-16). A lane that does not paint builds all of its sight.
    public static func builds(fromMS: Double, toMS: Double, stretch: ClosedRange<Double>, isKept: Bool,
                              lanePaints: Bool) -> Bool {
        !lanePaints || isKept || (toMS >= stretch.lowerBound && fromMS <= stretch.upperBound)
    }

    // MARK: Gaps

    /// The gaps that are views of their own on a lane. A lane that paints
    /// paints its gaps too, and builds a view only for the gap under the
    /// pointer (`pointerGapMS`, where it starts), which carries the gap's
    /// press and right-click menu: near the whole-hour view of the hour-long
    /// reference edit about seventy gaps were each a striped canvas, a dashed
    /// edge, a press and a menu, rebuilt on every frame of a zoom, about 5 ms
    /// of it (2026-11-17). A lane that does not paint builds them all.
    public static func gapViews(_ gaps: [TimelineGap], lanePaints: Bool, pointerGapMS: Int?) -> [TimelineGap] {
        guard lanePaints else { return gaps }
        guard let pointerGapMS else { return [] }
        return gaps.filter { $0.range.lowerBound == pointerGapMS }
    }

    /// The gaps a painting lane paints: every one reaching the drawn
    /// `stretch`, as every clip on it is.
    public static func paintedGaps(_ gaps: [TimelineGap], stretch: ClosedRange<Double>) -> [TimelineGap] {
        gaps.filter { Double($0.range.upperBound) >= stretch.lowerBound && Double($0.range.lowerBound) <= stretch.upperBound }
    }

    /// The gap `ms` along the lane is in, either end included.
    public static func gap(atMS ms: Double, in gaps: [TimelineGap]) -> TimelineGap? {
        gaps.last { Double($0.range.lowerBound) <= ms && ms <= Double($0.range.upperBound) }
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
        /// Its sound's shape is not read yet. It is painted all the same, as
        /// the flat bar a full view draws while it waits, and the lane asks
        /// for the shape: keeping it a view made every clip of a long edit a
        /// view at the moment it opened (2026-11-16).
        public var waveformMissing = false

        public init() {}
    }

    public static func paints(_ clip: Clip) -> Bool {
        !clip.isKept && clip.isPlainKind && clip.pieceCount == 1 && !clip.isHeld && !clip.pictureHidden
            && !clip.hasBadge && !clip.hasKeys && !clip.hasDrift
            && !clip.levelHasPoints && !clip.soundHasBadge
    }

    // MARK: While the timeline zooms

    /// What a painting lane's canvas covers: the drawn stretch, which a
    /// scroll slides and paints only when it moves, or while the timeline is
    /// zooming, the window and a sliver either side.
    ///
    /// A zoom paints every lane again on every frame, whatever the canvas
    /// covers, and near the whole-hour view of the reference edit two and a
    /// half windows of clips, waveforms and names were painted and laid on
    /// the screen for every frame of it, more than half of them off screen
    /// (2026-11-16).
    public static func paintedMS(window: MotionStripRuler, stretch: ClosedRange<Double>,
                                 isZooming: Bool) -> ClosedRange<Double> {
        guard isZooming else { return stretch }
        let sliver = window.spanMS / 32
        return (window.startMS - sliver)...(window.startMS + window.spanMS + sliver)
    }

    /// How far a zoom may stretch the painting a lane laid a frame or two
    /// ago before the lane paints it again: a name or a corner drawn at most
    /// this much wider or narrower than it is, for a frame or two. At the
    /// speed walk's step of four per cent a frame, two frames of three are
    /// held: 4.5 per cent (one of two held) took about 0.6 ms off a near-Fit
    /// frame of the reference edit, 8.5 about 1 ms, and a held frame
    /// photographed beside a fresh one at the same zoom differs only in where
    /// the pictures along a clip fall, which a zoom lays out again on every
    /// frame anyway (2026-11-19).
    public static let heldStretch = 0.085

    /// How much wider the painting laid under `painted` is drawn to stand
    /// for `window`, or nil when it must be painted again: the change of
    /// scale is more than `heldStretch`, or the window reaches past what
    /// was painted (`paintedMS` while zooming).
    ///
    /// Time across a lane is linear, so a painting stretched about where it
    /// starts puts every clip, cut and gap exactly where a fresh one would;
    /// only what has a size of its own (a name, a corner, a fade diamond) is
    /// a few per cent wider or narrower for those frames. Near the whole-hour
    /// view of the reference edit a lane's painting cost about half of each
    /// frame of a zoom, all of it laid again for a change of four per cent
    /// (2026-11-19).
    public static func stretch(painted: MotionStripRuler, to window: MotionStripRuler) -> Double? {
        guard painted.spanMS > 0, window.spanMS > 0 else { return nil }
        let ratio = painted.spanMS / window.spanMS
        guard abs(ratio - 1) <= heldStretch + 1e-9 else { return nil }
        let covered = paintedMS(window: painted, stretch: 0...0, isZooming: true)
        guard window.startMS >= covered.lowerBound - 1e-6,
              window.startMS + window.spanMS <= covered.upperBound + 1e-6 else { return nil }
        return ratio
    }

    /// Whether moving the window from `old` to `new` is a zoom: its scale
    /// changed. A move along at the same scale is a scroll.
    public static func isZoom(from old: TimelineZoom, to new: TimelineZoom) -> Bool {
        old.scale != new.scale
    }
}
