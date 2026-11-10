import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The trash of the user's own story (task
/// `an-animated-icon-told-as-a-little-story-moves-th`, run 20261109-134344):
/// the model said the ball's key at 0.6 s touches the lid, then, mending after
/// the look, wrote that value's keys again with replace true, the same keys,
/// and no touches. The hit was never placed, nothing started the lid, and the
/// bounce the user named was never seen. A key written again at the same
/// moment keeps what the earlier one said it touches. Keys and time only.
@Suite("Ask's story icons: what a key touches survives the keys being written again")
struct AskMotionTouchesKeptTests {

    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }
    static func touches(_ step: AskStep) -> [Double: String] {
        var out: [Double: String] = [:]
        for key in step.arguments["keys"]?.arrayValue ?? [] {
            if let seconds = key["seconds"]?.doubleValue, let other = key["touches"]?.stringValue { out[seconds] = other }
        }
        return out
    }

    static func ball(_ keys: String, replace: Bool = true) throws -> AskStep {
        AskStep(tool: "set_keys", arguments: try args(#"{"layer":"$1/trash","property":"position",\#(replace ? #""replace":true,"# : "")"keys":\#(keys)}"#))
    }

    static let first = #"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.3,"value":{"x":0,"y":0}},{"seconds":0.6,"touches":"$1/lid","value":{"x":-6,"y":3}},{"seconds":0.7,"value":{"x":-7,"y":1}},{"seconds":0.9,"touches":"$1/can","value":{"x":-7,"y":6}},{"seconds":1.3,"value":{"x":0,"y":0}}]"#
    static let again = #"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.3,"value":{"x":0,"y":0}},{"seconds":0.6,"value":{"x":-6,"y":3}},{"seconds":0.7,"value":{"x":-7,"y":1}},{"seconds":0.9,"value":{"x":-7,"y":6}},{"seconds":0.95,"value":{"x":-7,"y":8}},{"seconds":1.3,"value":{"x":0,"y":0}}]"#

    @Test("Keys written again with replace true keep the touches said for the same moments")
    func replaceKeepsTouches() throws {
        let kept = AskMotion.touchesKept([try Self.ball(Self.first), try Self.ball(Self.again)])
        #expect(Self.touches(kept[1]) == [0.6: "$1/lid", 0.9: "$1/can"])
        // The earlier step is left as it was.
        #expect(kept[0] == (try Self.ball(Self.first)))
    }

    @Test("Keys added without replace keep them too, and a moment the new keys moved loses nothing it never had")
    func addKeepsTouches() throws {
        let added = try Self.ball(#"[{"seconds":0.6,"value":{"x":-5,"y":3}}]"#, replace: false)
        let kept = AskMotion.touchesKept([try Self.ball(Self.first), added])
        #expect(Self.touches(kept[1]) == [0.6: "$1/lid"])
        // Somewhere else at another moment: no key there said what it touches.
        let moved = try Self.ball(#"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.65,"value":{"x":-4,"y":2}},{"seconds":1.3,"value":{"x":0,"y":0}}]"#)
        #expect(Self.touches(AskMotion.touchesKept([try Self.ball(Self.first), moved])[1]).isEmpty)
    }

    @Test("A key that says what it touches now keeps its own word, and another value or part is never touched")
    func ownWordAndOtherValues() throws {
        let own = try Self.ball(#"[{"seconds":0.6,"touches":"$1/can","value":{"x":-6,"y":3}}]"#)
        #expect(Self.touches(AskMotion.touchesKept([try Self.ball(Self.first), own])[1]) == [0.6: "$1/can"])
        let otherPart = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/lid","property":"position","replace":true,"keys":[{"seconds":0.6,"value":{"x":0,"y":0}}]}"#))
        let otherValue = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/trash","property":"scale","replace":true,"keys":[{"seconds":0.6,"value":100}]}"#))
        let steps = [try Self.ball(Self.first), otherPart, otherValue]
        #expect(AskMotion.touchesKept(steps) == steps)
    }

    @Test("The plan that lands places the hit the rewrite forgot: the ball is moved to meet the lid at 0.6 s")
    func landingPlacesTheKeptHit() throws {
        let bin = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><g id="trash"><circle id="trash-ball" cx="20" cy="4" r="1.5" fill="#1D1D1F" stroke="none"/></g><g id="lid"><line id="lid-bar" x1="5" y1="7" x2="19" y2="7"/></g><g id="can"><path d="M6 9 L7 20 L17 20 L18 9"/></g></svg>"##
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(bin)])
        let timing = AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(1.3)])
        let lid = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/lid","property":"rotation","pivot":{"x":5,"y":7},"keys":[{"seconds":0,"value":0},{"seconds":0.3,"value":-55},{"seconds":0.9,"value":-55},{"seconds":1.1,"value":0},{"seconds":1.3,"value":0}]}"#))
        let forgot = AskMotion.touchesPlaced(AskMotion.landingFolded([drawing, timing, lid, try Self.ball(Self.first), try Self.ball(Self.again)]))
        let remembered = AskMotion.touchesPlaced(AskMotion.landingFolded(AskMotion.touchesKept([drawing, timing, lid, try Self.ball(Self.first), try Self.ball(Self.again)])))
        func at06(_ steps: [AskStep]) -> CGPoint? {
            guard let ball = steps.last(where: { $0.arguments["layer"]?.stringValue == "$1/trash" }),
                  let key = (ball.arguments["keys"]?.arrayValue ?? []).first(where: { $0["seconds"]?.doubleValue == 0.6 }),
                  let x = key["value"]?["x"]?.doubleValue, let y = key["value"]?["y"]?.doubleValue else { return nil }
            return CGPoint(x: x, y: y)
        }
        #expect(at06(forgot) == CGPoint(x: -6, y: 3))
        let placed = try #require(at06(remembered))
        #expect(placed != CGPoint(x: -6, y: 3))
        // Placed where the ink of the two meets.
        let lap = try #require(AskMotion.Lap(remembered))
        #expect(AskMotion.inkMeets(lap.ink("trash", at: 0.6), lap.ink("lid", at: 0.6)))
    }

    @Test("A mend that moves the hit to another moment keeps it on the key that arrives where the hit was, not on one that only stays there")
    func movedInTime() throws {
        // Run 20261110-105702: the mend slowed the lap and wrote the hit at 0.7.
        let later = try Self.ball(#"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.3,"value":{"x":0,"y":0}},{"seconds":0.7,"value":{"x":-6,"y":3}},{"seconds":0.8,"value":{"x":-7,"y":1}},{"seconds":1,"value":{"x":-7,"y":6}},{"seconds":1.55,"value":{"x":-7,"y":6}},{"seconds":1.6,"value":{"x":0,"y":0}}]"#)
        #expect(Self.touches(AskMotion.touchesKept([try Self.ball(Self.first), later])[1]) == [0.7: "$1/lid", 1: "$1/can"])
        // Two keys arriving at that place: nothing says which, so neither.
        let twice = try Self.ball(#"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.7,"value":{"x":-6,"y":3}},{"seconds":0.8,"value":{"x":0,"y":0}},{"seconds":1.0,"value":{"x":-6,"y":3}},{"seconds":1.6,"value":{"x":0,"y":0}}]"#)
        #expect(Self.touches(AskMotion.touchesKept([try Self.ball(Self.first), twice])[1]).isEmpty)
    }

    /// A ball with no stroke and a bar seen at an angle: their boxes overlap
    /// while their ink is two units apart (the trash's hop at 0.8 s, run
    /// 20261110-105702, read as touching the lid and never did).
    static let tilted = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><g id="trash"><circle id="trash-ball" cx="20" cy="4" r="1.5" fill="#1D1D1F" stroke="none"/></g><g id="lid"><line id="lid-bar" x1="5" y1="7" x2="19" y2="7"/><line id="lid-knob" x1="12" y1="7" x2="12" y2="5"/></g><g id="can"><path d="M6 9 L7 20 L17 20 L18 9"/></g></svg>"##

    static func tiltedSteps(hit: String) throws -> [AskStep] {
        let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(Self.tilted)])
        let lid = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/lid","property":"rotation","pivot":{"x":5,"y":7},"keys":[{"seconds":0,"value":0},{"seconds":0.3,"value":-40},{"seconds":1,"value":-40},{"seconds":1.2,"value":0},{"seconds":1.6,"value":0}]}"#))
        let ball = try Self.ball(#"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.3,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"\#(hit)","value":{"x":-7,"y":1}},{"seconds":1,"value":{"x":-7,"y":6}},{"seconds":1.6,"value":{"x":0,"y":0}}]"#, replace: false)
        return [drawing, lid, ball]
    }

    @Test("Touching is read off the ink: boxes that overlap with the ink apart are not touching, and the hit is moved until the ink meets")
    func inkNotBoxes() throws {
        let steps = try Self.tiltedSteps(hit: "$1/lid")
        let before = try #require(AskMotion.Lap(steps))
        // The boxes say they meet; the ink says they do not.
        #expect(AskMotion.meet(try #require(before.outline("trash", at: 0.8)), try #require(before.outline("lid", at: 0.8))))
        #expect(!AskMotion.inkMeets(before.ink("trash", at: 0.8), before.ink("lid", at: 0.8)))
        let placed = AskMotion.touchesPlaced(steps)
        let after = try #require(AskMotion.Lap(placed))
        #expect(AskMotion.inkMeets(after.ink("trash", at: 0.8), after.ink("lid", at: 0.8)))
        // Moved up and to the left, towards the bar, and only as far as it takes.
        let key = try #require((placed[2].arguments["keys"]?.arrayValue ?? []).first { $0["seconds"]?.doubleValue == 0.8 })
        let x = try #require(key["value"]?["x"]?.doubleValue), y = try #require(key["value"]?["y"]?.doubleValue)
        #expect(x < -7 && y < 1)
        #expect(hypot(x + 7, y - 1) < 3)
    }

    @Test("A part that touches another and then goes on through it is sent back with when; one that comes away is not")
    func throughWhatItTouches() throws {
        // Run 20261110-112435: the trash met the lid and then dropped
        // straight through it while the lid stood half open.
        // Hidden in the can before it goes back to where it starts.
        let hide = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/trash","property":"opacity","keys":[{"seconds":0,"value":100},{"seconds":1.0,"value":100},{"seconds":1.05,"value":0},{"seconds":1.55,"value":0},{"seconds":1.6,"value":100}]}"#))
        let steps = try Self.tiltedSteps(hit: "$1/lid") + [hide]
        let away = AskMotionCheck.problems(steps).joined(separator: " ")
        #expect(!away.contains("passes through"), "\(away)")
        let up = try Self.ball(#"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.3,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"$1/lid","value":{"x":-7,"y":1}},{"seconds":1.1,"value":{"x":-8,"y":-7}},{"seconds":1.6,"value":{"x":0,"y":0}}]"#, replace: false)
        let through = AskMotionCheck.problems([steps[0], steps[1], up]).joined(separator: " ")
        #expect(through.contains("trash passes through lid from 0."), "\(through)")
        // Into what stays still is in behind its front: never asked about.
        let into = try Self.ball(#"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.3,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"$1/can","value":{"x":-7,"y":6}},{"seconds":1.0,"value":{"x":-7,"y":12}},{"seconds":1.6,"value":{"x":0,"y":0}}]"#, replace: false)
        #expect(!AskMotionCheck.problems([steps[0], steps[1], into, hide]).joined().contains("passes through can"))
        // Nothing said it touches: not this check's business.
        let unsaid = try Self.ball(#"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.3,"value":{"x":0,"y":0}},{"seconds":0.8,"value":{"x":-7,"y":1}},{"seconds":1.1,"value":{"x":-8,"y":-7}},{"seconds":1.6,"value":{"x":0,"y":0}}]"#, replace: false)
        #expect(!AskMotionCheck.problems([steps[0], steps[1], unsaid]).joined().contains("passes through"))
    }

    @Test("The ink of a round part is round and a line's is as thick as its stroke")
    func inkShapes() throws {
        let lap = try #require(AskMotion.Lap(try Self.tiltedSteps(hit: "$1/lid")))
        let ball = lap.ink("trash", at: 0)
        #expect(ball.count == 1)
        let xs = ball[0].map(\.x), ys = ball[0].map(\.y)
        // r 1.5 about 20,4, no stroke.
        #expect(abs((xs.min() ?? 0) - 18.5) < 0.05 && abs((xs.max() ?? 0) - 21.5) < 0.05)
        #expect(abs((ys.min() ?? 0) - 2.5) < 0.05 && abs((ys.max() ?? 0) - 5.5) < 0.05)
        // The bar at rest: y 7 with a stroke of 2 is y 6 to 8; the knob reaches 4.
        let lid = lap.ink("lid", at: 0)
        #expect(lid.count == 2)
        let bar = try #require(lid.first)
        #expect(abs((bar.map(\.y).min() ?? 0) - 6) < 0.05 && abs((bar.map(\.y).max() ?? 0) - 8) < 0.05)
    }
}
