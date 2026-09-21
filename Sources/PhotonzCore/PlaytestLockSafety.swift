import Foundation

/// Whether a walk can still run with the Mac's screen locked.
///
/// A lock does NOT stop the app. It is drawn, it animates, it takes the walk's
/// clicks and drags, and it can be photographed: on 2026-09-17, on a Mac locked
/// since the 14th, `redline-walk` ran all 70 of its steps and wrote fourteen
/// real pictures of the window, and `layers-list-follows-pick-walk` ran 103.
/// What a lock takes away is the NAME that SwiftUI hands to accessibility, so
/// every step that asks accessibility for a control reports it missing while it
/// is plainly on screen at the right size with the right tooltip.
///
/// That is a difference a walk can be sorted by. Half of the walk set never
/// asks accessibility for anything: it clicks points, drags, presses keys,
/// photographs the window, and finds panel controls through the app's own
/// register of them, which a lock cannot touch. Those walks run, and the
/// pictures they take are the app. The rest cannot, and are refused rather than
/// reporting failures that are about the lock (`PlaytestScreenState`).
///
/// Everything here is decided off the walk's own steps, before anything is
/// driven, so a walk knows before it launches whether its answer would be worth
/// anything.
public enum PlaytestLockSafety {

    /// Step kinds watched working with the screen locked, each one inside a
    /// walk that ran end to end on a locked Mac on 2026-09-17:
    ///
    /// - `panel-sections-walk`, 74 steps: blank, wait, action, tool, drag,
    ///   click, describe, expect, waitFor, panel, snapshot, press, appKey,
    ///   type, key, dragTile.
    /// - `gap-between-drawn-shapes-walk`, 81 steps: open, measureMode, move,
    ///   expectMeasures, clearClipboard, readClipboard.
    /// - `pen-arms-its-colour-walk`, 58 steps: toolBar, expectPath, render,
    ///   expectLayers.
    /// - `arrow-parts-walk`, 53 steps: dragColor.
    /// - `path-line-style-walk`, 93 steps: writeSVG.
    /// - `layers-list-follows-pick-walk`, 103 steps: scrollPanel, selectRow,
    ///   reveal.
    /// - `pen-draws-a-path-walk`, 70 steps: expectPicked.
    /// - `icon-previews-stay-with-nothing-picked-walk`, all 77 steps and six
    ///   real window captures, forced under a lock on 2026-09-19:
    ///   expectIconPreviews. It reads the editor's own previews strip inside
    ///   the app's process and never asks accessibility for anything, so a
    ///   lock has nothing to take away from it.
    /// - `name-chip-reads-anywhere-walk`, 24 steps before it failed on a
    ///   missing component tile, which is a fact about the walk and not about
    ///   the lock: dropImage, pinch, appearance.
    /// - `find-what-stayed-a-picture-walk`, 30 steps on a Mac locked since
    ///   2026-09-14: expectNotice, expectInView. Both read the app rather than
    ///   accessibility — the pill's own sentence, and a control's geometry out
    ///   of the register `press` already uses — so a lock has nothing to take
    ///   away from either.
    /// - `undo-while-trimming-walk`, 35 steps on a Mac locked since
    ///   2026-09-14: expectRecording. It asks the open recording how many
    ///   pieces it is in, which one is picked, how long the trim window is and
    ///   whether the handles are open. Every one of those is the app's own
    ///   state and none of them is a name, so the readings came back right
    ///   three times over ("3 pieces, piece 2 picked, window 8.00s, trim
    ///   open"). That un-refuses the video walks whose only blocked step was
    ///   this one.
    /// - `trim-save-send-walk`, 42 steps forced under a lock on 2026-09-19:
    ///   expectStoredRecording. It opens the recording's own FILE with
    ///   AVFoundation and measures it, and looks for the preserved original
    ///   beside it with FileManager. Neither is a control and neither is a
    ///   name, so a lock has nothing to take away: the four readings in that
    ///   walk came back 8.00s, 4.00s, 2.00s and 8.00s exactly as the saves
    ///   should have left them.
    /// - `close-a-trimmed-recording-walk`, 18 steps forced under a lock on
    ///   2026-09-19: expectWindows. It counts the app's own windows by their
    ///   titles, which the app sets itself and a lock cannot take away, so it
    ///   correctly reported the recording's window gone after the save closed
    ///   it.
    /// - `delete-key-drops-a-piece-walk`, 27 steps forced under a lock on
    ///   2026-09-17: shortcut. It reads the menu bar in the app's own process
    ///   and compares key equivalents, which are the app's own data and not an
    ///   accessibility name, so it named its item correctly ("delete is Video
    ///   ▸ Delete This Piece") and ran the chord's stand-in. It never opens a
    ///   menu, so the thing a lock really stops does not arise.
    /// - `nudge-stays-sharp-walk`, 16 steps forced under a lock on
    ///   2026-09-20: expectSharp. It asks the editor whether it has a sharp
    ///   copy of what is in the window and which camera that copy was drawn
    ///   for, both of which are the app's own state inside the app's own
    ///   process. It answered correctly twice in one run under the lock: it
    ///   passed before a shape was nudged and failed after it, which is the
    ///   bug it was written for.
    /// - `tool-tips`, `segment-tooltips-walk`, `history-tooltips-walk`,
    ///   `panel-toggle-titlebar-walk`, `path-points-under-the-pen-walk` and
    ///   `marquee-answers-to-m-walk`, all green on a Mac locked since
    ///   2026-09-14: hover. A tooltip's own name is not an accessibility name —
    ///   it is the word the app itself hung on a `HintAnchorView` — so a lock
    ///   takes nothing away from it, and the tooltip window it raises is a
    ///   window of the app's own that a snapshot still photographs (the
    ///   captures come out "with 1 window hung on it"). Six walks that were
    ///   being refused now run.
    ///
    /// - Twenty-two walks forced on 2026-09-20 under a lock three days old,
    ///   every one of them `ok`, between them watching twenty-four kinds that
    ///   had been refused for want of a witness: `dropComponent`,
    ///   `dragComponent`, `dragFile`, `expectBox`, `expectHint`,
    ///   `expectBuilds`, `expectRegion`, `toolFlyout`, `expectClickReaches`,
    ///   `expectFeet`, `expectCaption`, `expectReadout`, `exportQuality`,
    ///   `expectLanding`, `expectListStill`, `panelEdge`, `panelStart`,
    ///   `dragHandle`, `dragOver`, `dragRow`, `dragSection`, `expectChrome`,
    ///   `expectSVG`, `expectOneUnit`. The drags go through the app's own
    ///   pasteboard and its own views, and every reading is the app's own
    ///   state: `frame-second-screen-walk` measured "Frame" at (80, 38),
    ///   1440x1024; `panel-edge-narrow-walk` put eight icon centres on one
    ///   line; `row-put-down-walk` let a row go below another and the list took
    ///   it. Which walk watched which kind is written out in
    ///   `PlaytestLockSafetyTests`. That un-refuses 43 walks, so a locked sweep
    ///   runs 309 of 543 rather than 266.
    ///
    /// A step kind joins this list by being watched, not by looking safe.
    public static let stepsThatSurviveALock: Set<String> = [
        "action", "appKey", "appearance", "blank", "clearClipboard", "click", "describe", "drag",
        "dragColor", "dragTile", "dropImage", "expect", "expectInView", "expectLayers",
        "expectMeasures", "expectNotice",
        "expectEdited", "expectIconPreviews", "expectPath", "expectPicked", "expectRecording",
        "expectStoredRecording",
        // Watched on 2026-09-20, forced under a lock: it asks the editor for
        // the sharp copy it is drawing and the camera it was drawn for, which
        // are its own state and not a name.
        "expectSharp",
        // Watched on 2026-09-19, forced under a lock: it asks the app's own
        // toast controller what the corner is saying, so there is no name to
        // look up and nothing for a lock to take away.
        "expectToast",
        "expectWindows", "hover", "key", "measureMode", "move",
        "open", "panel", "pinch",
        "press", "readClipboard", "render", "reveal", "scrollPanel", "selectRow", "shortcut",
        "snapshot",
        "tool", "toolBar", "type", "wait", "waitFor", "writePicture", "writeRecording", "writeSVG",
        // Watched on 2026-09-20, twenty-two walks forced under a lock and all
        // of them green. Every one of these either drives the app through its
        // own pasteboard and its own views, or reads a number the app is
        // already holding. Neither is a name and neither is an NSMenu.
        "dropComponent", "dragComponent", "dragFile", "expectBox", "expectHint", "expectBuilds",
        "expectRegion", "toolFlyout", "expectClickReaches", "expectFeet", "expectCaption",
        "expectReadout", "exportQuality", "expectLanding", "expectListStill", "panelEdge",
        "panelStart", "dragHandle", "dragOver", "dragRow", "dragSection", "expectChrome",
        "expectSVG", "expectOneUnit",
    ]

