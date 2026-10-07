import CoreGraphics
import Testing
@testable import PhotonzCore

/// A list that opens over the panel (Animate a property's picker): where it
/// sits, and what a key does to its find box.
struct PanelDropdownTests {
    // MARK: Placement

    @Test func opensAtTheTopOfWhatItOpensOverInsetEitherSide() {
        let frame = PanelDropdown.frame(over: CGRect(x: 0, y: 120, width: 300, height: 200),
                                        in: CGSize(width: 300, height: 800), height: 300)
        #expect(frame == CGRect(x: 8, y: 120, width: 284, height: 300))
    }

    @Test func comesDownIntoViewWhenTheSectionTopHasScrolledAway() {
        let frame = PanelDropdown.frame(over: CGRect(x: 0, y: -90, width: 300, height: 400),
                                        in: CGSize(width: 300, height: 800), height: 300)
        #expect(frame.minY == 8)
    }

    @Test func goesUpRatherThanHangOffTheBottom() {
        let frame = PanelDropdown.frame(over: CGRect(x: 0, y: 700, width: 300, height: 60),
                                        in: CGSize(width: 300, height: 800), height: 300)
        #expect(frame.minY == 492)
        #expect(frame.maxY == 792)
    }

    @Test func neverTallerThanThePanel() {
        let frame = PanelDropdown.frame(over: CGRect(x: 0, y: 40, width: 300, height: 60),
                                        in: CGSize(width: 300, height: 200), height: 300)
        #expect(frame == CGRect(x: 8, y: 8, width: 284, height: 184))
    }

    @Test func keepsInsideThePanelSides() {
        let frame = PanelDropdown.frame(over: CGRect(x: -20, y: 10, width: 360, height: 60),
                                        in: CGSize(width: 300, height: 800), height: 100)
        #expect(frame.minX == 8)
        #expect(frame.maxX == 292)
    }

    // MARK: The find box

    @Test func lettersDigitsAndSpacesAreTyped() {
        #expect(PanelDropdown.key(keyCode: 0, characters: "a") == .text("a"))
        #expect(PanelDropdown.key(keyCode: 18, characters: "1") == .text("1"))
        #expect(PanelDropdown.key(keyCode: 49, characters: " ") == .text(" "))
        #expect(PanelDropdown.key(keyCode: 14, characters: "é") == .text("é"))
    }

    @Test func deleteTakesTheLastLetterAndReturnPicks() {
        #expect(PanelDropdown.key(keyCode: 51, characters: "\u{7F}") == .deleteBackward)
        #expect(PanelDropdown.key(keyCode: 36, characters: "\r") == .submit)
        #expect(PanelDropdown.key(keyCode: 76, characters: "\u{3}") == .submit)
    }

    @Test func arrowsTabAndFunctionKeysTypeNothing() {
        #expect(PanelDropdown.key(keyCode: 126, characters: "\u{F700}") == nil)
        #expect(PanelDropdown.key(keyCode: 125, characters: "\u{F701}") == nil)
        #expect(PanelDropdown.key(keyCode: 48, characters: "\t") == nil)
        #expect(PanelDropdown.key(keyCode: 122, characters: "\u{F704}") == nil)
        #expect(PanelDropdown.key(keyCode: 53, characters: "\u{1B}") == nil)
    }

    @Test func typingEditsTheQuery() {
        var query = "pos"
        PanelDropdown.apply(.text("i"), to: &query)
        #expect(query == "posi")
        PanelDropdown.apply(.deleteBackward, to: &query)
        PanelDropdown.apply(.deleteBackward, to: &query)
        #expect(query == "po")
        query = ""
        PanelDropdown.apply(.deleteBackward, to: &query)
        #expect(query == "")
        PanelDropdown.apply(.text("Shadow\n1"), to: &query)
        #expect(query == "Shadow 1")
    }
}
