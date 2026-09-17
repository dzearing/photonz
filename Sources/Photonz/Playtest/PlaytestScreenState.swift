// Whether this Mac's screen is locked, which decides whether a walk's answer
// is worth anything at all.
//
// A scripted walk finds a control BY NAME: the button called "Add Effect", the
// row called "Background". That name is the accessibility label SwiftUI hands
// to AppKit, and it is the one thing a locked screen takes away. With the login
// window up, every control still exists at the right place and the right size
// and still carries its tooltip, and its name comes back EMPTY. So step after
// step reports a control missing while it is plainly on screen, and a whole
// sweep turns into failures that are not in the app.
//
// Everything else about the app keeps working, and it is worth being exact
// about that, because four separate runners have burned part of their turn
// re-running walks by hand to disprove the old explanation. Forced past this
// refusal with PHOTONZ_ALLOW_LOCKED_WALK=1 on 2026-09-16, one walk:
//
//   [4 drag] (320, 260) to (620, 460) document, ... changed 7 ... last 608.0/448.0
//   [5 wait] never went quiet (16 of 16 slices busy, 5 restless (animating
//            CAShapeLayer transition)); mainBusy 757.3ms over 2488 passes
//   [6 panelMenu] FAILED: no menu called "Add Effect" is in the window; the ones
//            that are: ... 25.0pt wide at x 1218.0 says "Add an effect: a
//            shadow, a glow, a border or a blur"
//
// The drag drove the app and moved things, layout ran, animations were running,
// and the control the step could not find was there at the right size with the
// right tooltip and no name. Layout and animation do NOT stop. Nor does the
// camera: a two-snapshot walk on the same locked Mac wrote before-sc.png and
// after-sc.png, different pictures, the second one showing the rectangle the
// walk had just dragged out. A locked run that photographed nothing had died at
// a name lookup before it ever reached its snapshot step.
//
// The app is fine. The walk is not: it cannot find anything by name, so what it
// reports is about the lock and not about the app.
//
// That is not a hypothetical. The Mac locked at 2026-09-14 20:46:47 and the
// sweep at 00:09 reported 115 of 400 walks broken, including every one of the
// 31 tutorial walks, on source that had passed all 31 eight hours earlier.
// Runners were then sent to hunt bugs that were not there.
//
// So a walk that looks a control up by name does not pass and does not fail
// under a lock. It did not run, and it says so.
//
// A walk that never looks one up is a different matter, and it is half the
// set: it clicks points, drags, presses keys, photographs the window and
// reaches panel controls through the app's own register of them, none of which
// a lock can touch. Those RUN, and their answers count. Which steps are which
// is `PlaytestLockSafety` in PhotonzCore, one list, unit tested, where a step
// kind earns its place by being watched working under a lock rather than by
// looking safe.
#if PHOTONZ_PLAYTEST
import CoreGraphics
import Foundation

enum PlaytestScreenState {
    /// The status a walk reports when the screen was locked while it ran.
    /// Neither "ok" nor "failed": every layer above treats it as "no answer".
    static let lockedStatus = "locked"

    /// What to tell whoever reads the run, in words that say what to do.
    static let lockedExplanation =
        "the Mac's screen was locked while this walk ran. The app itself keeps working: it is "
        + "still laid out, still animating, still driven by the walk's clicks and drags, and a "
        + "snapshot step can still photograph it. What a locked screen takes away is the NAME on "
        + "every control, which is how a walk finds one. Steps then report a control missing while "
        + "it is on screen at the right size with the right tooltip, so the failures are in the "
        + "walk and not in the app. This run is not a pass and not a failure. Unlock the screen "
        + "and run it again."

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
    /// walk to run under a lock: what the comment at the top of this file
    /// knows about a locked screen was all learned this way.
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
        "PHOTONZ_ALLOW_LOCKED_WALK=1, so this walk ran with the screen LOCKED. The app is drawn "
        + "and driven normally and can still be photographed, but no control carries a name, so "
        + "every step that looks one up fails however healthy the app is. Whatever this run "
        + "reports is not evidence about the app."
}
#endif
