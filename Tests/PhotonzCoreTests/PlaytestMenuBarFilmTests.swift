import Foundation
import Testing
@testable import PhotonzCore

/// Filming the menu bar while something happens in the window, and counting
/// the frames in which the app's menus changed.
///
/// The user, 2026-10-11: "when a video is playing back, I am seeing the menu at
/// the top of the screen flickering". The bar is drawn by the system, outside
/// the window every other film takes, so this films it on its own.
@Suite("Filming the menu bar")
struct PlaytestMenuBarFilmTests {
    private func decode(_ json: String) throws -> PlaytestScript {
        try PlaytestScript.decode(Data(json.utf8))
    }

    @Test("A filmMenuBar step names its film, how long to film and how many changes it allows")
    func parses() throws {
        let script = try decode("""
        { "steps": [ { "do": "filmMenuBar", "name": "playing", "seconds": 10, "atMostChanges": 0 } ] }
        """)
        guard case .filmMenuBar(let name, let seconds, let atMost) = script.steps[0] else {
            Issue.record("filmMenuBar"); return
        }
        #expect(name == "playing")
        #expect(seconds == 10)
        #expect(atMost == 0)
        #expect(script.steps[0].name == "filmMenuBar")
        #expect(PlaytestStep.names.contains("filmMenuBar"))
    }

    @Test("Left without a ceiling it only reports what it saw")
    func ceilingIsOptional() throws {
        let script = try decode("""
        { "steps": [ { "do": "filmMenuBar", "name": "paused", "seconds": 2 } ] }
        """)
        guard case .filmMenuBar(_, _, let atMost) = script.steps[0] else { Issue.record("filmMenuBar"); return }
        #expect(atMost == nil)
    }

    @Test("A film is a few seconds to half a minute long, and its ceiling is not negative")
    func bounds() {
        #expect(throws: (any Error).self) {
            try decode(#"{ "steps": [ { "do": "filmMenuBar", "name": "x", "seconds": 0.1 } ] }"#)
        }
        #expect(throws: (any Error).self) {
            try decode(#"{ "steps": [ { "do": "filmMenuBar", "name": "x", "seconds": 60 } ] }"#)
        }
        #expect(throws: (any Error).self) {
            try decode(#"{ "steps": [ { "do": "filmMenuBar", "name": "x", "seconds": 5, "atMostChanges": -1 } ] }"#)
        }
    }

    /// The bar a lock leaves up is the login window's, not the app's.
    @Test("It does not run on a locked screen")
    func refusedUnderALock() {
        #expect(!PlaytestLockSafety.stepsThatSurviveALock.contains("filmMenuBar"))
    }
}
