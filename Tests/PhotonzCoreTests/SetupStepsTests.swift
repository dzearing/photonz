import Foundation
import PhotonzCore
import Testing

/// The setup window as a list of steps, each shown only while it is still
/// needed and never seen.
///
/// Every test is a Mac in a real state: brand new, finished the old one page
/// setup, everything done, a step skipped last time. The rules are pure so the
/// order of a real first run can be checked here instead of in a window.
@Suite("Setup steps")
struct SetupStepsTests {

    private let brandNew = SetupFacts(screenRecordingGranted: false, microphoneAnswered: false,
                                      screenshotKeysFree: false, agentsToSetUp: true)
    private let allDone = SetupFacts(screenRecordingGranted: true, microphoneAnswered: true,
                                     screenshotKeysFree: true, agentsToSetUp: false)

    // MARK: Which steps show

    @Test func aBrandNewMacSeesEveryStepInOrder() {
        #expect(SetupFlow.steps(facts: brandNew, seen: []) == [.screenRecording, .microphone, .screenshotKeys, .agents])
    }

    @Test func aMacWithEverythingDoneSeesNoStep() {
        #expect(SetupFlow.steps(facts: allDone, seen: []).isEmpty)
        #expect(!SetupFlow.presentsAtLaunch(steps: [], tourPending: false))
    }

    @Test func aStepSeenBeforeIsLeftOutEvenWhileStillNeeded() {
        #expect(SetupFlow.steps(facts: brandNew, seen: [.microphone, .agents]) == [.screenRecording, .screenshotKeys])
    }

    @Test func aStepNoLongerNeededIsLeftOut() {
        var facts = brandNew
        facts.screenRecordingGranted = true
        facts.agentsToSetUp = false
        #expect(SetupFlow.steps(facts: facts, seen: []) == [.microphone, .screenshotKeys])
    }

    @Test func aMicrophoneAnswerEitherWayIsNotAskedAgain() {
        // Denied in macOS is an answer too; the menu bar menu is the way back.
        var facts = allDone
        facts.microphoneAnswered = true
        #expect(!SetupFlow.isNeeded(.microphone, facts: facts))
        facts.microphoneAnswered = false
        #expect(SetupFlow.isNeeded(.microphone, facts: facts))
    }

    @Test func theTourAloneStillOpensTheWindow() {
        #expect(SetupFlow.presentsAtLaunch(steps: [], tourPending: true))
        #expect(SetupFlow.presentsAtLaunch(steps: [.agents], tourPending: false))
    }

    // MARK: The old one page setup

    @Test func aMacThatFinishedTheOldSetupSeesOnlyTheAgentsStep() {
        let seen = SetupFlow.migratedSeen(seen: [], setupCompleted: true, setupDismissed: false)
        #expect(seen == SetupStep.permissionSteps)
        #expect(SetupFlow.steps(facts: brandNew, seen: seen) == [.agents])
    }

    @Test func waivingTheOldSetupAwayCountsAsFinishingIt() {
        let seen = SetupFlow.migratedSeen(seen: [], setupCompleted: false, setupDismissed: true)
        #expect(SetupFlow.steps(facts: brandNew, seen: seen) == [.agents])
    }

    @Test func aMacThatNeverFinishedTheOldSetupKeepsEveryStep() {
        #expect(SetupFlow.migratedSeen(seen: [], setupCompleted: false, setupDismissed: false).isEmpty)
    }

    @Test func migratingKeepsWhatWasAlreadySeen() {
        let seen = SetupFlow.migratedSeen(seen: [.agents], setupCompleted: true, setupDismissed: false)
        #expect(seen == SetupStep.permissionSteps.union([.agents]))
    }

    // MARK: Seen is stored per step

    @Test func seenRoundTripsAndForgetsStepsItDoesNotKnow() {
        let stored = SetupFlow.encode([.agents, .microphone])
        #expect(stored == ["agents", "microphone"])
        #expect(SetupFlow.decode(stored + ["a-step-from-a-later-version"]) == [.agents, .microphone])
    }

    @Test func aStepAddedLaterShowsOnceToSomebodyWhoFinishedSetup() {
        // Somebody who saw every step there was: a new step is not in their
        // seen list, so it shows, and nothing they saw comes back.
        let seenBefore: Set<SetupStep> = SetupStep.permissionSteps
        #expect(SetupFlow.steps(facts: brandNew, seen: seenBefore) == [.agents])
        #expect(SetupFlow.steps(facts: brandNew, seen: seenBefore.union([.agents])).isEmpty)
    }

    // MARK: A run through the window

    @Test func theCounterShowsOnlyWhenMoreThanOneStepIsInTheRun() {
        let one = SetupRun(pages: [.agents], endsWithTour: false)
        #expect(one.counter == nil)
        let three = SetupRun(pages: [.microphone, .screenshotKeys, .agents], endsWithTour: true)
        #expect(three.counter == "1 of 3")
    }

