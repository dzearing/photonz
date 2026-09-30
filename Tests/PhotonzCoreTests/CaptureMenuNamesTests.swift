import Testing
@testable import PhotonzCore

@Suite struct CaptureMenuNamesTests {
    // MARK: The history item is a setting, so it keeps one name

    /// It used to read "Hide History" while the overlay was up. Now it always
    /// reads the same and carries a checkmark instead (see MenuToggleNames).
    @Test func historyKeepsOneNameWhicheverWayItIs() {
        #expect(CaptureMenuNames.history == "Show History")
    }

    /// The capture commands' own menu: a top-level menu before the pro menu
    /// bar, a submenu of File (Preview's Take Screenshot) with it.
    @Test func theCaptureCommandsAreFiledUnderOneName() {
        #expect(CaptureMenuNames.menuTitle == "Capture")
    }

    // MARK: Recording is an action pair, not a setting

    @Test func recordingOffersToStopWhileItIsRecording() {
        #expect(CaptureMenuNames.recording(isRecording: false) == "Record Screen / Video\u{2026}")
        #expect(CaptureMenuNames.recording(isRecording: true) == "Stop Recording")
    }
}
