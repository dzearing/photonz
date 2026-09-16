import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("What a typed number box does with what is in it")
struct NumberBoxTests {

    // MARK: What the box is showing

    @Test("A number is a number, a word is a stand-in, nothing is nothing")
    func showingTellsTheThreeApart() {
        #expect(NumberBox.Showing.number("296").text == "296")
        #expect(!NumberBox.Showing.number("296").isStandIn)
        #expect(NumberBox.Showing.standIn(MixedValue.text).isStandIn)
        #expect(NumberBox.Showing.nothing.text.isEmpty)
        #expect(!NumberBox.Showing.nothing.isStandIn)
    }

    @Test("Mixed is the one stand-in drawn at the quieter strength")
    func onlyMixedReadsAsMixed() {
        #expect(NumberBox.Showing.standIn(MixedValue.text).isMixed)
        // A stand-in naming a real state is a value, not an absence.
        #expect(!NumberBox.Showing.standIn("Spread").isMixed)
        #expect(!NumberBox.Showing.standIn("10 20 10 20").isMixed)
        #expect(!NumberBox.Showing.number("296").isMixed)
        #expect(!NumberBox.Showing.nothing.isMixed)
    }

    @Test("A stand-in made of numbers is told from one made of words")
    func standInOfNumbersIsKnown() {
        #expect(NumberBox.Showing.standIn("10 20 10 20").standsInForNumbers)
        #expect(!NumberBox.Showing.standIn(MixedValue.text).standsInForNumbers)
        #expect(!NumberBox.Showing.number("296").standsInForNumbers)
    }

