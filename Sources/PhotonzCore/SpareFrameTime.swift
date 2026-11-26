import Foundation

/// How much of the last display refresh the main thread has spent, and which
/// work held until a frame is out fits in what it left over.
///
/// A lane of the timeline that takes a new frame while the timeline moves
/// lays its new picture between frames rather than on the frame that asked
/// (`AfterTheFrame` in the app). Laid in the first gap, the picture of the
/// hour-long reference edit's busiest lane (V1, 378 clips, about 3 ms) went
/// into the same refresh as building that lane again (about 2.5 ms), and
/// those refreshes were the late ones near the whole-hour view and on a fast
/// scroll (2026-11-25, pass 25). So held work runs in a gap only when the
/// refresh ending there leaves room for it under `ceiling`, by what it cost
/// last time; work that has waited `longestWait` runs anyway, and so does
/// work on a thread that did nothing in the last refresh, which no frame with
/// more room would ever follow.
public struct SpareFrameTime: Sendable, Equatable {
    /// One refresh of a 120 Hz display.
    public var refresh: Double = 1.0 / 120
    /// What the main thread may spend in one refresh, held work included,
    /// with a little left for the drawing after it.
    public var ceiling: Double = 0.0065
    /// How long held work waits for a refresh with room: four refreshes.
    public var longestWait: Double = 4.0 / 120
    /// Below this the thread did nothing worth a frame in the last refresh.
    public var idleBelow: Double = 0.001

    private struct Pass: Sendable, Equatable {
        var start: Double
        var end: Double?
    }
    private var passes: [Pass] = []

    public init() {}

    /// The run loop woke.
    public mutating func passBegan(at time: Double) {
        if let last = passes.last, last.end == nil { return }
        passes.append(Pass(start: time, end: nil))
        forget(before: time - refresh)
    }

    /// The run loop is going to sleep.
    public mutating func passEnded(at time: Double) {
        guard let last = passes.indices.last, passes[last].end == nil else { return }
        passes[last].end = time
    }

    /// Main thread time spent in the refresh ending at `now`, a pass still
    /// open counted up to now.
    public func busy(endingAt now: Double) -> Double {
        let from = now - refresh
        return passes.reduce(0) { sum, pass in
            let end = min(now, pass.end ?? now)
            return sum + max(0, end - max(from, pass.start))
        }
    }

    /// Which of the held pieces of work, in the order they were held, run
    /// now: each that fits in the room left, by `costs`; each that has
    /// waited since `waitedSince` for `longestWait` or more; and on a thread
    /// that was idle for the last refresh, the first whatever it costs.
    public func runs(costs: [Double], waitedSince: [Double], now: Double) -> [Int] {
        let spent = busy(endingAt: now)
        var room = ceiling - spent
        var chosen: [Int] = []
        for index in costs.indices {
            let cost = costs[index]
            let overdue = index < waitedSince.count && now - waitedSince[index] >= longestWait
            let idle = chosen.isEmpty && spent < idleBelow
            guard cost <= room || overdue || idle else { continue }
            chosen.append(index)
            room -= cost
        }
        return chosen
    }

    /// How many passes it still remembers.
    public var passesKept: Int { passes.count }

    private mutating func forget(before time: Double) {
        passes.removeAll { pass in pass.end.map { $0 < time } ?? false }
    }
}
