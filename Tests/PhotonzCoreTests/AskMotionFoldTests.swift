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

    // MARK: A fold lands

    static func foldKeys(_ json: String, property: String = "rotationX") throws -> AskStep {
        AskStep(tool: "set_keys", arguments: try args(#"{"layer":"$1/flap","property":""# + property + #"","pivot":{"x":12,"y":6},"keys":"# + json + "}"))
    }

    static func keys(_ step: AskStep) -> [(seconds: Double, value: Double, curve: String?)] {
        AskMotionCheck.timed(step).map { ($0.seconds, $0.value.doubleValue ?? .nan, $0.curve) }
    }

    @Test("A fold closing onto its rest lands on it: a bounce past rest, which a flat file cannot show, goes, and the close slows as it lands")
    func foldLands() throws {
        // The envelope Ask made on 2026-11-08: shut in 200 ms on Ease in, then
        // 8 degrees past flat. The file showed it at full speed into the V,
        // a shallow V one frame and the whole one the next.
        let made = try Self.foldKeys(#"[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease in","seconds":0.2,"value":0},{"curve":"Ease out back","seconds":0.3,"value":8},{"curve":"Hold","seconds":0.5,"value":180},{"curve":"Ease in","seconds":1.6,"value":180},{"curve":"Ease out back","seconds":1.8,"value":-8},{"curve":"Hold","seconds":2,"value":0},{"seconds":2.4,"value":0}]"#)
        let landed = Self.keys(try #require(AskMotion.foldsLand([made]).first))
        #expect(landed.map(\.seconds) == [0, 0.2, 0.3, 0.5, 1.6, 2, 2.4])
        #expect(landed.map(\.value) == [0, 0, 8, 180, 180, 0, 0])
        #expect(landed[4].curve == "Ease in out")
        // The opening is not a landing and is left as made.
        #expect(landed[2].curve == "Ease out back")
    }

    @Test("A fold that shuts too quickly to see takes its time from the stillness after it")
    func foldLandsSlowly() throws {
        let quick = try Self.foldKeys(#"[{"seconds":0,"value":0},{"curve":"Ease in out","seconds":0.4,"value":180},{"curve":"Linear","seconds":1,"value":180},{"seconds":1.15,"value":0},{"seconds":2,"value":0}]"#)
        let landed = Self.keys(try #require(AskMotion.foldsLand([quick]).first))
        #expect(landed.map(\.seconds) == [0, 0.4, 1, 1.4, 2])
        #expect(landed[2].curve == "Ease in out")
        // With little stillness after it, it takes what there is and the key
        // that stood there goes, its value being the same rest.
        let tight = try Self.foldKeys(#"[{"seconds":0,"value":0},{"seconds":0.4,"value":-180},{"curve":"Ease in","seconds":1,"value":-180},{"seconds":1.15,"value":0},{"seconds":1.3,"value":0},{"curve":"Ease in","seconds":1.5,"value":90},{"seconds":2,"value":0}]"#, property: "rotationY")
        let held = Self.keys(try #require(AskMotion.foldsLand([tight]).first))
        #expect(held.map(\.seconds) == [0, 0.4, 1, 1.3, 1.5, 2])
        #expect(held.map(\.value) == [0, -180, -180, 0, 90, 0])
    }

    @Test("What already lands is left alone: a slow close, a flat turn, a fold that never comes home")
    func foldLandingLeftAlone() throws {
        let slow = try Self.foldKeys(#"[{"seconds":0,"value":0},{"seconds":0.5,"value":180},{"curve":"Ease out","seconds":1.2,"value":180},{"seconds":1.6,"value":0},{"seconds":2,"value":0}]"#)
        #expect(AskMotion.foldsLand([slow]) == [slow])
        let swing = try Self.foldKeys(#"[{"seconds":0,"value":0},{"seconds":0.5,"value":120},{"curve":"Ease in","seconds":1,"value":120},{"seconds":1.1,"value":-8},{"seconds":1.3,"value":0},{"seconds":2,"value":0}]"#, property: "rotation")
        #expect(AskMotion.foldsLand([swing]) == [swing])
        let small = try Self.foldKeys(#"[{"seconds":0,"value":0},{"curve":"Ease in","seconds":0.5,"value":40},{"seconds":0.6,"value":0},{"seconds":2,"value":0}]"#)
        #expect(AskMotion.foldsLand([small]) == [small])
    }

    @Test("Planning lands a fold: fitted carries it")
    func fittedLandsFolds() throws {
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><path id="body" d="M5 7 L19 7 L19 17 L5 17 Z"/><path id="flap" d="M5 7 L12 13 L19 7"/></svg>"##
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(svg)])
        let made = try Self.foldKeys(#"[{"seconds":0,"value":0},{"curve":"Ease in out","seconds":0.4,"value":180},{"curve":"Ease in","seconds":1,"value":180},{"curve":"Ease out back","seconds":1.2,"value":-8},{"seconds":1.4,"value":0},{"seconds":2,"value":0}]"#)
        let landed = Self.keys(try #require(AskMotion.fitted([drawing, made]).last))
        #expect(!landed.contains { $0.value < 0 })
        #expect(landed.first { $0.seconds == 1 }?.curve == "Ease in out")
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

    // MARK: Marks go with what leaves

    static let flyer = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><g id="craft"><path d="M4 12 L18 6 L12 18 Z"/></g><g id="lines"><path d="M1 15 L4 15"/><path d="M2 18 L5 18"/></g><path id="ground" d="M2 21 L22 21"/></svg>"##

    @Test("A mark that shows only while a part moves is gone by the time that part has left the frame, never left on its own")
    func marksGoWithWhatLeaves() throws {
        // The paper plane Ask made on 2026-11-08: its speed lines faded in as
        // it set off and hung on for half a second after it had gone.
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(Self.flyer)])
        let fly = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/craft","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.4,"value":{"x":0,"y":0}},{"curve":"Ease in","seconds":0.9,"value":{"x":24,"y":-20}},{"curve":"Hold","seconds":1.9,"value":{"x":24,"y":-20}},{"seconds":1.95,"value":{"x":-24,"y":20}},{"seconds":2.4,"value":{"x":0,"y":0}}]}"#))
        let lines = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/lines","property":"opacity","keys":[{"seconds":0,"value":0},{"seconds":0.4,"value":0},{"seconds":0.6,"value":100},{"seconds":1.1,"value":100},{"seconds":1.3,"value":0},{"seconds":2.4,"value":0}]}"#))
        let made = AskMotion.marksGo([drawing, fly, lines], view: CGRect(x: 0, y: 0, width: 24, height: 24))
        let faded = AskMotionCheck.timed(try #require(made.last))
        // Gone (back to 0) by the time two thirds of the part is out of the
        // frame, straight between its keys about 0.64 s; seen as it sets off.
        let gone = try #require(faded.first { $0.seconds > 0.45 && $0.value.doubleValue == 0 })
        #expect(gone.seconds <= 0.66)
        #expect(faded.contains { $0.seconds > 0.4 && $0.seconds < 0.6 && $0.value.doubleValue == 100 })
        #expect(faded.first?.seconds == 0 && faded.last?.seconds == 2.4)
        #expect(made.dropLast() == [drawing, fly])
        // Marks that drift on their own, slower than the part, still go: the
        // plane's lines drifted after it across an empty frame (2026-11-09).
        let drift = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/lines","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.4,"value":{"x":0,"y":0}},{"seconds":0.9,"value":{"x":12,"y":-9}},{"seconds":2.4,"value":{"x":0,"y":0}}]}"#))
        let drifted = AskMotion.marksGo([drawing, fly, drift, lines], view: CGRect(x: 0, y: 0, width: 24, height: 24))
        let fades = AskMotionCheck.timed(try #require(drifted.last))
        #expect(try #require(fades.first { $0.seconds > 0.45 && $0.value.doubleValue == 0 }).seconds <= 0.66)
    }

    @Test("What is there at rest, what never leaves, and what goes with the part are left alone")
    func marksLeftAlone() throws {
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(Self.flyer)])
        let fly = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/craft","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.9,"value":{"x":24,"y":-20}},{"seconds":2.4,"value":{"x":24,"y":-20}}]}"#))
        // Seen at the top of the lap: it is part of the picture, not a mark.
        let ground = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/ground","property":"opacity","keys":[{"seconds":0,"value":100},{"seconds":1.3,"value":0},{"seconds":2.4,"value":100}]}"#))
        let view = CGRect(x: 0, y: 0, width: 24, height: 24)
        #expect(AskMotion.marksGo([drawing, fly, ground], view: view) == [drawing, fly, ground])
        // A part that only nudges never leaves, so nothing is due to go.
        let nudge = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/craft","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.9,"value":{"x":2,"y":-2}},{"seconds":2.4,"value":{"x":0,"y":0}}]}"#))
        let lines = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/lines","property":"opacity","keys":[{"seconds":0,"value":0},{"seconds":0.6,"value":100},{"seconds":1.3,"value":0},{"seconds":2.4,"value":0}]}"#))
        #expect(AskMotion.marksGo([drawing, nudge, lines], view: view) == [drawing, nudge, lines])
        // Marks that go out of the frame themselves are not left behind.
        let linesFly = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/lines","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.8,"value":{"x":30,"y":-30}},{"seconds":2.4,"value":{"x":30,"y":-30}}]}"#))
        #expect(AskMotion.marksGo([drawing, fly, lines, linesFly], view: view) == [drawing, fly, lines, linesFly])
    }

    @Test("A drawing that has wholly left comes back soon and rests at home, rather than leaving the frame empty")
    func comesBackSoon() throws {
        // The paper plane of 2026-11-09 after `leaving`: out by 0.9 s, waiting
        // off the frame until 1.94 s, so a third of the lap was empty.
        let alone = Self.flyer.replacingOccurrences(of: #"<path id="ground" d="M2 21 L22 21"/>"#, with: "")
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(alone)])
        let fly = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/craft","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.2,"value":{"x":0,"y":0}},{"curve":"Ease in","seconds":0.35,"value":{"x":0,"y":0.9}},{"seconds":0.9,"value":{"x":22.4,"y":-16}},{"curve":"Hold","seconds":1.3,"value":{"x":24,"y":-20.3}},{"curve":"Hold","seconds":1.9,"value":{"x":24,"y":-20.3}},{"curve":"Ease out","seconds":1.94,"value":{"x":-24,"y":20.3}},{"seconds":2.4,"value":{"x":0,"y":0}}]}"#))
        let lines = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/lines","property":"opacity","keys":[{"seconds":0,"value":0},{"seconds":0.4,"value":0},{"seconds":0.6,"value":100},{"seconds":0.8,"value":0},{"seconds":2.4,"value":0}]}"#))
        let view = CGRect(x: 0, y: 0, width: 24, height: 24)
        let back = AskMotionCheck.timed(try #require(AskMotion.comesBack([drawing, fly, lines], view: view)[1]))
        #expect(back.map(\.seconds) == [0, 0.2, 0.35, 0.9, 1.05, 1.51, 2.4])
        #expect(back[3].curve == "Hold")
        #expect(back[4].value["x"]?.doubleValue == -24 && back[4].curve == "Ease out")
        #expect(back[5].value["x"]?.doubleValue == 0 && back[6].value["x"]?.doubleValue == 0)
        // With something left in the frame it is not empty: left alone.
        let grounded = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(Self.flyer)])
        #expect(AskMotion.comesBack([grounded, fly, lines], view: view) == [grounded, fly, lines])
        // Gone only briefly: left alone.
        let brief = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/craft","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"curve":"Hold","seconds":0.9,"value":{"x":24,"y":-20.3}},{"curve":"Ease out","seconds":1.1,"value":{"x":-24,"y":20.3}},{"seconds":1.6,"value":{"x":0,"y":0}},{"seconds":2.4,"value":{"x":0,"y":0}}]}"#))
        #expect(AskMotion.comesBack([drawing, brief, lines], view: view) == [drawing, brief, lines])
    }

    @Test("Ink that reaches the frame's edge at rest gets the icon's one unit of margin; a drawing on the usual live area keeps its frame")
    func inkOffTheEdge() throws {
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(Self.flyer)])
        let lines = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/lines","property":"opacity","keys":[{"seconds":0,"value":0},{"seconds":0.6,"value":100},{"seconds":1.3,"value":0},{"seconds":2.4,"value":0}]}"#))
        let svg = try #require(AskMotion.fitted([drawing, lines]).first?.arguments["svg"]?.stringValue)
        #expect(svg.contains(#"viewBox="-1.000 -1.000 26.000 26.000""#))
        let roomy = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(Self.flyer.replacingOccurrences(of: "M1 15", with: "M2 15"))])
        #expect(AskMotion.fitted([roomy, lines]).first == roomy)
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
