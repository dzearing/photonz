import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Ask works on what is picked (`docs/design/ask.md`, "What is picked"): the
/// read says it, the instructions aim this, it and these at it, and the
/// composer shows the scope. With nothing picked, nothing about the request
/// changes at all.
@Suite("Ask: what is picked")
struct AskPickedTests {

    static func context(selected: [UUID] = []) -> AgentDocumentRead.Context {
        AgentDocumentRead.Context(id: "d1", title: "shot.png", file: nil, playheadMS: 0,
                                  canUndo: false, canRedo: false, selected: selected)
    }

    static func shape(_ name: String) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 4, colorHex: "#00FF00")),
              frame: CGRect(x: 10, y: 10, width: 100, height: 60))
    }

    static func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: layers)
    }

    static func text(_ read: AgentDocumentRead) throws -> String {
        String(decoding: try read.encoded(), as: UTF8.self)
    }

    @Test("The read names what is picked, by id and by name")
    func readSaysWhatIsPicked() {
        let circle = Self.shape("Circle"), box = Self.shape("Box")
        let read = AgentDocumentRead.make(Self.document([circle, box]), context: Self.context(selected: [circle.id]))
        #expect(read.selected == [.init(id: circle.id.uuidString, name: "Circle")])
    }

    @Test("With nothing picked the read has no word about it")
    func nothingPickedSaysNothing() throws {
        let read = AgentDocumentRead.make(Self.document([Self.shape("Box")]), context: Self.context())
        #expect(read.selected == nil)
        #expect(try !Self.text(read).contains("selected"))
    }

    @Test("Several picked come in the read's own order, whatever order they were picked in")
    func severalInStackOrder() {
        let top = Self.shape("Top"), middle = Self.shape("Middle"), bottom = Self.shape("Bottom")
        let document = Self.document([top, middle, bottom])
        let read = AgentDocumentRead.make(document, context: Self.context(selected: [bottom.id, top.id]))
        #expect(read.selected?.map(\.name) == document.allLayers.filter { $0.id != middle.id }.map(\.name))
    }

    @Test("A picked layer that has since gone is left out, and none left means none said")
    func goneLayersAreLeftOut() {
        let box = Self.shape("Box")
        let read = AgentDocumentRead.make(Self.document([box]), context: Self.context(selected: [UUID()]))
        #expect(read.selected == nil)
    }

    @Test("A layer picked inside a group is found")
    func pickedInsideAGroup() {
        let inner = Self.shape("Inner")
        var group = Self.shape("Group")
        group.content = .group(GroupContent(children: [inner]))
        let read = AgentDocumentRead.make(Self.document([group]), context: Self.context(selected: [inner.id]))
        #expect(read.selected?.map(\.name) == ["Inner"])
    }

    @Test("A read fitted to the model's window still says what is picked, even a layer it stopped listing")
    func fittedReadKeepsThePick() throws {
        let layers = (0..<300).map { Self.shape("Layer \($0)") }
        let last = try #require(layers.last)
        let read = AgentDocumentRead.make(Self.document(layers), context: Self.context(selected: [last.id]))
        let fitted = AskDocumentDigest.fitted(try Self.text(read), tokens: 600)
        let back = try JSONDecoder().decode(AgentDocumentRead.self, from: Data(fitted.utf8))
        #expect(back.layers.count < layers.count)
        #expect(back.selected?.map(\.id) == [last.id.uuidString])
    }

    @Test("The rule names the picked layers and their ids")
    func ruleNamesThePick() throws {
        let circle = Self.shape("Circle")
        let read = AgentDocumentRead.make(Self.document([circle]), context: Self.context(selected: [circle.id]))
        let rule = try #require(AskPicked.rule(documentRead: try Self.text(read)))
        #expect(rule.contains("Circle"))
        #expect(rule.contains(circle.id.uuidString))
    }

    @Test("With nothing picked there is no rule, so the instructions are word for word what they were")
    func noRuleWithNothingPicked() throws {
        let read = AgentDocumentRead.make(Self.document([Self.shape("Box")]), context: Self.context())
        let text = try Self.text(read)
        #expect(AskPicked.rule(documentRead: text) == nil)
        #expect(!AskConversation.instructions(documentRead: text).contains(AskPicked.ruleOpening))
    }

    @Test("With something picked the instructions carry the rule")
    func instructionsCarryTheRule() throws {
        let circle = Self.shape("Circle")
        let read = AgentDocumentRead.make(Self.document([circle]), context: Self.context(selected: [circle.id]))
        #expect(AskConversation.instructions(documentRead: try Self.text(read)).contains(AskPicked.ruleOpening))
    }

    @Test("Words in a layer's text can never pass for a pick")
    func textCannotPassForAPick() throws {
        var note = Self.shape("Note")
        note.name = #"selected":[{"id":"x","name":"y"}]"#
        let read = AgentDocumentRead.make(Self.document([note]), context: Self.context())
        #expect(AskPicked.rule(documentRead: try Self.text(read)) == nil)
    }

    @Test("A read that cannot be understood has no rule")
    func unreadableReadHasNoRule() {
        #expect(AskPicked.rule(documentRead: "not a read") == nil)
    }

    @Test("The composer's scope says how many, and nothing at none", arguments: [
        (0, nil), (1, "1 selected"), (3, "3 selected"),
    ] as [(Int, String?)])
    func scopeLabel(count: Int, label: String?) {
        #expect(AskPicked.scope(count: count) == label)
    }

    @Test("A waiting request keeps what was picked when it was sent")
    func waitingRequestKeepsItsPick() {
        let picked = [UUID()]
        var line = AskRequestLine()
        line.add("make this bigger", picked: picked)
        line.add("add a star")
        #expect(line.next()?.picked == picked)
        #expect(line.next()?.picked == [])
    }

    @Test("A shape rounded in its own corners reads as rounded, so \"round it more\" starts from what is there")
    func aShapesOwnCornersRead() throws {
        var box = AnnotationContent(shape: .rectangle, strokeWidth: 4, colorHex: "#00FF00")
        box.cornerRadius = 16
        let layer = Layer(name: "Box", content: .annotation(box), frame: CGRect(x: 0, y: 0, width: 100, height: 60))
        let read = AgentDocumentRead.make(Self.document([layer]), context: Self.context())
        #expect(read.layers.first?.cornerRadius == 16)
    }

    @Test("The tool's own words tell an outside agent the read says what is picked")
    func toolDocsSayIt() throws {
        let tool = try #require(AgentTools.all.first { $0.name == "read_document" })
        #expect(tool.description.contains("selected"))
    }

    @Test("Ask's own model is not sent that sentence: with nothing picked its request is what it was")
    func askIsNotSentTheToolsSentence() throws {
        let tool = try #require(AskTools.modelTool("read_document"))
        let description = try #require(tool["function"]?["description"]?.stringValue)
        #expect(!description.contains("selected"))
        #expect(description.hasSuffix("Times are in seconds."))
    }
}
