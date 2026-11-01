import Foundation
import Testing
@testable import PhotonzCore

/// The one live line a working request shows in the Agent panel
/// (`while-ask-works-the-agent-panel-says-what-it-is`, the user, 2026-10-24:
/// "I'd like some indication of what's happening for the request").
@Suite("Ask says what it is doing")
struct AskProgressTests {

    @Test("Each stage reads as a few plain words")
    func plainWords() {
        #expect(AskStage.starting.line == "Getting ready")
        #expect(AskStage.gettingModelReady.line == "Getting the model ready")
        #expect(AskStage.reading(video: false).line == "Reading the picture")
        #expect(AskStage.reading(video: true).line == "Reading the video")
        #expect(AskStage.lookingAtCanvas.line == "Looking at the canvas")
        #expect(AskStage.thinking(turn: 1).line == "Thinking it through")
        #expect(AskStage.thinking(turn: 2).line == "Working out the steps")
        #expect(AskStage.lookingUp(tool: "list_components").line == "Looking through the components")
        #expect(AskStage.lookingUp(tool: "list_styles").line == "Looking through the styles")
        #expect(AskStage.lookingUp(tool: "something_new").line == "Looking something up")
        #expect(AskStage.making(step: 1, of: 1).line == "Making the change")
        #expect(AskStage.making(step: 3, of: 7).line == "Making the changes, 3 of 7")
        #expect(AskStage.gettingPainterReady.line == "Getting ready to paint")
    }

    @Test("A drawing names its subject, and its part when there is more than one")
    func parts() {
        #expect(AskStage.painting(subject: "a dog", part: 1, of: 1).line == "Painting a dog")
        #expect(AskStage.painting(subject: "the dog", part: 2, of: 3).line == "Painting the dog, 2 of 3")
        #expect(AskStage.drawing(subject: "a fox", part: 1, of: 2).line == "Drawing a fox, 1 of 2")
        #expect(AskStage.planningDrawing(subject: "a fox", part: 1, of: 1).line == "Planning a fox")
        #expect(AskStage.checking(subject: "a fox", part: 1, of: 1).line == "Checking a fox")
        #expect(AskStage.tracing(subject: "a fox", part: 1, of: 1).line == "Turning a fox into layers")
        #expect(AskStage.photo(subject: "a beach", part: 1, of: 1).line == "Making a photo of a beach")
    }

    @Test("A try again says why in a few words")
    func tryingAgain() {
        #expect(AskStage.tryingAgain(.seenAs("a cat.")).line == "Trying again: it looked like a cat")
        // The seeing model's capital letter does not land mid-line (seen 2026-11-01).
        #expect(AskStage.tryingAgain(.seenAs("Two foxes")).line == "Trying again: it looked like two foxes")
        #expect(AskStage.tryingAgain(.seenAs("NASA logo")).line == "Trying again: it looked like NASA logo")
        #expect(AskStage.tryingAgain(.missed("The tail is curled.")).line == "Trying again: missed the tail is curled")
        #expect(AskStage.tryingAgain(.offTheEdge).line == "Painting again: it ran off the edge")
        #expect(AskStage.keepingClosest.line == "Keeping the closest try")
    }

    @Test("A line fits the panel's budget, cutting the subject and never the part")
    func fitsTheBudget() {
        let long = AskStage.painting(subject: "a very small red fox curled up asleep under a pine tree", part: 2, of: 3)
        #expect(long.line.count <= AskStage.budget)
        #expect(long.line.hasPrefix("Painting a very small"))
        #expect(long.line.hasSuffix("…, 2 of 3"))
        // The tooltip keeps the whole thing.
        #expect(long.fullLine == "Painting a very small red fox curled up asleep under a pine tree, 2 of 3")
        let why = AskStage.tryingAgain(.missed("the fox's tail wraps around its front paws while it sleeps"))
        #expect(why.line.count <= AskStage.budget)
        #expect(why.line.hasSuffix("…"))
        for stage in AskStage.examples {
            #expect(stage.line.count <= AskStage.budget, "\(stage.line)")
        }
    }

    @Test("No em dashes, no tool names, no model names in what it says")
    func plainCopy() {
        for stage in AskStage.examples {
            #expect(!stage.line.contains("—"))
            #expect(!stage.line.contains("_"), "\(stage.line)")
            #expect(!stage.line.lowercased().contains("qwen"))
            #expect(!stage.line.lowercased().contains("model ") || stage == .gettingModelReady)
        }
    }

