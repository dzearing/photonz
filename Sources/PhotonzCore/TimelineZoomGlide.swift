import Foundation

// **The timeline never jumps when the recording changes length** (user
// 2026-10-28: "we go from one zoom level to another not gracefully; there's
// no transition but it just immediately snaps").
//
// The zoom is kept as a share of the length (`TimelineZoom.scale`), so every
// change of length rescaled the strip in one frame: a clip let go past the
// end, the room the timeline makes for one in the air, an undo of either. An
// eight second recording opened right out showed sixteen seconds, a clip let
// go at twelve made it twenty, and the strip was showing forty on the next
// frame with every bar on it a third of the width it had been.
//
// Two answers, by what the person was looking at:
//
// - **Zoomed to some stretch of it**, the seconds on screen stay exactly as
//   they were (`holdingSpan`): the frames being cut between do not move
//   because something happened at the far end.
// - **Showing the whole of it** (Fit, or opened right out to twice the
//   length, which is what a recording opens at), it goes on showing the whole
//   of it: the strip starts on what was on screen and glides to the same
//   share of the new length (`TimelineZoomGlide`), so the room after the end
//   is there again and the change is seen happening.

extension TimelineZoom {

    /// The same seconds on screen, from the same moment, against a recording
    /// that is now a different length. Where the new length cannot show that
    /// much (more than twice it), as much as it can.
    public func holdingSpan(fromDocumentMS old: Double, toDocumentMS new: Double) -> TimelineZoom {
        let was = max(1, old), now = max(1, new)
        let span = visibleMS(documentMS: was)
        return TimelineZoom(scale: now / span, startMS: startMS).clamped(documentMS: now)
    }

}

/// A timeline showing the whole recording gliding from what was on screen to
/// the same share of its new length: Fit to Fit, twice to twice.
///
/// Every moment of it is measured against `heldMS`, the longer of the two
/// lengths, which the timeline holds for as long as the glide runs: against
/// the shorter one a window twice the longer could not be drawn, and the
/// first frame of an undo would already be the end of it.
public struct TimelineZoomGlide: Hashable, Sendable {

    /// How long it takes. A quarter of a second and a bit: long enough to see
    /// where the strip went, short enough that nobody waits on it.
    public static let seconds: Double = 0.28

    /// The length every moment of the glide is measured against.
    public let heldMS: Double
    /// Where it lands, against the recording's new length. The same window
    /// the glide's last moment is, so letting go of the held length moves
    /// nothing.
    public let landing: TimelineZoom

    let fromSpanMS: Double
    let toSpanMS: Double
    let fromStartMS: Double
    let toStartMS: Double

    /// Nil where the length did not change. `landingScale` is the share of
    /// the length the person chose, where the window on screen is one the
    /// app held for a while (a file in the air); the window's own otherwise.
    public init?(from zoom: TimelineZoom, documentMS old: Double, to new: Double,
                 landingScale: Double? = nil) {
        let was = max(1, old), now = max(1, new)
        guard abs(was - now) > 0.5 else { return nil }
        heldMS = max(was, now)
        landing = TimelineZoom(scale: landingScale ?? zoom.clamped(documentMS: was).scale, startMS: zoom.startMS)
            .clamped(documentMS: now)
        fromSpanMS = zoom.visibleMS(documentMS: was)
        toSpanMS = landing.visibleMS(documentMS: now)
        fromStartMS = zoom.startMS
        toStartMS = landing.startMS
    }

    /// The window `progress` of the way through, nought to one, eased in and
    /// out so it neither lurches off nor stops dead.
    public func zoom(at progress: Double) -> TimelineZoom {
        let t = min(max(0, progress), 1)
        let eased = t * t * (3 - 2 * t)
        let span = fromSpanMS + (toSpanMS - fromSpanMS) * eased
        let start = fromStartMS + (toStartMS - fromStartMS) * eased
        return TimelineZoom(scale: heldMS / span, startMS: start).clamped(documentMS: heldMS)
    }
}
