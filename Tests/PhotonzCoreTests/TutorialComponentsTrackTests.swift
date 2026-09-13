import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The Components track: make a piece of UI once, fetch it as often as you
/// like, and change one copy without cutting it loose.
///
/// Four guides, in the order the job is done in. The first two are the whole
/// bargain (create once, reuse everywhere); the last two are the part everybody
/// gets wrong, which is what a copy OWNS and what it merely borrows.
///
/// Everything here is a fact about the DATA, because that is all a guide is.
/// That each anchor really turns up in a live window is proved by the walks.
@Suite("Tutorials: the Components track")
struct TutorialComponentsTrackTests {

    private var components: [TutorialGuide] { TutorialCatalog.guides(in: .components) }

    // MARK: The track itself

    @Test func theTrackRunsFromMakingOneToHoldingTwoLooksUnderOneName() {
        let ids = components.map(\.id)
        #expect(ids == ["make-a-component", "use-it-again-and-again",
                        "override-one-copy", "component-versions"])
    }

    @Test func everyGuideInTheTrackIsShortEnoughToFinishInOneSitting() {
        for guide in components {
            #expect(guide.minutes <= 3, "\(guide.id) claims \(guide.minutes) minutes")
            #expect(guide.steps.count <= 8, "\(guide.id) has \(guide.steps.count) steps")
            #expect(guide.steps.count >= 3, "\(guide.id) has \(guide.steps.count) steps")
        }
    }

    @Test func everyGuideClaimsATimeItCanActuallyBeFinishedIn() {
        for guide in components {
            #expect(TutorialLength.claimIsHonest(for: guide),
                    "\(guide.id) claims \(guide.minutes) min, work is \(Int(TutorialLength.estimatedSeconds(for: guide)))s")
        }
    }

    @Test func nothingInTheTrackTeachesOverYourOwnPicture() {
        // Every guide here promotes, places or restyles something, and doing
        // any of that to somebody's own work while showing them round is the
        // one thing a tutorial may never do.
        for guide in components {
            #expect(guide.sample != nil, "\(guide.id) would teach over whatever you had open")
            #expect(guide.sample?.isFlattened == false,
                    "\(guide.id) brings a picture, and a component cannot be made out of pixels")
        }
    }

    @Test func aStepThatPointsIntoThePanelOpensThePanelFirst() {
        for guide in components {
            for step in guide.steps where step.anchor.panelSectionID != nil {
                #expect(step.prepare.contains(.showPanel),
                        "\(guide.id)/\(step.id) points into the panel without opening it")
                #expect(step.prepare.contains(.revealTarget),
                        "\(guide.id)/\(step.id) points into the panel without scrolling to it")
            }
        }
    }

    @Test func aStepThatPointsAtTheShelfPutsItOnComponentsFirst() {
        // The shelf remembers the scope you left it on, and that is Media until
        // somebody changes it. A step ringing the Library while it is showing
        // screenshots is a step pointing at the wrong shelf, so every step that
        // names the shelf asks for the Components one.
        for guide in components {
            for step in guide.steps where step.anchor == .panelSection("library") {
                #expect(step.prepare.contains(.showComponentShelf),
                        "\(guide.id)/\(step.id) rings the shelf without putting it on Components")
            }
        }
    }

    @Test func noGuideEndsByVanishingOnYou() {
        for guide in components {
            #expect(guide.steps.last?.waits == false,
                    "\(guide.id) ends on a step that waits, so it vanishes rather than finishing")
        }
    }

    @Test func everyGuideHasYouBuildSomethingRatherThanReadSixCards() {
        for guide in components {
            let waits = guide.steps.filter(\.waits).count
            #expect(waits >= 3, "\(guide.id) waits on you \(waits) times")
        }
    }

    // MARK: What the copy is allowed to say

    @Test func theCopyNamesKeysRatherThanMenuRows() {
        for guide in components {
            for step in guide.steps {
                #expect(!step.body.contains("\u{25B8}"),
                        "\(guide.id)/\(step.id) names a menu row, which can move under a flag")
            }
        }
    }

    @Test func nothingInTheTrackSaysVariant() {
        // The task that asked for this track called the fourth guide
        // "Variants". The app has never used that word: a component holds
        // VERSIONS, the panel says Versions, and a guide teaches what shipped
        // rather than what the plan called it.
        for guide in components {
            for step in guide.steps {
                #expect(!step.body.lowercased().contains("variant"),
                        "\(guide.id)/\(step.id) teaches a word the panel does not use")
                #expect(!step.title.lowercased().contains("variant"), "\(guide.id)/\(step.id)")
            }
            #expect(!guide.summary.lowercased().contains("variant"), "\(guide.id)")
            #expect(!guide.title.lowercased().contains("variant"), "\(guide.id)")
        }
    }

    @Test func nothingInTheTrackNamesARowThatMovesUnderAFlag() {
        // `next-shape-parts` splits the panel: a shape's colour row is called
        // Fill under Appearance with the split on and Color without it. A step
        // may ring the section either way, and may not name what is in it.
        let moving = ["fill row", "appearance", "opacity", "fade"]
        for guide in components {
            for step in guide.steps {
                let copy = (step.title + " " + step.body).lowercased()
                for word in moving {
                    #expect(!copy.contains(word),
                            "\(guide.id)/\(step.id) names \(word), which moves under a flag")
                }
            }
        }
    }

    @Test func theWholeTrackPassesTheCopyRules() {
        for guide in components {
            #expect(TutorialCopyRules.problems(in: guide) == [], "\(guide.id)")
        }
    }

    // MARK: Flags

    @Test func everyGuideSaysWhichFeatureItNeeds() {
        let known = Set(FeatureCatalog.flags(for: .next).map(\.name))
        for guide in components {
            #expect(!guide.requires.isEmpty, "\(guide.id) names no feature")
            for flag in guide.requires {
                #expect(known.contains(flag),
                        "\(guide.id) needs \(flag), which is not a feature the app has")
            }
        }
    }

    @Test func everyGuideAsksForTheWholeChainItStandsOn() {
        // Components need the Library to be fetched from, and the Library needs
        // groups to hold anything. The app resolves that chain itself, but the
        // catalogue asks flag by flag, so a guide naming only the last link
        // would still be offered to somebody who switched off the first.
        for guide in components {
            #expect(guide.requires.contains(FeatureCatalog.componentsFlag), "\(guide.id)")
            #expect(guide.requires.contains(FeatureCatalog.libraryFlag), "\(guide.id)")
            #expect(guide.requires.contains(FeatureCatalog.layerGroupsFlag), "\(guide.id)")
        }
    }

    @Test func switchingComponentsOffTakesTheWholeShelfAway() {
        let shown = TutorialCatalog.guides(enabled: { $0 != FeatureCatalog.componentsFlag })
        #expect(shown.allSatisfy { $0.track != .components })
        #expect(!TutorialCatalog.populatedTracks(in: shown).contains(.components))
        #expect(TutorialCatalog.populatedTracks(in: shown).contains(.basics))
    }

    @Test func switchingGroupsOffTakesItAwayTooBecauseThereIsNoWayIn() {
        let shown = TutorialCatalog.guides(enabled: { $0 != FeatureCatalog.layerGroupsFlag })
        #expect(shown.allSatisfy { $0.track != .components })
    }

    // MARK: What each guide is for

    @Test func theFirstGuideGroupsThenPromotesThenNames() throws {
        let guide = try #require(TutorialCatalog.guide(id: "make-a-component"))
        let ids = guide.steps.map(\.id)
        #expect(ids.firstIndex(of: "group-them")! < ids.firstIndex(of: "promote")!,
                "a component is made from a group, so the grouping comes first")
        // It ends on the shelf, because the payoff of promoting something is
        // that it turns up somewhere you can fetch it from.
        #expect(guide.steps.last?.anchor == .panelSection("library"))
        // It brings the two loose pieces rather than a drawing lesson.
        #expect(guide.sample == .componentPieces)
    }

    @Test func theSecondGuidePlacesTwoCopiesAndThenMovesThemBoth() throws {
        let guide = try #require(TutorialCatalog.guide(id: "use-it-again-and-again"))
        // Two copies, not one: one copy following its original proves nothing
        // that a duplicate would not.
        let placements = guide.steps.filter { $0.anchor == .panelSection("library") && $0.waits }
        #expect(placements.count == 2, "one copy does not show anything two does not")
        // ...and then one edit to the original, which is the whole point.
        #expect(guide.steps.contains { $0.anchor == .panelSection("color") && $0.waits })
    }

    @Test func noStepWaitsOnPickingSomethingItAlsoAsksYouToDoubleClick() throws {
        // A double click's FIRST click already selects, which raises the very
        // event a waiting step listens for. So a step that says "double click
        // it" and waits on a selection moves the card on halfway through the
        // gesture. Every double click in this track therefore sits in a step
        // that waits on the EDIT it leads to, and picking something is always
        // its own single click.
        for guide in components {
            for step in guide.steps where step.body.lowercased().contains("double click") {
                #expect(step.advance.trigger != .layerSelected,
                        "\(guide.id)/\(step.id) advances halfway through its own double click")
            }
        }
    }

    @Test func noStepAsksYouToTellApartThreeRowsWithTheSameNameOnThem() throws {
        // Every copy carries its original's name, so a page with an original
        // and two copies on it puts three rows reading Save Button in the
        // layers list. The list cannot say which is which without reading the
        // mark on each row, and a step that asked somebody to would be a step
        // most people get wrong. Reaching the original is a click on the
        // drawing itself, where there is only one of it.
        for guide in components where guide.sample == .componentCopies {
            for step in guide.steps {
                #expect(step.anchor != .panelSection("layers"),
                        "\(guide.id)/\(step.id) sends you into a list of identical rows")
            }
        }
    }

    @Test func theOverrideGuideExposesTheKnobOnTheOriginalAndAnswersItOnACopy() throws {
        let guide = try #require(TutorialCatalog.guide(id: "override-one-copy"))
        let ids = guide.steps.map(\.id)
        #expect(ids.firstIndex(of: "add-a-knob")! < ids.firstIndex(of: "pick-a-copy")!,
                "the original decides what is adjustable before a copy can answer it")
        // Every copy is shown a way back, or an override set once is an
        // override you can only undo by undoing.
        let copy = guide.steps.map(\.body).joined(separator: " ").lowercased()
        #expect(copy.contains("back"), "the guide never says how to stop overriding")
        #expect(guide.sample == .componentCopies)
    }

    @Test func theVersionsGuideEndsOnACopyShowingTheSecondDrawing() throws {
        let guide = try #require(TutorialCatalog.guide(id: "component-versions"))
        let ids = guide.steps.map(\.id)
        #expect(ids.firstIndex(of: "add-a-version")! < ids.firstIndex(of: "switch-it")!)
        #expect(guide.steps.contains { $0.id == "switch-it" && $0.waits })
        #expect(guide.sample == .componentCopies)
    }

    // MARK: The samples the track brings

    @Test func theSampleForTheFirstGuideIsNotAComponentYet() {
        // The whole guide is making one. A sample that arrived already promoted
        // would have nothing to do.
        let layers = TutorialSampleScreen.layers(for: .componentPieces)
        #expect(layers.count == 2, "a box and its words, loose on the page")
        #expect(layers.allSatisfy { !$0.isMainComponent && !$0.isComponentInstance })
        #expect(layers.allSatisfy { !$0.isGroup }, "grouping them is a step of the guide")
    }

    @Test func theSampleForTheSecondGuideIsOneOriginalAndNoCopies() {
        // Placing the copies is the guide. Arriving with them placed would be
        // arriving with the lesson over.
        let layers = TutorialSampleScreen.layers(for: .componentOriginal)
        #expect(layers.filter(\.isMainComponent).count == 1)
        #expect(layers.filter(\.isComponentInstance).isEmpty)
    }

    @Test func theSampleForTheLastTwoGuidesIsOneOriginalAndTwoCopies() {
        let layers = TutorialSampleScreen.layers(for: .componentCopies)
        let original = layers.filter(\.isMainComponent)
        let copies = layers.filter(\.isComponentInstance)
        #expect(original.count == 1)
        #expect(copies.count == 2, "one copy proves nothing two does not")
        // Every copy really points at the original that is on the page with it.
        #expect(copies.allSatisfy { $0.instanceOf == original.first?.componentID })
    }

    @Test func theOriginalArrivesWithNothingAdjustableAndOneDrawing() {
        // Both are lessons: the override guide adds the first knob, and the
        // versions guide adds the second drawing.
        let layers = TutorialSampleScreen.layers(for: .componentCopies)
        let original = layers.first(where: \.isMainComponent)
        #expect(original?.group?.properties.isEmpty == true)
        #expect(original?.group?.versionID == nil)
    }

    @Test func everyCopyInTheSampleDrawsWhatTheOriginalDraws() throws {
        // A copy's contents are not its own. A sample whose copies arrived
        // drawing something else would be a lie on screen before step one.
        var document = PhotonzDocument(canvasSize: TutorialSampleScreen.canvasSize,
                                       layers: TutorialSampleScreen.layers(for: .componentCopies))
        document.syncComponentInstances()
        let original = try #require(document.layers.first { $0.isMainComponent })
        for copy in document.layers.filter({ $0.isComponentInstance }) {
            #expect(copy.children.map(\.name) == original.children.map(\.name))
        }
    }

    @Test func theSamplesSitInsideTheCanvasTheyAreDrawnOn() {
        let canvas = CGRect(origin: .zero, size: TutorialSampleScreen.canvasSize)
        for sample in [TutorialSample.componentPieces, .componentOriginal, .componentCopies] {
            for layer in TutorialSampleScreen.layers(for: sample) {
                #expect(canvas.contains(layer.frame),
                        "\(sample.rawValue) draws \(layer.name) outside the canvas")
            }
        }
    }

    @Test func theVersionsGuideHasRoomOnThePageForASecondDrawing() {
        // A new version lands beside the one it came from. A sample filling the
        // canvas would push it somewhere nobody is looking.
        let layers = TutorialSampleScreen.layers(for: .componentCopies)
        let right = layers.map(\.frame.maxX).max() ?? 0
        #expect(TutorialSampleScreen.canvasSize.width - right >= 220,
                "no room beside the original for the version the guide adds")
    }
}
