import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The brushes through the agent channel (`docs/design/brushes.md`, decision
/// 8): list them and their settings, pick and set the armed brush, and paint a
/// stroke from points with optional pressure, through the same stroke value a
/// person's pointer makes.
@Suite("Agent painting: list, set and paint with the brushes")
struct AgentPaintTests {

    static func args(_ json: String) throws -> AgentJSON {
        try AgentJSON.parse(Data(json.utf8))
    }

    static func stroke(_ json: String) throws -> AgentStroke {
        guard case .paintStroke(_, let stroke) = try AgentTools.request(tool: "paint_stroke", arguments: args(json)).get()
        else { throw AgentToolError("not a paint_stroke request") }
        return stroke
    }

    // MARK: The tools

    @Test("list_brushes, set_brush and paint_stroke are agent tools; Ask looks at the brushes and paints, never re-arms")
    func offered() {
        for name in ["list_brushes", "set_brush", "paint_stroke"] {
            #expect(AgentTools.tool(named: name) != nil, "\(name) is not offered")
        }
        #expect(AskTools.looking(painting: true).contains("list_brushes"))
        #expect(AskTools.doing(painting: true).contains("paint_stroke"))
        // Every other request is shown exactly what it was before.
        #expect(!AskTools.looking.contains("list_brushes") && !AskTools.doing.contains("paint_stroke"))
        // Arming the brush changes the person's tool, which one Command Z
        // over Ask's change would not take back.
        #expect(!AskTools.looking(painting: true).contains("set_brush") && !AskTools.doing(painting: true).contains("set_brush"))
    }

    @Test("Every medium in the schema is a medium the brush has")
    func mediaInTheSchema() throws {
        let schema = try #require(AgentTools.tool(named: "paint_stroke")?.inputSchema)
        let media = schema["properties"]?["medium"]?["enum"]?.arrayValue?.compactMap(\.stringValue)
        #expect(media == BrushMedium.allCases.map(\.rawValue))
    }

    // MARK: Checking a call

    @Test("list_brushes takes nothing but the document")
    func listBrushes() throws {
        #expect(try AgentTools.request(tool: "list_brushes", arguments: nil).get() == .listBrushes(document: nil))
        #expect(try AgentTools.request(tool: "list_brushes", arguments: Self.args(#"{"document": "d2"}"#)).get()
                == .listBrushes(document: "d2"))
    }

    @Test("set_brush carries the medium, mode, colour and settings it was given, a choice by its word or its index")
    func setBrush() throws {
        let request = try AgentTools.request(tool: "set_brush", arguments: Self.args(
            ##"{"medium": "pencil", "mode": "paint", "color": "#3366aa", "settings": {"size": 6, "hardness": "4B", "grain": 30}}"##)).get()
        guard case .setBrush(nil, let change) = request else { Issue.record("\(request)"); return }
        #expect(change.medium == .pencil)
        #expect(change.mode == .paint)
        #expect(change.colorHex == "#3366AA")
        #expect(change.settings["size"] == .number(6))
        #expect(change.settings["hardness"] == .choice("4B"))
    }

    @Test("set_brush with nothing to change is refused")
    func setBrushEmpty() {
        #expect(AgentTools.request(tool: "set_brush", arguments: nil).failure?.message.contains("set_brush") == true)
    }

    @Test("A colour that is not #RRGGBB is refused in words")
    func badColour() throws {
        let refused = AgentTools.request(tool: "set_brush", arguments: try Self.args(#"{"color": "red"}"#)).failure
        #expect(refused?.message.contains("#RRGGBB") == true)
    }

    @Test("paint_stroke needs two or more points; pressure and tilt ride along")
    func paintStroke() throws {
        let stroke = try Self.stroke(#"""
            {"points": [{"x": 10, "y": 20, "pressure": 0.5, "tilt": {"x": 0.2, "y": -0.1}}, {"x": 40, "y": 20, "pressure": 0.9}],
             "medium": "oil", "color": "#884422", "settings": {"size": 30}, "layer": "L1", "seed": 7}
            """#)
        #expect(stroke.samples.map(\.point) == [CGPoint(x: 10, y: 20), CGPoint(x: 40, y: 20)])
        #expect(stroke.samples.map(\.pressure) == [0.5, 0.9])
        #expect(stroke.samples[0].tilt == CGPoint(x: 0.2, y: -0.1))
        #expect(stroke.brush.medium == .oil)
        #expect(stroke.brush.colorHex == "#884422")
        #expect(stroke.layer == "L1")
        #expect(stroke.seed == 7)
        #expect(AgentTools.request(tool: "paint_stroke", arguments: try Self.args(#"{"points": [{"x": 1, "y": 1}]}"#))
                    .failure != nil, "one point is a dab, not a stroke; a click is two points in one place")
        #expect(AgentTools.request(tool: "paint_stroke", arguments: try Self.args(#"{"points": [{"x": 1, "y": 1}, {"x": 2, "y": 2, "pressure": 3}]}"#))
                    .failure?.message.contains("pressure") == true)
    }

    @Test("A path written short is the same stroke as its points")
    func shortPath() throws {
        let short = try Self.stroke(#"{"path": "10,20 40,20,0.7 40.5,60"}"#)
        let long = try Self.stroke(#"{"points": [{"x": 10, "y": 20}, {"x": 40, "y": 20, "pressure": 0.7}, {"x": 40.5, "y": 60}]}"#)
        #expect(short == long)
        #expect(AgentTools.request(tool: "paint_stroke", arguments: try Self.args(#"{"path": "10,20 forty,5"}"#))
                    .failure?.message.contains("x,y") == true)
        #expect(AgentTools.request(tool: "paint_stroke", arguments: try Self.args(#"{"path": "1,1 2,2", "points": [{"x": 1, "y": 1}, {"x": 2, "y": 2}]}"#))
                    .failure != nil, "one or the other")
        #expect(AgentTools.request(tool: "paint_stroke", arguments: nil).failure != nil)
    }

    @Test("A stroke cannot both name a layer and ask for a new one")
    func layerOrNew() throws {
        let both = AgentTools.request(tool: "paint_stroke", arguments: try Self.args(
            #"{"points": [{"x": 1, "y": 1}, {"x": 9, "y": 9}], "layer": "L1", "newLayer": true}"#))
        #expect(both.failure?.message.contains("newLayer") == true)
        #expect(try Self.stroke(#"{"points": [{"x": 1, "y": 1}, {"x": 9, "y": 9}], "newLayer": true}"#).newLayer)
    }

    // MARK: Timing and the hand

    @Test("Points with no time are walked at a steady hand's pace, too slow to thin a mouse's press")
    func steadyPace() throws {
        let stroke = try Self.stroke(#"{"points": [{"x": 0, "y": 0}, {"x": 30, "y": 0}, {"x": 30, "y": 40}]}"#)
        #expect(stroke.samples.map(\.ms) == [0, 30 / AgentPaint.handSpeed, 70 / AgentPaint.handSpeed])
        #expect(AgentPaint.handSpeed < 0.4, "a mouse's press starts to lighten at 0.4 points a millisecond")
        #expect(stroke.samples.allSatisfy { $0.pressure == nil && $0.tilt == nil }, "no pressure is a mouse")
    }

    @Test("Given times are kept, never going back")
    func givenTimes() throws {
        let stroke = try Self.stroke(#"{"points": [{"x": 0, "y": 0, "ms": 0}, {"x": 5, "y": 0, "ms": 16.5}, {"x": 9, "y": 0, "ms": 12}]}"#)
        #expect(stroke.samples.map(\.ms) == [0, 16.5, 16.5])
    }

    @Test("Points held in one place still move forward in time, so a held airbrush builds up")
    func heldPointsTakeTime() throws {
        let stroke = try Self.stroke(#"{"points": [{"x": 5, "y": 5}, {"x": 5, "y": 5}, {"x": 5, "y": 5}]}"#)
        #expect(stroke.samples.map(\.ms) == [0, AgentPaint.heldStepMS, 2 * AgentPaint.heldStepMS])
    }

    @Test("A pen's reading missing from some points is taken from the nearest point that has one")
    func pressureFilled() throws {
        let stroke = try Self.stroke(#"{"points": [{"x": 0, "y": 0}, {"x": 5, "y": 0, "pressure": 0.4}, {"x": 9, "y": 0}, {"x": 12, "y": 0, "pressure": 0.8}]}"#)
        #expect(stroke.samples.map(\.pressure) == [0.4, 0.4, 0.4, 0.8])
    }

    // MARK: The brush a stroke is painted with

    @Test("A change over the armed brush keeps everything it does not mention")
    func changeOverArmed() throws {
        var armed = BrushSettings(medium: .charcoal)
        armed.set("size", to: 22)
        let change = AgentBrushChange(settings: ["grain": .number(10)])
        let brush = try AgentPaint.brush(change, armed: armed, remembered: { BrushSettings(medium: $0) }).get()
        #expect(brush.medium == .charcoal)
        #expect(brush.size == 22)
        #expect(brush.value("grain") == 10)
    }

    @Test("Another medium starts from what that medium was last left at")
    func otherMedium() throws {
        var remembered = BrushSettings(medium: .marker)
        remembered.set("size", to: 5)
        let change = AgentBrushChange(medium: .marker, settings: ["tip": .choice("chisel")])
        let brush = try AgentPaint.brush(change, armed: BrushSettings(medium: .charcoal),
                                         remembered: { $0 == .marker ? remembered : BrushSettings(medium: $0) }).get()
        #expect(brush.medium == .marker)
        #expect(brush.size == 5)
        #expect(brush.value("tip") == 1, "a choice is found by its word, whatever its case")
    }

    @Test("A setting the medium does not have, or a value outside its range, is refused naming what it does take")
    func refusals() {
        let armed = BrushSettings(medium: .oil)
        let unknown = AgentPaint.brush(AgentBrushChange(settings: ["wetness": .number(50)]), armed: armed,
                                       remembered: { BrushSettings(medium: $0) })
        #expect(unknown.failure?.message.contains("load, smear") == true, "\(String(describing: unknown.failure))")
        let big = AgentPaint.brush(AgentBrushChange(settings: ["size": .number(900)]), armed: armed,
                                   remembered: { BrushSettings(medium: $0) })
        #expect(big.failure?.message.contains("1 to 500") == true, "\(String(describing: big.failure))")
        let grade = AgentPaint.brush(AgentBrushChange(medium: .pencil, settings: ["hardness": .choice("9B")]),
                                     armed: armed, remembered: { BrushSettings(medium: $0) })
        #expect(grade.failure?.message.contains("4H") == true, "\(String(describing: grade.failure))")
    }

    @Test("The stroke a call makes is the value the pointer would make: same samples, settings, colour and seed")
    func strokeValue() throws {
        let call = try Self.stroke(#"{"points": [{"x": 3, "y": 4, "ms": 0}, {"x": 50, "y": 9, "ms": 40}], "seed": 99}"#)
        let armed = BrushSettings(medium: .chalk)
        let stroke = try AgentPaint.brushStroke(call, armed: armed, armedColorHex: "#112233",
                                                remembered: { BrushSettings(medium: $0) },
                                                startedAt: 1000, seed: 5).get()
        #expect(stroke == BrushStroke(samples: [StrokeSample(point: CGPoint(x: 3, y: 4), ms: 0),
                                                StrokeSample(point: CGPoint(x: 50, y: 9), ms: 40)],
                                      settings: armed, colorHex: "#112233", seed: 99, startedAt: 1000))
    }

    @Test("An agent's strokes in quick succession start a hand's lift after the last one ended, so a wash dries as a person's would")
    func startsAfterTheLast() throws {
        let previous = BrushStroke(samples: [StrokeSample(point: .zero, ms: 0), StrokeSample(point: CGPoint(x: 9, y: 0), ms: 500)],
                                   settings: BrushSettings(medium: .watercolour), colorHex: "#000000", seed: 1, startedAt: 100)
        #expect(AgentPaint.startedAt(now: 100.1, after: previous) == 100.5 + AgentPaint.liftSeconds)
        #expect(AgentPaint.startedAt(now: 300, after: previous) == 300)
        #expect(AgentPaint.startedAt(now: 42, after: nil) == 42)
    }

    // MARK: Ask paints

    static func ask(_ request: String, brushes: Bool) -> AskConversation {
        AskConversation(request: request, documentRead: #"{"canvas":{"width":800,"height":560}}"#, paints: true,
                        brushes: brushes)
    }

    static func reply(_ name: String, _ args: AgentJSON) -> AgentJSON {
        ["message": ["role": "assistant", "content": "", "tool_calls": .array([["function": ["name": .string(name), "arguments": args]]])]]
    }

    @Test("Asked to paint with the brushes ready, Ask is taught to paint stroke by stroke; asked for anything else, it is not")
    func askIsTaughtToPaint() throws {
        let painting = try #require(Self.ask("paint a small landscape in oil", brushes: true).messages.first?["content"]?.stringValue)
        #expect(painting.contains("paint_stroke"))
        let drawing = try #require(Self.ask("draw a fox", brushes: true).messages.first?["content"]?.stringValue)
        #expect(!drawing.contains("paint_stroke once"))
        let noBrushes = try #require(Self.ask("paint a small landscape in oil", brushes: false).messages.first?["content"]?.stringValue)
        #expect(!noBrushes.contains("paint_stroke once"))
    }

    @Test("A request that is not a painting sees the same instructions and tools whether the Brush is there or not")
    func othersUnchanged() {
        for asked in ["draw a fox", "a photo of a dog on a beach", "measure the major elements"] {
            let with = Self.ask(asked, brushes: true), without = Self.ask(asked, brushes: false)
            #expect(with.messages == without.messages, "\(asked)")
            #expect(with.chatBody(model: "m") == without.chatBody(model: "m"), "\(asked)")
        }
        let painting = Self.ask("paint a small landscape in oil", brushes: true).chatBody(model: "m")
        let names = painting["tools"]?.arrayValue?.compactMap { $0["function"]?["name"]?.stringValue } ?? []
        #expect(names.contains("paint_stroke") && names.contains("list_brushes"))
    }

    @Test("A painting is painted with strokes: a whole-picture drawing or photo for it is turned back with what to do")
    func askPaintsStrokes() {
        var talk = Self.ask("paint a small landscape in oil", brushes: true)
        _ = talk.take(Self.reply("add_drawing", ["subject": "landscape", "scene": true]))
        #expect(talk.steps.isEmpty)
        #expect(talk.messages.last?["content"]?.stringValue?.contains("paint_stroke") == true)
        _ = talk.take(Self.reply("paint_stroke", ["medium": "oil", "color": "#6A8FC0", "settings": ["size": 60],
                                                  "points": [["x": 0, "y": 40], ["x": 400, "y": 30], ["x": 800, "y": 50]]]))
        #expect(talk.steps.map(\.tool) == ["paint_stroke"])
        #expect(talk.note == nil, "nothing to apologise for")
    }

    @Test("Before the brushes, a painting still falls back to one picture and says so")
    func noBrushesFallsBack() {
        var talk = Self.ask("paint a small landscape in oil", brushes: false)
        _ = talk.take(Self.reply("add_drawing", ["subject": "landscape", "scene": true]))
        #expect(talk.steps.first?.tool == "add_photo")
        #expect(talk.note == AskConversation.brushesNotReady)
    }

    @Test("Ask's row says it painted")
    func rowSaysPainted() {
        let steps = (0..<3).map { _ in AskStep(tool: "paint_stroke", arguments: ["medium": "oil"]) }
        #expect(AskChangeWords.sentence(steps).hasPrefix("Painted"))
    }

    // MARK: Reading it back

    @Test("read_document says how many strokes a paint layer holds and in which media")
    func readBack() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 200, height: 100))
        func stroke(_ medium: BrushMedium) -> BrushStroke {
            BrushStroke(samples: [StrokeSample(point: CGPoint(x: 10, y: 10), ms: 0),
                                  StrokeSample(point: CGPoint(x: 90, y: 40), ms: 200)],
                        settings: BrushSettings(medium: medium), colorHex: "#000000", seed: 1)
        }
        let layer = document.paintStroke(stroke(.oil), onto: nil)
        document.paintStroke(stroke(.pencil), onto: layer)
        document.paintStroke(stroke(.oil), onto: layer)
        let read = AgentDocumentRead.make(document, context: AgentDocumentRead.Context(
            id: "d1", title: "t", file: nil, playheadMS: 0, canUndo: true, canRedo: false))
        let painted = try #require(read.layers.first { $0.kind == "paint" })
        #expect(painted.paint == AgentDocumentRead.Painted(strokes: 3, media: ["oil", "pencil"]))
    }

    // MARK: The listing

    @Test("The listing names every medium with every setting: range and default, a choice by its words, the armed brush first")
    func listing() throws {
        var armed = BrushSettings(medium: .pencil)
        armed.set("hardness", to: 5)
        let listing = AgentBrushListing.make(armed: armed, colorHex: "#222222", remembered: { BrushSettings(medium: $0) })
        #expect(listing.armed.medium == "pencil")
        #expect(listing.armed.color == "#222222")
        #expect(listing.armed.settings["hardness"] == .choice("6B"))
        #expect(listing.brushes.map(\.medium) == BrushMedium.allCases.map(\.rawValue))
        let pencil = try #require(listing.brushes.first)
        #expect(pencil.settings.map(\.id) == BrushMedium.pencil.settings.map(\.id))
        let hardness = try #require(pencil.settings.first { $0.id == "hardness" })
        #expect(hardness.options == BrushMedium.pencilGrades)
        #expect(hardness.value == .choice("6B"))
        let size = try #require(pencil.settings.first { $0.id == "size" })
        #expect(size.min == 1 && size.max == 500 && size.options == nil)
        let encoded = String(decoding: try JSONEncoder().encode(listing), as: UTF8.self)
        #expect(encoded.contains("\"6B\""))
    }
}
