import CoreGraphics
import Foundation

// Scrubbing back fast keeps the picture moving
// (`scrubbing-back-fast-keeps-the-video-picture-movi`).
//
// A recording is stored as a key frame every so often and, between them, only
// what changed. Reading one exact frame means decoding every frame from the key
// frame before it, so a frame near the end of a two second stretch costs about
// 115 decodes, and reads of neighbouring frames do not run side by side: four
// of them at once took 700ms each on a full-screen Retina recording. A hand
// going backwards asks for exactly those frames, one after another, so the
// picture sat still for half a second.
//
// Reading the stretch in ONE pass decodes each frame once: the whole two
// seconds, every frame kept small, cost about as much as one exact frame at its
// far end. So while a hand moves the playhead, the stretch it is heading into
// is read that way, each frame filed small under its own reference, and the
// canvas shows them stretched. When the hand holds still, the frame under it is
// read sharp the ordinary way (`MovieFrameReads` already reads a frame again
// when it is filed smaller than the canvas shows it). Premiere and Final Cut
// drop resolution while you scrub for the same reason.

/// Which stretch of a recording to read in one pass, and how small to keep it.
public enum MovieSweep {

    /// How far the stretch reaches in the direction the hand is going.
    public static let aheadMS = 1500
    /// ...and how far behind it, so a hand that wobbles back finds the frames
    /// it just left.
    public static let behindMS = 100
    /// How far ahead of the hand every frame must be in hand before nothing
    /// new is read. Half the stretch, so the next one starts while the hand is
    /// still inside this one.
    public static let lookAheadMS = 750
    /// The widest a frame read in passing is kept. An 800-wide frame is under
    /// 2MB, and a hand moving the picture cannot see more.
    public static let roughWidth: CGFloat = 800
    /// How long a hand has to hold still before the frame under it is read
    /// sharp. Long enough that a hand still moving is never mistaken for one
    /// that stopped, short enough that a stop is sharp inside a quarter second.
    public static let settleMS = 30
    /// How many small frames one window keeps: a stretch and a half.
    public static let roughBudget = 64

    /// How much of a recording around a playhead at rest is read small once
    /// its sharp frame is in hand, so a hand that takes it and hunts has
    /// frames to show from its first move. Without them the first fifth of a
    /// second of a hunt showed the frame it started on while the decoder
    /// worked forward from the key frame before it (2026-11-17). More ahead
    /// than behind, since most hunts go forward.
    public static let restAheadMS = 1000
    public static let restBehindMS = 500

    /// The grid frames read around a playhead at rest on `frame`, one of
    /// `places` resting at once (two recordings on screen, say): together
    /// they fit in three quarters of the small frames' budget, or each let
    /// the others' go as they landed (2026-11-17).
    public static func restingWindow(around frame: Int, movie: MovieRef, places: Int = 1) -> ClosedRange<Int> {
        let whole = (restAheadMS + restBehindMS) / MovieRef.frameStepMS + 1
        let share = min(1, Double(roughBudget * 3 / 4) / Double(max(1, places) * whole))
        let ahead = Int(Double(restAheadMS / MovieRef.frameStepMS) * share)
        let behind = Int(Double(restBehindMS / MovieRef.frameStepMS) * share)
        let last = movie.frameIndex(atSourceMS: movie.durationMS)
        let low = min(max(0, frame - behind), last)
        return low...max(low, min(last, frame + ahead))
    }

    /// The grid frames to read for a hand whose first missing frame is `frame`,
    /// going `backward` or forward, inside the recording.
    public static func window(from frame: Int, backward: Bool, movie: MovieRef) -> ClosedRange<Int> {
        let ahead = aheadMS / MovieRef.frameStepMS
        let behind = behindMS / MovieRef.frameStepMS
        let last = movie.frameIndex(atSourceMS: movie.durationMS)
        let low = backward ? frame - ahead : frame - behind
        let high = backward ? frame + behind : frame + ahead
        let from = min(max(0, low), last)
        return from...max(from, min(last, high))
    }

    /// The stretch to start reading for a hand on `handFrame`, or nil when
    /// nothing new needs reading: every frame it is heading for is in hand, or
    /// the stretch already being read (`running`) covers where it is.
    ///
    /// A hand moving faster than a stretch can be read (`glimpses`) is given
    /// the one frame under it instead: by the time a stretch's first frame is
    /// read the hand has left it, so its frames are a picture of where the
    /// hand was a moment ago.
    public static func next(handFrame: Int, backward: Bool, movie: MovieRef,
                            inHand: (Int) -> Bool, running: ClosedRange<Int>?,
                            glimpse: Bool = false) -> ClosedRange<Int>? {
        let last = movie.frameIndex(atSourceMS: movie.durationMS)
        let hand = min(max(0, handFrame), last)
        if glimpse {
            guard !inHand(hand), running?.contains(hand) != true else { return nil }
            return hand...hand
        }
        let reach = lookAheadMS / MovieRef.frameStepMS
        let end = min(max(0, backward ? hand - reach : hand + reach), last)
        let ahead = backward ? Array(stride(from: hand, through: end, by: -1)) : Array(hand...end)
        guard let missing = ahead.first(where: { !inHand($0) && running?.contains($0) != true })
        else { return nil }
        if let running, running.contains(hand) || running.contains(missing) { return nil }
        return window(from: missing, backward: backward, movie: movie)
    }

