import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The user's trash story, walked on 2026-11-12 at 03:47 (task
/// `an-animated-icon-told-as-a-little-story-moves-th`, pass sixteen's walk):
/// the plan as it landed (the mend ran out of time, so the looked-at motion).
/// The model shut the lid by 0.95 s and dropped the trash into the can at
/// 1.1 to 1.2 s, through the shut lid, after its own hop up to y -2.
enum AskMotionInBeforeShutWalk {
    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }
    static let bin = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><g id="bin"><path id="body" d="M5 8 L6 20 Q6 21 7 21 L17 21 Q18 21 18 20 L19 8"/><line id="rib-left" x1="9" y1="11" x2="9.5" y2="18"/><line id="rib-right" x1="15" y1="11" x2="14.5" y2="18"/></g><g id="lid"><line id="lid-bar" x1="4" y1="8" x2="20" y2="8"/><line id="lid-knob" x1="11" y1="6" x2="13" y2="6"/></g><g id="trash"><path id="crumple" d="M18 2 L21 3 L20 5 L17 4 Z"/></g></svg>"##

    static func steps() throws -> [AskStep] {
        [AskStep(tool: "add_drawing", arguments: ["icon": true, "subject": "trash bin with openable lid and a piece of trash", "svg": .string(bin)]),
         AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(1.5)]),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease out","seconds":0.2,"value":0},{"curve":"Hold","seconds":0.5,"value":-50},{"curve":"Ease in","seconds":0.8,"value":-50},{"curve":"Hold","seconds":0.95,"value":0},{"seconds":1.5,"value":0}],"layer":"$1/lid","pivot":{"x":4,"y":8},"property":"rotation"}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":18,"y":2}},{"seconds":0.5,"value":{"x":18,"y":2}},{"seconds":0.8,"value":{"x":12,"y":4}},{"seconds":0.95,"value":{"x":12,"y":2}},{"seconds":1.2,"value":{"x":12,"y":10}},{"seconds":1.5,"value":{"x":12,"y":10}}],"layer":"$1/trash","property":"position"}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":100},{"seconds":1.2,"value":100},{"seconds":1.4,"value":0},{"seconds":1.5,"value":0}],"layer":"$1/trash","property":"opacity"}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"value":{"x":-6,"y":2}},{"seconds":0.95,"value":{"x":-6,"y":0}},{"seconds":1.2,"value":{"x":-6,"y":8}},{"seconds":1.5,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position","replace":true}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":100},{"seconds":1.2,"value":100},{"seconds":1.4,"value":0},{"seconds":1.5,"value":100}],"layer":"$1/trash","property":"opacity","replace":true}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"$1/lid","value":{"x":-6,"y":2}},{"seconds":0.95,"touches":"$1/lid","value":{"x":-6,"y":0}},{"seconds":1.2,"touches":"$1/bin","value":{"x":-6,"y":8}},{"seconds":1.5,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position","replace":true}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"value":{"x":-6,"y":2}},{"seconds":0.95,"value":{"x":-6,"y":0}},{"seconds":1.1,"value":{"x":-6,"y":-2}},{"seconds":1.2,"value":{"x":-6,"y":8}},{"seconds":1.5,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position","replace":true}"#))]
    }
}

@Suite("Ask's story icons: what goes in is in before the lid shuts")
struct AskMotionInBeforeShutTests {
    @Test("Pass sixteen's walk, written out on request",
          .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_LAP_DUMP"] != nil))
    func dump() throws {
        let path = try #require(ProcessInfo.processInfo.environment["PHOTONZ_LAP_DUMP"])
        let landed = AskMotion.planned(try AskMotionInBeforeShutWalk.steps())
        for step in landed where step.tool == "set_keys" { print("LANDED", step.arguments.encodedString()) }
        try LapDump.write(landed, to: path, frames: 48)
    }
}

extension AskMotionInBeforeShutTests {
    static func trash(_ landed: [AskStep], _ property: String) throws -> AskStep {
        try #require(landed.last { $0.tool == "set_keys" && $0.arguments["layer"]?.stringValue == "$1/trash" && $0.arguments["property"]?.stringValue == property })
    }

