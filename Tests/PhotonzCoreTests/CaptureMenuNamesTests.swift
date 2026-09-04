import Testing
@testable import PhotonzCore

@Suite struct CaptureMenuNamesTests {
    // MARK: The name follows what is on screen

    @Test func historyOffersToShowWhenItIsHidden() {
        #expect(CaptureMenuNames.history(isShown: false) == "Show History")
    }

    @Test func historyOffersToHideWhenItIsShowing() {
        #expect(CaptureMenuNames.history(isShown: true) == "Hide History")
    }

    @Test func recordingOffersToStopWhileItIsRecording() {
        #expect(CaptureMenuNames.recording(isRecording: false) == "Record Screen / Video…")
        #expect(CaptureMenuNames.recording(isRecording: true) == "Stop Recording")
    }

    // MARK: Both readings are known, so a menu item can be found by either

    @Test func historyNamesCoversBothReadings() {
        #expect(CaptureMenuNames.historyNames == ["Show History", "Hide History"])
        #expect(CaptureMenuNames.historyNames.contains(CaptureMenuNames.history(isShown: false)))
        #expect(CaptureMenuNames.historyNames.contains(CaptureMenuNames.history(isShown: true)))
    }
}
