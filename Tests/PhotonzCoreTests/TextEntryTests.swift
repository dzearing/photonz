import Foundation
import Testing
@testable import PhotonzCore

/// Opening words for typing.
///
/// Double clicking a label used to drop the caret after the last letter, so
/// typing a new label left you with the old one and the new one stuck
/// together ("Button" + "Save all the changes" = "ButtonSave all the
/// changes"). Every other app offers the existing words ready to be replaced.
/// (Reported 2026-09-04.)
struct TextEntryTests {

    @Test func existingWordsOpenSelected() {
        let selection = TextEntry.openingSelection(for: "Button")
        #expect(selection.location == 0)
        #expect(selection.length == 6)
        #expect(selection.selectsEverything)
    }

    @Test func emptyFieldOpensWithACaret() {
        let selection = TextEntry.openingSelection(for: "")
        #expect(selection.location == 0)
        #expect(selection.length == 0)
        #expect(!selection.selectsEverything)
    }

    /// The length is in the units AppKit measures a selection in, so a label
    /// with an emoji in it still opens fully selected instead of stopping
    /// short and leaving half a character behind.
    @Test func lengthCountsTheWayTheFieldDoes() {
        let flag = "Save 🇺🇸"
        #expect(TextEntry.openingSelection(for: flag).length == flag.utf16.count)
        #expect(TextEntry.openingSelection(for: flag).length != flag.count)
    }

    @Test func multipleLinesAreAllOffered() {
        let selection = TextEntry.openingSelection(for: "first\nsecond")
        #expect(selection.location == 0)
        #expect(selection.length == 12)
    }
}
