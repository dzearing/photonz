import Foundation

/// The Measure tool's mode hint (Next, `next-measure-modes`): the glass pill
/// that names the mode you just landed on and says what a click will do.
///
/// It is a toast, not a banner. It appears when the tool is picked up and every
/// time the mode changes (I cycles, the button's flyout, the inspector), then
/// fades on its own after `lifetime`. The old chip lived until the document's
/// first measurement landed and then never came back, so anyone switching to
/// Gap or Size later got no words at all; this one is tied to the ACT of
/// switching instead, which is the moment the words are wanted.
///
/// Session chrome only: it never enters the document or the undo history.
public struct MeasureModeHint: Hashable, Sendable {
    /// How long the chip stays up before fading. Long enough to read one line,
    /// short enough that a fluent user never waits for it. A longer line gets a
    /// little longer (`lifetime`), never more than `longestLifetime`.
    public static let lifetime: TimeInterval = 2
    public static let longestLifetime: TimeInterval = 3.5
    /// Reading pace the stretch is priced at, per word of the detail line.
    static let secondsPerWord: TimeInterval = 0.22

    public var mode: MeasureToolMode
    public var shownAt: Date

    public init(mode: MeasureToolMode, shownAt: Date) {
        self.mode = mode
        self.shownAt = shownAt
    }

    /// Whether the chip should still be on screen at `now`. Strictly inside the
    /// window, so a clock that runs backwards cannot pin it up forever.
    public func isLive(at now: Date) -> Bool {
        let age = now.timeIntervalSince(shownAt)
        return age >= 0 && age < lifetime
    }

    /// This chip's own stay: the base lifetime, stretched for a line that
    /// takes longer to read (Size's line carries the [ and ] tip and runs to
    /// sixteen words), and capped so no mode turns the toast into a banner.
    public var lifetime: TimeInterval {
        let words = detail.split(whereSeparator: \.isWhitespace).count
        return min(Self.longestLifetime, max(Self.lifetime, Double(words) * Self.secondsPerWord))
    }

    /// The same chip, re-shown for a new mode with its clock restarted. Three
    /// quick presses of I keep the chip up and it fades from the LAST press.
    public func reshown(as mode: MeasureToolMode, at now: Date) -> MeasureModeHint {
        MeasureModeHint(mode: mode, shownAt: now)
    }

    /// The mode's name, set in its own weight at the head of the pill.
    public var title: String { mode.title }

    /// What a click does in that mode, phrased as the next thing to do.
    public var detail: String { mode.hint }
}
