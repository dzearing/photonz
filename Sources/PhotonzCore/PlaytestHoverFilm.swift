import CoreGraphics
import Foundation

/// A `filmHover` step: film a control while the walk's pointer arrives on it,
/// and read whether a band of light crossed it (`SheenSweep`).
///
/// The user, 2026-10-24, of the Ask button: "when I hover over it the first
/// time it has a nice sheen animation, but subsequent hovers do not repeat
/// the sheen". A snapshot lands after the 0.66s sweep has ended, so only the
/// drawn window, frame by frame, can say whether the second hover swept.
public struct PlaytestHoverFilm: Sendable, Equatable {
    public static let defaultSeconds: Double = 1.0

    /// Frames go to `<name>-<n>-sc.png`, all of them stacked to
    /// `<name>-strip-sc.png`, and the readings to `<name>.json`.
    public var name: String
    /// The control the pointer is moved onto once filming has begun, found
    /// in the app's own register as `move` finds it.
    public var control: String
    public var seconds: Double
    /// A claim: true fails the step when no band crosses the control, false
    /// when one does. Nil films and reports without claiming.
    public var sweeps: Bool?

    public init(name: String, control: String, seconds: Double = Self.defaultSeconds, sweeps: Bool? = nil) {
        self.name = name
        self.control = control
        self.seconds = seconds
        self.sweeps = sweeps
    }
}

/// Whether a band of light crossed a control in a film of it, read off one
/// number per column per frame: how light the column is (`lightness`).
///
/// The film begins before the pointer arrives and ends with the hover
/// settled, so its first frame is the control at rest and its last is the
/// control hovered, neither with a band on it. A hover's colour change is a
/// cross fade between those two, so no column of it is lighter than the
/// lighter of the two; a band of white is. So every frame is read against
/// the lighter of rest and settled, column by column: a band is a column
/// clearly lighter than both. A sweep is a band seen in several frames,
/// carried from the leading half to the trailing half.
public enum SheenSweep {
    /// Lighter than both rest and settled by at least this, out of 255, over
    /// and above what the control's least-changed quarter moved by.
    public static let lift: Double = 12
    /// A sweep is seen in at least this many frames.
    public static let fewestFrames = 3
    /// And carried at least this share of the control's width.
    public static let shortestTravel = 0.4

    /// How light a pixel is for this reading: its weakest channel, out of
    /// 255. White laid over a saturated colour raises its weakest channel the
    /// most, and a change of hue between two saturated colours barely moves it.
    public static func lightness(r: Double, g: Double, b: Double) -> Double {
        min(r, g, b)
    }

    public struct Reading: Sendable, Equatable {
        /// Per frame, where the band's lightest column is as a share of the
        /// width, leading edge 0; nil where no band is drawn.
        public var centres: [Double?]
        /// How many frames drew a band.
        public var lit: Int
        /// The most any frame's band stood above the rest of its control.
        public var strongest: Double
        public var swept: Bool
    }

    public static func read(_ frames: [[Double]]) -> Reading {
        guard frames.count >= 2, let atRest = frames.first, let settled = frames.last,
              settled.count >= 2, atRest.count == settled.count else {
            return Reading(centres: frames.map { _ in nil }, lit: 0, strongest: 0, swept: false)
        }
        let ceiling = zip(atRest, settled).map { max($0, $1) }
        var strongest = 0.0
        let centres: [Double?] = frames.map { columns in
            guard columns.count == ceiling.count else { return nil }
            let excess = zip(columns, ceiling).map { $0 - $1 }
            // A frame lighter all over (the capture's own drift) lifts the
            // floor; one darker than the ceiling, as most of the cross fade
            // is, does not lower it.
            let floor = max(0, excess.sorted()[excess.count / 4])
            guard let peak = excess.indices.max(by: { excess[$0] < excess[$1] }) else { return nil }
            let standing = excess[peak] - floor
            strongest = max(strongest, standing)
            guard standing >= lift else { return nil }
            return Double(peak) / Double(settled.count - 1)
        }
        let seen = centres.compactMap { $0 }
        let swept = seen.count >= fewestFrames
            && (seen.max() ?? 0) - (seen.min() ?? 0) >= shortestTravel
            && (seen.first ?? 1) < 0.5 && (seen.last ?? 0) > 0.5
        return Reading(centres: centres, lit: seen.count, strongest: strongest, swept: swept)
    }
}
