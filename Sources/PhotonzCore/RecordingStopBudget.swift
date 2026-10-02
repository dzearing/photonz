import Foundation

/// How long a stopped recording may take to appear in history.
///
/// Stop is the person's last act of recording and history is where they look
/// next, so anything slower than a beat reads as the app processing the
/// recording. Everything a tile can wait for (poster frame, duration, any
/// analysis) runs after the tile is up; this budget covers only the stream
/// stopping, the file closing and the file being filed.
public enum RecordingStopBudget {
    /// Stop to history tile, in milliseconds.
    public static let stopToTileMS: Double = 300

    /// Stop to the tile showing the recording's picture, in milliseconds.
    /// The last frame the stream delivered is in memory at Stop, so the
    /// picture never waits for the file.
    public static let stopToThumbnailMS: Double = 100

    /// Stop to an editor opened on the recording showing its picture, in
    /// milliseconds: the editor opens on that same last frame.
    public static let stopToEditorPictureMS: Double = 300

    /// Whether a measured Stop-to-tile time is inside the budget. A reading
    /// that is not a real duration never passes.
    public static func isWithin(stopToTileMS ms: Double) -> Bool {
        within(ms, stopToTileMS)
    }

    public static func isWithin(stopToThumbnailMS ms: Double) -> Bool {
        within(ms, stopToThumbnailMS)
    }

    public static func isWithin(stopToEditorPictureMS ms: Double) -> Bool {
        within(ms, stopToEditorPictureMS)
    }

    private static func within(_ ms: Double, _ budget: Double) -> Bool {
        ms.isFinite && ms >= 0 && ms <= budget
    }
}
