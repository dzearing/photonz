import Foundation
import Testing
@testable import PhotonzCore

/// Ask's plan arrives as it is written (`while-ask-writes-a-long-plan-its-line-names-each`):
/// a component sheet took 97 s on one line that only said "Writing the steps",
/// so the built-in server's answer is now streamed and the line names each
/// step and the part it has reached.
@Suite("Ask's plan is read as it is written")
struct AskStreamedAnswerTests {

    /// llama-server b11826's own lines for one answer of two calls, measured
    /// on 2026-11-18 (Qwen3.5 4B, cut to the fields that matter).
    static let twoCalls = [
        #"data: {"choices":[{"finish_reason":null,"index":0,"delta":{"role":"assistant","content":null}}],"object":"chat.completion.chunk"}"#,
        #"data: {"choices":[{"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"id":"n0TT","type":"function","function":{"name":"add_component","arguments":"{"}}]}}]}"#,
        #"data: {"choices":[{"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"name\":\""}}]}}]}"#,
        #"data: {"choices":[{"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"Tog"}}]}}]}"#,
        #"data: {"choices":[{"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"gle\""}}]}}]}"#,
        #"data: {"choices":[{"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":",\"parts\":[{\"name\": \"Track\", \"shape\": \"rect\", \"width\": 100}, "}}]}}]}"#,
        #"data: {"choices":[{"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"name\": \"Knob\", \"shape\": \"circle\", \"width\": 20}]}"}}]}}]}"#,
        #"data: {"choices":[{"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":1,"id":"x9Yq","type":"function","function":{"name":"add_component","arguments":"{\"name\":\"Button\",\"parts\":[{\"name\": \"Background\", \"width\": 80}]}"}}]}}]}"#,
        #"data: {"choices":[{"finish_reason":"tool_calls","index":0,"delta":{}}],"object":"chat.completion.chunk","timings":{"cache_n":0,"prompt_n":351}}"#,
        "data: [DONE]",
    ]

