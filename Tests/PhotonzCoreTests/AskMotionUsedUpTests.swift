import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The user's trash, run 20261111-092934 (task
/// `an-animated-icon-told-as-a-little-story-moves-th`): the model kept the
/// trash in view beside the can from the start of the lap, standing there
/// until it set off for the lid, and every look of the judge read "the trash
/// just hangs beside the can before drifting in". A part the story uses up
/// (it sets off, meets something, and ends out of sight) is not seen waiting:
/// it is out of sight until it sets off, and so comes in from off the frame.
@Suite("Ask's story icons: what the story uses up is not seen waiting")
struct AskMotionUsedUpTests {

    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }
    static let bin = AskMotionStruckWaitsTests.bin
    static let lid = #"[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease out","seconds":0.2,"value":0},{"curve":"Hold","seconds":0.5,"value":-40},{"curve":"Ease in out","seconds":0.8,"value":-40},{"curve":"Ease out back","seconds":0.95,"value":-30},{"curve":"Hold","seconds":1.3,"value":0},{"seconds":1.5,"value":0}]"#
    static let trash = #"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"$1/lid","value":{"x":-6,"y":2}},{"seconds":0.95,"touches":"$1/lid","value":{"x":-7,"y":0}},{"seconds":1.1,"touches":"$1/bin","value":{"x":-7,"y":4}},{"seconds":1.2,"value":{"x":-7,"y":4}},{"seconds":1.5,"value":{"x":0,"y":0}}]"#
    static let seenAtRest = #"[{"seconds":0,"value":100},{"seconds":0.5,"value":100},{"seconds":1.1,"value":100},{"seconds":1.2,"value":0},{"seconds":1.5,"value":100}]"#

    static func steps(fade: String = seenAtRest, trash: String = trash) throws -> [AskStep] {
        [AskStep(tool: "add_drawing", arguments: ["icon": true, "subject": "trash bin with openable lid", "svg": .string(bin)]),
         AskStep(tool: "set_timing", arguments: ["loop": true, "seconds": .number(1.5)]),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":\#(lid),"layer":"$1/lid","pivot":{"x":5,"y":8},"property":"rotation"}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":\#(trash),"layer":"$1/trash","property":"position","replace":true}"#)),
         AskStep(tool: "set_keys", arguments: try args(#"{"keys":\#(fade),"layer":"$1/trash","property":"opacity","replace":true}"#))]
    }

    static func view(_ steps: [AskStep]) throws -> CGRect {
        let svg = try #require(steps.first { $0.tool == "add_drawing" }?.arguments["svg"]?.stringValue)
        guard case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true), let box = art.viewBox else { throw CancellationError() }
        return box
    }

    @Test("Out of sight at rest and until it sets off, thrown in from outside the frame, seen when it hits, out of sight at the lap's end")
    func hiddenUntilThrown() throws {
        let landed = AskMotion.planned(try Self.steps())
        let lap = try #require(AskMotion.Lap(landed))
        for moment in [0.0, 0.25, 0.45] { #expect(lap.placed("trash", at: moment)?.seen == false, "\(moment)") }
        #expect(lap.placed("trash", at: 0.8)?.seen == true)
        #expect(lap.placed("trash", at: 1.49)?.seen == false)
        // Sets off from outside the frame, not from where it was drawn.
        let view = try Self.view(landed)
        let start = try #require(lap.placed("trash", at: 0.5)?.quad)
        #expect(!start.contains { view.insetBy(dx: 0.01, dy: 0.01).contains($0) }, "\(start) in \(view)")
    }

    @Test("A part seen at rest that the story does not use up keeps its fade: it stays in sight, or never meets anything")
    func keptWhenNotUsedUp() throws {
        // Stays in sight after landing in the can: it is still part of the picture.
        let stays = #"[{"seconds":0,"value":100},{"seconds":1.5,"value":100}]"#
        let raw = try Self.steps(fade: stays)
        let fade = AskMotion.usedUpUnseen(raw)
        #expect(fade == raw)
        // Fades but meets nothing on its way: a puff that drifts.
        let drift = #"[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"value":{"x":0,"y":-2}},{"seconds":1.3,"value":{"x":0,"y":-2}},{"seconds":1.5,"value":{"x":0,"y":0}}]"#
        let puff = try Self.steps(trash: drift)
        #expect(AskMotion.usedUpUnseen(puff) == puff)
    }
}
