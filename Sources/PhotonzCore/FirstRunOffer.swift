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
//  * The choice waits for no restart to be pending, and for nothing else. A
//    Screen Recording grant only takes effect in a fresh process, so the setup
//    window's last act on a brand new Mac is "Relaunch Photonz", and a tour
//    started there is a tour a restart kills twenty seconds later.
//    It does NOT wait for the grant itself. It used to, and that quietly meant
//    the one person never shown round was the person who came to build UI and
//    never intended to capture anything. The tour teaches the tool bar, the
//    layers list and the settings beside them; none of it touches the screen.
//  * CLOSING the window while the question is up counts as skip. Without that,
//    somebody who reaches for the red button instead of either offered button
//    is asked again on every launch for ever, which is the nagging this is
//    supposed to prevent. A finished setup with no question to ask counts too,
//    and only those two: see `answerOnDismiss` for why both and not either.
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
    /// Deliberately NOT waiting on Screen Recording, nor on the recommended
    /// steps (the screenshot key conflicts). Neither is worth being blocked by,
    /// and waiting on either leaves somebody who never sorts it being asked on
    /// every launch, or never asked at all. A pending restart is the one thing
    /// that does hold the question back, because it would end the tour.
    public static func showsChoice(tutorialsEnabled: Bool, needsRelaunch: Bool,
                                   answer: FirstRunAnswer?) -> Bool {
        tutorialsEnabled && answer == nil && !needsRelaunch
    }

    /// What closing the window records, or nil to record nothing.
    ///
    /// There are two separate reasons to stop asking, and both are needed.
    ///
    ///  * **The question was on screen**, so closing the window is the answer.
    ///    This has to track `showsChoice` exactly or somebody who reaches for
    ///    the red button instead of either offered button is asked again on
    ///    every launch for ever, which is the nagging this exists to prevent.
    ///  * **The install finished its setup** with no question to ask, which is
    ///    still its first run being over. That is what stops the question
    ///    arriving months later out of nowhere in a release where tutorials are
    ///    switched off.
    ///
    /// The second one is why this cannot simply be `showsChoice`, and the first
    /// is why it cannot simply be "setup is finished". Photonz ships Current and
    /// Next in one binary over one set of settings, so a brand new person who
    /// tries Current first and dismisses this window there must NOT have the
    /// offer they have never seen quietly spent on their behalf: with tutorials
    /// off and nothing granted, neither reason holds and nothing is recorded.
    public static func answerOnDismiss(tutorialsEnabled: Bool, screenRecordingGranted: Bool,
                                       needsRelaunch: Bool,
                                       answer: FirstRunAnswer?) -> FirstRunAnswer? {
        guard answer == nil, !needsRelaunch else { return nil }
        let wasAsked = showsChoice(tutorialsEnabled: tutorialsEnabled,
                                   needsRelaunch: needsRelaunch, answer: answer)
        guard wasAsked || screenRecordingGranted else { return nil }
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

    /// What the window says while the question is on the table. It replaces the
    /// setup line, so the last thing read before choosing is what the two
    /// buttons are for.
    public static func headline(screenRecordingGranted: Bool) -> String {
        screenRecordingGranted ? headlineWhenReady : headlineWhenSetupIsUnfinished
    }

    /// Everything works and the question is on the table.
    ///
    /// It does not say "you are all set": the finished step above it already
    /// says that, and reading the same sentence twice eight lines apart makes
    /// the window feel like it is stalling.
    public static let headlineWhenReady =
        "Everything is ready. Take a quick lap of the window, or jump straight in. The tour is under Help whenever you want it."

    /// The question is on the table with Screen Recording still unfinished.
    ///
    /// "Everything is ready" cannot be said here: it would sit eight lines
    /// above a step still badged Required, and a window that contradicts
    /// itself teaches somebody not to read it. So it says the one thing that
    /// makes the choice safe to make, which is that the tour is independent of
    /// the setup underneath it.
    public static let headlineWhenSetupIsUnfinished =
        "The tour does not need any of the setup below. Take a quick lap of the window, or jump straight in. It is under Help whenever you want it."

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
        [("first run headline", headlineWhenReady),
         ("first run headline before setup is finished", headlineWhenSetupIsUnfinished),
         ("first run tour button", tourButtonTitle),
         ("first run skip button", skipButtonTitle)]
    }
}
