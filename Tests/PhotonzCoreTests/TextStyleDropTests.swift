import Foundation
import Testing
@testable import PhotonzCore

/// Picking a saved text style up off the Library shelf and letting go of it on
/// a piece of text.
///
/// A saved colour has always been something you could pick up off its tile and
/// drop on a swatch, which is what makes the shelf a place styles come FROM. A
/// text style could only be worn by selecting the text and finding the name in
/// a menu, so the shelf was a place text styles went and never came back out
/// of.
///
/// The picture has to answer BEFORE the pointer is let go, so the whole answer
/// is worked out here, away from any view: the outline round the text, the one
/// line that says what letting go would do, and the drop itself all read the
/// same answer.
struct TextStyleDropTests {

    private let heading = TextStyleDrop.SavedStyle(id: UUID(), name: "Heading")

    private func text(_ name: String = "Title", wearing: TextStyleDrop.SavedStyle? = nil,
                      reaches: Int = 1) -> TextStyleDrop.Target {
        TextStyleDrop.Target(name: name, isText: true, wearingID: wearing?.id,
                             wearingName: wearing?.name, reaches: reaches)
    }

    // MARK: - The ordinary drop

    @Test func textTakesTheStyle() {
        let answer = TextStyleDrop.answer(dropping: heading, on: text())
        #expect(answer.lands)
        #expect(answer.note == "Sets this text in Heading.")
        #expect(answer.letsGoOf == nil)
    }

    /// Text already wearing a DIFFERENT name is re-dressed, and the name it is
    /// letting go of is said out loud first: that is a thing somebody would
    /// rather know before letting go than after.
    @Test func textWearingAnotherStyleSaysWhatItLetsGoOf() {
        let caption = TextStyleDrop.SavedStyle(id: UUID(), name: "Caption")
        let answer = TextStyleDrop.answer(dropping: heading, on: text(wearing: caption))
        #expect(answer.lands)
        #expect(answer.letsGoOf == "Caption")
        #expect(answer.note == "Sets this text in Heading and lets go of Caption.")
    }

    /// Aiming at one of several picked pieces of text reaches all of them, the
    /// way a colour let go on a swatch paints everything the swatch speaks
    /// for. The line says how many, so nobody has to count afterwards.
    @Test func aDropOnPickedTextReachesAllOfThem() {
        let answer = TextStyleDrop.answer(dropping: heading, on: text(reaches: 3))
        #expect(answer.lands)
        #expect(answer.note == "Sets all 3 of them in Heading.")
    }

    // MARK: - The drops that change nothing

    /// Bare canvas is not a refusal to explain away, it is a signpost: the
    /// person is carrying something and has not found where it goes yet.
    @Test func bareCanvasSaysWhereItGoes() {
        let answer = TextStyleDrop.answer(
            dropping: heading,
            on: TextStyleDrop.Target(name: nil, isText: false))
        #expect(!answer.lands)
        #expect(answer.note == "Drop this on a piece of text to set it in Heading.")
    }

    @Test func aShapeSaysItIsNotText() {
        let answer = TextStyleDrop.answer(
            dropping: heading,
            on: TextStyleDrop.Target(name: "Card", isText: false))
        #expect(!answer.lands)
        #expect(answer.note == "Card is not text, so it cannot wear Heading.")
    }

    /// The same name arriving on text already wearing it is as much of a no-op
    /// as the same colour arriving twice, and a no-op that lights up and writes
    /// an undo step is worse than one that says so.
    @Test func textAlreadyWearingItDoesNotLightUp() {
        let answer = TextStyleDrop.answer(dropping: heading, on: text(wearing: heading))
        #expect(!answer.lands)
        #expect(answer.note == "This text is already Heading.")
    }

    /// Text is never named in the sentence, however the layers list names it.
    /// The outline round it and the pointer on it already say WHICH text, and a
    /// fresh block's made-up name ("Text 2") says less than the words it is
    /// drawn over. A shape IS named, because there is no outline there and what
    /// somebody needs told is what kind of thing they are pointing at.
    @Test func textIsNotNamedButAShapeIs() {
        let onText = TextStyleDrop.answer(
            dropping: heading,
            on: TextStyleDrop.Target(name: "Text 2", isText: true))
        #expect(onText.note == "Sets this text in Heading.")
        let onNothingNamed = TextStyleDrop.answer(
            dropping: heading,
            on: TextStyleDrop.Target(name: "", isText: false))
        #expect(onNothingNamed.note == "That is not text, so it cannot wear Heading.")
    }
}
