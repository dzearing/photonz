/// The names the capture commands answer to, in one place.
///
/// Two menus offer the same commands — the menu-bar icon's drop-down and the
/// editor's Capture menu — and a command a person learned in one has to be
/// findable by the same name in the other, so the strings live here rather than
/// being typed out twice.
///
/// `recording` is the one name here that changes with what is on screen, and it
/// changes because starting a recording and stopping one are two different
/// actions. `history` is a setting, so it keeps one name and wears a checkmark
/// while the overlay is up (see `MenuToggleNames`).
public enum CaptureMenuNames {
    public static let captureRegion = "Capture Region"
    public static let captureFullScreen = "Capture Full Screen"
    public static let startRecording = "Record Screen / Video…"
    public static let stopRecording = "Stop Recording"
    public static let editLastCapture = "Edit Last Capture"
    /// One name whichever way the overlay is. The checkmark says which.
    public static let history = "Show History"

    /// What the recording item offers to do next.
    public static func recording(isRecording: Bool) -> String {
        isRecording ? stopRecording : startRecording
    }
}
