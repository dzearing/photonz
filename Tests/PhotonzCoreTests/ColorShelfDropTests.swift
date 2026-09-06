import Foundation
import Testing
@testable import PhotonzCore

/// Letting a colour go on the Library shelf, which is the one place a drop
/// KEEPS it rather than paints with it.
///
/// The shelf has to answer before the pointer is let go, the same way a swatch
/// does, so the whole answer is worked out here: the same answer lights the
/// shelf up, says what letting go would do, and decides whether the name field
/// opens at all.
struct ColorShelfDropTests {

    private let blue = Paint(hex: "#3B82F6")

    private func ramp() -> Paint {
        Paint(hex: "#3B82F6", kind: .linear,
              stops: [GradientStop(hex: "#3B82F6", position: 0),
                      GradientStop(hex: "#EF4444", position: 1)],
              angle: 90)
    }

    // MARK: - The ordinary drop

    @Test func aColourIsKept() {
        let answer = ColorDrop.answer(dropping: blue, on: ColorDrop.Shelf())
        #expect(answer.lightsUp)
        #expect(answer.landing?.paint == blue)
        #expect(answer.landing?.flattened == false)
        #expect(answer.landing?.letsGoOf == nil)
        #expect(answer.note == "Saves this color under a name you choose.")
    }

    /// The shelf is the one drop target with no slot behind it, so a ramp is
    /// kept aimed the way it was aimed rather than giving up its stops.
    @Test func aGradientKeepsItsRamp() {
        let answer = ColorDrop.answer(dropping: ramp(), on: ColorDrop.Shelf())
        #expect(answer.landing?.paint == ramp())
        #expect(answer.landing?.flattened == false)
        #expect(answer.note == "Saves this gradient under a name you choose.")
    }

    // MARK: - The colour that is already there

    /// A second name for one colour is a real thing to want — one blue really
    /// is both Brand and Link — so the shelf takes it rather than refusing.
    /// It says which name already has that colour first, so a drop made by
    /// accident is one Escape away from nothing.
    @Test func aColourAlreadySavedIsStillTakenAndSaysSo() {
        let shelf = ColorDrop.Shelf(alreadySaved: "Accent")
        let answer = ColorDrop.answer(dropping: blue, on: shelf)
        #expect(answer.lightsUp)
        #expect(answer.landing?.paint == blue)
        #expect(answer.note == "Accent is already this color. Saving keeps a second one.")
    }

    // MARK: - The shelf that cannot keep anything

    @Test func aShelfThatCannotSaveDoesNotLightUp() {
        let answer = ColorDrop.answer(dropping: blue, on: ColorDrop.Shelf(canSave: false))
        #expect(!answer.lightsUp)
        #expect(answer.landing == nil)
        #expect(answer.note == "Saved colors are turned off.")
    }

    /// Nothing about the shelf's answer depends on how the colour got there,
    /// so a colour dragged straight off a swatch and one dragged in from
    /// another app land the same way. (A swatch refuses the colour that came
    /// off it; the shelf has no such thing to refuse.)
    @Test func theShelfIsNeverTheSourceOfADrag() {
        let answer = ColorDrop.answer(dropping: blue, on: ColorDrop.Shelf())
        #expect(answer.lightsUp)
    }
}
