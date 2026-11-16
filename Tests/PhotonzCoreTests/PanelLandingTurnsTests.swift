import PhotonzCore
import Testing

/// The dock fills in a piece a pass (a section, then a section's later
/// rows), and two pieces landing in one pass make the long pass the pieces
/// were split up to avoid. `PanelLandingTurns` hands each run-loop pass to
/// one piece; the next waits a pass.
@Suite("PanelLandingTurns")
struct PanelLandingTurnsTests {

    @Test func theFirstPieceInAPassLands() {
        var turns = PanelLandingTurns()
        let c1 = turns.claim(pass: 7)
        #expect(c1)
    }

    @Test func aSecondPieceInTheSamePassWaits() {
        var turns = PanelLandingTurns()
        let c2 = turns.claim(pass: 7)
        #expect(c2)
        let c3 = turns.claim(pass: 7)
        #expect(c3 == false)
        let c4 = turns.claim(pass: 7)
        #expect(c4 == false)
    }

    @Test func theNextPassIsFreeAgain() {
        var turns = PanelLandingTurns()
        let c5 = turns.claim(pass: 7)
        #expect(c5)
        let c6 = turns.claim(pass: 8)
        #expect(c6)
        let c7 = turns.claim(pass: 8)
        #expect(c7 == false)
    }

    @Test func passesWithNothingLandingInBetweenChangeNothing() {
        // A dock that went quiet for a while: the pass count has moved on by
        // many, and the first piece after it lands at once.
        var turns = PanelLandingTurns()
        let c8 = turns.claim(pass: 3)
        #expect(c8)
        let c9 = turns.claim(pass: 400)
        #expect(c9)
    }

    @Test func aPassCountThatWrapsStillLands() {
        // The count is a wrapping integer; landing must never stop because
        // it went round.
        var turns = PanelLandingTurns()
        let c10 = turns.claim(pass: Int.max)
        #expect(c10)
        let c11 = turns.claim(pass: Int.min)
        #expect(c11)
    }

    @Test func aPieceThatAsksForRestKeepsTheNextPassQuiet() {
        // Rows full of controls are paid for twice: in the pass they land and
        // again a pass later, when SwiftUI works out focus and accessibility
        // for every control they brought. Nothing else lands in that pass.
        var turns = PanelLandingTurns()
        let rows = turns.claim(pass: 10, restAfter: 1)
        #expect(rows)
        let next = turns.claim(pass: 11)
        #expect(next == false)
        let after = turns.claim(pass: 12)
        #expect(after)
    }

    @Test func restingNeverHoldsAPassBeforeTheOneThatAskedForIt() {
        var turns = PanelLandingTurns()
        let first = turns.claim(pass: 10, restAfter: 2)
        #expect(first)
        let farLater = turns.claim(pass: 50)
        #expect(farLater)
    }
}
