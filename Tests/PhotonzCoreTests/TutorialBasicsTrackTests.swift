import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The Basics track: the four guides a brand new person needs, in the order
/// they need them. Everything here is a fact about the DATA, because that is
/// all a guide is. That each anchor really turns up in a live window is proved
/// by the walks, not here.
@Suite("Tutorials: the Basics track")
struct TutorialBasicsTrackTests {

    private var basics: [TutorialGuide] { TutorialCatalog.guides(in: .basics) }

    // MARK: The track itself

    @Test func theTrackWalksSomebodyFromNothingToAFinishedHandoff() {
        let ids = basics.map(\.id)
        #expect(ids == ["take-the-tour", "first-capture", "mark-it-up",
                        "layers-and-undo", "save-export-copy"])
    }

    @Test func everyGuideInTheTrackIsShortEnoughToFinishInOneSitting() {
        for guide in basics {
            // The claim on the card, and the thing the claim is made of. A
            // guide that says two minutes and holds twelve steps is a guide
            // nobody finishes.
            #expect(guide.minutes <= 3, "\(guide.id) claims \(guide.minutes) minutes")
            #expect(guide.steps.count <= 8, "\(guide.id) has \(guide.steps.count) steps")
            #expect(guide.steps.count >= 3, "\(guide.id) has \(guide.steps.count) steps")
        }
    }

    @Test func nothingInTheTrackTeachesOverYourOwnPicture() {
        // Every Basics guide points at a canvas or a panel section, and a
        // person new enough to be here may have nothing open at all. So each
        // one brings a document of its own.
        for guide in basics {
            #expect(guide.sample != nil, "\(guide.id) would teach over whatever you had open")
        }
    }

    @Test func aStepThatPointsIntoThePanelOpensThePanelFirst() {
        for guide in basics {
            for step in guide.steps where step.anchor.panelSectionID != nil {
                #expect(step.prepare.contains(.showPanel),
                        "\(guide.id)/\(step.id) points into the panel without opening it")
                #expect(step.prepare.contains(.revealTarget),
                        "\(guide.id)/\(step.id) points into the panel without scrolling to it")
            }
        }
    }

    // MARK: What the copy is allowed to say

    @Test func theCopyNamesKeysRatherThanMenuRows() {
        // A menu row moves under a feature flag and a key does not: the same
        // press is Copy Image with `next-copy-picks-your-layer` off and Copy
        // Merged with it on, and both put the whole picture on the clipboard.
        // So a guide says the key.
        for guide in basics {
            for step in guide.steps {
                #expect(!step.body.contains("▸"),
                        "\(guide.id)/\(step.id) names a menu row, which can move under a flag")
                #expect(!step.body.contains(" menu"),
                        "\(guide.id)/\(step.id) sends somebody to a menu instead of a key")
            }
        }
    }

    @Test func theWholeTrackPassesTheCopyRules() {
        for guide in basics {
            #expect(TutorialCopyRules.problems(in: guide) == [], "\(guide.id)")
        }
    }

    // MARK: What each guide is for

    @Test func theCaptureGuideTeachesEveryWayInAndAsksForNoneOfThem() throws {
        let guide = try #require(TutorialCatalog.guide(id: "first-capture"))
        // It opens an empty window on purpose: the three ways in are the rows
        // of the card that only exists with nothing open.
        #expect(guide.sample == .emptyWindow)
        #expect(TutorialSampleScreen.layers(for: .emptyWindow).isEmpty)
        let anchors = guide.steps.map(\.anchor.name)
        #expect(anchors.contains("start.capture"))
        #expect(anchors.contains("start.open"))
        #expect(anchors.contains("start.paste"))
        // Nothing waits. A real capture opens a window of its own and would
        // leave the guide behind in this one, so the guide teaches the key and
        // lets the person use it when they are ready.
        #expect(guide.steps.allSatisfy { !$0.waits })
    }

    @Test func theMarkUpGuideMakesYouDrawSomethingAndHandItOver() throws {
        let guide = try #require(TutorialCatalog.guide(id: "mark-it-up"))
        let waits = guide.steps.compactMap(\.advance.trigger)
        #expect(waits.contains(.toolPicked(.arrow)))
        #expect(waits.contains(.toolPicked(.text)))
        #expect(waits.contains(.editMade))
        #expect(waits.contains(.pictureCopied))
    }

    @Test func theLayersGuideMakesYouUndoSomethingYouReallyDid() throws {
        let guide = try #require(TutorialCatalog.guide(id: "layers-and-undo"))
        let waiting = guide.steps.filter(\.waits)
        let order = waiting.compactMap(\.advance.trigger)
        #expect(order.contains(.layerSelected))
        // The edit comes before the undo. Undo with an empty stack does
        // nothing, and a step waiting on nothing is a step nobody can finish.
        let edit = try #require(order.firstIndex(of: .editMade))
        let undo = try #require(order.firstIndex(of: .undone))
        #expect(edit < undo)
    }

    @Test func theWayOutGuideEndsOnTheThingSavingActuallyKeeps() throws {
        let guide = try #require(TutorialCatalog.guide(id: "save-export-copy"))
        #expect(guide.steps.last?.anchor == .panelSection("layers"))
        #expect(guide.steps.contains { $0.advance.trigger == .pictureCopied })
    }

    // MARK: The samples

    @Test func aGuideBringsEitherAPictureOrAnEmptyWindowAndNothingElse() {
        #expect(!TutorialSampleScreen.layers(for: .starterScreen).isEmpty)
        #expect(TutorialSampleScreen.layers(for: .emptyWindow).isEmpty)
    }
}
