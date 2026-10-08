import PhotonzCore
import Testing

/// A section the dock stops showing leaves the screen at once and is pulled
/// down a pass later. These tests pin when it lingers (the pick stayed on the
/// same thing, as a click on a clip's cut does), when it goes at once (the
/// pick moved, as Undo can), that a lingering section wanted again simply
/// comes back, and that a pass called twice says the same thing.
@Suite("PanelSectionDeparture")
struct PanelSectionDepartureTests {

    /// A clip's dock with the clip's piece picked, and the same clip's dock a
    /// click on one of its cuts later.
    let piece = ["keys", "time", "appearance", "effects", "sound", "edit", "transition", "transitions"]
    let cut = ["edit", "transition", "transitions"]

    @Test func nothingLingersOnTheFirstPass() {
        var departure = PanelSectionDeparture()
        #expect(departure.draw(piece, pick: "clip").isEmpty)
    }

    @Test func aClickOnACutOfTheSameClipLeavesTheClipSectionsForAPass() {
        var departure = PanelSectionDeparture()
        departure.draw(piece, pick: "clip")
        let lingering = departure.draw(cut, pick: "clip")
        // In the order they stood, so nothing is shuffled on the way out.
        #expect(lingering == ["keys", "time", "appearance", "effects", "sound"])
        #expect(departure.isHolding)
    }

    @Test func aPickThatMovesTakesEverythingAwayAtOnce() {
        // Undo of a cut puts the pick back to nothing: what the clip's sections
        // would draw with no clip is not theirs to draw, so none of them stay.
        var departure = PanelSectionDeparture()
        departure.draw(piece, pick: "clip")
        #expect(departure.draw(["time", "captions"], pick: nil).isEmpty)
        #expect(departure.isHolding == false)
    }

    @Test func aPickThatMovesWhileSomethingLingersLetsItGoToo() {
        var departure = PanelSectionDeparture()
        departure.draw(piece, pick: "clip")
        departure.draw(cut, pick: "clip")
        #expect(departure.draw(["keys", "time"], pick: "other").isEmpty)
    }

    @Test func releasingLetsTheLingeringSectionsGo() {
        var departure = PanelSectionDeparture()
        departure.draw(piece, pick: "clip")
        departure.draw(cut, pick: "clip")
        departure.release()
        #expect(departure.isHolding == false)
        #expect(departure.draw(cut, pick: "clip").isEmpty)
    }

    @Test func aSecondCallInTheSamePassSaysTheSame() {
        // SwiftUI may ask for the dock's body twice in one pass.
        var departure = PanelSectionDeparture()
        departure.draw(piece, pick: "clip")
        let first = departure.draw(cut, pick: "clip")
        let second = departure.draw(cut, pick: "clip")
        #expect(first == second)
    }

    @Test func aLingeringSectionWantedAgainComesStraightBack() {
        // Cut, then the piece again before the pass that pulls them down: the
        // clip's sections are still built, so they are simply shown.
        var departure = PanelSectionDeparture()
        departure.draw(piece, pick: "clip")
        departure.draw(cut, pick: "clip")
        let lingering = departure.draw(piece, pick: "clip")
        #expect(lingering.isEmpty)
        #expect(departure.isHolding == false)
    }

    @Test func onlyWhatIsStillUnwantedKeepsLingering() {
        var departure = PanelSectionDeparture()
        departure.draw(piece, pick: "clip")
        departure.draw(cut, pick: "clip")
        let lingering = departure.draw(["keys", "edit", "transition", "transitions"], pick: "clip")
        #expect(lingering == ["time", "appearance", "effects", "sound"])
    }

    @Test func sectionsLeavingAcrossTwoPassesAllLinger() {
        var departure = PanelSectionDeparture()
        departure.draw(["a", "b", "c"], pick: "clip")
        departure.draw(["a", "c"], pick: "clip")
        #expect(departure.draw(["c"], pick: "clip") == ["b", "a"])
    }

    @Test func turnedOffNothingLingers() {
        var departure = PanelSectionDeparture()
        departure.draw(piece, pick: "clip", lingers: false)
        #expect(departure.draw(cut, pick: "clip", lingers: false).isEmpty)
    }
}