    @Test("Time spent shows once a stage passes five seconds")
    func elapsed() {
        #expect(AskStage.elapsed(0) == nil)
        #expect(AskStage.elapsed(4.9) == nil)
        #expect(AskStage.elapsed(5) == "5s")
        #expect(AskStage.elapsed(42.6) == "42s")
        #expect(AskStage.elapsed(65) == "1:05")
        #expect(AskStage.elapsed(600) == "10:00")
    }

    @Test("A stage log keeps each change of line once, with when it came")
    func log() {
        var log = AskStageLog()
        log.enter(.reading(video: false), at: 0)
        log.enter(.reading(video: false), at: 0.4)
        log.enter(.thinking(turn: 1), at: 1)
        log.enter(.painting(subject: "a dog", part: 1, of: 1), at: 12)
        log.end(at: 30)
        #expect(log.entries.map(\.line) == ["Reading the picture", "Thinking it through", "Painting a dog"])
        #expect(log.longestGap == 18)
        #expect(log.lines == ["0.0s Reading the picture", "1.0s Thinking it through", "12.0s Painting a dog", "30.0s done"])
    }

    @Test("The longest gap with no change of line is measured to the end")
    func longestGapToTheEnd() {
        var log = AskStageLog()
        log.enter(.starting, at: 0)
        log.end(at: 3)
        #expect(log.longestGap == 3)
        #expect(AskStageLog().longestGap == 0)
    }

    @Test("While the model reads, the line says how far through; once it writes, it says so")
    func modelProgress() throws {
        // What llama-server's /slots said part way through a 9,946 token
        // prompt, measured on 2026-11-01: n_prompt_tokens grows a batch at a
        // time, and the whole is never given, so Ask's own estimate is the whole.
        let reading = try AgentJSON.parse(Data("""
            [{"id":0,"is_processing":true,"n_prompt_tokens":4138,"n_prompt_tokens_processed":3626,
              "n_prompt_tokens_cache":0,"next_token":[{"n_decoded":0}]}]
            """.utf8))
        let progress = try #require(AskModelProgress(slots: reading))
        #expect(progress == AskModelProgress(read: 4138, written: 0))
        #expect(AskStage.thinking(turn: 1, at: progress, expected: 10_000) == .readingRequest(percent: 41))
        #expect(AskStage.readingRequest(percent: 41).line == "Reading your request, 41%")
        // An estimate under the truth never says 100 before it writes.
        #expect(AskStage.thinking(turn: 1, at: AskModelProgress(read: 12_000, written: 0), expected: 10_000)
                == .readingRequest(percent: 99))
        #expect(AskStage.thinking(turn: 1, at: AskModelProgress(read: 9_946, written: 20), expected: 10_000) == .writing)
        #expect(AskStage.writing.line == "Writing the steps")
        // Nothing known (another runtime, or the server between requests).
        #expect(AskStage.thinking(turn: 2, at: nil, expected: 10_000) == .thinking(turn: 2))
        let idle = try AgentJSON.parse(Data("""
            [{"id":0,"is_processing":false,"n_prompt_tokens":9975,"next_token":[{"n_decoded":0}]}]
            """.utf8))
        #expect(AskModelProgress(slots: idle) == nil)
        #expect(AskModelProgress(slots: try AgentJSON.parse(Data("{}".utf8))) == nil)
    }

    @Test("The painter's own steps become how far through the painting is")
    func painterSteps() {
        #expect(AskPainterSaid("painting") == .painting(again: false, step: nil, of: nil))
        #expect(AskPainterSaid("painting 3/9") == .painting(again: false, step: 3, of: 9))
        #expect(AskPainterSaid("painting again 9/9\n") == .painting(again: true, step: 9, of: 9))
        #expect(AskPainterSaid("tracing") == .tracing)
        #expect(AskPainterSaid("") == nil)
        #expect(AskPainterSaid("painting 3/9")?.percent == 33)
        #expect(AskPainterSaid("painting 9/9")?.percent == 99)
        #expect(AskPainterSaid("painting")?.percent == nil)
        #expect(AskStage.painting(subject: "a fox", part: 1, of: 1, percent: 33).line == "Painting a fox, 33%")
        #expect(AskStage.painting(subject: "the dog", part: 2, of: 3, percent: 50).line == "Painting the dog, 2 of 3, 50%")
        let long = AskStage.painting(subject: "a very small red fox curled up asleep", part: 2, of: 3, percent: 50)
        #expect(long.line.count <= AskStage.budget)
        #expect(long.line.hasSuffix("…, 2 of 3, 50%"))
    }
}

