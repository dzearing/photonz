import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The user's trash story as the eval landed it on 2026-11-14 at 02:41 (run
/// 20261114-021418-ask, task `an-animated-icon-told-as-a-little-story-moves-th`,
/// pass eighteen's measure): the first plan of pass sixteen's walk, then the
/// mend after the look (the trash said to touch the lid at 0.8 s and the bin
/// at 1.2 s, with a hop up to y -2 at 0.95 s between). At the hit the scrap
/// was drawn behind the lid's bar, which nine looks of nine read as passing
/// through the lid.
enum AskMotionOverTheLidEval {
    static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }

    static func steps() throws -> [AskStep] {
        let first = try AskMotionInBeforeShutWalk.steps().prefix(5)
        return Array(first) + [
            AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"curve":"Hold","seconds":0,"value":0},{"curve":"Ease out","seconds":0.2,"value":0},{"curve":"Hold","seconds":0.5,"value":-50},{"curve":"Ease in","seconds":0.8,"value":-50},{"curve":"Hold","seconds":0.95,"value":0},{"seconds":1.5,"value":0}],"layer":"$1/lid","pivot":{"x":4,"y":8},"property":"rotation","replace":true}"#)),
            AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"curve":"Ease in","seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"$1/lid","value":{"x":-6,"y":2}},{"curve":"Ease in","seconds":0.95,"value":{"x":-6,"y":-2}},{"seconds":1.2,"touches":"$1/bin","value":{"x":-6,"y":8}},{"seconds":1.5,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position","replace":true}"#)),
            AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":100},{"seconds":1.2,"value":100},{"seconds":1.3,"value":0},{"seconds":1.45,"value":0},{"seconds":1.5,"value":100}],"layer":"$1/trash","property":"opacity","replace":true}"#)),
            AskStep(tool: "set_keys", arguments: try args(#"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":0}},{"seconds":0.8,"touches":"$1/lid","value":{"x":-6,"y":2}},{"seconds":0.95,"value":{"x":-6,"y":-2}},{"seconds":1.2,"touches":"$1/bin","value":{"x":-6,"y":8}},{"seconds":1.5,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position","replace":true}"#)),
        ]
    }
}

@Suite("Ask's story icons: what hits a lid is seen hitting it, not cutting through")
struct AskMotionOverTheLidTests {
    /// The landed steps with every line as wide as the app draws it once
    /// the drawing lands in its grown frame: lines keep their weight on the
    /// 24 grid while the drawing shrinks by its viewBox's growth.
    static func asDrawn(_ landed: [AskStep]) -> [AskStep] {
        guard let svg = landed.first(where: { $0.tool == "add_drawing" })?.arguments["svg"]?.stringValue,
              case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true), let view = art.viewBox else { return landed }
        return AskMotion.linesAsDrawn(landed, on: view.width, from: 24)
    }

    /// How far apart the ink of two parts is at `moment` (below 0: how deep
    /// they overlap), to a hundredth.
    static func gap(_ lap: AskMotion.Lap, _ a: String, _ b: String, _ moment: Double) -> Double {
        let one = lap.ink(a, at: moment), other = lap.ink(b, at: moment)
        var low: CGFloat = -6, high: CGFloat = 6
        for _ in 0..<30 {
            let mid = (low + high) / 2
            if AskMotion.inkMeets(one, other, within: mid) { high = mid } else { low = mid }
        }
        return Double((high * 100).rounded() / 100)
    }

    @Test("The eval's plan, written out on request",
          .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_LAP_DUMP"] != nil))
    func dump() throws {
        let path = try #require(ProcessInfo.processInfo.environment["PHOTONZ_LAP_DUMP"])
        let landed = AskMotion.planned(try AskMotionOverTheLidEval.steps())
        for step in landed { print("LANDED", step.tool, step.arguments.encodedString()) }
        let lap = try #require(AskMotion.Lap(landed))
        let drawn = try #require(AskMotion.Lap(Self.asDrawn(landed)))
        for moment in stride(from: 0.5, through: 1.3, by: 0.025) {
            let seen = lap.placed("trash", at: moment)?.seen ?? false
            print("AT", moment, "seen", seen, "lid", Self.gap(lap, "trash", "lid", moment), "lid drawn", Self.gap(drawn, "trash", "lid", moment))
        }
        try LapDump.write(landed, to: path, frames: 48)
    }

    /// On the eval's frames (run 20261114-021418-ask, 0.8 s) the scrap sat
    /// 0.84 deep in the lid's bar at the hit: the hit was placed with lines
    /// as wide as they are written, and the drawing then shrank by its room
    /// (1.275 times) while its lines kept their weight of 2 on the grid. A
    /// hit is placed against the lines as they will be drawn, and the
    /// drawing lands saying so: seen, from the throw to the hit, the scrap
    /// meets the lid and never cuts into it.
    @Test("The hit on the lid is a touch as drawn, not a cut through it")
    func hitAsDrawn() throws {
        let landed = AskMotion.planned(try AskMotionOverTheLidEval.steps())
        let lap = try #require(AskMotion.Lap(landed))
        let drawn = try #require(AskMotion.Lap(Self.asDrawn(landed)))
        let seen = stride(from: 0.5, through: 1.0, by: 0.01).filter { lap.placed("trash", at: $0)?.seen ?? false }
        let closest = try #require(seen.map { Self.gap(drawn, "trash", "lid", $0) }.min())
        #expect(closest >= -0.1, "cuts \(closest) into the lid as drawn")
        #expect(closest <= Double(AskMotion.edgeTouch), "never meets the lid: \(closest) apart")
    }

    /// The app lands a line weight on a whole or half unit of the 24 grid
    /// after the drawing is scaled to fit its frame.
    @Test("A line is as wide as the app draws it in a grown frame")
    func drawnWidths() {
        #expect(abs(AskMotion.drawnWidth(2, viewBox: 30.6, from: 24) - 2.55) < 0.001)
        // Grown past a third, a 2 drawn at under 1.5 units comes to 1.
        #expect(abs(AskMotion.drawnWidth(2, viewBox: 33.6, from: 24) - 1.4) < 0.001)
        #expect(AskMotion.drawnWidth(2, viewBox: 24, from: 24) == 2)
    }
}
