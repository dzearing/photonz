import Foundation
@testable import PhotonzCore
import Testing

/// Run 20261111-095723 (task `an-animated-icon-told-as-a-little-story-moves-th`):
/// the model keyed the rocket's shake and smoke at 100 to 3000 "seconds" on a
/// 3 second lap, copying its design's milliseconds, and the icon showed a
/// rocket that barely moved. Twice in two runs, and once on 2026-11-10.
@Suite("Ask's moving icons: key times written in milliseconds are read as seconds")
struct AskMotionMillisecondsTests {

    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }
    static func times(_ arguments: AgentJSON) -> [Double] { (arguments["keys"]?.arrayValue ?? []).compactMap { $0["seconds"]?.doubleValue } }

    @Test("Whole numbers past the lap, within it in milliseconds, become seconds; everything else on the key stays")
    func converts() throws {
        let rocket = try Self.args(#"{"layer":"$1/smoke","property":"opacity","keys":[{"seconds":0,"value":0},{"seconds":700,"value":0,"curve":"Ease out"},{"seconds":1500,"value":100},{"seconds":3000,"value":0}]}"#)
        let read = AskMotion.keysInSeconds(rocket, lap: 3)
        #expect(Self.times(read) == [0, 0.7, 1.5, 3])
        #expect(read["keys"]?.arrayValue?[1]["curve"]?.stringValue == "Ease out")
        #expect(read["layer"]?.stringValue == "$1/smoke")
    }

    @Test("Keys in seconds, or numbers no lap explains, are left as written")
    func leftAlone() throws {
        let seconds = try Self.args(#"{"layer":"$1/lid","property":"rotation","keys":[{"seconds":0,"value":0},{"seconds":0.5,"value":-40},{"seconds":1.5,"value":0}]}"#)
        #expect(AskMotion.keysInSeconds(seconds, lap: 1.5) == seconds)
        // Within a 4 second lap as whole seconds.
        let whole = try Self.args(#"{"layer":"$1/sun","property":"rotation","keys":[{"seconds":0,"value":0},{"seconds":2,"value":180},{"seconds":4,"value":360}]}"#)
        #expect(AskMotion.keysInSeconds(whole, lap: 4) == whole)
        // Past the lap even in milliseconds: not a reading of anything.
        let far = try Self.args(#"{"layer":"$1/sun","property":"rotation","keys":[{"seconds":0,"value":0},{"seconds":9000,"value":180}]}"#)
        #expect(AskMotion.keysInSeconds(far, lap: 3) == far)
        // A fraction among them is seconds, written long.
        let mixed = try Self.args(#"{"layer":"$1/sun","property":"rotation","keys":[{"seconds":0,"value":0},{"seconds":1.5,"value":90},{"seconds":6,"value":180}]}"#)
        #expect(AskMotion.keysInSeconds(mixed, lap: 3) == mixed)
    }
}
