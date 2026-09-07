import CoreGraphics
import Testing
@testable import PhotonzCore

/// What the Font menu offers, and what it says when a name is too long for the
/// box. The width itself is AppKit's to measure; these are the two decisions
/// around it that are ours.
@Suite struct FontMenuOptionsTests {

    // MARK: - What the menu offers

    @Test func offersTheCuratedListWhenNothingElseIsInPlay() {
        #expect(TextStyles.fontOptions(picked: ["SF Pro"]) == TextStyles.fonts)
    }

    @Test func offersTheCuratedListForAnEmptySelection() {
        #expect(TextStyles.fontOptions(picked: []) == TextStyles.fonts)
    }

    @Test func keepsAFamilyTheLabelsAlreadyWear() {
        let options = TextStyles.fontOptions(picked: ["Bodoni 72 Smallcaps"])
        #expect(options == TextStyles.fonts + ["Bodoni 72 Smallcaps"])
    }

    @Test func neverRepeatsAFamily() {
        let options = TextStyles.fontOptions(picked: ["Rockwell", "Georgia", "Rockwell"])
        #expect(options == TextStyles.fonts + ["Rockwell"])
    }

    /// The curated part comes first and in its own order, always. That is what
    /// lets the menu hold one width: the widest curated name is present in
    /// every state the menu can be in, so it, and nothing else, sets the size.
    @Test func alwaysStartsWithTheCuratedListInOrder() {
        let options = TextStyles.fontOptions(picked: ["Rockwell", "Papyrus"])
        #expect(Array(options.prefix(TextStyles.fonts.count)) == TextStyles.fonts)
    }

    @Test func keepsSeveralExtrasInThePickedOrder() {
        let options = TextStyles.fontOptions(picked: ["Rockwell", "Papyrus"])
        #expect(options.suffix(2) == ["Rockwell", "Papyrus"])
    }

    // MARK: - What a shortened menu says when hovered

    @Test func aMenuThatShowsItAllJustSaysWhatItIs() {
        #expect(MenuTip.text(about: "The font of this text",
                             showing: "SF Pro", isClipped: false) == "The font of this text")
    }

    @Test func aShortenedNameIsSaidInFullFirst() {
        #expect(MenuTip.text(about: "The font of this text",
                             showing: "Bodoni 72 Smallcaps", isClipped: true)
                == "Bodoni 72 Smallcaps, the font of this text")
    }

    /// Mixed selections show no value at all, so there is nothing to carry.
    @Test func aMenuWithNoValueSaysWhatItIs() {
        #expect(MenuTip.text(about: "The font of all 3 selected layers",
                             showing: nil, isClipped: true) == "The font of all 3 selected layers")
    }

    @Test func anEmptyValueSaysWhatItIs() {
        #expect(MenuTip.text(about: "The font of this text",
                             showing: "", isClipped: true) == "The font of this text")
    }

    /// The sentence keeps reading as a sentence: only the first letter moves
    /// down, so a name that is itself capitalised is untouched.
    @Test func onlyTheFirstLetterOfTheSentenceChanges() {
        #expect(MenuTip.text(about: "The font of ALL text",
                             showing: "Papyrus", isClipped: true) == "Papyrus, the font of ALL text")
    }
}
