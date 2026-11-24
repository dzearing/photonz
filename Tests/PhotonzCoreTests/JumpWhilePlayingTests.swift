import Foundation
import Testing
@testable import PhotonzCore

// Jumping back while a video plays never flickers between two frames
// (`jumping-back-while-a-video-plays-never-flickers`).
@Suite("What a playing playhead shows after a jump")
struct JumpWhilePlayingTests {

    private let clip = "clip"

    private func look(_ ms: Int, wanted: Int, shown: Int?, difference: Double = 1) -> JumpPlayReading.Look {
        .init(momentMS: ms, frames: [.init(clip: clip, wanted: wanted, shown: shown)], difference: difference)
    }

    @Test("A jump that lands at once and plays on reads clean")
    func clean() {
        let looks = (0..<20).map { look(1000 + $0 * 33, wanted: 30 + $0, shown: 30 + $0) }
        let reading = JumpPlayReading(looks: looks, tolerance: 8, onTime: 0)
        #expect(reading.problems.isEmpty)
        #expect(reading.arrivedAtLook == 1)
    }

    @Test("Holding the picture from before the jump until the new place lands is a wait, not a flicker")
    func holdThenArrive() {
        var looks = (0..<5).map { look(1000 + $0 * 33, wanted: 30 + $0, shown: 120, difference: 40) }
        looks += (5..<20).map { look(1000 + $0 * 33, wanted: 30 + $0, shown: 30 + $0) }
        let reading = JumpPlayReading(looks: looks, tolerance: 8, onTime: 0)
        #expect(reading.problems.isEmpty)
        #expect(reading.arrivedAtLook == 6)
        #expect(reading.heldMS == 5 * 33)
    }

    // The user's report: the frame at the new place, then one from before the
    // jump, then the new place again, for about half a second.
    @Test("Swapping between the new place and the old one fails, naming the pictures")
    func alternation() {
        var looks: [JumpPlayReading.Look] = []
        for step in 0..<12 {
            let wanted = 30 + step
            looks.append(look(1000 + step * 33, wanted: wanted, shown: step.isMultiple(of: 2) ? wanted : 121,
                              difference: step.isMultiple(of: 2) ? 1 : 40))
        }
        let reading = JumpPlayReading(looks: looks, tolerance: 8, onTime: 0)
        #expect(reading.reversals >= 5)
        #expect(reading.problems.contains { $0.contains("backwards") })
        #expect(reading.problems.contains { $0.contains("frame 121 for 31") })
    }

    // A hand dragging the playhead back while it plays leaves reads of the
    // frames it passed landing as it lets go: the picture steps down through
    // them onto the new place and plays on. Always nearer, never back and
    // forth.
    @Test("Stepping down onto the new place and playing on is not going back and forth")
    func convergesThenPlays() {
        let shown = [105, 105, 94, 86, 79, 76, 77, 78, 79, 80]
        let looks = shown.enumerated().map { index, frame in
            look(2500 + index * 10, wanted: 77 + max(0, index - 5), shown: frame)
        }
        let reading = JumpPlayReading(looks: looks, tolerance: 8, onTime: 0)
        #expect(reading.reversals == 0)
        #expect(!reading.problems.contains { $0.contains("backwards") })
    }

    @Test("Going forwards before the new place and then back onto it is going back and forth")
    func upThenDownBeforeArriving() {
        let shown = [40, 135, 60, 61]
        let looks = shown.enumerated().map { index, frame in look(index * 33, wanted: 58 + index, shown: frame) }
        #expect(JumpPlayReading(looks: looks, tolerance: 8, onTime: 0).reversals == 1)
    }

    // Recorded in the probe on 2026-11-24, before the fix: the long-GOP
    // fixture played from 5s, clicked back from 6.03s to 2.00s. Frame 135 is
    // one read before the jump; each frame of the new place was read on its
    // own and stood in for by it until it landed.
    @Test("The pictures recorded before the fix fail")
    func recordedBeforeTheFix() {
        let recorded: [(Int, Int, Int)] = [
            (2000, 135, 60), (2038, 135, 61), (2038, 61, 61), (2071, 135, 62), (2103, 135, 63), (2103, 63, 63),
            (2137, 135, 64), (2137, 64, 64), (2171, 135, 65), (2204, 135, 66), (2204, 66, 66), (2236, 135, 67),
            (2268, 135, 68), (2268, 68, 68), (2301, 135, 69), (2335, 135, 70), (2335, 70, 70), (2369, 135, 71),
            (2400, 135, 72), (2400, 72, 72),
        ]
        let looks = recorded.map { ms, shown, wanted in look(ms, wanted: wanted, shown: shown) }
        let reading = JumpPlayReading(looks: looks, tolerance: 4, onTime: 0)
        #expect(reading.arrivedAtLook == 3)
        #expect(reading.reversals == 6)
        #expect(reading.problems.contains { $0.contains("frame 135 for 62") })
    }