    @Test func skippingMarksTheStepSeenAndMovesOn() {
        var run = SetupRun(pages: [.microphone, .screenshotKeys, .agents], endsWithTour: false)
        #expect(run.current == .microphone)
        run.advance(facts: brandNew)
        #expect(run.current == .screenshotKeys)
        #expect(run.counter == "2 of 3")
        #expect(run.seen == [.microphone])
    }

    @Test func aStepThatGotDoneMeanwhileIsPassedOver() {
        // Keys freed in System Settings while the microphone page was up.
        var run = SetupRun(pages: [.microphone, .screenshotKeys, .agents], endsWithTour: false)
        var facts = brandNew
        facts.screenshotKeysFree = true
        run.advance(facts: facts)
        #expect(run.current == .agents)
    }

    @Test func theLastStepEndsTheRunOrHandsOverToTheTour() {
        var plain = SetupRun(pages: [.agents], endsWithTour: false)
        #expect(plain.isLastPage)
        plain.advance(facts: brandNew)
        #expect(plain.isFinished)
        #expect(plain.current == nil)

        var toured = SetupRun(pages: [.agents], endsWithTour: true)
        #expect(!toured.isLastPage)
        toured.advance(facts: brandNew)
        #expect(!toured.isFinished)
        #expect(toured.isOnTour)
        #expect(toured.counter == nil)
        #expect(toured.isLastPage)
    }

    @Test func aRunOfOnlyTheTourStartsOnTheTour() {
        let run = SetupRun(pages: [], endsWithTour: true)
        #expect(run.isOnTour)
        #expect(run.isLastPage)
    }

    @Test func aStepIsSeenTheMomentItIsOnScreen() {
        var run = SetupRun(pages: [.screenRecording, .microphone, .agents], endsWithTour: true)
        #expect(run.shown == [.screenRecording])
        run.advance(facts: brandNew)
        #expect(run.shown == [.screenRecording, .microphone])
        run.advance(facts: brandNew)
        run.advance(facts: brandNew)
        #expect(run.isOnTour)
        #expect(run.shown == [.screenRecording, .microphone, .agents])
    }

    @Test func closingTheWindowCountsEveryStepInTheRunAsSeen() {
        var run = SetupRun(pages: [.screenRecording, .microphone, .agents], endsWithTour: false)
        run.advance(facts: brandNew)
        #expect(run.seenOnClose(needsRelaunch: false) == [.screenRecording, .microphone, .agents])
    }

    @Test func closingForARelaunchKeepsTheStepsNotYetReached() {
        // The close IS the restart, and the steps after it are owed a showing
        // on the other side.
        let run = SetupRun(pages: [.screenRecording, .microphone, .agents], endsWithTour: false)
        #expect(run.seenOnClose(needsRelaunch: true) == [.screenRecording])
    }

    @Test func reopeningFromTheMenuShowsWhatIsStillNeededWhateverWasSeen() {
        var facts = allDone
        facts.agentsToSetUp = true
        #expect(SetupFlow.reopenedSteps(facts: facts, agentToolOnThisMac: true) == [.agents])
    }

    @Test func reopeningWithNothingLeftShowsEveryStepAsDone() {
        #expect(SetupFlow.reopenedSteps(facts: allDone, agentToolOnThisMac: true)
                == [.screenRecording, .microphone, .screenshotKeys, .agents])
        #expect(SetupFlow.reopenedSteps(facts: allDone, agentToolOnThisMac: false)
                == [.screenRecording, .microphone, .screenshotKeys])
    }

    @Test func aReopenedRunDoesNotPassOverDoneSteps() {
        var run = SetupRun(pages: [.screenRecording, .microphone], endsWithTour: false, passesOverDone: false)
        run.advance(facts: allDone)
        #expect(run.current == .microphone)
    }

    // MARK: Words

    @Test func everyWordPassesTheCopyRules() {
        // The one vendor name allowed is the tool's own name, so it is taken
        // out before the rules read the rest.
        for (label, text) in SetupFlow.allCopy {
            let rest = text.replacingOccurrences(of: "Claude Code", with: "the tool")
            #expect(TutorialCopyRules.problems(in: rest, label: label).isEmpty, "\(label): \(text)")
            #expect(!text.contains("\u{2014}"), "\(label) has an em dash")
        }
    }

    @Test func theAgentsStepNamesBothToolsAndSaysAskNeedsNoSetup() {
        let words = SetupFlow.body(.agents)
        #expect(words.contains("Claude Code"))
        #expect(words.contains("Copilot"))
        #expect(SetupFlow.agentsAskLine.contains("Ask"))
    }
}
