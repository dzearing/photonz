import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The user's trash, walked on 2026-11-11 (task
/// `an-animated-icon-told-as-a-little-story-moves-th`): the model keyed the
/// trash touching the lid at 0.9 and 1.05 s and touching the bin at 1.2 s,
/// at the can's mouth. The bounce off the lid re-aimed the key after the hit,
/// which was that landing, and threw it 4 units right and 3 down: the trash
/// slid down outside the can's right wall and faded there. What the model
/// says a part touches next is kept; the bounce goes between.
@Suite("Ask's story icons: a bounce never moves the next contact the model planned")
struct AskMotionBounceThenInTests {

    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }
    static let bin = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><g id="bin"><path id="body" d="M7 9 L8 20 L16 20 L17 9"/><line id="rib-left" x1="10" y1="11" x2="10.5" y2="18"/><line id="rib-right" x1="14" y1="11" x2="13.5" y2="18"/></g><g id="lid"><line id="lid-bar" x1="6" y1="8" x2="18" y2="8"/><line id="lid-knob" x1="11" y1="6" x2="13" y2="6"/></g><path id="trash" d="M19 3 L21 4 L20 6 L18 5 Z" fill="#1D1D1F" stroke="none"/></svg>"##

    static func steps() throws -> [AskStep] {
        [AskStep(tool: "add_drawing", arguments: ["icon": true, "subject": "trash bin with hinged lid", "svg": .string(bin)]),
         AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(1.5)]),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease out","seconds":0.2,"value":0},{"curve":"Ease in","seconds":0.5,"value":-40},{"curve":"Ease out","seconds":0.8,"value":-40},{"curve":"Ease in","seconds":0.95,"value":-30},{"curve":"Ease out back","seconds":1.1,"value":-30},{"curve":"Hold","seconds":1.3,"value":0}],"layer":"$1/lid","pivot":{"x":6,"y":8},"property":"rotation"}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":100},{"seconds":1.1,"value":100},{"seconds":1.3,"value":0},{"seconds":1.5,"value":100}],"layer":"$1/trash","property":"opacity","replace":true}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.9,"touches":"lid","value":{"x":-4,"y":2}},{"seconds":1.05,"touches":"lid","value":{"x":-5,"y":0}},{"seconds":1.2,"touches":"bin","value":{"x":-5,"y":4}},{"seconds":1.3,"value":{"x":-5,"y":4}},{"seconds":1.5,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position","replace":true}"#))]
    }

    static func keys(_ steps: [AskStep]) -> [(seconds: Double, at: CGPoint)] {
        guard let step = steps.last(where: { $0.arguments["layer"]?.stringValue == "$1/trash" && $0.arguments["property"]?.stringValue == "position" }) else { return [] }
        return (step.arguments["keys"]?.arrayValue ?? []).compactMap { key in
            guard let s = key["seconds"]?.doubleValue, let x = key["value"]?["x"]?.doubleValue, let y = key["value"]?["y"]?.doubleValue else { return nil }
            return (s, CGPoint(x: x, y: y))
        }.sorted { $0.seconds < $1.seconds }
    }

    @Test("The trash lands in the can's mouth where the model put it, and bounces off the lid on a key of its own before that")
    func landsInAfterTheBounce() throws {
        let placed = AskMotion.touchesPlaced(try Self.steps())
        let keys = Self.keys(placed)
        let landing = try #require(keys.first { abs($0.seconds - 1.2) < 0.0005 })
        // Drawn at x 18 to 21: between the can's walls (7 to 17) at its mouth.
        #expect(landing.at.x + 18 >= 7 && landing.at.x + 21 <= 17.5, "\(landing)")
        #expect(landing.at.y + 3 <= 10, "at the mouth, not down the side: \(landing)")
        // A bounce key between the last lid hit and the landing, apart from the lid.
        let bounce = try #require(keys.first { $0.seconds > 1.05 + 0.0005 && $0.seconds < 1.2 - 0.0005 }, "\(keys)")
        let lap = try #require(AskMotion.Lap(placed))
        #expect(!AskMotion.inkMeets(lap.ink("trash", at: bounce.seconds), lap.ink("lid", at: bounce.seconds), within: 0), "\(bounce)")
        // And never through the lid from the hit to the landing.
        #expect(try !AskMotionBounceTests.through(placed, from: 1.05, to: 1.2))
    }
}
