import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// An agent keys a layer with the keys a person sets on the timeline
/// (task `an-agent-can-set-read-and-change-a-layer-s-keys`).
@Suite("Agent keys")
struct AgentKeysTests {

    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }

    /// A picture with one box on it, and no time of any kind.
    static func picture() -> (document: PhotonzDocument, id: UUID) {
        let box = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FF0000")),
                        frame: CGRect(x: 10, y: 20, width: 40, height: 30))
        return (PhotonzDocument(canvasSize: CGSize(width: 200, height: 200), layers: [box]), box.id)
    }

    static func keys(_ layer: UUID, _ property: MotionProperty, _ moments: [(Int, MotionValue, EasingCurve?)],
                     replace: Bool = false) -> AgentSetKeys {
        AgentSetKeys(layer: layer.uuidString, property: property,
                     keys: moments.map { AgentKey(atMS: $0.0, value: $0.1, curve: $0.2) }, replace: replace)
    }

    static func request(_ tool: String, _ json: String) throws -> Result<AgentRequest, AgentToolError> {
        AgentTools.request(tool: tool, arguments: try args(json))
    }

    // MARK: The calls

    @Test("set_keys is checked and arrives in milliseconds, with each kind of value")
    func setKeysCall() throws {
        let id = UUID().uuidString
        let request = try Self.request("set_keys", """
            {"layer": "\(id)", "property": "rotation", "keys": [
              {"seconds": 0, "value": 0, "curve": "Linear"}, {"seconds": 1.5, "value": 360}]}
            """).get()
        #expect(request == .setKeys(document: nil, call: AgentSetKeys(
            layer: id, property: .rotation,
            keys: [AgentKey(atMS: 0, value: .number(0), curve: .linear), AgentKey(atMS: 1500, value: .number(360))])))
        guard case .setKeys(_, let moved) = try Self.request("set_keys", """
            {"layer": "\(id)", "property": "position", "keys": [{"seconds": 0, "value": {"x": 1, "y": 2}}]}
            """).get() else { Issue.record("not set_keys"); return }
        #expect(moved.keys.first?.value == .point(CGPoint(x: 1, y: 2)))
        guard case .setKeys(_, let painted) = try Self.request("set_keys", """
            {"layer": "\(id)", "property": "color", "keys": [{"seconds": 0, "value": "#00ff00"}]}
            """).get() else { Issue.record("not set_keys"); return }
        #expect(painted.keys.first?.value == .color("#00FF00"))
    }

    @Test("set_keys turns down what it cannot mean, in words a model can act on")
    func setKeysRefusals() throws {
        let id = UUID().uuidString
        for bad in [
            #"{"layer": "\#(id)", "property": "wobble", "keys": [{"seconds": 0, "value": 1}]}"#,
            #"{"layer": "\#(id)", "property": "opacity", "keys": []}"#,
            #"{"layer": "\#(id)", "property": "opacity", "keys": [{"seconds": -1, "value": 1}]}"#,
            #"{"layer": "\#(id)", "property": "opacity", "keys": [{"seconds": 0, "value": 1, "curve": "wiggly"}]}"#,
            #"{"layer": "\#(id)", "property": "opacity", "keys": [{"seconds": 0, "value": "red"}]}"#,
            #"{"layer": "\#(id)", "property": "opacity", "keys": [{"seconds": 1, "value": 1}, {"seconds": 1.001, "value": 2}]}"#,
            #"{"layer": "\#(id)", "property": "opacity", "keys": [{"seconds": 0, "value": 1}], "pivot": "artboard"}"#,
        ] {
            guard case .failure(let error) = try Self.request("set_keys", bad) else {
                Issue.record("accepted \(bad)"); continue
            }
            #expect(!error.isUnknownTool)
            #expect(error.message.hasPrefix("set_keys") || error.message.contains("keys") || error.message.contains("property"))
        }
    }

    @Test("A curve reads back in the words it is set with, so a read can be handed straight back")
    func curveWords() {
        for curve in EasingCurve.named + [.steps(1), .custom(x1: 0.1, y1: 0.2, x2: 0.3, y2: 0.9)] {
            #expect(AgentKeyCurve.curve(named: AgentKeyCurve.word(curve)) == curve, "\(curve)")
        }
        #expect(AgentKeyCurve.curve(named: "hold") == .steps(1))
        #expect(AgentKeyCurve.curve(named: "ease in out") == .easeInOut)
        #expect(AgentKeyCurve.curve(named: "bouncy") == nil)
    }

    @Test("set_timing and remove_keys are checked too")
    func otherCalls() throws {
        #expect(try Self.request("set_timing", #"{"seconds": 1.2, "loop": false}"#).get()
                == .setTiming(document: nil, timing: AgentTiming(lengthMS: 1200, repeats: false)))
        guard case .failure = try Self.request("set_timing", "{}") else {
            Issue.record("a timing that says nothing was accepted"); return
        }
        let id = UUID().uuidString
        #expect(try Self.request("remove_keys", #"{"layer": "\#(id)", "property": "scale", "seconds": 2}"#).get()
                == .removeKeys(document: nil, call: AgentRemoveKeys(layer: id, property: .scale, atMS: 2000)))
    }

    // MARK: Keying a picture

    @Test("Keys on a still picture give it a lap and stay a picture, and the timeline sees them")
    func keysAPicture() throws {
        var (document, id) = Self.picture()
        #expect(!document.isKeyedPicture)
        let made = try document.agentSetKeys(Self.keys(id, .rotation, [(0, .number(0), nil), (1000, .number(90), nil)])).get()
        #expect(document.isKeyedPicture)
        #expect(!document.hasTime)
        #expect(made.keys == 2)
        #expect(made.lapSeconds == 2)
        #expect(document.keyLap?.repeats == true)
        #expect(document.clipKeyMarks(layerID: id).map(\.documentMS) == [0, 1000])
        #expect(document.keyCount(layerID: id, .motion(.rotation)) == 2)
        #expect(document.keyedValue(layerID: id, .motion(.rotation), atDocumentTimeMS: 1000) == .number(90))
    }

    @Test("A person's edit lands on a key a tool set")
    func aPersonCanChangeIt() throws {
        var (document, id) = Self.picture()
        _ = try document.agentSetKeys(Self.keys(id, .opacity, [(0, .number(0), nil), (1000, .number(100), nil)])).get()
        let landed = document.setKeyedValue(.number(40), layerID: id, .motion(.opacity), atDocumentTimeMS: 1000)
        #expect(landed)
        #expect(document.keyCount(layerID: id, .motion(.opacity)) == 2)
        #expect(document.keyedValue(layerID: id, .motion(.opacity), atDocumentTimeMS: 1000) == .number(40))
    }

    @Test("Setting keys again adds and rewrites; replace starts over and keeps the pivot")
    func changingKeys() throws {
        var (document, id) = Self.picture()
        var call = Self.keys(id, .rotation, [(0, .number(0), nil), (1000, .number(90), nil)])
        call.pivot = .unit(CGPoint(x: 0.5, y: 0))
        _ = try document.agentSetKeys(call).get()
        _ = try document.agentSetKeys(Self.keys(id, .rotation, [(1000, .number(45), nil), (1500, .number(10), nil)])).get()
        #expect(document.keyCount(layerID: id, .motion(.rotation)) == 3)
        #expect(document.keyedValue(layerID: id, .motion(.rotation), atDocumentTimeMS: 1000) == .number(45))
        _ = try document.agentSetKeys(Self.keys(id, .rotation, [(200, .number(1), nil), (400, .number(2), nil)], replace: true)).get()
        #expect(document.keyCount(layerID: id, .motion(.rotation)) == 2)
        let motion = try #require(document.layer(id: id)?.keyedMotion(.rotation))
        #expect(motion.keyframes.map(\.atMS) == [200, 400])
        #expect(motion.pivot?.unit == CGPoint(x: 0.5, y: 0))
    }

    @Test("A curve belongs to the run leaving its key, and only that run")
    func curves() throws {
        var (document, id) = Self.picture()
        _ = try document.agentSetKeys(Self.keys(id, .scale, [
            (0, .number(100), .easeOutBack), (500, .number(150), .steps(1)), (1000, .number(100), nil),
        ])).get()
        let motion = try #require(document.layer(id: id)?.keyedMotion(.scale))
        #expect(motion.stretchCurve(0) == .easeOutBack)
        #expect(motion.stretchCurve(1) == .steps(1))
        // A hold stays where its key put it until the next one.
        #expect(document.keyedValue(layerID: id, .motion(.scale), atDocumentTimeMS: 900) == .number(150))
    }

    @Test("Layers inside a frame key the same way, and are seen on their lap")
    func insideAFrame() throws {
        let inner = Layer(name: "Part", content: .annotation(AnnotationContent(shape: .ellipse, colorHex: "#000000")),
                          frame: CGRect(x: 1, y: 1, width: 4, height: 4))
        let frame = Layer(name: "Icon", content: .group(GroupContent(children: [inner], isFrame: true)),
                          frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        var document = PhotonzDocument(canvasSize: CGSize(width: 24, height: 24), layers: [frame])
        var call = Self.keys(inner.id, .rotation, [(0, .number(0), .linear), (1000, .number(360), nil)])
        call.pivot = .artboard
        _ = try document.agentSetKeys(call).get()
        #expect(document.isKeyedPicture)
        let motion = try #require(document.layer(id: inner.id)?.keyedMotion(.rotation))
        #expect(motion.pivot?.isOnArtboard == true)
    }

    @Test("A key past the lap grows the lap, and says so")
    func growsTheLap() throws {
        var (document, id) = Self.picture()
        let made = try document.agentSetKeys(Self.keys(id, .opacity, [(0, .number(0), nil), (3000, .number(100), nil)])).get()
        #expect(made.lapSeconds == 3)
        #expect(document.motionCycleLengthMS == 3000)
    }

    @Test("Refused: no such layer, a locked one, a value of the wrong kind, a value it does not have")
    func refusals() throws {
        var (document, id) = Self.picture()
        let before = document
        func refuses(_ call: AgentSetKeys, _ words: String) {
            guard case .failure(let error) = document.agentSetKeys(call) else {
                Issue.record("accepted: \(words)"); return
            }
            #expect(error.message.contains(words), "\(error.message)")
        }
        refuses(AgentSetKeys(layer: "nope", property: .opacity, keys: [AgentKey(atMS: 0, value: .number(1))]), "no layer")
        refuses(Self.keys(id, .position, [(0, .number(1), nil)]), "x and y")
        refuses(Self.keys(id, .color, [(0, .number(1), nil)]), "#RRGGBB")
        refuses(Self.keys(id, .rotation, [(0, .color("#000000"), nil)]), "a number")
        refuses(Self.keys(id, .opacity, [(0, .number(140), nil)]), "0 to 100")
        refuses(Self.keys(id, .textSize, [(0, .number(10), nil)]), "cannot key")
        #expect(document == before, "a refused call changes nothing")
        document.updateLayer(id: id) { $0.isLocked = true }
        refuses(Self.keys(id, .opacity, [(0, .number(1), nil)]), "locked")
    }

    // MARK: Keying a video

    @Test("On a video a key's seconds are the video's, however late the title starts, and read back the same")
    func keysAVideo() throws {
        var title = Layer(name: "Title", content: .text(TextContent(string: "Hi")),
                          frame: CGRect(x: 10, y: 10, width: 100, height: 40))
        title.time = LayerTime(inMS: 2000, outMS: 8000)
        var document = PhotonzDocument(canvasSize: CGSize(width: 640, height: 360), layers: [title])
        document.durationMS = 10_000
        let id = title.id
        let made = try document.agentSetKeys(Self.keys(id, .opacity, [(3000, .number(0), nil), (5000, .number(100), nil)])).get()
        #expect(made.lapSeconds == nil, "a video has no lap")
        #expect(document.keyLap == nil)
        #expect(document.clipKeyMarks(layerID: id).map(\.documentMS) == [3000, 5000])
        #expect(document.keyedValue(layerID: id, .motion(.opacity), atDocumentTimeMS: 5000) == .number(100))
        let context = AgentDocumentRead.Context(id: "d1", title: "T", file: nil, playheadMS: 0, canUndo: true, canRedo: false)
        let read = AgentDocumentRead.make(document, context: context)
        #expect(read.layers.first?.keyed?.first?.keys.map(\.seconds) == [3, 5])
        #expect(read.lap == nil)
        guard case .failure(let outside) = document.agentSetKeys(Self.keys(id, .opacity, [(9000, .number(0), nil)])) else {
            Issue.record("a key after the title ends was accepted"); return
        }
        #expect(outside.message.contains("plays from 2"))
        guard case .failure(let timing) = document.agentSetTiming(AgentTiming(lengthMS: 1000)) else {
            Issue.record("a video took a lap"); return
        }
        #expect(timing.message.contains("video"))
    }

    // MARK: Taking keys away

    @Test("remove_keys takes one key, a value's keys, or the whole layer's, and the last goes back to a still")
    func removing() throws {
        var (document, id) = Self.picture()
        _ = try document.agentSetKeys(Self.keys(id, .rotation, [(0, .number(0), nil), (1000, .number(90), nil)])).get()
        _ = try document.agentSetKeys(Self.keys(id, .opacity, [(0, .number(100), nil), (1000, .number(0), nil)])).get()
        var said = try document.agentRemoveKeys(AgentRemoveKeys(layer: id.uuidString, property: .rotation, atMS: 1000)).get()
        #expect(said.removed == 1)
        #expect(document.keyCount(layerID: id, .motion(.rotation)) == 1)
        said = try document.agentRemoveKeys(AgentRemoveKeys(layer: id.uuidString, property: .rotation)).get()
        #expect(said.removed == 1)
        #expect(document.keyCount(layerID: id, .motion(.rotation)) == 0)
        #expect(document.isKeyedPicture)
        guard case .failure(let error) = document.agentRemoveKeys(
            AgentRemoveKeys(layer: id.uuidString, property: .opacity, atMS: 400)) else {
            Issue.record("a key that is not there was removed"); return
        }
        #expect(error.message.contains("no key"))
        said = try document.agentRemoveKeys(AgentRemoveKeys(layer: id.uuidString)).get()
        #expect(said.removed == 2)
        #expect(!document.isKeyedPicture)
    }

    // MARK: The lap

    @Test("set_timing sets a picture's length and loop before or after its keys")
    func timing() throws {
        var (document, id) = Self.picture()
        var said = try document.agentSetTiming(AgentTiming(lengthMS: 1200, repeats: false)).get()
        #expect(said.lapSeconds == 1.2)
        #expect(said.loop == false)
        #expect(!document.hasTime, "a timed picture is still a picture")
        _ = try document.agentSetKeys(Self.keys(id, .opacity, [(0, .number(0), nil), (1000, .number(100), nil)])).get()
        #expect(document.isKeyedPicture)
        #expect(document.motionCycleLengthMS == 1200, "the first key keeps the length that was asked for")
        #expect(document.keyLap?.repeats == false)
        said = try document.agentSetTiming(AgentTiming(repeats: true)).get()
        #expect(said.lapSeconds == 1.2)
        #expect(said.loop == true)
    }

    @Test("A lap can end on its last key and no sooner")
    func lapStopsAtTheLastKey() throws {
        var (document, id) = Self.picture()
        _ = try document.agentSetKeys(Self.keys(id, .opacity, [(0, .number(0), nil), (1000, .number(100), nil)])).get()
        let ended = try document.agentSetTiming(AgentTiming(lengthMS: 1000)).get()
        #expect(ended.lapSeconds == 1)
        guard case .failure(let error) = document.agentSetTiming(AgentTiming(lengthMS: 999)) else {
            Issue.record("a lap shorter than its keys was accepted"); return
        }
        #expect(error.message.contains("1"))
    }

    // MARK: Reading

    @Test("read_document shows keys, curves, the pivot and the lap, in the words set_keys takes")
    func reading() throws {
        var (document, id) = Self.picture()
        var call = Self.keys(id, .rotation, [(0, .number(0), .linear), (1000, .number(90), nil)])
        call.pivot = .unit(CGPoint(x: 0.5, y: 0))
        _ = try document.agentSetKeys(call).get()
        _ = try document.agentSetKeys(Self.keys(id, .position, [(500, .point(CGPoint(x: 1, y: 2)), nil)])).get()
        _ = try document.agentSetKeys(Self.keys(id, .color, [(500, .color("#00FF00"), nil)])).get()
        let context = AgentDocumentRead.Context(id: "d1", title: "T", file: nil, playheadMS: 250, canUndo: true, canRedo: false)
        let read = AgentDocumentRead.make(document, context: context)
        #expect(read.kind == "picture")
        #expect(read.lap == AgentDocumentRead.Lap(seconds: 2, loop: true))
        #expect(read.playheadSeconds == 0.25)
        let keyed = try #require(read.layers.first?.keyed)
        let turn = try #require(keyed.first { $0.property == "rotation" })
        #expect(turn.keys.map(\.seconds) == [0, 1])
        #expect(turn.keys.map(\.value) == [.number(0), .number(90)])
        #expect(turn.keys.first?.curve == "Linear")
        #expect(turn.keys.last?.curve == nil, "the last key has no run leaving it")
        #expect(turn.pivot == AgentDocumentRead.Pivot(x: 0.5, y: 0))
        #expect(keyed.first { $0.property == "position" }?.keys.first?.value == .point(x: 1, y: 2))
        #expect(keyed.first { $0.property == "color" }?.keys.first?.value == .color("#00FF00"))
        let text = String(decoding: try read.encoded(), as: UTF8.self)
        let back = try AgentJSON.parse(Data(text.utf8))
        #expect(back["lap"]?["seconds"]?.doubleValue == 2)
        #expect(back["layers"]?.arrayValue?.first?["keyed"] != nil)
    }

    @Test("A picture with no keys reads exactly as it did")
    func stillReadsTheSame() throws {
        let (document, _) = Self.picture()
        let context = AgentDocumentRead.Context(id: "d1", title: "T", file: nil, playheadMS: 0, canUndo: false, canRedo: false)
        let text = String(decoding: try AgentDocumentRead.make(document, context: context).encoded(), as: UTF8.self)
        #expect(!text.contains("keyed") && !text.contains("lap") && !text.contains("playhead"))
    }

    // MARK: The file plays what the timeline plays

    /// Where the file's list of moments has a value at `ms`, reading its
    /// splines the way a browser does.
    static func fileValue(_ stops: [MotionSVG.Stop], atMS ms: Double) -> Double? {
        guard let after = stops.firstIndex(where: { $0.ms > ms }), after > 0 else {
            guard case .number(let last)? = stops.last?.value else { return nil }
            return last
        }
        let left = stops[after - 1], right = stops[after]
        guard case .number(let a) = left.value, case .number(let b) = right.value else { return nil }
        let t = (ms - left.ms) / (right.ms - left.ms)
        let s = left.spline
        return a + (b - a) * CubicBezier.value(t, s.x1, s.y1, s.x2, s.y2)
    }

    @Test("A key's curve reaches the file: it plays what the timeline plays", arguments: [
        EasingCurve.linear, .easeIn, .easeOut, .easeInOut, .easeOutBack, .steps(1),
    ])
    func fileMatchesTimeline(curve: EasingCurve) throws {
        var (document, id) = Self.picture()
        _ = try document.agentSetKeys(Self.keys(id, .rotation, [(0, .number(0), curve), (1000, .number(100), nil)])).get()
        _ = try document.agentSetTiming(AgentTiming(lengthMS: 1000)).get()
        let lapping = document.lappingKeys
        let motion = try #require(lapping.layer(id: id)?.keyedMotion(.rotation))
        let stops = MotionSVG.stops(for: motion, cycleMS: 1000)
        for ms in stride(from: 100, to: 1000, by: 100) {
            guard case .number(let timeline) = motion.value(atMS: ms, cycleMS: 1000) else {
                Issue.record("no value at \(ms)"); continue
            }
            let file = try #require(Self.fileValue(stops, atMS: Double(ms)))
            #expect(abs(file - timeline) < 3, "at \(ms) ms the timeline says \(timeline), the file \(file)")
        }
    }

    @Test("Three keys on different curves reach the file stretch by stretch, and a hold stays held")
    func fileMatchesTimelineAcrossKeys() throws {
        var (document, id) = Self.picture()
        _ = try document.agentSetKeys(Self.keys(id, .rotation, [
            (100, .number(0), .steps(1)), (400, .number(100), .linear), (700, .number(40), .easeOutBack), (900, .number(90), nil),
        ])).get()
        _ = try document.agentSetTiming(AgentTiming(lengthMS: 1000)).get()
        let motion = try #require(document.lappingKeys.layer(id: id)?.keyedMotion(.rotation))
        let stops = MotionSVG.stops(for: motion, cycleMS: 1000)
        for ms in stride(from: 20, to: 1000, by: 20) {
            guard case .number(let timeline) = motion.value(atMS: ms, cycleMS: 1000) else { continue }
            let file = try #require(Self.fileValue(stops, atMS: Double(ms)))
            #expect(abs(file - timeline) < 3, "at \(ms) ms the timeline says \(timeline), the file \(file)")
        }
    }

    @Test("A keyed icon writes itself as a loop, and as one play when it does not repeat")
    func exportsTheLoop() throws {
        var (document, id) = Self.picture()
        _ = try document.agentSetKeys(Self.keys(id, .rotation, [(0, .number(0), .linear), (1000, .number(360), nil)])).get()
        _ = try document.agentSetTiming(AgentTiming(lengthMS: 1000)).get()
        let moving = SVGExport.Animation.moving(cycleMS: document.motionCycleLengthMS)
        let looped = SVGExport.write(document, animation: moving).text
        #expect(looped.contains("animateTransform"))
        #expect(looped.contains(#"repeatCount="indefinite""#))
        _ = try document.agentSetTiming(AgentTiming(repeats: false)).get()
        let once = SVGExport.write(document, animation: moving).text
        #expect(once.contains(#"fill="freeze""#))
        #expect(!once.contains(#"repeatCount="indefinite""#))
    }

    // MARK: Who is offered them

    static func toolNames(_ talk: AskConversation) -> [String] {
        (talk.chatBody(model: "m")["tools"]?.arrayValue ?? []).compactMap { $0["function"]?["name"]?.stringValue }
    }

    static let plainRead = #"{"kind":"picture","canvas":{"width":100,"height":100},"layers":[]}"#
    static let keyedRead = #"{"kind":"picture","canvas":{"width":100,"height":100},"lap":{"seconds":2,"loop":true},"layers":[]}"#

    @Test("Every tool is over MCP; Ask is shown them for a request about motion or a document that has it")
    func offered() {
        let names = AgentTools.all.map(\.name)
        for tool in AskTools.keyDoing {
            #expect(names.contains(tool))
            #expect(AskTools.modelTool(tool) != nil)
        }
        #expect(Set(AskTools.keyDoing) == ["set_keys", "remove_keys", "change_keys", "set_timing"])
        for request in ["animate the logo", "make an animated icon", "add a keyframe here", "Animation please"] {
            #expect(Self.toolNames(AskConversation(request: request, documentRead: Self.plainRead)).contains("set_keys"), "\(request)")
        }
        let tweak = AskConversation(request: "slower", documentRead: Self.keyedRead)
        #expect(Self.toolNames(tweak).contains("set_keys"))
        #expect(tweak.doingTools.contains("set_timing"))
        let plain = AskConversation(request: "make the box red", documentRead: Self.plainRead)
        #expect(!Self.toolNames(plain).contains("set_keys"), "every other request is shown what it always was")
        #expect(!plain.doingTools.contains("set_keys"))
    }

    @Test("The skill's reference lists every tool the channel offers")
    func skillListsThem() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let skill = try String(contentsOf: root.appendingPathComponent("plugin/skills/photonz/SKILL.md"), encoding: .utf8)
        for tool in AgentTools.all { #expect(skill.contains(tool.name), "\(tool.name) is not in the skill") }
    }

    @Test("A plan's key step names the layer an earlier step made, and says what it did")
    func inAPlan() throws {
        let step = AskStep(tool: "set_keys", arguments: try Self.args(
            #"{"layer": "$1", "property": "opacity", "keys": [{"seconds": 0, "value": 0}]}"#))
        let id = UUID().uuidString
        guard case .setKeys(let document, let call) = try step.request(document: "d1", made: [1: id]).get() else {
            Issue.record("not set_keys"); return
        }
        #expect(document == "d1")
        #expect(call.layer == id)
        #expect(AskChangeWords.sentence([step]).contains("Animated"))
    }
}

@Suite("Agent tool walk step")
struct AgentToolWalkStepTests {
    @Test("A walk can call an agent tool, and the step runs on a locked screen")
    func step() throws {
        let script = try PlaytestScript.decode(Data(#"""
            { "steps": [ { "do": "agentTool", "tool": "set_timing", "arguments": "{\"seconds\": 2}" } ] }
            """#.utf8))
        #expect(script.steps.first == .agentTool(tool: "set_timing", arguments: #"{"seconds": 2}"#))
        #expect(PlaytestLockSafety.stepsThatSurviveALock.contains("agentTool"))
    }
}

/// change_keys: what a tweak to an animation asks for, in one call.
@Suite("Agent changes keys that are there")
struct AgentChangeKeysTests {

    static func keyed() throws -> (document: PhotonzDocument, box: UUID, dot: UUID) {
        let box = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FF0000")),
                        frame: CGRect(x: 10, y: 20, width: 40, height: 30))
        let dot = Layer(name: "Dot", content: .annotation(AnnotationContent(shape: .ellipse, colorHex: "#00FF00")),
                        frame: CGRect(x: 100, y: 100, width: 10, height: 10))
        var document = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200), layers: [box, dot])
        _ = try document.agentSetKeys(AgentSetKeys(layer: box.id.uuidString, property: .position, keys: [
            AgentKey(atMS: 0, value: .point(CGPoint(x: 10, y: 20)), curve: .easeOutBack),
            AgentKey(atMS: 1000, value: .point(CGPoint(x: 50, y: 20))),
            AgentKey(atMS: 2000, value: .point(CGPoint(x: 10, y: 20))),
        ])).get()
        _ = try document.agentSetKeys(AgentSetKeys(layer: dot.id.uuidString, property: .rotation, keys: [
            AgentKey(atMS: 1000, value: .number(0)), AgentKey(atMS: 1500, value: .number(90)),
        ])).get()
        _ = try document.agentSetTiming(AgentTiming(lengthMS: 2000)).get()
        return (document, box.id, dot.id)
    }

    static func times(_ document: PhotonzDocument, _ id: UUID, _ property: MotionProperty) -> [Int] {
        document.layer(id: id)?.keyedMotion(property)?.keyframes.map(\.atMS) ?? []
    }

    @Test("The call is schema checked: it says how, and only sensible amounts")
    func call() throws {
        #expect(AgentTools.tool(named: "change_keys") != nil)
        if case .failure = try AgentKeysTests.request("change_keys", #"{"speed":2}"#) { Issue.record("speed alone is a call") }
        guard case .failure = try AgentKeysTests.request("change_keys", #"{}"#) else { Issue.record("say speed or amount"); return }
        guard case .failure = try AgentKeysTests.request("change_keys", #"{"speed":0}"#) else { Issue.record("speed 0 stops time"); return }
    }

    @Test("Twice as fast halves every key and the lap, and keeps each curve")
    func faster() throws {
        var (document, box, dot) = try Self.keyed()
        let answer = try document.agentChangeKeys(AgentChangeKeys(speed: 2)).get()
        #expect(Self.times(document, box, .position) == [0, 500, 1000])
        #expect(Self.times(document, dot, .rotation) == [500, 750])
        #expect(document.motionCycleLengthMS == 1000)
        #expect(answer.lapSeconds == 1)
        #expect(document.layer(id: box)?.keyedMotion(.position)?.stretchCurve(0) == .easeOutBack)
    }

    @Test("Faster on one layer keeps its start and the lap, and does not touch the others")
    func fasterOnOne() throws {
        var (document, box, dot) = try Self.keyed()
        _ = try document.agentChangeKeys(AgentChangeKeys(layers: [dot.uuidString], speed: 2)).get()
        #expect(Self.times(document, dot, .rotation) == [1000, 1250])
        #expect(Self.times(document, box, .position) == [0, 1000, 2000])
        #expect(document.motionCycleLengthMS == 2000)
    }

    @Test("Naming every keyed layer is the whole motion, so the lap goes with it: a slowed spinner never stops half way round")
    func everyLayerNamed() throws {
        var (document, box, dot) = try Self.keyed()
        _ = try document.agentChangeKeys(AgentChangeKeys(layers: [box.uuidString, dot.uuidString], speed: 0.5)).get()
        #expect(Self.times(document, box, .position) == [0, 2000, 4000])
        #expect(document.motionCycleLengthMS == 4000)
    }

    @Test("A key slowed past the end of the lap makes the lap longer, rather than never being reached")
    func pastTheLap() throws {
        var (document, _, dot) = try Self.keyed()
        _ = try document.agentChangeKeys(AgentChangeKeys(layers: [dot.uuidString], speed: 0.2)).get()
        #expect(Self.times(document, dot, .rotation) == [1000, 3500])
        #expect(document.motionCycleLengthMS == 3500)
    }

    @Test("Further scales each value from where it starts, and -1 turns it the other way")
    func further() throws {
        var (document, box, dot) = try Self.keyed()
        _ = try document.agentChangeKeys(AgentChangeKeys(layers: [box.uuidString], amount: 1.5)).get()
        let middle = document.layer(id: box)?.keyedMotion(.position)?.keyframes[1].value
        #expect(middle == .point(CGPoint(x: 70, y: 20)))
        _ = try document.agentChangeKeys(AgentChangeKeys(layers: [dot.uuidString], property: .rotation, amount: -1)).get()
        #expect(document.layer(id: dot)?.keyedMotion(.rotation)?.keyframes.last?.value == .number(-90))
    }

    @Test("A fade is left alone by amount unless it is named, and stays in range when it is")
    func fades() throws {
        var (document, box, _) = try Self.keyed()
        _ = try document.agentSetKeys(AgentSetKeys(layer: box.uuidString, property: .opacity, keys: [
            AgentKey(atMS: 0, value: .number(40)), AgentKey(atMS: 1000, value: .number(90)),
        ])).get()
        _ = try document.agentChangeKeys(AgentChangeKeys(amount: 2)).get()
        #expect(document.layer(id: box)?.keyedMotion(.opacity)?.keyframes.last?.value == .number(90))
        _ = try document.agentChangeKeys(AgentChangeKeys(property: .opacity, amount: 2)).get()
        #expect(document.layer(id: box)?.keyedMotion(.opacity)?.keyframes.last?.value == .number(100))
    }

    @Test("Nothing to change is refused, and changes nothing")
    func refused() throws {
        var (document, box, _) = try Self.keyed()
        let before = document
        guard case .failure = document.agentChangeKeys(AgentChangeKeys(layers: [box.uuidString], property: .color, speed: 2)) else {
            Issue.record("no colour keys to change"); return
        }
        guard case .failure = document.agentChangeKeys(AgentChangeKeys(layers: ["nobody"], speed: 2)) else {
            Issue.record("no such layer"); return
        }
        #expect(document == before)
    }

    @Test("Keys too close to tell apart after a speed up are refused rather than merged")
    func tooClose() throws {
        var (document, box, _) = try Self.keyed()
        _ = try document.agentSetKeys(AgentSetKeys(layer: box.uuidString, property: .scale, keys: [
            AgentKey(atMS: 0, value: .number(100)), AgentKey(atMS: PropertyKeys.nearMS * 2, value: .number(120)),
        ])).get()
        guard case .failure = document.agentChangeKeys(AgentChangeKeys(speed: 10)) else {
            Issue.record("keys would land on each other"); return
        }
    }
}
