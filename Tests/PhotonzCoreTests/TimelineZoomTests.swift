import Foundation
import PhotonzCore
import Testing

/// **Opening the timeline out** (`TimelineZoom.swift`,
/// `docs/design/video-surface.md`).
///
/// The timeline draws the whole document across whatever width the window
/// happens to be. Eight seconds fits and reads fine; five minutes, which is
/// what a real screen recording is, is a bar a few hundred points wide where
/// every cut is a guess. Zoom is the window moving: the ruler stops measuring
/// the whole document and measures the stretch you are working on instead.
///
/// Written before the change, which is the rule for `PhotonzCore`.
@Suite("Opening the timeline out")
struct TimelineZoomTests {

    /// A real screen recording.
    static let fiveMinutes: Double = 5 * 60 * 1000
    /// The sample everything else in the app is tested on.
    static let eightSeconds: Double = 8000

    // MARK: - Fit, which is what it has always done

    @Test func fitShowsTheWholeDocument() {
        let zoom = TimelineZoom.fit
        #expect(zoom.isFit)
        #expect(zoom.startMS == 0)
        #expect(zoom.visibleMS(documentMS: Self.fiveMinutes) == Self.fiveMinutes)
    }

    @Test func fitCannotBeZoomedOutFurther() {
        #expect(!TimelineZoom.fit.canZoomOut)
        let out = TimelineZoom.fit.steppedOut(anchorMS: 0, documentMS: Self.fiveMinutes)
        #expect(out == .fit)
    }

    // MARK: - How far in it goes

    @Test func fiveMinutesOpensOutFarEnoughToAimAtAWord() {
        // The whole claim, in numbers a person can check. At the widest, a
        // second of the recording is the whole width of the strip, so a word
        // of about a third of a second is a third of the strip. On a lane six
        // hundred points wide that is two hundred points: a cut can be put in
        // the middle of a word rather than near it.
        let widest = TimelineZoom(scale: TimelineZoom.widestScale(documentMS: Self.fiveMinutes))
        let visible = widest.visibleMS(documentMS: Self.fiveMinutes)
        #expect(visible == TimelineZoom.closestVisibleMS)
        let laneWidth = 600.0
        let pointsPerWord = laneWidth * (300 / visible)
        #expect(pointsPerWord > 100)
    }

    @Test func aShortRecordingIsNotOpenedOutPastItself() {
        // A document already shorter than the closest window has nothing to
        // open out INTO: zooming it in past its own length would draw a
        // timeline mostly made of nothing.
        let half = TimelineZoom.widestScale(documentMS: 500)
        #expect(half == 1)
    }

    @Test func eightSecondsStillZoomsEightTimes() {
        #expect(TimelineZoom.widestScale(documentMS: Self.eightSeconds) == 8)
    }

    // MARK: - Zooming keeps you where you were looking

    @Test func zoomingInKeepsThePlayheadWhereItIsOnScreen() {
        // The playhead sits two minutes in, which at fit is four tenths of the
        // way across. After a zoom it has to still be four tenths of the way
        // across: a zoom that jumped you to the start would make the control
        // useless, because the moment you are working on is the one you would
        // lose.
        let playhead = 120_000.0
        var zoom = TimelineZoom.fit
        for _ in 0..<4 {
            zoom = zoom.steppedIn(anchorMS: playhead, documentMS: Self.fiveMinutes)
            let span = zoom.visibleMS(documentMS: Self.fiveMinutes)
            let through = (playhead - zoom.startMS) / span
            #expect(abs(through - 0.4) < 0.001)
        }
    }

    @Test func zoomingOutKeepsThePlayheadWhereItIsToo() {
        let playhead = 120_000.0
        let inward = TimelineZoom.fit
            .steppedIn(anchorMS: playhead, documentMS: Self.fiveMinutes)
            .steppedIn(anchorMS: playhead, documentMS: Self.fiveMinutes)
        let back = inward.steppedOut(anchorMS: playhead, documentMS: Self.fiveMinutes)
        let span = back.visibleMS(documentMS: Self.fiveMinutes)
        #expect(abs((playhead - back.startMS) / span - 0.4) < 0.001)
    }

    @Test func zoomingInAtTheStartStaysAtTheStart() {
        // Nothing before nought to show, so the window stops at the edge
        // rather than drawing empty room.
        let zoom = TimelineZoom.fit.steppedIn(anchorMS: 0, documentMS: Self.fiveMinutes)
        #expect(zoom.startMS == 0)
    }

    @Test func zoomingInAtTheEndStaysAtTheEnd() {
        let zoom = TimelineZoom.fit.steppedIn(anchorMS: Self.fiveMinutes,
                                              documentMS: Self.fiveMinutes)
        let span = zoom.visibleMS(documentMS: Self.fiveMinutes)
        #expect(abs(zoom.startMS + span - Self.fiveMinutes) < 0.001)
    }

