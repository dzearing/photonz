import Foundation
import Testing
@testable import PhotonzCore

/// What Photonz is held to in memory, and how a walk's `memory` step judges a
/// reading against it (`MemoryBudget`, `docs/design/memory.md`).
@Suite("Memory budget")
struct MemoryBudgetTests {

    private let mb = 1_048_576

    @Test func theBudgetIsWrittenDown() {
        #expect(MemoryBudget.idleWithOneScreenshotMB == 300)
        #expect(MemoryBudget.backAfterASessionPercent == 20)
    }

    @Test func aReadingUnderItsCeilingPasses() {
        let check = PlaytestMemoryCheck(underMB: 300)
        let reading = MemoryReading(footprintBytes: 250 * mb, liveEditors: 1)
        #expect(MemoryBudget.verdict(reading, check: check, marks: [:]) == nil)
    }

    @Test func aReadingOverItsCeilingFailsAndSaysBothNumbers() throws {
        let check = PlaytestMemoryCheck(underMB: 300)
        let reading = MemoryReading(footprintBytes: 420 * mb, liveEditors: 1)
        let failure = try #require(MemoryBudget.verdict(reading, check: check, marks: [:]))
        #expect(failure.contains("420 MB"))
        #expect(failure.contains("300 MB"))
    }

    @Test func closedWindowsStillInMemoryFail() throws {
        let check = PlaytestMemoryCheck(editorsAtMost: 0)
        let reading = MemoryReading(footprintBytes: 200 * mb, liveEditors: 3)
        let failure = try #require(MemoryBudget.verdict(reading, check: check, marks: [:]))
        #expect(failure.contains("3 editors"))
    }

    @Test func comingBackWithinThePercentOfAMarkPasses() {
        let check = PlaytestMemoryCheck(withinPercentOf: "start", percent: 20)
        let start = MemoryReading(footprintBytes: 200 * mb, liveEditors: 1)
        #expect(MemoryBudget.verdict(MemoryReading(footprintBytes: 239 * mb, liveEditors: 1),
                                     check: check, marks: ["start": [start]]) == nil)
        #expect(MemoryBudget.verdict(MemoryReading(footprintBytes: 241 * mb, liveEditors: 1),
                                     check: check, marks: ["start": [start]]) != nil)
    }

    @Test func aMarkNobodyTookFails() throws {
        let check = PlaytestMemoryCheck(withinPercentOf: "start")
        let failure = try #require(MemoryBudget.verdict(MemoryReading(footprintBytes: mb, liveEditors: 0),
                                                        check: check, marks: [:]))
        #expect(failure.contains("start"))
    }

    @Test func growthThatKeepsClimbingIsALeakAndALevelOneIsNot() {
        // Five rounds of the same open and close, read after each.
        let leaking = [300, 390, 470, 560, 650].map { $0 * mb }
        let settled = [300, 380, 385, 381, 386].map { $0 * mb }
        #expect(MemoryBudget.keepsGrowing(leaking))
        #expect(!MemoryBudget.keepsGrowing(settled))
    }

    @Test func theStepReadsItsFields() throws {
        let script = try PlaytestScript.decode(Data("""
        {"out": "/tmp/x", "steps": [
          {"do": "memory", "mark": "start"},
          {"do": "memory", "underMB": 400, "editorsAtMost": 0, "withinPercentOf": "start", "percent": 25,
           "risingOver": "round"},
          {"do": "memory", "mark": "round"}
        ]}
        """.utf8))
        guard case .memory(let first) = script.steps[0],
              case .memory(let second) = script.steps[1] else {
            Issue.record("not memory steps")
            return
        }
        #expect(first.mark == "start")
        #expect(second.underMB == 400)
        #expect(second.editorsAtMost == 0)
        #expect(second.withinPercentOf == "start")
        #expect(second.percent == 25)
        #expect(second.risingOver == "round")
        #expect(PlaytestStep.names.contains("memory"))
    }

    @Test func theStepSurvivesALock() {
        #expect(PlaytestLockSafety.stepsThatSurviveALock.contains("memory"))
    }
}