    /// Why a lock stops the rest, in the words the refusal says out loud.
    ///
    /// Two kinds of entry. Some are known to break, and say what breaks. The
    /// rest are simply unproven: nobody has watched them run under a lock, and
    /// the default is to refuse rather than to trust, because a walk whose
    /// failures are about the lock is exactly what sent runners hunting bugs
    /// that were not in the app on 2026-09-15.
    public static let lockStops: [String: String] = {
        // Watched on 2026-09-17: `wrap-at-a-ceiling-walk`, forced under a lock,
        // reached its `focus` step and listed the editable fields it could see
        // as "Opacity, Corner Radius, None, None, Gap, Padding". The step
        // itself runs — it walks the app's own views in the app's own process,
        // which a lock cannot touch — and the two limit fields are right there.
        // What comes back empty is their NAME, so they answer only to the
        // placeholder "None" and never to "Smallest width" or "Largest width".
        let accessibility = "finds what it needs by asking accessibility for a name, and a locked "
            + "screen hands back an empty one, so it would report a control missing that is on "
            + "screen at the right size with the right tooltip"
        let menu = "opens a real menu, and an open menu is a window of its own that the app can "
            + "neither drive nor photograph while the login window is up"
        // A `menus` step opens nothing: it reads NSApp.mainMenu inside the
        // app's own process. What stops it is the frozen menu bar. A walk
        // never brings the probe to the front, so the only thing that ever
        // gives it a live bar is one of its own windows taking key, and a
        // locked Mac gives nothing key. Forced on 2026-09-19,
        // `save-is-live-after-a-trim-walk` opened the Capture History overlay
        // exactly as it does unlocked and the reading still came back "nothing
        // in the probe has focus", which is the step saying its own answer is
        // worthless. Saying "opens a real menu" instead sent that day's runner
        // into the harness source to find the real objection.
        let frozenBar = "reads the menu bar, and a locked Mac gives no window of the app key. "
            + "SwiftUI only fills a window-scoped command in for a window that has focus, so every "
            + "one of them reads dimmed and empty however the document changes, and the step itself "
            + "says so rather than pretending ('nothing in the probe has focus')"
        let tutorial = "needs a tutorial card, and a card is not drawn while the login window is "
            + "over the app, so it would wait for something that never appears"
        let unproven = "has never been watched running with the screen locked, so it is refused "
            + "rather than trusted; force the walk, and if the step works, say so and it moves "
            + "to the list of steps a lock cannot touch"
        var stops: [String: String] = [
            "focus": accessibility,
            "expectField": accessibility,
            "menus": frozenBar,
            "menuShot": menu,
            "panelMenu": menu,
            "rightClick": menu,
            "startGuide": tutorial,
            "expectTutorialStep": tutorial,
            "expectTutorialTracks": tutorial,
        ]
        for name in PlaytestStep.names
        where stops[name] == nil && !stepsThatSurviveALock.contains(name) {
            stops[name] = unproven
        }
        return stops
    }()

