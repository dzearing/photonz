import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// A beat where one part hits, lands on or bounces off another is placed where
/// the two meet (task `an-animated-icon-told-as-a-little-story-moves-th`): the
/// key says which part it touches, and its position is moved, by the parts'
/// own outlines as the keys turn and move them, just far enough that they
/// meet. On 2026-11-09 the user's trash hovered beside the lid it should
/// bounce off, run after run, though the model was told in numbers that it
/// touched nothing. Nothing here knows what any part is.
@Suite("A key that touches another part is placed against it")
struct AskMotionContactTests {

    static let drawing = AskMotionWhereTheyAreTests.drawing

    static func keys(_ json: String) throws -> AskStep { try AskMotionWhereTheyAreTests.keys(json) }

    static func touchesNamed(_ steps: [AskStep]) -> Bool {
        steps.contains { step in (step.arguments["keys"]?.arrayValue ?? []).contains { $0["touches"] != nil } }
    }

    static func position(_ steps: [AskStep], at seconds: Double) -> CGPoint? {
        guard let step = steps.last(where: { $0.arguments["property"]?.stringValue == "position" }),
              let key = step.arguments["keys"]?.arrayValue?.first(where: { abs(($0["seconds"]?.doubleValue ?? -1) - seconds) < 0.001 }),
              let x = key["value"]?["x"]?.doubleValue, let y = key["value"]?["y"]?.doubleValue else { return nil }
        return CGPoint(x: x, y: y)
    }

    @Test("A key short of the part it touches is moved just far enough to meet it, straight towards it")
    func movedToMeet() throws {
        let throwIn = try Self.keys(#"{"layer":"$1/trash","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":-3},"touches":"lid"},{"seconds":1,"value":{"x":0,"y":0}}]}"#)
        let placed = AskMotion.touchesPlaced([Self.drawing, throwIn])
        let after = try #require(AskMotion.whereParts(placed))
        #expect(after.contains("touching lid"), "\(after)")
        let moved = try #require(Self.position(placed, at: 0.5))
        #expect(moved.x == 0)
        // Just far enough: it meets the lid's edge, it does not sink into it.
        #expect(moved.y > 0 && moved.y < 1.5, "\(moved)")
        // The other keys are as written.
        #expect(Self.position(placed, at: 0) == CGPoint.zero)
        #expect(!Self.touchesNamed(placed), "the word is the planner's, never the file's")
    }

    @Test("A part that turns is met where its keys turn it at that moment")
    func metWhereItTurned() throws {
        let lift = try Self.keys(#"{"layer":"$1/lid","property":"rotation","pivot":{"x":19,"y":6},"keys":[{"seconds":0,"value":0},{"seconds":0.5,"value":90},{"seconds":1,"value":0}]}"#)
        // Far to the left of the lid standing up over its hinge at x 18 to 20.
        let throwIn = try Self.keys(#"{"layer":"$1/trash","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":-6,"y":0},"touches":"lid"},{"seconds":1,"value":{"x":0,"y":0}}]}"#)
        let placed = AskMotion.touchesPlaced([Self.drawing, lift, throwIn])
        let after = try #require(AskMotion.whereParts(placed))
        #expect(after.contains("0.5 s: lid turned 90, x 18 to 20, y -9 to 7, touching can and trash; trash"), "\(after)")
        #expect(after.contains("touching lid"), "\(after)")
        let moved = try #require(Self.position(placed, at: 0.5))
        #expect(moved.x > 3 && moved.x < 6, "\(moved)")
    }

    @Test("A key already touching stays as written, and a part the drawing does not have changes nothing")
    func leftAsWritten() throws {
        let landed = try Self.keys(#"{"layer":"$1/trash","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":2.5},"touches":"lid"},{"seconds":0.8,"value":{"x":3,"y":-2},"touches":"moon"},{"seconds":1,"value":{"x":0,"y":0}}]}"#)
        let placed = AskMotion.touchesPlaced([Self.drawing, landed])
        #expect(Self.position(placed, at: 0.5) == CGPoint(x: 0, y: 2.5))
        #expect(Self.position(placed, at: 0.8) == CGPoint(x: 3, y: -2))
        #expect(!Self.touchesNamed(placed))
    }

    @Test("The plan that lands carries no touches, and the moving icon's set_keys offers it")
    func landsWithout() throws {
        let throwIn = try Self.keys(#"{"layer":"$1/trash","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":-3},"touches":"lid"},{"seconds":1,"value":{"x":0,"y":0}}]}"#)
        let landing = AskMotion.planned([Self.drawing, throwIn])
        #expect(!Self.touchesNamed(landing))
        let tool = try #require(AskMotion.modelTools.first { $0["function"]?["name"]?.stringValue == "set_keys" })
        #expect(tool["function"]?["parameters"]?["properties"]?["keys"]?["items"]?["properties"]?["touches"] != nil)
        // Every other tool that keys is as it was.
        #expect(AskTools.pictureKeyModelTools.first { $0["function"]?["name"]?.stringValue == "set_keys" }?["function"]?["parameters"]?["properties"]?["keys"]?["items"]?["properties"]?["touches"] == nil)
    }

    @Test("A key that says what it touches is planned, not refused, and the part may be named as the model names layers")
    func plannedNotRefused() throws {
        var talk = AskMotionStoryTests.told("make an animated icon where a ball hits the lid", design: nil)
        _ = talk.take(AskMotionTests.reply("add_drawing", ["subject": "thing", "svg": .string(AskMotionWhereTheyAreTests.svg)]))
        _ = talk.take(AskMotionTests.reply("set_keys", try AskMotionTests.args(#"{"layer":"$1/trash","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":-3},"touches":"$1/lid"},{"seconds":1,"value":{"x":0,"y":0}}]}"#)))
        let said = talk.messages.last?["content"]?.stringValue ?? ""
        #expect(!said.contains("not an argument"), "\(said)")
        #expect(talk.steps.count == 2)
        let placed = AskMotion.touchesPlaced(talk.steps)
        let moved = try #require(Self.position(placed, at: 0.5))
        #expect(moved.y > 0 && moved.y < 1.5, "\(moved)")
    }
}
