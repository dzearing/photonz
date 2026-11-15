import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// A moving icon is looked at before it lands (task
/// `an-animated-icon-told-as-a-little-story-moves-th`): frames of what the plan
/// made, across one lap, go to the planning model, which says which beat of the
/// request each frame shows and what looks wrong; what it saw goes back to the
/// plan once. Nothing here knows what any icon is of.
@Suite("A moving icon is looked at before it lands")
struct AskMotionLookTests {

    static let request = "make an animated icon of a thing that opens, bounces and closes"

    static func planned() throws -> AskConversation {
        var talk = AskMotionStoryTests.told(request)
        _ = talk.take(AskMotionTests.reply("add_drawing", ["subject": "thing", "svg": .string(AskMotionStoryTests.svg)]))
        _ = talk.take(AskMotionTests.reply("set_keys", try AskMotionTests.args(#"{"layer":"$1/whole","property":"scale","keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":125},{"seconds":1,"value":100}]}"#)))
        _ = talk.take(AskMotionTests.said("Done."))
        guard case .planned = talk.take(AskMotionTests.said("Done.\nLeft out: nothing")) else {
            Issue.record("the plan lands before it is looked at")
            return talk
        }
        return talk
    }

    @Test("The look sends the frames and the request to the planning model, with no tools and no thinking")
    func body() {
        let png = Data([1, 2, 3])
        let body = AskMotionLook.body(model: "m", png: png, request: Self.request)
        let message = body["messages"]?.arrayValue?.last
        let asked = message?["content"]?.stringValue ?? ""
        #expect(asked.contains(Self.request))
        #expect(asked.contains("not seen"))
        #expect(asked.contains(AskMotionLook.allGood))
        #expect(message?["images"]?.arrayValue?.first?.stringValue == png.base64EncodedString())
        #expect(body["tools"] == nil)
        #expect(body["think"]?.boolValue == false)
        #expect(body["options"]?["temperature"]?.doubleValue == 0)
        #expect((body["options"]?["num_predict"]?.doubleValue ?? 0) > 0)
    }

    @Test("Frames spread over the whole lap, the last just before it starts again")
    func times() {
        let times = AskMotionLook.times(lapMS: 2400)
        #expect(times.count == AskMotionLook.frames)
        #expect(times.first == 0)
        #expect((times.last ?? 0) < 2400)
        #expect((times.last ?? 0) > 2000)
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("All good with every beat seen lands as it is; a beat not seen or a fault goes back in the model's words")
    func reading() {
        #expect(AskMotionLook.critique(fromAnswer: "Opens: 0.2 s\nBounces: 0.6 s\nCloses: 1.0 s\nAll good.") == nil)
        #expect(AskMotionLook.critique(fromAnswer: "<think>\n</think>\n\nOpens: 0.2 s\nAll good") == nil)
        #expect(AskMotionLook.critique(fromAnswer: "") == nil)
        #expect(AskMotionLook.critique(fromAnswer: "   ") == nil)
        let missed = "Opens: 0.2 s\nBounces: not seen\nCloses: 1.0 s"
        #expect(AskMotionLook.critique(fromAnswer: missed) == missed)
        // A beat not seen is not all good, whatever the last line says.
        let contradicts = "Opens: 0.2 s\nBounces: not seen\nAll good."
        #expect(AskMotionLook.critique(fromAnswer: contradicts)?.contains("Bounces: not seen") == true)
        let fault = "Opens: 0.2 s\n**Issues:**\n* The ball appears in place at 0.5 s instead of travelling."
        #expect(AskMotionLook.critique(fromAnswer: fault)?.contains("appears in place") == true)
        // Markdown the model dresses its answer in is taken off.
        #expect(AskMotionLook.critique(fromAnswer: fault)?.contains("**") == false)
        let long = String(repeating: "Bounces: not seen. ", count: 200)
        #expect((AskMotionLook.critique(fromAnswer: long)?.count ?? 0) <= AskMotionLook.mostCritique)
    }

    @Test("What the look saw goes back to the plan once: the drawing stays, the keys are mended, and it lands")
    func sentBack() throws {
        var talk = try Self.planned()
        #expect(talk.movesIcon)
        let drawn = talk.steps.count
        talk.reviseMotion(seen: "Opens: 0.2 s\nBounces: not seen")
        let asked = talk.messages.last?["content"]?.stringValue ?? ""
        #expect(asked.contains("Bounces: not seen"))
        #expect(asked.contains("replace true"))
        #expect(asked.contains("Left out:"))
        // Where the keys put the parts goes with it, so a miss is plain in numbers.
        #expect(asked.contains("Where your keys put each moving part"), "\(asked)")
        #expect(talk.steps.count == drawn, "the drawing and its keys stay, to be mended")
        _ = talk.take(AskMotionTests.reply("set_keys", try AskMotionTests.args(#"{"layer":"$1/whole","property":"position","replace":true,"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":-3}},{"seconds":0.7,"value":{"x":0,"y":0}},{"seconds":1,"value":{"x":0,"y":0}}]}"#)))
        // No second beats review: the look was the review.
        guard case .planned(let plan) = talk.take(AskMotionTests.said("The bounce is keyed.\nLeft out: nothing")) else {
            Issue.record("the mended plan lands"); return
        }
        #expect(plan.steps.filter { $0.tool == "add_drawing" }.count == 1)
        #expect(plan.steps.filter { $0.tool == "set_keys" }.count == 2)
        #expect(plan.unplanned == nil)
    }

    @Test("The mend after a look is a fresh short talk: the rules, then the request, the drawing, the keys as they play and what was seen")
    func freshMend() throws {
        var talk = try Self.planned()
        // Two keys for the same value, the second replacing the first: only
        // the one that plays is shown to be mended.
        talk.reviseMotion(seen: "warm up")
        _ = talk.take(AskMotionTests.reply("set_keys", try AskMotionTests.args(#"{"layer":"$1/whole","property":"scale","replace":true,"keys":[{"seconds":0,"value":100},{"seconds":0.4,"value":140},{"seconds":1,"value":100}]}"#)))
        let system = talk.messages.first
        talk.reviseMotion(seen: "Opens: 0.2 s\nBounces: not seen")
        // No earlier turn to anchor on: the model's own calls, the rule
        // send-backs and the beats review are gone.
        #expect(talk.messages.count == 2, "\(talk.messages.count) messages")
        #expect(talk.messages.first == system)
        let asked = talk.messages.last?["content"]?.stringValue ?? ""
        #expect(talk.messages.last?["role"]?.stringValue == "user")
        #expect(asked.contains(Self.request))
        #expect(asked.contains("1) the thing 2) parts 3) beats"), "the design goes with it")
        #expect(asked.contains(#"id="whole""#), "the drawing goes with it, its part ids readable")
        #expect(asked.contains("140"), "the keys that play")
        #expect(!asked.contains("125"), "not the keys a replace took away: \(asked)")
        #expect(asked.contains("Bounces: not seen"))
        #expect(asked.contains("Where your keys put each moving part"))
        #expect(asked.contains("Left out:"))
        // The steps stay, so `$1` is still the drawing and the new keys replace.
        _ = talk.take(AskMotionTests.reply("set_keys", try AskMotionTests.args(#"{"layer":"$1/whole","property":"position","replace":true,"keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":-3}},{"seconds":1,"value":{"x":0,"y":0}}]}"#)))
        guard case .planned(let plan) = talk.take(AskMotionTests.said("Done.\nLeft out: nothing")) else {
            Issue.record("the mended plan lands"); return
        }
        #expect(plan.steps.first?.tool == "add_drawing")
    }

    @Test("A mended plan that still leaves a beat out says so on the row")
    func stillLeftOut() throws {
        var talk = try Self.planned()
        talk.reviseMotion(seen: "Bounces: not seen")
        guard case .planned(let plan) = talk.take(AskMotionTests.said("Done.\nLeft out: the bounce")) else {
            Issue.record("it lands"); return
        }
        #expect(plan.unplanned?.things == ["the bounce"])
    }

    @Test("A look starts only while the request has time for it, and once")
    func onlyWithTime() {
        #expect(AskMotionLook.looks(after: 90, looked: 0))
        #expect(!AskMotionLook.looks(after: AskMotionLook.latestStart + 1, looked: 0))
        #expect(!AskMotionLook.looks(after: 90, looked: AskMotionLook.mostLooks))
    }

    @Test("After a look the rule checks send back once more, not twice")
    func oneMoreSendBack() throws {
        var talk = try Self.planned()
        talk.reviseMotion(seen: "Bounces: not seen")
        // A key that never changes is a rule problem: sent back once, then it lands.
        _ = talk.take(AskMotionTests.reply("set_keys", try AskMotionTests.args(#"{"layer":"$1/whole","property":"rotation","replace":true,"keys":[{"seconds":0,"value":0},{"seconds":1,"value":0}]}"#)))
        guard case .again = talk.take(AskMotionTests.said("Done.\nLeft out: nothing")) else { Issue.record("sent back once"); return }
        guard case .planned = talk.take(AskMotionTests.said("Done.\nLeft out: nothing")) else { Issue.record("then it lands"); return }
    }

    @Test("A still icon is never looked at as a moving one")
    func stillIcon() {
        let still = AskConversation(request: "make a trash can icon", documentRead: #"{"kind":"picture","canvas":{"width":1440,"height":1024}}"#,
                                    paints: true)
        #expect(!still.movesIcon)
    }

    @Test("The live line says the motion is being checked and then fixed")
    func stages() {
        #expect(AskStage.checkingMotion.line == "Checking the motion")
        #expect(AskStage.fixingMotion.line == "Fixing the motion")
    }
}
