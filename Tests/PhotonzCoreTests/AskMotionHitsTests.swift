import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Two ways the trash of the story eval lost its ending on 2026-11-09 (task
/// `an-animated-icon-told-as-a-little-story-moves-th`), read from its plan:
/// the model wrote each key's curve as how the part ARRIVES there ("Hold" on
/// the key it stays open until, "Ease out back" on the key it shuts at), while
/// a curve is the run LEAVING its key, so the lid stood open and snapped shut
/// in one frame ("snaps shut in one frame", "no easing", every look); and the
/// ball met the lid at 0.6 s while the lid stood still until 0.9 s, so the
/// close the request said the hit causes read as the lid shutting on its own.
/// Keys, boxes and time only: nothing knows what the icon is of.
@Suite("Ask's story icons: a seen hold moves, and a hit starts what it hits")
struct AskMotionHitsTests {

    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }
    static func keys(_ step: AskStep) -> [(seconds: Double, value: Double, curve: String?)] {
        AskMotionCheck.timed(step).compactMap { key in key.value.doubleValue.map { (key.seconds, $0, key.curve) } }
    }

    static let bin = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><g id="trash"><circle id="trash-ball" cx="20" cy="4" r="1.5" fill="#1D1D1F" stroke="none"/></g><g id="lid"><line id="lid-bar" x1="5" y1="7" x2="19" y2="7"/><line x1="12" y1="7" x2="12" y2="5"/></g><g id="can"><path d="M6 9 L7 20 L17 20 L18 9"/></g></svg>"##
    static var drawing: AskStep { AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(bin)]) }
    static let timing = AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(1.3)])

    /// The lid as the model keyed it on 2026-11-09.
    static func lid() throws -> AskStep {
        AskStep(tool: "set_keys", arguments: try args(#"{"layer":"$1/lid","property":"rotation","pivot":{"x":5,"y":7},"keys":[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease in","seconds":0.05,"value":8},{"curve":"Ease out back","seconds":0.3,"value":-55},{"curve":"Hold","seconds":0.9,"value":-55},{"curve":"Ease out back","seconds":1.1,"value":0},{"curve":"Hold","seconds":1.3,"value":0}]}"#))
    }

    // MARK: A seen hold moves

    @Test("A part held still and then keyed somewhere else while it is seen moves there on the next key's curve, instead of snapping")
    func seenHoldMoves() throws {
        let made = AskMotion.holdsMove([Self.drawing, Self.timing, try Self.lid()])
        let lid = Self.keys(try #require(made.last))
        #expect(lid.map(\.seconds) == [0, 0.05, 0.3, 0.9, 1.1, 1.3])
        #expect(lid.map(\.value) == [0, 8, -55, -55, 0, 0])
        // Stays open until 0.9, then shuts on the curve written where it shuts;
        // the first key starts the little dip the same way.
        #expect(lid.map(\.curve) == ["Ease in", "Ease in", "Ease out back", "Ease out back", "Ease out back", "Hold"])
    }

    @Test("A hold that stays a hold: out of the frame, out of sight, an opacity, a step to a new value, or nothing seen to tell")
    func holdsThatStay() throws {
        // Gone off the top of the frame, then home unseen: the jump is meant.
        let away = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/trash","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":-30}},{"curve":"Hold","seconds":1,"value":{"x":0,"y":-30}},{"seconds":1.3,"value":{"x":0,"y":0}}]}"#))
        #expect(AskMotion.holdsMove([Self.drawing, Self.timing, away]) == [Self.drawing, Self.timing, away])
        // Faded out while it jumps.
        let jump = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/trash","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":-6,"y":4}},{"curve":"Hold","seconds":1,"value":{"x":-6,"y":4}},{"seconds":1.3,"value":{"x":0,"y":0}}]}"#))
        let fade = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/trash","property":"opacity","keys":[{"seconds":0,"value":100},{"seconds":0.6,"value":100},{"seconds":0.7,"value":0},{"seconds":1.3,"value":0}]}"#))
        #expect(AskMotion.holdsMove([Self.drawing, Self.timing, jump, fade]) == [Self.drawing, Self.timing, jump, fade])
        // Seen, it slides home instead.
        let slid = AskMotion.holdsMove([Self.drawing, Self.timing, jump])
        #expect(AskMotionCheck.timed(try #require(slid.last)).map(\.curve) == [nil, nil, AgentKeyCurve.easeInOut, nil])
        // A blink is an opacity's own business.
        let blink = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/trash","property":"opacity","keys":[{"seconds":0,"value":100},{"curve":"Hold","seconds":0.5,"value":100},{"seconds":0.6,"value":0}]}"#))
        #expect(AskMotion.holdsMove([Self.drawing, blink]) == [Self.drawing, blink])
        // A hold reached by moving is a step: it arrives, stays, then steps on.
        let step = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/lid","property":"rotation","keys":[{"seconds":0,"value":0},{"curve":"Hold","seconds":0.5,"value":-20},{"seconds":0.8,"value":-40}]}"#))
        #expect(AskMotion.holdsMove([Self.drawing, step]) == [Self.drawing, step])
        // No drawing: nothing says whether it is seen.
        let alone = try Self.lid()
        #expect(AskMotion.holdsMove([alone]) == [alone])
    }

    // MARK: A hit starts what it hits

    /// The ball as keyed: thrown from outside, meets the lid at 0.6, drops in.
    static func ball(touches: String = "$1/lid") throws -> AskStep {
        AskStep(tool: "set_keys", arguments: try args(#"{"layer":"$1/trash","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.3,"value":{"x":0,"y":0}},{"seconds":0.6,"touches":"\#(touches)","value":{"x":-6,"y":3}},{"seconds":0.7,"value":{"x":-7,"y":1}},{"seconds":0.9,"value":{"x":-7,"y":6}},{"seconds":1.3,"value":{"x":-7,"y":6}}]}"#))
    }

    @Test("What a part hits, standing still until it moves a little later, starts moving the moment it is hit, and its lap still ends where it did")
    func hitStartsWhatItHits() throws {
        let ball = try Self.ball()
        let made = AskMotion.hitStarts([Self.drawing, Self.timing, try Self.lid(), ball])
        #expect(made.last == ball)
        let lid = Self.keys(made[2])
        // Started at the hit (0.6) it swept down through the ball as it
        // dropped in (2026-11-10), so it waited 0.1 s; with the ball now sent
        // away from what it hits (`bouncedAway`), it starts at the very hit,
        // 0.3 s before it was planned to, and passes through nothing.
        #expect(lid.map(\.seconds) == [0, 0.05, 0.3, 0.6, 0.8, 1.0, 1.3])
        #expect(lid.map(\.value) == [0, 8, -55, -55, 0, 0, 0])
        #expect(!AskMotion.crosses("lid", "trash", from: 0.6, lasting: 0.5, in: made))
        #expect(Array(lid.map(\.curve).prefix(5)) == ["Hold", "Ease in", "Ease out back", "Hold", "Ease out back"])
        // Named the plain way, the same.
        #expect(AskMotion.hitStarts([Self.drawing, Self.timing, try Self.lid(), try Self.ball(touches: "lid")])[2] == made[2])
    }

    @Test("A hit leaves alone what is not keyed, what moves anyway, and what only moves long after")
    func hitsThatStartNothing() throws {
        let ball = try Self.ball(touches: "can")
        let steps = [Self.drawing, Self.timing, try Self.lid(), ball]
        #expect(AskMotion.hitStarts(steps) == steps)
        // Already moving when it is hit.
        let swinging = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/lid","property":"rotation","keys":[{"seconds":0,"value":0},{"seconds":0.3,"value":-55},{"seconds":1,"value":0},{"seconds":1.3,"value":0}]}"#))
        let moving = [Self.drawing, Self.timing, swinging, try Self.ball()]
        #expect(AskMotion.hitStarts(moving) == moving)
        // Still for a long while after: its own beat, not the hit's.
        let late = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/lid","property":"rotation","keys":[{"seconds":0,"value":0},{"seconds":0.3,"value":-55},{"seconds":1.2,"value":-55},{"seconds":1.3,"value":0}]}"#))
        let waits = [Self.drawing, Self.timing, late, try Self.ball()]
        #expect(AskMotion.hitStarts(waits) == waits)
        // Its opacity is not a move.
        let fade = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/lid","property":"opacity","keys":[{"seconds":0,"value":100},{"seconds":0.9,"value":100},{"seconds":1.1,"value":0},{"seconds":1.3,"value":100}]}"#))
        let fading = [Self.drawing, Self.timing, fade, try Self.ball()]
        #expect(AskMotion.hitStarts(fading) == fading)
    }

    @Test("Landing a plan moves a seen hold and starts what is hit, before the touch is placed")
    func plannedCarriesThem() throws {
        let made = AskMotion.planned([Self.drawing, Self.timing, try Self.lid(), try Self.ball()])
        let lid = try #require(made.first { $0.arguments["layer"]?.stringValue == "$1/lid" })
        let keys = Self.keys(lid)
        // Open (its swing may be narrowed to fit the room) until just after
        // the hit at 0.6, then shut by 0.9, not 1.1 as planned.
        let open = try #require(keys.first { $0.seconds == 0.3 }?.value)
        #expect(open < -20)
        let starts = try #require(keys.last { $0.value == open && $0.curve == "Ease out back" }?.seconds)
        #expect(starts >= 0.6 && starts < 0.9)
        let shut = try #require(keys.first { $0.seconds > starts && $0.value == 0 }?.seconds)
        #expect(shut < 1.1)
        #expect(!AskMotion.crosses("lid", "trash", from: 0.6, lasting: 0.6, in: made))
    }
    // MARK: Seen the whole way

    @Test("What fades out while it travels a long way stays seen the whole way and fades where it arrives")
    func seenTheWholeWay() throws {
        let throwIn = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/trash","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.3,"value":{"x":0,"y":0}},{"seconds":0.7,"value":{"x":-6,"y":3}},{"seconds":0.8,"value":{"x":-7,"y":1}},{"seconds":1,"value":{"x":-7,"y":6}},{"seconds":1.15,"value":{"x":-7,"y":6}},{"seconds":1.3,"value":{"x":0,"y":0}}]}"#))
        let fade = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/trash","property":"opacity","keys":[{"seconds":0,"value":100},{"seconds":0.3,"value":100},{"seconds":0.9,"value":0},{"seconds":1.15,"value":0},{"seconds":1.3,"value":100}]}"#))
        let made = AskMotion.travelsSeen([Self.drawing, Self.timing, throwIn, fade])
        #expect(Array(made.prefix(3)) == [Self.drawing, Self.timing, throwIn])
        let opacity = Self.keys(try #require(made.last))
        #expect(opacity.map(\.seconds) == [0, 0.3, 0.9, 1, 1.15, 1.3])
        #expect(opacity.map(\.value) == [100, 100, 100, 0, 0, 100])
        // A short drift that fades is a puff: kept.
        let drift = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/trash","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.3,"value":{"x":0,"y":0}},{"seconds":0.9,"value":{"x":0,"y":-2}},{"seconds":1.3,"value":{"x":0,"y":0}}]}"#))
        #expect(AskMotion.travelsSeen([Self.drawing, Self.timing, drift, fade]) == [Self.drawing, Self.timing, drift, fade])
        // A mark that grows as it goes is left behind as planned.
        let grow = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/trash","property":"scale","keys":[{"seconds":0,"value":40},{"seconds":0.9,"value":120},{"seconds":1.3,"value":40}]}"#))
        #expect(AskMotion.travelsSeen([Self.drawing, Self.timing, throwIn, fade, grow]) == [Self.drawing, Self.timing, throwIn, fade, grow])
        // Seen until it arrives already: kept.
        let late = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/trash","property":"opacity","keys":[{"seconds":0,"value":100},{"seconds":1,"value":100},{"seconds":1.1,"value":0},{"seconds":1.3,"value":100}]}"#))
        #expect(AskMotion.travelsSeen([Self.drawing, Self.timing, throwIn, late]) == [Self.drawing, Self.timing, throwIn, late])
    }
}
