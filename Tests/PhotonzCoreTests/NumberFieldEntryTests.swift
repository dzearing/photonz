import Foundation
import Testing
@testable import PhotonzCore

@Suite("The keys of a typed number field")
struct NumberFieldEntryTests {

    // MARK: Finishing

    @Test("Return lands the number and hands the keyboard back")
    func returnCommitsAndReleases() {
        let action = NumberFieldEntry.action(for: .return, shift: false)
        #expect(action == .commitAndRelease)
        #expect(NumberFieldEntry.lands(action))
        #expect(NumberFieldEntry.releasesKeyboard(action))
    }

    @Test("Escape puts the number back and hands the keyboard back")
    func escapeRevertsAndReleases() {
        let action = NumberFieldEntry.action(for: .escape, shift: false)
        #expect(action == .revertAndRelease)
        #expect(!NumberFieldEntry.lands(action), "an abandoned draft must never reach the layer")
        #expect(NumberFieldEntry.releasesKeyboard(action))
    }

    @Test("Shift does not change what Return or Escape mean")
    func modifiersDoNotChangeFinishing() {
        #expect(NumberFieldEntry.action(for: .return, shift: true) == .commitAndRelease)
        #expect(NumberFieldEntry.action(for: .escape, shift: true) == .revertAndRelease)
    }

    // MARK: Stepping

    @Test("Up and down step the number without letting go of the keyboard")
    func arrowsStep() {
        let up = NumberFieldEntry.action(for: .upArrow, shift: false)
        let down = NumberFieldEntry.action(for: .downArrow, shift: false)
        #expect(up == .step(direction: 1, coarse: false))
        #expect(down == .step(direction: -1, coarse: false))
        #expect(!NumberFieldEntry.releasesKeyboard(up), "stepping is still working in the field")
        #expect(!NumberFieldEntry.releasesKeyboard(down))
    }

    @Test("Shift and an arrow steps by the coarse amount")
    func shiftArrowsStepCoarse() {
        #expect(NumberFieldEntry.action(for: .upArrow, shift: true) == .step(direction: 1, coarse: true))
        #expect(NumberFieldEntry.action(for: .downArrow, shift: true) == .step(direction: -1, coarse: true))
    }

    @Test("A stepped number moves by the same 1 and 10 the canvas nudges by")
    func steppingMatchesTheCanvas() {
        guard case .step(let direction, let coarse) = NumberFieldEntry.action(for: .upArrow, shift: true) else {
            Issue.record("shift and up is a step")
            return
        }
        #expect(LayerGeometry.stepped(296, direction: direction, coarse: coarse) == 306)
        #expect(LayerGeometry.coarseStep == Nudge.delta(keyCode: 126, large: true)?.dy.magnitude,
                "a coarse step in a field and a coarse nudge on the canvas are the same 10 points")
    }

    // MARK: Typing

    @Test("Every other key types, so a tool letter never steals a digit mid-edit")
    func otherKeysType() {
        let action = NumberFieldEntry.action(for: .other, shift: false)
        #expect(action == .type)
        #expect(!NumberFieldEntry.lands(action))
        #expect(!NumberFieldEntry.releasesKeyboard(action))
    }
}
