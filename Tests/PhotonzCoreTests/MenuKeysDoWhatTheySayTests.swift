import Foundation
import Testing
@testable import PhotonzCore

/// **Every key a menu prints beside a row does what the row says**
/// (`find-out-whether-the-layer-menu-promises-a-dupli`).
///
/// Measured on 2026-09-28 in the probe with its menu bar live: ⌘⌫ and ⌥⌫ never
/// reached Layer ▸ Delete Layer and Edit ▸ Fill with Foreground, because those
/// rows carried U+007F and AppKit matches a real ⌫ against U+0008 only; and the
/// layer row menu printed ⌘D beside Duplicate while ⌘D is Deselect.
@Suite("Menu keys do what they say")
struct MenuKeysDoWhatTheySayTests {

    @Test("Next has it at its defaults, and Current never offers it")
    func nextOnly() {
        #expect(FeatureCatalog.defaultSettings(for: .next).isEnabled(FeatureCatalog.menuKeysDoWhatTheySayFlag))
        #expect(!FeatureCatalog.flags(for: .current).contains { $0.name == FeatureCatalog.menuKeysDoWhatTheySayFlag })
    }

    @Test("A row that has to answer ⌫ carries the character AppKit matches the press against")
    func aLiveRowCarriesBackspace() {
        #expect(DeleteKeyCharacters.menuRow(answersThePress: true) == "\u{8}")
        #expect(DeleteKeyCharacters.menuRow(answersThePress: true) == DeleteKeyCharacters.menuKeyEquivalent)
    }

    @Test("Off, a row keeps the character it always carried")
    func offKeepsTheOldCharacter() {
        #expect(DeleteKeyCharacters.menuRow(answersThePress: false) == DeleteKeyCharacters.backwards)
    }
}
