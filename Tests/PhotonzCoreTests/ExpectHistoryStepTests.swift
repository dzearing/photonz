import Foundation
@testable import PhotonzCore
import Testing

// The history strip's filter and its keyboard focus live in the strip, where
// no screenshot can say which tile has the keys and no accessibility name says
// which filter the strip is showing. `expectHistory` asks the strip itself.
@Suite("expectHistory step")
struct ExpectHistoryStepTests {
    private func decode(_ json: String) throws -> PlaytestScript {
        try PlaytestScript.decode(Data(json.utf8))
    }

    @Test("It claims the filter, the kind of capture focused, and which capture")
    func decodesEveryClaim() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectHistory", "filter": "videos", "focused": "video",
                       "capture": "Recording 0002.mp4" } ] }
        """)
        guard case .expectHistory(let filter, let focused, let capture) = script.steps[0] else {
            Issue.record("expectHistory"); return
        }
        #expect(filter == .videos)
        #expect(focused == .video)
        #expect(capture == "Recording 0002.mp4")
        #expect(script.steps[0].name == "expectHistory")
        #expect(PlaytestStep.names.contains("expectHistory"))
    }

    @Test("Each claim is optional, and none focused is a claim too")
    func takesOneClaim() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectHistory", "focused": "none" } ] }
        """)
        guard case .expectHistory(let filter, let focused, let capture) = script.steps[0] else {
            Issue.record("expectHistory"); return
        }
        #expect(filter == nil)
        #expect(focused == PlaytestHistoryFocus.none)
        #expect(capture == nil)
    }

    @Test("It has to claim something, and only words it knows")
    func refusesEmptyAndUnknown() {
        #expect(throws: (any Error).self) {
            _ = try decode(#"{ "steps": [ { "do": "expectHistory" } ] }"#)
        }
        #expect(throws: (any Error).self) {
            _ = try decode(#"{ "steps": [ { "do": "expectHistory", "filter": "movies" } ] }"#)
        }
        #expect(throws: (any Error).self) {
            _ = try decode(#"{ "steps": [ { "do": "expectHistory", "focused": "picture" } ] }"#)
        }
    }

    @Test("It reads the strip itself, so a lock does not stop it")
    func survivesALock() {
        #expect(PlaytestLockSafety.stepsThatSurviveALock.contains("expectHistory"))
    }
}
