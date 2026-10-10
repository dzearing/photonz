// The history strip's filter and keyboard focus, for a walk's
// `expectHistory`. Both live in the strip's own state, where no picture says
// which tile has the keys, so the overlay hands the probe a way to read them.
//
// Probe builds only.
#if PHOTONZ_PLAYTEST
import PhotonzCore

@MainActor
final class HistoryOverlayProbe {
    static let shared = HistoryOverlayProbe()

    struct Reading {
        /// The segment the filter shows picked.
        let filter: CaptureFilter
        /// The filter whose strip is in sight.
        let showing: CaptureFilter
        /// The capture with the keyboard focus in that strip, if any.
        let focused: CaptureEntry?
        /// How many captures that strip holds.
        let count: Int
    }

    /// Set by the overlay when it comes up.
    var read: (() -> Reading)?
}
#endif
