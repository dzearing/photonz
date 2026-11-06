import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Ask animates what it makes (task `ask-animates-what-it-makes-an-animated-svg-icon`):
/// the model draws every part a motion needs and keys them in one plan, naming
/// parts by their ids and speaking in the 24 grid it drew on. Nothing here
/// knows what the icon is of.
@Suite("Ask animates what it makes")
struct AskMotionTests {

    static let svg = ##"""
    <svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
    <g id="whole"><circle id="body" cx="12" cy="10" r="6"/><path id="tail" d="M12 16 L12 22"/></g>
    <path id="spark" d="M12 10 L12 8"/></svg>
    """##

    static func conversation(_ request: String, read: String = #"{"kind":"picture","canvas":{"width":1440,"height":1024}}"#) -> AskConversation {
        AskConversation(request: request, documentRead: read, paints: true)
    }

    static func reply(_ name: String, _ args: AgentJSON) -> AgentJSON {
        ["message": ["role": "assistant", "content": "", "tool_calls": .array([["function": ["name": .string(name), "arguments": args]]])]]
    }

    static func said(_ words: String) -> AgentJSON { ["message": ["role": "assistant", "content": .string(words)]] }

    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }

    static func drawn(_ talk: inout AskConversation) {
        _ = talk.take(reply("add_drawing", ["subject": "thing", "svg": .string(svg)]))
    }

    /// A blank picture with the drawing landed on it as an icon.
    static func landed() throws -> (document: PhotonzDocument, frame: UUID) {
        let art = try SVGArtwork.parse(svg, keepingGroups: true).get()
        var document = PhotonzDocument(canvasSize: CGSize(width: 512, height: 512), layers: [])
        let frame = document.addDrawing(art, named: "Thing", icon: true, side: 512, box: nil, blank: true, onGrid: true)
        return (document, frame)
    }

    static func layer(_ name: String, in document: PhotonzDocument) -> Layer? {
        func find(_ layers: [Layer]) -> Layer? {
            for layer in layers {
                if layer.name == name { return layer }
                if let inside = find(layer.children) { return inside }
            }
            return nil
        }
        return find(document.layers)
    }

    // MARK: Which requests

    @Test("Words for an animated file or an animated icon take the icon route, and animating what is here does not")
    func route() {
        for asked in ["make an animated SVG icon of a balloon popping", "an animated svg of a kite", "animate an icon of a star", "make a looping icon of a flag"] {
            #expect(AskConversation.takesIconRoute(asked, brushes: true, web: false), "\(asked)")
            #expect(AskMotion.drawsMotion(asked), "\(asked)")
        }
        for asked in ["animate it", "make the icon bounce", "a kite icon", "draw a kite", "an icon of a motion sensor"] {
            #expect(!AskMotion.drawsMotion(asked), "\(asked)")
        }
        #expect(!AskConversation.takesIconRoute("animate the icon", brushes: false, web: false, holdsIcon: true))
    }

    @Test("A moving icon is shown the key tools, only what an SVG carries, and is told how to key its parts")
    func offered() {
        let talk = Self.conversation("make an animated icon of a flag")
        let names = talk.offeredTools.compactMap { $0["function"]?["name"]?.stringValue }
        // Only what it uses: reading every tool was 100 s of each request.
        #expect(Set(names) == Set(AskMotion.tools))
        #expect(Set(talk.doingTools) == Set(AskMotion.tools))
        #expect(talk.lookingTools.isEmpty)
        let keys = talk.offeredTools.first { $0["function"]?["name"]?.stringValue == "set_keys" }
        let properties = keys?["function"]?["parameters"]?["properties"]?["property"]?["enum"]?.arrayValue?.compactMap(\.stringValue) ?? []
        #expect(Set(properties) == Set(MotionSVG.carried.map(\.rawValue)))
        let told = talk.messages.first?["content"]?.stringValue ?? ""
        #expect(told.contains("$1/"))
        #expect(told.contains("anticipation"))
        #expect(!told.contains("break its outline"))
    }

    @Test("An animation already here can be changed: the tools are offered and the rules say how")
    func tweakOffered() {
        let read = #"{"kind":"picture","canvas":{"width":512,"height":512},"lap":{"seconds":2,"loop":true}}"#
        let talk = Self.conversation("pop faster", read: read)
        let names = talk.offeredTools.compactMap { $0["function"]?["name"]?.stringValue }
        #expect(names.contains("change_keys"))
        #expect((talk.messages.first?["content"]?.stringValue ?? "").contains("change_keys"))
    }

    @Test("Nothing moves until it is asked for: a still icon's talk is as it was")
    func stillUntouched() {
        let talk = Self.conversation("a kite icon")
        let told = talk.messages.first?["content"]?.stringValue ?? ""
        #expect(!told.contains("change_keys"))
        #expect(told.contains("break its outline"))
    }

    @Test("The model can write what a key holds: a tool call is held to its schema, so a place and a pivot must be in it")
    func keyShapes() throws {
        for tools in [AskTools.keyModelTools, AskTools.pictureKeyModelTools] {
            let keys = try #require(tools.first { $0["function"]?["name"]?.stringValue == "set_keys" })
            let properties = try #require(keys["function"]?["parameters"]?["properties"])
            let value = try #require(properties["keys"]?["items"]?["properties"]?["value"])
            #expect(Set(value["type"]?.arrayValue?.compactMap(\.stringValue) ?? []) == ["number", "string", "object"])
            #expect(value["properties"]?["x"] != nil)
            #expect(properties["pivot"]?["type"]?.stringValue == "object")
            #expect(properties["pivot"]?["properties"]?["y"] != nil)
        }
    }

    @Test("A tool call is written in its schema's order, so a key says what it is about before its numbers")
    func keyOrder() throws {
        let body: AgentJSON = ["tools": .array(AskTools.pictureKeyModelTools)]
        let wire = String(decoding: AskTools.wireEncoded(body), as: UTF8.self)
        let tool = try #require(wire.range(of: "\"name\":\"set_keys\"").map { String(wire[$0.upperBound...]) } ?? wire.components(separatedBy: "set_keys").last)
        func at(_ word: String) -> Int { tool.range(of: "\"\(word)\":{").map { tool.distance(from: tool.startIndex, to: $0.lowerBound) } ?? Int.max }
        #expect(at("layer") < at("property"))
        #expect(at("property") < at("keys"))
        #expect(at("pivot") < at("keys"))
        let whole = String(decoding: AskTools.wireEncoded(body), as: UTF8.self)
        let keys = try #require(whole.range(of: "\"seconds\":{"))
        let value = try #require(whole.range(of: "\"value\":{"))
        let curve = try #require(whole.range(of: "\"curve\":{"))
        #expect(keys.lowerBound < value.lowerBound)
        #expect(value.lowerBound < curve.lowerBound)
    }

    @Test("A value of the wrong shape is sent back while the model can still mend it, not lost when the plan runs")
    func valueShapes() throws {
        for (json, words) in [
            (#"{"layer":"$1/body","property":"position","keys":[{"seconds":0,"value":3}]}"#, "x and y"),
            (#"{"layer":"$1/body","property":"opacity","keys":[{"seconds":0,"value":112}]}"#, "0 to 100"),
            (#"{"layer":"$1/body","property":"scale","keys":[{"seconds":0,"value":{"x":1,"y":1}}]}"#, "a number"),
            (#"{"layer":"$1/body","property":"color","keys":[{"seconds":0,"value":3}]}"#, "#RRGGBB"),
        ] {
            var talk = Self.conversation("make an animated icon of a thing")
            Self.drawn(&talk)
            _ = talk.take(Self.reply("set_keys", try Self.args(json)))
            #expect(talk.steps.count == 1, "\(json)")
            #expect((talk.messages.last?["content"]?.stringValue ?? "").contains(words), "\(json)")
        }
    }

    // MARK: Planning

    @Test("A moving icon's drawing is kept for motion, and is not looked at as a still")
    func keptForMotion() throws {
        var talk = Self.conversation("make an animated icon of a thing")
        #expect(talk.landsAsDrawn)
        Self.drawn(&talk)
        #expect(talk.steps.first?.arguments["forMotion"]?.boolValue == true)
        guard case .addDrawing(_, let call) = try AgentTools.request(tool: "add_drawing", arguments: talk.steps[0].arguments).get() else {
            Issue.record("not a drawing"); return
        }
        #expect(call.forMotion)
    }

    @Test("A part is named by its id, a group's too, and one that is not drawn is sent back with the ids that are")
    func partNames() throws {
        var talk = Self.conversation("make an animated icon of a thing")
        Self.drawn(&talk)
        _ = talk.take(Self.reply("set_keys", try Self.args(#"{"layer":"$1/whole","property":"scale","keys":[{"seconds":0,"value":100},{"seconds":1,"value":100}]}"#)))
        #expect(talk.steps.count == 2)
        _ = talk.take(Self.reply("set_keys", try Self.args(#"{"layer":"$1/wing","property":"scale","keys":[{"seconds":0,"value":100}]}"#)))
        #expect(talk.steps.count == 2)
        let answer = (talk.messages.last?["content"]?.stringValue ?? "").lowercased()
        #expect(answer.contains("wing"))
        #expect(answer.contains("spark"))
    }

    @Test("The whole drawing is not a part: a key goes on its parts")
    func wholeDrawing() throws {
        var talk = Self.conversation("make an animated icon of a thing")
        Self.drawn(&talk)
        _ = talk.take(Self.reply("set_keys", try Self.args(#"{"layer":"$1","property":"scale","keys":[{"seconds":0,"value":100}]}"#)))
        #expect(talk.steps.count == 1)
        #expect((talk.messages.last?["content"]?.stringValue ?? "").contains("$1/"))
    }

    @Test("A key on a part of a drawing that was left out is passed over with it")
    func namesItsDrawing() {
        let step = AskStep(tool: "set_keys", arguments: ["layer": "$1/body"])
        #expect(step.names(step: 1))
        #expect(!step.names(step: 2))
    }

    @Test("A pivot on anything but a turn is dropped rather than refused")
    func pivotOnScale() throws {
        var talk = Self.conversation("make an animated icon of a thing")
        Self.drawn(&talk)
        _ = talk.take(Self.reply("set_keys", try Self.args(#"{"layer":"$1/body","property":"scale","pivot":{"x":12,"y":10},"keys":[{"seconds":0,"value":100}]}"#)))
        #expect(talk.steps.count == 2)
        #expect(talk.steps[1].arguments["pivot"] == nil)
    }

    @Test("A part hidden in the drawing is sent back: a key hides it")
    func hiddenInTheDrawing() {
        var talk = Self.conversation("make an animated icon of a thing")
        let hidden = Self.svg.replacingOccurrences(of: #"<path id="spark""#, with: #"<path id="spark" opacity="0""#)
        _ = talk.take(Self.reply("add_drawing", ["subject": "thing", "svg": .string(hidden)]))
        #expect(talk.steps.isEmpty)
        #expect((talk.messages.last?["content"]?.stringValue ?? "").contains("opacity"))
    }

    @Test("A gap is drawn, not dashed: dashes do not reach the layers, and a spinning whole ring looks still")
    func dashed() {
        var talk = Self.conversation("make an animated icon of a thing")
        let dashed = Self.svg.replacingOccurrences(of: #"<path id="spark""#, with: #"<path id="spark" stroke-dasharray="4 2""#)
        _ = talk.take(Self.reply("add_drawing", ["subject": "thing", "svg": .string(dashed)]))
        #expect(talk.steps.isEmpty)
        #expect((talk.messages.last?["content"]?.stringValue ?? "").contains("dash"))
    }

    @Test("A plan that moves nothing, or jumps at the loop, goes back once; then it lands")
    func finishing() throws {
        var talk = Self.conversation("make an animated icon of a thing")
        Self.drawn(&talk)
        guard case .again = talk.take(Self.said("Done.")) else { Issue.record("a moving icon with no keys should go back"); return }
        _ = talk.take(Self.reply("set_keys", try Self.args(#"{"layer":"$1/body","property":"scale","keys":[{"seconds":0,"value":100},{"seconds":1,"value":140}]}"#)))
        guard case .again = talk.take(Self.said("Done.")) else { Issue.record("a jump at the loop should go back"); return }
        #expect((talk.messages.last?["content"]?.stringValue ?? "").contains("body"))
        guard case .planned = talk.take(Self.said("Done.")) else { Issue.record("it lands after that"); return }
    }

    @Test("A whole turn and a value that ends where it began do not jump; playing once may end anywhere")
    func loopCheck() throws {
        func step(_ json: String) throws -> AskStep { AskStep(tool: "set_keys", arguments: try Self.args(json)) }
        let turn = try step(#"{"layer":"$1/body","property":"rotation","keys":[{"seconds":0,"value":0},{"seconds":1,"value":360}]}"#)
        let back = try step(#"{"layer":"$1/body","property":"opacity","keys":[{"seconds":0,"value":0},{"seconds":0.4,"value":100},{"seconds":1,"value":0}]}"#)
        let moved = try step(#"{"layer":"$1/body","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":1,"value":{"x":4,"y":0}}]}"#)
        #expect(AskMotionCheck.problems([turn, back]) == [])
        #expect(AskMotionCheck.problems([moved]).count == 1)
        let once = AskStep(tool: "set_timing", arguments: ["loop": false])
        #expect(AskMotionCheck.problems([once, moved]) == [])
    }

    @Test("A line that draws itself and starts over is a loop, and is not told to end where it began")
    func drawingOnRestarts() throws {
        let drawn = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/body","property":"trimEnd","keys":[{"seconds":0,"value":0},{"seconds":0.8,"value":100},{"seconds":1.6,"value":100}]}"#))
        #expect(AskMotionCheck.problems([drawn]) == [])
    }

    @Test("A value whose keys never change moves nothing, and is said to")
    func flat() throws {
        let still = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/body","property":"trimEnd","keys":[{"seconds":0,"value":0},{"seconds":1.6,"value":0}]}"#))
        #expect(AskMotionCheck.problems([still]).joined().contains("body"))
    }

    @Test("Sent back, the model is told to give all of a value's keys, so a jump is mended and nothing is flattened")
    func sendBackWords() throws {
        let moved = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/body","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":1,"value":{"x":4,"y":0}}]}"#))
        let said = AskMotionCheck.problems([moved]).joined()
        #expect(said.contains("replace"))
        #expect(said.contains("all"))
    }

    @Test("A Hold just before the last key stands still and then jumps, so the last move is never seen")
    func holdBeforeTheEnd() throws {
        let held = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/body","property":"scale","keys":[{"seconds":0,"value":100},{"seconds":0.7,"value":0},{"seconds":1.4,"value":0,"curve":"Hold"},{"seconds":1.6,"value":100}]}"#))
        #expect(AskMotionCheck.problems([held]).joined().contains("Hold"))
        let fine = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/body","property":"scale","keys":[{"seconds":0,"value":100,"curve":"Hold"},{"seconds":0.7,"value":100},{"seconds":1.4,"value":0,"curve":"Hold"},{"seconds":1.5,"value":0},{"seconds":1.6,"value":100}]}"#))
        #expect(AskMotionCheck.problems([fine]) == [])
    }

    @Test("A motion that needs room gets it: the viewBox widens around the middle, so nothing is cut off and nobody is asked to move less")
    func fitsItsMotion() throws {
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(Self.svg)])
        func step(_ json: String) throws -> AskStep { AskStep(tool: "set_keys", arguments: try Self.args(json)) }
        func view(_ steps: [AskStep]) throws -> CGRect {
            let svg = try #require(AskMotion.fitted(steps).first?.arguments["svg"]?.stringValue)
            return try #require(try SVGArtwork.parse(svg).get().viewBox)
        }
        let grown = try step(#"{"layer":"$1/whole","property":"scale","keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":120},{"seconds":1,"value":100}]}"#)
        let box = try view([drawing, grown])
        #expect(box.width > 24)
        #expect(abs(box.width - box.height) < 0.01)
        #expect(abs(box.midX - 12) < 0.01)
        #expect(abs(box.midY - 12) < 0.01)
        let inside = try step(#"{"layer":"$1/spark","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":4,"y":-3}},{"seconds":1,"value":{"x":0,"y":0}}]}"#)
        #expect(AskMotion.fitted([drawing, inside]) == [drawing, inside])
        let gone = try step(#"{"layer":"$1/spark","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":-60}},{"seconds":1,"value":{"x":0,"y":0}}]}"#)
        #expect(try view([drawing, gone]).width <= 24 * AskMotion.mostRoom + 0.01, "flying right off is meant, and the icon stays a size to read")
    }

    @Test("A part that turns and travels has room for both at once, not for each on its own")
    func roomForBoth() throws {
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(Self.svg)])
        func step(_ json: String) throws -> AskStep { AskStep(tool: "set_keys", arguments: try Self.args(json)) }
        let turn = try step(#"{"layer":"$1/tail","property":"rotation","pivot":{"x":12,"y":20},"keys":[{"seconds":0,"value":0},{"seconds":0.5,"value":180},{"seconds":1,"value":0}]}"#)
        let move = try step(#"{"layer":"$1/tail","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":2}},{"seconds":1,"value":{"x":0,"y":0}}]}"#)
        func side(_ steps: [AskStep]) throws -> CGFloat {
            let svg = try #require(AskMotion.fitted(steps).first?.arguments["svg"]?.stringValue)
            return try #require(try SVGArtwork.parse(svg).get().viewBox).width
        }
        #expect(try side([drawing, turn, move]) > (try side([drawing, turn])))
    }

    @Test("A planned moving icon lands fitted, and the keys land on the wider grid")
    func plannedFits() throws {
        var talk = Self.conversation("make an animated icon of a thing")
        Self.drawn(&talk)
        _ = talk.take(Self.reply("set_keys", try Self.args(#"{"layer":"$1/whole","property":"scale","keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":125},{"seconds":1,"value":100}]}"#)))
        guard case .planned(let plan) = talk.take(Self.said("Done.")) else { Issue.record("it lands, with no send back for room"); return }
        let svg = try #require(plan.steps.first?.arguments["svg"]?.stringValue)
        #expect(try #require(try SVGArtwork.parse(svg).get().viewBox).width > 24)
    }

    // MARK: Landing

    @Test("The drawing lands on its own grid, its groups kept")
    func landsOnGrid() throws {
        let (document, frame) = try Self.landed()
        #expect(document.layer(id: frame)?.isFrame == true)
        let spark = try #require(Self.layer("spark", in: document) ?? Self.layer("Spark", in: document))
        // 12 across and 8 down on the 24 grid, at 512 / 24 points a unit.
        let box = try #require(document.canvasBounds(of: spark.id))
        #expect(abs(box.minX - 256) < 0.01)
        #expect(abs(box.minY - 8 * 512 / 24) < 0.01)
        #expect((Self.layer("Whole", in: document) ?? Self.layer("whole", in: document))?.group != nil)
    }

    @Test("A key on a part becomes the keys a person sets: its id, a place in points, a pivot on its box")
    func landing() throws {
        let (document, frame) = try Self.landed()
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(Self.svg), "icon": true, "forMotion": true])
        let move = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/spark","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":1,"value":{"x":3,"y":-6}}]}"#))
        let landed = try AskMotion.landing(move, in: document, plan: [drawing, move], made: [1: frame.uuidString]).get()
        let spark = try #require(Self.layer("Spark", in: document))
        #expect(landed.arguments["layer"]?.stringValue == spark.id.uuidString)
        let first = try #require(landed.arguments["keys"]?.arrayValue?.first?["value"])
        let last = try #require(landed.arguments["keys"]?.arrayValue?.last?["value"])
        #expect(abs((first["x"]?.doubleValue ?? 0) - spark.frame.minX) < 0.01)
        #expect(abs((last["x"]?.doubleValue ?? 0) - (spark.frame.minX + 64)) < 0.01)
        #expect(abs((last["y"]?.doubleValue ?? 0) - (spark.frame.minY - 128)) < 0.01)

        let turn = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/body","property":"rotation","pivot":{"x":12,"y":4},"keys":[{"seconds":0,"value":0},{"seconds":1,"value":90}]}"#))
        let turned = try AskMotion.landing(turn, in: document, plan: [drawing, turn], made: [1: frame.uuidString]).get()
        // The circle runs from 4 to 16 down, so 4 is its top and 12 its middle.
        #expect(abs((turned.arguments["pivot"]?["x"]?.doubleValue ?? 0) - 0.5) < 0.01)
        #expect(abs(turned.arguments["pivot"]?["y"]?.doubleValue ?? 1) < 0.01)
    }

    @Test("Landed keys work: the part moves, inside a group too, and the picture gets a lap")
    func landedKeysRun() throws {
        var (document, frame) = try Self.landed()
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(Self.svg), "icon": true, "forMotion": true])
        let steps = [
            #"{"layer":"$1/whole","property":"scale","keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":120},{"seconds":1,"value":100}]}"#,
            #"{"layer":"$1/tail","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":1,"value":{"x":0,"y":0}}]}"#,
        ]
        for json in steps {
            let step = AskStep(tool: "set_keys", arguments: try Self.args(json))
            let landed = try AskMotion.landing(step, in: document, plan: [drawing, step], made: [1: frame.uuidString]).get()
            guard case .setKeys(_, let call) = try AgentTools.request(tool: "set_keys", arguments: landed.arguments).get() else {
                Issue.record("not a set_keys call"); continue
            }
            _ = try document.agentSetKeys(call).get()
        }
        #expect(document.keyLap != nil)
        #expect((Self.layer("Whole", in: document)?.motions ?? []).count == 1)
        #expect((Self.layer("Tail", in: document)?.motions ?? []).count == 1)
    }

    @Test("A pivot written as fractions of the part is read as fractions: 0.5, 0.5 on a 24 grid is its middle")
    func pivotAsFractions() throws {
        let (document, frame) = try Self.landed()
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(Self.svg), "icon": true, "forMotion": true])
        let turn = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/body","property":"rotation","pivot":{"x":0.5,"y":0.5},"keys":[{"seconds":0,"value":0},{"seconds":1,"value":360}]}"#))
        let landed = try AskMotion.landing(turn, in: document, plan: [drawing, turn], made: [1: frame.uuidString]).get()
        #expect(landed.arguments["pivot"]?["x"]?.doubleValue == 0.5)
        #expect(landed.arguments["pivot"]?["y"]?.doubleValue == 0.5)
    }

    @Test("A turn is checked all the way round, not only at its keys, and about the pivot it will really have")
    func turnsAllTheWay() throws {
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(Self.svg)])
        let orbit = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/tail","property":"rotation","pivot":{"x":4,"y":4},"keys":[{"seconds":0,"value":0},{"seconds":1,"value":360}]}"#))
        #expect(AskMotion.fitted([drawing, orbit]) != [drawing, orbit])
        let spin = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/body","property":"rotation","pivot":{"x":0.5,"y":0.5},"keys":[{"seconds":0,"value":0},{"seconds":1,"value":360}]}"#))
        #expect(AskMotion.fitted([drawing, spin]) == [drawing, spin])
        // A whole drawing's worth of round thing, spinning about its middle, needs no room.
        let wide = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><circle id="ring" cx="12" cy="12" r="10"/></svg>"##
        let ring = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(wide)])
        let turning = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/ring","property":"rotation","pivot":{"x":12,"y":12},"keys":[{"seconds":0,"value":0},{"seconds":1,"value":360}]}"#))
        #expect(AskMotion.fitted([ring, turning]) == [ring, turning])
    }

    @Test("A moving icon is designed in words first, with its hinges and its beats, and then drawn from that")
    func designed() {
        let body = AskMotion.designBody(model: "m", request: "make an animated icon of a thing")
        let asked = body["messages"]?.arrayValue?.last?["content"]?.stringValue ?? ""
        #expect(asked.contains("hinge"))
        #expect(asked.contains("beats"))
        // Rough coordinates replace the form the model knows (`AskIcon.designAsk`).
        #expect(!asked.contains("coordinates"))
        #expect(AskMotion.design(fromAnswer: "Parts and beats.") == "Parts and beats.")
        #expect(AskMotion.design(fromAnswer: "<svg></svg>") == nil)
        let talk = AskConversation(request: "make an animated icon of a thing", documentRead: #"{"kind":"picture","canvas":{"width":512,"height":512}}"#, iconDesign: "A plan.")
        #expect(talk.messages.last?["content"]?.stringValue == AskMotion.drawTheDesign)
    }

    @Test("The rules are about motion in general and name no subject")
    func noSubjects() {
        let told = (AskMotion.drawRules + AskMotion.designAsk + AskMotion.keyRules + AskMotion.tweakRules).lowercased()
        for word in ["balloon", "bell", "heart", "spinner", "trash", "gear", "envelope", "checkmark"] {
            #expect(!told.contains(word), "\(word)")
        }
        #expect(told.contains("never one picture fading into another"))
        #expect(told.contains("left end"))
    }

    @Test("A part that did not land is said, in words the row can show")
    func partMissing() throws {
        let (document, frame) = try Self.landed()
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(Self.svg), "icon": true, "forMotion": true])
        let step = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/wing","property":"opacity","keys":[{"seconds":0,"value":0}]}"#))
        #expect(throws: AgentToolError.self) { try AskMotion.landing(step, in: document, plan: [drawing, step], made: [1: frame.uuidString]).get() }
    }

    @Test("A step with no part in it goes through as it was")
    func plainStep() throws {
        let (document, frame) = try Self.landed()
        let step = AskStep(tool: "set_timing", arguments: ["seconds": 2])
        #expect(try AskMotion.landing(step, in: document, plan: [step], made: [1: frame.uuidString]).get() == step)
    }

    @Test("What Ask keys says itself in the row: a lap, and what the file cannot carry")
    func sentence() {
        #expect(AskChangeWords.motionNote(lapSeconds: 1.6, loops: true, notMoving: []) == "Plays for 1.6 s and loops.")
        #expect(AskChangeWords.motionNote(lapSeconds: 2, loops: false, notMoving: []) == "Plays once, for 2 s.")
        #expect(AskChangeWords.motionNote(lapSeconds: 2, loops: true, notMoving: ["Lid", "Handle"]).contains("Lid and Handle"))
    }
}

/// A line drawing itself on leaves the app (`StrokeTrim`, `MotionSVG`).
@Suite("A line drawing itself in an animated SVG")
struct SVGTrimMotionTests {

    static func path() -> Layer {
        let content = PathContent(anchors: [PathAnchor(point: CGPoint(x: 10, y: 10)), PathAnchor(point: CGPoint(x: 90, y: 10))],
                                  isClosed: false, paint: Paint(hex: "#112233"), strokeWidth: 4)
        return PathBuilder.layer(content, at: content.bounds.origin, name: "Line")
    }

    @Test("A keyed trim is written as a dash, carried and not dropped")
    func written() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [Self.path()])
        let id = document.layers[0].id
        _ = try document.agentSetKeys(AgentSetKeys(layer: id.uuidString, property: .trimEnd, keys: [
            AgentKey(atMS: 0, value: .number(0)), AgentKey(atMS: 1000, value: .number(100)),
        ])).get()
        let wrap = MotionSVG.wrap(for: try #require(document.layer(id: id)), cycleMS: 1000, level: 0, isPicture: false)
        #expect(wrap.dropped.isEmpty)
        #expect(wrap.pathLength)
        let written = wrap.opens.joined()
        #expect(written.contains("stroke-dasharray=\"100 200\""))
        #expect(written.contains("attributeName=\"stroke-dashoffset\""))
        #expect(written.contains("values=\"100.5;0\""))
    }

    @Test("A trim on a shape with no line of its own says so")
    func dropped() throws {
        let box = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FF0000")),
                        frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let motion = LayerMotion.keyed(.trimEnd, effect: 0, atMS: 0, value: .number(0))
        var keyed = box
        keyed.motions = [motion]
        #expect(!MotionSVG.wrap(for: keyed, cycleMS: 1000, level: 0, isPicture: false).dropped.isEmpty)
    }

    @Test("A box no taller than its line is a solid bar, in a still file and a moving one, not nothing")
    func thinBar() throws {
        var box = Layer(name: "Bar", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#112233")),
                        frame: CGRect(x: 10, y: 20, width: 80, height: 8))
        if var annotation = box.annotation {
            annotation.fill = nil
            annotation.strokeWidth = 0
            box.content = .annotation(annotation)
        }
        var ring = BorderEffect()
        ring.width = 8
        ring.paint = Paint(hex: "#112233")
        ring.position = .inside
        box.style.effects = [.border(ring)]
        let document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [box])
        let text = SVGExport.write(document, background: .drop).text
        #expect(text.contains("#112233"))
        #expect(text.contains("width=\"80\""))
    }

    @Test("The carried list is what the exporter writes")
    func carried() {
        #expect(MotionSVG.carried.contains(.trimEnd))
        #expect(!MotionSVG.carried.contains(.blur))
    }
}
