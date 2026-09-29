import CoreGraphics
import Foundation

/// A `filmThumb` step: film the window while a segmented control's thumb
/// moves, and read where the glass is drawn in every frame against its rail.
///
/// The user, 2026-09-29, of View | Edit in the title bar: "the segmented
/// control overshoots like CRAZY. I'm on Edit, click View, look at the crazy
/// weird overshoot." The motion model (`SegmentThumbMorph`) was bounded to the
/// row and its tests were green, so whatever flung the thumb was downstream of
/// it, in the drawing. Only the drawn window can say, frame by frame.
public struct PlaytestThumbFilm: Sendable, Equatable {
    /// What sets the thumb off.
    public enum Trigger: Sendable, Equatable {
        /// A key, the way a person presses it (⌘1 for View).
        case key(PlaytestKey, [PlaytestModifier])
        /// A control pressed by its face, the way `press` does.
        case press(control: String, in: String?)
    }

    public static let defaultSeconds: Double = 0.7

    /// Frames go to `<name>-<n>-sc.png` and the readings to `<name>.json`.
    public var name: String
    /// The controls whose boxes, joined, are the rail: both halves of View |
    /// Edit, or the first and last segment of a panel picker.
    public var rail: [String]
    /// Points added round those boxes to reach the rail's edge: a panel
    /// picker's segments sit 2pt inside it.
    public var pad: CGFloat
    public var seconds: Double
    public var trigger: Trigger
    /// A claim: true fails the step when any frame draws the thumb past the
    /// rail, false when none does. Nil films and reports without claiming.
    public var inside: Bool?

    public init(name: String, rail: [String], pad: CGFloat = 0, seconds: Double = Self.defaultSeconds,
                trigger: Trigger, inside: Bool? = nil) {
        self.name = name
        self.rail = rail
        self.pad = pad
        self.seconds = seconds
        self.trigger = trigger
        self.inside = inside
    }
}

/// Where a thumb is drawn in one frame, read off the brightness of a strip of
/// columns through the rail (one number per column, 0 black to 1 white),
/// wider than the rail so a thumb that leaves it is still seen.
///
/// The rail is darker than what it sits on and the thumb is a pane lighter
/// than both, so the thumb is the run of columns clearly brighter than the
/// backdrop that lies most over the rail (the panel toggle beside View | Edit
/// is bright too, but never on the rail). The backdrop is read once, off a
/// frame taken before the thumb moves (`backdrop(columns:rail:)`).
///
/// The rail clips what it holds, so a thumb flung past it does not show past
/// it: it shows as glass pressed flat against the rail's end, over the
/// padding a thumb at rest never covers. So the room a thumb may use is where
/// it rests, and `outside(_:of:)` counts what goes beyond that.
public enum ThumbFootprint {

    /// Brighter than the backdrop by at least this.
    public static let lift: Double = 0.06
    /// A run narrower than this is a letter's stroke, not glass.
    public static let narrowest = 3
    /// Columns this close to the rail's edge are its hairline and shadow, not
    /// what it sits on.
    public static let edge = 6

    /// What the rail sits on: the middle brightness either side of it, off its
    /// hairline, in a frame where the thumb is at rest inside it.
    public static func backdrop(columns: [Double], rail: ClosedRange<Int>) -> Double {
        let outside = columns.indices
            .filter { $0 < rail.lowerBound - edge || $0 > rail.upperBound + edge }
            .map { columns[$0] }
            .sorted()
        return outside.isEmpty ? 0 : outside[outside.count / 2]
    }

    /// The columns the thumb covers, or nil when no glass is drawn on the rail.
    public static func read(columns: [Double], rail: ClosedRange<Int>, backdrop: Double) -> ClosedRange<Int>? {
        let threshold = backdrop + lift
        var best: ClosedRange<Int>?
        var start: Int?
        for index in 0...columns.count {
            let lit = index < columns.count && columns[index] >= threshold
            if lit, start == nil { start = index }
            if !lit, let first = start {
                let run = first...(index - 1)
                if run.count >= narrowest, run.overlaps(rail),
                   overlap(run, rail) > (best.map { overlap($0, rail) } ?? 0) { best = run }
                start = nil
            }
        }
        return best
    }

    /// How many of the thumb's columns lie beyond `room`.
    public static func outside(_ thumb: ClosedRange<Int>, of room: ClosedRange<Int>) -> Int {
        max(0, room.lowerBound - thumb.lowerBound) + max(0, thumb.upperBound - room.upperBound)
    }

    private static func overlap(_ a: ClosedRange<Int>, _ b: ClosedRange<Int>) -> Int {
        a.overlaps(b) ? a.clamped(to: b).count : 0
    }
}