    @Test func zoomingAllTheWayBackOutLandsOnFit() {
        var zoom = TimelineZoom.fit
        for _ in 0..<12 { zoom = zoom.steppedIn(anchorMS: 90_000, documentMS: Self.fiveMinutes) }
        for _ in 0..<12 { zoom = zoom.steppedOut(anchorMS: 90_000, documentMS: Self.fiveMinutes) }
        #expect(zoom.isFit)
        #expect(zoom.startMS == 0)
    }

    // MARK: - The window never runs off either end

    @Test func theWindowIsAlwaysInsideTheDocument() {
        for scale in [1.0, 2.0, 9.0, 60.0, 300.0, 5000.0] {
            for start in [-90_000.0, 0, 42_000, 299_000, 900_000] {
                let zoom = TimelineZoom(scale: scale, startMS: start)
                    .clamped(documentMS: Self.fiveMinutes)
                let span = zoom.visibleMS(documentMS: Self.fiveMinutes)
                #expect(zoom.startMS >= 0)
                #expect(zoom.startMS + span <= Self.fiveMinutes + 0.001)
                #expect(zoom.scale >= 1)
            }
        }
    }

    @Test func panningStopsAtTheEnds() {
        let zoom = TimelineZoom(scale: 10).clamped(documentMS: Self.fiveMinutes)
        #expect(zoom.panned(byMS: -100_000, documentMS: Self.fiveMinutes).startMS == 0)
        let far = zoom.panned(byMS: 900_000, documentMS: Self.fiveMinutes)
        #expect(abs(far.startMS + far.visibleMS(documentMS: Self.fiveMinutes) - Self.fiveMinutes) < 0.001)
    }

    // MARK: - Playing does not leave the playhead behind

    @Test func aPlayheadAlreadyOnScreenMovesNothing() {
        let zoom = TimelineZoom(scale: 10, startMS: 60_000).clamped(documentMS: Self.fiveMinutes)
        #expect(zoom.revealing(ms: 62_000, documentMS: Self.fiveMinutes) == zoom)
    }

    @Test func aPlayheadThatRanOffTheEndBringsTheWindowWithIt() {
        let zoom = TimelineZoom(scale: 10, startMS: 60_000).clamped(documentMS: Self.fiveMinutes)
        let span = zoom.visibleMS(documentMS: Self.fiveMinutes)
        let ahead = zoom.startMS + span + 500
        let moved = zoom.revealing(ms: ahead, documentMS: Self.fiveMinutes)
        #expect(moved.contains(ms: ahead, documentMS: Self.fiveMinutes))
        #expect(moved.scale == zoom.scale)
        // It PAGES rather than creeping: the playhead lands near the left hand
        // edge, so what is about to happen is on screen rather than arriving
        // one frame at a time under the pointer.
        let through = (ahead - moved.startMS) / span
        #expect(through < 0.25)
    }

    @Test func scrubbingBackwardsBringsTheWindowBack() {
        let zoom = TimelineZoom(scale: 10, startMS: 60_000).clamped(documentMS: Self.fiveMinutes)
        let behind = 20_000.0
        let moved = zoom.revealing(ms: behind, documentMS: Self.fiveMinutes)
        #expect(moved.contains(ms: behind, documentMS: Self.fiveMinutes))
    }

    @Test func revealingNeverLeavesTheDocument() {
        let zoom = TimelineZoom(scale: 10).clamped(documentMS: Self.fiveMinutes)
        let moved = zoom.revealing(ms: Self.fiveMinutes, documentMS: Self.fiveMinutes)
        let span = moved.visibleMS(documentMS: Self.fiveMinutes)
        #expect(moved.startMS >= 0)
        #expect(moved.startMS + span <= Self.fiveMinutes + 0.001)
    }

    // MARK: - What it says it is showing

    @Test func itSaysWhichStretchIsOnScreen() {
        let zoom = TimelineZoom(scale: 10, startMS: 60_000).clamped(documentMS: Self.fiveMinutes)
        #expect(zoom.reading(documentMS: Self.fiveMinutes) == "1:00 to 1:30")
    }

    @Test func fitSaysTheWholeThing() {
        #expect(TimelineZoom.fit.reading(documentMS: Self.fiveMinutes) == "all 5:00")
    }

    // MARK: - The ruler measures the window

    @Test func aZoomedRulerMeasuresTheWindowAndNotTheDocument() {
        let zoom = TimelineZoom(scale: 10, startMS: 60_000).clamped(documentMS: Self.fiveMinutes)
        let ruler = MotionStripRuler(documentMS: Int(Self.fiveMinutes), zoom: zoom)
        #expect(ruler.startMS == 60_000)
        #expect(ruler.spanMS == 30_000)
        #expect(ruler.fraction(ofMS: 60_000) == 0)
        #expect(abs(ruler.fraction(ofMS: 90_000) - 1) < 0.0001)
        #expect(abs(ruler.fraction(ofMS: 75_000) - 0.5) < 0.0001)
        #expect(ruler.ms(atFraction: 0.5) == 75_000)
    }

