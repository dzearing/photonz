import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The user's trash story, walked on 2026-11-12 at 00:58 (task
/// `an-animated-icon-told-as-a-little-story-moves-th`, pass fourteen's walk),
/// the plan exactly as the model wrote it after its look and mend.
@Suite("Ask's story icons: a bounce off what was hit is seen")
struct AskMotionBounceSeenTests {

    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }
    static let bin = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><g id="bin"><path id="body" d="M6 9 L7 20 Q7 21 8 21 L16 21 Q17 21 17 20 L18 9"/><line id="rib-left" x1="10" y1="12" x2="10.5" y2="18"/><line id="rib-right" x1="14" y1="12" x2="13.5" y2="18"/></g><g id="lid"><line id="lid-bar" x1="5" y1="8" x2="19" y2="8"/><line id="lid-knob" x1="11" y1="6" x2="13" y2="6"/></g><g id="trash"><path id="crumple" d="M18 3 L21 4 L20 6 L17 5 Z"/></g></svg>"##

    static func steps() throws -> [AskStep] {
        [AskStep(tool: "add_drawing", arguments: ["icon": true, "subject": "trash bin with openable lid", "svg": .string(bin)]),
         AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(1.5)]),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease out","seconds":0.2,"value":0},{"curve":"Hold","seconds":0.5,"value":-40},{"curve":"Ease in","seconds":0.8,"value":-40},{"curve":"Ease out back","seconds":0.95,"value":-25},{"curve":"Hold","seconds":1.3,"value":0},{"seconds":1.5,"value":0}],"layer":"$1/lid","pivot":{"x":5,"y":8},"property":"rotation"}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":100},{"seconds":1.1,"value":100},{"seconds":1.2,"value":0},{"seconds":1.4,"value":0},{"seconds":1.5,"value":100}],"layer":"$1/trash","property":"opacity"}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"$1/lid","value":{"x":-4,"y":3}},{"seconds":0.95,"value":{"x":-5,"y":1}},{"seconds":1.1,"touches":"$1/body","value":{"x":-5,"y":5}},{"seconds":1.2,"value":{"x":-5,"y":5}},{"seconds":1.5,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position"}"#))]
    }

    /// `PHOTONZ_LAP_DUMP=/tmp/lap.json swift test --filter AskMotionBounceSeen`, then
    /// `python3 Scripts/ask-eval/lap-frames.py /tmp/lap.json /tmp/lap.png`.
    @Test("The landed plan's frames, written out on request",
          .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_LAP_DUMP"] != nil))
    func dump() throws {
        let path = try #require(ProcessInfo.processInfo.environment["PHOTONZ_LAP_DUMP"])
        let landed = AskMotion.planned(try Self.steps())
        for step in landed where step.tool == "set_keys" {
            print("LANDED", step.arguments.encodedString())
        }
        try LapDump.write(landed, to: path, frames: 48)
    }
}

extension AskMotionBounceSeenTests {
    static func point(_ value: AgentJSON?) -> CGPoint? {
        guard let x = value?["x"]?.doubleValue, let y = value?["y"]?.doubleValue else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// The trash met the open lid's underside on a way in nearly along it
    /// (about 25 degrees), so no bounce off it turned without running into
    /// the can's wall: it went back the way it came, stopped in mid-air
    /// above the right wall and dropped across it. Met a unit further up the
    /// lid, its mirror off the lid turns 60 degrees or more and drops into
    /// the can's mouth.
    @Test("Met where its mirror turns: the bounce off the lid turns sharply and drops into the can clear of its walls")
    func bounceTurnsClear() throws {
        let landed = AskMotion.planned(try Self.steps())
        let trash = try #require(landed.last { $0.tool == "set_keys" && $0.arguments["layer"]?.stringValue == "$1/trash" && $0.arguments["property"]?.stringValue == "position" })
        // Read with its lines as wide as they are drawn in the grown frame,
        // which is what the hit is placed against.
        let lap = try #require(AskMotion.Lap(AskMotionOverTheLidTests.asDrawn(landed)))
        let keys = AskMotionCheck.timed(trash)
        let hit = try #require(keys.firstIndex { key in
            key.seconds > 0.6 && key.seconds < 1 && AskMotion.inkMeets(lap.ink("trash", at: key.seconds), lap.ink("lid", at: key.seconds))
        })
        let at = try #require(Self.point(keys[hit].value))
        let before = try #require(Self.point(AskMotionCheck.value(of: trash, at: keys[hit].seconds - 0.05)))
        let after = try #require(Self.point(keys[hit + 1].value))
        let into = CGVector(dx: at.x - before.x, dy: at.y - before.y), out = CGVector(dx: after.x - at.x, dy: after.y - at.y)
        // Turned 60 degrees or more off its way in, at speed: a ricochet.
        #expect(into.dx * out.dx + into.dy * out.dy <= AskMotion.aimedTurn * hypot(into.dx, into.dy) * hypot(out.dx, out.dy), "in \(into), out \(out)")
        #expect(out.dy > abs(out.dx), "off the lid it drops: \(out)")
        // From the hit until it is out of sight, never through the can's wall or the lid.
        let walls = AskMotion.lines(of: "body", in: lap)
        var moment = keys[hit].seconds + 0.02
        while moment < 1.5, lap.placed("trash", at: moment)?.seen ?? false {
            let mine = lap.ink("trash", at: moment)
            #expect(!AskMotion.inkMeets(mine, walls, within: -AskMotion.passesThrough), "through the can at \(moment): \(mine)")
            #expect(!AskMotion.inkMeets(mine, lap.ink("lid", at: moment), within: -AskMotion.passesThrough), "through the lid at \(moment)")
            moment += 0.02
        }
    }
}

