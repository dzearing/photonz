import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Ask never fails because a document is too big to describe (the user,
/// 2026-10-31: a change to a traced Statue of Liberty of 216 parts failed
/// with "request (41070 tokens) exceeds the available context size (32768
/// tokens)"). A big drawing is described as one entry, every request is
/// budgeted before it is sent, and no server's words reach the person.
@Suite("Ask fits any document into its model's window")
struct AskDocumentFitTests {

    static let context = AgentDocumentRead.Context(id: "d1", title: "Image", file: nil, playheadMS: 0, canUndo: true, canRedo: false)

    /// A closed outline of `count` points round a middle, as a tracer leaves them.
    static func outline(_ count: Int, _ seed: Int) -> [PathAnchor] {
        (0..<count).map { index in
            let angle = Double(index) / Double(count) * 2 * .pi
            let radius = 20 + Double((index * 7 + seed) % 11)
            return PathAnchor(point: CGPoint(x: 40 + radius * cos(angle), y: 40 + radius * sin(angle)))
        }
    }

    /// A traced drawing like the one the user hit: `parts` path layers named
    /// by colour ("Teal 12", "Pale teal 3"), in one group over a 1440 by 1024
    /// picture with its white background.
    static func tracedDrawing(parts: Int = 216) -> (PhotonzDocument, UUID) {
        let shades: [(String, String)] = [("Teal", "#4E9A8C"), ("Pale teal", "#A8D8CC"), ("Dark teal", "#1F5A50"),
                                          ("Yellow", "#E0B030"), ("Black", "#101818"), ("White", "#F4F8F6")]
        var counts: [String: Int] = [:]
        let children: [Layer] = (0..<parts).map { index in
            let (shade, hex) = shades[index % 7 < 4 ? index % 3 : 3 + index % 3]
            counts[shade, default: 0] += 1
            let name = counts[shade] == 1 ? shade : "\(shade) \(counts[shade] ?? 0)"
            return Layer(name: name, content: .path(PathContent(anchors: outline(12 + index % 30, index), isClosed: true,
                                                                paint: Paint(hex: hex), strokeWidth: 0, fill: Paint(hex: hex))),
                         frame: CGRect(x: 500 + Double(index % 20) * 12, y: 120 + Double(index / 20) * 70, width: 80, height: 80))
        }
        let group = Layer(name: "Statue of Liberty", content: .group(GroupContent(children: children)),
                          frame: CGRect(x: 470, y: 110, width: 440, height: 860))
        let background = Layer(name: "Background", content: .image(ImageRef(pixelSize: CGSize(width: 1440, height: 1024))),
                               frame: CGRect(x: 0, y: 0, width: 1440, height: 1024))
        return (PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024), layers: [background, group]), group.id)
    }

    static func readText(_ document: PhotonzDocument, only: UUID? = nil) throws -> String {
        String(decoding: try AgentDocumentRead.make(document, context: context, only: only).encoded(), as: UTF8.self)
    }

    /// A PNG's first bytes, with the size in its header, for a canvas picture.
    static func pngHeader(width: UInt32, height: UInt32) -> Data {
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52])
        for value in [width, height] { withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: [8, 6, 0, 0, 0] + [UInt8](repeating: 0, count: 4) + [UInt8](repeating: 7, count: 60_000))
        return data
    }

    // MARK: The estimate

    @Test("The token estimate never undercounts the kinds of text Ask sends by more than a little")
    func estimateIsCautious() {
        // Measured on Qwen3.8 27B's own tokenizer on 2026-10-31: the traced
        // Statue's read_document was 23,423 tokens in 45,885 characters, the
        // tools 10,837 in 46,871 and the instructions 1,484 in 6,438. A
        // line of each kind, the estimate read against the same ratio.
        let read = ##"{"frame":{"height":58.4,"width":31.2,"x":612.5,"y":340.1},"id":"6F1C2A9E-3B7D-4E58-9A10-2C4F5E6D7A8B","kind":"path","name":"Teal 17","path":{"anchors":31,"closed":true,"fill":"#4E9A8C","stroke":"#4E9A8C","strokeWidth":0}}"##
        #expect(Double(AskTokens.estimate(read)) >= Double(read.count) * 23_423 / 45_885 * 0.95)
        let prose = "Turn it into a plan of tool calls on that document. Coordinates are points from the top left of the canvas."
        #expect(Double(AskTokens.estimate(prose)) >= Double(prose.count) * 1_484 / 6_438 * 0.95)
        #expect(AskTokens.estimate("") == 0)
    }

    @Test("A canvas picture is counted from its size, a pixel square of 32 to a token")
    func pictureEstimate() {
        // Measured on Qwen3.8 27B, 2026-10-31: 738 tokens for this picture.
        let tokens = AskTokens.estimate(picture: Self.pngHeader(width: 1024, height: 728))
        #expect(tokens >= 738)
        #expect(tokens < 1400)
        #expect(AskTokens.estimate(picture: Data([1, 2, 3])) > 0)
    }

    // MARK: The document, described to fit

    @Test("A traced drawing of 216 parts is one entry: its name, box, part count, names grouped and colours")
    func bigDrawingIsOneEntry() throws {
        let (document, group) = Self.tracedDrawing()
        let full = try Self.readText(document)
        #expect(AskTokens.estimate(full) > 20_000)

        let fitted = AskDocumentDigest.fitted(full)
        #expect(AskTokens.estimate(fitted) <= 1_500)
        let read = try JSONDecoder().decode(AgentDocumentRead.self, from: Data(fitted.utf8))
        let drawing = try #require(read.layers.first { $0.id == group.uuidString })
        #expect(drawing.name == "Statue of Liberty")
        #expect(drawing.kind == "group")
        #expect(drawing.children == nil)
        let parts = try #require(drawing.parts)
        #expect(parts.count == 216)
        #expect(parts.names.contains { $0.hasPrefix("Teal (") })
        #expect(parts.names.contains { $0.hasPrefix("Pale teal (") })
        #expect(parts.names.count <= AskDocumentDigest.mostNames)
        #expect(parts.colors?.first?.hasPrefix("#") == true)
        #expect((parts.colors?.count ?? 0) <= AskDocumentDigest.mostColors)
        // The rest of the document reads exactly as it did.
        #expect(read.layers.contains { $0.name == "Background" && $0.pixels != nil })
        #expect(read.canvas.width == 1440 && read.layerCount == 218)
    }

    @Test("A document that already fits is handed over exactly as read_document read it")
    func smallDocumentUnchanged() throws {
        let (document, _) = Self.tracedDrawing(parts: 6)
        let full = try Self.readText(document)
        #expect(AskDocumentDigest.fitted(full) == full)
        #expect(AskDocumentDigest.fitted("not json") == "not json")
    }

    @Test("Hundreds of loose layers are listed from the top until the budget, the rest counted")
    func manyLooseLayers() throws {
        let (traced, _) = Self.tracedDrawing(parts: 400)
        let loose = traced.layers[1].group?.children ?? []
        let document = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024), layers: loose)
        let fitted = AskDocumentDigest.fitted(try Self.readText(document))
        #expect(AskTokens.estimate(fitted) <= AskDocumentDigest.documentTokens)
        let read = try JSONDecoder().decode(AgentDocumentRead.self, from: Data(fitted.utf8))
        #expect(!read.layers.isEmpty)
        #expect(read.layers.count + (read.layersNotListed ?? 0) == 400)
        // Top of the stack first, as read_document lists them.
        #expect(read.layers.first?.id == loose.last?.id.uuidString)
    }

    @Test("Opening the drawing with read_document lists its parts one by one, as many as fit, the rest counted")
    func openingADrawing() throws {
        let (document, group) = Self.tracedDrawing()
        var talk = AskConversation(request: "make her robe a darker green", documentRead: try Self.readText(document))
        talk.answer(AskLook(tool: "read_document", arguments: ["layer": .string(group.uuidString)]),
                    with: try Self.readText(document, only: group))
        let answer = try #require(talk.messages.last?["content"]?.stringValue)
        #expect(AskTokens.estimate(answer) <= AskDocumentDigest.lookTokens)
        let read = try JSONDecoder().decode(AgentDocumentRead.self, from: Data(answer.utf8))
        let drawing = try #require(read.layers.first)
        let listed = drawing.children ?? []
        #expect(listed.count > 20)
        #expect(listed.allSatisfy { $0.kind == "path" && $0.path != nil })
        #expect(drawing.parts?.count == 216)
        #expect(drawing.parts?.listed == listed.count)
    }

    @Test("The memory names a traced drawing's parts by their names once each, with how many share them")
    func memoryGroupsAlikeNames() {
        let (document, _) = Self.tracedDrawing()
        let parts = AskMemory.parts(of: document.layers[1])
        #expect(parts.count <= 6)
        #expect(parts.contains { $0.hasPrefix("Teal (") })
        let (small, _, _) = AskChangesWhatItMadeTests.drawing()
        #expect(AskMemory.parts(of: small.layers[0]) == ["Sun", "Hill"])
    }

    static func reply(_ tool: String, _ arguments: String) throws -> AgentJSON {
        ["message": ["role": "assistant", "content": "",
                     "tool_calls": [["function": ["name": .string(tool), "arguments": try AgentJSON.parse(Data(arguments.utf8))]]]]]
    }

    @Test("A part said in short that no name there is, with no point inside it, is sent back for a point; a point or a name there plans")
    func partOfADrawingSaidInShort() throws {
        let (document, group) = Self.tracedDrawing()
        let read = try Self.readText(document)
        var talk = AskConversation(request: "make her robe a darker green", documentRead: read)
        _ = talk.take(try Self.reply("change_part", ##"{"part":"robe","layer":"\##(group.uuidString)","color":"#2E6B4F"}"##))
        #expect(talk.steps.isEmpty)
        let told = talk.messages.last?["content"]?.stringValue ?? ""
        #expect(told.hasPrefix("Not planned") && told.contains(" at"))
        _ = talk.take(try Self.reply("change_part", ##"{"part":"robe","layer":"\##(group.uuidString)","color":"#2E6B4F","at":{"x":700,"y":600}}"##))
        #expect(talk.steps.count == 1)

        var byColour = AskConversation(request: "make the teal darker", documentRead: read)
        _ = byColour.take(try Self.reply("change_part", ##"{"part":"teal","layer":"\##(group.uuidString)","lightness":-20}"##))
        #expect(byColour.steps.count == 1)
    }

    // MARK: The whole request

    @Test("The first request with the 216-part drawing, its memory and a picture of the canvas takes under half the window")
    func firstRequestUnderHalf() throws {
        let (document, group) = Self.tracedDrawing()
        let memory = AskMemory.prompt([AskMemory.Turn(asked: "draw the Statue of Liberty", did: "Drew the Statue of Liberty",
                                                      made: [.init(id: group.uuidString, name: "Statue of Liberty", kind: "group",
                                                                   parts: AskMemory.parts(of: document.layers[1]))])])
        let talk = AskConversation(request: "make her robe a darker green", documentRead: try Self.readText(document),
                                   paints: true, memory: memory, canvas: Self.pngHeader(width: 1024, height: 728),
                                   canvasScale: 1024.0 / 1440)
        #expect(talk.estimatedTokens < AskConversation.contextWindow / 2)
        #expect(talk.fits)
        // The person's words and the instructions are all there.
        let body = talk.chatBody(model: "m")
        let sent = body["messages"]?.arrayValue ?? []
        #expect(sent.count == 2)
        #expect(sent[1]["content"]?.stringValue == "make her robe a darker green")
        #expect(sent[0]["content"]?.stringValue?.contains("Statue of Liberty") == true)
    }

    @Test("A long plan is shortened oldest tool answer first: never the instructions, the person's words or the newest answer")
    func longPlanShortensOldestAnswers() throws {
        let (document, _) = Self.tracedDrawing(parts: 6)
        var talk = AskConversation(request: "check the spacing everywhere", documentRead: try Self.readText(document))
        let system = talk.messages[0]
        let reply: AgentJSON = ["message": ["role": "assistant", "content": "",
                                            "tool_calls": [["function": ["name": "find_elements", "arguments": [:]]]]]]
        let big = String(repeating: #"{"box":{"x":120.5,"y":340.25,"width":88,"height":24},"what":"button 7"},"#, count: 80)
        for round in 0..<12 {
            _ = talk.take(reply)
            talk.answer(AskLook(tool: "find_measurements", arguments: [:]), with: "[\(round)]" + big)
        }
        #expect(talk.estimatedTokens(of: talk.messages) > talk.budget)
        let sent = talk.chatBody(model: "m")["messages"]?.arrayValue ?? []
        #expect(talk.estimatedTokens(of: sent) <= talk.budget)
        #expect(sent.count == talk.messages.count)
        #expect(sent[0] == system)
        #expect(sent[1]["content"]?.stringValue == "check the spacing everywhere")
        let answers = sent.filter { $0["role"]?.stringValue == "tool" }.compactMap { $0["content"]?.stringValue }
        #expect(answers.first == AskConversation.shortenedAnswer)
        #expect(answers.last?.hasPrefix("[11]") == true)
        // Only as many as it takes, oldest first.
        let kept = answers.drop { $0 == AskConversation.shortenedAnswer }
        #expect(kept.allSatisfy { $0 != AskConversation.shortenedAnswer })
        #expect(kept.count >= 2)
    }

    // MARK: The window

    @Test("A Mac with room for it gets the bigger window, and the server is started with the window Ask plans to")
    func windowPerMac() throws {
        #expect(AskConversation.contextWindow(memoryGigabytes: 64) == AskConversation.largeContextWindow)
        #expect(AskConversation.contextWindow(memoryGigabytes: 32) == AskConversation.contextWindow)
        let talk = AskConversation(request: "x", documentRead: "{}", window: AskConversation.largeContextWindow)
        #expect(talk.chatBody(model: "m")["options"]?["num_ctx"]?.doubleValue == Double(AskConversation.largeContextWindow))
        #expect(talk.budget > AskConversation(request: "x", documentRead: "{}").budget)
        let choice = try #require(AskBuiltInModels.ranked.first)
        let args = AskBuiltInServerPlan.arguments(for: choice, in: URL(fileURLWithPath: "/m"), port: 1,
                                                  window: AskConversation.largeContextWindow)
        let at = try #require(args.firstIndex(of: "--ctx-size"))
        #expect(args[at + 1] == String(AskConversation.largeContextWindow))
    }

    // MARK: What the person reads

    @Test("A server's own words never reach the person: each becomes one short plain sentence")
    func plainSentences() {
        let raw = [
            "request (41070 tokens) exceeds the available context size (32768 tokens), try increasing it",
            "the request exceeds the available context size, try increasing it",
            "Failed to parse tool call arguments as JSON: [json.exception.parse_error.101]",
            "model 'qwen3.6:27b' not found",
            "Internal Server Error",
            "",
        ]
        for words in raw {
            let sentence = AskTrouble.sentence(forServerError: words)
            #expect(!sentence.isEmpty)
            #expect(sentence.count <= 80)
            #expect(!sentence.contains("\u{2014}"))
            #expect(!sentence.lowercased().contains("token"))
            #expect(!sentence.lowercased().contains("context"))
            #expect(!sentence.contains("JSON"))
            #expect(sentence.rangeOfCharacter(from: .decimalDigits) == nil)
            #expect(sentence.hasSuffix("."))
        }
        #expect(AskTrouble.sentence(forServerError: raw[0]) == AskTrouble.tooMuchSentence)
        #expect(AskTrouble.sentence(forServerError: raw[0]) != AskTrouble.sentence(forServerError: raw[4]))
    }
}