    @Test("A picture that differs from its moment once the new place is on screen fails")
    func differsAfterArriving() {
        var looks = (0..<10).map { look(1000 + $0 * 33, wanted: 30 + $0, shown: 30 + $0) }
        looks[6].difference = 20
        let reading = JumpPlayReading(looks: looks, tolerance: 8, onTime: 0)
        #expect(reading.problems.count == 1)
        #expect(reading.problems[0].contains("picture 7"))
    }

    @Test("A picture a frame or more behind its moment after arriving fails, beyond the allowance")
    func lateAfterArriving() {
        var looks = (0..<10).map { look(1000 + $0 * 33, wanted: 30 + $0, shown: 30 + $0) }
        looks[4].frames[0].shown = 33
        looks[5].frames[0].shown = 33
        looks[6].frames[0].shown = 33
        let reading = JumpPlayReading(looks: looks, tolerance: 8, onTime: 0)
        #expect(reading.problems.contains { $0.contains("behind") })
        // ...and at 8x a few frames off is on time.
        #expect(JumpPlayReading(looks: looks, tolerance: 8, onTime: 3).problems.isEmpty)
    }

    // A jump while playing waits for its first frames with the playhead
    // standing on the new place, so the wait is told by the wall clock.
    @Test("The wait for the new place is timed by the clock on the wall, not the playhead")
    func waitOnTheWall() {
        var looks: [JumpPlayReading.Look] = []
        for step in 0..<4 {
            looks.append(.init(momentMS: 2000, frames: [.init(clip: clip, wanted: 60, shown: 110)],
                               difference: 30, shownAtMS: step * 150))
        }
        looks.append(.init(momentMS: 2000, frames: [.init(clip: clip, wanted: 60, shown: 60)],
                           difference: 1, shownAtMS: 600))
        let reading = JumpPlayReading(looks: looks, tolerance: 8, onTime: 0, longestHoldMS: 500)
        #expect(reading.heldMS == 600)
        #expect(reading.problems.contains { $0.contains("held 600ms") })
    }

    @Test("A wait longer than the longest allowed fails")
    func waitTooLong() {
        var looks: [JumpPlayReading.Look] = (0..<20).map { (step: Int) -> JumpPlayReading.Look in
            look(1000 + step * 33, wanted: 30 + step, shown: 120, difference: 40)
        }
        for step in 20..<25 { looks.append(look(1000 + step * 33, wanted: 30 + step, shown: 30 + step)) }
        let reading = JumpPlayReading(looks: looks, tolerance: 8, onTime: 0, longestHoldMS: 400)
        #expect(reading.problems.contains { $0.contains("held") })
        #expect(JumpPlayReading(looks: Array(looks.prefix(3)), tolerance: 8, onTime: 0)
            .problems.contains { $0.contains("never") })
    }

    @Test("Every clip on screen is read on its own")
    func twoClips() {
        var looks: [JumpPlayReading.Look] = []
        for step in 0..<6 {
            let a = JumpPlayReading.Frame(clip: "a", wanted: 10 + step, shown: 10 + step)
            let b = JumpPlayReading.Frame(clip: "b", wanted: 50 + step, shown: step == 3 ? 90 : 50 + step)
            looks.append(JumpPlayReading.Look(momentMS: step * 33, frames: [a, b], difference: 1))
        }
        let reading = JumpPlayReading(looks: looks, tolerance: 8, onTime: 0)
        #expect(reading.problems.contains { $0.contains("b frame 90 for 53") })
    }
}

// The cause, 2026-11-24: a jump back while playing forwards set the playhead
// going backwards for as long as it then played, so nothing read ahead of it
// and every frame not read yet was stood in for from the frames AHEAD of it,
// the place it had left: the new frame, the old one, the new one again.
@Suite("Which way the playhead goes after it is moved")
struct PlayheadTravelAfterAMoveTests {

    typealias Travel = MovieFramesInHand.Travel

    @Test("At rest, the way it was moved")
    func atRest() {
        #expect(Travel.afterMove(from: 5000, to: 2000, clockRate: nil, handHolds: false) == .backward)
        #expect(Travel.afterMove(from: 2000, to: 5000, clockRate: nil, handHolds: false) == .forward)
    }

    @Test("While a clock plays, the clock's way, whichever way it was moved")
    func whilePlaying() {
        #expect(Travel.afterMove(from: 5000, to: 2000, clockRate: 1, handHolds: false) == .forward)
        #expect(Travel.afterMove(from: 5000, to: 2000, clockRate: 2, handHolds: false) == .forward)
        #expect(Travel.afterMove(from: 2000, to: 5000, clockRate: -1, handHolds: false) == .backward)
    }

    @Test("A hand dragging it while it plays goes the hand's way until it lets go")
    func handWhilePlaying() {
        #expect(Travel.afterMove(from: 5000, to: 4900, clockRate: 1, handHolds: true) == .backward)
        #expect(Travel.afterMove(from: 4900, to: 5000, clockRate: -2, handHolds: true) == .forward)
        #expect(Travel.whenHandLetsGo(clockRate: 1, handWent: .backward) == .forward)
        #expect(Travel.whenHandLetsGo(clockRate: -1, handWent: .forward) == .backward)
        #expect(Travel.whenHandLetsGo(clockRate: nil, handWent: .backward) == .backward)
    }
}
