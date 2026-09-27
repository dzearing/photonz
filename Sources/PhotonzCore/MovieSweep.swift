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
    public static func next(handFrame: Int, backward: Bool, movie: MovieRef,
                            inHand: (Int) -> Bool, running: ClosedRange<Int>?) -> ClosedRange<Int>? {
        let last = movie.frameIndex(atSourceMS: movie.durationMS)
        let hand = min(max(0, handFrame), last)
        let reach = lookAheadMS / MovieRef.frameStepMS
        let end = min(max(0, backward ? hand - reach : hand + reach), last)
        let ahead = backward ? Array(stride(from: hand, through: end, by: -1)) : Array(hand...end)
        guard let missing = ahead.first(where: { !inHand($0) && running?.contains($0) != true })
        else { return nil }
        if let running, running.contains(hand) || running.contains(missing) { return nil }
        return window(from: missing, backward: backward, movie: movie)
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
