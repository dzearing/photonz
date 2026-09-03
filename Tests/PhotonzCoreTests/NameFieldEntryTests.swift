import Foundation
import Testing
@testable import PhotonzCore

@Suite("The keys of a typed name field")
struct NameFieldEntryTests {

    // MARK: Finishing

    @Test("Return lands the name and hands the keyboard back")
    func returnCommitsAndReleases() {
        let action = NameFieldEntry.action(for: .return)
        #expect(action == .commitAndRelease)
        #expect(NameFieldEntry.lands(action))
        #expect(NameFieldEntry.releasesKeyboard(action))
    }

    @Test("Escape puts things back and hands the keyboard back")
    func escapeRevertsAndReleases() {
        let action = NameFieldEntry.action(for: .escape)
        #expect(action == .revertAndRelease)
        #expect(!NameFieldEntry.lands(action), "an abandoned draft must never reach the document")
        #expect(NameFieldEntry.releasesKeyboard(action))
    }

    // MARK: Typing

    @Test("Every other key types, so a tool letter never steals a letter mid-edit")
    func otherKeysType() {
        let action = NameFieldEntry.action(for: .other)
        #expect(action == .type)
        #expect(!NameFieldEntry.lands(action))
        #expect(!NameFieldEntry.releasesKeyboard(action))
    }

    @Test("A name field finishes on the same two keys a number field does")
    func matchesTheNumberField() {
        #expect(NameFieldEntry.releasesKeyboard(NameFieldEntry.action(for: .return))
                == NumberFieldEntry.releasesKeyboard(NumberFieldEntry.action(for: .return, shift: false)))
        #expect(NameFieldEntry.releasesKeyboard(NameFieldEntry.action(for: .escape))
                == NumberFieldEntry.releasesKeyboard(NumberFieldEntry.action(for: .escape, shift: false)))
        #expect(NameFieldEntry.lands(NameFieldEntry.action(for: .return))
                == NumberFieldEntry.lands(NumberFieldEntry.action(for: .return, shift: false)))
    }

    @Test("Up and down are caret movement, not a step: a name has no next value")
    func arrowsDoNotStep() {
        // The arrows arrive as `other`, which is the whole point: nothing in a
        // name field answers them, so they stay the field editor's business.
        #expect(NameFieldEntry.action(for: .other) == .type)
    }

    // MARK: What lands

    @Test("Edges are trimmed off a name before it lands")
    func landedNameIsTrimmed() {
        #expect(NameFieldEntry.landedName("  Save button  ") == "Save button")
    }

    @Test("A blank name is refused, so nothing ends up nameless")
    func blankNameIsRefused() {
        #expect(NameFieldEntry.landedName("") == nil)
        #expect(NameFieldEntry.landedName("   ") == nil)
    }
}
