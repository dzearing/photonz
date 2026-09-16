import Foundation
import PhotonzCore
import Testing

/// The one question a new person is asked, and the rules that keep it to one.
///
/// Every test here is a moment in a real first run, written as the state the
/// app is actually in at that moment: no permission yet, permission granted but
/// the app not restarted, restarted and working, and the launch after the
/// answer. The whole point of the type under test is that those moments are
/// decidable without a window, so they can be checked here rather than guessed
/// at in AppKit.
@Suite("First run offer")
struct FirstRunOfferTests {

    // MARK: A genuinely new person

    @Test func aBrandNewInstallSeesTheSetupWindow() {
        #expect(FirstRunOffer.presentsAtLaunch(setupCompleted: false, setupDismissed: false,
                                               answer: nil, tutorialsEnabled: true))
    }

    @Test func theChoiceDoesNotWaitForScreenRecording() {
        // Nothing granted, and the offer is still made. The tour teaches the
        // tool bar, the layers list and the settings beside them, none of which
        // needs the screen, so somebody who came to draw is shown round on the
        // first launch rather than never.
        #expect(FirstRunOffer.showsChoice(tutorialsEnabled: true,
                                          needsRelaunch: false, answer: nil))
    }

    @Test func theChoiceWaitsOutAPendingRelaunch() {
        // Granted this session: capture does not work until the app restarts,
        // so a tour started here would be killed by the restart.
        #expect(!FirstRunOffer.showsChoice(tutorialsEnabled: true,
                                           needsRelaunch: true, answer: nil))
    }

    @Test func theChoiceIsOfferedOnceEverythingWorks() {
        #expect(FirstRunOffer.showsChoice(tutorialsEnabled: true,
                                          needsRelaunch: false, answer: nil))
    }

    @Test func theChoiceIsNotThereWhenTutorialsAreTurnedOff() {
        #expect(!FirstRunOffer.showsChoice(tutorialsEnabled: false,
                                           needsRelaunch: false, answer: nil))
    }

    // MARK: An answer is an answer

    @Test func skippingIsRemembered() {
        #expect(!FirstRunOffer.presentsAtLaunch(setupCompleted: true, setupDismissed: true,
                                                answer: .skip, tutorialsEnabled: true))
        #expect(!FirstRunOffer.showsChoice(tutorialsEnabled: true,
                                           needsRelaunch: false, answer: .skip))
    }

    @Test func takingTheTourIsRemembered() {
        #expect(!FirstRunOffer.presentsAtLaunch(setupCompleted: true, setupDismissed: true,
                                                answer: .tour, tutorialsEnabled: true))
        #expect(!FirstRunOffer.showsChoice(tutorialsEnabled: true,
                                           needsRelaunch: false, answer: .tour))
    }

    @Test func anUnansweredOfferIsWhyTheWindowComesBackAfterTheRelaunch() {
        // Setup finished during the relaunch, but nobody was ever asked, so the
        // one launch where the app actually works is where the question lands.
        #expect(FirstRunOffer.presentsAtLaunch(setupCompleted: true, setupDismissed: true,
                                               answer: nil, tutorialsEnabled: true))
    }

    @Test func withTutorialsOffAFinishedSetupNeverPresentsAgain() {
        #expect(!FirstRunOffer.presentsAtLaunch(setupCompleted: true, setupDismissed: true,
                                                answer: nil, tutorialsEnabled: false))
    }

    // MARK: Closing the window is an answer too

    @Test func closingTheWindowWithTheChoiceUpCountsAsSkip() {
        // Otherwise somebody who reaches for the red button instead of either
        // button gets asked again on every launch for ever. It counts whether
        // or not the screen was ever granted, because the buttons were up
        // either way.
        #expect(FirstRunOffer.answerOnDismiss(tutorialsEnabled: true,
                                              screenRecordingGranted: false,
                                              needsRelaunch: false, answer: nil) == .skip)
        #expect(FirstRunOffer.answerOnDismiss(tutorialsEnabled: true,
                                              screenRecordingGranted: true,
                                              needsRelaunch: false, answer: nil) == .skip)
    }

    @Test func closingTheWindowWithARestartPendingAnswersNothing() {
        // The choice is not up in this state, so closing cannot be an answer
        // to a question nobody was asked.
        #expect(FirstRunOffer.answerOnDismiss(tutorialsEnabled: true,
                                              screenRecordingGranted: true,
                                              needsRelaunch: true, answer: nil) == nil)
    }

    @Test func finishingSetupWhereThereIsNoQuestionIsStillAnAnswer() {
        // Tutorials off, so nothing was asked, but this install has finished
        // its first run. Recording it is what stops the question arriving
        // months later out of nowhere.
        #expect(FirstRunOffer.answerOnDismiss(tutorialsEnabled: false,
                                              screenRecordingGranted: true,
                                              needsRelaunch: false, answer: nil) == .skip)
    }

    @Test func aReleaseThatNeverAsksNeverSpendsTheOfferItNeverMade() {
        // Current and Next ship in one binary over one set of settings. A brand
        // new person who tries Current first and closes this window without
        // granting anything was asked nothing and finished nothing, so the
        // offer is still theirs to be made the day they switch to Next.
        #expect(FirstRunOffer.answerOnDismiss(tutorialsEnabled: false,
                                              screenRecordingGranted: false,
                                              needsRelaunch: false, answer: nil) == nil)
    }

    @Test func closingTheWindowNeverOverwritesAnAnswerAlreadyGiven() {
        #expect(FirstRunOffer.answerOnDismiss(tutorialsEnabled: true,
                                              screenRecordingGranted: true,
                                              needsRelaunch: false, answer: .tour) == nil)
    }

    @Test func whereverTheChoiceIsOfferedClosingTheWindowAnswersIt() {
        // The half that must move together. Showing the buttons without
        // recording the dismissal is the every launch nagging they exist to
        // prevent, so every state that shows them records an answer.
        for tutorials in [false, true] {
            for granted in [false, true] {
                for relaunch in [false, true] {
                    guard FirstRunOffer.showsChoice(tutorialsEnabled: tutorials,
                                                    needsRelaunch: relaunch,
                                                    answer: nil) else { continue }
                    #expect(FirstRunOffer.answerOnDismiss(tutorialsEnabled: tutorials,
                                                          screenRecordingGranted: granted,
                                                          needsRelaunch: relaunch,
                                                          answer: nil) == .skip)
                }
            }
        }
    }

    // MARK: Saying no is an answer too

    @Test func closingTheWindowEndsTheFirstRunWhereverNoIsAnAnswer() {
        // Nothing else is asked of it. Whether the screen was granted, whether
        // the tour was offered, whether the person pressed a button or the red
        // one: the window was in front of them and they closed it.
        #expect(FirstRunOffer.dismissalEndsFirstRun(takesNoForAnAnswer: true,
                                                    needsRelaunch: false))
    }

    @Test func closingTheWindowWithARestartPendingDoesNotEndTheFirstRun() {
        // That close IS the restart: the window is owed one more appearance on
        // the other side of it, where the app finally works and the tour can be
        // offered. Ending the first run here would eat that appearance.
        #expect(!FirstRunOffer.dismissalEndsFirstRun(takesNoForAnAnswer: true,
                                                     needsRelaunch: true))
    }

    @Test func aReleaseThatDoesNotTakeNoForAnAnswerRecordsNothing() {
        for relaunch in [false, true] {
            #expect(!FirstRunOffer.dismissalEndsFirstRun(takesNoForAnAnswer: false,
                                                         needsRelaunch: relaunch))
        }
    }

    @Test func aDismissedSetupStopsPresentingEvenThoughItWasNeverFinished() {
        // The whole point. Nothing was granted, so the setup is not complete
        // and never will be, and the window still stops opening itself.
        #expect(!FirstRunOffer.presentsAtLaunch(setupCompleted: false, setupDismissed: true,
                                                answer: .skip, tutorialsEnabled: true))
        #expect(!FirstRunOffer.presentsAtLaunch(setupCompleted: false, setupDismissed: true,
                                                answer: nil, tutorialsEnabled: false))
    }

    @Test func aDismissedSetupStillOwesAnUnaskedTourQuestion() {
        // Dismissed in a release that never asks, then the person switches to
        // one that does. They were never offered the tour, so they are offered
        // it once, in the window they can close again straight away.
        #expect(FirstRunOffer.presentsAtLaunch(setupCompleted: false, setupDismissed: true,
                                               answer: nil, tutorialsEnabled: true))
    }

    @Test func aFirstRunThatGrantsTheScreenIsUnchanged() {
        // Acceptance for the person this never needed to change for: grant,
        // restart, get asked once, answer, and never see the window again.
        var install = Install(takesNoForAnAnswer: true)
        let first = install.launch(grantsDuringThisLaunch: true)
        #expect(first.presented)
        #expect(!first.offered)
        // The close that carries the restart records nothing, so the question
        // still lands on the launch where the app actually works.
        #expect(!install.setupDismissed)
        let second = install.launch()
        #expect(second.presented)
        #expect(second.offered)
        #expect(install.answer == .skip)
        #expect(!install.launch().presented)
        #expect(!install.launch().presented)
    }

    @Test func theScreenRecordingStepStopsSayingRequired() {
        // A step badged Required above a window that lets you leave is a
        // window arguing with itself. Where no is an answer, the badge says
        // what the permission is for instead of demanding it.
        #expect(FirstRunOffer.screenRecordingBadge(takesNoForAnAnswer: false) == "Required")
        let honest = FirstRunOffer.screenRecordingBadge(takesNoForAnAnswer: true)
        #expect(honest != "Required")
        #expect(honest.lowercased().contains("capture"))
    }

    @Test func theWayOutSaysWhatItDoes() {
        // "Not Now" promises a later that never comes once no is an answer.
        #expect(FirstRunOffer.closeButtonTitle(takesNoForAnAnswer: false) == "Not Now")
        #expect(FirstRunOffer.closeButtonTitle(takesNoForAnAnswer: true) != "Not Now")
    }

    @Test func theStepSaysTheRestOfTheAppWorksWithoutIt() {
        // The sentence that makes saying no safe to say. Without it, somebody
        // who only wants to draw has to guess whether closing this window
        // costs them the app.
        let plain = FirstRunOffer.screenRecordingBody(appName: "Photonz",
                                                      takesNoForAnAnswer: false)
        let honest = FirstRunOffer.screenRecordingBody(appName: "Photonz",
                                                       takesNoForAnAnswer: true)
        #expect(plain != honest)
        #expect(honest.lowercased().contains("without it"))
    }

    // MARK: The upgrade, and the new person the upgrade must not eat

    @Test func somebodyWhoFinishedSetupBeforeTutorialsExistedIsNeverAskedAgain() {
        #expect(FirstRunOffer.migratedAnswer(setupCompleted: true, answer: nil) == .skip)
    }

    @Test func afreshInstallIsStampedNothingOnItsVeryFirstLaunch() {
        // This is the whole reason the stamp happens ONCE, on the first launch
        // of a build that knows about tutorials. Run it again after the person
        // grants permission and restarts, and it would stamp them skip and eat
        // the offer they were owed.
        #expect(FirstRunOffer.migratedAnswer(setupCompleted: false, answer: nil) == nil)
    }

    @Test func anAnswerAlreadyOnFileIsNeverRewritten() {
        #expect(FirstRunOffer.migratedAnswer(setupCompleted: true, answer: .tour) == nil)
        #expect(FirstRunOffer.migratedAnswer(setupCompleted: true, answer: .skip) == nil)
    }

    // MARK: The whole sequence, launch by launch

    /// One tiny model of the two things that persist, driven exactly the way
    /// the controller drives them, so the sequence is checked and not assumed.
    private struct Install {
        var setupCompleted = false
        /// The person closed the window at least once. Written only by a
        /// release where a no sticks, and read only there, exactly as the
        /// controller does it.
        var setupDismissed = false
        var answer: FirstRunAnswer?
        var migrated = false
        var screenGrantedAtLaunch = false
        var systemGranted = false
        /// Whether this install is running a release that takes no for an
        /// answer. False is the behaviour that shipped before this existed.
        var takesNoForAnAnswer = false

        /// Everything one launch does, in the order the app does it.
        mutating func launch(grantsDuringThisLaunch: Bool = false,
                             closesTheWindow: Bool = true) -> (presented: Bool, offered: Bool) {
            if !migrated {
                if let stamp = FirstRunOffer.migratedAnswer(setupCompleted: setupCompleted,
                                                            answer: answer) {
                    answer = stamp
                }
                migrated = true
            }
            screenGrantedAtLaunch = systemGranted
            guard FirstRunOffer.presentsAtLaunch(setupCompleted: setupCompleted,
                                                 setupDismissed: takesNoForAnAnswer && setupDismissed,
                                                 answer: answer, tutorialsEnabled: true)
            else { return (false, false) }
            if grantsDuringThisLaunch { systemGranted = true }
            let needsRelaunch = systemGranted && !screenGrantedAtLaunch
            let offered = FirstRunOffer.showsChoice(tutorialsEnabled: true,
                                                    needsRelaunch: needsRelaunch,
                                                    answer: answer)
            if closesTheWindow {
                if systemGranted { setupCompleted = true }
                if FirstRunOffer.dismissalEndsFirstRun(takesNoForAnAnswer: takesNoForAnAnswer,
                                                       needsRelaunch: needsRelaunch) {
                    setupDismissed = true
                }
                if let stamp = FirstRunOffer.answerOnDismiss(tutorialsEnabled: true,
                                                             screenRecordingGranted: systemGranted,
                                                             needsRelaunch: needsRelaunch,
                                                             answer: answer) {
                    answer = stamp
                }
            }
            return (true, offered)
        }
    }

    @Test func theRealFirstRunAsksOnceAndThenLeavesYouAlone() {
        var install = Install()
        // Launch one: no permission. Setup window, no tour question yet.
        let first = install.launch(grantsDuringThisLaunch: true)
        #expect(first.presented)
        #expect(!first.offered)
        // Launch two, after the restart the grant needs. Now it works, so now
        // the question is asked.
        let second = install.launch()
        #expect(second.presented)
        #expect(second.offered)
        #expect(install.answer == .skip)
        // Launch three and every launch after it: nothing.
        #expect(!install.launch().presented)
        #expect(!install.launch().presented)
    }

    @Test func somebodyWhoNeverGrantsTheScreenIsStillAskedOnce() {
        // The person who came to build UI and has no interest in capturing
        // anything. They used to be the one person the app never showed round.
        var install = Install()
        let first = install.launch()
        #expect(first.presented)
        #expect(first.offered)
        // Closing the window answered it, so the question is over for good.
        #expect(install.answer == .skip)
        for _ in 0..<4 {
            #expect(!install.launch().offered)
        }
    }

    @Test func sayingNoToTheScreenIsRememberedForGood() {
        // The person who came to draw icons and will never capture anything.
        // They close the window once, and the app never opens it at them
        // again: not the next launch, not the one after, not ever. Turning
        // Screen Recording on later is still one click, from the menu bar.
        var install = Install(takesNoForAnAnswer: true)
        #expect(install.launch().presented)
        #expect(install.setupDismissed)
        for _ in 0..<5 {
            #expect(!install.launch().presented)
        }
    }

    @Test func beforeAnyOfThisTheWindowCameBackAtEveryLaunch() {
        // The behaviour that shipped, kept here as the thing being fixed and
        // as what a release without this still does. Five launches, nothing
        // granted, and the window is in the way on every one of them.
        var install = Install()
        for _ in 0..<5 {
            #expect(install.launch().presented)
        }
    }

    @Test func anExistingUserUpgradingSeesNothingAtAll() {
        // Everything this install did happened before tutorials existed.
        var install = Install(setupCompleted: true, systemGranted: true)
        #expect(!install.launch().presented)
        #expect(install.answer == .skip)
        #expect(!install.launch().presented)
    }

    // MARK: The words

    @Test func theHeadlineNeverClaimsMoreThanIsTrue() {
        // The offer is now made with the Screen Recording card still red, so
        // the sentence above it cannot be the one that says everything works.
        let waiting = FirstRunOffer.headline(screenRecordingGranted: false)
        let ready = FirstRunOffer.headline(screenRecordingGranted: true)
        #expect(waiting != ready)
        #expect(!waiting.contains("Everything is ready"))
        // Both still say what the two buttons are for, and that the tour keeps.
        for text in [waiting, ready] {
            #expect(text.contains(FirstRunOffer.tourButtonTitle.lowercased())
                    || text.contains("lap of the window"))
            #expect(text.contains("Help"))
        }
    }

    @Test func everyWordOfTheOfferPassesTheCopyRules() {
        for (label, text) in FirstRunOffer.allCopy {
            #expect(TutorialCopyRules.problems(in: text, label: label).isEmpty)
        }
    }
}
