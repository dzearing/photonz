import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// A lap's long stillness shows the icon whole (`AskMotion.restsWhole`). On
/// the climb set of 2026-11-15 (run 20261115-005857-ask) four plans of twelve
/// rested for a third to a half of their lap with a part gone: a mark that
/// had dropped and faded, waves undrawn, a burst's pieces faded. Sixteen
/// frames of a lap then showed the thing incomplete or empty in five to eight
/// of them. Parts here are named by their role only.
@Suite("Ask's moving icons: a long rest shows the icon whole")
struct AskMotionRestsWholeTests {
    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }

    static let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path id="base" d="M4 16 L4 20 L20 20 L20 16"/><g id="mark"><path id="mark-line" d="M12 4 L12 12 M8 9 L12 13 L16 9"/></g></svg>"##

    static func lap(_ steps: [AskStep]) -> Double? {
        steps.last { $0.tool == "set_timing" }?.arguments["seconds"]?.doubleValue
    }

    static func keyed(_ steps: [AskStep], _ property: String) -> AskStep? {
        steps.last { $0.tool == "set_keys" && $0.arguments["property"]?.stringValue == property }
    }

    static func times(_ step: AskStep?) -> [Double] {
        (step?.arguments["keys"]?.arrayValue ?? []).compactMap { $0["seconds"]?.doubleValue }
    }

    /// The mark pops in at 0.2 s, holds whole 0.4 to 0.8 s, falls and fades
    /// by 1.0 s, then the lap waits with it gone until 2.2 s.
    static func popThenGone(lap: Double = 2.2) throws -> [AskStep] {
        [AskStep(tool: "add_drawing", arguments: ["icon": true, "svg": .string(svg)]),
         AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(lap)]),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":0},{"curve":"Ease out back","seconds":0.2,"value":0},{"seconds":0.4,"value":100},{"curve":"Ease in","seconds":0.8,"value":100},{"curve":"Hold","seconds":1.0,"value":100},{"seconds":\#(lap),"value":0}],"layer":"$1/mark","property":"scale"}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":0},{"seconds":0.2,"value":0},{"seconds":0.3,"value":100},{"seconds":0.8,"value":100},{"seconds":1.0,"value":0},{"seconds":\#(lap),"value":0}],"layer":"$1/mark","property":"opacity"}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"curve":"Ease in","seconds":0.8,"value":{"x":0,"y":0}},{"seconds":1.0,"value":{"x":0,"y":4}},{"curve":"Hold","seconds":1.1,"value":{"x":0,"y":4}},{"seconds":\#(lap),"value":{"x":0,"y":0}}],"layer":"$1/mark","property":"position"}"#))]
    }

    @Test("A long rest with a part gone is cut short and the time goes to the rest where all is seen")
    func timeMovesToTheWholeRest() throws {
        let before = try Self.popThenGone()
        let landed = AskMotion.restsWhole(before)
        // The lap keeps its length: the time is moved, not taken away.
        #expect(Self.lap(landed) == 2.2)
        // The gone stretch (1.1 to 2.2 and 0 to 0.2, joined over the loop)
        // is down to the most a gone rest may last.
        let opacity = try #require(Self.keyed(landed, "opacity"))
        var gone = 0.0
        var seconds = 0.0
        while seconds < 2.2 {
            if (AskMotionCheck.played(of: opacity, at: seconds)?.doubleValue ?? 100) < 10 { gone += 0.01 }
            seconds += 0.01
        }
        #expect(gone <= AskMotion.goneRest + 0.25, "gone for \(gone) s of 2.2")
        // The whole rest (0.4 to 0.8 s) is longer by what the gone one lost.
        let scale = try #require(Self.keyed(landed, "scale"))
        let position = try #require(Self.keyed(landed, "position"))
        var whole = 0.0
        seconds = 0
        while seconds < 2.2 {
            let shown = (AskMotionCheck.played(of: opacity, at: seconds)?.doubleValue ?? 0) >= 99
                && (AskMotionCheck.played(of: scale, at: seconds)?.doubleValue ?? 0) >= 99
                && (AskMotionCheck.played(of: position, at: seconds)?["y"]?.doubleValue ?? 1) == 0
            if shown { whole += 0.01 }
            seconds += 0.01
        }
        #expect(whole >= 1.4, "whole for \(whole) s of 2.2")
        // Every value still ends the lap where it began.
        for step in landed where step.tool == "set_keys" {
            #expect(Self.times(step).last == 2.2)
        }
        // The motion itself plays at the same speed: the fall still takes 0.2 s.
        let fall = Self.times(position)
        #expect(abs((fall[2] - fall[1]) - 0.2) < 0.0005, "\(fall)")
    }

    @Test("With no rest where all is seen, the gone rest is cut short and the lap with it")
    func lapShrinksWithNoWholeRest() throws {
        // As above but the mark never holds still while seen.
        var steps = try Self.popThenGone()
        steps[2] = AskStep(tool: "set_keys", arguments: try Self.args(#"{"keys":[{"seconds":0,"value":0},{"curve":"Ease out back","seconds":0.2,"value":0},{"seconds":0.5,"value":100},{"curve":"Hold","seconds":1.0,"value":110},{"seconds":2.2,"value":0}],"layer":"$1/mark","property":"scale"}"#))
        steps[3] = AskStep(tool: "set_keys", arguments: try Self.args(#"{"keys":[{"seconds":0,"value":0},{"seconds":0.2,"value":0},{"seconds":0.3,"value":100},{"seconds":0.9,"value":100},{"seconds":1.0,"value":0},{"seconds":2.2,"value":0}],"layer":"$1/mark","property":"opacity"}"#))
        steps[4] = AskStep(tool: "set_keys", arguments: try Self.args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"curve":"Ease in","seconds":0.3,"value":{"x":0,"y":0}},{"seconds":1.0,"value":{"x":0,"y":4}},{"curve":"Hold","seconds":1.1,"value":{"x":0,"y":4}},{"seconds":2.2,"value":{"x":0,"y":0}}],"layer":"$1/mark","property":"position"}"#))
        let landed = AskMotion.restsWhole(steps)
        let lap = try #require(Self.lap(landed))
        #expect(lap < 2.2 - 0.5, "\(lap)")
        #expect(lap >= AskMotion.shortestRestedLap - 0.0005)
        for step in landed where step.tool == "set_keys" {
            #expect(Self.times(step).last == lap)
        }
    }

    @Test("A lap whose long rest shows every part is left as it is")
    func wholeRestUntouched() throws {
        let steps: [AskStep] = [
            AskStep(tool: "add_drawing", arguments: ["icon": true, "svg": .string(Self.svg)]),
            AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(2)]),
            AskStep(tool: "set_keys", arguments: try Self.args(#"{"keys":[{"seconds":0,"value":0},{"seconds":0.15,"value":-10},{"seconds":0.3,"value":10},{"seconds":0.45,"value":0},{"seconds":2,"value":0}],"layer":"$1/mark","pivot":{"x":12,"y":4},"property":"rotation"}"#)),
        ]
        #expect(AskMotion.restsWhole(steps) == steps)
    }

    @Test("A short gone rest is left as it is")
    func shortGoneRestUntouched() throws {
        let steps = try Self.popThenGone(lap: 1.2)
        #expect(AskMotion.restsWhole(steps) == steps)
    }

    @Test("A part waiting outside the frame is gone too")
    func outsideTheFrameIsGone() throws {
        let steps: [AskStep] = [
            AskStep(tool: "add_drawing", arguments: ["icon": true, "svg": .string(Self.svg)]),
            AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(2.4)]),
            AskStep(tool: "set_keys", arguments: try Self.args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"curve":"Ease in","seconds":0.3,"value":{"x":0,"y":0}},{"curve":"Hold","seconds":0.7,"value":{"x":0,"y":-20}},{"curve":"Ease out","seconds":2.1,"value":{"x":0,"y":10}},{"seconds":2.4,"value":{"x":0,"y":0}}],"layer":"$1/mark","property":"position"}"#)),
        ]
        let landed = AskMotion.restsWhole(steps)
        let keys = Self.times(Self.keyed(landed, "position"))
        // Away from 0.7 to 2.1 s (1.4 s) before; now no longer than a gone rest.
        let away = keys[3] - keys[2]
        #expect(away <= AskMotion.goneRest + 0.0005, "\(keys)")
    }
}

