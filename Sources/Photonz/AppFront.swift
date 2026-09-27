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

    /// Show a panel that floats over every app and takes the keys, the way
    /// the capture history strip comes down over whatever a person is doing.
    ///
    /// A non-activating panel that makes itself key takes the keyboard from
    /// the app a person is typing in without that app ever losing the front:
    /// during a walk the strip sat over the person's window and swallowed
    /// every key they typed (focus drill, 2026-09-26, history-menu-title-walk).
    /// A walk's strip goes under their windows instead and leaves the keys
    /// where they are; its presses are handed to the app directly. The same
    /// goes for a toast in the screen's corner (`takingKeys: false`), which
    /// sat over the person's work for as long as it was up
    /// (opening-a-recording-walk).
    static func showFloating(_ panel: NSPanel, takingKeys: Bool = true) {
        #if PHOTONZ_PLAYTEST
        if aWalkIsDriving {
            panel.level = PlaytestHarness.walkWindowLevel
            panel.orderBack(nil)
            return
        }
        #endif
        panel.orderFrontRegardless()
        if takingKeys { panel.makeKey() }
    }

    /// Bring a window of the app's own forward and give it the keys, as
    /// `makeKeyAndOrderFront` does, for a person and never for a walk: the
    /// Welcome window floats over every app, and during a walk it sat over the
    /// person's work for as long as it was open (focus drill, 2026-09-26,
    /// never-granting-walk). A walk's goes under their windows instead.
    static func present(_ window: NSWindow) {
        #if PHOTONZ_PLAYTEST
        if aWalkIsDriving {
            window.level = PlaytestHarness.walkWindowLevel
            window.orderBack(nil)
            return
        }
        #endif
        window.makeKeyAndOrderFront(nil)
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
