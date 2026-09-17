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

    @Test("Ordinary typing is not a delete key")
    func otherCharactersDoNot() {
        for character: Character in ["b", "B", " ", "\r", "\u{1B}", "\u{F702}", "0"] {
            #expect(!DeleteKeyCharacters.means(deleteKey: character))
        }
    }
}
