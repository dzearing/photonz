import Foundation

/// How the main thread's time is cut into passes, for the playtest meter that
/// holds a click or a key to one frame (`MainThreadMeter` in the app).
///
/// The thread is busy from the moment the run loop wakes until it next goes
/// to sleep, and that stretch is cut wherever a run of the run loop begins or
/// ends. The time BETWEEN two runs is a pass like any other: AppKit takes an
/// event out of the queue inside a run and hands it to the app after that run
/// has ended, so a click's own work happens there. It used to count for
/// nothing, and the history filter's switch built its 14 tiles in that gap
/// and read 5.6ms (2026-10-03). The run edges still cut because a frame is
/// committed inside a run: one pass from wake to sleep would join two
/// stretches of work with a frame drawn between them.
public struct MainThreadPassClock: Sendable, Equatable {

    /// What the run loop's observer saw.
    public enum Moment: Sendable, Equatable {
        case woke
        case enteredARun
        case leftARun
        case fallingAsleep
    }

    private var openSince: Double?
    private var excluded: Double = 0

    public init() {}

    /// Feeds one moment in. Returns how long the pass that just ended took,
    /// the harness's own time taken off, when this moment ended one.
    public mutating func record(_ moment: Moment, at time: Double) -> Double? {
        switch moment {
        case .woke:
            if openSince == nil { openSince = time; excluded = 0 }
            return nil
        case .enteredARun, .leftARun:
            // A run edge ends one pass and starts the next: the thread is
            // plainly awake on both sides of it.
            let ended = openSince.map { max(0, time - $0 - excluded) }
            openSince = time
            excluded = 0
            return ended
        case .fallingAsleep:
            guard let since = openSince else { return nil }
            openSince = nil
            defer { excluded = 0 }
            return max(0, time - since - excluded)
        }
    }

    /// Time the harness itself spent on the main thread. Taken off the pass
    /// it happened in; with no pass open, it is handed back so the caller can
    /// take it off its totals instead.
    public mutating func exclude(_ seconds: Double) -> Double {
        guard openSince != nil else { return seconds }
        excluded += seconds
        return 0
    }

    /// Counts the pass from now, as if it had just begun.
    public mutating func restart(at time: Double) {
        openSince = time
        excluded = 0
    }

    /// Forgets the open pass without counting it.
    public mutating func drop() {
        openSince = nil
        excluded = 0
    }

    /// How long the open pass has run so far, or nil when the thread is asleep.
    public func running(at time: Double) -> Double? {
        openSince.map { max(0, time - $0 - excluded) }
    }
}

/// How long the main thread spent inside AppKit's slide of a sheet or window.
///
/// AppKit slides a sheet in and out inside a run of its own private run loop
/// mode, which is not one of the common modes, so an observer on the common
/// modes never sees the thread sleep between the slide's frames and counts the
/// whole slide as one pass (`the-export-sheet-opens-without-a-stall`,
/// 2026-10-08: 360ms opening, 275ms closing, on every document). The meter
/// watches `mode` as well, which cuts the slide into its frames, and keeps this
/// tally so a walk can say how much of a step was the slide.
public struct WindowSlideSpan: Sendable, Equatable {

    /// The run loop mode AppKit runs a sheet's slide in.
    public static let mode = "_NSMoveTimerRunLoopMode"

    private var since: Double?
    public private(set) var total: Double = 0

    public init() {}

    public mutating func entered(at time: Double) {
        if since == nil { since = time }
    }

    public mutating func left(at time: Double) {
        guard let since else { return }
        total += max(0, time - since)
        self.since = nil
    }

    /// The total, with a slide still under way counted up to `time`.
    public func total(at time: Double) -> Double {
        total + (since.map { max(0, time - $0) } ?? 0)
    }

    /// Starts the tally again at `time`. A slide under way keeps going, and
    /// counts from here.
    public mutating func reset(at time: Double) {
        if since != nil { since = time }
        total = 0
    }
}
