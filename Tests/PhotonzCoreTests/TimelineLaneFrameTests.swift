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