    /// Whether a frame a stretch reads is worth turning into a picture for a
    /// hand on `hand`: not once the hand has passed it by more than
    /// `behindMS`. Every frame is still decoded, since each is decoded from
    /// the one before, but making the picture is most of a frame's cost, and
    /// a hand hunting forwards at five times the speed it plays stays a few
    /// frames ahead of a stretch that makes every one (2026-11-17: 150 frames
    /// a second against about 150 made).
    public static func worthShowing(frame: Int, hand: Int, backward: Bool) -> Bool {
        let slack = behindMS / MovieRef.frameStepMS
        return backward ? frame <= hand + slack : frame >= hand - slack
    }

    // MARK: A hand faster than a stretch can follow

    /// The pace, in milliseconds of the edit a second, past which a hand is
    /// given the frame under it alone (`next(glimpse:)`): ten times the speed
    /// it plays. A stretch reads about seven times as fast as a recording
    /// plays (a 60 frame a second Retina screen recording, 2026-11-17), and a
    /// hand hunting for a moment moves at about five; a drag from one end of
    /// a six minute edit to the other in two seconds moves at 180.
    public static let glimpsePace: Double = 10_000

    public static func glimpses(pace: Double) -> Bool { pace > glimpsePace }

    /// How far ahead of a hunting hand, in milliseconds of the edit, clips it
    /// is about to cross into are looked for: what it covers in a quarter of
    /// a second, the time a stretch takes to bring its first frame with
    /// another read beside it (50 to 100ms alone, 2026-11-17), never more
    /// than four seconds of the edit.
    public static func cutReachMS(pace: Double) -> Int {
        min(4000, max(0, Int(pace * 0.25)))
    }

    /// How long a key frame takes to come for a hand too fast to follow: a
    /// read of about 17ms, after waiting up to a refresh for the one before it
    /// (one at a time, 2026-11-17).
    public static let glimpseLandsMS: Double = 25

    /// How far ahead of a hand too fast to follow, in milliseconds of the
    /// edit, its key frames are aimed: where it will be when the read lands.
    /// Aimed where it was, each landed about four seconds of a six minute
    /// drag behind it, and a clip it crossed into showed whatever frame of
    /// that recording was in hand, often twenty seconds away, until the first
    /// one did (2026-11-17). Nothing for a slower hand, which is read in
    /// stretches.
    public static func glimpseLeadMS(pace: Double) -> Int {
        glimpses(pace: pace) ? Int((pace * glimpseLandsMS / 1000).rounded()) : 0
    }

    /// ...a tenth of a second of the edit at a time: a clip shorter than that
    /// is crossed before it could be read anyway.
    public static let cutStepMS = 100

    /// How fast a hand is moving the playhead, from its moves over the last
    /// tenth of a second.
    public struct HandPace: Equatable, Sendable {
        /// How far back moves count.
        public static let windowMS: Double = 100
        /// The shortest time a pace is worked out over, so two moves that
        /// arrive together do not read as a burst of speed.
        public static let shortestMS: Double = 16

        private struct Move: Equatable, Sendable {
            let atMS: Double
            let momentMS: Int
        }
        private var moves: [Move] = []

        public init() {}

        public mutating func moved(toMS moment: Int, atMS time: Double) {
            moves.append(Move(atMS: time, momentMS: moment))
            moves.removeAll { $0.atMS < time - Self.windowMS }
        }

        public mutating func reset() { moves = [] }

        /// Milliseconds of the edit crossed a second; 0 until there are two
        /// moves to tell it from.
        public var editMSPerSecond: Double {
            guard let first = moves.first, let last = moves.last, moves.count > 1 else { return 0 }
            let span = max(Self.shortestMS, last.atMS - first.atMS)
            return Double(abs(last.momentMS - first.momentMS)) / span * 1000
        }
    }

    /// How big to keep a frame read in passing, for a canvas that shows it
    /// `wanted` big: never wider than `roughWidth`, never bigger than wanted.
    public static func roughSize(for wanted: CGSize) -> CGSize {
        guard wanted.width > roughWidth, wanted.width > 0 else { return wanted }
        return CGSize(width: roughWidth, height: (wanted.height * roughWidth / wanted.width).rounded())
    }
}

/// Which grid frames each sample of a one-pass read fills, fed the samples in
/// the order the file gives them.
///
/// A grid frame shows the sample on screen at its moment: the last one that
/// starts at or before it, with half a grid step of slack so a 60 frame a
/// second recording gives each grid frame its own sample rather than the one a
/// hair earlier. A screen recording that sat still for a second has one sample
/// for that second, and every grid frame in it shows that one.
public struct MovieSweepGrid: Sendable {

    public let frames: ClosedRange<Int>
    private var next: Int
    private var hasPrevious = false

    public init(frames: ClosedRange<Int>) {
        self.frames = frames
        self.next = frames.lowerBound
    }

    /// The first grid frame no sample has filled yet: everything before it
    /// has been handed over. What a pass playing ahead of the playhead paces
    /// itself by (`MoviePlayPass`).
    public var nextFrame: Int { next }

    /// A sample starting at `ms` arrived. Answers the grid frames the sample
    /// BEFORE it fills, which are the ones this one starts too late for. None
    /// before the first sample: those grid frames show something the pass
    /// never read.
    public mutating func arrived(atMS ms: Double) -> [Int] {
        var filled: [Int] = []
        let slack = Double(MovieRef.frameStepMS) / 2
        while next <= frames.upperBound, Double(next * MovieRef.frameStepMS) + slack < ms {
            if hasPrevious { filled.append(next) }
            next += 1
        }
        hasPrevious = true
        return filled
    }

    /// The pass reached its end: the last sample fills whatever is left.
    public mutating func finished() -> [Int] {
        guard hasPrevious, next <= frames.upperBound else { return [] }
        let filled = Array(next...frames.upperBound)
        next = frames.upperBound + 1
        return filled
    }
}