    /// The model faded the trash from 1.2 s, where it landed in the can, and
    /// sent it home to where the lap starts by 1.5 s. Read as a journey to
    /// be seen, the fade was moved to 1.4 to 1.46 s, so the trash rose back
    /// out of the can, over the shut lid, in plain view. Going home is the
    /// next lap's, unseen: it fades where it landed and only then sets off.
    @Test("Faded where it landed: going home for the next lap is never seen")
    func homeUnseen() throws {
        let landed = AskMotion.planned(try AskMotionInBeforeShutWalk.steps())
        let lap = try #require(AskMotion.Lap(landed))
        let moves = AskMotionCheck.timed(try Self.trash(landed, "position"))
        // The last key before it sets off home, and the way home after it.
        let home = try #require(moves.last)
        let setsOff = try #require(moves.dropLast().last { $0.value != home.value })
        var moment = setsOff.seconds + 0.02
        while moment < home.seconds - 0.0005 {
            #expect(!(lap.placed("trash", at: moment)?.seen ?? true), "seen on its way home at \(moment)")
            moment += 0.02
        }
    }
}

extension AskMotionInBeforeShutTests {
    /// The lid shut at 0.95 s; the trash, after its own hop up off the
    /// shutting lid, dropped through the shut lid into the can at 1.15 s.
    /// What goes in under a part that shuts is in before it shuts: from the
    /// hit on, never through the lid while seen, and under the lid's line
    /// by the moment the lid is shut.
    @Test("In before the lid shuts: the trash never drops through the shut lid")
    func inBeforeShut() throws {
        let landed = AskMotion.planned(try AskMotionInBeforeShutWalk.steps())
        let lap = try #require(AskMotion.Lap(landed))
        var moment = 0.5
        while moment < 1.5 {
            if lap.placed("trash", at: moment)?.seen ?? false {
                #expect(!AskMotion.inkMeets(lap.ink("trash", at: moment), lap.ink("lid", at: moment), within: -AskMotion.passesThrough),
                        "through the lid at \(moment)")
            }
            moment += 0.01
        }
        // The lid's last key that is not where it rests: when it is shut.
        let lid = try #require(landed.last { $0.tool == "set_keys" && $0.arguments["layer"]?.stringValue == "$1/lid" && $0.arguments["property"]?.stringValue == "rotation" })
        let turns = AskMotionCheck.timed(lid)
        let rest = try #require(turns.last)
        let closing = try #require(turns.lastIndex { $0.value != rest.value })
        let shut = turns[closing + 1].seconds
        let lidLowest = try #require(lap.ink("lid", at: 1.5).flatMap { $0 }.map(\.y).max())
        let trashPoints = lap.ink("trash", at: shut).flatMap { $0 }
        let middle = trashPoints.map(\.y).reduce(0, +) / CGFloat(trashPoints.count)
        #expect(middle > lidLowest, "trash middle \(middle) above the shut lid's line \(lidLowest) at \(shut)")
    }
}

/// The same sentence walked on 2026-11-13 at 15:52 on the first change of
/// pass seventeen: the lid hinged at (5, 7), no hop, the trash faded over
/// 0.95 to 1.2 s as it dropped into the can, after the lid shut at 0.95 s.
enum AskMotionInBeforeShutWalkTwo {
    static let bin = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><g id="bin"><path id="body" d="M6 9 L7 20 Q7 21 8 21 L16 21 Q17 21 17 20 L18 9"/><line id="rib-left" x1="10" y1="12" x2="10.5" y2="18"/><line id="rib-right" x1="14" y1="12" x2="13.5" y2="18"/></g><g id="lid"><line id="lid-bar" x1="5" y1="7" x2="19" y2="7"/><line id="lid-knob" x1="11" y1="5" x2="13" y2="5"/></g><g id="trash"><path id="crumple" d="M18 2 L21 3 L20 5 L17 4 Z"/></g></svg>"##
    static let moves = #"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"value":{"x":-6,"y":2}},{"seconds":0.95,"value":{"x":-6,"y":0}},{"seconds":1.2,"value":{"x":-6,"y":8}},{"seconds":1.5,"value":{"x":0,"y":0}}]"#
    static let touching = #"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"lid","value":{"x":-6,"y":2}},{"seconds":0.95,"touches":"lid","value":{"x":-6,"y":0}},{"seconds":1.2,"touches":"bin","value":{"x":-6,"y":8}},{"seconds":1.5,"value":{"x":0,"y":0}}]"#

