import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// A person's thumbs on Ask's rows feed the eval's held-out set, and the eval
/// counts how often a result was looked up rather than drawn for the request
/// (the user, 2026-10-20: Ask scored 92 on drawings while it drew one cat for
/// every cat request).
@Suite("Ask: votes on rows, and where a drawing came from")
struct AskFeedbackTests {

    static func picture(_ layers: [Layer] = []) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: layers)
    }

    static func box(_ name: String) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#000000")),
              frame: CGRect(x: 0, y: 0, width: 50, height: 20))
    }

    // MARK: Where a drawing came from

    @Test("A built-in drawing is a lookup, an illustration a coded template, the model's own svg drawn")
    func drawingSources() {
        #expect(AskDrawingSource.of(tool: "add_drawing", answer: #"{"from":"built-in: cat face","layer":"x"}"#) == .stored)
        #expect(AskDrawingSource.of(tool: "add_drawing", answer: #"{"from":"illustration: Layered (picked)"}"#) == .template)
        #expect(AskDrawingSource.of(tool: "add_drawing", answer: #"{"from":"your svg","parts":4}"#) == .drawn)
    }

    @Test("Shapes and paths are drawn for the request; words, measurements and edits are not drawings")
    func otherTools() {
        #expect(AskDrawingSource.of(tool: "add_shape", answer: "{}") == .drawn)
        #expect(AskDrawingSource.of(tool: "add_path", answer: "{}") == .drawn)
        #expect(AskDrawingSource.of(tool: "add_text", answer: "{}") == nil)
        #expect(AskDrawingSource.of(tool: "add_measurement", answer: "{}") == nil)
        #expect(AskDrawingSource.of(tool: "set_layer", answer: "{}") == nil)
    }

    @Test("An add_drawing answer that says nothing of where it came from is not guessed")
    func unreadableAnswer() {
        #expect(AskDrawingSource.of(tool: "add_drawing", answer: "not json") == nil)
        #expect(AskDrawingSource.of(tool: "add_drawing", answer: #"{"from":"somewhere new"}"#) == nil)
    }

    // MARK: Votes

    @Test("A row starts with no vote; a vote sticks, the same vote again takes it back, the other swaps")
    func voting() {
        var list = AskChangeList()
        let id = list.record(asked: "draw a cat curled up sleeping", sentence: "Drew a cat",
                             before: Self.picture(), after: Self.picture([Self.box("Cat")]),
                             sources: [.stored])
        guard let id else { Issue.record("no row"); return }
        #expect(list.row(id)?.verdict == nil)
        #expect(list.row(id)?.sources == [.stored])
        #expect(list.vote(.down, id: id) == .down)
        #expect(list.row(id)?.verdict == .down)
        #expect(list.vote(.up, id: id) == .up)
        #expect(list.row(id)?.verdict == .up)
        #expect(list.vote(.up, id: id) == nil)
        #expect(list.row(id)?.verdict == nil)
    }

    @Test("Voting on a row that is not there does nothing")
    func votingNowhere() {
        var list = AskChangeList()
        #expect(list.vote(.down, id: UUID()) == nil)
        #expect(list.rows.isEmpty)
    }

    // MARK: The saved case

    @Test("A saved case's folder is the time and the request's first words, safe for a file name")
    func folderName() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let at = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 15, minute: 37, second: 5)) ?? Date()
        let name = AskFeedbackCase.folderName(request: "Draw a cat, curled up / sleeping!", at: at, timeZone: calendar.timeZone)
        #expect(name == "20261020-153705-draw-a-cat-curled-up-sleeping")
        let long = AskFeedbackCase.folderName(request: String(repeating: "piano ", count: 30), at: at, timeZone: calendar.timeZone)
        #expect(long.count <= 16 + AskFeedbackCase.slugLength)
        #expect(!long.hasSuffix("-"))
        #expect(AskFeedbackCase.folderName(request: "???", at: at, timeZone: calendar.timeZone) == "20261020-153705-request")
    }

    @Test("The saved case keeps the request, the vote and where each drawing came from, under the keys the eval reads")
    func caseFile() throws {
        let saved = AskFeedbackCase(request: "draw a piano with a cartoon cat playing it", verdict: .down,
                                    at: "2026-10-20T15:35:00Z", sentence: "Drew 2 drawings",
                                    sources: [.stored, .stored], canvas: [1440, 1024], model: "qwen3:30b",
                                    app: "Photonz Next (Dev)")
        let data = try JSONEncoder().encode(saved)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["request"] as? String == "draw a piano with a cartoon cat playing it")
        #expect(object["verdict"] as? String == "down")
        #expect(object["sources"] as? [String] == ["stored", "stored"])
        #expect(object["canvas"] as? [Double] == [1440, 1024])
        #expect(try JSONDecoder().decode(AskFeedbackCase.self, from: data) == saved)
    }
}
