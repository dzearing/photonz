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

    @Test func theChoiceWaitsUntilScreenRecordingIsSorted() {
        // Nothing granted: the window is about permissions and says only that.
        #expect(!FirstRunOffer.showsChoice(tutorialsEnabled: true,
                                           screenRecordingGranted: false,
                                           needsRelaunch: false, answer: nil))
    }

    @Test func theChoiceWaitsOutAPendingRelaunch() {
        // Granted this session: capture does not work until the app restarts,
        // so a tour started here would be killed by the restart.
        #expect(!FirstRunOffer.showsChoice(tutorialsEnabled: true,
                                           screenRecordingGranted: true,
                                           needsRelaunch: true, answer: nil))
    }

    @Test func theChoiceIsOfferedOnceEverythingWorks() {
        #expect(FirstRunOffer.showsChoice(tutorialsEnabled: true,
                                          screenRecordingGranted: true,
                                          needsRelaunch: false, answer: nil))
    }

    @Test func theChoiceIsNotThereWhenTutorialsAreTurnedOff() {
        #expect(!FirstRunOffer.showsChoice(tutorialsEnabled: false,
                                           screenRecordingGranted: true,
                                           needsRelaunch: false, answer: nil))
    }

    // MARK: An answer is an answer

    @Test func skippingIsRemembered() {
        #expect(!FirstRunOffer.presentsAtLaunch(setupCompleted: true, answer: .skip,
                                                tutorialsEnabled: true))
        #expect(!FirstRunOffer.showsChoice(tutorialsEnabled: true,
                                           screenRecordingGranted: true,
                                           needsRelaunch: false, answer: .skip))
    }

    @Test func takingTheTourIsRemembered() {
        #expect(!FirstRunOffer.presentsAtLaunch(setupCompleted: true, answer: .tour,
                                                tutorialsEnabled: true))
        #expect(!FirstRunOffer.showsChoice(tutorialsEnabled: true,
                                           screenRecordingGranted: true,
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

    @Test func closingTheWindowWithEverythingWorkingCountsAsSkip() {
        // Otherwise somebody who reaches for the red button instead of either
        // button gets asked again on every launch for ever.
        #expect(FirstRunOffer.answerOnDismiss(screenRecordingGranted: true,
                                              needsRelaunch: false, answer: nil) == .skip)
    }

    @Test func closingTheWindowBeforePermissionAnswersNothing() {
        #expect(FirstRunOffer.answerOnDismiss(screenRecordingGranted: false,
                                              needsRelaunch: false, answer: nil) == nil)
        #expect(FirstRunOffer.answerOnDismiss(screenRecordingGranted: true,
                                              needsRelaunch: true, answer: nil) == nil)
    }

    @Test func closingTheWindowNeverOverwritesAnAnswerAlreadyGiven() {
        #expect(FirstRunOffer.answerOnDismiss(screenRecordingGranted: true,
                                              needsRelaunch: false, answer: .tour) == nil)
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
                                                    screenRecordingGranted: systemGranted,
                                                    needsRelaunch: needsRelaunch,
                                                    answer: answer)
            if closesTheWindow {
                if systemGranted { setupCompleted = true }
                if let stamp = FirstRunOffer.answerOnDismiss(screenRecordingGranted: systemGranted,
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

    @Test func somebodyWhoIgnoresPermissionIsNeverAskedAboutATour() {
        var install = Install()
        for _ in 0..<5 {
            let launch = install.launch()
            #expect(launch.presented)
            #expect(!launch.offered)
        }
        #expect(install.answer == nil)
    }

    @Test func anExistingUserUpgradingSeesNothingAtAll() {
        // Everything this install did happened before tutorials existed.
        var install = Install(setupCompleted: true, systemGranted: true)
        #expect(!install.launch().presented)
        #expect(install.answer == .skip)
        #expect(!install.launch().presented)
    }

    // MARK: The words

    @Test func everyWordOfTheOfferPassesTheCopyRules() {
        for (label, text) in FirstRunOffer.allCopy {
            #expect(TutorialCopyRules.problems(in: text, label: label).isEmpty)
        }
    }
}