    @Test func aDurationIsMeasuredAsALengthAndNotAsAMoment() {
        // The one trap in windowing the ruler: half the strip asks where a
        // moment falls and the other half asks how wide a length is. A length
        // must not have the window's start taken off it, or every bar on a
        // zoomed timeline comes out the wrong size.
        let zoom = TimelineZoom(scale: 10, startMS: 60_000).clamped(documentMS: Self.fiveMinutes)
        let ruler = MotionStripRuler(documentMS: Int(Self.fiveMinutes), zoom: zoom)
        #expect(ruler.fraction(spanningMS: 30_000) == 1)
        #expect(ruler.fraction(spanningMS: 15_000) == 0.5)
        #expect(ruler.msSpanning(fraction: 0.5) == 15_000)
    }

    @Test func anUnzoomedRulerIsExactlyWhatItAlwaysWas() {
        let plain = MotionStripRuler(documentMS: 5000)
        let fitted = MotionStripRuler(documentMS: 5000, zoom: .fit)
        #expect(plain.startMS == 0)
        #expect(fitted.spanMS == plain.spanMS)
        #expect(fitted.fraction(ofMS: 2500) == plain.fraction(ofMS: 2500))
        #expect(fitted.ticks == plain.ticks)
    }

    @Test func aLapIsNeverWindowed() {
        // An icon's ruler measures a lap and a third and has no zoom: there is
        // nothing to open out, because ninety milliseconds already fills the
        // width.
        let lap = MotionStripRuler(cycleMS: 900)
        #expect(lap.startMS == 0)
    }

    // MARK: - The numbers along the top

    @Test func aZoomedRulerNumbersTheWindow() {
        let zoom = TimelineZoom(scale: 10, startMS: 60_000).clamped(documentMS: Self.fiveMinutes)
        let ruler = MotionStripRuler(documentMS: Int(Self.fiveMinutes), zoom: zoom)
        let ticks = ruler.ticks
        #expect(ticks.count >= 3)
        for tick in ticks {
            #expect(tick.ms >= 60_000)
            #expect(tick.ms <= 90_000)
        }
        // Round numbers, not "1:00 1:03 1:06": the step is chosen off the
        // ladder, so a zoomed ruler reads as easily as the whole one does.
        #expect(ticks.first?.label == "1:00")
    }

    @Test func aRulerOpenedRightOutCountsInTenths() {
        // A second across the width with every number reading "0:12" would be
        // a row of the same number five times over.
        let zoom = TimelineZoom(scale: 300, startMS: 12_000).clamped(documentMS: Self.fiveMinutes)
        let ruler = MotionStripRuler(documentMS: Int(Self.fiveMinutes), zoom: zoom)
        let labels = ruler.ticks.map(\.label)
        #expect(Set(labels).count == labels.count)
        #expect(labels.contains { $0.contains(".") })
    }

    // MARK: - What is drawn when a bar runs off the side

    @Test func aBarThatRunsOffTheSideIsDrawnOnlyWhereItShows() {
        // At three hundred times, a five minute clip's bar is a hundred and
        // eighty thousand points wide. Nobody can see it and a waveform
        // sampled across it is a hundred and eighty thousand columns, so what
        // is drawn is the part in the window plus enough slack to keep its
        // rounded ends and its edges off screen.
        let drawn = TimelineSpan.drawn(x: -90_000, width: 180_000, across: 600)
        #expect(drawn.x < 0)
        #expect(drawn.x > -200)
        #expect(drawn.width < 1200)
        #expect(drawn.x + drawn.width > 600)
    }

    @Test func aBarWhollyOnScreenIsDrawnWholeAndUnchanged() {
        let drawn = TimelineSpan.drawn(x: 40, width: 200, across: 600)
        #expect(drawn.x == 40)
        #expect(drawn.width == 200)
    }

    @Test func aBarWhollyOffScreenIsNotDrawnAtAll() {
        #expect(TimelineSpan.drawn(x: 4000, width: 200, across: 600).width == 0)
        #expect(TimelineSpan.drawn(x: -4000, width: 200, across: 600).width == 0)
    }

    @Test func whatIsCutOffTheFrontIsSaidAsAFraction() {
        // The waveform inside a clipped piece has to be sampled from the part
        // of the FILE that is still on screen, which is the same fraction of
        // the piece that survived the clipping.
        let drawn = TimelineSpan.drawn(x: -1000, width: 2000, across: 600)
        #expect(drawn.startFraction > 0.4)
        #expect(drawn.startFraction < 0.6)
        #expect(drawn.endFraction > drawn.startFraction)
        #expect(drawn.endFraction <= 1)
    }
}
