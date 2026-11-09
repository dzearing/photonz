import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Four ways a story icon lost a beat the model had planned, found in the
/// traces of the story eval on 2026-11-09 (task
/// `an-animated-icon-told-as-a-little-story-moves-th`): smoke left behind was
/// pressed into the moment before the rocket had gone and showed for one
/// frame; a tick that drew itself also faded in, so it read as a grey ghost
/// growing; an envelope that flew off was faded out on its way and faded in
/// on its way back, so it read as gone in one frame and popping back; and a
/// letter dropped into an envelope showed through its front. Every rule here
/// is boxes, keys and time: nothing knows what the icon is of.
@Suite("Ask's story icons keep every beat the model planned")
struct AskMotionStoryBeatsTests {

    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }
    static func keys(_ step: AskStep) -> [(seconds: Double, value: Double, curve: String?)] {
        AskMotionCheck.timed(step).compactMap { key in key.value.doubleValue.map { (key.seconds, $0, key.curve) } }
    }
    static let view = CGRect(x: 0, y: 0, width: 24, height: 24)

    // MARK: Left behind

    static let launcher = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><g id="craft"><path d="M12 2 L15 10 L15 16 L9 16 L9 10 Z"/></g><g id="puff"><circle cx="9" cy="20" r="1.5"/><circle cx="15" cy="20" r="1.5"/></g></svg>"##

    @Test("A mark that grows where it was left is left behind as planned, not pressed into the moment before the part has gone")
    func growingMarkStays() throws {
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(Self.launcher)])
        let lift = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/craft","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"curve":"Ease in","seconds":0.55,"value":{"x":0,"y":1}},{"seconds":1.1,"value":{"x":0,"y":-24}},{"seconds":1.5,"value":{"x":0,"y":-24}},{"seconds":2.4,"value":{"x":0,"y":0}}]}"#))
        let fade = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/puff","property":"opacity","keys":[{"seconds":0,"value":0},{"seconds":0.55,"value":0},{"curve":"Ease out","seconds":0.75,"value":100},{"curve":"Ease out","seconds":1.5,"value":0},{"seconds":2.4,"value":0}]}"#))
        let grow = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/puff","property":"scale","keys":[{"seconds":0,"value":30},{"seconds":0.55,"value":30},{"curve":"Ease out","seconds":0.75,"value":100},{"seconds":1.5,"value":100},{"seconds":2.4,"value":30}]}"#))
        #expect(AskMotion.marksGo([drawing, lift, fade, grow], view: Self.view) == [drawing, lift, fade, grow])
        // Without growth of its own it is a trail, and still goes with the part.
        let pressed = AskMotion.marksGo([drawing, lift, fade], view: Self.view)
        #expect(pressed != [drawing, lift, fade])
        // A scale that never changes is not growth.
        let flat = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/puff","property":"scale","keys":[{"seconds":0,"value":100},{"seconds":2.4,"value":100}]}"#))
        #expect(AskMotion.marksGo([drawing, lift, fade, flat], view: Self.view) != [drawing, lift, fade, flat])
    }

    // MARK: Drawn, not faded

    @Test("A line that draws itself is not faded in over the same beat: it is fully inked from the moment it starts to draw")
    func drawsNotFades() throws {
        let trim = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/tick","property":"trimEnd","keys":[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease out","seconds":0.2,"value":0},{"curve":"Hold","seconds":0.6,"value":100},{"curve":"Ease in","seconds":2.2,"value":100},{"seconds":2.4,"value":0}]}"#))
        let fade = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/tick","property":"opacity","keys":[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease out","seconds":0.2,"value":0},{"curve":"Hold","seconds":0.6,"value":100},{"curve":"Ease in","seconds":2.2,"value":100},{"seconds":2.4,"value":0}]}"#))
        let made = AskMotion.drawnNotFaded([trim, fade])
        #expect(made.first == trim)
        let opacity = Self.keys(try #require(made.last))
        #expect(opacity.map(\.value) == [0, 100, 100, 100, 0])
        #expect(opacity.map(\.seconds) == [0, 0.2, 0.6, 2.2, 2.4])
        #expect(opacity.first?.curve == "Hold")
        // A fade on a line that is already drawn is meant to be seen.
        let drawn = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/tick","property":"trimEnd","keys":[{"seconds":0,"value":100},{"seconds":2.4,"value":100}]}"#))
        #expect(AskMotion.drawnNotFaded([drawn, fade]) == [drawn, fade])
        // Another part's fade is its own.
        let other = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/box","property":"opacity","keys":[{"seconds":0,"value":0},{"seconds":0.2,"value":0},{"seconds":0.6,"value":100},{"seconds":2.4,"value":0}]}"#))
        #expect(AskMotion.drawnNotFaded([trim, other]) == [trim, other])
    }

    // MARK: The edge hides

    static let sender = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><g id="craft"><rect x="4" y="8" width="16" height="10"/></g></svg>"##

    @Test("What flies out of the frame is seen the whole way: a fade that only hides it while it is gone is taken off, and the edge hides it")
    func edgeHides() throws {
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(Self.sender)])
        let fly = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/craft","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"curve":"Ease in","seconds":1,"value":{"x":0,"y":0}},{"curve":"Hold","seconds":1.5,"value":{"x":24,"y":-24}},{"seconds":1.55,"value":{"x":-24,"y":24}},{"seconds":1.8,"value":{"x":0,"y":0}}]}"#))
        let fade = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/craft","property":"opacity","keys":[{"seconds":0,"value":100},{"seconds":1.4,"value":100},{"seconds":1.5,"value":0},{"seconds":1.7,"value":0},{"seconds":1.8,"value":100}]}"#))
        let made = AskMotion.edgeHides([drawing, fly, fade], view: Self.view)
        #expect(Array(made.prefix(2)) == [drawing, fly])
        let opacity = Self.keys(try #require(made.last))
        #expect(opacity.allSatisfy { $0.value == 100 })
        #expect(opacity.map(\.seconds) == [0, 1.4, 1.5, 1.7, 1.8])
        // Hidden while it is still in the frame: the fade is the motion, kept.
        let early = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/craft","property":"opacity","keys":[{"seconds":0,"value":100},{"seconds":0.3,"value":0},{"seconds":0.6,"value":0},{"seconds":0.8,"value":100},{"seconds":1.8,"value":100}]}"#))
        #expect(AskMotion.edgeHides([drawing, fly, early], view: Self.view) == [drawing, fly, early])
        // A part that rests half seen keeps its look.
        let ghost = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/craft","property":"opacity","keys":[{"seconds":0,"value":50},{"seconds":1.5,"value":0},{"seconds":1.8,"value":50}]}"#))
        #expect(AskMotion.edgeHides([drawing, fly, ghost], view: Self.view) == [drawing, fly, ghost])
        // A part that never leaves keeps its fade.
        let stay = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/craft","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":1,"value":{"x":2,"y":-2}},{"seconds":1.8,"value":{"x":0,"y":0}}]}"#))
        #expect(AskMotion.edgeHides([drawing, stay, fade], view: Self.view) == [drawing, stay, fade])
    }

    @Test("Landing a plan takes off the fade of what flies out of the frame")
    func fittedCarriesThem() throws {
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(Self.sender)])
        let fly = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/craft","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"curve":"Ease in","seconds":1,"value":{"x":0,"y":0}},{"curve":"Hold","seconds":1.5,"value":{"x":24,"y":-24}},{"seconds":1.55,"value":{"x":-24,"y":24}},{"seconds":1.8,"value":{"x":0,"y":0}}]}"#))
        let fade = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/craft","property":"opacity","keys":[{"seconds":0,"value":100},{"seconds":1.4,"value":100},{"seconds":1.5,"value":0},{"seconds":1.7,"value":0},{"seconds":1.8,"value":100}]}"#))
        let landed = AskMotion.planned([drawing, fly, fade])
        let opacity = try #require(landed.last { $0.arguments["layer"]?.stringValue == "$1/craft" && $0.arguments["property"]?.stringValue == "opacity" })
        #expect(Self.keys(opacity).allSatisfy { $0.value == 100 })
    }

    // MARK: Going in

    @Test("What drops into a closed outline drawn before it goes behind that outline, which is filled white, so the front hides it")
    func goesInBehind() throws {
        // The eval's envelope on 2026-11-09: the letter drawn above the
        // envelope and after it, dropping in, showed through the closed front.
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><g id="whole"><rect id="body" x="3" y="9" width="18" height="12" rx="1"/><path id="sheet" d="M8 3h8v6H8z"/><path id="cover" d="M3 9l9-5 9 5"/></g></svg>"##
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(svg)])
        let drop = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/sheet","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.4,"value":{"x":0,"y":8}},{"seconds":1.5,"value":{"x":0,"y":8}},{"seconds":1.8,"value":{"x":0,"y":0}}]}"#))
        let made = AskMotion.hidden([drawing, drop])
        let art = try SVGArtwork.parse(try #require(made.first?.arguments["svg"]?.stringValue), keepingGroups: true).get()
        #expect(art.parts.compactMap { $0.name.map(AskMotion.plain) } == ["sheet", "body", "cover"])
        func fill(_ name: String) -> String? { art.parts.first { AskMotion.plain($0.name ?? "") == name }?.fill }
        #expect(fill("body") == "#FFFFFF")
        #expect(made.dropFirst() == [drop])
        // Dropping only part of the way in, it is meant to be seen.
        let short = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/sheet","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.4,"value":{"x":0,"y":2}},{"seconds":1.8,"value":{"x":0,"y":0}}]}"#))
        #expect(AskMotion.hidden([drawing, short]) == [drawing, short])
    }
}
