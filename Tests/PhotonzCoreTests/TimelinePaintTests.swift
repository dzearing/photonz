import Foundation
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

    /// A picture laid on one canvas, shown on the next for the one frame its
    /// own picture takes to lay, puts every moment where the new canvas has
    /// it: zoomed in, zoomed out, and stepped along by a scroll.
    @Test func aPictureLaidOnOneCanvasLandsWhereTheNextHasEveryMoment() {
        let laneWidth: CGFloat = 1463
        let old = TimelinePaint.Canvas(drawnMS: 600_000...1_500_000, ruler: Self.window(scale: 4, startMS: 600_000),
                                       laneWidth: laneWidth)
        let next = [
            TimelinePaint.Canvas(drawnMS: 650_000...1_400_000, ruler: Self.window(scale: 4.7, startMS: 650_000),
                                 laneWidth: laneWidth),
            TimelinePaint.Canvas(drawnMS: 500_000...1_700_000, ruler: Self.window(scale: 3.4, startMS: 500_000),
                                 laneWidth: laneWidth),
            TimelinePaint.Canvas(drawnMS: 900_000...1_800_000, ruler: Self.window(scale: 4, startMS: 900_000),
                                 laneWidth: laneWidth),
        ]
        for canvas in next {
            let place = canvas.place(ofPictureLaidOn: old, laneWidth: laneWidth)
            for ms in stride(from: 600_000.0, through: 1_500_000, by: 37_000) {
                let onOld = laneWidth * old.ruler.fraction(ofMS: ms)
                let shown = place.x + onOld * place.stretch
                let onNew = laneWidth * canvas.ruler.fraction(ofMS: ms)
                #expect(abs(shown - onNew) < 1e-6)
            }
        }
        // The same canvas shows it as it was laid.
        let same = old.place(ofPictureLaidOn: old, laneWidth: laneWidth)
        #expect(same.x == 0 && same.stretch == 1)
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

    /// While a zoom paints only the window, the painting is held no longer
    /// than `stretch` allows, so the left edge can reach no further than a
    /// sliver before where it was painted and a ninth of a window after:
    /// that, not a whole step of the drawn stretch, is where a name may be
    /// pushed. Near the whole-hour view every clip in the window had its
    /// name drawn on every frame of a zoom (2026-11-20).
    @Test func whileItZoomsOnlyANameNearTheLeftEdgeFollowsIt() {
        let window = Self.window(scale: 2, startMS: 900_000)
        let reach = TimelinePaint.leftEdgeWhileZooming(window: window)
        #expect(reach.lowerBound < window.startMS)
        #expect(reach.upperBound > window.startMS)
        #expect(reach.upperBound - reach.lowerBound < window.spanMS / 3)
        // A clip in the middle of the window never meets the edge.
        let middle = window.startMS + window.spanMS / 2
        #expect(!TimelinePaint.nameFollowsTheEdge(fromMS: middle, toMS: middle + 10_000, leftEdgeMS: reach))
        // The clip across the edge does.
        #expect(TimelinePaint.nameFollowsTheEdge(fromMS: window.startMS - 5_000, toMS: window.startMS + 5_000,
                                                 leftEdgeMS: reach))
    }

    /// Every window a held painting is stretched to has its left edge inside
    /// the reach the painting was laid for, in and out, about any anchor.
    @Test func everyWindowAHeldPaintingStandsForHasItsEdgeInReach() {
        let painted = Self.window(scale: 2, startMS: 900_000)
        let reach = TimelinePaint.leftEdgeWhileZooming(window: painted)
        var checked = 0
        for anchorShare in stride(from: 0.0, through: 1.0, by: 0.05) {
            let anchor = painted.startMS + painted.spanMS * anchorShare
            for by in stride(from: 0.8, through: 1.2, by: 0.0025) {
                let window = Self.window(scale: 2 * by,
                                         startMS: anchor - (anchor - painted.startMS) / by)
                for shift in stride(from: -0.05, through: 0.05, by: 0.01) {
                    let moved = Self.window(scale: 2 * by, startMS: window.startMS + painted.spanMS * shift)
                    guard TimelinePaint.stretch(painted: painted, to: moved, heldForMS: 0) != nil else { continue }
                    checked += 1
                    #expect(reach.contains(moved.startMS), "edge \(moved.startMS) outside \(reach)")
                }
            }
        }
        #expect(checked > 100)
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
        #expect(painted.upperBound - painted.lowerBound <= window.spanMS * 1.2)
        #expect(painted.upperBound - painted.lowerBound < (stretch.upperBound - stretch.lowerBound) / 2)
    }

    /// A scroll slides the stretch, which it paints only when it moves.
    @Test func whileItScrollsTheCanvasIsTheStretch() {
        let window = Self.window(scale: 120, startMS: 600_000)
        let stretch = TimelineDrawnStretch(windowStartMS: 600_000, visibleMS: window.spanMS)
            .stretchMS(visibleMS: window.spanMS, documentMS: Double(Self.hour))
        #expect(TimelinePaint.paintedMS(window: window, stretch: stretch, isZooming: false) == stretch)
    }

    // MARK: A painting held through a zoom

    /// A zoom a step at a time keeps the last painting, stretched to the new
    /// scale, while the stretch is slight and the painting still covers the
    /// window: every clip lands where it belongs, since time across the lane
    /// is linear, and only a name or a corner is a few per cent wider for a
    /// frame (2026-11-19).
    @Test func aSlightZoomStretchesThePaintingItHolds() {
        let painted = Self.window(scale: 2, startMS: 900_000)
        let anchor = painted.startMS + painted.spanMS / 2
        let inStep = Self.window(scale: 2 * 1.04, startMS: anchor - painted.spanMS / 1.04 / 2)
        let outStep = Self.window(scale: 2 / 1.04, startMS: anchor - painted.spanMS * 1.04 / 2)
        let stretchIn = TimelinePaint.stretch(painted: painted, to: inStep, heldForMS: 200)
        let stretchOut = TimelinePaint.stretch(painted: painted, to: outStep, heldForMS: 200)
        #expect(stretchIn.map { abs($0 - 1.04) < 1e-9 } == true)
        #expect(stretchOut.map { abs($0 - 1 / 1.04) < 1e-9 } == true)
    }

    /// Two steps of four per cent in are still held; three are too far, and
    /// it is painted again.
    @Test func aZoomPastTheHeldStretchPaintsAgain() {
        let painted = Self.window(scale: 2, startMS: 900_000)
        let anchor = painted.startMS + painted.spanMS / 2
        func steps(_ n: Int) -> MotionStripRuler {
            let by = pow(1.04, Double(n))
            return Self.window(scale: 2 * by, startMS: anchor - painted.spanMS / by / 2)
        }
        #expect(TimelinePaint.stretch(painted: painted, to: steps(2), heldForMS: 200) != nil)
        #expect(TimelinePaint.stretch(painted: painted, to: steps(3), heldForMS: 200) == nil)
    }

    /// A quick zoom holds its painting twice as far, for as long as a quick
    /// zoom takes to get there: four steps of four per cent in and three out,
    /// inside the first fifty milliseconds. A slow zoom that has held one
    /// painting longer than that goes back to the slight stretch, so a name
    /// is never seen growing a sixth wider and springing back. Near Fit on
    /// the hour-long reference edit the frames that paint afresh are the late
    /// ones: holding four of five instead of two of three took the mean
    /// frame from 11.5 to 10.5-11.1 ms and the late frames from 239-293 of
    /// 648 to 166-194 (2026-11-21).
    @Test func aQuickZoomHoldsItsPaintingFurther() {
        let painted = Self.window(scale: 2, startMS: 900_000)
        let anchor = painted.startMS + painted.spanMS / 2
        func steps(_ n: Int) -> MotionStripRuler {
            let by = pow(1.04, Double(n))
            return Self.window(scale: 2 * by, startMS: anchor - painted.spanMS / by / 2)
        }
        #expect(TimelinePaint.stretch(painted: painted, to: steps(4), heldForMS: 35) != nil)
        #expect(TimelinePaint.stretch(painted: painted, to: steps(4), heldForMS: 80) == nil)
        #expect(TimelinePaint.stretch(painted: painted, to: steps(5), heldForMS: 0) == nil)
        #expect(TimelinePaint.stretch(painted: painted, to: steps(-3), heldForMS: 35) != nil)
        #expect(TimelinePaint.stretch(painted: painted, to: steps(-4), heldForMS: 35) == nil)
    }

    /// A zoom out about the window's left edge uncovers more on the right
    /// than the painting's sliver reaches: it is painted again rather than
    /// showing an unpainted strip.
    @Test func aWindowPastWhatWasPaintedPaintsAgain() {
        let painted = Self.window(scale: 2, startMS: 900_000)
        let out = Self.window(scale: 2 / 1.1, startMS: painted.startMS)
        #expect(TimelinePaint.stretch(painted: painted, to: out, heldForMS: 0) == nil)
        let along = Self.window(scale: 2, startMS: painted.startMS + painted.spanMS / 8)
        #expect(TimelinePaint.stretch(painted: painted, to: along, heldForMS: 0) == nil)
    }

    /// A change of scale is a zoom; a move along at the same scale is not.
    @Test func aZoomIsAChangeOfScale() {
        let at = TimelineZoom(scale: 8, startMS: 10_000)
        #expect(TimelinePaint.isZoom(from: at, to: TimelineZoom(scale: 8.32, startMS: 9_000)))
        #expect(!TimelinePaint.isZoom(from: at, to: TimelineZoom(scale: 8, startMS: 19_000)))
    }

    // MARK: Gaps

    /// A painting lane paints its gaps and builds a view only for the gap
    /// under the pointer, for its press and right-click menu: near the
    /// whole-hour view of the reference edit about seventy gaps were each a
    /// striped canvas, a dashed edge, a press and a menu, rebuilt on every
    /// frame of a zoom, about 5 ms of it (2026-11-17).
    @Test func aPaintingLaneBuildsOnlyTheGapUnderThePointer() {
        let track = UUID()
        let gaps = [TimelineGap(trackID: track, range: 0..<1_000),
                    TimelineGap(trackID: track, range: 5_000..<6_000),
                    TimelineGap(trackID: track, range: 9_000..<9_500)]
        #expect(TimelinePaint.gapViews(gaps, lanePaints: false, pointerGapMS: nil) == gaps)
        #expect(TimelinePaint.gapViews(gaps, lanePaints: false, pointerGapMS: 5_000) == gaps)
        #expect(TimelinePaint.gapViews(gaps, lanePaints: true, pointerGapMS: nil).isEmpty)
        #expect(TimelinePaint.gapViews(gaps, lanePaints: true, pointerGapMS: 5_000) == [gaps[1]])
        // A gap that closed under the pointer builds nothing.
        #expect(TimelinePaint.gapViews(gaps, lanePaints: true, pointerGapMS: 7_000).isEmpty)
    }

    /// Every gap reaching the drawn stretch is painted, as every clip is.
    @Test func aPaintingLanePaintsEveryGapOnTheStretch() {
        let track = UUID()
        let gaps = [TimelineGap(trackID: track, range: 0..<1_000),
                    TimelineGap(trackID: track, range: 5_000..<6_000),
                    TimelineGap(trackID: track, range: 9_000..<9_500)]
        #expect(TimelinePaint.paintedGaps(gaps, stretch: 900...5_000) == [gaps[0], gaps[1]])
        #expect(TimelinePaint.paintedGaps(gaps, stretch: 1_200...4_800).isEmpty)
        #expect(TimelinePaint.paintedGaps(gaps, stretch: 0...10_000) == gaps)
    }

    /// The gap a point along the lane is in, ends included.
    @Test func theGapUnderAPoint() {
        let track = UUID()
        let gaps = [TimelineGap(trackID: track, range: 0..<1_000),
                    TimelineGap(trackID: track, range: 5_000..<6_000)]
        #expect(TimelinePaint.gap(atMS: 500, in: gaps) == gaps[0])
        #expect(TimelinePaint.gap(atMS: 6_000, in: gaps) == gaps[1])
        #expect(TimelinePaint.gap(atMS: 5_000, in: gaps) == gaps[1])
        #expect(TimelinePaint.gap(atMS: 3_000, in: gaps) == nil)
    }
}
