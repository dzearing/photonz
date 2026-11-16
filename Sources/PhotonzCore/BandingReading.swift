import Foundation

/// How banded a line of pixels is: how many different levels it passes
/// through, how often it changes, and the longest stretch that stays on one
/// level.
///
/// A soft gradient drawn in 8-bit steps is a staircase: ten shades over 1300
/// pixels of a dark window is ten flat bands about 130 pixels wide, and the eye
/// reads every edge between two of them. The same gradient smoothed passes
/// through many more levels and never sits on one for long. These are the
/// numbers the smoothing pass for recordings is held to
/// (`RecordingSmoothing` in PhotonzRender), read the same way in its tests,
/// in the app's own check and in the audit.
public struct BandingReading: Equatable, Sendable {
    /// How many different values the line holds.
    public let distinctLevels: Int
    /// How many times a value differs from the one before it.
    public let changes: Int
    /// The longest stretch of one value, in pixels.
    public let longestFlatRun: Int
    /// The biggest difference between two neighbours.
    public let largestStep: Int
    public let lowest: Int
    public let highest: Int

    public init(levels: [Int]) {
        guard let first = levels.first else {
            distinctLevels = 0; changes = 0; longestFlatRun = 0; largestStep = 0; lowest = 0; highest = 0
            return
        }
        var changes = 0, run = 1, longest = 1, step = 0
        var low = first, high = first
        for (before, value) in zip(levels, levels.dropFirst()) {
            low = min(low, value)
            high = max(high, value)
            if value == before {
                run += 1
            } else {
                changes += 1
                step = max(step, abs(value - before))
                run = 1
            }
            longest = max(longest, run)
        }
        self.distinctLevels = Set(levels).count
        self.changes = changes
        self.longestFlatRun = longest
        self.largestStep = step
        self.lowest = low
        self.highest = high
    }

    /// Fractions of full scale (0 to 1) as whole codes of a `bits`-deep
    /// channel, rounded to the nearest.
    public static func codes(_ fractions: [Double], bits: Int) -> [Int] {
        let top = Double((1 << bits) - 1)
        return fractions.map { Int(($0 * top).rounded()) }
    }

    /// Whether the line reads as smooth by the bar: no flat run as long as
    /// `longestRunUnder` and at least `levelsAtLeast` different levels.
    public func isSmooth(longestRunUnder: Int, levelsAtLeast: Int) -> Bool {
        longestFlatRun < longestRunUnder && distinctLevels >= levelsAtLeast
    }
}