    @Test("A number it has, a word it stands in with, or nothing")
    func showingFromAValueAndAStandIn() {
        #expect(NumberBox.showing(12, standingIn: MixedValue.text) == .number("12"))
        #expect(NumberBox.showing(12.6, standingIn: "") == .number("13"),
                "a box of whole numbers shows a whole number")
        #expect(NumberBox.showing(nil, standingIn: MixedValue.text) == .standIn(MixedValue.text))
        #expect(NumberBox.showing(nil, standingIn: "") == .nothing,
                "no number and nothing to stand in with is an empty box")
    }

    // MARK: Landing the draft

    @Test("A number lands")
    func aNumberLands() {
        let landing = NumberBox.landing(draft: "296", showing: .number("200"),
                                        canClear: false, floor: nil, wholeNumbers: false)
        #expect(landing == .land(296))
    }

    @Test("Text that is not a number changes nothing and puts the box back")
    func nonsensePutsItBack() {
        for draft in ["wide", "1e9", "296,5", "-", "12 34"] {
            #expect(NumberBox.landing(draft: draft, showing: .number("200"),
                                      canClear: false, floor: nil, wholeNumbers: false) == .putBack,
                    "\(draft) is not one number")
        }
    }

    @Test("A floor holds a number that went under it")
    func floorHolds() {
        #expect(NumberBox.landing(draft: "-5", showing: .number("0"), canClear: false,
                                  floor: 0, wholeNumbers: true) == .land(0))
        #expect(NumberBox.landing(draft: "-5", showing: .number("0"), canClear: false,
                                  floor: nil, wholeNumbers: true) == .land(-5),
                "a position may go negative, so a box with no floor keeps the minus")
    }

    @Test("A ceiling holds a number that went over it")
    func ceilingHolds() {
        #expect(NumberBox.landing(draft: "140", showing: .number("60"), canClear: false,
                                  floor: 0, ceiling: 100, wholeNumbers: true) == .land(100))
        #expect(NumberBox.stepping(draft: "100", direction: 1, coarse: true,
                                   floor: 0, ceiling: 100, wholeNumbers: true,
                                   stepsEach: false) == .to(100),
                "a strength that means nothing past 100 holds at 100")
    }

    @Test("A box that counts in whole numbers rounds what was typed")
    func wholeNumbersRound() {
        #expect(NumberBox.landing(draft: "12.6", showing: .number("8"), canClear: false,
                                  floor: 0, wholeNumbers: true) == .land(13))
        #expect(NumberBox.landing(draft: "12.6", showing: .number("8"), canClear: false,
                                  floor: nil, wholeNumbers: false) == .land(12.6),
                "a box that does not count in whole numbers keeps the fraction")
    }

    @Test("A pasted unit does not stop the number landing")
    func unitsSurvive() {
        #expect(NumberBox.landing(draft: "296 px", showing: .number("200"), canClear: false,
                                  floor: nil, wholeNumbers: false) == .land(296))
        #expect(NumberBox.landing(draft: "45\u{00B0}", showing: .number("0"), canClear: false,
                                  floor: nil, wholeNumbers: false) == .land(45))
    }

    // MARK: Emptying it

    @Test("Emptying a box that may be cleared clears it")
    func emptyingClears() {
        #expect(NumberBox.landing(draft: "", showing: .number("40"), canClear: true,
                                  floor: nil, wholeNumbers: true) == .clear)
        #expect(NumberBox.landing(draft: "   ", showing: .number("40"), canClear: true,
                                  floor: nil, wholeNumbers: true) == .clear,
                "spaces are as empty as empty")
    }

    @Test("Emptying a box that may not be cleared puts its number back")
    func emptyingSnapsBack() {
        #expect(NumberBox.landing(draft: "", showing: .number("40"), canClear: false,
                                  floor: nil, wholeNumbers: true) == .putBack)
    }

    @Test("Emptying a box standing in for several values puts the word back")
    func emptyingAStandInPutsTheWordBack() {
        // Not a clear: there is no one value to take away, and a box left
        // blank reads as a row that failed to draw.
        #expect(NumberBox.landing(draft: "", showing: .standIn(MixedValue.text), canClear: true,
                                  floor: nil, wholeNumbers: true) == .putBack)
        #expect(NumberBox.landing(draft: "", showing: .standIn(MixedValue.text), canClear: false,
                                  floor: nil, wholeNumbers: true) == .putBack)
    }

    @Test("Emptying a box that was already empty does nothing at all")
    func emptyingNothingDoesNothing() {
        #expect(NumberBox.landing(draft: "", showing: .nothing, canClear: true,
                                  floor: nil, wholeNumbers: true) == .putBack)
    }

    // MARK: The arrow keys

    @Test("Up and down step by one, and Shift steps by ten")
    func arrowsStep() {
        #expect(NumberBox.stepping(draft: "296", direction: 1, coarse: false,
                                   floor: nil, stepsEach: false) == .to(297))
        #expect(NumberBox.stepping(draft: "296", direction: -1, coarse: false,
                                   floor: nil, stepsEach: false) == .to(295))
        #expect(NumberBox.stepping(draft: "296", direction: 1, coarse: true,
                                   floor: nil, stepsEach: false) == .to(306))
        #expect(NumberBox.stepping(draft: "296", direction: -1, coarse: true,
                                   floor: nil, stepsEach: false) == .to(286))
    }

    @Test("A step walks the number that is on screen, fraction and all")
    func steppingWalksWhatIsShown() {
        // A frame off a drag carries a fraction nobody typed, but the BOX
        // shows 296, so the arrow walks 296, 297, 298 and never drifts on a
        // half nobody saw. Where the box really does show a fraction -- an
        // angle of 12.5 degrees -- the step keeps it, because 13.5 is what the
        // person pressing the key meant.
        #expect(NumberBox.stepping(draft: "296", direction: 1, coarse: false,
                                   floor: nil, stepsEach: false) == .to(297))
        #expect(NumberBox.stepping(draft: "12.5", direction: 1, coarse: false,
                                   floor: nil, stepsEach: false) == .to(13.5))
        #expect(NumberBox.stepping(draft: "12.5", direction: -1, coarse: false,
                                   floor: nil, stepsEach: false) == .to(11.5))
    }

    @Test("A box of whole numbers steps to a whole number")
    func steppingRoundsWhereItCounts() {
        #expect(NumberBox.stepping(draft: "12.6", direction: 1, coarse: false,
                                   floor: 0, wholeNumbers: true, stepsEach: false) == .to(14))
        #expect(NumberBox.stepping(draft: "12", direction: 1, coarse: false,
                                   floor: 0, wholeNumbers: true, stepsEach: false) == .to(13))
    }

    @Test("A step holds at the floor rather than counting on below it")
    func steppingHoldsAtTheFloor() {
        #expect(NumberBox.stepping(draft: "0", direction: -1, coarse: false,
                                   floor: 0, stepsEach: false) == .to(0))
        #expect(NumberBox.stepping(draft: "4", direction: -1, coarse: true,
                                   floor: 0, stepsEach: false) == .to(0))
    }

    @Test("An arrow on a box with no number in it steps each thing from its own")
    func steppingEach() {
        #expect(NumberBox.stepping(draft: MixedValue.text, direction: 1, coarse: false,
                                   floor: nil, stepsEach: true) == .each(direction: 1, coarse: false))
        #expect(NumberBox.stepping(draft: "", direction: -1, coarse: true,
                                   floor: nil, stepsEach: true) == .each(direction: -1, coarse: true))
    }

    @Test("An arrow on a box with no number and nothing to step does nothing")
    func steppingNothing() {
        // Inventing a nought here would flatten four sides that disagree into
        // one number nobody typed.
        #expect(NumberBox.stepping(draft: MixedValue.text, direction: 1, coarse: false,
                                   floor: nil, stepsEach: false) == .nothing)
        #expect(NumberBox.stepping(draft: "10 20 10 20", direction: 1, coarse: false,
                                   floor: nil, stepsEach: false) == .nothing)
        #expect(NumberBox.stepping(draft: "", direction: 1, coarse: false,
                                   floor: nil, stepsEach: false) == .nothing)
    }

    // MARK: Not landing the number that is already there

    @Test("The number the box already shows is not landed again")
    func alreadyShowingIsNotLanded() {
        #expect(NumberBox.alreadyShowing(40, showing: .number("40")))
        #expect(NumberBox.alreadyShowing(45, showing: .number("45\u{00B0}")),
                "the unit mark on screen is not part of the number")
        #expect(!NumberBox.alreadyShowing(41, showing: .number("40")))
    }

    @Test("A box with no one number in it always lands what was typed")
    func standInAlwaysLands() {
        // Mixed is not a number, so typing 40 over it really does set 40 on
        // everything, even the ones that already had it.
        #expect(!NumberBox.alreadyShowing(40, showing: .standIn(MixedValue.text)))
        #expect(!NumberBox.alreadyShowing(40, showing: .nothing))
    }

    @Test("An arrow steps the half-typed draft, not the number behind it")
    func steppingUsesTheDraft() {
        #expect(NumberBox.stepping(draft: "50", direction: 1, coarse: false,
                                   floor: nil, stepsEach: false) == .to(51))
    }
}
