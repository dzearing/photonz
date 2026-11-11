import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The user's trash story, walked on 2026-11-11 at 13:50 (task
/// `an-animated-icon-told-as-a-little-story-moves-th`), the plan exactly as the
/// model left it: the trash hits the lid at 0.9 s, hops at 1.05 s and lands in
/// the can at 1.2 s. The bounce, mirrored off the lid's face, re-aimed the
/// hop down and to the right, through the can's right wall: from 1.0 to 1.1 s
/// the trash hung outside the can. A bounce never takes a part further from
/// where it goes next than the hit left it.
@Suite("Ask's story icons: a bounce goes towards where the part goes next")
struct AskMotionBounceTowardsTests {

    static let svg = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><g id="bin"><path id="body" d="M7 9 L8 20 Q8 21 9 21 L15 21 Q16 21 16 20 L17 9"/><line id="rib-left" x1="10" y1="11" x2="10.5" y2="19"/><line id="rib-right" x1="14" y1="11" x2="13.5" y2="19"/></g><g id="lid"><line id="lid-bar" x1="6" y1="8" x2="18" y2="8"/><line id="lid-knob" x1="11" y1="6" x2="13" y2="6"/></g><path id="trash" d="M16 1 L21 2 L20 7 L15 6 Z"/></svg>"##

    static func steps() throws -> [AskStep] {
        let args = AskMotionTuckedInTests.args
        return [AskStep(tool: "add_drawing", arguments: ["icon": true, "subject": "trash bin with hinged lid", "svg": .string(svg)]),
                AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(1.5)]),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease out","seconds":0.2,"value":0},{"curve":"Hold","seconds":0.5,"value":-40},{"curve":"Ease in out","seconds":0.8,"value":-40},{"curve":"Ease out back","seconds":0.95,"value":-30},{"curve":"Hold","seconds":1.3,"value":0},{"seconds":1.5,"value":0}],"layer":"$1/lid","pivot":{"x":6,"y":8},"property":"rotation"}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":100},{"seconds":1.1,"value":0},{"seconds":1.2,"value":0},{"seconds":1.5,"value":100}],"layer":"$1/trash","property":"opacity"}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":100},{"seconds":1.2,"value":0},{"seconds":1.3,"value":0},{"seconds":1.5,"value":100}],"layer":"$1/trash","property":"opacity","replace":true}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":0},{"seconds":0.2,"value":0},{"seconds":0.5,"value":-40},{"seconds":0.9,"value":-40},{"seconds":1.05,"value":-30},{"seconds":1.3,"value":0},{"seconds":1.5,"value":0}],"layer":"$1/lid","property":"rotation","replace":true}"#)),
                AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.9,"touches":"lid","value":{"x":-6,"y":4}},{"seconds":1.05,"value":{"x":-7,"y":2}},{"seconds":1.2,"touches":"bin","value":{"x":-7,"y":8}},{"seconds":1.3,"value":{"x":-7,"y":8}},{"seconds":1.5,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position","replace":true}"#))]
    }

    @Test("Landed, the trash never hangs outside the can's wall below its rim while it is seen")
    func neverOutside() throws {
        let landed = AskMotion.planned(try Self.steps())
        let lap = try #require(AskMotion.Lap(landed))
        var moment = 0.9
        var outside: [Double] = []
        while moment < 1.5 {
            if lap.placed("trash", at: moment)?.seen ?? false {
                let ink = lap.ink("trash", at: moment).flatMap { $0 }
                let middle = CGPoint(x: ink.map(\.x).reduce(0, +) / CGFloat(ink.count), y: ink.map(\.y).reduce(0, +) / CGFloat(ink.count))
                // The right wall runs from (17, 9) to (16, 20): its outside edge is a unit further.
                if middle.y > 10, middle.x > 17 + 1 - (middle.y - 9) / 11 { outside.append(moment) }
            }
            moment += 0.01
        }
        #expect(outside.isEmpty, "\(outside)")
    }
}
