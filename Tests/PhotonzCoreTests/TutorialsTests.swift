import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The walkthrough framework's data model: a guide is a value, a run is a value,
/// and what a person has finished is a value. Nothing here draws anything.
@Suite("Tutorials")
struct TutorialsTests {

    // MARK: A guide is data

    @Test func aGuideSurvivesBeingWrittenDownAndReadBack() throws {
        let guide = TutorialGuides.takeTheTour
        let data = try JSONEncoder().encode(guide)
        let back = try JSONDecoder().decode(TutorialGuide.self, from: data)
        #expect(back == guide)
        #expect(back.steps.count == guide.steps.count)
        #expect(back.steps[1].advance == .waitsFor(.toolPicked(.measure)))
    }

    @Test func everyGuideSaysWhichTrackItIsOnHowLongItTakesAndWhatItsStepsPointAt() {
        for guide in TutorialCatalog.guides {
            #expect(!guide.title.isEmpty)
            #expect(guide.minutes > 0)
            #expect(!guide.steps.isEmpty)
            for step in guide.steps {
                #expect(!step.anchor.name.isEmpty)
                #expect(!step.title.isEmpty)
                #expect(!step.body.isEmpty)
            }
        }
    }

    @Test func theCatalogueOnlyShowsTracksThatHaveSomethingOnThem() {
        let tracks = TutorialCatalog.populatedTracks
        #expect(tracks.contains(.basics))
        for track in tracks {
            #expect(!TutorialCatalog.guides(in: track).isEmpty)
        }
        // In track order, never in catalogue order.
        #expect(tracks == tracks.sorted { $0.order < $1.order })
    }

    // MARK: A guide that points at nothing fails here, not in front of a person

    @Test func theShippingCatalogueIsClean() {
        #expect(TutorialCatalogCheck.problems() == [])
    }

    @Test func anAnchorNothingPromisesIsCaught() {
        let guide = TutorialGuide(
            id: "broken", track: .basics, title: "Broken", summary: "A guide that lies.",
            minutes: 1, sample: nil,
            steps: [TutorialStep(id: "one", anchor: TutorialAnchor("tool.teleport"),
                                 title: "Press it", body: "Press the thing that is not there.")])
        let problems = TutorialCatalogCheck.problems(in: [guide])
        #expect(problems.contains { $0.contains("tool.teleport") })
        #expect(problems.contains { $0.contains("broken") && $0.contains("one") })
    }

    @Test func twoStepsWithTheSameNameAreCaught() {
        let step = TutorialStep(id: "same", anchor: .canvas, title: "Look", body: "Look here.")
        let guide = TutorialGuide(id: "dupes", track: .basics, title: "Dupes",
                                  summary: "Two of the same.", minutes: 1, sample: nil,
                                  steps: [step, step])
        #expect(TutorialCatalogCheck.problems(in: [guide]).contains { $0.contains("two steps called same") })
    }

    @Test func anAnchorIsNamedOffTheModelNotOffTheWords() {
        // Rewording the Measure button cannot reach this name: it is built from
        // the tool itself.
        #expect(TutorialAnchor.tool(.measure) == TutorialAnchor("tool.measure"))
        #expect(TutorialAnchor.panelSection("layers") == TutorialAnchor("panel.layers"))
        #expect(TutorialAnchor.all.contains(TutorialAnchor.tool(.select)))
        #expect(TutorialAnchor.all.contains(TutorialAnchor.panelSection("geometry")))
        #expect(TutorialAnchor.panelSection("layers").panelSectionID == "layers")
        #expect(TutorialAnchor.tool(.measure).panelSectionID == nil)
    }

    // MARK: The copy rules

    @Test func guideCopyObeysTheRepoCopyRules() {
        for guide in TutorialCatalog.guides {
            #expect(TutorialCopyRules.problems(in: guide) == [])
        }
    }

    @Test func aDashStandingInForPunctuationIsCaught() {
        let problems = TutorialCopyRules.problems(in: "Press I — the Measure tool.", label: "body")
        #expect(problems.contains { $0.contains("dash") })
    }

    @Test func copyThatGivesAwayTheToolingIsCaught() {
        let problems = TutorialCopyRules.problems(in: "Claude wrote this step.", label: "body")
        #expect(problems.contains { $0.contains("claude") })
    }

    @Test func copyTooLongToReadOffACalloutIsCaught() {
        let wall = String(repeating: "a sentence that keeps going and going. ", count: 8)
        #expect(TutorialCopyRules.problems(in: wall, label: "body").contains { $0.contains("too long") })
    }

    // MARK: Running one

    @Test func nextWalksForwardAndBackWalksBack() {
        var run = TutorialRun(guide: TutorialGuides.takeTheTour)
        #expect(run.number == 1)
        #expect(!run.canGoBack)
        let backedUpFromTheStart = run.back()
        #expect(backedUpFromTheStart == false)
        let movedOn = run.advance()
        #expect(movedOn)
        #expect(run.number == 2)
        #expect(run.canGoBack)
        let wentBack = run.back()
        #expect(wentBack)
        #expect(run.number == 1)
    }

