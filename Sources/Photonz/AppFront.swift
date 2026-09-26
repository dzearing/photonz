import AppKit

/// The app bringing itself to the front, for a person and never for a walk.
///
/// A scripted walk drives the probe on a Mac a person may be using. Every place
/// the app pulls itself forward (a window opening, an alert, the Open panel,
/// handing the front back to the app used last) took that person's keyboard
/// mid-sentence: on 2026-09-26 the user could not type while the loop tested,
/// and opening a recording in a walk made the probe the active app, measured by
/// `queue/bin/focus-drill.sh`. A walk never needs the front: it drives the
/// window it holds and photographs that window directly. So while one runs,
/// these do nothing, and the app a person is typing in keeps the keys.
///
/// Always the plain activation in the shipping build, which has no harness.
@MainActor
enum AppFront {
    /// Whether a walk is driving this app, from the moment it was launched for
    /// one, so nothing at launch slips in ahead of the walk starting.
    static var aWalkIsDriving: Bool {
        #if PHOTONZ_PLAYTEST
        PlaytestHarness.isDrivingAWalk || CommandLine.arguments.contains(PlaytestHarness.argument)
        #else
        false
        #endif
    }

    /// Bring Photonz to the front.
    static func activate() {
        guard !aWalkIsDriving else { return }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hand the front to another app, the one that had it before.
    static func activate(_ app: NSRunningApplication) {
        guard !aWalkIsDriving else { return }
        app.activate()
    }

    /// Show a panel that hangs on `window` (a tooltip, a guide's card).
    ///
    /// `orderFront` on a child window lifts the whole family, so during a walk
    /// it pulled the walk's window up over the person's work at every tooltip
    /// and every guide step. A walk's panel goes just above its own window
    /// instead, wherever that window is.
    static func show(_ panel: NSWindow, above window: NSWindow) {
        if aWalkIsDriving {
            panel.order(.above, relativeTo: window.windowNumber)
        } else {
            panel.orderFront(nil)
        }
    }
}
