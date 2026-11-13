import Foundation
@testable import PhotonzCore
import Testing

/// **A playing clock keeps its own beat** (`PlayClockPace`). It slept a frame's
/// length after each tick's work, so every millisecond a tick spent pushed the
/// next one back: 10 ms of work a tick played 23 ticks a second, not 30.
@Suite("The playing clock's beat")
struct PlayClockPaceTests {

    @Test("A tick waits for the next step of the beat, not a whole step after its work")
    func waitsForTheNextStep() {
        let step = Double(MovieRef.frameStepMS)
        // Woken on the beat, nothing done: a whole step.
        #expect(PlayClockPace.waitMS(elapsedMS: step) == step)
        // Ten milliseconds of work after the first beat: the rest of the step.
        #expect(PlayClockPace.waitMS(elapsedMS: step + 10) == step - 10)
        // Just started.
        #expect(PlayClockPace.waitMS(elapsedMS: 0) == step)
    }

    @Test("Ten milliseconds of work a tick still plays the full thirty ticks a second")
    func tenMillisecondsOfWork() {
        var now = 0.0, ticks = 0
        while now < 1000 {
            now += PlayClockPace.waitMS(elapsedMS: now)
            ticks += 1
            now += 10
        }
        #expect(ticks >= 30)
    }

    @Test("A tick that ran past its step leaves a moment to draw, then joins the beat again")
    func behindLeavesAMoment() {
        let step = Double(MovieRef.frameStepMS)
        // Woken at 33, worked 31: two short of the next beat, and the
        // shortest wait still leaves the main thread its moment.
        #expect(PlayClockPace.waitMS(elapsedMS: 64) == PlayClockPace.shortestWaitMS)
        // Worked through two whole steps: back on the next beat, not racing
        // through the ones it missed.
        #expect(PlayClockPace.waitMS(elapsedMS: step * 3 + 5) == step - 5)
    }
}
