import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Turn Into Picture over a SELECTION: which of the picked rows it takes, and
/// the sentence it says before it takes them.
@Suite("Turn Into Picture over several layers")
struct RasterizeBatchTests {

    private func shape(_ name: String) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle)),
              frame: CGRect(x: 10, y: 10, width: 60, height: 40))
    }

    private func words(_ name: String) -> Layer {
        Layer(name: name, content: .text(TextContent(string: name)),
              frame: CGRect(x: 10, y: 10, width: 60, height: 20))
    }

    private func picture(_ name: String) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: CGSize(width: 20, height: 20))),
              frame: CGRect(x: 0, y: 0, width: 20, height: 20))
    }

    // MARK: - Which of the picked rows the command takes

    @Test("It takes the shapes and the text out of a mixed pick, and leaves the rest")
    func takesOnlyWhatCanTurn() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 300, height: 300))
        let bottom = picture("Background")
        let rect = shape("Rectangle")
        let label = words("Sign in")
        let group = Layer(name: "Group", content: .group(GroupContent(children: [])),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        for layer in [bottom, rect, label, group] { doc.addLayer(layer) }

        let taken = doc.rasterizableLayers(ids: [bottom.id, rect.id, label.id, group.id])
        // A picture is already pixels and a group holds other layers, so both
        // are simply left where they are rather than failing the command.
        #expect(taken.map(\.id) == [rect.id, label.id])
    }

    @Test("What it takes comes back bottom of the stack first, whatever order the pick was made in")
    func takesInStackingOrder() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 300, height: 300))
        let first = shape("One")
        let second = shape("Two")
        let third = shape("Three")
        for layer in [first, second, third] { doc.addLayer(layer) }

        let taken = doc.rasterizableLayers(ids: [third.id, first.id, second.id])
        #expect(taken.map(\.name) == ["One", "Two", "Three"])
    }

    @Test("Ids that are not in the document are skipped rather than crashing the command")
    func skipsStrangers() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 300, height: 300))
        let rect = shape("Rectangle")
        doc.addLayer(rect)
        #expect(doc.rasterizableLayers(ids: [rect.id, UUID()]).map(\.id) == [rect.id])
        #expect(doc.rasterizableLayers(ids: []).isEmpty)
    }

    // MARK: - The question it asks first

    @Test("One layer raises no plural question: the singular prompt says it better")
    func onePicksTheSingularPrompt() {
        #expect(RasterizeQuestion(layers: [shape("Rectangle")]) == nil)
        #expect(RasterizeQuestion(layers: []) == nil)
        // A picture picked alongside one shape still leaves one thing to turn.
        #expect(RasterizeQuestion(layers: [shape("Rectangle"), picture("Background")]) == nil)
    }

    @Test("Two shapes are both, three are all 3, and nobody says all 2")
    func countsTheCrowdInWords() {
        #expect(RasterizeQuestion(layers: [shape("A"), shape("B")])?.title
            == "Turn both shapes into pictures?")
        #expect(RasterizeQuestion(layers: [shape("A"), shape("B"), shape("C")])?.title
            == "Turn all 3 shapes into pictures?")
    }

    @Test("It names what the rows ARE: shapes, pieces of text, or layers when they are both")
    func namesTheSubject() {
        #expect(RasterizeQuestion(layers: [words("A"), words("B")])?.title
            == "Turn both pieces of text into pictures?")
        #expect(RasterizeQuestion(layers: [shape("A"), words("B"), words("C")])?.title
            == "Turn all 3 layers into pictures?")
    }

    @Test("Only what will really turn is counted, so the number cannot overstate the damage")
    func countsOnlyWhatTurns() {
        let question = RasterizeQuestion(layers: [shape("A"), shape("B"), picture("Bg")])
        #expect(question?.takes == 2)
        #expect(question?.title == "Turn both shapes into pictures?")
    }

    @Test("It says what is lost, which is different for a shape and for words")
    func saysWhatIsLost() {
        let shapes = RasterizeQuestion(layers: [shape("A"), shape("B")])
        #expect(shapes?.message.contains("The shapes stop being editable") == true)
        let texts = RasterizeQuestion(layers: [words("A"), words("B")])
        #expect(texts?.message.contains("The words stop being editable") == true)
        let both = RasterizeQuestion(layers: [shape("A"), words("B")])
        #expect(both?.message.contains("The shapes and the words stop being editable") == true)
    }

    @Test("It promises ONE undo takes the whole batch back, which is the thing a batch owes you")
    func promisesOneUndo() {
        let question = RasterizeQuestion(layers: [shape("A"), shape("B"), shape("C")])
        #expect(question?.message.contains("One undo puts them all back") == true)
        // The gain comes first: it is what they came for.
        #expect(question?.message.hasPrefix("They become pixels") == true)
    }

    @Test("The button carries the verb in the plural, so the buttons alone still read")
    func buttonsCarryTheVerb() {
        let question = RasterizeQuestion(layers: [shape("A"), shape("B")])
        #expect(question?.confirm == "Turn Into Pictures")
        #expect(question?.cancel == "Cancel")
        // Same menu row and same "Don't ask again" as the single question, so
        // silencing it once silences both.
        #expect(RasterizePrompt.menuItem == "Turn Into Picture\u{2026}")
    }
}
