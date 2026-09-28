import Foundation

/// A short loop that plays over and over (a caption style tile saying its
/// words, a transition tile going there and back), read off once as the
/// frames that differ and the moment each starts.
///
/// The app hands a reel to Core Animation, which plays it for ever without
/// the main thread: the tiles used to redraw thirty times a second each, and
/// every redraw laid the whole window out again, so a recording sitting open
/// with nothing playing kept the main thread more than half busy (found
/// 2026-09-27).
public struct LoopReel<Frame: Equatable & Sendable>: Sendable {
    public struct Shot: Sendable {
        public var startMS: Int
        public var frame: Frame
    }

    /// How long one lap lasts.
    public let lapMS: Int
    /// Every frame that differs from the one before it, in order, the first
    /// starting at nought.
    public let shots: [Shot]

    /// The loop read a step at a time: `frame` is asked for the frame at
    /// nought, `stepMS`, twice that, and so on through the lap, and a frame is
    /// kept only where it changes.
    public init(lapMS: Int, stepMS: Int, frame: (Int) -> Frame) {
        let lap = max(1, lapMS)
        let step = max(1, stepMS)
        var shots: [Shot] = []
        var ms = 0
        while ms < lap {
            let next = frame(ms)
            if shots.last?.frame != next { shots.append(Shot(startMS: ms, frame: next)) }
            ms += step
        }
        self.lapMS = lap
        self.shots = shots
    }

    /// Where each frame starts as a share of the lap, and a last `1` closing
    /// it: the key times Core Animation's discrete keyframes take.
    public var keyTimes: [Double] {
        shots.map { Double($0.startMS) / Double(lapMS) } + [1]
    }

    /// What shows `ms` in, on any lap.
    public func frame(atMS ms: Int) -> Frame? {
        let into = ((ms % lapMS) + lapMS) % lapMS
        return shots.last { $0.startMS <= into }?.frame ?? shots.first?.frame
    }
}

// MARK: - A transition tile

/// How a transition tile plays: a beat on the first shot, across, a beat on
/// the second and back again, eased so it reads as a move. Most of the loop is
/// spent part way through, where the kinds differ.
public enum TransitionTileLoop {
    public static let cycleSeconds = 2.2
    /// Thirty frames a second, as the tiles played before.
    public static let stepMS = 33
    /// How finely the reel tells one moment from the next: fine enough that a
    /// wipe across a tile moves under two points a frame, coarse enough that
    /// the way back lands on the way there's frames.
    static let steps = 40.0

    /// How far across `seconds` in, from nought (the first shot) to one (the
    /// second).
    public static func progress(atSeconds seconds: Double) -> Double {
        let t = seconds.truncatingRemainder(dividingBy: cycleSeconds) / cycleSeconds
        let there = t < 0.5 ? t * 2 : 2 - t * 2
        let raw = min(max((there - 0.1) / 0.8, 0), 1)
        return raw * raw * (3 - 2 * raw)
    }

    /// One lap as the moments a tile draws.
    public static let reel = LoopReel(lapMS: Int((cycleSeconds * 1000).rounded()), stepMS: stepMS) { ms in
        (progress(atSeconds: Double(ms) / 1000) * steps).rounded() / steps
    }
}
