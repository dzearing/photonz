import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Three motions Ask's moving icons fell short on (task
/// `an-animated-icon-s-flap-reads-and-a-drawn-line-e`): a flap turned flat
/// across its body instead of folding over its edge, a part that flew off
/// stopped half over the frame's edge, and a line keyed at both ends lost
/// one of them in the file. Every rule here is geometry: nothing knows what
/// the icon is of.
@Suite("Ask's moving icons fold, leave and draw cleanly")
struct AskMotionFoldTests {

    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }

    static func box() -> (document: PhotonzDocument, id: UUID) {
        let box = Layer(name: "Flap", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FF0000")),
                        frame: CGRect(x: 8, y: 10, width: 24, height: 12))
        return (PhotonzDocument(canvasSize: CGSize(width: 48, height: 48), layers: [box]), box.id)
    }

    // MARK: A fold

    @Test("A fold may name its hinge: a key on rotationX with a pivot is taken, not refused")
    func foldTakesAPivot() throws {
        let id = UUID().uuidString
        guard case .setKeys(_, let call) = try AgentTools.request(tool: "set_keys", arguments: Self.args("""
            {"layer": "\(id)", "property": "rotationX", "pivot": {"x": 0.5, "y": 0},
             "keys": [{"seconds": 0, "value": 0}, {"seconds": 1, "value": 180}]}
            """)).get() else { Issue.record("not set_keys"); return }
        #expect(call.pivot == .unit(CGPoint(x: 0.5, y: 0)))
        #expect(throws: AgentToolError.self) {
            try AgentTools.request(tool: "set_keys", arguments: Self.args("""
                {"layer": "\(id)", "property": "opacity", "pivot": {"x": 0.5, "y": 0}, "keys": [{"seconds": 0, "value": 0}]}
                """)).get()
        }
    }

    @Test("A fold's pivot is its hinge: the layer turns in space about that edge")
    func foldSetsTheHinge() throws {
        var (document, id) = Self.box()
        _ = try document.agentSetKeys(AgentSetKeys(layer: id.uuidString, property: .rotationX, keys: [
            AgentKey(atMS: 0, value: .number(0)), AgentKey(atMS: 1000, value: .number(180)),
        ], pivot: .unit(CGPoint(x: 0.5, y: 0)))).get()
        let layer = try #require(document.layer(id: id))
        #expect(layer.turn3D?.hinge == CGPoint(x: 0.5, y: 0))
        #expect(layer.spacePivot == CGPoint(x: 20, y: 10))
    }

    @Test("A fold leaves the app in the file: a flip about its hinge, drawn point by point")
    func foldIsWritten() throws {
        var (document, id) = Self.box()
        _ = try document.agentSetKeys(AgentSetKeys(layer: id.uuidString, property: .rotationX, keys: [
            AgentKey(atMS: 0, value: .number(0)), AgentKey(atMS: 1000, value: .number(180)),
        ], pivot: .unit(CGPoint(x: 0.5, y: 0)))).get()
        let layer = try #require(document.layer(id: id))
        let wrap = MotionSVG.wrap(for: layer, cycleMS: 1000, level: 0, isPicture: false)
        #expect(wrap.dropped.isEmpty)
        let written = wrap.opens.joined(separator: "\n")
        #expect(written.contains("type=\"scale\""))
        // About the top edge's middle, stepping out to it and back.
        #expect(written.contains("translate(20 10)"))
        #expect(written.contains("translate(-20 -10)"))
        let values = try #require(SVGMotionExportTests.valueLists(written).first)
        #expect(values.first == "1 1")
        #expect(values.last == "1 -1")
        // A cosine is no cubic: it is drawn in many moments, and passes edge on.
        #expect(values.count > 12)
        #expect(values.contains { $0.hasPrefix("1 0") || $0.hasPrefix("1 -0.0") })
        #expect(MotionSVG.carried.contains(.rotationX) && MotionSVG.carried.contains(.rotationY))
    }

    @Test("A side fold flips across, and a fold that moves keeps its hinge with it")
    func sideFold() throws {
        var (document, id) = Self.box()
        _ = try document.agentSetKeys(AgentSetKeys(layer: id.uuidString, property: .rotationY, keys: [
            AgentKey(atMS: 0, value: .number(0)), AgentKey(atMS: 1000, value: .number(180)),
        ], pivot: .unit(CGPoint(x: 0, y: 0.5)))).get()
        _ = try document.agentSetKeys(AgentSetKeys(layer: id.uuidString, property: .position, keys: [
            AgentKey(atMS: 0, value: .point(CGPoint(x: 8, y: 10))), AgentKey(atMS: 1000, value: .point(CGPoint(x: 8, y: 2))),
        ])).get()
        let wrap = MotionSVG.wrap(for: try #require(document.layer(id: id)), cycleMS: 1000, level: 0, isPicture: false)
        let opens = wrap.opens
        let move = try #require(opens.firstIndex { $0.contains("type=\"translate\"") })
        let flip = try #require(opens.firstIndex { $0.contains("type=\"scale\"") })
        #expect(move < flip, "the hinge is said where the layer was drawn, inside the move")
        #expect(SVGMotionExportTests.valueLists(opens.joined(separator: "\n")).contains { $0.last == "-1 1" })
    }

    @Test("Ask keeps a fold's hinge, lands it on the part, and makes room for the flap's swing")
    func askFolds() throws {
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><rect id="body" x="3" y="8" width="18" height="12"/><path id="flap" d="M3 8 L12 14 L21 8 Z"/></svg>"##
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(svg)])
        let fold = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/flap","property":"rotationX","pivot":{"x":12,"y":8},"keys":[{"seconds":0,"value":0},{"seconds":0.6,"value":180},{"seconds":1.2,"value":0}]}"#))
        #expect(AskMotion.tidied(fold.arguments)["pivot"] != nil)
        let art = try SVGArtwork.parse(svg, keepingGroups: true).get()
        let reach = AskMotionCheck.reach(of: [fold], in: art)
        // Laid open, the flap stands above its hinge as far as it hung below it.
        #expect(reach.minY < 3)
        #expect(abs(reach.minX - 2) < 0.01 && abs(reach.maxX - 22) < 0.01, "a fold over a level edge grows no wider")
        #expect(AskMotionCheck.problems([drawing, AskStep(tool: "set_timing", arguments: ["seconds": .number(1.2)]), fold]).isEmpty)
    }

    // MARK: Leaving the frame

    /// The part's box at a position key, on the drawing's grid, after `fitted`.
    static func boxes(_ steps: [AskStep], part: String) throws -> (view: CGRect, at: [CGRect]) {
        let fitted = AskMotion.fitted(steps)
        let svg = try #require(fitted.first?.arguments["svg"]?.stringValue)
        let art = try SVGArtwork.parse(svg, keepingGroups: true).get()
        let view = try #require(art.viewBox)
        let still = try #require(AskMotionCheck.reach(of: fitted.filter {
            $0.tool == "set_keys" && $0.arguments["property"]?.stringValue != "position"
        }, in: art, only: part))
        let moves = fitted.filter { $0.arguments["property"]?.stringValue == "position" }
        let at = moves.flatMap { $0.arguments["keys"]?.arrayValue ?? [] }.compactMap { key -> CGRect? in
            guard let x = key["value"]?["x"]?.doubleValue, let y = key["value"]?["y"]?.doubleValue else { return nil }
            return still.offsetBy(dx: x, dy: y)
        }
        return (view, at)
    }

    @Test("A part that travels past all the room there is leaves the frame whole, never stopping half over its edge")
    func leavesWhole() throws {
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><g id="thing"><path id="body" d="M21 3 L3 11 L9 13 L11 19 Z"/></g></svg>"##
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(svg)])
        let turn = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/thing","property":"rotation","pivot":{"x":0.125,"y":0.542},"keys":[{"seconds":0,"value":0},{"seconds":0.3,"value":6},{"seconds":0.7,"value":-22},{"seconds":1.1,"value":-22},{"seconds":1.4,"value":0},{"seconds":1.8,"value":0}]}"#))
        let move = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/thing","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.3,"value":{"x":0,"y":1}},{"seconds":0.7,"value":{"x":3,"y":-3}},{"seconds":1.1,"value":{"x":12,"y":-12}},{"seconds":1.4,"value":{"x":0,"y":0}},{"seconds":1.8,"value":{"x":0,"y":0}}]}"#))
        let (view, at) = try Self.boxes([drawing, turn, move], part: "thing")
        let room = view.insetBy(dx: -AskMotionCheck.edgeSlack, dy: -AskMotionCheck.edgeSlack)
        for box in at {
            #expect(room.contains(box) || !box.intersects(view), "at \(box) it is half over the edge of \(view)")
        }
        #expect(at.contains { !$0.intersects(view) }, "it does leave")
        #expect(at.first.map { room.contains($0) } == true, "it starts at rest, inside")
        // A small dip before the launch stays a small dip, and the climb
        // that nearly fits is brought in, still climbing the way it was keyed.
        #expect(at.count > 2 && abs(at[1].minX - at[0].minX) < 0.01 && abs(at[1].minY - at[0].minY - 1) < 0.01)
        #expect(at[2].minX > at[0].minX + 1 && at[2].minY < at[0].minY - 1 && room.contains(at[2]))
        // Gone up and right, it comes back in from down and left, not back down
        // the way it left: a Hold while it is out of sight, then the far side.
        let gone = try #require(at.firstIndex { !$0.intersects(view) })
        #expect(at.count > gone + 1)
        #expect(at[gone + 1].minY > view.maxY || at[gone + 1].maxX < view.minX, "it re-enters from the other side")
        let keys = try #require(AskMotion.fitted([drawing, turn, move]).last?.arguments["keys"]?.arrayValue)
        #expect(keys[gone]["curve"]?.stringValue == AgentKeyCurve.hold)
        #expect(keys.compactMap { $0["seconds"]?.doubleValue } == keys.compactMap { $0["seconds"]?.doubleValue }.sorted())
    }

    @Test("A swing that reaches past all the room there is swings a little less, rather than being cut off; a whole turn is left alone")
    func swingFits() throws {
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><g id="thing"><path id="body" d="M21 3 L3 11 L10 13 L12 20 L15 13 Z"/></g></svg>"##
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(svg)])
        let swing = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/thing","property":"rotation","pivot":{"x":3,"y":11},"keys":[{"seconds":0,"value":0},{"seconds":0.3,"value":6},{"seconds":0.5,"value":-60},{"seconds":1.3,"value":-60},{"seconds":1.8,"value":0}]}"#))
        let fitted = AskMotion.fitted([drawing, swing])
        let svgOut = try #require(fitted.first?.arguments["svg"]?.stringValue)
        let art = try SVGArtwork.parse(svgOut, keepingGroups: true).get()
        let view = try #require(art.viewBox)
        let reach = AskMotionCheck.reach(of: Array(fitted.dropFirst()), in: art)
        #expect(view.insetBy(dx: -AskMotionCheck.edgeSlack, dy: -AskMotionCheck.edgeSlack).contains(reach))
        let angles = (fitted.last?.arguments["keys"]?.arrayValue ?? []).compactMap { $0["value"]?.doubleValue }
        #expect(angles.first == 0 && angles.last == 0)
        #expect(angles.min().map { $0 < -20 && $0 > -60 } == true, "still a clear swing, just less: \(angles)")
        let orbit = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/thing","property":"rotation","pivot":{"x":3,"y":11},"keys":[{"seconds":0,"value":0},{"seconds":1,"value":360}]}"#))
        #expect(AskMotion.fitted([drawing, orbit]).last == orbit)
    }

    @Test("A part that only pokes past the room is brought back inside rather than thrown away")
    func pokesBackIn() throws {
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><circle id="ball" cx="12" cy="12" r="9"/><path id="spark" d="M12 2 L12 4"/></svg>"##
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(svg)])
        // The ball grows to fill all the room there is; the spark rises a little past it.
        let grow = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/ball","property":"scale","keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":160},{"seconds":1,"value":100}]}"#))
        let rise = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/spark","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":-7}},{"seconds":1,"value":{"x":0,"y":0}}]}"#))
        let (view, at) = try Self.boxes([drawing, grow, rise], part: "spark")
        let room = view.insetBy(dx: -AskMotionCheck.edgeSlack, dy: -AskMotionCheck.edgeSlack)
        #expect(at.allSatisfy { room.contains($0) })
        #expect(at.contains { $0.minY < 1 }, "it still rises most of the way")
    }

    // MARK: A line drawing itself

    @Test("A line drawing itself is keyed at its end: a key on its start is sent back while the model can mend it")
    func drawsFromItsEnd() throws {
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><path id="wave" d="M4 12 C8 8 16 8 20 12"/></svg>"##
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(svg)])
        let start = try Self.args(#"{"layer":"$1/wave","property":"trimStart","keys":[{"seconds":0,"value":0},{"seconds":1,"value":100}]}"#)
        let end = try Self.args(#"{"layer":"$1/wave","property":"trimEnd","keys":[{"seconds":0,"value":0},{"seconds":0.5,"value":100}]}"#)
        #expect(AskMotion.refusal(start, steps: [drawing])?.contains("trimEnd") == true)
        #expect(AskMotion.refusal(end, steps: [drawing]) == nil)
    }

    // MARK: Coming out of something

    @Test("What travels out from inside a closed outline drawn after it starts hidden: that outline is filled white, nothing else is")
    func hiddenInside() throws {
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><rect id="sheet" x="7" y="10" width="10" height="6"/><path id="body" d="M3 6 L21 6 L21 18 L3 18 Z"/><path id="cover" d="M3 6 L12 13 L21 6 Z"/></svg>"##
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(svg)])
        let rise = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/sheet","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":1,"value":{"x":0,"y":-6}},{"seconds":2,"value":{"x":0,"y":0}}]}"#))
        let made = AskMotion.hidden([drawing, rise])
        let art = try SVGArtwork.parse(try #require(made.first?.arguments["svg"]?.stringValue), keepingGroups: true).get()
        func fill(_ name: String) -> String? { art.parts.first { AskMotion.plain($0.name ?? "") == name }?.fill }
        #expect(fill("body") == "#FFFFFF")
        #expect(fill("cover") == nil)
        #expect(fill("sheet") == nil)
        #expect(made.dropFirst() == [rise])
        // Still, or drawn in front of the outline, it was meant to be seen.
        #expect(AskMotion.hidden([drawing]) == [drawing])
        let inFront = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><path id="body" d="M3 6 L21 6 L21 18 L3 18 Z"/><rect id="sheet" x="7" y="10" width="10" height="6"/></svg>"##
        let shown = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(inFront)])
        #expect(AskMotion.hidden([shown, rise]) == [shown, rise])
    }

    @Test("The rules teach a fold, a part that leaves and a line drawn on, in words true of anything")
    func taught() {
        let rules = AskMotion.drawRules
        #expect(rules.contains("rotationX"))
        #expect(rules.contains("trimEnd 0"))
        #expect(rules.contains("leaves"))
    }
}