/// The same sentence walked again on 2026-11-12 at 03:20 on the first half
/// of this change: a smaller can (mouth 8 across between the walls' lines)
/// and the model's last keys sent with no `touches` (kept from the ones
/// they replace). Off the lid the trash dropped down the can's right wall.
enum AskMotionBounceSeenWalkTwo {
    static let bin = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><g id="bin"><path id="body" d="M7 9 L8 20 L16 20 L17 9"/><line id="rib-left" x1="10" y1="11" x2="10.5" y2="18"/><line id="rib-right" x1="14" y1="11" x2="13.5" y2="18"/></g><g id="lid"><line id="lid-bar" x1="6" y1="8" x2="18" y2="8"/><line id="lid-knob" x1="11" y1="6" x2="13" y2="6"/></g><path id="trash" d="M18 2 L21 3 L20 6 L17 5 Z"/></svg>"##
    static let throwKeys = #"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"value":{"x":-4,"y":3}},{"seconds":0.95,"value":{"x":-5,"y":1}},{"seconds":1.1,"value":{"x":-5,"y":6}},{"seconds":1.5,"value":{"x":0,"y":0}}]"#
    static let touchedKeys = #"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"$1/lid","value":{"x":-4,"y":3}},{"seconds":0.95,"value":{"x":-5,"y":1}},{"seconds":1.1,"touches":"$1/bin","value":{"x":-5,"y":6}},{"seconds":1.5,"value":{"x":0,"y":0}}]"#

    static func steps() throws -> [AskStep] {
        let args = AskMotionBounceSeenTests.args
        return [AskStep(tool: "add_drawing", arguments: ["icon": true, "subject": "trash bin with hinged lid", "svg": .string(bin)]),
                AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(1.5)]),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease out","seconds":0.2,"value":0},{"curve":"Hold","seconds":0.5,"value":-40},{"curve":"Ease in","seconds":0.8,"value":-40},{"curve":"Ease out back","seconds":0.95,"value":-25},{"curve":"Hold","seconds":1.3,"value":0},{"seconds":1.5,"value":0}],"layer":"$1/lid","pivot":{"x":6,"y":8},"property":"rotation"}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":\#(throwKeys),"layer":"$1/trash","property":"position"}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":100},{"seconds":1.1,"value":0},{"seconds":1.5,"value":100}],"layer":"$1/trash","property":"opacity"}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":\#(touchedKeys),"layer":"$1/trash","property":"position","replace":true}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":\#(throwKeys),"layer":"$1/trash","property":"position","replace":true}"#))]
    }
}

extension AskMotionBounceSeenTests {
    @Test("Walk two's frames, written out on request",
          .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_LAP_DUMP2"] != nil))
    func dumpTwo() throws {
        let path = try #require(ProcessInfo.processInfo.environment["PHOTONZ_LAP_DUMP2"])
        let landed = AskMotion.planned(try AskMotionBounceSeenWalkTwo.steps())
        for step in landed where step.tool == "set_keys" { print("LANDED", step.arguments.encodedString()) }
        try LapDump.write(landed, to: path, frames: 48)
    }
}
