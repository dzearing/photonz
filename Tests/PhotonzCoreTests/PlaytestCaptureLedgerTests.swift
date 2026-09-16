import Foundation
import PhotonzCore
import Testing

/// A walk writes two pictures of every snapshot: an offscreen drawing of the
/// window, and `<name>-sc.png`, the window as a person would actually see it.
/// The second one is the only one an audit may ship, and until 2026-09-15 it
/// could fail in silence: the walk noted the refusal and carried on green, so a
/// run that photographed nothing looked exactly like a run that photographed
/// everything. Two mornings of audits shipped drawings of the window in place
/// of the window, with nothing in the run to say so.
///
/// The ledger is the part of that which can be reasoned about without an app:
/// what got photographed, what was refused, and therefore whether the run has a
/// real picture in it or only looks like it does.
@Suite("What a walk managed to photograph")
struct PlaytestCaptureLedgerTests {

    @Test("A walk that never asked for a picture is not a failure")
    func neverAsked() {
        let ledger = PlaytestCaptureLedger()
        #expect(ledger.written.isEmpty)
        #expect(ledger.failure(granted: true) == nil)
        #expect(ledger.report(granted: true)
            == "none. This walk never asked for one.")
    }

    @Test("Every picture it asked for, it got")
    func allTaken() {
        var ledger = PlaytestCaptureLedger()
        ledger.photographed("a-start")
        ledger.photographed("b-styled")
        #expect(ledger.written == ["a-start-sc.png", "b-styled-sc.png"])
        #expect(ledger.failure(granted: true) == nil)
        #expect(ledger.report(granted: true)
            == "2 real pictures of the window: a-start-sc.png, b-styled-sc.png")
    }

    @Test("One picture reads as one, not as 1 pictures")
    func oneReadsAsOne() {
        var ledger = PlaytestCaptureLedger()
        ledger.photographed("only")
        #expect(ledger.report(granted: true)
            == "1 real picture of the window: only-sc.png")
    }

    @Test("A picture that could have been taken and was not fails the walk")
    func refusedWhenItCouldHaveWorked() {
        var ledger = PlaytestCaptureLedger()
        ledger.photographed("a-start")
        ledger.refused("b-styled")
        let failure = ledger.failure(granted: true)
        #expect(failure != nil)
        #expect(failure?.contains("b-styled") == true)
        // The reason it matters, in the words the person reading it needs.
        #expect(failure?.contains("audit") == true)
    }

    // A locked screen used to excuse every refusal and to explain away every
    // run that photographed nothing, on the belief that macOS refuses a capture
    // while the login window is up. It does not. Forced past the refusal with
    // PHOTONZ_ALLOW_LOCKED_WALK=1 on 2026-09-16, a two-snapshot walk wrote
    // before-sc.png and after-sc.png, different pictures, the second one showing
    // the rectangle the walk had just dragged out. So the lock is not an excuse
    // and is not an explanation, and neither call takes it any more.
    @Test("A refusal is still a failure even with the screen locked")
    func lockIsNoLongerAnExcuse() {
        var ledger = PlaytestCaptureLedger()
        ledger.refused("a-start")
        #expect(ledger.failure(granted: true) != nil)
        #expect(ledger.report(granted: true) == "none. 1 was refused: a-start")
    }

    @Test("No Screen Recording grant is not the walk's failure either")
    func ungrantedIsNotAFailure() {
        var ledger = PlaytestCaptureLedger()
        ledger.skippedUngranted()
        ledger.skippedUngranted()
        #expect(ledger.ungranted == 2)
        #expect(ledger.failure(granted: false) == nil)
        #expect(ledger.report(granted: false)
            == "none. This app holds no Screen Recording grant, so it may not photograph its own window.")
    }

    @Test("Refusals are named even when some pictures were taken")
    func mixedRunSaysBoth() {
        var ledger = PlaytestCaptureLedger()
        ledger.photographed("a-start")
        ledger.refused("b-styled")
        ledger.refused("c-done")
        #expect(ledger.report(granted: true)
            == "1 real picture of the window: a-start-sc.png; 2 more were refused: b-styled, c-done")
    }

    @Test("A run where every picture was refused says so and says which")
    func allRefused() {
        var ledger = PlaytestCaptureLedger()
        ledger.refused("a-start")
        #expect(ledger.report(granted: true)
            == "none. 1 was refused: a-start")
    }

    @Test("A missing grant explains a run that photographed nothing")
    func ungrantedExplainsAnEmptyRun() {
        var ledger = PlaytestCaptureLedger()
        ledger.skippedUngranted()
        #expect(ledger.report(granted: false)
            == "none. This app holds no Screen Recording grant, so it may not photograph its own window.")
    }
}
