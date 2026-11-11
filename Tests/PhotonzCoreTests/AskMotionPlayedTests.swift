import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Where Ask's contact checks read a part is where the icon plays it: on each
/// key's curve, not in a straight line between keys. On 2026-11-11 the user's
/// trash was kept clear of a lid closing on Ease out back, read as -26 degrees
/// at 1.0 s; the exported icon played it at about -14, swept through the
/// trash, and the judge saw the trash "pass straight through the lid" in
/// every look (run 20261111-064936).
@Suite("Ask's story icons: parts are read where the icon plays them, on their curves")
struct AskMotionPlayedTests {

    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }

    static func turn(_ keys: String) throws -> AskStep {
        AskStep(tool: "set_keys", arguments: try args(#"{"layer":"$1/lid","property":"rotation","keys":\#(keys)}"#))
    }

    @Test("A run on Ease out back is read on that curve, matching the played motion")
    func readsTheCurve() throws {
        let step = try Self.turn(#"[{"seconds":0.95,"value":-30,"curve":"Ease out back"},{"seconds":1.3,"value":0}]"#)
        let played = try #require(AskMotionCheck.played(of: step, at: 1.0)?.doubleValue)
        let share = EasingCurve.easeOutBack.value(at: 0.05 / 0.35)
        #expect(abs(played - (-30 + 30 * share)) < 0.001)
        // Far nearer shut than a straight line would have it.
        #expect(played > -16)
        // Past the end it overshoots and settles, as the icon plays it.
        let late = try #require(AskMotionCheck.played(of: step, at: 1.25)?.doubleValue)
        #expect(late > 0)
    }

    @Test("A key with no curve runs Ease in out, a Hold stands, positions ease on both axes")
    func defaultsAndHolds() throws {
        let plain = try Self.turn(#"[{"seconds":0,"value":0},{"seconds":1,"value":100}]"#)
        #expect(abs((AskMotionCheck.played(of: plain, at: 0.25)?.doubleValue ?? -1) - 100 * EasingCurve.easeInOut.value(at: 0.25)) < 0.001)
        let held = try Self.turn(#"[{"seconds":0,"value":0,"curve":"Hold"},{"seconds":1,"value":100}]"#)
        #expect(AskMotionCheck.played(of: held, at: 0.9)?.doubleValue == 0)
        let moves = AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/ball","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0},"curve":"Ease in"},{"seconds":1,"value":{"x":10,"y":-4}}]}"#))
        let at = try #require(AskMotionCheck.played(of: moves, at: 0.5))
        let share = EasingCurve.easeIn.value(at: 0.5)
        #expect(abs((at["x"]?.doubleValue ?? 0) - 10 * share) < 0.001)
        #expect(abs((at["y"]?.doubleValue ?? 0) + 4 * share) < 0.001)
    }

    @Test("The lap reads a part where it plays: the lid's ink on its curve")
    func lapPlays() throws {
        let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><g id="lid"><line id="bar" x1="5" y1="8" x2="19" y2="8"/></g></svg>"##
        let steps = [AskStep(tool: "add_drawing", arguments: ["icon": true, "svg": .string(svg)]),
                     AskStep(tool: "set_keys", arguments: try Self.args(#"{"layer":"$1/lid","property":"rotation","pivot":{"x":5,"y":8},"keys":[{"seconds":0.95,"value":-30,"curve":"Ease out back"},{"seconds":1.3,"value":0}]}"#))]
        let lap = try #require(AskMotion.Lap(steps))
        let degrees = try #require(lap.value("lid", .rotation, at: 1.0)?.doubleValue)
        #expect(abs(degrees - (AskMotionCheck.played(of: steps[1], at: 1.0)?.doubleValue ?? 0)) < 0.001)
    }
}
