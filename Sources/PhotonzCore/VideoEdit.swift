import CoreGraphics
import Foundation

/// Non-destructive trim window for a recording (phase 13.3). Holds the in/out
/// points in seconds; the clip plays (and exports) only within `[inPoint,
/// outPoint]`. Pure value type — the `AVPlayer`/export plumbing lives app-side.
///
/// Editing rules: both points clamp to `[0, duration]`, a minimum window is
/// enforced, and moving one handle past the other **pushes** the other instead
/// of inverting (set-in pushes out forward; set-out pushes in backward). When a
/// push would run off the end of the clip, the moved handle is pulled back so
/// the minimum window still fits.
public struct VideoTrim: Codable, Sendable, Hashable {
    /// Trim start, seconds. Always `<= outPoint - minDuration`.
    public private(set) var inPoint: TimeInterval
    /// Trim end, seconds. Always `>= inPoint + minDuration`.
    public private(set) var outPoint: TimeInterval
    /// The clip length this trim was made against, in seconds. Stored so
    /// `isTrimmed`/`effectiveDuration` need no external duration and the value
    /// survives Codable round-trips.
    public private(set) var clipDuration: TimeInterval

    /// The default minimum kept window, in seconds, so a clip can never trim to
    /// nothing.
    public static let defaultMinDuration: TimeInterval = 0.1

    /// A full-clip trim for a recording of `duration` seconds.
    public init(duration: TimeInterval) {
        let d = max(0, duration)
        self.inPoint = 0
        self.outPoint = d
        self.clipDuration = d
    }

    /// A trim with explicit points, clamped into `[0, duration]` and ordered.
    public init(inPoint: TimeInterval, outPoint: TimeInterval, duration: TimeInterval,
                minDuration: TimeInterval = VideoTrim.defaultMinDuration) {
        let d = max(0, duration)
        let lo = min(max(0, inPoint), d)
        let hi = min(max(0, outPoint), d)
        self.inPoint = min(lo, hi)
        self.outPoint = max(lo, hi)
        self.clipDuration = d
        enforceMinDuration(minDuration: max(0, minDuration), prefer: .keepIn)
    }

    /// True when the window is anything narrower than the whole clip.
    public var isTrimmed: Bool {
        inPoint > 1e-6 || outPoint < clipDuration - 1e-6
    }

    /// Kept length in seconds.
    public var effectiveDuration: TimeInterval { max(0, outPoint - inPoint) }

    /// The kept window as `(start, length)` for `AVAssetExportSession` /
    /// composition insertion. `duration` lets the out-point re-clamp if the
    /// underlying clip length changed since this trim was made.
    public func timeRange(duration: TimeInterval) -> (start: TimeInterval, length: TimeInterval) {
        let d = max(0, duration)
        let start = min(max(0, inPoint), d)
        let end = min(max(start, outPoint), d)
        return (start, end - start)
    }

    /// Move the in-point to `seconds`, clamped and min-window-enforced. Pushes
    /// the out-point forward if needed (never inverts).
    public mutating func setIn(_ seconds: TimeInterval, duration: TimeInterval,
                               minDuration: TimeInterval = VideoTrim.defaultMinDuration) {
        clipDuration = max(0, duration)
        let m = max(0, minDuration)
        inPoint = min(max(0, seconds), clipDuration)
        if outPoint < inPoint + m {
            outPoint = inPoint + m
            if outPoint > clipDuration {
                outPoint = clipDuration
                inPoint = max(0, clipDuration - m)
            }
        }
    }

    /// Move the out-point to `seconds`, clamped and min-window-enforced. Pushes
    /// the in-point backward if needed (never inverts).
    public mutating func setOut(_ seconds: TimeInterval, duration: TimeInterval,
                                minDuration: TimeInterval = VideoTrim.defaultMinDuration) {
        clipDuration = max(0, duration)
        let m = max(0, minDuration)
        outPoint = min(max(0, seconds), clipDuration)
        if inPoint > outPoint - m {
            inPoint = outPoint - m
            if inPoint < 0 {
                inPoint = 0
                outPoint = min(clipDuration, m)
            }
        }
    }

    private enum Bias { case keepIn, keepOut }

    private mutating func enforceMinDuration(minDuration: TimeInterval, prefer: Bias) {
        guard outPoint - inPoint < minDuration else { return }
        switch prefer {
        case .keepIn:
            outPoint = inPoint + minDuration
            if outPoint > clipDuration {
                outPoint = clipDuration
                inPoint = max(0, clipDuration - minDuration)
            }
        case .keepOut:
            inPoint = outPoint - minDuration
            if inPoint < 0 {
                inPoint = 0
                outPoint = min(clipDuration, minDuration)
            }
        }
    }
}
