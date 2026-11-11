import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The user's own trash story (task
/// `an-animated-icon-told-as-a-little-story-moves-th`, run 20261110-121442):
/// the model's last plan as it was mended, step for step. The trash faded in
/// beside the open lid, met its underside at 0.8 s and then moved back up
/// into it as the lid dipped, so neither "thrown in" nor "bouncing off the
/// lid" was ever seen. What is hit sends the part away from it, and what
/// appears as it sets off to hit something comes in from outside the frame.
@Suite("Ask's story icons: what is thrown comes in from outside and bounces away from what it hits")
struct AskMotionBounceTests {

    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }
    static let bin = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><g id="bin"><path id="body" d="M6 9 L7 20 Q7 21 8 21 L16 21 Q17 21 17 20 L18 9"/><line id="rib-left" x1="10" y1="12" x2="10.5" y2="18"/><line id="rib-right" x1="14" y1="12" x2="13.5" y2="18"/></g><g id="lid"><line id="lid-bar" x1="5" y1="8" x2="19" y2="8"/><line id="lid-knob" x1="11" y1="6" x2="13" y2="6"/></g><g id="trash"><path id="crumple" d="M19 3 L21 4 L20 6 L18 5 Z" fill="#1D1D1F" stroke="none"/></g></svg>"##
    static let trashKeys = #"[{"seconds":0,"value":{"x":0,"y":0}},{"curve":"Ease in","seconds":0.5,"value":{"x":0,"y":0}},{"curve":"Ease out","seconds":0.8,"touches":"$1/lid","value":{"x":-6,"y":2}},{"curve":"Ease in","seconds":1,"value":{"x":-6,"y":0}},{"curve":"Ease in","seconds":1.2,"touches":"$1/bin","value":{"x":-6,"y":4}},{"seconds":1.3,"value":{"x":-6,"y":4}},{"seconds":1.5,"value":{"x":0,"y":0}}]"#
    static let fadeKeys = #"[{"seconds":0,"value":0},{"curve":"Ease out","seconds":0.5,"value":0},{"curve":"Ease in","seconds":0.6,"value":100},{"curve":"Ease in","seconds":1.2,"value":100},{"seconds":1.3,"value":0},{"seconds":1.5,"value":0}]"#

    static func steps(trash: String = trashKeys, fade: String? = fadeKeys) throws -> [AskStep] {
        var steps = [AskStep(tool: "add_drawing", arguments: ["icon": true, "subject": "trash bin", "svg": .string(bin)]),
                     AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(1.5)]),
                     AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease out","seconds":0.2,"value":0},{"curve":"Ease in out","seconds":0.5,"value":-40},{"curve":"Ease in out","seconds":0.8,"value":-40},{"curve":"Ease out back","seconds":1,"value":-25},{"curve":"Ease in out","seconds":1.2,"value":-25},{"curve":"Ease out back","seconds":1.4,"value":0},{"seconds":1.5,"value":0}],"layer":"$1/lid","pivot":{"x":5,"y":8},"property":"rotation","replace":true}"#))]
        if let fade {
            steps.append(AskStep(tool: "set_keys", arguments: try args(#"{"keys":\#(fade),"layer":"$1/trash","property":"opacity","replace":true}"#)))
        }
        steps.append(AskStep(tool: "set_keys", arguments: try args(#"{"keys":\#(trash),"layer":"$1/trash","property":"position","replace":true}"#)))
        return steps
    }

    static func trash(_ steps: [AskStep], at seconds: Double) -> CGPoint? {
        guard let step = steps.last(where: { $0.arguments["layer"]?.stringValue == "$1/trash" && $0.arguments["property"]?.stringValue == "position" }),
              let key = (step.arguments["keys"]?.arrayValue ?? []).first(where: { abs(($0["seconds"]?.doubleValue ?? -1) - seconds) < 0.0005 }),
              let x = key["value"]?["x"]?.doubleValue, let y = key["value"]?["y"]?.doubleValue else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// Whether the trash's ink goes deeper into the lid's than a touch, while both are seen, from `from` to `to`.
    static func through(_ steps: [AskStep], from: Double, to: Double) throws -> Bool {
        let lap = try #require(AskMotion.Lap(steps))
        var moment = from + 0.02
        while moment <= to {
            if lap.placed("trash", at: moment)?.seen ?? true,
               AskMotion.inkMeets(lap.ink("trash", at: moment), lap.ink("lid", at: moment), within: -AskMotion.passesThrough) { return true }
            moment += 0.02
        }
        return false
    }

    @Test("After it hits the dipping lid the trash comes away from it, mirrored off the face it struck, and never goes through")
    func bouncesAway() throws {
        let raw = try Self.steps()
        let placed = AskMotion.touchesPlaced(raw)
        let hit = try #require(Self.trash(placed, at: 0.8))
        let after = try #require(Self.trash(placed, at: 1.0))
        #expect(after != CGPoint(x: -6, y: 0))
        #expect(try !Self.through(placed, from: 0.8, to: 1.2))
        // Off the face it struck from below: down, away from the lid, into the can.
        #expect(after.y - hit.y > 2)
        // And seen apart from the lid by then, though the lid dips after it.
        let lap = try #require(AskMotion.Lap(placed))
        #expect(!AskMotion.inkMeets(lap.ink("trash", at: 1.0), lap.ink("lid", at: 1.0), within: AskMotion.bounceGap * 24))
        // Far enough to be seen at icon size: an eighth of the drawing.
        #expect(hypot(after.x - hit.x, after.y - hit.y) >= 24 * AskMotion.leastBounce - 0.01)
        // The check no longer sends the model back about it.
        #expect(!AskMotionCheck.problems(raw).contains { $0.contains("passes through") })
    }

    @Test("A part that comes away already, stays where it hit, or hits something that stays still keeps its keys")
    func leftAlone() throws {
        // Comes away: up and out to the right after the hit.
        let away = #"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"$1/lid","value":{"x":-6,"y":2}},{"seconds":1.0,"value":{"x":2,"y":4}},{"seconds":1.5,"value":{"x":0,"y":0}}]"#
        let stays = #"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"$1/lid","value":{"x":-6,"y":2}},{"seconds":1.2,"value":{"x":-6,"y":2}},{"seconds":1.5,"value":{"x":0,"y":0}}]"#
        for keys in [away, stays] {
            let placed = AskMotion.touchesPlaced(try Self.steps(trash: keys))
            let hit = try #require(Self.trash(placed, at: 0.8))
            let next = try #require(Self.trash(placed, at: keys == away ? 1.0 : 1.2))
            #expect(next == (keys == away ? CGPoint(x: 2, y: 4) : hit))
        }
        // Into the bin, which stays still: going in behind its front is meant.
        let into = #"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"$1/bin","value":{"x":-6,"y":4}},{"seconds":1.0,"value":{"x":-6,"y":10}},{"seconds":1.5,"value":{"x":0,"y":0}}]"#
        #expect(Self.trash(AskMotion.touchesPlaced(try Self.steps(trash: into)), at: 1.0) == CGPoint(x: -6, y: 10))
    }

    @Test("What fades in as it sets off to hit something sets off from outside the frame, on the same line, and still hits where planned")
    func thrownFromOutside() throws {
        let landed = AskMotion.planned(try Self.steps())
        let lap = try #require(AskMotion.Lap(landed))
        let view = try #require(lap.art.viewBox)
        // At 0.5 s, as it sets off, it is wholly off the frame.
        let quad = try #require(lap.placed("trash", at: 0.5)?.quad)
        let box = quad.dropFirst().reduce(CGRect(origin: quad[0], size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        #expect(box.minX >= view.maxX - 0.01)
        // On the line it was planned on: from where it was drawn towards the hit.
        let start = try #require(Self.trash(landed, at: 0.5)), hit = try #require(Self.trash(landed, at: 0.8))
        #expect(start.x > 6)
        let cross = (start.x - 0) * (hit.y - 0) - (start.y - 0) * (hit.x - 0)
        #expect(abs(cross) / hypot(hit.x, hit.y) < 0.5)
        // Seen in the frame before it hits.
        #expect(lap.placed("trash", at: 0.7)?.seen == true)
        #expect(lap.placed("trash", at: 0.7).map { q in q.quad.contains { view.contains($0) } } == true)
    }

    @Test("A part seen before it sets off, or one that sets off to hit nothing, starts where it was drawn")
    func notThrown() throws {
        // Seen the whole lap: it was in view all along.
        let always = #"[{"seconds":0,"value":100},{"seconds":1.5,"value":100}]"#
        #expect(Self.trash(AskMotion.planned(try Self.steps(fade: always)), at: 0.5) == CGPoint(x: 0, y: 0))
        // Fades in and drifts a little, meeting nothing: a puff, not a throw.
        let drift = #"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"value":{"x":0,"y":-2}},{"seconds":1.3,"value":{"x":0,"y":-2}},{"seconds":1.5,"value":{"x":0,"y":0}}]"#
        #expect(Self.trash(AskMotion.planned(try Self.steps(trash: drift)), at: 0.5) == CGPoint(x: 0, y: 0))
    }

    @Test("Two keys in a row touching the lid are one contact: the second is brought out of the lid onto it, and the trash comes away only after it")
    func contactRun() throws {
        // Run 20261110-141555: the model's mend keyed 0.8 and 0.95 s as
        // touching the lid, the second two units inside it, then into the bin.
        let run = #"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"lid","value":{"x":-6,"y":2}},{"seconds":0.95,"touches":"lid","value":{"x":-7,"y":0}},{"seconds":1.1,"touches":"bin","value":{"x":-7,"y":4}},{"seconds":1.2,"value":{"x":-7,"y":4}},{"seconds":1.5,"value":{"x":0,"y":0}}]"#
        let placed = AskMotion.touchesPlaced(try Self.steps(trash: run))
        let lap = try #require(AskMotion.Lap(placed))
        // Both keys meet the lid's ink, neither is buried in it.
        for moment in [0.8, 0.95] {
            #expect(AskMotion.inkMeets(lap.ink("trash", at: moment), lap.ink("lid", at: moment)))
            #expect(!AskMotion.inkMeets(lap.ink("trash", at: moment), lap.ink("lid", at: moment), within: -AskMotion.passesThrough))
        }
        // Nothing passes through the lid from the first touch to the drop, and it is apart by then.
        #expect(try !Self.through(placed, from: 0.8, to: 1.2))
        // Apart on a bounce key of its own before the drop the model planned
        // into the bin, which stays where it was (AskMotionBounceThenInTests).
        let keys = AskMotionCheck.timed(try #require(placed.last))
        let bounce = try #require(keys.first { $0.seconds > 0.95 + 0.0005 && $0.seconds < 1.1 - 0.0005 }, "\(keys)")
        #expect(!AskMotion.inkMeets(lap.ink("trash", at: bounce.seconds), lap.ink("lid", at: bounce.seconds), within: AskMotion.bounceGap * 24))
        #expect(Self.trash(placed, at: 1.1) == CGPoint(x: -7, y: 4))
        #expect(!AskMotionCheck.problems(try Self.steps(trash: run)).contains { $0.contains("passes through") })
    }

    @Test("A key buried in something that stays still is left where it is: going into the bin is meant")
    func buriedInStill() throws {
        let into = #"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"bin","value":{"x":-7,"y":10}},{"seconds":1.5,"value":{"x":0,"y":0}}]"#
        #expect(Self.trash(AskMotion.touchesPlaced(try Self.steps(trash: into)), at: 0.8) == CGPoint(x: -7, y: 10))
    }
}
