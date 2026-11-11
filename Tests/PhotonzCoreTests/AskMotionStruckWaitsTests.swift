import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The user's own trash story, run 20261111-064936 (task
/// `an-animated-icon-told-as-a-little-story-moves-th`), the model's last plan
/// as it was mended. Read on the curves the icon plays, the lid closing on
/// Ease out back from 0.95 s swept through the trash on its way into the can
/// from 1.0 to 1.1 s, and every look of the judge saw the trash "pass
/// straight through the lid". What was hit waits, before its next move,
/// until what hit it is clear of its path.
@Suite("Ask's story icons: what is hit waits for what hit it to get clear")
struct AskMotionStruckWaitsTests {

    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }
    static let bin = ##"<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><g id="bin"><path id="body" d="M6 9 L7 20 Q7 21 8 21 L16 21 Q17 21 17 20 L18 9"/><line id="rib-left" x1="10" y1="12" x2="10.5" y2="18"/><line id="rib-right" x1="14" y1="12" x2="13.5" y2="18"/></g><g id="lid"><line id="lid-bar" x1="5" y1="8" x2="19" y2="8"/><line id="lid-knob" x1="11" y1="6" x2="13" y2="6"/></g><path id="trash" d="M19 3 L21 4 L20 6 L18 5 Z" fill="#1D1D1F" stroke="none"/></svg>"##
    static let lidKeys = #"[{"seconds":0,"value":0},{"curve":"Ease out","seconds":0.2,"value":0},{"curve":"Hold","seconds":0.5,"value":-40},{"curve":"Ease in out","seconds":0.8,"value":-40},{"curve":"Ease out back","seconds":0.95,"value":-30},{"curve":"Hold","seconds":1.3,"value":0},{"seconds":1.5,"value":0}]"#
    static let trashKeys = #"[{"seconds":0,"value":{"x":0,"y":0}},{"curve":"Ease in","seconds":0.5,"value":{"x":0,"y":0}},{"curve":"Ease out","seconds":0.8,"touches":"lid","value":{"x":-6,"y":3}},{"curve":"Ease in","seconds":0.95,"touches":"lid","value":{"x":-7,"y":1}},{"curve":"Ease in","seconds":1.1,"touches":"bin","value":{"x":-7,"y":5}},{"seconds":1.15,"value":{"x":-7,"y":5}},{"curve":"Ease in","seconds":1.35,"value":{"x":-7,"y":5}},{"seconds":1.5,"value":{"x":0,"y":0}}]"#

    static func steps(lid: String = lidKeys, trash: String = trashKeys) throws -> [AskStep] {
        [AskStep(tool: "add_drawing", arguments: ["icon": true, "subject": "trash bin with openable lid", "svg": .string(bin)]),
         AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(1.5)]),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":\#(lid),"layer":"$1/lid","pivot":{"x":0.05,"y":0.5},"property":"rotation","replace":true}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":0},{"seconds":0.5,"value":0},{"seconds":0.8,"value":100},{"seconds":1.1,"value":100},{"seconds":1.15,"value":0},{"seconds":1.5,"value":0}],"layer":"$1/trash","property":"opacity","replace":true}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":\#(trash),"layer":"$1/trash","property":"position","replace":true}"#))]
    }

    /// The first moment from `from` the trash's ink, seen, goes deeper into the lid's than a touch.
    static func through(_ steps: [AskStep], from: Double, to: Double) throws -> Double? {
        let lap = try #require(AskMotion.Lap(steps))
        var moment = from + 0.01
        while moment <= to {
            if lap.placed("trash", at: moment)?.seen ?? true,
               AskMotion.inkMeets(lap.ink("trash", at: moment), lap.ink("lid", at: moment), within: -AskMotion.passesThrough) { return moment }
            moment += 0.01
        }
        return nil
    }

    @Test("Landed, the trash never goes through the lid, and the lid still shuts after it is in, within the lap")
    func lidWaits() throws {
        let raw = try Self.steps()
        let landed = AskMotion.planned(raw)
        #expect(try Self.through(landed, from: 0.5, to: 1.5) == nil)
        let lap = try #require(AskMotion.Lap(landed))
        // Open at the hit, shut (within a few degrees) by the lap's end.
        #expect((lap.value("lid", .rotation, at: 0.8)?.doubleValue ?? 0) < -30)
        #expect(abs(lap.value("lid", .rotation, at: 1.45)?.doubleValue ?? 99) < 4)
        // It does not wait long: shut within half a second of the trash going in.
        #expect(abs(lap.value("lid", .rotation, at: 1.4)?.doubleValue ?? 99) < 6)
    }

    @Test("What was hit keeps its keys when nothing passes through it")
    func leftAlone() throws {
        // The lid closes only once the trash has long gone (faded at 1.15 s).
        let late = #"[{"seconds":0,"value":0},{"curve":"Ease out","seconds":0.2,"value":0},{"curve":"Hold","seconds":0.5,"value":-40},{"curve":"Ease in out","seconds":0.8,"value":-40},{"curve":"Ease in out","seconds":1.2,"value":-40},{"seconds":1.45,"value":0},{"seconds":1.5,"value":0}]"#
        let raw = try Self.steps(lid: late)
        let lid = AskMotion.struckWaits(raw, part: "trash", hit: 0.95, off: "lid")
        #expect(lid == raw)
    }

    @Test("Waiting keeps the lid's keys in order, apart, and the lap's last key where it was")
    func keysKept() throws {
        let raw = AskMotion.touchesPlaced(try Self.steps())
        let waited = AskMotion.struckWaits(raw, part: "trash", hit: 0.95, off: "lid")
        let lid = try #require(waited.last { $0.arguments["layer"]?.stringValue == "$1/lid" })
        let times = AskMotionCheck.timed(lid).map(\.seconds)
        #expect(times == times.sorted())
        #expect(zip(times, times.dropFirst()).allSatisfy { $1 - $0 > Double(PropertyKeys.nearMS) / 1000 })
        #expect(times.last == 1.5)
        #expect(times.contains(0.95))
    }
}
