import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A bar's end dragged along the timeline, step by step, read against the
/// pointer (`GripTrace`, and the `dragGrip` walk step that feeds it).
///
/// On 2026-09-26 the user dragged a rectangle's bar end left and it flickered:
/// "it doesn't want to just track with the mouse". The standard is Premiere's
/// and Final Cut's: the edge sits under the pointer every frame, snaps only
/// when near something, and lets go cleanly.
@Suite("A dragged edge read against the pointer")
struct GripTraceTests {

    // MARK: - The drag itself, worked out from where it was grabbed

    /// Ten seconds of a rectangle placed from one second to eleven, free to
    /// be shortened from its right hand end down to a frame.
    static func placed() -> ClipPieces {
        ClipPieces(single: LayerTime(inMS: 1_000, outMS: 11_000,
                                     sourceInMS: 0, sourceLengthMS: 10_000))
    }

    @Test("The out point is worked out from the grab and the hand, and is monotonic in the hand")
    func outPointFollowsTheHand() {
        let drag = ClipBarDrag(grab: .seam(after: 0), pieces: Self.placed(), clipStartMS: 1_000)
        var last = Int.max
        // Forty small steps left, the way the user dragged it.
        for step in 0...40 {
            let hand = -step * 50
            let landing = drag.landing(byMS: hand)
            let out = 1_000 + landing.pieces.totalLengthMS
            #expect(out <= last, "step \(step): the end went back on itself")
            #expect(out == 11_000 + hand, "step \(step): the end is not under the hand")
            last = out
        }
    }

    @Test("Asking the same drag twice gives the same answer: nothing creeps between moves")
    func noCreep() {
        let drag = ClipBarDrag(grab: .seam(after: 0), pieces: Self.placed(), clipStartMS: 1_000)
        let once = drag.landing(byMS: -730)
        _ = drag.landing(byMS: -20)
        _ = drag.landing(byMS: -1_400)
        #expect(drag.landing(byMS: -730) == once)
    }

    @Test("Snapping catches near an edge, holds inside, and lets go once on the far side")
    func snapCatchesAndLetsGoOnce() {
        let playhead = MotionStripEdge(ms: 8_000, name: "the playhead", isStart: true)
        let drag = ClipBarDrag(grab: .seam(after: 0), pieces: Self.placed(), clipStartMS: 1_000,
                               others: [playhead], snapWithinMS: 60)
        var states: [Bool] = []
        for step in 0...80 {
            let hand = -step * 50            // 11s down to 7s, across the playhead at 8s
            let landing = drag.landing(byMS: hand)
            let out = 1_000 + landing.pieces.totalLengthMS
            if let caught = landing.snappedTo {
                #expect(caught == playhead)
                #expect(out == 8_000)
                #expect(abs(11_000 + hand - 8_000) <= 60)
            } else {
                #expect(out == 11_000 + hand)
            }
            if states.last != (landing.snappedTo != nil) { states.append(landing.snappedTo != nil) }
        }
        // Free, caught, free: never caught twice on one pass.
        #expect(states == [false, true, false])
    }

    @Test("An edge held where it started by something it lines up with says what it caught on")
    func heldAtTheStartSaysSo() {
        // The rectangle ends at eleven seconds, and so does the recording under
        // it: a small pull is held there, and the line has to say why.
        let recordingEnd = MotionStripEdge(ms: 11_000, name: "Recording", isStart: false)
        let drag = ClipBarDrag(grab: .seam(after: 0), pieces: Self.placed(), clipStartMS: 1_000,
                               others: [recordingEnd], snapWithinMS: 60)
        let landing = drag.landing(byMS: -40)
        #expect(landing.movedMS == 0)
        #expect(landing.snappedTo == recordingEnd)
        #expect(drag.landing(byMS: 0).snappedTo == recordingEnd)
    }

    @Test("Nought reach is a drag free of every magnet")
    func noReachNoSnap() {
        let playhead = MotionStripEdge(ms: 8_000, name: "the playhead", isStart: true)
        let drag = ClipBarDrag(grab: .seam(after: 0), pieces: Self.placed(), clipStartMS: 1_000,
                               others: [playhead], snapWithinMS: 60).snapping(withinMS: 0)
        let landing = drag.landing(byMS: -3_020)
        #expect(landing.snappedTo == nil)
        #expect(1_000 + landing.pieces.totalLengthMS == 7_980)
    }

    @Test("A grabbed left end and a slid bar follow the hand the same way")
    func leftEndAndBodyFollow() {
        let start = ClipBarDrag(grab: .clipStart, pieces: Self.placed(), clipStartMS: 1_000,
                                startIsFree: true)
        let body = ClipBarDrag(grab: .body, pieces: Self.placed(), clipStartMS: 1_000)
        var lastStart = Int.min, lastBody = Int.min
        for step in 0...40 {
            let hand = step * 50
            let a = start.landing(byMS: hand), b = body.landing(byMS: hand)
            #expect(a.clipStartMS == 1_000 + hand)
            #expect(b.clipStartMS == 1_000 + hand)
            #expect(a.clipStartMS >= lastStart && b.clipStartMS >= lastBody)
            lastStart = a.clipStartMS
            lastBody = b.clipStartMS
        }
    }

    // MARK: - Reading a walk's trace

    static func sample(_ pointer: CGFloat, _ grip: CGFloat, snapped: Bool = false) -> GripTrace.Sample {
        GripTrace.Sample(pointerX: pointer, gripX: grip, snapped: snapped)
    }

    @Test("A grip that keeps its place under the pointer misses by nothing")
    func steadyGrip() {
        // Grabbed 3 points left of the grip's middle, dragged left 1pt a step.
        let samples = (0...30).map { i in Self.sample(500 - CGFloat(i), 503 - CGFloat(i)) }
        let trace = GripTrace(samples)
        #expect(trace.worstMiss == 0)
        #expect(trace.wentBack == 0)
        #expect(trace.follows(within: 1))
    }

    @Test("A grip that feeds its own move back into the next one shows up as a miss and a reversal")
    func feedbackFlicker() {
        // The pointer walks left 2pt a step; the grip lands at half, then
        // snaps back, then half again: the flicker the user saw.
        var samples: [GripTrace.Sample] = [Self.sample(500, 500)]
        for i in 1...30 {
            let pointer = 500 - CGFloat(i * 2)
            let grip = i.isMultiple(of: 2) ? pointer : 500 - CGFloat(i)
            samples.append(Self.sample(pointer, grip))
        }
        let trace = GripTrace(samples)
        #expect(trace.worstMiss > 10)
        #expect(trace.wentBack > 5)
        #expect(!trace.follows(within: 1))
    }

    @Test("Steps where the grip is caught on something are not counted as misses")
    func snappedStepsAreExcused() {
        var samples = (0...10).map { i in Self.sample(500 - CGFloat(i), 500 - CGFloat(i)) }
        // Caught 3 points to the left of the pointer for two steps, then free.
        samples.append(Self.sample(489, 486, snapped: true))
        samples.append(Self.sample(488, 486, snapped: true))
        samples.append(Self.sample(487, 487))
        let trace = GripTrace(samples)
        #expect(trace.worstMiss == 0)
        #expect(trace.snappedSteps == 2)
        #expect(trace.follows(within: 1))
    }

    @Test("The summary says the numbers a person reads")
    func summary() {
        let trace = GripTrace((0...4).map { i in Self.sample(100 - CGFloat(i), 100 - CGFloat(i)) })
        #expect(trace.summary == "5 steps, worst 0.0pt off the pointer, went back on itself 0 times, caught 0")
    }
}
