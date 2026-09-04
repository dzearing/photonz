import Foundation

// MARK: Timing without the machine's mood in it
//
// Wall clock makes a relative perf guard flaky. A build or the rest of the
// (parallel) suite takes the core away and the very same work reads two to
// four times slower; on Apple silicon the scheduler then parks the test thread
// on an efficiency core, where it runs slower again with nobody stealing time
// from it. Two perf checks in this target went red that way on 2026-09-04, in
// each case by a hair and for a reason that had nothing to do with what
// changed.
//
// So every guard here reads the same two ways:
//
//   * on THIS THREAD'S CPU clock, so time the thread spent parked does not
//     count against it, and
//   * INTERLEAVED, the subject and the thing it is measured against taken back
//     to back inside every round, so whichever core a round landed on cancels
//     out of the ratio.
//
// A real regression (more work per call, a scan back over whole rows) slows
// every call on every clock, so the readings still move with it. Spreads are
// printed so a flake, if one ever does get through, can be told from a
// regression at a glance.
//
// The one thing this cannot see is work handed to another thread or the GPU.
// Both current callers do their work on the calling thread, so the clock sees
// all of it; a change that moves that work off-thread needs its guard rethought.
// `Tests/PhotonzCoreTests/ElementBoundsTests.swift` takes the same approach in
// its own target.
enum PerfClock {

    /// Milliseconds of CPU this thread has burned.
    static func nowMS() -> Double {
        var stamp = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &stamp)
        return Double(stamp.tv_sec) * 1000 + Double(stamp.tv_nsec) / 1_000_000
    }

    /// What one call cost, in milliseconds of this thread's CPU.
    struct Comparison {
        let subject: [Double]
        let reference: [Double]
        /// The fastest reading: other work only ever slows a reading down, so
        /// the fastest is the one least polluted by the rest of the machine.
        var cost: Double { subject.min() ?? .infinity }
        var baseline: Double { reference.min() ?? 0 }
        var ratio: Double { baseline > 0 ? cost / baseline : .infinity }

        func report(_ name: String, rounds: Int) {
            print(String(format: "[perf] %@ over %d rounds: fastest %.2f ms against %.2f ms, "
                         + "ratio %.2f (slowest %.2f ms and %.2f ms)",
                         name, rounds, cost, baseline, ratio,
                         subject.max() ?? 0, reference.max() ?? 0))
        }
    }

    /// Times `subject` against `reference`, one reading of each per round and
    /// the two taken back to back so they share whatever core the round got.
    /// `callsPerRound` amortizes the clock read over several calls when one
    /// call is too quick to time on its own.
    static func compare(_ name: String, rounds: Int, callsPerRound: Int = 1,
                        subject: () -> Void, reference: () -> Void) -> Comparison {
        // Warm both, so neither pays for a cache the other gets for free.
        reference()
        subject()
        var subjectReadings: [Double] = []
        var referenceReadings: [Double] = []
        for _ in 0..<rounds {
            var start = nowMS()
            for _ in 0..<callsPerRound { reference() }
            referenceReadings.append((nowMS() - start) / Double(callsPerRound))
            start = nowMS()
            for _ in 0..<callsPerRound { subject() }
            subjectReadings.append((nowMS() - start) / Double(callsPerRound))
        }
        let result = Comparison(subject: subjectReadings, reference: referenceReadings)
        result.report(name, rounds: rounds)
        return result
    }
}
