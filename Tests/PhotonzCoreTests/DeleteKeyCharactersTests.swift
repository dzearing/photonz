import Foundation
import PhotonzCore
import Testing

/// The one thing this type exists to hold: ⌫ is U+007F, not the backspace
/// control character SwiftUI names `.delete`.
@Suite("Delete key characters")
struct DeleteKeyCharactersTests {

    @Test("The delete key above Return is U+007F, what a Mac keyboard really sends")
    func backwardsIsDeleteCharacter() {
        #expect(DeleteKeyCharacters.backwards == "\u{7F}")
        #expect(DeleteKeyCharacters.backwards != DeleteKeyCharacters.backspaceControl)
    }

    @Test("Forward delete is the function-key scalar")
    func forwardsIsFunctionKey() {
        #expect(DeleteKeyCharacters.forwards == "\u{F728}")
    }

    @Test("All three ways a delete key arrives are recognised")
    func everyDeleteCharacterCounts() {
        #expect(DeleteKeyCharacters.means(deleteKey: "\u{7F}"))
        #expect(DeleteKeyCharacters.means(deleteKey: "\u{F728}"))
        #expect(DeleteKeyCharacters.means(deleteKey: "\u{8}"))
    }

    /// The other half of the same fact, and the one that cost a walk five
    /// days: a MENU row that wants ⌫ has to carry U+0008, because AppKit
    /// normalises the press to backspace before it looks along the menu bar.
    /// Measured on 2026-09-22 against a real ⌫ built by CoreGraphics: a menu
    /// holding U+007F never matched it, one holding U+0008 matched every time,
    /// bare and with ⌘ and with ⌥. A field with the keyboard still keeps the
    /// key either way, so the row is safe to make live.
    @Test("A menu row that wants ⌫ carries U+0008, which is not what the key sends")
    func menuKeyEquivalentIsBackspace() {
        #expect(DeleteKeyCharacters.menuKeyEquivalent == "\u{8}")
        #expect(DeleteKeyCharacters.menuKeyEquivalent != DeleteKeyCharacters.backwards)
        #expect(DeleteKeyCharacters.menuKeyEquivalent == DeleteKeyCharacters.backspaceControl)
    }

    @Test("The menu's character still reads as a delete key when one arrives that way")
    func menuKeyEquivalentIsADeleteKey() {
        #expect(DeleteKeyCharacters.means(deleteKey: DeleteKeyCharacters.menuKeyEquivalent))
    }

    @Test("Ordinary typing is not a delete key")
    func otherCharactersDoNot() {
        for character: Character in ["b", "B", " ", "\r", "\u{1B}", "\u{F702}", "0"] {
            #expect(!DeleteKeyCharacters.means(deleteKey: character))
        }
    }
}