    static func steps() throws -> [AskStep] {
        let args = AskMotionInBeforeShutWalk.args
        return [AskStep(tool: "add_drawing", arguments: ["icon": true, "subject": "trash bin with hinged lid and a piece of trash", "svg": .string(bin)]),
                AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(1.5)]),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease out","seconds":0.2,"value":0},{"curve":"Hold","seconds":0.5,"value":-50},{"curve":"Ease in out","seconds":0.8,"value":-50},{"curve":"Hold","seconds":0.95,"value":0},{"seconds":1.5,"value":0}],"layer":"$1/lid","pivot":{"x":5,"y":7},"property":"rotation"}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":18,"y":2}},{"seconds":0.5,"value":{"x":18,"y":2}},{"seconds":0.8,"value":{"x":12,"y":4}},{"seconds":0.95,"value":{"x":12,"y":2}},{"seconds":1.2,"value":{"x":12,"y":10}},{"seconds":1.5,"value":{"x":12,"y":10}}],"layer":"$1/trash","property":"position"}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":100},{"seconds":0.8,"value":100},{"seconds":0.95,"value":100},{"seconds":1.2,"value":0},{"seconds":1.5,"value":0}],"layer":"$1/trash","property":"opacity"}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":\#(moves),"layer":"$1/trash","property":"position","replace":true}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":100},{"seconds":0.8,"value":100},{"seconds":0.95,"value":100},{"seconds":1.2,"value":0},{"seconds":1.5,"value":100}],"layer":"$1/trash","property":"opacity","replace":true}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":\#(touching),"layer":"$1/trash","property":"position","replace":true}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":\#(moves),"layer":"$1/trash","property":"position","replace":true}"#))]
    }
}

extension AskMotionInBeforeShutTests {
    @Test("Walk two's frames, written out on request",
          .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_LAP_DUMP2"] != nil))
    func dumpTwo() throws {
        let path = try #require(ProcessInfo.processInfo.environment["PHOTONZ_LAP_DUMP2"])
        let landed = AskMotion.planned(try AskMotionInBeforeShutWalkTwo.steps())
        for step in landed where step.tool == "set_keys" { print("LANDED", step.arguments.encodedString()) }
        try LapDump.write(landed, to: path, frames: 48)
    }
}

extension AskMotionInBeforeShutTests {
    /// Walk two landed the trash with its top in the shut lid's stroke, so
    /// no landing moment cleared and it dropped in after the lid shut.
    @Test("Walk two: in before the lid shuts, held where it landed till gone")
    func walkTwoInBeforeShut() throws {
        let landed = AskMotion.planned(try AskMotionInBeforeShutWalkTwo.steps())
        let lap = try #require(AskMotion.Lap(landed))
        // Touching the lid at the hit (0.8 s, placed so) is the hit; once
        // apart, never through it again while seen.
        var apart = false
        var moment = 0.8
        while moment < 1.5 {
            if lap.placed("trash", at: moment)?.seen ?? false {
                let meets = AskMotion.inkMeets(lap.ink("trash", at: moment), lap.ink("lid", at: moment), within: -AskMotion.passesThrough)
                #expect(!(meets && apart), "through the lid at \(moment)")
                if !meets { apart = true }
            }
            moment += 0.01
        }
        #expect(apart, "never came away from the lid")
    }
}
