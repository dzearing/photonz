import CoreGraphics
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

    // MARK: - Words that belong to a copy

    private func copyWords(piece: String = "Label", component: String = "Button",
                           canDetach: Bool = true) -> TextStyleDrop.Target {
        TextStyleDrop.Target(name: "Button", isText: false,
                             copyPiece: TextStyleDrop.CopyPiece(piece: piece, component: component,
                                                                canDetach: canDetach))
    }

    /// The lie this exists to stop. The pointer is on the words of a button
    /// that is a copy of a component; the hit stops at the copy, because that
    /// is the rule every click on a copy follows, and the old sentence then
    /// said "Save button is not text" over the top of words anybody can read.
    /// It says instead where the words come from, and the two moves that work.
    @Test func wordsInsideACopySayWhereTheyComeFrom() {
        let answer = TextStyleDrop.answer(dropping: heading, on: copyWords())
        #expect(!answer.lands)
        #expect(answer.note
                == "Label comes from Button. Set Heading on the original, or detach this copy.")
    }

    /// A copy inside another copy is rebuilt by the OUTER copy, so detaching
    /// the inner one does not stick. Offering it there would be a second lie,
    /// so only the move that works is offered.
    @Test func wordsInsideANestedCopyDoNotOfferDetach() {
        let answer = TextStyleDrop.answer(dropping: heading, on: copyWords(canDetach: false))
        #expect(!answer.lands)
        #expect(answer.note == "Label comes from Button. Set Heading on the original.")
    }

    /// Nothing in the sentence depends on anybody having named anything: a
    /// piece nobody named is "This text", and an original nobody named is
    /// "the original", which the rest of the sentence then points back at.
    @Test func unnamedPiecesStillReadAsASentence() {
        let answer = TextStyleDrop.answer(dropping: heading,
                                          on: copyWords(piece: "", component: ""))
        #expect(answer.note
                == "This text comes from the original. Set Heading there, or detach this copy.")
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

/// Finding the words of a copy under the pointer, which is what turns the
/// canvas's "not text" into "these words come from Button".
///
/// The ordinary hit test stops at a copy on purpose, so the copy is all the
/// drop can see. Reaching one level further, only to SAY what is there, is the
/// whole of the fix: nothing about what a drop does changes.
struct TextStyleDropOnACopyTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, start: .zero,
                                                     end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    private func text(_ name: String, _ string: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)), frame: rect)
    }

    /// A component "Button" holding a box and a "Label", with one copy of it
    /// placed on the canvas.
    private func withCopy() -> (doc: PhotonzDocument, copy: UUID, piece: UUID) {
        var doc = PhotonzDocument(
            canvasSize: CGSize(width: 800, height: 600),
            layers: [box("Box", CGRect(x: 10, y: 10, width: 120, height: 40)),
                     text("Label", "Button", CGRect(x: 30, y: 20, width: 60, height: 20))])
        let boxID = doc.layers[0].id
        let labelID = doc.layers[1].id
        let main = doc.groupLayers(ids: [boxID, labelID], name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        let copy = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300))!
        return (doc, copy, ComponentIdentity.derived(instance: copy, source: labelID))
    }

    @Test func theWordsOfACopyAreNamedWithTheirOriginal() {
        let c = withCopy()
        let words = c.doc.canvasLayer(id: c.piece)!.frame
        let found = c.doc.textStyleCopyPiece(at: CGPoint(x: words.midX, y: words.midY))
        #expect(found?.piece == "Label")
        #expect(found?.component == "Button")
        #expect(found?.canDetach == true)
    }

    /// Only the words. The rest of a copy genuinely is not text, so a style
    /// aimed at the button's own face is refused the way it always was.
    @Test func theRestOfACopyIsNotWords() {
        let c = withCopy()
        let copyBox = c.doc.canvasLayer(id: c.copy)!.frame
        #expect(c.doc.textStyleCopyPiece(at: CGPoint(x: copyBox.maxX - 3,
                                                     y: copyBox.maxY - 3)) == nil)
    }

    /// Text that is nobody's copy is just text, so the ordinary answer stands.
    @Test func plainTextOnTheCanvasIsNotAPiece() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [text("Title", "Hello",
                                                CGRect(x: 40, y: 40, width: 120, height: 30))])
        #expect(doc.textStyleCopyPiece(at: CGPoint(x: 100, y: 55)) == nil)
    }
}
