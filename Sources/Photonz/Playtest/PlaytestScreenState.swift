// Whether this Mac's screen is locked, which decides whether a walk's answer
// is worth anything at all.
//
// A scripted walk drives a real window and then reads it: the words on a
// control, the rows in a list, where a tutorial's callout landed. All of that
// needs the window to be COMPOSITED — actually drawn by the window server on a
// real screen. When the screen is locked, the login window covers everything,
// every other window goes occluded, and macOS stops the work it would otherwise
// be wasting: layout and drawing are suspended, animations stop advancing, the
// accessibility text SwiftUI hands to AppKit never materialises, and screen
// capture refuses outright.
//
// The app is fine. The walk is not: it reads a half-built window and reports
// what it found as if the app had produced it.
//
// That is not a hypothetical. The Mac locked at 2026-09-14 20:46:47. The sweep
// that started at 20:42 collapsed four minutes in, with walks that take five
// seconds taking a quarter of an hour; the last screen capture any walk managed
// was written at 20:44; and the sweep at 00:09 reported 115 of 400 walks broken,
// including every one of the 31 tutorial walks, on source that had passed all 31
// eight hours earlier. Runners were then sent to hunt bugs that were not there.
//
// So a walk run under a locked screen does not pass and does not fail. It did
// not run, and it says so.
#if PHOTONZ_PLAYTEST
import CoreGraphics
import Foundation

enum PlaytestScreenState {
    /// The status a walk reports when the screen was locked while it ran.
    /// Neither "ok" nor "failed": every layer above treats it as "no answer".
    static let lockedStatus = "locked"

    /// What to tell whoever reads the run, in words that say what to do.
    static let lockedExplanation =
        "the Mac's screen was locked while this walk ran, so the window it drives was never "
        + "drawn on screen: layout and animations stop, control names never arrive, and screen "
        + "capture is refused. Nothing a walk reads in that state is worth reporting, so this "
        + "run is not a pass and not a failure. Unlock the screen and run it again."

    /// Whether the screen is locked right now.
    ///
    /// `CGSessionCopyCurrentDictionary` is the same answer the login window
    /// itself keeps, so this is true for a screen locked by hand, by the
    /// screen saver, or by the display going to sleep with a password asked
    /// for. Nothing here can unlock it, and nothing tries.
    static var isLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) == true
            || (session["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue == true
    }

    /// Whether this run was told to go ahead anyway, with
    /// `PHOTONZ_ALLOW_LOCKED_WALK=1`.
    ///
    /// For working on the harness itself, which is the one job that needs a
    /// walk to run under a lock: the fix above was checked exactly this way,
    /// by watching a tutorial step resolve its anchor with the window still
    /// occluded. Nothing in the loop sets it.
    ///
    /// It buys the run, not the verdict. `done.json` still carries
    /// `screenLocked: true` and the log still says so in words, because a walk
    /// that ran on a locked screen is not evidence about the app however
    /// deliberately it was started.
    static var isAllowedAnyway: Bool {
        ProcessInfo.processInfo.environment["PHOTONZ_ALLOW_LOCKED_WALK"] == "1"
    }

    /// What the log says when a run was let through.
    static let allowedAnywayNote =
        "PHOTONZ_ALLOW_LOCKED_WALK=1, so this walk ran with the screen LOCKED. The window is "
        + "not being drawn: layout and animations stop, control names never arrive and screen "
        + "capture is refused. Whatever this run reports is not evidence about the app."
}
#endif
