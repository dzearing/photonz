import Foundation
import Testing

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
// Every caller here does its work on the calling thread, so the clock sees
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

        /// The typical round's ratio, subject over reference WITHIN the round.
        ///
        /// Dividing the fastest subject reading by the fastest reference
        /// reading looks equivalent and is not, whenever the two halves take
        /// different times: the shorter half fits into a quiet gap on a busy
        /// machine more often than the longer one, so its best reading is the
        /// cleaner of the two and the quotient drifts upward under load with
        /// nothing having changed. Measured on 2026-09-17, the check in
        /// `ElementDetectionFixtureTests` (a 5.6 ms subject against a 3.0 ms
        /// reference) read 1.84 idle and 3.40 during a full suite with eight
        /// spin loops on top, against a guard of 4.
        ///
        /// Pairing the halves inside the round they were measured in removes
        /// that bias, but taking the BEST pair introduces the opposite one:
        /// over twenty rounds something is bound to have caught the reference
        /// slow and the subject fast, and on the same loaded run that read 0.35
        /// against a guard of 1.3, loose enough to wave a real regression
        /// through. The middle pair has no luck in it either way.
        var ratio: Double {
            let paired = zip(subject, reference).filter { $0.1 > 0 }
                .map { $0.0 / $0.1 }.sorted()
            return paired.isEmpty ? .infinity : paired[paired.count / 2]
        }

        func report(_ name: String, rounds: Int) {
            print(String(format: "[perf] %@ over %d rounds: fastest %.2f ms against %.2f ms, "
                         + "ratio %.2f in a typical round (slowest %.2f ms and %.2f ms)",
                         name, rounds, cost, baseline, ratio,
                         subject.max() ?? 0, reference.max() ?? 0))
        }
    }

    /// What one call costs, in milliseconds of this thread's CPU: the fastest
    /// of `batches` batches of `callsPerBatch` calls, after a warm-up. Other
    /// work on the machine only ever slows a batch down, so the fastest one is
    /// the reading least polluted by it, and a batch amortizes the clock read
    /// over calls too quick to time on their own.
    static func fastestCallMS(batches: Int, callsPerBatch: Int,
                              _ body: () -> Void) -> Double {
        body()
        var readings: [Double] = []
        for _ in 0..<batches {
            let start = nowMS()
            for _ in 0..<callsPerBatch { body() }
            readings.append((nowMS() - start) / Double(callsPerBatch))
        }
        return readings.min() ?? .infinity
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

    // MARK: A budget against the CPU ruler, for work done on this thread

    /// What one ruler round cost on the calibration machine (the arm64 Mac this
    /// repo is developed on, a debug build, the rest of the suite quiet),
    /// measured 2026-10-30. The same work as `CPUYardstick` in
    /// PhotonzCoreTests, which reads 4.5 there: re-record it only when the
    /// calibration machine changes, never to make a gate pass.
    static let rulerBaselineMS: Double = 4.5

    /// Kept so the compiler cannot decide the ruler's work had no effect.
    nonisolated(unsafe) static var sink: Double = 0

    /// One round of the CPU ruler: arrays made, written, read and let go,
    /// running no Photonz code. `CPUYardstick` says how this shape was chosen:
    /// of the rulers tried beside a busy full suite it was the one that slowed
    /// down exactly as much as the work being judged did.
    static func rulerRound() {
        var total = 0.0
        for k in 0..<24_000 {
            var candidates = [Double](repeating: Double(k), count: 64)
            candidates[3] += 1
            total += candidates[3]
        }
        sink += total
    }

    /// Work timed against the ruler, each round the ruler first and the
    /// subject straight after on this thread's CPU clock.
    struct Calibrated {
        /// Each round's subject, in this machine's milliseconds of CPU.
        let subject: [Double]
        /// Each round's ruler, the fastest of its ruler rounds, in the same.
        let ruler: [Double]

        private var ratios: [Double] {
            zip(subject, ruler).filter { $0.1 > 0 }.map { $0.0 / $0.1 }
        }

        /// A typical round of the subject, in the calibration machine's
        /// milliseconds: the middle ratio, scaled by the ruler's baseline.
        var medianMS: Double {
            MachineSpeed.median(of: ratios).map { $0 * PerfClock.rulerBaselineMS } ?? .infinity
        }

        /// Every round of the subject added up, scaled by the ruler's middle
        /// reading: for rounds that are different work (one per brush), where
        /// no one round's ratio is typical of the rest.
        var summedMS: Double {
            guard !subject.isEmpty, rulerMS > 0, rulerMS.isFinite else { return .infinity }
            return subject.reduce(0, +) / rulerMS * PerfClock.rulerBaselineMS
        }

        /// What the ruler itself read here, against its own baseline.
        var rulerMS: Double { MachineSpeed.median(of: ruler) ?? .infinity }
    }

    /// Times `subject(round)` against the ruler for `rounds` rounds. A subject
    /// much longer than the ruler takes `rulerRounds` of it each round, half
    /// just before and half just after, and is read against the fastest of
    /// them: what this core does when nothing
    /// takes it away, which is the hardware's speed. Read against their
    /// average instead, a WebP encode in the stopwatch run read 843ms against
    /// the 1220 it costs alone (2026-10-30): the encode ran exactly as fast as
    /// alone while the ruler, made of arrays let go, was slowed half as much
    /// again by the 12 megapixel exports beside it, so twice the encode would
    /// have passed.
    static func calibrated(rounds: Int, rulerRounds: Int = 1,
                           subject: (Int) -> Void) -> Calibrated {
        rulerRound()  // warm: the first round pays for pages the rest reuse
        var subjectMS: [Double] = []
        var rulerMS: [Double] = []
        func fastestRuler(_ count: Int) -> Double {
            var fastest = Double.infinity
            for _ in 0..<count {
                let start = nowMS()
                rulerRound()
                fastest = min(fastest, nowMS() - start)
            }
            return fastest
        }
        let before = max(1, (rulerRounds + 1) / 2), after = rulerRounds - before
        for round in 0..<rounds {
            let ahead = fastestRuler(before)
            let start = nowMS()
            subject(round)
            subjectMS.append(nowMS() - start)
            // The rest of the ruler straight after: a stretch of slow ruler
            // rounds on one side of the subject (the thread on an efficiency
            // core, say, and back on a performance core for the subject) does
            // not decide the round.
            rulerMS.append(after > 0 ? min(ahead, fastestRuler(after)) : ahead)
        }
        return Calibrated(subject: subjectMS, ruler: rulerMS)
    }

    /// The gate every CPU budget here goes through: `ms` is a `Calibrated`
    /// reading, the calibration machine's milliseconds, judged against
    /// `baselineMS x tolerance`. Inside it passes however busy the machine
    /// was; over it fails, unless the ruler read so far off its own number
    /// that the machine was too busy to judge, which is said as a known issue.
    /// Never gates under `PHOTONZ_PERF_GATE=report`, as CI and release run.
    static func check(_ label: String, ms: Double, rulerMS: Double, baselineMS: Double,
                      tolerance: Double,
                      fileID: String = #fileID, filePath: String = #filePath,
                      line: Int = #line, column: Int = #column) {
        let bound = baselineMS * tolerance
        let message = String(format: "%@ — %.1fms on the calibration machine's CPU clock against a "
                             + "budget of %.1fms (baseline %.1fms x %.1f), beside a CPU ruler "
                             + "reading %.2fms against its own %.2fms",
                             label, ms, bound, baselineMS, tolerance, rulerMS, rulerBaselineMS)
        print("[perf] budget: \(message)")
        guard MachineSpeed.isGating else { return }
        let location = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
        switch MachineSpeed.reading(normalizedMS: ms, boundMS: bound, yardstickMS: rulerMS,
                                    yardstickBaselineMS: rulerBaselineMS) {
        case .withinBudget:
            return
        case .overBudget:
            Issue.record(Comment(rawValue: "\(label) regressed: \(message)"), sourceLocation: location)
        case .untrusted:
            print("[perf] not judged: \(label), the CPU ruler read \(rulerMS)ms against its own \(rulerBaselineMS)ms")
            withKnownIssue("\(label) could not be measured: the machine was too busy",
                           sourceLocation: location) {
                Issue.record(Comment(rawValue: "\(label) over budget on a machine too busy to judge it: \(message)"),
                             sourceLocation: location)
            }
        }
    }
}
