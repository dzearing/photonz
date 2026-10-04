import Foundation
import Testing
@testable import PhotonzCore

/// "No two controls in a track header overlap" has to be MEASURED, and a
/// picture of two buttons 1 point apart looks the same as one of them 0 apart.
/// `expectApart` reads the boxes of the named controls off the window and
/// fails naming the pair that comes closer than `gap`; `expectTimeline`'s
/// `trackColumn` claims how wide the column of track names is.
@Suite("expectApart and the track column claim")
struct ExpectApartStepTests {

    @Test("An expectApart step names the controls and the least gap between them")
    func namesControlsAndGap() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "expectApart", "controls": ["Track V1", "Track V1 Hide", "Key V1"], "gap": 4,
                       "whole": ["Track V1"] } ] }
        """.utf8))
        guard case .expectApart(let controls, let gap, let whole) = script.steps[0] else {
            Issue.record("expectApart"); return
        }
        #expect(controls == ["Track V1", "Track V1 Hide", "Key V1"])
        #expect(gap == 4)
        #expect(whole == ["Track V1"])
        #expect(script.steps[0].name == "expectApart")
        #expect(PlaytestStep.names.contains("expectApart"))
    }

    @Test("The gap is 4 points unless the walk says otherwise, and nothing has to be whole")
    func defaults() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "expectApart", "controls": ["A", "B"] } ] }
        """.utf8))
        guard case .expectApart(_, let gap, let whole) = script.steps[0] else {
            Issue.record("expectApart"); return
        }
        #expect(gap == 4)
        #expect(whole.isEmpty)
    }

    @Test("An expectApart step needs two controls to measure between")
    func needsTwo() {
        #expect(throws: (any Error).self) {
            try PlaytestScript.decode(Data("""
            { "steps": [ { "do": "expectApart", "controls": ["A"] } ] }
            """.utf8))
        }
        #expect(throws: (any Error).self) {
            try PlaytestScript.decode(Data("""
            { "steps": [ { "do": "expectApart" } ] }
            """.utf8))
        }
    }

    @Test("A negative gap is refused")
    func noNegativeGap() {
        #expect(throws: (any Error).self) {
            try PlaytestScript.decode(Data("""
            { "steps": [ { "do": "expectApart", "controls": ["A", "B"], "gap": -1 } ] }
            """.utf8))
        }
    }

    @Test("expectApart reads the app and no names from accessibility, so it runs under a lock")
    func survivesALock() {
        #expect(PlaytestLockSafety.stepsThatSurviveALock.contains("expectApart"))
    }

    @Test("expectTimeline claims how wide the track column is")
    func trackColumnClaim() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "expectTimeline", "trackColumn": 180 } ] }
        """.utf8))
        guard case .expectTimeline(let claim) = script.steps[0] else {
            Issue.record("expectTimeline"); return
        }
        #expect(claim.trackColumn == 180)
        #expect(claim.claimsSomething)
        #expect(PlaytestTimelineClaim().trackColumn == nil)
        #expect(throws: (any Error).self) {
            try PlaytestScript.decode(Data("""
            { "steps": [ { "do": "expectTimeline", "trackColumn": 0 } ] }
            """.utf8))
        }
    }
}
