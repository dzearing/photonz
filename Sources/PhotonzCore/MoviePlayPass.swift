import CoreGraphics
import Foundation

// A full-screen Retina recording keeps up while it plays
// (`a-full-screen-retina-recording-keeps-up-while-it`).
//
// Playing used to read each frame on its own, four at a time, the way a
// still playhead is read. Each of those reads seeks: it decodes from the key
// frame before it, and the four do not share the work. On the 3456x2234
// fixture that came to about 15 frames a second against the 30 the grid
// shows, so the picture fell further behind with every frame and held one up
// to half a second old (measured 2026-10-07: 90 frames in 6.0s that way, the
// same stretch read in one pass and every frame converted in 0.45s).
//
// So a playing playhead is fed by ONE pass over the recording from where it
// is, every frame decoded once, read at the size the canvas shows it and
// filed sharp. The pass keeps `aheadFrames` ahead of the playhead and waits
// there, so it never reads frames the window would only have to let go of,
// and it is started over wherever the playhead goes that it is not: a scrub
// while playing, a cut that jumps within the same recording, a machine so
// loaded the pass fell behind. A frame across a cut, far past the playhead in
// the recording, is still read on its own, so a cut is in hand before the
// playhead reaches it.

/// Which stretch of a recording a playing playhead reads in one pass, and
/// when that pass has stopped serving it.
public enum MoviePlayPass {

    /// How many grid frames ahead of the playhead a pass reads before it waits.
    /// A quarter of a second: the same reach exact reads had, well inside the
    /// sixteen frames a window keeps, so nothing read ahead is let go before
    /// it is shown.
    public static let aheadFrames = 8
    /// How far the pass may be behind the playhead before it is started over
    /// where the playhead is. A few frames: a start costs one decode from the
    /// key frame before it, which is cheaper than catching up a long way.
    public static let fallenBehindFrames = 4

    /// The grid frames a pass for a playhead on `frame` reads: from there to
    /// the end of the recording. It waits, rather than stops, so a long play
    /// is one pass.
    public static func window(from frame: Int, movie: MovieRef) -> ClosedRange<Int> {
        let last = movie.frameIndex(atSourceMS: movie.durationMS)
        let from = min(max(0, frame), last)
        return from...last
    }

    /// Whether a pass whose next frame to fill is `next` is far enough ahead
    /// of a playhead on `playhead` to wait for it.
    public static func shouldWait(next: Int, playhead: Int) -> Bool {
        next > playhead + aheadFrames
    }

    /// Whether the pass reading `running`, which has filled every frame
    /// before `reached`, still serves a playhead on `playhead`.
    ///
    /// Not when the playhead is outside it, nor when the pass has fallen more
    /// than `fallenBehindFrames` behind, nor when the playhead went back over
    /// ground the pass already read and the window has let that frame go.
    public static func serves(running: ClosedRange<Int>, reached: Int, playhead: Int,
                              inHand: (Int) -> Bool) -> Bool {
        guard running.contains(playhead) else { return false }
        if reached < playhead - fallenBehindFrames { return false }
        if playhead < reached, !inHand(playhead) { return false }
        return true
    }

    /// Whether the frame `frame` is the running pass's to read, so nothing
    /// reads it on its own: inside the pass, not yet gone by, and no further
    /// past the playhead than the pass will go. A frame further than that is
    /// across a cut and is read on its own.
    public static func covers(frame: Int, running: ClosedRange<Int>, reached: Int, playhead: Int) -> Bool {
        running.contains(frame) && frame >= reached && frame <= max(reached, playhead + aheadFrames)
    }
}
