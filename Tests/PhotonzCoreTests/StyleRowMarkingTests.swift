import Foundation
import Testing
@testable import PhotonzCore

/// The mark one row in the layers list wears while a saved text style is held
/// over it.
///
/// The rules that matter are the ones about taking it AWAY. A drag does not
/// always report its own end — escape cancels it, it can be let go outside the
/// window, the row can be rebuilt under it — and a mark nobody ever took away
/// is a row ringed in accent for the rest of the session.
struct StyleRowMarkingTests {

    private let rowA = UUID()
    private let rowB = UUID()

    private func lands(_ row: UUID) -> StyleRowDrop {
        StyleRowDrop(rowID: row,
                     answer: TextStyleDrop.Answer(lands: true, note: "Sets this text in Heading."),
                     layerIDs: [row])
    }

    @Test func aRowWearsWhatItWasToldToWear() {
        var mark = StyleRowMarking()
        mark.say(lands(rowA), at: 0)
        #expect(mark.drop?.rowID == rowA)
        #expect(mark.drop?.lands == true)
    }

    @Test func theRowTheStyleLeftTakesItsOwnMarkAway() {
        var mark = StyleRowMarking()
        mark.say(lands(rowA), at: 0)
        mark.end(from: rowA)
        #expect(mark.drop == nil)
    }

    /// The pointer crossing a row edge enters the new row before it leaves the
    /// old one, so the goodbye arrives second. Honouring it would blink the
    /// mark off at every boundary.
    @Test func aGoodbyeFromARowThatNoLongerOwnsTheMarkIsIgnored() {
        var mark = StyleRowMarking()
        mark.say(lands(rowA), at: 0)
        mark.say(lands(rowB), at: 0.02)
        mark.end(from: rowA)
        #expect(mark.drop?.rowID == rowB)
    }

    /// A drag holds the mouse button down for its whole life, so a mark being
    /// refreshed can never be settled out from under a real drag.
    @Test func aMarkStandsWhileSomethingIsStillInTheAir() {
        var mark = StyleRowMarking()
        mark.say(lands(rowA), at: 0)
        let cleared = mark.settle(dragInTheAir: true, at: 60)
        #expect(!cleared)
        #expect(mark.drop != nil)
    }

    @Test func aMarkNobodyHasSpokenForGoesOnItsOwn() {
        var mark = StyleRowMarking()
        mark.say(lands(rowA), at: 0)
        let early = mark.settle(dragInTheAir: false, at: PanelDropMarking.idleGrace / 2)
        #expect(!early)
        let late = mark.settle(dragInTheAir: false, at: PanelDropMarking.idleGrace)
        #expect(late)
        #expect(mark.drop == nil)
    }

    /// Every frame of a drag pushes the deadline out, so a pointer resting
    /// still over one row is not read as a drag that ended.
    @Test func speakingAgainPushesTheDeadlineOut() {
        var mark = StyleRowMarking()
        mark.say(lands(rowA), at: 0)
        mark.say(lands(rowA), at: 10)
        let early = mark.settle(dragInTheAir: false, at: 10.5)
        #expect(!early)
        let late = mark.settle(dragInTheAir: false, at: 11)
        #expect(late)
    }

    @Test func settlingNothingClearsNothing() {
        var mark = StyleRowMarking()
        let cleared = mark.settle(dragInTheAir: false, at: 99)
        #expect(!cleared)
    }
}
