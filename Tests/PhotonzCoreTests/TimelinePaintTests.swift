import CoreGraphics
import Testing
@testable import PhotonzCore

/// Which clips a busy lane paints as one layer rather than as a view each
/// (`TimelinePaint`, `the-timeline-of-an-hour-long-edit-scrolls-zooms`).
@Suite struct TimelinePaintTests {
    private let plain = TimelinePaint.Clip()

    @Test func aQuietLaneBuildsEveryClip() {
        #expect(!TimelinePaint.lanePaints(clipsInSight: TimelinePaint.busyLane - 1))
        #expect(TimelinePaint.lanePaints(clipsInSight: TimelinePaint.busyLane))
        #expect(TimelinePaint.lanePaints(clipsInSight: 500))
    }

    /// A long track paints whatever of it is in sight, a handful of clips
    /// zoomed right in included: on the hour-long reference edit a lane
    /// zoomed to half a minute holds a few clips, each a full bar of pictures
    /// slid along on every frame of a scroll (2026-11-15).
    @Test func aLongTrackPaintsWhateverIsInSight() {
        #expect(TimelinePaint.lanePaints(clipsInSight: 3, clipsOnTrack: TimelinePaint.busyLane))
        #expect(TimelinePaint.lanePaints(clipsInSight: 0, clipsOnTrack: 500))
        #expect(!TimelinePaint.lanePaints(clipsInSight: 3, clipsOnTrack: TimelinePaint.busyLane - 1))
        #expect(TimelinePaint.lanePaints(clipsInSight: TimelinePaint.busyLane,
                                         clipsOnTrack: TimelinePaint.busyLane))
    }

    /// A quiet track of a long edit paints too: the hour-long reference
    /// edit's 22 titles were each a full bar, about 8 ms of every frame of a
    /// zoom near the whole-hour view (2026-11-16). A short edit's quiet
    /// track still builds every clip.
    @Test func aQuietTrackOfALongEditPaints() {
        #expect(TimelinePaint.lanePaints(clipsInSight: 2, clipsOnTrack: 22, clipsInEdit: TimelinePaint.longEdit))
        #expect(TimelinePaint.lanePaints(clipsInSight: 0, clipsOnTrack: 1, clipsInEdit: 524))
        #expect(!TimelinePaint.lanePaints(clipsInSight: 2, clipsOnTrack: 22, clipsInEdit: TimelinePaint.longEdit - 1))
        #expect(!TimelinePaint.lanePaints(clipsInSight: 5, clipsOnTrack: 5, clipsInEdit: 60))
    }

    /// The 20 minute reference edit (177 clips) is a long edit: built as a
    /// full bar each, the clips of its quiet tracks made the pass its rows
    /// arrived in 120 to 135 ms, against about 55 painted (2026-11-16).
    @Test func theTwentyMinuteReferenceEditPaintsItsQuietTracks() {
        #expect(TimelinePaint.lanePaints(clipsInSight: 6, clipsOnTrack: 9, clipsInEdit: 177))
        #expect(TimelinePaint.lanePaints(clipsInSight: 4, clipsOnTrack: 4, clipsInEdit: 100))
        #expect(!TimelinePaint.lanePaints(clipsInSight: 4, clipsOnTrack: 4, clipsInEdit: 99))
    }


    /// On a lane that paints, a clip or cut in the lane's sight but off the
    /// stretch the painting covers is off screen: it is not built at all,
    /// unless somebody is working on it. Near the whole-hour view the sight
    /// reaches up to half a window past the stretch either side, and dozens
    /// of full bars and cut views were built there on every frame of a zoom
    /// (2026-11-16).
    @Test func offTheStretchAPaintingLaneBuildsOnlyWhatIsWorkedOn() {
        let stretch = 100_000.0...400_000.0
        // On the stretch: painted or built, as the clip decides.
        #expect(TimelinePaint.builds(fromMS: 90_000, toMS: 110_000, stretch: stretch, isKept: false, lanePaints: true))
        #expect(TimelinePaint.builds(fromMS: 390_000, toMS: 500_000, stretch: stretch, isKept: false, lanePaints: true))
        // Off it: only a clip somebody is working on.
        #expect(!TimelinePaint.builds(fromMS: 410_000, toMS: 420_000, stretch: stretch, isKept: false, lanePaints: true))
        #expect(!TimelinePaint.builds(fromMS: 50_000, toMS: 99_000, stretch: stretch, isKept: false, lanePaints: true))
        #expect(TimelinePaint.builds(fromMS: 410_000, toMS: 420_000, stretch: stretch, isKept: true, lanePaints: true))
        // A lane that does not paint builds everything in its sight.
        #expect(TimelinePaint.builds(fromMS: 410_000, toMS: 420_000, stretch: stretch, isKept: false, lanePaints: false))
    }

    /// A sound whose shape has not been read yet is painted all the same,
    /// as the flat bar a full view draws while it waits, and the lane asks
    /// for the shape. Keeping such a clip a view was every clip of a long
    /// edit at the moment it opens: the 60 minute reference edit built about
    /// 430 bars and as many cuts, held the main thread for four seconds, and
    /// threw them all away when the shapes landed (2026-11-16).
    @Test func aSoundNotReadYetIsStillPainted() {
        var waiting = plain
        waiting.waveformMissing = true
        #expect(TimelinePaint.paints(waiting))
    }

    @Test func aPlainClipIsPainted() {
        #expect(TimelinePaint.paints(plain))
    }

    @Test func aClipSomebodyIsWorkingOnKeepsItsView() {
        var kept = plain
        kept.isKept = true
        #expect(!TimelinePaint.paints(kept))
    }

    /// Everything the full bar draws that the painting does not: each keeps
    /// the clip a view, so what the timeline shows never changes.
    @Test func whatThePaintingDoesNotDrawKeepsTheView() {
        let changes: [(inout TimelinePaint.Clip) -> Void] = [
            { $0.isPlainKind = false },
            { $0.pieceCount = 2 },
            { $0.isHeld = true },
            { $0.pictureHidden = true },
            { $0.hasBadge = true },
            { $0.hasKeys = true },
            { $0.hasDrift = true },
            { $0.levelHasPoints = true },
            { $0.soundHasBadge = true },
        ]
        for change in changes {
            var clip = plain
            change(&clip)
            #expect(!TimelinePaint.paints(clip))
        }
    }

    // MARK: - Laid against a fixed origin

    private static let hour = 60 * 60 * 1000

    private static func window(scale: Double, startMS: Double) -> MotionStripRuler {
        MotionStripRuler(documentMS: hour, zoom: TimelineZoom(scale: scale, startMS: startMS))
    }

    /// A scroll that stays inside one drawn stretch hands the painting the
    /// very same canvas, so it is slid along rather than painted again.
    @Test func aScrollInsideOneStretchKeepsTheSameCanvas() {
        let visible = Double(Self.hour) / 120
        let stretch = TimelineDrawnStretch(windowStartMS: 600_000, visibleMS: visible)
            .stretchMS(visibleMS: visible, documentMS: Double(Self.hour))
        let first = TimelinePaint.Canvas(drawnMS: stretch, ruler: Self.window(scale: 120, startMS: 600_000),
                                         laneWidth: 1200)
        for start in stride(from: 600_000.0, to: 600_000 + visible / 2, by: 997) {
            let later = TimelinePaint.Canvas(drawnMS: stretch, ruler: Self.window(scale: 120, startMS: start),
                                             laneWidth: 1200)
            #expect(later == first)
        }
    }

    /// Slid by its offset, every moment on the canvas lands where the
    /// window's own ruler puts it, to within a pixel.
    @Test func slidByItsOffsetEveryMomentLandsWhereTheWindowPutsIt() {
        let visible = Double(Self.hour) / 120
        let stretch = TimelineDrawnStretch(windowStartMS: 600_000, visibleMS: visible)
            .stretchMS(visibleMS: visible, documentMS: Double(Self.hour))
        for start in stride(from: 600_000.0, to: 600_000 + visible / 2, by: 1531) {
            let window = Self.window(scale: 120, startMS: start)
            let canvas = TimelinePaint.Canvas(drawnMS: stretch, ruler: window, laneWidth: 1200)
            let offset = canvas.offset(in: window, laneWidth: 1200, scale: 2)
            // On a pixel, so the painting never sits between two.
            #expect((offset * 2).rounded() == offset * 2)
            for ms in stride(from: stretch.lowerBound, through: stretch.upperBound, by: 4111) {
                let painted = 1200 * canvas.ruler.fraction(ofMS: ms) + offset
                let lane = 1200 * window.fraction(ofMS: ms)
                #expect(abs(painted - lane) <= 0.5)
            }
        }
    }

    @Test func theCanvasIsAsWideAsTheStretch() {
        let window = Self.window(scale: 4, startMS: 0)
        let canvas = TimelinePaint.Canvas(drawnMS: 1000...(1000 + window.spanMS * 2), ruler: window,
                                          laneWidth: 1000)
        #expect(abs(canvas.width - 2000) < 1e-6)
        #expect(canvas.ruler.startMS == 1000)
        #expect(canvas.ruler.spanMS == window.spanMS)
    }

    /// A name is kept in sight while its clip runs off the lane's left edge,
    /// which moves with every frame of a scroll: only a clip that may hang
    /// off it somewhere in this stretch has its name drawn against the
    /// window rather than the canvas.
    @Test func onlyAClipAcrossTheLeftEdgeHasItsNameFollowTheWindow() {
        let edge = 10_000.0...12_000.0
        #expect(TimelinePaint.nameFollowsTheEdge(fromMS: 9_000, toMS: 20_000, leftEdgeMS: edge))
        #expect(TimelinePaint.nameFollowsTheEdge(fromMS: 11_000, toMS: 20_000, leftEdgeMS: edge))
        #expect(!TimelinePaint.nameFollowsTheEdge(fromMS: 12_500, toMS: 20_000, leftEdgeMS: edge))
        #expect(!TimelinePaint.nameFollowsTheEdge(fromMS: 2_000, toMS: 9_500, leftEdgeMS: edge))
    }

    // MARK: While the timeline zooms

    /// Every frame of a zoom paints the canvas again, whatever it covers, so
    /// while the window's scale is changing the canvas is the window and a
    /// sliver either side, not the stretch two and a half windows wide.
    @Test func whileItZoomsTheCanvasIsTheWindow() {
        let window = Self.window(scale: 120, startMS: 600_000)
        let stretch = TimelineDrawnStretch(windowStartMS: 600_000, visibleMS: window.spanMS)
            .stretchMS(visibleMS: window.spanMS, documentMS: Double(Self.hour))
        let painted = TimelinePaint.paintedMS(window: window, stretch: stretch, isZooming: true)
        #expect(painted.lowerBound <= window.startMS)
        #expect(painted.upperBound >= window.startMS + window.spanMS)
        #expect(painted.upperBound - painted.lowerBound <= window.spanMS * 1.1)
        #expect(painted.upperBound - painted.lowerBound < (stretch.upperBound - stretch.lowerBound) / 2)
    }

    /// A scroll slides the stretch, which it paints only when it moves.
    @Test func whileItScrollsTheCanvasIsTheStretch() {
        let window = Self.window(scale: 120, startMS: 600_000)
        let stretch = TimelineDrawnStretch(windowStartMS: 600_000, visibleMS: window.spanMS)
            .stretchMS(visibleMS: window.spanMS, documentMS: Double(Self.hour))
        #expect(TimelinePaint.paintedMS(window: window, stretch: stretch, isZooming: false) == stretch)
    }

    /// A change of scale is a zoom; a move along at the same scale is not.
    @Test func aZoomIsAChangeOfScale() {
        let at = TimelineZoom(scale: 8, startMS: 10_000)
        #expect(TimelinePaint.isZoom(from: at, to: TimelineZoom(scale: 8.32, startMS: 9_000)))
        #expect(!TimelinePaint.isZoom(from: at, to: TimelineZoom(scale: 8, startMS: 19_000)))
    }
}
