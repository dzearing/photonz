import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The story eval's checkbox of 2026-11-12 (run 20261112-095935-ask, task
/// `an-animated-icon-told-as-a-little-story-moves-th`, pass sixteen), its
/// plan as the model left it: the tick draws itself by 0.45 s and holds
/// drawn to the end of a 1.1 s lap, so every lap snapped from a ticked box
/// to an empty one ("no hold or fade", nine looks of nine; the rule check
/// read a jump at the loop of 4.9).
enum AskMotionStartsOverCheckbox {
    static let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect id="box" x="3" y="3" width="18" height="18" rx="4"/><path id="tick" d="M7 12.5 L10.5 16 L17 8"/></svg>"##

    static func steps(lap: Double = 1.1) throws -> [AskStep] {
        let args = AskMotionBounceSeenTests.args
        return [AskStep(tool: "add_drawing", arguments: ["icon": true, "subject": "checkbox with tick", "svg": .string(svg)]),
                AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(lap)]),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Ease in out","seconds":0,"value":0},{"curve":"Hold","seconds":0.45,"value":100}],"layer":"$1/tick","property":"trimEnd"}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Hold","seconds":0,"value":{"x":0,"y":0}},{"curve":"Ease in","seconds":0.45,"value":{"x":0,"y":0}},{"curve":"Ease out","seconds":0.55,"value":{"x":0,"y":1}},{"curve":"Ease in","seconds":0.75,"value":{"x":0,"y":-3}},{"curve":"Ease out back","seconds":0.9,"value":{"x":0,"y":0}},{"curve":"Ease out","seconds":1,"value":{"x":0,"y":-0.5}},{"seconds":1.1,"value":{"x":0,"y":0}}],"layer":"$1/tick","property":"position"}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":100},{"seconds":0.45,"value":100},{"seconds":0.55,"value":100},{"seconds":0.75,"value":110},{"seconds":0.9,"value":85},{"seconds":1,"value":105},{"seconds":1.1,"value":100}],"layer":"$1/tick","property":"scale"}"#))]
    }
}

@Suite("Ask's moving icons: a line that drew itself starts over unseen")
struct AskMotionStartsOverTests {
    static func lap(_ steps: [AskStep]) -> Double? {
        steps.last { $0.tool == "set_timing" }?.arguments["seconds"]?.doubleValue
    }

    static func step(_ steps: [AskStep], _ property: String) -> AskStep? {
        steps.last { $0.tool == "set_keys" && $0.arguments["layer"]?.stringValue == "$1/tick" && $0.arguments["property"]?.stringValue == property }
    }

    @Test("The tick holds drawn after its bounce, fades out, and is undrawn only once it cannot be seen")
    func holdsThenFades() throws {
        let landed = AskMotion.startsOver(try AskMotionStartsOverCheckbox.steps())
        let lap = try #require(Self.lap(landed))
        let fade = try #require(Self.step(landed, "opacity"), "no fade: \(landed.map(\.arguments))")
        let settled = 1.1
        // Held drawn and seen a while after the last move, then gone by the lap's end.
        #expect((AskMotionCheck.value(of: fade, at: settled + AskMotion.startOverHold - 0.01)?.doubleValue ?? 0) >= 99)
        #expect((AskMotionCheck.value(of: fade, at: lap)?.doubleValue ?? 100) <= 0.5)
        // A fade, not a cut: half way through it the tick is part seen.
        let middle = AskMotionCheck.value(of: fade, at: lap - AskMotion.startOverFade / 2)?.doubleValue ?? 0
        #expect(middle > 10 && middle < 90, "\(middle)")
        // At the start of the next lap it is undrawn, so showing again is not seen.
        let trim = try #require(Self.step(landed, "trimEnd"))
        #expect((AskMotionCheck.value(of: trim, at: 0)?.doubleValue ?? 100) == 0)
        #expect(lap <= AskMotion.longestStory + 0.0005)
        // Nothing else changed: the bounce plays as planned.
        #expect(Self.step(landed, "position")?.arguments == Self.step(try AskMotionStartsOverCheckbox.steps(), "position")?.arguments)
    }

    @Test("Stillness already at the end of the lap is used before the lap grows")
    func usesStillness() throws {
        let landed = AskMotion.startsOver(try AskMotionStartsOverCheckbox.steps(lap: 2.2))
        #expect(Self.lap(landed) == 2.2)
        #expect(Self.step(landed, "opacity") != nil)
    }

    @Test("A line that undraws itself, or fades already, or a lap that plays once, is left alone")
    func leftAlone() throws {
        var once = try AskMotionStartsOverCheckbox.steps()
        once[1] = AskStep(tool: "set_timing", arguments: ["loop": false, "seconds": .number(1.1)])
        #expect(AskMotion.startsOver(once).map(\.arguments) == once.map(\.arguments))
        var undraws = try AskMotionStartsOverCheckbox.steps()
        undraws[2] = AskStep(tool: "set_keys", arguments: try AskMotionBounceSeenTests.args(#"{"keys":[{"seconds":0,"value":0},{"seconds":0.45,"value":100},{"seconds":1.1,"value":0}],"layer":"$1/tick","property":"trimEnd"}"#))
        #expect(AskMotion.startsOver(undraws).map(\.arguments) == undraws.map(\.arguments))
        var fades = try AskMotionStartsOverCheckbox.steps()
        fades.append(AskStep(tool: "set_keys", arguments: try AskMotionBounceSeenTests.args(#"{"keys":[{"seconds":0,"value":100},{"seconds":0.9,"value":100},{"seconds":1.1,"value":0}],"layer":"$1/tick","property":"opacity"}"#)))
        #expect(AskMotion.startsOver(fades).map(\.arguments) == fades.map(\.arguments))
    }

    @Test("The whole landing keeps it")
    func landed() throws {
        let landed = AskMotion.planned(try AskMotionStartsOverCheckbox.steps())
        #expect(Self.step(landed, "opacity") != nil)
        #expect((Self.lap(landed) ?? 0) > 1.1)
    }
}
