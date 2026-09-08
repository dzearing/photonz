import Foundation
import Testing
@testable import PhotonzCore

/// What the layers list is holding while a row is being carried up or down it:
/// who picks a row up, who puts it down, and the deadline that puts it down
/// when the drag ends without telling anyone.
@Suite struct LayerRowInHandTests {
    private let row = UUID()
    private let other = UUID()

    @Test func theListStartsEmptyHanded() {
        let hand = LayerRowInHand()
        #expect(hand.rowID == nil)
        #expect(hand.isHolding == false)
        #expect(hand.landing == nil)
    }

    @Test func pickingARowUpPutsItInTheHand() {
        var hand = LayerRowInHand()
        hand.pickUp(row, at: 0)
        #expect(hand.rowID == row)
        #expect(hand.isHolding)
    }

    /// Picking up starts over: nothing of the last drag's landing carries into
    /// the new one, or the first frame of a drag draws a line for where the
    /// PREVIOUS one was pointing.
    @Test func pickingUpForgetsTheLastLanding() {
        var hand = LayerRowInHand()
        hand.pickUp(row, at: 0)
        hand.say(landing: .above(other), at: 0.1)
        hand.pickUp(other, at: 1)
        #expect(hand.landing == nil)
        #expect(hand.rowID == other)
    }

    @Test func theRowUnderThePointerNamesTheLanding() {
        var hand = LayerRowInHand()
        hand.pickUp(row, at: 0)
        hand.say(landing: .inside(other), at: 0.1)
        #expect(hand.landing == .inside(other))
    }

    /// Off the end of the list, or over a row that cannot take what is being
    /// carried: no line, but the row is still in the hand and the drag is still
    /// live.
    @Test func aLandingNobodyOffersLeavesTheRowInTheHand() {
        var hand = LayerRowInHand()
        hand.pickUp(row, at: 0)
        hand.say(landing: .above(other), at: 0.1)
        hand.say(landing: nil, at: 0.2)
        #expect(hand.landing == nil)
        #expect(hand.isHolding)
    }

    /// A file, a colour, or words being carried over a row are not a row, and
    /// nothing they say may put one in the list's hand — that is what made a
    /// picture arriving get answered as a reorder.
    @Test func nothingCanNameALandingWithNoRowInTheHand() {
        var hand = LayerRowInHand()
        hand.say(landing: .above(other), at: 0)
        #expect(hand.landing == nil)
        #expect(hand.isHolding == false)
    }

    @Test func lettingGoEmptiesTheHand() {
        var hand = LayerRowInHand()
        hand.pickUp(row, at: 0)
        hand.say(landing: .below(other), at: 0.1)
        hand.letGo()
        #expect(hand.rowID == nil)
        #expect(hand.landing == nil)
    }

    // MARK: - The way out that does not need the drag to report its own end

    /// The reported bug. A row is picked up and the drag ends somewhere that
    /// never reports it — escape, let go over the picture, let go outside the
    /// window — and nothing calls `letGo`. Without this the list is still
    /// holding that row, and the next colour carried over a row is read as it
    /// coming back and draws a reorder line for a colour.
    @Test func aRowNobodyPutDownGoesOnItsOwnOnceNothingIsInTheAir() {
        var hand = LayerRowInHand()
        hand.pickUp(row, at: 10)
        hand.say(landing: .above(other), at: 10.1)
        #expect(hand.settle(dragInTheAir: false, at: 10.1 + LayerRowInHand.idleGrace) == true)
        #expect(hand.isHolding == false)
        #expect(hand.landing == nil)
    }

    /// A row picked up and abandoned before it ever reached another row is the
    /// same case, and the deadline runs from the moment it was picked up.
    @Test func aRowAbandonedBeforeItReachedAnyRowGoesToo() {
        var hand = LayerRowInHand()
        hand.pickUp(row, at: 10)
        #expect(hand.settle(dragInTheAir: false, at: 10 + LayerRowInHand.idleGrace) == true)
        #expect(hand.isHolding == false)
    }

    /// ...but not the instant a frame goes by without an update, or a drag a
    /// walk is holding in the air with no button down would be put down
    /// between two of its own updates.
    @Test func aRowJustPickedUpIsLeftAloneEvenWithNoButtonDown() {
        var hand = LayerRowInHand()
        hand.pickUp(row, at: 10)
        #expect(hand.settle(dragInTheAir: false, at: 10.2) == false)
        #expect(hand.rowID == row)
    }

    /// A real drag holds the mouse button down for its whole life, so a
    /// pointer resting still over one row for a long moment keeps its row.
    @Test func aRowStaysHeldWhileSomethingIsStillInTheAir() {
        var hand = LayerRowInHand()
        hand.pickUp(row, at: 10)
        #expect(hand.settle(dragInTheAir: true, at: 10 + LayerRowInHand.idleGrace * 5) == false)
        #expect(hand.rowID == row)
    }

    /// Every frame of a drag asks the row under the pointer again, and each
    /// answer pushes the deadline out, so a long drag is never put down under
    /// itself.
    @Test func everyAnswerPushesTheDeadlineOut() {
        var hand = LayerRowInHand()
        hand.pickUp(row, at: 10)
        hand.say(landing: nil, at: 10 + LayerRowInHand.idleGrace * 0.9)
        #expect(hand.settle(dragInTheAir: false, at: 10 + LayerRowInHand.idleGrace) == false)
        #expect(hand.isHolding)
    }

    @Test func settlingAnEmptyHandChangesNothing() {
        var hand = LayerRowInHand()
        #expect(hand.settle(dragInTheAir: false, at: 1000) == false)
        #expect(hand.isHolding == false)
    }

    /// After it has been put down on its own, a late goodbye from the drop
    /// that finally reported itself is harmless.
    @Test func aLateGoodbyeAfterTheDeadlineIsHarmless() {
        var hand = LayerRowInHand()
        hand.pickUp(row, at: 0)
        hand.settle(dragInTheAir: false, at: LayerRowInHand.idleGrace)
        hand.letGo()
        #expect(hand.isHolding == false)
    }
}
