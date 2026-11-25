import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The ruler a busy lane lays out against while the timeline moves, and how
/// the lane is slid and stretched to the window (`TimelineLaneFrame`).
@Suite struct TimelineLaneFrameTests {
    private let hour = 3_600_000

    private func window(scale: Double, startMS: Double) -> MotionStripRuler {
        MotionStripRuler(documentMS: hour, zoom: TimelineZoom(scale: scale, startMS: startMS)
            .clamped(documentMS: Double(hour)))
    }

    /// Where a moment lands across the lane, laid against `frame` and slid
    /// to `window`, against where the window itself puts it.
    private func lands(_ ms: Double, frame: TimelineLaneFrame, window: MotionStripRuler,
                       laneWidth: CGFloat = 1463) -> (slid: CGFloat, true: CGFloat) {
        let x = laneWidth * CGFloat(frame.ruler.fraction(ofMS: ms))
        let slid = frame.windowX(ofFrameX: x, window: window, laneWidth: laneWidth, scale: 1)
        return (slid, laneWidth * CGFloat(window.fraction(ofMS: ms)))
    }

    /// The first frame of a hold lays out exactly as the zoom frame before
    /// it, so nothing is built again for it.
    @Test func aHoldBeginsWhereTheFreshFrameLeftOff() {
        let painted = window(scale: 2, startMS: 600_000)
        let edge = 500_000.0...700_000.0
        #expect(TimelineLaneFrame.zooming(painted, leftEdgeMS: edge, zoomScale: 2)
                == TimelineLaneFrame.holding(painted, leftEdgeMS: edge, zoomScale: 2))
    }

    /// A hold begun from a lane at rest that painted the drawn stretch (after
    /// a scroll, or as a file opens) keeps that stretch as its painting and
    /// its bars' stretch, so the first frame of the zoom paints nothing again
    /// and lays no new picture: the at-rest lane, stretched (pass 23).
    @Test func aHoldFromRestKeepsTheStretchTheLanePainted() {
        let rest = window(scale: 1, startMS: 0)
        let stretch = 0.0...7_200_000
        let frame = TimelineLaneFrame.holding(rest, leftEdgeMS: 0...3_600_000, zoomScale: 1, painted: stretch)
        #expect(frame.ruler == rest)
        #expect(frame.paintedMS == stretch)
        #expect(frame.drawnMS == stretch)
        #expect(frame.sightMargin == TimelineSight.margin)
        #expect(frame.isZoom)
        // Without one, the window and its sliver, as a fresh zoom frame paints.
        let plain = TimelineLaneFrame.holding(rest, leftEdgeMS: 0...0, zoomScale: 1)
        #expect(plain.paintedMS == TimelinePaint.paintedMS(window: rest, stretch: 0...0, isZooming: true))
    }

    /// A zoom's frames say they are a zoom's and a scroll's say they are not:
    /// a lane's picture moving to a new canvas on a zoom shows the last one
    /// for the frame the new one takes to lay, and on a scroll's step lays
    /// at once (`TimelinePaintedPicture`, pass 23).
    @Test func aZoomsFrameSaysItIsAZoom() {
        let now = window(scale: 2, startMS: 600_000)
        #expect(TimelineLaneFrame.holding(now, leftEdgeMS: 0...0, zoomScale: 2).isZoom)
        #expect(TimelineLaneFrame.zooming(now, leftEdgeMS: 0...0, zoomScale: 2).isZoom)
        #expect(!TimelineLaneFrame.scrolling(now, anchorMS: 590_000, drawnMS: 560_000...1_490_000,
                                             leftEdgeMS: 590_000...1_000_000, zoomScale: 2).isZoom)
    }

    /// Every moment slid and stretched from a held frame lands where the
    /// window puts it, to well inside a point: time across a lane is linear.
    @Test func aHeldFrameStretchedLandsWhereTheWindowPutsIt() {
        let painted = window(scale: 2, startMS: 600_000)
        let frame = TimelineLaneFrame.holding(painted, leftEdgeMS: 0...0, zoomScale: 2)
        let now = window(scale: 2.16, startMS: 640_000)
        for ms in stride(from: 600_000.0, through: 2_400_000, by: 37_000) {
            let (slid, truth) = lands(ms, frame: frame, window: now)
            #expect(abs(slid - truth) <= 0.5)
        }
        let (stretch, _) = frame.slide(to: now, laneWidth: 1463, scale: 2)
        #expect(abs(stretch - 2.16 / 2) < 1e-9)
    }

    /// A scroll's frame keeps the window's scale, so it is only slid, never
    /// stretched, and the slide lands on a whole pixel.
    @Test func aZoomsFrameStandsAStepPastWhatAHoldIsLet() {
        let window = MotionStripRuler(documentMS: 100_000, zoom: TimelineZoom(scale: 4, startMS: 30_000))
        let frame = TimelineLaneFrame.zooming(window, leftEdgeMS: 0...1, zoomScale: 4)
        func zoomed(_ by: Double) -> MotionStripRuler {
            let span = window.spanMS / by
            return MotionStripRuler(documentMS: 100_000,
                                    zoom: TimelineZoom(scale: 4 * by, startMS: 30_000 + (window.spanMS - span) / 2))
        }
        #expect(frame.stands(for: window))
        for by in [1.2, 0.84] {
            #expect(TimelinePaint.stretch(painted: window, to: zoomed(by), heldForMS: 0) == nil)
            #expect(frame.stands(for: zoomed(by)), "\(by)")
        }
        // Past what is painted, or stretched too far, it does not.
        for by in [1.5, 0.7] { #expect(!frame.stands(for: zoomed(by)), "\(by)") }
        let scrolled = TimelineLaneFrame.scrolling(window, anchorMS: 20_000, drawnMS: 0...90_000,
                                                   leftEdgeMS: 0...1, zoomScale: 4)
        // A scroll's covers any window its painting and what it built reach,
        // at its own scale.
        #expect(scrolled.stands(for: window))
        #expect(!scrolled.stands(for: zoomed(1.04)))
        let past = MotionStripRuler(documentMS: 100_000, zoom: TimelineZoom(scale: 4, startMS: 70_000))
        #expect(!scrolled.stands(for: past))
    }

    private let rest = TimelineLaneFrame.resting(
        MotionStripRuler(documentMS: 100_000, zoom: TimelineZoom(scale: 4, startMS: 30_000)),
        painted: 0...100_000, drawnMS: 0...100_000, leftEdgeMS: 25_000...50_000, zoomScale: 4)

    private func at(_ startMS: Double, scale: Double = 4) -> MotionStripRuler {
        MotionStripRuler(documentMS: 100_000, zoom: TimelineZoom(scale: scale, startMS: startMS))
    }

    private func scrollFrame(_ startMS: Double) -> TimelineLaneFrame {
        TimelineLaneFrame.scrolling(at(startMS), anchorMS: 25_000, drawnMS: 0...100_000,
                                    leftEdgeMS: 25_000...50_000, zoomScale: 4)
    }

    /// A scroll that begins lays no lane out again on its first frame, and
    /// one group on each after it: each stands on its layout at rest, slid.
    @Test func aScrollTakesItsLanesAGroupAFrame() {
        var waves = TimelineLaneWaves()
        for step in 0...TimelineLaneWaves.groupCount {
            let start = 30_000 + Double(step) * 500
            waves.step(to: scrollFrame(start), window: at(start), rest: rest)
            #expect(waves.groups.count { $0 != nil } == step)
        }
        #expect(!waves.someRest)
        // Slid a little, the resting layout lands where the window puts it.
        let (stretch, offset) = rest.slide(to: at(31_000), laneWidth: 1000, scale: 2)
        #expect(stretch == 1)
        #expect(offset == -40)
    }

    /// Scrolled past what the layout at rest covers, every lane goes at once:
    /// none is ever slid to show what it never built.
    @Test func aScrollPastTheLayoutAtRestTakesEveryLane() {
        var waves = TimelineLaneWaves()
        waves.step(to: scrollFrame(60_000), window: at(60_000), rest: rest)
        #expect(!waves.someRest)
    }

    /// A zoom that begins holds the painting at rest, so no lane is laid out
    /// for it; its first fresh frame is taken by half, and by the rest a step
    /// later.
    @Test func aZoomTakesItsLanesInHalves() {
        var waves = TimelineLaneWaves()
        let held = TimelineLaneFrame.holding(rest.ruler, leftEdgeMS: 0...1, zoomScale: 4, painted: rest.paintedMS)
        for scale in [4.16, 4.3] {
            let window = at(30_300, scale: scale)
            waves.step(to: held, window: window, rest: rest)
            #expect(waves.groups.allSatisfy { $0 == nil })
        }
        let fresh = at(30_500, scale: 4.5)
        let zooming = TimelineLaneFrame.zooming(fresh, leftEdgeMS: 0...1, zoomScale: 4.5)
        waves.step(to: zooming, window: fresh, rest: rest)
        #expect(waves.groups.count { $0 == zooming } == TimelineLaneWaves.groupCount / 2)
        waves.step(to: zooming, window: at(30_600, scale: 4.6), rest: rest)
        #expect(waves.groups.allSatisfy { $0 == zooming })
    }

    /// Whatever the steps, every group stands on a layout that covers the
    /// window it is slid to.
    @Test func everyGroupCoversTheWindowAtEveryStep() {
        var waves = TimelineLaneWaves()
        var start = 30_000.0
        for step in 0..<60 {
            start += step % 7 == 0 ? 6_000 : 700
            if start > 60_000 { start = 26_000 }
            let window = at(start)
            let stretch = TimelineDrawnStretch(windowStartMS: start, visibleMS: 25_000, stepShare: 0.5)
            let edge = stretch.leftEdgeMS(visibleMS: 25_000, documentMS: 100_000)
            let frame = TimelineLaneFrame.scrolling(window, anchorMS: edge.lowerBound,
                                                    drawnMS: stretch.stretchMS(visibleMS: 25_000, documentMS: 100_000),
                                                    leftEdgeMS: edge, zoomScale: 4)
            waves.step(to: frame, window: window, rest: rest)
            for group in waves.groups {
                #expect((group ?? rest).stands(for: window), "step \(step)")
            }
        }
    }

    /// At rest the groups go back one after another, and the newest frame is
    /// let go at once.
    @Test func theLanesComeToRestAGroupAtATime() {
        var waves = TimelineLaneWaves()
        waves.step(to: scrollFrame(60_000), window: at(60_000), rest: rest)
        var rests = 1
        while waves.restNext() { rests += 1 }
        #expect(rests == TimelineLaneWaves.groupCount)
        #expect(waves.frame == nil)
        #expect(waves.groups.allSatisfy { $0 == nil })
    }

    @Test func aScrollIsSlidNotStretched() {
        let now = window(scale: 120, startMS: 1_000_000)
        let frame = TimelineLaneFrame.scrolling(now, anchorMS: 990_000, drawnMS: 960_000...1_090_000,
                                                leftEdgeMS: 990_000...1_020_000, zoomScale: 120)
        let (stretch, offset) = frame.slide(to: now, laneWidth: 1463, scale: 2)
        #expect(stretch == 1)
        #expect((offset * 2).rounded() == offset * 2)
        let (slid, truth) = lands(1_005_000, frame: frame, window: now)
        #expect(abs(slid - truth) <= 0.5)
    }

    /// A scroll's frame holds still while the window moves anywhere its
    /// stretch allows, and builds far enough either side for every one of
    /// those windows to have half a window built past each edge.
    @Test func aScrollFrameSeesEveryWindowInsideItsStretch() {
        let visible = 30_000.0
        let stretch = TimelineDrawnStretch(windowStartMS: 1_000_000, visibleMS: visible, stepShare: 1)
        let edge = stretch.leftEdgeMS(visibleMS: visible, documentMS: Double(hour))
        let drawn = stretch.stretchMS(visibleMS: visible, documentMS: Double(hour))
        let scale = Double(hour) / visible
        let frames = stride(from: edge.lowerBound, to: edge.upperBound, by: 2_500).map { start in
            TimelineLaneFrame.scrolling(window(scale: scale, startMS: start), anchorMS: edge.lowerBound,
                                        drawnMS: drawn, leftEdgeMS: edge, zoomScale: scale)
        }
        #expect(Set(frames).count == 1)
        let sight = TimelineSight(ruler: frames[0].ruler, margin: frames[0].sightMargin)
        for start in stride(from: edge.lowerBound, to: edge.upperBound, by: 2_500) {
            let own = TimelineSight(ruler: window(scale: scale, startMS: start))
            #expect(sight.fromMS <= own.fromMS + 1e-6)
            #expect(sight.toMS >= own.toMS - 1e-6)
        }
    }

    /// A point read across the lane as the window has it goes to the frame
    /// and back unchanged.
    @Test func aPointGoesToTheFrameAndBack() {
        let frame = TimelineLaneFrame.holding(window(scale: 3, startMS: 400_000), leftEdgeMS: 0...0, zoomScale: 3)
        let now = window(scale: 3.2, startMS: 410_000)
        for x in stride(from: CGFloat(0), through: 1463, by: 97) {
            let there = frame.frameX(ofWindowX: x, window: now, laneWidth: 1463, scale: 2)
            let back = frame.windowX(ofFrameX: there, window: now, laneWidth: 1463, scale: 2)
            #expect(abs(back - x) < 1e-6)
        }
    }
}