/// A mark that fades as it travels stays inside the frame while it can be
/// seen (`AskMotion.marksStayIn`). On the climb set of 2026-11-15 (run
/// 20261115-005857-ask) two small marks beside a swinging part slid six units
/// sideways while fading, past the frame's edge: "cut off by the right edge"
/// in the judge's notes.
@Suite("Ask's moving icons: a fading mark stays inside the frame while seen")
struct AskMotionMarksStayInTests {
    static let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path id="body" d="M5 5 L15 5 L15 17 L5 17 Z"/><path id="mark" d="M18 9 C19 10.5 19 12.5 18 14"/></svg>"##

    static func steps(travel: Double) throws -> [AskStep] {
        let args = AskMotionRestsWholeTests.args
        return [AskStep(tool: "add_drawing", arguments: ["icon": true, "svg": .string(svg)]),
                AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(1.2)]),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":0},{"seconds":0.2,"value":100},{"seconds":0.6,"value":0},{"seconds":1.2,"value":0}],"layer":"$1/mark","property":"opacity"}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.2,"value":{"x":0,"y":0}},{"seconds":0.6,"value":{"x":\#(travel),"y":0}},{"curve":"Hold","seconds":0.7,"value":{"x":\#(travel),"y":0}},{"seconds":1.2,"value":{"x":0,"y":0}}],"layer":"$1/mark","property":"position"}"#))]
    }

    static func box(at seconds: Double, in steps: [AskStep]) throws -> (seen: Double, right: Double) {
        let opacity = try #require(steps.last { $0.arguments["property"]?.stringValue == "opacity" })
        let position = try #require(steps.last { $0.arguments["property"]?.stringValue == "position" })
        let seen = AskMotionCheck.played(of: opacity, at: seconds)?.doubleValue ?? 0
        let dx = AskMotionCheck.played(of: position, at: seconds)?["x"]?.doubleValue ?? 0
        guard case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true) else { return (seen, .infinity) }
        let own = try #require(AskMotionCheck.box(of: "mark", in: art))
        return (seen, Double(own.maxX) + dx)
    }

    @Test("A mark sliding past the edge as it fades slides less, and is inside the frame whenever it is seen")
    func pulledIn() throws {
        let landed = AskMotion.marksStayIn(try Self.steps(travel: 7))
        var seconds = 0.0
        while seconds < 1.2 {
            let (seen, right) = try Self.box(at: seconds, in: landed)
            if seen >= 10 { #expect(right <= 24 + 0.01, "at \(seconds) s seen \(seen) right edge \(right)") }
            seconds += 0.02
        }
        // It still travels: pulled in, not stopped.
        let position = try #require(landed.last { $0.arguments["property"]?.stringValue == "position" })
        let far = AskMotionCheck.timed(position).compactMap { $0.value["x"]?.doubleValue }.max() ?? 0
        #expect(far > 1)
        #expect(far < 7)
        // Its timing is as planned.
        #expect(AskMotionCheck.timed(position).map(\.seconds) == [0, 0.2, 0.6, 0.7, 1.2])
    }

    @Test("A mark that stays inside the frame is left as it is")
    func insideUntouched() throws {
        let steps = try Self.steps(travel: 1.5)
        #expect(AskMotion.marksStayIn(steps) == steps)
    }

    @Test("A part that never fades is not a mark: leaving the frame is left to the rules for leaving")
    func notAMark() throws {
        var steps = try Self.steps(travel: 7)
        steps.remove(at: 2)
        #expect(AskMotion.marksStayIn(steps) == steps)
    }
}
