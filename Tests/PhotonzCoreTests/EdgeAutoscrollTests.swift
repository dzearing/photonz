import CoreGraphics
import PhotonzCore
import Testing

/// A drag held near the edge of a view that scrolls: the timeline's box, a
/// clip, a zoom bar or a track carried by its header. It starts gently just
/// inside the edge and gathers speed towards it, and never jumps.
struct EdgeAutoscrollTests {

    let edge = EdgeAutoscroll(band: 40, topSpeed: 1000)

    @Test func nothingScrollsAwayFromTheEdges() {
        #expect(edge.depth(at: 200, along: 800) == 0)
        #expect(edge.speed(at: 200, along: 800) == 0)
        // The band's inner edge itself is still nought.
        #expect(edge.speed(at: 40, along: 800) == 0)
        #expect(edge.speed(at: 760, along: 800) == 0)
    }

    @Test func theNearEdgeScrollsBackAndTheFarEdgeOn() {
        #expect(edge.speed(at: 10, along: 800) < 0)
        #expect(edge.speed(at: 790, along: 800) > 0)
        // The same depth either side is the same speed.
        #expect(edge.speed(at: 10, along: 800) == -edge.speed(at: 790, along: 800))
    }

    @Test func topSpeedOnlyAtOrPastTheEdge() {
        #expect(edge.speed(at: 800, along: 800) == 1000)
        #expect(edge.speed(at: 0, along: 800) == -1000)
        // Past the edge, even far outside the window, it holds top speed.
        #expect(edge.speed(at: 1400, along: 800) == 1000)
        #expect(edge.speed(at: -500, along: 800) == -1000)
        #expect(edge.speed(at: 799, along: 800) < 1000)
    }

    @Test func itStartsGentlyAcrossTheInnerHalfOfTheBand() {
        // Well under a fifth of top speed anywhere in the inner half.
        for step in 0...20 {
            let position = 760 + 20 * CGFloat(step) / 20
            #expect(edge.speed(at: position, along: 800) <= 0.13 * 1000)
        }
    }

    @Test func itNeverSlowsAsThePointerNearsTheEdge() {
        var last: CGFloat = 0
        for x in stride(from: CGFloat(760), through: 820, by: 1) {
            let speed = edge.speed(at: x, along: 800)
            #expect(speed >= last)
            last = speed
        }
    }

    @Test func aViewTooSmallForTwoBandsNeverScrolls() {
        #expect(edge.speed(at: 2, along: 70) == 0)
        #expect(edge.speed(at: 68, along: 70) == 0)
    }

    @Test func travelIsSpeedTimesTheFrame() {
        let travel = edge.travel(at: 800, along: 800, seconds: 1.0 / 60)
        #expect(abs(travel - 1000.0 / 60) < 0.001)
        #expect(edge.travel(at: 400, along: 800, seconds: 1) == 0)
    }

    @Test func aScrollLandsInsideTheContent() {
        // Already at the end: nothing more to go.
        #expect(edge.scrolled(offset: 200, contentLength: 600, viewport: 400, at: 400, seconds: 0.1) == 200)
        #expect(edge.scrolled(offset: 0, contentLength: 600, viewport: 400, at: 0, seconds: 0.1) == 0)
        // Part way, it goes on, and stops at the end.
        #expect(edge.scrolled(offset: 150, contentLength: 600, viewport: 400, at: 400, seconds: 0.1) == 200)
        #expect(edge.scrolled(offset: 50, contentLength: 600, viewport: 400, at: 400, seconds: 0.01) == 60)
    }

    // MARK: Arming

    @Test func aPressThatStartsInTheBandDoesNotScrollUntilItLeavesIt() {
        var arming = EdgeAutoscroll.Arming(startingAt: 780, along: 800, band: 40)
        #expect(!arming.armsFar)
        #expect(arming.armsNear)
        #expect(edge.speed(at: 790, along: 800, arming: arming) == 0)
        arming.moved(to: 700, along: 800, band: 40)
        #expect(arming.armsFar)
        #expect(edge.speed(at: 790, along: 800, arming: arming) > 0)
    }

    @Test func pastTheEdgeAlwaysScrollsEvenUnarmed() {
        let arming = EdgeAutoscroll.Arming(startingAt: 780, along: 800, band: 40)
        #expect(edge.speed(at: 801, along: 800, arming: arming) == 1000)
    }

    @Test func timeCrossesATenMinuteTimelineInAFewSecondsAtAnyWidth() {
        // A ten minute timeline opened out to two minutes across is five
        // lanes long, however wide the lane is, and crossed at top speed in a
        // few seconds on a narrow window and a wide one alike.
        for width: CGFloat in [600, 800, 1554, 2400] {
            let seconds = 5 * width / EdgeAutoscroll.time(laneWidth: width).topSpeed
            #expect(seconds > 2 && seconds < 5)
        }
    }

    @Test func timeStaysEasyToStopOnAClipPartWayIn() {
        // A third of the way into the band on a wide lane: well under a tenth
        // of a lane a second, so a clip a few seconds long drifts past slowly.
        let edge = EdgeAutoscroll.time(laneWidth: 1554)
        let speed = edge.speed(at: 1554 - 40 + 40.0 / 3, along: 1554)
        #expect(speed / 1554 < 0.1)
        #expect(EdgeAutoscroll.rows.band >= 20)
        #expect(EdgeAutoscroll.rows.topSpeed < EdgeAutoscroll.time(laneWidth: 800).topSpeed)
    }
}
