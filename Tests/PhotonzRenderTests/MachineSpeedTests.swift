import Foundation
import Testing
@testable import PhotonzRender

/// The arithmetic behind a performance budget, on its own, away from any
/// actual rendering. The probes that feed it are hardware; this is the part
/// that has to be right.
@Suite("Machine-speed budgets")
struct MachineSpeedTests {

    @Test func aBudgetIsAMultipleOfTheRecordedBaseline() {
        // On the machine the baselines were recorded on, factor is 1.
        let bound = MachineSpeed.budget(baselineMS: 100, factor: 1)
        #expect(bound == 100 * MachineSpeed.tolerance + MachineSpeed.jitterSlackMS)
        #expect(bound > 100, "a budget always sits above the number it was calibrated from")
    }

    @Test func aSlowerMachineGetsAProportionallyLooserBudget() {
        let onCalibration = MachineSpeed.budget(baselineMS: 100, factor: 1)
        let onHalfSpeed = MachineSpeed.budget(baselineMS: 100, factor: 2)
        #expect(onHalfSpeed == onCalibration * 2)
        // The release that failed twice: a runner four to eight times slower
        // than the machine this was written on must not trip a budget that
        // the same code passes at home.
        let measuredOnSlowRunner = 100 * 8.0
        #expect(measuredOnSlowRunner < MachineSpeed.budget(baselineMS: 100, factor: 8))
    }

    @Test func aFasterMachineDoesNotGetATighterBudget() {
        // A probe reading fast (a quiet moment, a quicker Mac) must never
        // squeeze a budget below what it was calibrated to allow, or the gate
        // starts failing on luck again.
        #expect(MachineSpeed.budget(baselineMS: 100, factor: 0.4)
                == MachineSpeed.budget(baselineMS: 100, factor: 1))
    }

    @Test func smallNumbersGetAbsoluteSlackSoJitterCannotDecideThem() {
        // A 6ms reading multiplied by a tolerance alone leaves a budget only a
        // few milliseconds wide, which scheduler noise can cross on its own.
        let bound = MachineSpeed.budget(baselineMS: 6, factor: 1)
        #expect(bound - 6 >= MachineSpeed.jitterSlackMS)
    }

    @Test func aRealRegressionStillCrossesTheLine() {
        // Whatever the machine, code that does three times the work fails.
        for factor in [1.0, 4.5, 8.0, 20.0] {
            let baseline = 40.0
            let regressed = baseline * 3 * factor
            #expect(regressed >= MachineSpeed.budget(baselineMS: baseline, factor: factor),
                    "a 3x regression must fail at factor \(factor)")
        }
    }

    @Test func gatingIsOnUnlessTheEnvironmentAsksForReportsOnly() {
        #expect(MachineSpeed.gates(mode: nil))
        #expect(MachineSpeed.gates(mode: ""))
        #expect(MachineSpeed.gates(mode: "gate"))
        #expect(!MachineSpeed.gates(mode: "report"))
        #expect(!MachineSpeed.gates(mode: "REPORT"))
    }

    // MARK: Judged against a yardstick taken in the same rounds
    //
    // The factor measured once at process start says how fast the HARDWARE is.
    // It cannot say how busy the machine is at the moment the subject runs, and
    // inside a 600-suite parallel run that is the number that moves. So the
    // budgets that kept going red are now read against the yardstick taken
    // back to back with the subject, round by round, and judged on the ratio.

    @Test func atRestARoundReadsWhatItWouldOnTheCalibrationMachine() {
        // Subject 5ms, yardstick reading exactly its recorded baseline.
        let normalized = MachineSpeed.normalizedMS(subject: [5, 5, 5],
                                                   reference: [8, 8, 8],
                                                   referenceBaselineMS: 8)
        #expect(abs(normalized - 5) < 0.001)
    }

    @Test func aMachineBusyThroughoutReachesTheSameVerdict() {
        // Everything reads twice as slow. Nothing got slower; the machine did.
        let normalized = MachineSpeed.normalizedMS(subject: [10, 10, 10],
                                                   reference: [16, 16, 16],
                                                   referenceBaselineMS: 8)
        #expect(abs(normalized - 5) < 0.001)
        #expect(normalized < MachineSpeed.budget(baselineMS: 5, factor: 1))
    }

    @Test func loadArrivingPartWayThroughDoesNotDecideIt() {
        // The exact shape of the failures this replaced: quiet for the first
        // rounds, then the rest of the suite lands on the machine. Both
        // readings rise together, so the ratio does not move.
        let normalized = MachineSpeed.normalizedMS(subject: [5, 5, 15, 20, 12],
                                                   reference: [8, 8, 24, 32, 19.2],
                                                   referenceBaselineMS: 8)
        #expect(abs(normalized - 5) < 0.001)
    }

    @Test func oneSpikedRoundDoesNotDecideIt() {
        // A single round where only the subject was descheduled. The median of
        // the rounds ignores it; a mean or a max would not.
        let normalized = MachineSpeed.normalizedMS(subject: [5, 5, 90, 5, 5],
                                                   reference: [8, 8, 8, 8, 8],
                                                   referenceBaselineMS: 8)
        #expect(abs(normalized - 5) < 0.001)
    }

    @Test func realExtraWorkStillCrossesTheLineOnAnyMachine() {
        // Three times the work, on a machine of any speed and any busyness:
        // the subject moves and the yardstick does not, so the gate fires.
        // The baseline here is 40ms, above the range where the flat jitter
        // slack dominates (see the next test).
        for machine in [1.0, 2.0, 8.0] {
            let normalized = MachineSpeed.normalizedMS(
                subject: Array(repeating: 40 * 3 * machine, count: 7),
                reference: Array(repeating: 8 * machine, count: 7),
                referenceBaselineMS: 8)
            #expect(abs(normalized - 120) < 0.001)
            #expect(normalized >= MachineSpeed.budget(baselineMS: 40, factor: 1),
                    "a 3x regression must fail on a machine reading \(machine)x")
        }
    }

    @Test func aSmallBaselineOnlyEverCatchesABigRegression() {
        // Worth writing down because the icon-preview strip is one of these:
        // its baseline is 5ms, so the flat 8ms of slack is larger than the
        // number being guarded and nothing under about 4x trips it. That is
        // the deliberate trade in `jitterSlackMS` and not a bug, but it does
        // mean a 2x slowdown in a 5ms budget goes unnoticed.
        let bound = MachineSpeed.budget(baselineMS: 5, factor: 1)
        #expect(5 * 3 < bound, "a 3x regression on a 5ms baseline still passes")
        #expect(5 * 4.5 > bound, "a 4.5x regression on a 5ms baseline fails")
    }

    @Test func aYardstickThatMeasuredNothingFailsRatherThanPasses() {
        // No rounds, or a reference that read zero, means the comparison never
        // happened. That must never come out as a pass.
        #expect(MachineSpeed.normalizedMS(subject: [], reference: [],
                                          referenceBaselineMS: 8) == .infinity)
        #expect(MachineSpeed.normalizedMS(subject: [5], reference: [0],
                                          referenceBaselineMS: 8) == .infinity)
    }

    @Test func theMedianOfTheRoundsIsWhatCounts() {
        #expect(MachineSpeed.median(of: [3, 1, 2]) == 2)
        #expect(MachineSpeed.median(of: [4, 1, 3, 2]) == 3)   // upper of the two middles
        #expect(MachineSpeed.median(of: []) == nil)
    }
}
