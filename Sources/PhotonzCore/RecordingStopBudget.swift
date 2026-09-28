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

    /// Whether a measured Stop-to-tile time is inside the budget. A reading
    /// that is not a real duration never passes.
    public static func isWithin(stopToTileMS ms: Double) -> Bool {
        ms.isFinite && ms >= 0 && ms <= stopToTileMS
    }
}
