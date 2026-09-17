import CoreGraphics
import Foundation

/// Where a trim handle lands, and what caught it.
///
/// `caught` is the cut the handle is standing on, in timeline seconds, or nil
/// when the handle is simply where the hand put it. It is the thing the track
/// draws its tell from, so the mark on screen and the number that was stored
/// cannot say different things.
public struct VideoCutSnap: Equatable, Sendable {
    /// The timeline position to put the handle at.
    public let seconds: TimeInterval
    /// The cut it caught on, or nil when nothing did.
    public let caught: TimeInterval?

    public init(seconds: TimeInterval, caught: TimeInterval? = nil) {
        self.seconds = seconds
        self.caught = caught
    }

    /// Whether a cut decided where this handle sits, rather than the hand.
    public var isCaught: Bool { caught != nil }
}

/// The magnet that makes a trim handle catch on a cut as it passes.
///
/// Every cut in a recording is a place somebody has already said is meaningful,
/// so a handle creeping up on one should land on it rather than beside it.
/// Trimming exactly to a join was otherwise a steady hand and a lot of
/// squinting, because a cut is one position out of thousands along the track.
///
/// Three things make it a snap rather than a stutter, all of them borrowed from
/// the canvas (`Snapping`, `SnapHold`), so a handle feels like everything else
/// in the app that lines up with something:
///
/// - **The reach is a distance on screen**, not a span of time. Eight points is
///   eight points whether the track is showing eight seconds or eight minutes,
///   so the magnet feels identical on a short recording and a long one.
/// - **A cut that caught keeps the handle** until the hand has travelled
///   clearly away from it — twice as far as it took to catch. Without that
///   memory a pointer resting on the edge of the reach is a coin toss, taken
///   and dropped and taken again while the hand barely moves.
/// - **The ends of the recording catch too.** The first frame and the last are
///   joins like any other, and a handle put back against one should land on it
///   rather than a hair inside.
///
/// What it deliberately does NOT do is reach for anything it cannot actually
/// deliver: a caller passes the range its handle may legally occupy (the
/// minimum-piece floor keeps the two handles apart), and candidates outside it
/// are never offered. A tell that said "caught" while the handle sat somewhere
/// else would be worse than no tell at all.
public enum VideoCutSnapping {

    /// How near a cut has to be, in points on screen, before it takes the
    /// handle. The same eight points the canvas magnets use.
    public static let catchDistance: CGFloat = 8

    /// How far the hand must travel from a cut it is standing on before the
    /// cut lets go, in points on screen. `SnapHold.releaseFactor` times the
    /// reach, which is the room a wobbling hand needs.
    public static var releaseDistance: CGFloat { catchDistance * SnapHold.releaseFactor }

    /// Every position a trim handle may catch on in this recording, in timeline
    /// seconds and in order: the start, each cut between two pieces, the end.
    ///
    /// - Parameter range: the positions this particular handle may legally
    ///   occupy. Pass nil for all of them.
    public static func candidates(in cuts: VideoCutList,
                                  within range: ClosedRange<TimeInterval>? = nil)
        -> [TimeInterval] {
        var positions: [TimeInterval] = [0]
        var elapsed: TimeInterval = 0
        for piece in cuts.pieces {
            elapsed += piece.duration
            positions.append(elapsed)
        }
        guard let range else { return positions }
        return positions.filter { $0 >= range.lowerBound - 1e-9 && $0 <= range.upperBound + 1e-9 }
    }

    /// Where a handle dragged to `seconds` should actually land.
    ///
    /// - Parameters:
    ///   - seconds: the timeline position the pointer is over.
    ///   - candidates: what this handle may catch on (`candidates(in:within:)`).
    ///   - pointsPerSecond: how much of the track one second takes up, which is
    ///     what turns the reach from points on screen into a span of time. Zero
    ///     or less means the track has not been laid out yet, and a magnet with
    ///     no width on screen would take everything, so it takes nothing.
    ///   - held: the cut this drag is already standing on, if any.
    public static func snap(_ seconds: TimeInterval,
                            to candidates: [TimeInterval],
                            pointsPerSecond: CGFloat,
                            held: TimeInterval?) -> VideoCutSnap {
        guard pointsPerSecond > 0, !candidates.isEmpty else {
            return VideoCutSnap(seconds: seconds)
        }
        let reach = TimeInterval(catchDistance / pointsPerSecond)
        let letGo = TimeInterval(releaseDistance / pointsPerSecond)

        // Whatever is nearest wins the catch, so passing one cut on the way to
        // another hands the handle straight over rather than leaving it stuck.
        let nearest = candidates.min { abs($0 - seconds) < abs($1 - seconds) }

        // The cut being stood on keeps the handle first, unless the hand has
        // already reached a different cut, which is the one it is plainly
        // heading for.
        if let held, candidates.contains(where: { abs($0 - held) <= 1e-9 }),
           abs(held - seconds) <= letGo {
            if let nearest, abs(nearest - held) > 1e-9, abs(nearest - seconds) <= reach {
                return VideoCutSnap(seconds: nearest, caught: nearest)
            }
            return VideoCutSnap(seconds: held, caught: held)
        }

        if let nearest, abs(nearest - seconds) <= reach {
            return VideoCutSnap(seconds: nearest, caught: nearest)
        }
        return VideoCutSnap(seconds: seconds)
    }
}
