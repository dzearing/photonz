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

    // MARK: - The picture, as well as the tile

    @Test func theThumbnailIsDueInAHundredMilliseconds() {
        #expect(RecordingStopBudget.stopToThumbnailMS == 100)
        #expect(RecordingStopBudget.isWithin(stopToThumbnailMS: 100))
        #expect(!RecordingStopBudget.isWithin(stopToThumbnailMS: 101))
        #expect(!RecordingStopBudget.isWithin(stopToThumbnailMS: .infinity))
    }

    @Test func theEditorShowsThePictureInThreeHundredMilliseconds() {
        #expect(RecordingStopBudget.stopToEditorPictureMS == 300)
        #expect(RecordingStopBudget.isWithin(stopToEditorPictureMS: 299))
        #expect(!RecordingStopBudget.isWithin(stopToEditorPictureMS: 301))
        #expect(!RecordingStopBudget.isWithin(stopToEditorPictureMS: -5))
    }
}