    /// Every step kind a lock stops, however it stops it.
    public static var stepsALockStops: Set<String> { Set(lockStops.keys) }

    /// What a locked screen would do to this one step, or nil when it would do
    /// nothing at all.
    public static func lockTrouble(with step: PlaytestStep) -> String? {
        // A wait is only as safe as the thing it waits for: a tutorial card is
        // the one thing on this list that a lock genuinely hides.
        if case .waitFor(let condition, _) = step {
            switch condition {
            case .tutorialStep, .tutorialFinished:
                return "waits for a tutorial card, and a card is not drawn while the login window "
                    + "is over the app, so it would wait for something that never appears"
            default:
                break
            }
        }
        return lockStops[step.name]
    }

    /// The steps in this walk a locked screen would stop, in order.
    public static func nameLookups(in steps: [PlaytestStep]) -> [(step: Int, name: String)] {
        steps.enumerated().compactMap { index, step in
            lockTrouble(with: step) == nil ? nil : (step: index + 1, name: step.name)
        }
    }

    /// Whether this walk can run with the screen locked and be believed.
    public static func canRunLocked(_ steps: [PlaytestStep]) -> Bool {
        nameLookups(in: steps).isEmpty
    }

    /// What to tell whoever ran a walk that cannot run under a lock: which step
    /// stops it, why, and what forcing it would still photograph. That last
    /// part is the decision a runner actually has to make, since an audit with
    /// no picture of the app in it is the cost of getting this wrong.
    public static func refusal(for steps: [PlaytestStep]) -> String? {
        guard let first = nameLookups(in: steps).first,
              let why = lockTrouble(with: steps[first.step - 1]) else { return nil }
        let pictures = steps.filter(asksForAPicture).count
        let before = steps.prefix(first.step - 1).filter(asksForAPicture).count
        var said = "this walk cannot run with the screen locked: step \(first.step) "
            + "(\(first.name)) \(why). "
        if pictures == 0 {
            said += "It asks for no pictures, so there is nothing to be had by forcing it."
        } else if before == 0 {
            said += "Forcing it with PHOTONZ_ALLOW_LOCKED_WALK=1 gets none of its \(pictures) "
                + "picture\(pictures == 1 ? "" : "s"): the first one comes after that step."
        } else {
            said += "Forcing it with PHOTONZ_ALLOW_LOCKED_WALK=1 still photographs \(before) of "
                + "its \(pictures) picture\(pictures == 1 ? "" : "s") before it stops there, and "
                + "those pictures are the real window."
        }
        return said
    }

    /// The line that goes under a picture taken while the Mac was locked,
    /// wherever it is shown. The window in it is real; two things about it are
    /// not what a person at the machine would see, and saying so is what stops
    /// the next reader filing a dimmed colour as a bug.
    public static let pictureLabel =
        "Photographed while the Mac was locked. The window is the real one, drawn and driven "
        + "normally, with two known costs: colours can read dimmed, and a tutorial card does not "
        + "draw at all because the login window is over it."

    /// Whether this step asks for a picture of the window.
    private static func asksForAPicture(_ step: PlaytestStep) -> Bool {
        switch step {
        case .snapshot: true
        // The onboarding card only exists before a canvas does, so `blank` is
        // the only step that can photograph it.
        case .blank(_, _, let card, _): card != nil
        default: false
        }
    }
}
