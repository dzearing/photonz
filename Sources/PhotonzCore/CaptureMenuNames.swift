/// The names the capture commands answer to, in one place.
///
/// Two menus offer the same commands — the menu-bar icon's drop-down and the
/// editor's Capture menu — and a command a person learned in one has to be
/// findable by the same name in the other, so the strings live here rather than
/// being typed out twice.
///
/// `history` and `recording` are the two names that change with what is on
/// screen. `historyNames` lists both readings of the history item, which is how
/// the app finds that item in a live menu whichever way it currently reads.
public enum CaptureMenuNames {
    public static let captureRegion = "Capture Region"
    public static let captureFullScreen = "Capture Full Screen"
    public static let startRecording = "Record Screen / Video…"
    public static let stopRecording = "Stop Recording"
    public static let editLastCapture = "Edit Last Capture"
    public static let showHistory = "Show History"
    public static let hideHistory = "Hide History"

    /// What the history item offers to do next: hide the overlay while it is
    /// up, show it while it is not.
    public static func history(isShown: Bool) -> String {
        isShown ? hideHistory : showHistory
    }

    /// What the recording item offers to do next.
    public static func recording(isRecording: Bool) -> String {
        isRecording ? stopRecording : startRecording
    }

    /// Every reading the history item can carry.
    public static let historyNames = [showHistory, hideHistory]
}
