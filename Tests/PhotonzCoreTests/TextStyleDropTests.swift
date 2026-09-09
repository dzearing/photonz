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

/// Letting a saved text style go on a ROW in the layers list.
///
/// The picture was the only place a style could be put down, and the row is the
/// other obvious place to aim: the list is where a layer is named, picked and
/// reordered, so it is where somebody expects to be able to dress it too.
///
/// The rules are not a second set. The row works out the same `Target` the
/// canvas works out and reads the same answer back, so the sentence a row says
/// and the sentence the picture says are the same sentence, and a drop that
/// lands on a row lands exactly what a drop on the words would have.
struct TextStyleRowDropTests {

    private func text(_ name: String, _ string: String = "Hello") -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)),
              frame: CGRect(x: 0, y: 0, width: 120, height: 30))
    }

    private func box(_ name: String) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, start: .zero,
                                                     end: CGPoint(x: 80, y: 40))),
              frame: CGRect(x: 0, y: 0, width: 80, height: 40))
    }

    private func treatment(_ size: CGFloat) -> TextTreatment {
        TextTreatment(fontName: "Georgia", fontSize: size, weight: .regular, colorHex: "#111111")
    }

    /// A document holding these layers and one saved style called Heading.
    private func doc(_ layers: [Layer]) -> (doc: PhotonzDocument, style: TextStyleDrop.SavedStyle) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: layers)
        let id = doc.addTextStyle(name: "Heading", treatment: treatment(32))
        return (doc, TextStyleDrop.SavedStyle(id: id, name: "Heading"))
    }

    @Test func aTextRowTakesTheStyle() {
        let c = doc([text("Title")])
        let id = c.doc.layers[0].id
        let drop = c.doc.textStyleRowDrop(c.style, onRow: id)
        #expect(drop.answer.lands)
        #expect(drop.answer.note == "Sets this text in Heading.")
        #expect(drop.layerIDs == [id])
    }

    /// The very sentence the canvas says, because it is the very same answer.
    @Test func aShapeRowRefusesInTheCanvasWords() {
        let c = doc([box("Card")])
        let drop = c.doc.textStyleRowDrop(c.style, onRow: c.doc.layers[0].id)
        #expect(!drop.answer.lands)
        #expect(drop.answer.note == "Card is not text, so it cannot wear Heading.")
        #expect(drop.layerIDs.isEmpty)
    }

    /// A row nobody can point at any more — the list rebuilt under the pointer,
    /// the layer was deleted mid-drag — is the same as pointing at nothing, and
    /// says the same signpost the bare canvas says.
    @Test func aRowThatIsNotThereSaysWhereAStyleGoes() {
        let c = doc([text("Title")])
        let drop = c.doc.textStyleRowDrop(c.style, onRow: UUID())
        #expect(!drop.answer.lands)
        #expect(drop.answer.note == "Drop this on a piece of text to set it in Heading.")
    }

    /// A locked layer is the one case a row meets that the picture never does:
    /// the canvas hit test walks straight past a locked layer, so a style can
    /// only ever be aimed at one here. Locked means what it means everywhere
    /// else in the app — the Text section will not dress a locked layer either
    /// — so the row refuses, and says which of the two things is in the way.
    @Test func aLockedTextRowRefusesAndSaysSo() {
        var c = doc([text("Title")])
        let id = c.doc.layers[0].id
        c.doc.updateLayer(id: id) { $0.isLocked = true }
        let drop = c.doc.textStyleRowDrop(c.style, onRow: id)
        #expect(!drop.answer.lands)
        #expect(drop.answer.note == "Title is locked, so it cannot wear Heading.")
        #expect(drop.layerIDs.isEmpty)
    }

    /// A hidden layer is not a protected one: hiding is about what you can see,
    /// and the Text section dresses a hidden layer without complaint. So does
    /// a drop.
    @Test func aHiddenTextRowStillTakesTheStyle() {
        var c = doc([text("Title")])
        let id = c.doc.layers[0].id
        c.doc.updateLayer(id: id) { $0.isVisible = false }
        #expect(c.doc.textStyleRowDrop(c.style, onRow: id).answer.lands)
    }

    /// The canvas rule, in the list: aiming at a row that is part of what you
    /// have picked reaches every picked piece of text, and aiming at a row
    /// nobody picked reaches only that row.
    @Test func aDropOnAPickedRowReachesEveryPickedTextRow() {
        let c = doc([text("One"), text("Two"), box("Card")])
        let ids = c.doc.layers.map(\.id)
        let picked: Set<UUID> = [ids[0], ids[1], ids[2]]
        let drop = c.doc.textStyleRowDrop(c.style, onRow: ids[0], picked: picked)
        #expect(drop.answer.lands)
        #expect(drop.answer.note == "Sets all 2 of them in Heading.")
        #expect(Set(drop.layerIDs) == Set([ids[0], ids[1]]))
    }

    @Test func aDropOnARowNobodyPickedReachesOnlyThatRow() {
        let c = doc([text("One"), text("Two")])
        let ids = c.doc.layers.map(\.id)
        let drop = c.doc.textStyleRowDrop(c.style, onRow: ids[1], picked: [ids[0]])
        #expect(drop.layerIDs == [ids[1]])
        #expect(drop.answer.note == "Sets this text in Heading.")
    }

    /// A locked row inside the picked crowd is not dressed, and is not counted
    /// in the number the sentence promises.
    @Test func aLockedRowInTheCrowdIsNotCounted() {
        var c = doc([text("One"), text("Two"), text("Three")])
        let ids = c.doc.layers.map(\.id)
        c.doc.updateLayer(id: ids[2]) { $0.isLocked = true }
        let drop = c.doc.textStyleRowDrop(c.style, onRow: ids[0], picked: Set(ids))
        #expect(drop.answer.note == "Sets all 2 of them in Heading.")
        #expect(Set(drop.layerIDs) == Set([ids[0], ids[1]]))
    }

    /// A row already wearing the style has nothing to do, and says so rather
    /// than lighting up and writing an undo step for nothing.
    @Test func aRowAlreadyWearingItDoesNotLightUp() {
        var c = doc([text("Title")])
        let id = c.doc.layers[0].id
        _ = c.doc.bindTextStyle(layerIDs: [id], styleID: c.style.id)
        let drop = c.doc.textStyleRowDrop(c.style, onRow: id)
        #expect(!drop.answer.lands)
        #expect(drop.answer.note == "This text is already Heading.")
    }

    /// The name being given up is said before it is given up, exactly as it is
    /// on the picture.
    @Test func aRowWearingAnotherNameSaysWhatItLetsGoOf() {
        var c = doc([text("Title")])
        let id = c.doc.layers[0].id
        let caption = c.doc.addTextStyle(name: "Caption", treatment: treatment(12))
        _ = c.doc.bindTextStyle(layerIDs: [id], styleID: caption)
        let drop = c.doc.textStyleRowDrop(c.style, onRow: id)
        #expect(drop.answer.lands)
        #expect(drop.answer.note == "Sets this text in Heading and lets go of Caption.")
    }

    /// A row inside a group is reached by name like any other: the list shows
    /// it, so a style can be aimed at it.
    @Test func aRowInsideAGroupTakesTheStyle() {
        var c = doc([text("One"), box("Card")])
        let ids = c.doc.layers.map(\.id)
        _ = c.doc.groupLayers(ids: Set(ids), name: "Panel")
        let drop = c.doc.textStyleRowDrop(c.style, onRow: ids[0])
        #expect(drop.answer.lands)
        #expect(drop.layerIDs == [ids[0]])
    }
}
