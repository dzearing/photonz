import Foundation
import Testing
@testable import PhotonzCore

/// Which work held until a frame is out fits in what the last refresh left
/// over (`SpareFrameTime`).
@Suite struct SpareFrameTimeTests {
    private let ms = 0.001

    /// A clock that has seen the main thread busy over these stretches.
    private func clock(_ passes: [(Double, Double)]) -> SpareFrameTime {
        var spare = SpareFrameTime()
        for (start, end) in passes {
            spare.passBegan(at: start * ms)
            spare.passEnded(at: end * ms)
        }
        return spare
    }

    @Test func busyCountsOnlyTheLastRefresh() {
        // 5 ms of work long ago, 3 ms of it inside the last 8.3 ms, then 2 ms.
        let spare = clock([(0, 5), (10, 13), (15, 17)])
        #expect(abs(spare.busy(endingAt: 18 * ms) - 5 * ms) < 1e-9)
        // A pass that straddles the start of the refresh counts only its tail.
        let straddles = clock([(0, 6)])
        let tail: Double = (6 - (10 - 1000.0 / 120)) * ms
        let read: Double = straddles.busy(endingAt: 10 * ms)
        #expect(abs(read - tail) < 1e-9)
    }

    @Test func anOpenPassCountsUpToNow() {
        var spare = clock([])
        spare.passBegan(at: 2 * ms)
        #expect(abs(spare.busy(endingAt: 6 * ms) - 4 * ms) < 1e-9)
    }

    @Test func afterALightFrameTheWorkRuns() {
        // A 3 ms frame: room for a 3 ms picture under the ceiling.
        let spare = clock([(0, 3)])
        #expect(spare.runs(costs: [3 * ms], waitedSince: [1 * ms], now: 4 * ms) == [0])
    }

    @Test func afterAHeavyFrameItWaits() {
        // A 6 ms frame that built a lane: its 3 ms picture waits for the next.
        let spare = clock([(0, 6)])
        #expect(spare.runs(costs: [3 * ms], waitedSince: [5 * ms], now: 7 * ms).isEmpty)
    }

    @Test func whatFitsRunsAndTheRestWaitsInOrder() {
        // 3 ms of room: the 1 ms and the 1.5 ms fit, the 3 ms behind the first does not.
        let spare = clock([(0, 3.5)])
        let costs: [Double] = [1 * ms, 3 * ms, 1.5 * ms]
        let since: [Double] = [3 * ms, 3 * ms, 3 * ms]
        #expect(spare.runs(costs: costs, waitedSince: since, now: 4 * ms) == [0, 2])
    }

    @Test func workThatWaitedLongEnoughRunsAnyway() {
        let spare = clock([(20, 27)])
        let waited = 20 * ms - SpareFrameTime().longestWait
        #expect(spare.runs(costs: [3 * ms], waitedSince: [waited], now: 28 * ms) == [0])
    }

    @Test func onAnIdleThreadEvenWorkOverTheCeilingRuns() {
        // Nothing else wakes an idle thread, so work bigger than any frame's
        // room is never left waiting for a frame that has room.
        let spare = clock([(0, 1)])
        #expect(spare.runs(costs: [9 * ms], waitedSince: [0.5 * ms], now: 30 * ms) == [0])
    }

    @Test func oldPassesAreForgotten() {
        var spare = SpareFrameTime()
        for i in 0..<1000 {
            spare.passBegan(at: Double(i) * 8 * ms)
            spare.passEnded(at: (Double(i) * 8 + 4) * ms)
        }
        #expect(spare.passesKept <= 4)
    }
}
