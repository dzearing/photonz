import Foundation

/// How long writing a video took against how long the video runs.
///
/// A person exporting a five minute recording should not wait five minutes for
/// the file: Premiere writes a screen recording several times faster than it
/// plays. A walk holds the write to a share of the film's length with this, so
/// a write that slows back down fails the day it happens.
public enum VideoWritePace {

    /// The write's time over the film's, or nil for a film with no length.
    public static func share(writtenMS: Int, runsSeconds: Double) -> Double? {
        guard runsSeconds > 0, runsSeconds.isFinite else { return nil }
        return Double(writtenMS) / 1000 / runsSeconds
    }

    /// Whether the write took no more than `limit` of the film's length.
    public static func isWithin(_ limit: Double, writtenMS: Int, runsSeconds: Double) -> Bool {
        guard let share = share(writtenMS: writtenMS, runsSeconds: runsSeconds) else { return false }
        return share <= limit
    }
}
