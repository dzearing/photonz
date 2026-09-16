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
        #expect(FirstRunOffer.presentsAtLaunch(setupCompleted: false, answer: nil,
                                               tutorialsEnabled: true))
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
        #expect(!FirstRunOffer.presentsAtLaunch(setupCompleted: true, answer: .skip,
                                                tutorialsEnabled: true))
        #expect(!FirstRunOffer.showsChoice(tutorialsEnabled: true,
                                           needsRelaunch: false, answer: .skip))
    }

    @Test func takingTheTourIsRemembered() {
        #expect(!FirstRunOffer.presentsAtLaunch(setupCompleted: true, answer: .tour,
                                                tutorialsEnabled: true))
        #expect(!FirstRunOffer.showsChoice(tutorialsEnabled: true,
                                           needsRelaunch: false, answer: .tour))
    }

    @Test func anUnansweredOfferIsWhyTheWindowComesBackAfterTheRelaunch() {
        // Setup finished during the relaunch, but nobody was ever asked, so the
        // one launch where the app actually works is where the question lands.
        #expect(FirstRunOffer.presentsAtLaunch(setupCompleted: true, answer: nil,
                                               tutorialsEnabled: true))
    }

    @Test func withTutorialsOffAFinishedSetupNeverPresentsAgain() {
        #expect(!FirstRunOffer.presentsAtLaunch(setupCompleted: true, answer: nil,
                                                tutorialsEnabled: false))
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
        var answer: FirstRunAnswer?
        var migrated = false
        var screenGrantedAtLaunch = false
        var systemGranted = false

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
                                                 answer: answer, tutorialsEnabled: true)
            else { return (false, false) }
            if grantsDuringThisLaunch { systemGranted = true }
            let needsRelaunch = systemGranted && !screenGrantedAtLaunch
            let offered = FirstRunOffer.showsChoice(tutorialsEnabled: true,
                                                    needsRelaunch: needsRelaunch,
                                                    answer: answer)
            if closesTheWindow {
                if systemGranted { setupCompleted = true }
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

    @Test func neverGrantingStillLeavesTheSetupWindowComingBack() {
        // Deliberately recorded, because it is the part this does NOT fix.
        // The tour question is answered once and then over, but the setup
        // window itself still presents at every launch while Screen Recording
        // is unfinished, which is a separate question about what Photonz owes
        // somebody who never gives it the screen.
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
