import Foundation

// The one question a new person is asked, and the rules that keep it to one.
//
// After the setup window has walked somebody through the macOS permissions
// Photonz needs, there is exactly one moment where offering to show them round
// is welcome. This decides when that moment is, what closing the window means,
// and how an install that predates tutorials is left alone. It is pure so the
// whole sequence can be driven in tests: the traps here are all in the ORDER of
// a real first run, and an order is a thing you can check without a window.
//
// The rules, and what each one is defending against:
//
//  * The choice waits for Screen Recording to be granted AND for no restart to
//    be pending. A Screen Recording grant only takes effect in a fresh process,
//    so the setup window's last act on a brand new Mac is "Relaunch Photonz".
//    A tour started there is a tour a restart kills twenty seconds later.
//  * CLOSING the window while everything works counts as skip. Without that,
//    somebody who reaches for the red button instead of either offered button
//    is asked again on every launch for ever, which is the nagging this is
//    supposed to prevent.
//  * The migration stamp happens ONCE, on the first launch of a build that
//    knows about tutorials. Run every launch, it would fire on the new person
//    the moment they restart (by then their setup IS complete) and quietly eat
//    the offer they were owed.
//
// There is no second offer anywhere else in the app. One question, one
// remembered answer, and Help ▸ Tutorials for ever after.

/// What somebody said when they were asked, once.
public enum FirstRunAnswer: String, Codable, Hashable, Sendable, CaseIterable {
    /// Show me around.
    case tour
    /// Let me at it.
    case skip
}

/// When the first run offer is made, what closing the window means, and how an
/// existing install is left alone.
public enum FirstRunOffer {

    /// Whether the setup window opens itself at launch.
    ///
    /// Unfinished setup presents it, exactly as it always has. On top of that,
    /// a finished setup that has never been asked about the tour presents it
    /// once, which is how somebody who granted permission and restarted gets
    /// the question on the first launch where the app actually works.
    public static func presentsAtLaunch(setupCompleted: Bool, answer: FirstRunAnswer?,
                                        tutorialsEnabled: Bool) -> Bool {
        if !setupCompleted { return true }
        guard tutorialsEnabled else { return false }
        return answer == nil
    }

    /// Whether the window is showing the two ways on right now.
    ///
    /// Deliberately NOT waiting on the recommended steps (the screenshot key
    /// conflicts). Those are worth fixing and not worth being blocked by, and
    /// waiting on them would leave somebody who never frees the keys being
    /// asked on every launch.
    public static func showsChoice(tutorialsEnabled: Bool, screenRecordingGranted: Bool,
                                   needsRelaunch: Bool, answer: FirstRunAnswer?) -> Bool {
        tutorialsEnabled && answer == nil && screenRecordingGranted && !needsRelaunch
    }

    /// What closing the window records, or nil to record nothing.
    ///
    /// Not gated on whether tutorials are switched on: an install that finishes
    /// setup while there is no offer to make has still had its first run, and
    /// recording that here is what stops the question arriving months later
    /// out of nowhere.
    public static func answerOnDismiss(screenRecordingGranted: Bool, needsRelaunch: Bool,
                                       answer: FirstRunAnswer?) -> FirstRunAnswer? {
        guard answer == nil, screenRecordingGranted, !needsRelaunch else { return nil }
        return .skip
    }

    /// What to write for an install that finished its setup before any of this
    /// existed, so an upgrade is never shown first run setup again.
    ///
    /// Called once ever, on the first launch of a build that knows about
    /// tutorials. See the note at the top for why once and not every launch.
    public static func migratedAnswer(setupCompleted: Bool,
                                      answer: FirstRunAnswer?) -> FirstRunAnswer? {
        guard answer == nil, setupCompleted else { return nil }
        return .skip
    }

    // MARK: - The words

    /// What the window says once everything works and the question is on the
    /// table. It replaces the setup line, so the last thing read before
    /// choosing is what the two buttons are for.
    ///
    /// It does not say "you are all set": the finished step above it already
    /// says that, and reading the same sentence twice eight lines apart makes
    /// the window feel like it is stalling.
    public static let headline =
        "Everything is ready. Take a quick lap of the window, or jump straight in. The tour is under Help whenever you want it."

    /// Show me around.
    public static let tourButtonTitle = "Take the Tour"

    /// Let me at it.
    public static let skipButtonTitle = "Start Working"

    /// The window's name for anything that finds a window by its name. It is
    /// not drawn: the panel hides its title bar text.
    public static let windowTitle = "Welcome"

    /// Every word above, labelled, so a test can run the repo's copy rules over
    /// the lot rather than over whichever one somebody remembered.
    public static var allCopy: [(String, String)] {
        [("first run headline", headline),
         ("first run tour button", tourButtonTitle),
         ("first run skip button", skipButtonTitle)]
    }
}
