import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Ask changes what it just made ("make the water bluer" after "paint a beach
/// at sunset"): what it makes is labelled by its parts, in the model's own
/// words; the model is handed a short memory of the window's requests; and it
/// has a tool that changes one named part in place.
@Suite("Ask changes what it just made: parts, memory and change_part")
struct AskChangesWhatItMadeTests {

    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }

    static func stroke(_ points: [CGPoint], hex: String, part: String?, size: Double = 10) -> BrushStroke {
        var settings = BrushSettings(medium: .oil)
        settings.set("size", to: size)
        return BrushStroke(samples: points.enumerated().map { StrokeSample(point: $1, ms: Double($0) * 8) },
                           settings: settings, colorHex: hex, seed: 7, part: part)
    }

    /// A painted beach: two sky strokes, three water strokes in close shades, a sun.
    static func beach() -> (PhotonzDocument, UUID) {
        let strokes = [
            stroke([CGPoint(x: 0, y: 40), CGPoint(x: 400, y: 40)], hex: "#E8A070", part: "sky"),
            stroke([CGPoint(x: 0, y: 80), CGPoint(x: 400, y: 80)], hex: "#E09060", part: "sky"),
            stroke([CGPoint(x: 0, y: 160), CGPoint(x: 400, y: 160)], hex: "#3C7A8C", part: "water"),
            stroke([CGPoint(x: 0, y: 180), CGPoint(x: 400, y: 180)], hex: "#4A8A9C", part: "water"),
            stroke([CGPoint(x: 0, y: 200), CGPoint(x: 400, y: 200)], hex: "#2E6A7C", part: "water"),
            stroke([CGPoint(x: 190, y: 60), CGPoint(x: 210, y: 60)], hex: "#FFD040", part: "sun", size: 20),
        ]
        let layer = Layer(name: "Paint", content: .paint(PaintContent(strokes: strokes)),
                          frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        return (PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [layer]), layer.id)
    }

    static func change(_ json: String) throws -> AgentPartChange {
        guard case .changePart(_, let change) = try AgentTools.request(tool: "change_part", arguments: args(json)).get()
        else { throw AgentToolError("not a change_part request") }
        return change
    }

    static func hsl(_ hex: String) -> (h: Double, s: Double, l: Double) { AgentGroupRecolour.hsl(AgentGroupRecolour.rgb(hex)) }

    // MARK: Parts on what Ask paints

    @Test("paint_stroke takes the part a stroke paints, and the stroke keeps it")
    func paintStrokeTakesAPart() throws {
        guard case .paintStroke(_, let call) = try AgentTools.request(
            tool: "paint_stroke", arguments: Self.args(#"{"path": "0,0 10,10", "part": "water"}"#)).get()
        else { Issue.record("not a paint_stroke"); return }
        #expect(call.part == "water")
        let made = try AgentPaint.brushStroke(call, armed: BrushSettings(medium: .oil), armedColorHex: "#000000",
                                              remembered: { BrushSettings(medium: $0) }, startedAt: 0, seed: 1).get()
        #expect(made.part == "water")
    }

    @Test("A stroke with no part saves exactly as before, and one with a part survives a reopen")
    func partIsSavedOnlyWhenThere() throws {
        let plain = Self.stroke([.zero, CGPoint(x: 1, y: 1)], hex: "#000000", part: nil)
        let text = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!text.contains("part"))
        let named = Self.stroke([.zero, CGPoint(x: 1, y: 1)], hex: "#000000", part: "sun")
        #expect(try JSONDecoder().decode(BrushStroke.self, from: JSONEncoder().encode(named)).part == "sun")
    }

    @Test("A painted sketch carries each shape's own id onto its strokes and calls, in the model's words")
    func sketchStrokesCarryTheShapesName() throws {
        let art = try SVGArtwork.parse(#"""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 960 640">
          <rect id="sky" x="0" y="0" width="960" height="400" fill="#E8A070"/>
          <rect id="sea" x="0" y="400" width="960" height="240" fill="#3C7A8C"/>
          <circle id="sun" cx="480" cy="300" r="60" fill="#FFD040"/>
        </svg>
        """#).get()
        let strokes = BrushSketch.strokes(art, canvas: CGSize(width: 960, height: 640), medium: .oil, seed: 3)
        let parts = strokes.compactMap(\.part)
        #expect(parts.count == strokes.count, "every stroke of a named shape carries its name")
        #expect(Set(parts) == ["Sky", "Sea", "Sun"])
        let calls = BrushSketch.calls(strokes, medium: .oil)
        #expect(calls.allSatisfy { $0["part"]?.stringValue != nil })
    }

    @Test("read_document lists a paint layer's parts in the order they were first painted")
    func readListsParts() {
        let (document, _) = Self.beach()
        let context = AgentDocumentRead.Context(id: "d1", title: "Beach", file: nil, playheadMS: 0, canUndo: true, canRedo: false)
        let read = AgentDocumentRead.make(document, context: context)
        #expect(read.layers.first?.paint?.parts == ["sky", "water", "sun"])
    }

    // MARK: change_part, the call

    @Test("change_part is an agent tool Ask plans with, and refuses a call that changes nothing")
    func theCall() throws {
        #expect(AgentTools.tool(named: "change_part") != nil)
        #expect(AskTools.doing.contains("change_part"))
        let recolour = try Self.change(##"{"part": "water", "color": "#1E64DC"}"##)
        #expect(recolour.part == "water" && recolour.colorHex == "#1E64DC")
        let grow = try Self.change(#"{"part": "sun", "scale": 1.5, "layer": "L1"}"#)
        #expect(grow.scale == 1.5 && grow.layer == "L1")
        guard case .failure = AgentTools.request(tool: "change_part", arguments: try Self.args(#"{"part": "water"}"#)) else {
            Issue.record("a change_part that changes nothing should be refused"); return
        }
        guard case .failure = AgentTools.request(tool: "change_part", arguments: try Self.args(##"{"color": "#000000"}"##)) else {
            Issue.record("a change_part with no part should be refused"); return
        }
    }

    // MARK: change_part on a painting

    @Test("Recolouring a painted part moves only its strokes toward the colour, keeping their shading")
    func recolourPaintedPart() throws {
        var (document, id) = Self.beach()
        let before = document.layer(id: id)?.paint?.strokes ?? []
        let answer = try document.agentChangePart(Self.change(##"{"part": "water", "color": "#1E64DC"}"##)).get()
        #expect(answer.strokes == 3)
        let after = document.layer(id: id)?.paint?.strokes ?? []
        // Sky and sun untouched.
        for index in [0, 1, 5] { #expect(after[index] == before[index]) }
        // The water is bluer: every stroke's hue is now near the asked hue.
        let target = Self.hsl("#1E64DC").h
        for index in 2...4 {
            #expect(abs(Self.hsl(after[index].colorHex).h - target) < 0.04, "\(after[index].colorHex) is not blue")
        }
        // Shading kept: the three water strokes are still three shades, in the same order of lightness.
        let lights = (2...4).map { Self.hsl(after[$0].colorHex).l }
        #expect(Set(after[2...4].map(\.colorHex)).count == 3)
        #expect(lights[1] > lights[0] && lights[0] > lights[2])
        // Nothing but the colour changed.
        for index in 2...4 { #expect(after[index].samples == before[index].samples) }
    }

    @Test("A part can be named in any case, and hue, saturation and lightness shift it by amounts")
    func shiftByAmounts() throws {
        var (document, id) = Self.beach()
        _ = try document.agentChangePart(Self.change(#"{"part": "Sky", "lightness": -20}"#)).get()
        let after = document.layer(id: id)?.paint?.strokes ?? []
        #expect(Self.hsl(after[0].colorHex).l < Self.hsl("#E8A070").l - 0.15)
    }

    @Test("Scaling a painted part grows it about its own middle, brush and all; moving shifts it")
    func scaleAndMovePaintedPart() throws {
        var (document, id) = Self.beach()
        let sun = document.layer(id: id)?.paint?.strokes[5]
        _ = try document.agentChangePart(Self.change(#"{"part": "sun", "scale": 2}"#)).get()
        let grown = document.layer(id: id)?.paint?.strokes[5]
        #expect(grown?.samples.map(\.point) == [CGPoint(x: 180, y: 60), CGPoint(x: 220, y: 60)])
        #expect(grown?.settings.size == (sun?.settings.size ?? 0) * 2)
        _ = try document.agentChangePart(Self.change(#"{"part": "sun", "dx": 10, "dy": -5}"#)).get()
        #expect(document.layer(id: id)?.paint?.strokes[5].samples.first?.point == CGPoint(x: 190, y: 55))
    }

    @Test("Removing a painted part takes its strokes away and nothing else")
    func removePaintedPart() throws {
        var (document, id) = Self.beach()
        let answer = try document.agentChangePart(Self.change(#"{"part": "sun", "remove": true}"#)).get()
        #expect(answer.strokes == 1)
        let left = document.layer(id: id)?.paint?.strokes ?? []
        #expect(left.count == 5 && !left.contains { $0.part == "sun" })
    }

    @Test("A part nobody painted is refused, naming the parts there are")
    func unknownPart() throws {
        var (document, _) = Self.beach()
        guard case .failure(let refused) = document.agentChangePart(try Self.change(#"{"part": "boat", "remove": true}"#)) else {
            Issue.record("an unknown part should be refused"); return
        }
        #expect(refused.message.contains("sky") && refused.message.contains("water") && refused.message.contains("sun"))
    }

    // MARK: change_part on a drawing's named layers

    static func drawing() -> (PhotonzDocument, UUID, UUID) {
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0), CGPoint(x: 40, y: 40), CGPoint(x: 0, y: 40)]
        let sun = Layer(name: "Sun", content: .path(PathContent(anchors: square.map { PathAnchor(point: $0) }, isClosed: true,
                                                               paint: Paint(hex: "#FFD040"), strokeWidth: 0,
                                                               fill: Paint(hex: "#FFD040"))),
                        frame: CGRect(x: 40, y: 20, width: 40, height: 40))
        let hill = Layer(name: "Hill", content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#3A8040",
                                                                              fillColorHex: "#3A8040")),
                         frame: CGRect(x: 0, y: 60, width: 200, height: 40))
        let group = Layer(name: "Landscape", content: .group(GroupContent(children: [hill, sun])),
                          frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        return (PhotonzDocument(canvasSize: CGSize(width: 200, height: 100), layers: [group]), group.id, sun.id)
    }

    @Test("On a drawing, the part is the layer of that name: recoloured, grown about its middle or removed")
    func namedLayerParts() throws {
        var (document, _, sun) = Self.drawing()
        _ = try document.agentChangePart(Self.change(##"{"part": "sun", "color": "#FF6020"}"##)).get()
        #expect(document.layer(id: sun)?.path?.fill?.hex.uppercased() == "#FF6020")
        _ = try document.agentChangePart(Self.change(#"{"part": "sun", "scale": 1.5}"#)).get()
        #expect(document.layer(id: sun)?.frame == CGRect(x: 30, y: 10, width: 60, height: 60))
        #expect(document.layer(id: sun)?.path?.anchors.map(\.point).last == CGPoint(x: 0, y: 60))
        let answer = try document.agentChangePart(Self.change(#"{"part": "sun", "remove": true}"#)).get()
        #expect(answer.layers == 1)
        #expect(document.layer(id: sun) == nil)
    }

    // MARK: The memory

    @Test("The memory names each recent request, what it did and the parts of what it made, oldest first")
    func memoryPrompt() {
        let (document, id) = Self.beach()
        let turns = [
            AskMemory.Turn(asked: "paint a beach at sunset", did: "Painted a beach at sunset",
                           made: [AskMemory.Made(id: id.uuidString, name: "Paint", kind: "paint", parts: ["sky", "water", "sun"])]),
            AskMemory.Turn(asked: "make the water bluer", did: "Made the water bluer", made: []),
        ]
        let prompt = AskMemory.prompt(turns)
        #expect(prompt.contains("paint a beach at sunset"))
        #expect(prompt.contains(id.uuidString) && prompt.contains("sky, water, sun"))
        #expect(prompt.range(of: "paint a beach")?.lowerBound ?? prompt.endIndex
                < prompt.range(of: "make the water bluer")?.lowerBound ?? prompt.startIndex)
        #expect(prompt.contains("change_part"))
        #expect(AskMemory.prompt([]).isEmpty)
        _ = document
    }

    @Test("The memory is read from the window's rows that are still on, the latest few, with what each made now")
    func memoryFromRows() {
        let (beach, id) = Self.beach()
        let blank = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [])
        var rows = AskChangeList()
        rows.record(asked: "paint a beach at sunset", sentence: "Painted a beach at sunset", before: blank, after: beach)
        let turns = AskMemory.turns(from: rows, in: beach)
        #expect(turns.count == 1)
        #expect(turns.first?.made.first?.id == id.uuidString)
        #expect(turns.first?.made.first?.parts == ["sky", "water", "sun"])
        // A row turned off made nothing that is still there: it is not remembered.
        guard let row = rows.rows.first else { return }
        _ = rows.setOn(false, id: row.id, in: beach)
        #expect(AskMemory.turns(from: rows, in: blank).isEmpty)
        // At most the latest few.
        var many = AskChangeList()
        for n in 0..<(AskMemory.mostTurns + 3) {
            many.record(asked: "request \(n)", sentence: "Did \(n)", before: blank, after: beach)
        }
        let kept = AskMemory.turns(from: many, in: blank)
        #expect(kept.count == AskMemory.mostTurns)
        #expect(kept.last?.asked == "request \(AskMemory.mostTurns + 2)")
    }

    @Test("Ask hands the model the memory and a picture of the canvas with the request")
    func conversationCarriesMemoryAndPicture() {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let talk = AskConversation(request: "make the water bluer", documentRead: #"{"canvas":{"width":400,"height":300}}"#,
                                   memory: "Earlier in this conversation: paint a beach", canvas: png)
        let body = talk.chatBody(model: "m")
        let messages = body["messages"]?.arrayValue ?? []
        #expect(messages.first?["content"]?.stringValue?.contains("Earlier in this conversation: paint a beach") == true)
        #expect(messages.last?["images"]?.arrayValue?.first?.stringValue == png.base64EncodedString())
        let plain = AskConversation(request: "draw a fox", documentRead: "{}")
        #expect(plain.chatBody(model: "m")["messages"]?.arrayValue?.last?["images"] == nil)
    }

    @Test("A change_part step is planned, and its row says the change in the person's words")
    func plannedAndWorded() {
        var talk = AskConversation(request: "make the water bluer", documentRead: #"{"canvas":{"width":400,"height":300}}"#)
        let reply: AgentJSON = ["message": ["role": "assistant", "content": "",
                                            "tool_calls": [["function": ["name": "change_part",
                                                                         "arguments": ["part": "water", "color": "#1E64DC"]]]]]]
        guard case .again = talk.take(reply) else { Issue.record("expected another turn"); return }
        #expect(talk.steps.map(\.tool) == ["change_part"])
        let sentence = AskChangeWords.sentence(talk.steps, asked: "make the water bluer")
        #expect(sentence == "Made the water bluer")
    }
}