    @Test func theLastStepFinishesRatherThanRunningOffTheEnd() {
        var run = TutorialRun(guide: TutorialGuides.takeTheTour,
                              startingAt: TutorialGuides.takeTheTour.steps.count - 1)
        #expect(run.isLastStep)
        #expect(run.buttonTitle == "Done")
        let ranOffTheEnd = run.advance()
        #expect(ranOffTheEnd == false)
    }

    @Test func aWaitingStepNeverOffersNext() {
        // Offering Next on "pick the Measure tool" would be a way to claim you
        // did something you did not. It offers to skip the step instead, so
        // nobody is ever stuck.
        var run = TutorialRun(guide: TutorialGuides.takeTheTour)
        while !run.step.waits && !run.isLastStep { run.advance() }
        #expect(run.step.waits)
        #expect(run.buttonTitle == "Skip This Step")
    }

    @Test func aWaitingStepMovesOnWhenThePersonDoesTheThing() {
        var run = TutorialRun(guide: TutorialGuides.takeTheTour)
        run.advance() // the Measure step
        #expect(run.step.id == "pick-measure")
        #expect(!run.isSatisfied(by: .toolPicked(.text)))
        #expect(!run.isSatisfied(by: .layerSelected))
        #expect(run.isSatisfied(by: .toolPicked(.measure)))
    }

    @Test func aStepThatIsShowingYouSomethingIsNotWaitingOnAnything() {
        let run = TutorialRun(guide: TutorialGuides.takeTheTour)
        #expect(!run.step.waits)
        #expect(run.buttonTitle == "Next")
        #expect(!run.isSatisfied(by: .toolPicked(.measure)))
    }

    @Test func startingPastTheEndLandsOnTheLastStepRatherThanCrashing() {
        let run = TutorialRun(guide: TutorialGuides.takeTheTour, startingAt: 99)
        #expect(run.isLastStep)
    }

    // MARK: Quitting part way loses nothing

    @Test func whereYouStoppedIsRememberedAndResumed() {
        var progress = TutorialProgress()
        let guide = TutorialGuides.takeTheTour
        #expect(progress.startIndex(for: guide) == 0)
        #expect(!progress.isResumable(guide))
        progress.record(guide: guide.id, step: 3)
        #expect(progress.startIndex(for: guide) == 3)
        #expect(progress.isResumable(guide))
    }

    @Test func aGuideThatMovedOrShrankCannotStrandYouOnAStepThatIsGone() {
        var progress = TutorialProgress()
        let guide = TutorialGuides.takeTheTour
        progress.record(guide: guide.id, step: 40)
        #expect(progress.startIndex(for: guide) == guide.steps.count - 1)
    }

    @Test func finishingAGuideClearsThePlaceAndMarksItDone() {
        var progress = TutorialProgress()
        let guide = TutorialGuides.takeTheTour
        progress.record(guide: guide.id, step: 2)
        progress.complete(guide.id)
        #expect(progress.isCompleted(guide.id))
        #expect(progress.startIndex(for: guide) == 0)
        #expect(!progress.isResumable(guide))
    }

    @Test func startingOverForgetsWhereYouWere() {
        var progress = TutorialProgress()
        progress.record(guide: "take-the-tour", step: 2)
        progress.restart("take-the-tour")
        #expect(progress.startIndex(for: TutorialGuides.takeTheTour) == 0)
    }

    @Test func progressSurvivesBeingWrittenDownAndReadBack() throws {
        var progress = TutorialProgress()
        progress.record(guide: "take-the-tour", step: 2)
        progress.complete("something-else")
        let data = try JSONEncoder().encode(progress)
        let back = try JSONDecoder().decode(TutorialProgress.self, from: data)
        #expect(back == progress)
    }

    // MARK: The sample a guide opens for itself

    @Test func theSampleScreenIsSomethingWithLayersToPick() {
        let layers = TutorialSampleScreen.layers(for: .starterScreen)
        #expect(layers.count >= 3)
        #expect(Set(layers.map(\.name)).count == layers.count)
        for layer in layers {
            #expect(layer.frame.width > 0)
            #expect(layer.frame.height > 0)
            // Inside the canvas it is drawn on, so nothing is off the picture.
            #expect(layer.frame.maxX <= TutorialSampleScreen.canvasSize.width)
            #expect(layer.frame.maxY <= TutorialSampleScreen.canvasSize.height)
        }
    }

    // MARK: A prepare action may only reveal

    @Test func preparingAStepCanOnlyBringSomethingOnScreen() {
        // The closed list is the guard rail: nothing here can pick a tool,
        // select a layer, or otherwise do the thing a step is asking for.
        #expect(TutorialPrep.allCases == [.showPanel, .showLibrary, .revealTarget])
        for step in TutorialGuides.takeTheTour.steps {
            for prep in step.prepare {
                #expect(TutorialPrep.allCases.contains(prep))
            }
        }
    }
}
