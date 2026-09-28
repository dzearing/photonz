import Foundation
import PhotonzCore
import Testing

@Suite("A stopped recording reaches history at once")
struct RecordingStopBudgetTests {
    @Test func theBudgetIsThreeHundredMilliseconds() {
        #expect(RecordingStopBudget.stopToTileMS == 300)
    }

    @Test func aTileInsideTheBudgetPasses() {
        #expect(RecordingStopBudget.isWithin(stopToTileMS: 0))
        #expect(RecordingStopBudget.isWithin(stopToTileMS: 120))
        #expect(RecordingStopBudget.isWithin(stopToTileMS: 300))
    }

    @Test func aTileOverTheBudgetFails() {
        #expect(!RecordingStopBudget.isWithin(stopToTileMS: 301))
        #expect(!RecordingStopBudget.isWithin(stopToTileMS: 1_400))
    }

    @Test func aReadingThatIsNotANumberFails() {
        #expect(!RecordingStopBudget.isWithin(stopToTileMS: .nan))
        #expect(!RecordingStopBudget.isWithin(stopToTileMS: -1))
    }
}
