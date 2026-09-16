import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A layer nobody has named by hand says what it actually is: a piece of text
/// wears its own words, and a shape that stopped being a rectangle stops
/// saying Rectangle.
@Suite("A layer nobody renamed says what it is")
struct LayerDisplayNameTests {

    // MARK: Helpers

    private func textLayer(named name: String, words: String) -> Layer {
        Layer(name: name, content: .text(TextContent(string: words)),
              frame: CGRect(x: 10, y: 10, width: 200, height: 40))
    }

    private func shapeLayer(_ shape: AnnotationShape, named name: String) -> Layer {
        let content = AnnotationContent(shape: shape, strokeWidth: 4, colorHex: "#FF3B30",
                                        start: .zero, end: CGPoint(x: 160, y: 90))
        return Layer(name: name, content: .annotation(content),
                     frame: CGRect(x: 20, y: 20, width: 160, height: 90))
    }

    // MARK: - Words become the name

    @Test("A run the app numbered wears the words it holds")
    func wordsStandInForTheNumber() {
        #expect(textLayer(named: "Text 9", words: "Appearance").displayName == "Appearance")
        #expect(textLayer(named: "Text", words: "Cancel").displayName == "Cancel")
    }

    @Test("Retyping the words changes what the row says")
    func retypingFollowsThrough() {
        var layer = textLayer(named: "Text 9", words: "General")
        #expect(layer.displayName == "General")
        layer.content = .text(TextContent(string: "Appearance"))
        #expect(layer.displayName == "Appearance")
    }

    @Test("A name somebody typed is theirs, whatever the words say")
    func aHandNameIsNeverTakenAway() {
        var layer = textLayer(named: "Primary button label", words: "Save Changes")
        #expect(layer.displayName == "Primary button label")
        layer.content = .text(TextContent(string: "Done"))
        #expect(layer.displayName == "Primary button label")
    }

    @Test("Words too long for a row are cut at a word boundary")
    func longWordsAreShortened() {
        let long = "Choose how often this document checks for a newer version"
        let name = textLayer(named: "Text 2", words: long).displayName
        #expect(name.count <= LayerNaming.wordsLimit + 1)
        #expect(name.hasSuffix("\u{2026}"))
        #expect(long.hasPrefix(name.dropLast()))
        // Cut between words, not through one.
        #expect(!name.dropLast().hasSuffix(" "))
    }

    @Test("One long word with nowhere to break is cut where the room ran out")
    func oneLongWordIsCutAnyway() {
        let name = textLayer(named: "Text", words: String(repeating: "x", count: 60)).displayName
        #expect(name.count == LayerNaming.wordsLimit + 1)
    }

    @Test("Several lines read as one line in the list")
    func linesCollapseToOneRow() {
        let layer = textLayer(named: "Text 4", words: "  Save\n\tChanges  \n\n  now ")
        #expect(layer.displayName == "Save Changes now")
    }

    @Test("Text with nothing in it keeps the name the app gave it")
    func emptyWordsFallBack() {
        #expect(textLayer(named: "Text", words: "").displayName == "Text")
        #expect(textLayer(named: "Text 3", words: "   \n ").displayName == "Text 3")
    }

    @Test("Anything that is not text says exactly what it always said")
    func otherLayersAreUntouched() {
        #expect(shapeLayer(.rectangle, named: "Rectangle 2").displayName == "Rectangle 2")
        let picture = Layer(name: "Text 7",
                            content: .image(ImageRef(pixelSize: CGSize(width: 20, height: 8))),
                            frame: CGRect(x: 0, y: 0, width: 20, height: 8))
        #expect(picture.displayName == "Text 7")
    }

    // MARK: - The layers list shows it

    @Test("The layers list row says the words")
    func theRowSaysTheWords() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        document.addLayer(textLayer(named: "Text 1", words: "Appearance"))
        document.addLayer(textLayer(named: "Sidebar heading", words: "General"))
        let rows = document.layerRows(expanded: [], selected: [])
        #expect(rows.map(\.name) == ["Sidebar heading", "Appearance"])
    }

    // MARK: - A shape that stopped being a rectangle

    @Test("An unnamed box, oval or line becomes a row called Path")
    func turningAShapeRenamesIt() throws {
        for shape in [AnnotationShape.rectangle, .ellipse, .line] {
            var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
            document.addLayer(shapeLayer(shape, named: shape.title))
            let id = try #require(document.layers.last?.id)
            document.turnLayerIntoPath(id: id)
            #expect(document.layer(id: id)?.path != nil)
            #expect(document.layer(id: id)?.displayName == "Path")
        }
    }

    @Test("A layer somebody called Card is still called Card")
    func aHandNamedShapeKeepsItsName() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        document.addLayer(shapeLayer(.rectangle, named: "Card"))
        let id = try #require(document.layers.last?.id)
        document.turnLayerIntoPath(id: id)
        #expect(document.layer(id: id)?.name == "Card")
    }

    @Test("Two boxes turned into paths are still tellable apart")
    func twoPathsTakeDifferentNames() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        document.addLayer(shapeLayer(.rectangle, named: "Rectangle"))
        document.addLayer(shapeLayer(.rectangle, named: "Rectangle 2"))
        let ids = document.layers.map(\.id)
        for id in ids { document.turnLayerIntoPath(id: id) }
        let names = ids.compactMap { document.layer(id: $0)?.name }
        #expect(names == ["Path", "Path 2"])
    }

    @Test("The new name is part of the same step, so one undo puts both back")
    func theRenameRidesInTheSameUndoStep() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        document.addLayer(shapeLayer(.rectangle, named: "Rectangle"))
        let id = try #require(document.layers.last?.id)
        var history = History(document: document)
        history.perform { $0.turnLayerIntoPath(id: id) }
        #expect(history.current.layer(id: id)?.name == "Path")
        history.undo()
        #expect(history.current.layer(id: id)?.name == "Rectangle")
        #expect(history.current.layer(id: id)?.annotation?.shape == .rectangle)
        #expect(!history.canUndo)
    }

    // MARK: - Typing the name you can already see

    @Test("Committing the name already on the row leaves it following the words")
    func typingWhatIsAlreadyThereChangesNothing() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        document.addLayer(textLayer(named: "Text 5", words: "Appearance"))
        let id = try #require(document.layers.last?.id)
        // The field opens filled with what the row says, so pressing Return on
        // it must not quietly freeze the name away from the words.
        document.renameLayer(id: id, to: "Appearance")
        #expect(document.layer(id: id)?.name == "Text 5")
        document.renameLayer(id: id, to: "  Appearance ")
        #expect(document.layer(id: id)?.name == "Text 5")
        // An empty field is not a name either.
        document.renameLayer(id: id, to: "   ")
        #expect(document.layer(id: id)?.name == "Text 5")
        // Typing something of their own does stick, and stays stuck.
        document.renameLayer(id: id, to: "Sidebar heading")
        #expect(document.layer(id: id)?.name == "Sidebar heading")
        #expect(document.layer(id: id)?.displayName == "Sidebar heading")
    }
}
