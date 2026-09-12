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
}
