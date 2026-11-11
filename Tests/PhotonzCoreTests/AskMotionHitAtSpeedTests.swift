import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The user's trash story, walked on 2026-11-11 (task
/// `an-animated-icon-told-as-a-little-story-moves-th`): the model gave the
/// trash's keys no curve, every leg played Ease in out, and the trash came to
/// a dead stop against the lid and set off again slowly. Seen at icon size
/// that is a touch and a slide, never a bounce ("the square touches the
/// lid's underside and goes on down", the 2026-11-11 digest). A hit is met
/// at speed and left at speed.
@Suite("Ask's story icons: a hit is met at speed and left at speed")
struct AskMotionHitAtSpeedTests {

    /// How far the trash goes in the 0.02 s from `at`.
    static func step(_ lap: AskMotion.Lap, at: Double) -> CGFloat {
        guard let a = lap.value("trash", .position, at: at), let b = lap.value("trash", .position, at: at + 0.02),
              let ax = a["x"]?.doubleValue, let ay = a["y"]?.doubleValue,
              let bx = b["x"]?.doubleValue, let by = b["y"]?.doubleValue else { return 0 }
        return CGFloat(hypot(bx - ax, by - ay))
    }

    /// The trash's mean distance per 0.02 s from `from` to `to`.
    static func mean(_ lap: AskMotion.Lap, from: Double, to: Double) -> CGFloat {
        guard let a = lap.value("trash", .position, at: from), let b = lap.value("trash", .position, at: to),
              let ax = a["x"]?.doubleValue, let ay = a["y"]?.doubleValue,
              let bx = b["x"]?.doubleValue, let by = b["y"]?.doubleValue else { return 0 }
        return CGFloat(hypot(bx - ax, by - ay)) * 0.02 / CGFloat(to - from)
    }

    static func trashKeys(_ steps: [AskStep]) -> [(seconds: Double, value: AgentJSON, curve: String?)] {
        steps.last { $0.arguments["layer"]?.stringValue == "$1/trash" && $0.arguments["property"]?.stringValue == "position" }
            .map(AskMotionCheck.timed) ?? []
    }

    @Test("Landed, the trash is still moving fast as it meets the lid and as it leaves it")
    func atSpeed() throws {
        let landed = AskMotion.planned(try AskMotionTuckedInTests.steps())
        let lap = try #require(AskMotion.Lap(landed))
        let keys = Self.trashKeys(landed)
        let hit = try #require(keys.firstIndex { abs($0.seconds - 0.8) < 0.0005 })
        let before = keys[hit - 1].seconds, after = keys[hit + 1].seconds
        let inMean = Self.mean(lap, from: before, to: 0.8), outMean = Self.mean(lap, from: 0.8, to: after)
        #expect(Self.step(lap, at: 0.78) >= inMean * 0.5, "into the lid: \(Self.step(lap, at: 0.78)) of \(inMean)")
        #expect(Self.step(lap, at: 0.8) >= outMean * 0.5, "off the lid: \(Self.step(lap, at: 0.8)) of \(outMean)")
    }

    @Test("A curve the model chose that already meets the hit at speed is kept")
    func chosenKept() throws {
        var steps = try AskMotionTuckedInTests.steps()
        let linear = #"{"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"curve":"Linear","seconds":0.5,"value":{"x":0,"y":0}},{"curve":"Linear","seconds":0.8,"touches":"lid","value":{"x":-6,"y":3}},{"seconds":0.95,"value":{"x":-5,"y":1}},{"seconds":1.1,"value":{"x":-4,"y":5}},{"seconds":1.2,"value":{"x":-4,"y":5}},{"seconds":1.5,"value":{"x":0,"y":0}}],"layer":"$1/trash","property":"position","replace":true}"#
        steps[steps.count - 1] = AskStep(tool: "set_keys", arguments: try AskMotionTuckedInTests.args(linear))
        let keys = Self.trashKeys(AskMotion.touchesPlaced(AskMotion.landingFolded(steps)))
        #expect(keys.first { abs($0.seconds - 0.5) < 0.0005 }?.curve == "Linear")
        #expect(keys.first { abs($0.seconds - 0.8) < 0.0005 }?.curve == "Linear")
    }
}
