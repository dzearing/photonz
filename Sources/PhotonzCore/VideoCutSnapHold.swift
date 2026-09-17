import CoreGraphics
import Foundation

/// What one trim-handle drag remembers about the cuts it is dealing with.
///
/// The magnet (`VideoCutSnapping`) decides one event at a time: here is a
/// position, here are the cuts, which one takes it. That is not enough on its
/// own for two things a hand does, so a drag carries this alongside it.
///
/// **The cut it is standing on**, so a wobble cannot lose a cut that has
/// already caught. That was always here; it used to be a bare `held` passed
/// back in.
///
/// **The cuts it has been told to leave alone**, which is what the key that
/// frees the magnet leaves behind it. While the key is down nothing catches,
/// so the eight-point band on each side of every cut — unreachable by dragging
/// otherwise, because anything the hand puts there is taken — opens up. The
/// question that band raises is what happens when the key comes UP with the
/// handle still sitting in it: catching comes back, the cut is three points
/// away, and the handle is yanked onto the very thing the key was held to
/// escape.
///
/// The canvas never has to answer that, because `SnapHold.free()` latches its
/// magnets off for the whole drag: ⌘ there is a one-shot. On a track that is
/// too blunt, because a trim drag passes several cuts and the next one along
/// is usually the one being aimed at. So instead of latching, every cut within
/// reach when the key was last down is MUTED: it cannot catch until the hand
/// has travelled clearly away from it, the same sixteen points a caught cut
/// needs before it lets go. Nothing can yank the handle, which is the whole
/// point of the canvas latch, and every other cut still works.
public struct VideoCutSnapHold: Equatable, Sendable {

    /// The cut the handle is standing on, in timeline seconds, or nil when the
    /// handle is simply where the hand put it.
    public private(set) var caught: TimeInterval?

    /// Cuts that may not catch until the hand has moved clearly away from
    /// them: the ones the freeing key was let go of next to.
    private var muted: [TimeInterval] = []

    public init() {}

    /// Where the handle should land, and what that does to the drag's memory.
    ///
    /// - Parameters:
    ///   - seconds: the timeline position the pointer is over.
    ///   - candidates: what this handle may catch on
    ///     (`VideoCutSnapping.candidates(in:within:)`).
    ///   - pointsPerSecond: how much of the track one second takes up. Zero or
    ///     less means the track has not been laid out, and a magnet with no
    ///     width on screen would take everything, so it takes nothing.
    ///   - freed: whether the key that frees the magnet is down right now.
    ///     Read per event rather than once, so pressing it part way through a
    ///     drag works, which is when you actually reach for it.
    public mutating func landing(for seconds: TimeInterval,
                                 catchingOn candidates: [TimeInterval],
                                 pointsPerSecond: CGFloat,
                                 freed: Bool) -> TimeInterval {
        guard pointsPerSecond > 0 else {
            caught = nil
            muted = []
            return seconds
        }
        let reach = TimeInterval(VideoCutSnapping.catchDistance / pointsPerSecond)
        let letGo = TimeInterval(VideoCutSnapping.releaseDistance / pointsPerSecond)

        if freed {
            // Nothing catches, and the cuts near enough to have caught are
            // noted, so the moment the key comes up they are already muted.
            // Recomputed every event rather than accumulated: a cut the hand
            // has since moved away from was never the danger.
            caught = nil
            muted = candidates.filter { abs($0 - seconds) <= reach }
            return seconds
        }

        muted = muted.filter { abs($0 - seconds) <= letGo }
        let live = candidates.filter { candidate in
            !muted.contains { abs($0 - candidate) <= 1e-9 }
        }
        let snap = VideoCutSnapping.snap(seconds, to: live,
                                         pointsPerSecond: pointsPerSecond,
                                         held: caught)
        caught = snap.caught
        return snap.seconds
    }
}
