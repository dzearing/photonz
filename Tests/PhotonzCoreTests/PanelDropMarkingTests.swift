import Foundation
import Testing
@testable import PhotonzCore

/// The mark the properties panel wears while something is held over it: who
/// gets to arm it, who gets to clear it, and the deadline that clears it when
/// nobody does.
@Suite struct PanelDropMarkingTests {
    private let target = UUID()

    @Test func nothingIsShowingToBeginWith() {
        let marking = PanelDropMarking()
        #expect(marking.offer == nil)
    }

    @Test func aTargetSaysWhatItWillDo() {
        var marking = PanelDropMarking()
        marking.say(.refuses, from: "row", at: 0)
        #expect(marking.offer == .refuses)
    }

    @Test func theTargetThatArmedItClearsIt() {
        var marking = PanelDropMarking()
        marking.say(.accepts(.above(target)), from: "row", at: 0)
        marking.end(from: "row")
        #expect(marking.offer == nil)
    }

    /// A pointer crossing from one row to the next ENTERS the new one before it
    /// leaves the old, so the old row's goodbye arrives after the new row has
    /// already spoken. Honouring it would blink the mark off at every row
    /// boundary.
    @Test func aStaleGoodbyeFromTheRowBehindIsIgnored() {
        var marking = PanelDropMarking()
        marking.say(.refuses, from: "first", at: 0)
        marking.say(.accepts(nil), from: "second", at: 0.1)
        marking.end(from: "first")
        #expect(marking.offer == .accepts(nil))
        marking.end(from: "second")
        #expect(marking.offer == nil)
    }

    // MARK: - The way out that does not need the drag to report its own end

    /// The whole point of the deadline: a drag can be armed and then vanish —
    /// cancelled with escape, let go outside the window, or over a target that
    /// disappeared underneath it — and nothing ever says it ended. Without this
    /// the mark stays on the panel for good, which is the reported bug.
    @Test func aMarkNobodyClearedGoesOnItsOwnOnceNothingIsInTheAir() {
        var marking = PanelDropMarking()
        marking.say(.refuses, from: "row", at: 10)
        #expect(marking.settle(dragInTheAir: false, at: 10 + PanelDropMarking.idleGrace) == true)
        #expect(marking.offer == nil)
    }

    /// ...but not the instant a frame goes by without an update, or a drag that
    /// a walk is holding in the air with no button down would flicker off
    /// between two of its own updates.
    @Test func aMarkJustSpokenIsLeftAloneEvenWithNoButtonDown() {
        var marking = PanelDropMarking()
        marking.say(.refuses, from: "row", at: 10)
        #expect(marking.settle(dragInTheAir: false, at: 10.2) == false)
        #expect(marking.offer == .refuses)
    }

    /// A real drag holds the mouse button down the whole time it is in the air,
    /// so a pointer resting still over one row for a long moment keeps its
    /// mark.
    @Test func aMarkStandsWhileSomethingIsStillInTheAir() {
        var marking = PanelDropMarking()
        marking.say(.accepts(nil), from: "panel", at: 10)
        #expect(marking.settle(dragInTheAir: true, at: 10 + PanelDropMarking.idleGrace * 5) == false)
        #expect(marking.offer == .accepts(nil))
    }

    /// Every frame of a drag asks the target again, and each answer pushes the
    /// deadline out, so a long drag never times out under itself.
    @Test func everyAnswerPushesTheDeadlineOut() {
        var marking = PanelDropMarking()
        marking.say(.refuses, from: "row", at: 10)
        marking.say(.refuses, from: "row", at: 10 + PanelDropMarking.idleGrace * 0.9)
        #expect(marking.settle(dragInTheAir: false, at: 10 + PanelDropMarking.idleGrace) == false)
        #expect(marking.offer == .refuses)
    }

    @Test func settlingAnEmptyMarkChangesNothing() {
        var marking = PanelDropMarking()
        #expect(marking.settle(dragInTheAir: false, at: 1000) == false)
        #expect(marking.offer == nil)
    }

    /// The deadline is armed by whoever spoke last, so a mark handed from one
    /// row to another still goes on its own from the moment of the LAST word.
    @Test func theDeadlineFollowsWhoeverSpokeLast() {
        var marking = PanelDropMarking()
        marking.say(.refuses, from: "first", at: 10)
        marking.say(.refuses, from: "second", at: 10 + PanelDropMarking.idleGrace)
        #expect(marking.settle(dragInTheAir: false, at: 10 + PanelDropMarking.idleGrace) == false)
        #expect(marking.settle(dragInTheAir: false, at: 10 + PanelDropMarking.idleGrace * 2) == true)
        #expect(marking.offer == nil)
    }

    /// After it has gone on its own, the row that armed it saying goodbye late
    /// is harmless.
    @Test func aLateGoodbyeAfterTheDeadlineIsHarmless() {
        var marking = PanelDropMarking()
        marking.say(.refuses, from: "row", at: 0)
        marking.settle(dragInTheAir: false, at: PanelDropMarking.idleGrace)
        marking.end(from: "row")
        #expect(marking.offer == nil)
    }

    /// The landing the drop line in the layers list draws comes off the mark,
    /// and only an accepting one has one.
    @Test func onlyAnAcceptingMarkNamesALanding() {
        var marking = PanelDropMarking()
        marking.say(.refuses, from: "row", at: 0)
        #expect(marking.landing == nil)
        marking.say(.accepts(.below(target)), from: "row", at: 0)
        #expect(marking.landing == .below(target))
    }
}
