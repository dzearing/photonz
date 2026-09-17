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
    /// - `name-chip-reads-anywhere-walk`, 24 steps before it failed on a
    ///   missing component tile, which is a fact about the walk and not about
    ///   the lock: dropImage, pinch, appearance.
    /// - `find-what-stayed-a-picture-walk`, 30 steps on a Mac locked since
    ///   2026-09-14: expectNotice, expectInView. Both read the app rather than
    ///   accessibility — the pill's own sentence, and a control's geometry out
    ///   of the register `press` already uses — so a lock has nothing to take
    ///   away from either.
    ///
    /// A step kind joins this list by being watched, not by looking safe.
    public static let stepsThatSurviveALock: Set<String> = [
        "action", "appKey", "appearance", "blank", "clearClipboard", "click", "describe", "drag",
        "dragColor", "dragTile", "dropImage", "expect", "expectInView", "expectLayers",
        "expectMeasures", "expectNotice",
        "expectPath", "expectPicked", "key", "measureMode", "move", "open", "panel", "pinch",
        "press", "readClipboard", "render", "reveal", "scrollPanel", "selectRow", "snapshot",
        "tool", "toolBar", "type", "wait", "waitFor", "writeSVG",
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
        let tutorial = "needs a tutorial card, and a card is not drawn while the login window is "
            + "over the app, so it would wait for something that never appears"
        let unproven = "has never been watched running with the screen locked, so it is refused "
            + "rather than trusted; force the walk, and if the step works, say so and it moves "
            + "to the list of steps a lock cannot touch"
        var stops: [String: String] = [
            "focus": accessibility,
            "expectField": accessibility,
            "menus": menu,
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
