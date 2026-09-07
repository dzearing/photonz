import Foundation
import PhotonzCore
import Testing

/// A walk's `wait` step exists because whoever wrote it wanted the editor to
/// have finished before the next step looked at it. What it wanted was quiet,
/// not the clock, and on a quick machine the editor is finished long before
/// the wait is up: across the 247 walks in the suite the waits alone add up to
/// 31 minutes of sleeping (measured 2026-09-07).
///
/// So a wait ends when the app has been quiet for a beat, never sooner than a
/// floor and never later than the walk asked for. This is that rule, on its
/// own, without an app around it.
@Suite("How long a wait step actually waits")
struct PlaytestSettleTests {

    private let settle = PlaytestSettle.standard

    @Test("A wait never comes back before the floor, however quiet the app is")
    func floorHolds() {
        #expect(!settle.isOver(waited: 0, asked: 0.5, quiet: 10))
        #expect(!settle.isOver(waited: settle.floor / 2, asked: 0.5, quiet: 10))
        #expect(settle.isOver(waited: settle.floor, asked: 0.5, quiet: 10))
    }

    @Test("A quiet app ends the wait early")
    func quietEndsItEarly() {
        let waited = settle.floor + settle.quiet
        #expect(settle.isOver(waited: waited, asked: 2, quiet: settle.quiet))
        #expect(!settle.isOver(waited: waited, asked: 2, quiet: settle.quiet / 2))
    }

    @Test("A busy app still gets everything the walk asked for, and no more")
    func busyGetsTheWholeWait() {
        #expect(!settle.isOver(waited: 0.4, asked: 0.5, quiet: 0))
        #expect(settle.isOver(waited: 0.5, asked: 0.5, quiet: 0))
        #expect(settle.isOver(waited: 0.9, asked: 0.5, quiet: 0))
    }

    @Test("A wait shorter than the floor is just that wait")
    func shortWaitsAreLeftAlone() {
        #expect(settle.isOver(waited: 0.08, asked: 0.08, quiet: 0))
        #expect(!settle.isOver(waited: 0.04, asked: 0.08, quiet: 0))
    }

    @Test("Turned off, a wait is the clock again")
    func offMeansTheClock() {
        let off = PlaytestSettle.off
        #expect(!off.isOver(waited: 0.4, asked: 0.5, quiet: 10))
        #expect(off.isOver(waited: 0.5, asked: 0.5, quiet: 0))
    }

    @Test("The nap never overshoots what the walk asked for")
    func napStopsAtTheAsk() {
        #expect(settle.nap(waited: 0, asked: 1) == settle.slice)
        #expect(settle.nap(waited: 0.99, asked: 1).isApproximatelyEqual(to: 0.01))
        #expect(settle.nap(waited: 1, asked: 1) == 0)
        #expect(settle.nap(waited: 1.5, asked: 1) == 0)
    }

    @Test("A quiet slice lengthens the run of quiet, a busy one resets it")
    func quietRunAddsUp() {
        var quiet = 0.0
        quiet = settle.quiet(after: quiet, slice: 0.03, busy: 0, restless: false)
        #expect(quiet.isApproximatelyEqual(to: 0.03))
        quiet = settle.quiet(after: quiet, slice: 0.03, busy: 0, restless: false)
        #expect(quiet.isApproximatelyEqual(to: 0.06))
        quiet = settle.quiet(after: quiet, slice: 0.03, busy: 0.02, restless: false)
        #expect(quiet == 0)
    }

    @Test("Something still animating keeps the app restless however idle the main thread is")
    func restlessResetsTheRun() {
        let quiet = settle.quiet(after: 0.09, slice: 0.03, busy: 0, restless: true)
        #expect(quiet == 0)
    }

    @Test("A slice of main thread work small enough to be the harness looking still counts as quiet")
    func tinyBusyIsStillQuiet() {
        let quiet = settle.quiet(after: 0.03, slice: 0.03, busy: settle.busyBudget / 2, restless: false)
        #expect(quiet.isApproximatelyEqual(to: 0.06))
    }

    @Test("The pace is named so a flaky walk can be re-run on the clock")
    func namedPaces() {
        #expect(PlaytestSettle.named(nil) == .standard)
        #expect(PlaytestSettle.named("") == .standard)
        #expect(PlaytestSettle.named("settle") == .standard)
        #expect(PlaytestSettle.named("full") == .off)
        #expect(PlaytestSettle.named("FULL") == .off)
        #expect(PlaytestSettle.named("off") == .off)
    }
}

private extension Double {
    func isApproximatelyEqual(to other: Double) -> Bool { abs(self - other) < 1e-9 }
}
