import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Picking a colour up off one swatch and letting go of it on another.
///
/// A colour well on a Mac has always been something you can drag a colour out
/// of and drop a colour onto, and the panel is full of wells: Outline, Fill,
/// Text, the shadow's colour, a collage backdrop. Putting one colour on two of
/// them used to mean opening the picker twice and matching by eye.
///
/// The swatch has to answer BEFORE the pointer is let go — that is what the
/// highlight is — so the whole answer is worked out here, away from any view,
/// and the same answer feeds the highlight, the tooltip and the drop itself.
struct ColorDropTests {

    private let blue = Paint(hex: "#3B82F6")
    private let red = Paint(hex: "#EF4444")

    private func ramp() -> Paint {
        Paint(hex: "#3B82F6", kind: .linear,
              stops: [GradientStop(hex: "#3B82F6", position: 0),
                      GradientStop(hex: "#EF4444", position: 1)],
              angle: 90)
    }

    private func target(part: String = "Fill", wearing: Paint, styleName: String? = nil,
                        reaches: Int = 1, isSource: Bool = false,
                        acceptsGradient: Bool = true) -> ColorDrop.Target {
        ColorDrop.Target(part: part, wearing: wearing, styleName: styleName,
                         reaches: reaches, isSource: isSource, acceptsGradient: acceptsGradient)
    }

    // MARK: - The ordinary drop

    @Test func aDifferentColourIsTaken() {
        let answer = ColorDrop.answer(dropping: red, on: target(wearing: blue))
        #expect(answer.landing?.paint == red)
        #expect(answer.landing?.flattened == false)
        #expect(answer.landing?.letsGoOf == nil)
        #expect(answer.lightsUp)
    }

    @Test func theSentenceSaysWhatWillHappen() {
        let answer = ColorDrop.answer(dropping: red, on: target(wearing: blue))
        #expect(answer.note == "Paints Fill with this colour.")
    }

    // MARK: - The drops that change nothing

    @Test func theSwatchItCameFromDoesNotLightUp() {
        let answer = ColorDrop.answer(dropping: blue, on: target(wearing: blue, isSource: true))
        #expect(!answer.lightsUp)
        #expect(answer.landing == nil)
        #expect(answer.note == "This is where the colour came from.")
    }

    /// Dropping a colour on a swatch already wearing it is a no-op, and a
    /// no-op that lights up and writes an undo step is worse than one that
    /// says so.
    @Test func aSwatchAlreadyWearingItDoesNotLightUp() {
        let answer = ColorDrop.answer(dropping: Paint(hex: "#3b82f6"), on: target(wearing: blue))
        #expect(!answer.lightsUp)
        #expect(answer.note == "Fill is already this colour.")
    }

    /// ...but a swatch wearing a SAVED colour that happens to be the same one
    /// still has something to do: letting go takes it off the saved colour.
    @Test func aStyledSwatchWearingTheSameColourStillTakesIt() {
        let answer = ColorDrop.answer(dropping: blue,
                                      on: target(wearing: blue, styleName: "Accent"))
        #expect(answer.lightsUp)
        #expect(answer.landing?.letsGoOf == "Accent")
    }

    @Test func aSwatchWithNothingBehindItDoesNotLightUp() {
        let answer = ColorDrop.answer(dropping: red, on: target(wearing: blue, reaches: 0))
        #expect(!answer.lightsUp)
        #expect(answer.note == "There is nothing here to paint.")
    }

    // MARK: - A saved colour is let go of out loud

    @Test func droppingOnASavedColourSaysWhatItLetsGoOf() {
        let answer = ColorDrop.answer(dropping: red,
                                      on: target(wearing: blue, styleName: "Accent"))
        #expect(answer.landing?.letsGoOf == "Accent")
        #expect(answer.note == "Paints Fill with this colour and lets go of Accent.")
    }

    @Test func severalLayersSayHowMany() {
        let answer = ColorDrop.answer(dropping: red, on: target(wearing: blue, reaches: 3))
        #expect(answer.note == "Paints Fill on all 3 of them with this colour.")
    }

    // MARK: - Gradients

    @Test func aSlotThatHoldsARampKeepsIt() {
        let answer = ColorDrop.answer(dropping: ramp(), on: target(wearing: red))
        #expect(answer.landing?.paint == ramp())
        #expect(answer.landing?.flattened == false)
    }

    /// A slot that cannot hold a ramp still takes the colour rather than
    /// refusing — the document has always flattened a paint that lands
    /// somewhere flat — but the swatch says so first, so nobody drops a
    /// gradient on Text and wonders where it went.
    @Test func aSlotThatCannotHoldARampTakesItsFlatColour() {
        let answer = ColorDrop.answer(dropping: ramp(),
                                      on: target(part: "Text", wearing: red,
                                                 acceptsGradient: false))
        #expect(answer.landing?.paint == Paint(hex: "#3B82F6"))
        #expect(answer.landing?.flattened == true)
        #expect(answer.note == "Text cannot hold a gradient, so it takes its flat colour.")
    }

    @Test func aFlattenedRampThatMatchesWhatIsThereChangesNothing() {
        let answer = ColorDrop.answer(dropping: ramp(),
                                      on: target(wearing: blue, acceptsGradient: false))
        #expect(!answer.lightsUp)
    }

    // MARK: - What the colour in flight says about itself

    @Test func aWellWithNoSlotTakesFlatColoursOnly() {
        let shadow = ColorDrop.Target(part: "Shadow", wearing: Paint(hex: "#000000"),
                                      styleName: nil, reaches: 1, isSource: false,
                                      acceptsGradient: false)
        let answer = ColorDrop.answer(dropping: ramp(), on: shadow)
        #expect(answer.landing?.paint == Paint(hex: "#3B82F6"))
        #expect(answer.landing?.flattened == true)
    }

    // MARK: - A swatch that names itself in words

    /// The panel's swatches are named after their row — "Fill", "Outline" —
    /// but the toolbar's swatch has no row: what it stands for is the next
    /// shape you draw, and the only honest name for it is those words. So a
    /// part may be a phrase, and the sentence that STARTS with it capitalises
    /// it rather than reading "the next shape is already this colour."
    @Test func aPartThatIsAPhraseReadsMidSentence() {
        let answer = ColorDrop.answer(dropping: red,
                                      on: target(part: "the next shape", wearing: blue))
        #expect(answer.note == "Paints the next shape with this colour.")
    }

    @Test func aPartThatIsAPhraseIsCapitalisedWhenItStartsTheSentence() {
        let answer = ColorDrop.answer(dropping: blue,
                                      on: target(part: "the next shape's border", wearing: blue))
        #expect(!answer.lightsUp)
        #expect(answer.note == "The next shape's border is already this colour.")
    }

    @Test func aPhrasePartIsCapitalisedInTheGradientSentenceToo() {
        let answer = ColorDrop.answer(dropping: ramp(),
                                      on: target(part: "the text you type next", wearing: red,
                                                 acceptsGradient: false))
        #expect(answer.note
                == "The text you type next cannot hold a gradient, so it takes its flat colour.")
    }

    /// A row's own label is left exactly as the row writes it: capitalising
    /// the first letter of "Fill" changes nothing, which is the point.
    @Test func aRowLabelIsUntouched() {
        let answer = ColorDrop.answer(dropping: blue, on: target(part: "Outline", wearing: blue))
        #expect(answer.note == "Outline is already this colour.")
    }
}
