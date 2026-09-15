import Foundation
import Testing
@testable import PhotonzCore

/// How fast the preview runs (`next-motion`, `MotionSpeed.swift`).
///
/// The whole reason this type exists is a number nobody can see: ninety
/// milliseconds between two parts of one drawing is under six frames at thirty
/// a second, so a lag you can SET on the timing strip is a lag you cannot then
/// judge. Slowing the clock is what replaces scrubbing a playhead for something
/// that loops, so the arithmetic that slows it is worth testing on its own.
@Suite("How fast the preview runs")
struct MotionSpeedTests {

    // MARK: - What there is to pick

    @Test("Full speed is what it runs at until somebody says otherwise")
    func fullIsTheDefault() {
        #expect(MotionSpeed.full.rate == 1)
        #expect(MotionSpeed.choices.first == .full)
        #expect(MotionSpeed.full.isSlowed == false)
    }

    @Test("A quarter and a tenth are the two slow rates")
    func theSlowRates() {
        #expect(MotionSpeed.quarter.rate == 0.25)
        #expect(MotionSpeed.tenth.rate == 0.1)
        #expect(MotionSpeed.quarter.isSlowed)
        #expect(MotionSpeed.tenth.isSlowed)
    }

    @Test("Every rate is offered, slowest last, and no two are the same")
    func choicesAreOrdered() {
        #expect(MotionSpeed.choices == [.full, .quarter, .tenth])
        let rates = MotionSpeed.choices.map(\.rate)
        #expect(rates == rates.sorted(by: >))
        #expect(Set(MotionSpeed.allCases) == Set(MotionSpeed.choices))
    }

    @Test("The control says the rate and the menu says what it means")
    func titles() {
        #expect(MotionSpeed.full.title == "1×")
        #expect(MotionSpeed.quarter.title == "0.25×")
        #expect(MotionSpeed.tenth.title == "0.1×")
        #expect(MotionSpeed.full.menuTitle == "1×")
        #expect(MotionSpeed.quarter.menuTitle == "0.25× · slow")
        #expect(MotionSpeed.tenth.menuTitle == "0.1× · very slow")
    }

    // MARK: - Real time to loop time

    @Test("At full speed a second of real time is a second of the loop")
    func fullSpeedIsRealTime() {
        #expect(MotionSpeed.full.motionMS(afterRealSeconds: 0) == 0)
        #expect(MotionSpeed.full.motionMS(afterRealSeconds: 0.9) == 900)
        #expect(MotionSpeed.full.motionMS(afterRealSeconds: 2.5) == 2500)
    }

    @Test("At a quarter a lap takes four times as long to watch")
    func quarterStretchesTheLap() {
        #expect(MotionSpeed.quarter.motionMS(afterRealSeconds: 0.9) == 225)
        // Four seconds of watching for a 900 ms lap, which is the point.
        #expect(MotionSpeed.quarter.motionMS(afterRealSeconds: 3.6) == 900)
    }

    @Test("At a tenth, the ninety milliseconds nobody can see is nearly a second")
    func tenthMakesALagVisible() {
        // The lag is not a special case: it is the same clock, so the gap
        // between two motions stretches by exactly the same factor as the
        // motions do. Ninety milliseconds of loop is 0.9 seconds of watching.
        #expect(MotionSpeed.tenth.motionMS(afterRealSeconds: 0.9) == 90)
        let bell = MotionSpeed.tenth.realSeconds(forMotionMS: 0)
        let knob = MotionSpeed.tenth.realSeconds(forMotionMS: 90)
        #expect(abs((knob - bell) - 0.9) < 0.0001)
    }

    @Test("Time never runs backwards, however the clock is read")
    func neverNegative() {
        #expect(MotionSpeed.full.motionMS(afterRealSeconds: -3) == 0)
        #expect(MotionSpeed.quarter.motionMS(afterRealSeconds: -0.001) == 0)
        #expect(MotionSpeed.tenth.realSeconds(forMotionMS: -400) == 0)
    }

    @Test("A wild clock reading is not allowed to become a wild playhead")
    func infinityIsRefused() {
        #expect(MotionSpeed.full.motionMS(afterRealSeconds: .infinity) == 0)
        #expect(MotionSpeed.quarter.motionMS(afterRealSeconds: .nan) == 0)
    }

    // MARK: - Changing speed while it runs

    @Test("Reading the clock and reading it back agree")
    func roundTrip() {
        for speed in MotionSpeed.choices {
            for ms in [0, 90, 225, 900, 3_601] {
                #expect(speed.motionMS(afterRealSeconds: speed.realSeconds(forMotionMS: ms)) == ms,
                        "\(speed) at \(ms) ms")
            }
        }
    }

    @Test("Slowing down mid-lap carries on from where the loop had got to")
    func changingSpeedKeepsThePlace() {
        // The loop is 450 ms in at full speed and the speed drops to a quarter.
        // What must NOT happen is a jump back to the top: the same 450 ms is
        // still where the picture is, it is just going to take four times as
        // long to leave. So the clock is re-anchored to the moment that same
        // playhead would have been reached at the new rate.
        let anchor = MotionSpeed.quarter.realSeconds(forMotionMS: 450)
        #expect(abs(anchor - 1.8) < 0.0001)
        #expect(MotionSpeed.quarter.motionMS(afterRealSeconds: anchor) == 450)
    }
}
