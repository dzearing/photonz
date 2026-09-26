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
    /// - `focus`, the single biggest stop in the set at 100 walks, watched on
    ///   2026-09-21 in all 71 of the walks it was the ONLY thing stopping,
    ///   forced on a Mac locked since the 17th, every one of them green. It
    ///   stopped needing accessibility that day: it now asks the panel's own
    ///   register what a box is called (`PlaytestPanelPress.registeredNames`),
    ///   the same register `press`, `reveal` and `selectRow` have always used,
    ///   and only falls back to the placeholder and the accessibility label
    ///   after that. `width-reads-back-walk` typed into "Smallest width" and
    ///   read "W" back three times under the lock; `piece-geometry-walk` ran
    ///   all 63 of its steps. Two boxes had no register name and no usable
    ///   placeholder and were given one: a copy's wording knob while it reads
    ///   Mixed (`InstanceTextKnob`), and one walk that was asking for a field
    ///   called "Knob name" that the app calls "Property name".
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
        // Added 2026-09-25 by reading, NOT yet watched under a lock (the screen
        // was unlocked all day): it asks the editor how wide each frame on
        // screen was read and how wide it is shown, the same kind of own state
        // as expectSharp, never a name. A guide walk has to be lock safe, so
        // the first locked sweep is its watch; if it refuses there, take it out.
        "expectFrameSharp",
        // Added 2026-09-26 by reading, NOT yet watched under a lock: it asks a
        // clip's timeline bar what it last drew, which the bar tells the
        // harness itself, never a name. The second-clip guide walk reads it,
        // so the first locked sweep is its watch; if it refuses there, take
        // it out.
        "expectWaveform",
        // Added 2026-09-26 by reading, NOT yet watched under a lock: it holds
        // the playhead through the editor's own calls and reads the pictures
        // and moments the editor is holding, never a name. The first locked
        // run of scrub-never-blacks-out-walk is its watch; if it refuses
        // there, take it out.
        "expectScrubSmooth",
        // Watched on 2026-09-19, forced under a lock: it asks the app's own
        // toast controller what the corner is saying, so there is no name to
        // look up and nothing for a lock to take away.
        "expectToast",
        "expectWindows", "hover", "key", "measureMode", "move",
        "open", "panel", "pinch",
        "press", "readClipboard", "render", "reveal", "scrollPanel", "selectRow", "shortcut",
        "snapshot",
        "tool", "toolBar", "type", "wait", "waitFor", "writePicture", "writeRecording", "writeSVG",
        // A video export asks the editor to write a file and then opens the
        // file: no name, no menu, and nothing on screen it depends on. Writing
        // one frame out as a picture is the same thing, one frame long.
        "writeVideo", "writeFrame",
        // Watched on 2026-09-20, twenty-two walks forced under a lock and all
        // of them green. Every one of these either drives the app through its
        // own pasteboard and its own views, or reads a number the app is
        // already holding. Neither is a name and neither is an NSMenu.
        "dropComponent", "dragComponent", "dragFile", "expectBox", "expectHint", "expectBuilds",
        "expectRegion", "toolFlyout", "expectClickReaches", "expectFeet", "expectCaption",
        // Watched on 2026-09-21 in all 71 walks it was the only stop in, once
        // it stopped asking accessibility for the name and started asking the
        // panel's own register.
        "focus",
        // Watched on 2026-09-21: `turned-words-walk`, forced under a lock,
        // read the canvas's typing field back four times — "corner (370.2,
        // 288.9), leaning 20.0 degrees; draft \"Save\" ... 55.0 by 33.0". It
        // was listed as an accessibility step and never was one: it asks the
        // canvas for the geometry of the box it is drawing, which is the app's
        // own state inside the app's own process.
        "expectField",
        // Watched on 2026-09-21: `component-whole-path-walk`, forced under a
        // lock, reached both of its `expectOneNumberPerName` steps once
        // `focus` stopped stopping it, and read "no two rows in the panel wear
        // one name over different numbers, across 2 named readouts" each time.
        // It was one of the six nobody could reach; `focus` was what came
        // first.
        "expectOneNumberPerName",
        // Watched on 2026-09-22, and the biggest single stop left in the set
        // at 80 walks. Nothing about opening a panel menu needs the menu to be
        // ON SCREEN: the rows are read out of the button's own `NSMenu` and a
        // row is chosen with `performActionForItem(at:)`, both inside the
        // app's own process, and since 2026-09-21 the menu's own name comes
        // from the panel's register rather than from accessibility. All 80
        // walks that use one were forced twice on a Mac locked since the 17th
        // and 77 were green both times; the three exceptions were two tutorial
        // cards and one walk since corrected and green twice
        // (`walks-that-fail-in-the-full-sweep`, batch 14).
        //
        // The one thing that kept it refused until today was a doubt about
        // the colour picker: four walks pressed a colour well under a lock and
        // found no picker, which read as "a popover raised by a click does not
        // come up while the login window is up". It does. The locked sweep of
        // 2026-09-22 03:01 ran ten walks that press a well and then press
        // controls INSIDE the picker — `picker-controls-walk` pressed Solid,
        // Linear, Add a stop, Radial and Angular — and every one of them
        // passed. What had been wrong was the way a synthesized press was
        // delivered, fixed in batches 13 and 14; the same four walks pass with
        // somebody logged in too.
        //
        // A panel menu asked for its PICTURE is still refused, in
        // `lockTrouble(with:)`, because that is the one part of it that really
        // does need the menu on screen.
        "panelMenu",
        // Watched on 2026-09-21: `motion-timing-strip-walk`, forced under a
        // lock, dragged the same bar four times and read the milliseconds back
        // each time — "Ellipse Rotation body dragged 90 ms: 0-900 ms became
        // 90-990 ms", and a drag carried 400 ms and called off with a real
        // Escape "is back at 90 to 990 ms". It drives the strip's own views and
        // reads the document's own times. It was on the unreachable list
        // because `panelMenu` came first.
        "dragTiming",
        // Watched on 2026-09-22, and the last big stop in the set at 39
        // walks. Starting a guide, asking which step it is on and waiting for
        // one are all the guide's own state inside the app's own process
        // (`TutorialController.run`), and the check each step is held to —
        // that the control it rings is really on screen — reads the app's own
        // anchor registry, which a lock cannot touch: caught on the locked Mac
        // of 2026-09-15, "mark-it-up/pick-arrow ... occlusion HIDDEN; found
        // after 0.5s on screen".
        //
        // What a lock really took was the CARD's picture, and that was the
        // trap: every one of the 39 walks photographs the window after its
        // guide starts, so refusing only the ones that ask for a picture
        // would have un-refused none of them, and letting them run as they
        // were would have shipped 39 walks' worth of pictures with an empty
        // space where the card belongs. Both halves are now closed. A guide
        // driven by a walk keeps its card up however buried the window is
        // (`TutorialCardPresence`), and a `snapshot` taken while a guide is
        // showing refuses to photograph a window the card is missing from,
        // reporting `locked` rather than a failure when the screen is locked.
        // So a tutorial walk under a lock either answers honestly with the
        // card in its pictures, or reports no verdict at all.
        //
        // `expectTutorialTracks` is NOT here: it reads the Tutorials window
        // through the accessibility tree, which is exactly what a lock empties.
        "startGuide", "expectTutorialStep",
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
        let tutorial = "reads the Tutorials window through the accessibility tree, and a locked "
            + "screen takes the name off everything in it, so the list would read empty however "
            + "many tracks are really offered"
        let unproven = "has never been watched running with the screen locked, so it is refused "
            + "rather than trusted; force the walk, and if the step works, say so and it moves "
            + "to the list of steps a lock cannot touch"
        // `dragMotionKey` is the same machinery as `dragTiming` pointed at one
        // key rather than the whole bar — it drives the strip's own views and
        // reads the document's own times, and nothing in it asks for a name —
        // and it is still refused, because a kind joins the list above by being
        // watched and nobody has watched this one. It was written on
        // 2026-09-22 on an unlocked Mac. The first runner to find the screen
        // locked should force `punch-in-and-hold-walk`, and if its two
        // `dragMotionKey` steps read their milliseconds back, move it up.
        let keyDrag = "has never been watched running with the screen locked. It is the same "
            + "machinery as dragTiming, which a lock cannot touch, so forcing the walk will very "
            + "likely work: do that, say so, and it moves to the list of steps a lock cannot touch"
        var stops: [String: String] = [
            "dragMotionKey": keyDrag,
            "menus": frozenBar,
            "menuShot": menu,
            "rightClick": menu,
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
        // A panel menu is read and chosen from inside the app's own process,
        // so a lock takes nothing away from it — unless the step wants a
        // PICTURE of the open menu, which is the one part that needs the menu
        // really on screen, or opens it by clicking some other control, which
        // nobody has watched under a lock.
        if case .panelMenu(_, _, let shot, _, let clicking) = step {
            if shot != nil {
                return "asks for a picture of the open menu, and a menu draws outside this "
                    + "process: the only picture of one there is comes from the screen recorder "
                    + "photographing its own window, which is not there while the login window "
                    + "is up. The same step without a picture runs"
            }
            if clicking != nil {
                return "opens its menu by clicking another control, which has never been watched "
                    + "with the screen locked; the same step opened by pressing the menu itself "
                    + "runs"
            }
            return nil
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
        + "normally, with one known cost: colours can read dimmed. A tutorial card used to be a "
        + "second cost, and is not since 2026-09-22: a guide a walk is driving keeps its card up "
        + "however buried the window is, and a walk that finds the card missing stops rather than "
        + "photographing the window without it."

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
