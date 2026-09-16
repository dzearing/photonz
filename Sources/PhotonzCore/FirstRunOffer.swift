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
//  * CLOSING the window is also a no to the SETUP, and a no that sticks. The
//    window used to come back at every launch until Screen Recording was
//    switched on, so the only way to stop it was to do the thing you did not
//    want to do. Photonz is now also where you draw an icon and build a screen,
//    neither of which touches the screen, so the person who never grants it is
//    an ordinary person and not an unfinished one (`dismissalEndsFirstRun`).
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
    /// A first run that is neither finished nor waved away presents it, exactly
    /// as it always has. On top of that, a first run that IS over but was never
    /// asked about the tour presents it once, which is how somebody who granted
    /// permission and restarted gets the question on the first launch where the
    /// app actually works.
    ///
    /// The two ways a first run can be over are not the same thing, and both
    /// are needed. `setupCompleted` is the screen granted; `setupDismissed` is
    /// the person having closed this window at least once without granting it,
    /// which is a no, and a no the app is not allowed to keep re-asking. Before
    /// that second one existed, somebody who only wanted to draw icons got this
    /// window floating over everything at every launch for ever, because the
    /// only way to make it stop was to do the thing they did not want to do.
    public static func presentsAtLaunch(setupCompleted: Bool, setupDismissed: Bool,
                                        answer: FirstRunAnswer?,
                                        tutorialsEnabled: Bool) -> Bool {
        if !setupCompleted && !setupDismissed { return true }
        guard tutorialsEnabled else { return false }
        return answer == nil
    }

    /// Whether closing the setup window means this install has had its first
    /// run, so the app stops opening the window by itself.
    ///
    /// It asks for nothing except a restart not being pending, because every
    /// other reading of a close is the app deciding it knows better than the
    /// person who just closed it. The pending restart is genuinely different:
    /// that close IS the restart (the window's own button does it), the app
    /// does not work yet, and the window is owed one more appearance on the
    /// other side where it can finally offer the tour.
    ///
    /// `takesNoForAnAnswer` is the release switch. A release without it writes
    /// nothing and reads nothing, so its first run behaves exactly as it did.
    public static func dismissalEndsFirstRun(takesNoForAnAnswer: Bool,
                                             needsRelaunch: Bool) -> Bool {
        takesNoForAnAnswer && !needsRelaunch
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

    /// What the Screen Recording step is badged.
    ///
    /// "Required" was true when Photonz was only a way to photograph your
    /// screen. It is a false statement in an app you can also draw an icon in,
    /// build a screen in and edit a picture in, and it sat above a window that
    /// now lets you leave, so the window was arguing with itself. The honest
    /// badge says what the permission is FOR and leaves the wanting of it to
    /// the person.
    public static func screenRecordingBadge(takesNoForAnAnswer: Bool) -> String {
        takesNoForAnAnswer ? screenRecordingBadgeText : "Required"
    }

    /// See `screenRecordingBadge`.
    public static let screenRecordingBadgeText = "Needed to capture"

    /// What the Screen Recording step says while it is still switched off.
    ///
    /// Where no is an answer it carries one extra sentence, and that sentence
    /// is the whole point: somebody who only wants to draw should not have to
    /// guess whether closing this window costs them the app.
    public static func screenRecordingBody(appName: String,
                                           takesNoForAnAnswer: Bool) -> String {
        let opening = "Lets \(appName) take screenshots and record video."
        let rest = "Click below, then turn on \(appName). This window updates by itself."
        guard takesNoForAnAnswer else { return opening + " " + rest }
        return opening + " Everything else in \(appName) works without it. " + rest
    }

    /// The way out of the setup window when there is no tour question in it.
    ///
    /// "Not Now" promises a later. Once closing the window is a remembered no,
    /// there is no later to promise, and a button that says there is teaches
    /// somebody not to trust the window.
    public static func closeButtonTitle(takesNoForAnAnswer: Bool) -> String {
        takesNoForAnAnswer ? "Done" : "Not Now"
    }

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
         ("first run skip button", skipButtonTitle),
         ("screen recording badge", screenRecordingBadgeText),
         ("screen recording step", screenRecordingBody(appName: "Photonz",
                                                       takesNoForAnAnswer: true)),
         ("first run close button", closeButtonTitle(takesNoForAnAnswer: true))]
    }
}