    /// The same answer as the server gives it without streaming.
    static let twoCallsWhole = #"""
        {"choices":[{"finish_reason":"tool_calls","index":0,"message":{"role":"assistant","content":"","tool_calls":[
          {"type":"function","function":{"name":"add_component","arguments":"{\"name\":\"Toggle\",\"parts\":[{\"name\": \"Track\", \"shape\": \"rect\", \"width\": 100}, {\"name\": \"Knob\", \"shape\": \"circle\", \"width\": 20}]}"},"id":"n0TT"},
          {"type":"function","function":{"name":"add_component","arguments":"{\"name\":\"Button\",\"parts\":[{\"name\": \"Background\", \"width\": 80}]}"},"id":"x9Yq"}]}}],
         "timings":{"cache_n":0,"prompt_n":351}}
        """#

    @Test("A streamed answer makes the same reply as the whole one")
    func sameReply() throws {
        var answer = AskStreamedAnswer()
        for line in Self.twoCalls { answer.take(line) }
        #expect(answer.finished)
        let whole = try AgentJSON.parse(Data(Self.twoCallsWhole.utf8))
        #expect(AskServerChat.reply(fromServer: answer.reply) == AskServerChat.reply(fromServer: whole))
        #expect(answer.reply["timings"]?["prompt_n"]?.doubleValue == 351)
    }

    @Test("Words the model writes come together in order")
    func words() {
        var answer = AskStreamedAnswer()
        answer.take(#"data: {"choices":[{"index":0,"delta":{"role":"assistant","content":null}}]}"#)
        answer.take(#"data: {"choices":[{"index":0,"delta":{"content":"Planned a "}}]}"#)
        answer.take("")
        answer.take(#"data: {"choices":[{"index":0,"delta":{"content":"sheet."}}]}"#)
        answer.take(#"data: {"choices":[{"finish_reason":"stop","index":0,"delta":{}}]}"#)
        answer.take("data: [DONE]")
        let reply = AskServerChat.reply(fromServer: answer.reply)
        #expect(reply["message"]?["content"]?.stringValue == "Planned a sheet.")
        #expect(reply["message"]?["tool_calls"] == nil)
        #expect(answer.writing.step == 0)
    }

    @Test("An answer cut off part way is kept as far as it got, as without streaming")
    func cutOff() {
        var answer = AskStreamedAnswer()
        answer.take(#"data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"a","type":"function","function":{"name":"add_component","arguments":"{"}}]}}]}"#)
        answer.take(#"data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"name\":\"Toggle\",\"parts\":[{\"name\": \"Track\", \"width"}}]}}]}"#)
        answer.take(#"data: {"choices":[{"finish_reason":"length","index":0,"delta":{}}]}"#)
        answer.take("data: [DONE]")
        let calls = AskServerChat.reply(fromServer: answer.reply)["message"]?["tool_calls"]?.arrayValue
        #expect(calls?.count == 1)
        // Unreadable arguments stay the words they were, as they do today.
        #expect(calls?.first?["function"]?["arguments"]?.stringValue == #"{"name":"Toggle","parts":[{"name": "Track", "width"#)
    }

    @Test("The server's complaint, before or during the answer, is the reply's error")
    func errors() {
        // Mid-answer: llama-server sends an `error:` event (server_sent_event).
        var during = AskStreamedAnswer()
        during.take(#"data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"a","function":{"name":"add_shape","arguments":"{"}}]}}]}"#)
        during.take(#"error: {"code":500,"message":"Failed to parse tool call arguments as JSON: [json.exception.parse_error.101]","type":"server_error"}"#)
        during.take("data: [DONE]")
        let said = AskServerChat.reply(fromServer: during.reply)["error"]?.stringValue ?? ""
        #expect(AskConversation.isUnreadableReply(said))
        // Before it: the whole body is one JSON error, not a stream.
        var before = AskStreamedAnswer()
        before.take(#"{"error":{"code":500,"message":"No user query found in messages.","type":"server_error"}}"#)
        #expect(AskServerChat.reply(fromServer: before.reply)["error"]?.stringValue == "No user query found in messages.")
        // Nothing at all.
        #expect(AskServerChat.reply(fromServer: AskStreamedAnswer().reply)["error"] != nil)
    }

    @Test("While a call is written, the line knows its step, its name and the part it has reached")
    func writingSoFar() {
        var answer = AskStreamedAnswer()
        var seen: [AskWriting] = []
        for line in Self.twoCalls {
            answer.take(line)
            if seen.last != answer.writing { seen.append(answer.writing) }
        }
        #expect(seen.map { AskStage.writing($0).line } == [
            "Writing the steps",
            "Writing step 1",
            "Writing step 1: Toggle",
            "Writing step 1: Toggle, Track",
            "Writing step 1: Toggle, Knob",
            "Writing step 2: Button, Background",
        ])
        #expect(answer.writing.tool == "add_component")
    }

    @Test("A drawing's subject names its step; a long string inside is never read as a name")
    func subjects() {
        var reader = AskArgumentsReader()
        reader.read(#"{"subject": "A red fox asleep", "svg": "<svg><g name=\"x\"/></svg>", "x": 10}"#)
        #expect(reader.subject == "A red fox asleep")
        #expect(reader.part == nil)
        #expect(AskStage.writing(AskWriting(step: 1, subject: reader.subject)).line == "Writing step 1: a red fox asleep")
        // A name beats a title or text met first, and escapes are read.
        var text = AskArgumentsReader()
        text.read(#"{"text": "Say \"hi\"\nthere", "#)
        #expect(text.subject == #"Say "hi" there"#)
        text.read(#""name": "Greeting"}"#)
        #expect(text.subject == "Greeting")
        // A list of strings is not a name.
        var list = AskArgumentsReader()
        list.read(#"{"tags": ["a", "b"], "looks": [{"name": "On", "changes": [{"part": "Knob"}]}]}"#)
        #expect(list.subject == nil)
        #expect(list.part == "On")
        // A part named as its whole is not said twice.
        var same = AskArgumentsReader()
        same.read(#"{"name": "Badge", "parts": [{"name": "Badge"}]}"#)
        #expect(AskStage.writing(AskWriting(step: 3, subject: same.subject, part: same.part)).line == "Writing step 3: Badge")
    }

    @Test("A long name is cut to the panel's budget, the step never")
    func budget() {
        let long = AskWriting(step: 12, subject: "Segmented Control With A Very Long Name", part: "Selected Segment Background")
        let line = AskStage.writing(long).line
        #expect(line.count <= AskStage.budget)
        #expect(line == "Writing step 12: Segmen…, Selected Segm…")
        #expect(line.hasSuffix("…"))
        // Measured 2026-11-18: every part of a Segmented Control read
        // "Writing step 6: Segmented Control…", 22 s with no visible change.
        // The name is cut first, so each part still shows.
        let parts = ["Background", "Segment 1", "Selected", "Disabled"].map {
            AskStage.writing(AskWriting(step: 6, subject: "Segmented Control", part: $0)).line
        }
        #expect(parts == [
            "Writing step 6: Segmented…, Background",
            "Writing step 6: Segmented…, Segment 1",
            "Writing step 6: Segmented…, Selected",
            "Writing step 6: Segmented…, Disabled",
        ])
        #expect(Set(parts).count == parts.count)
        #expect(parts.allSatisfy { $0.count <= AskStage.budget })
    }

    @Test("The server's count of tokens written says writing, with what the stream heard")
    func fromSlots() {
        let heard = AskWriting(step: 4, subject: "Toggle")
        #expect(AskStage.thinking(turn: 1, at: AskModelProgress(read: 9_946, written: 20), expected: 10_000, writing: heard)
                == .writing(heard))
        // Measured 2026-11-18: /slots read a moment late said 0 written
        // after the stream had heard the answer begin, and the line went back
        // to reading. Once a step is heard, it is writing.
        #expect(AskStage.thinking(turn: 1, at: AskModelProgress(read: 9_946, written: 0), expected: 10_000, writing: heard)
                == .writing(heard))
        #expect(AskStage.thinking(turn: 1, at: AskModelProgress(read: 9_946, written: 0), expected: 10_000)
                == .readingRequest(percent: 99))
    }

    @Test("A new step or name is said at once; a new part at most once a second")
    func pace() {
        var pacer = AskWritingPacer()
        let readings: [(AskWriting, Double)] = [
            (AskWriting(), 0),
            (AskWriting(step: 1), 0),
            (AskWriting(step: 1, subject: "Toggle"), 0.2),
            (AskWriting(step: 1, subject: "Toggle", part: "Track"), 0.5),
            (AskWriting(step: 1, subject: "Toggle", part: "Knob"), 1.3),
            (AskWriting(step: 1, subject: "Toggle", part: "Knob"), 1.5),
            (AskWriting(step: 1, subject: "Toggle", part: "Lid"), 1.8),
            (AskWriting(step: 2), 1.9),
            (AskWriting(step: 2), 4),
        ]
        let said = readings.map { pacer.says($0.0, at: $0.1) }
        #expect(said == [false, true, true, false, true, false, false, true, false])
    }
}
