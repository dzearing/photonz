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

    @Test func theTrackRunsFromMakingOneToGivingItEveryState() {
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

    @Test func nothingInTheTrackSaysVersion() {
        // A guide teaches the word the panel says. Until 2026-09-15 the panel
        // said "Versions" and this test held the track to it; the panel now
        // asks one question called Variant, in one list called Properties, so
        // the word that must not appear is the old one.
        //
        // "Version" is also the other thing that word means in an editor — the
        // history of a document — which is half of why it had to go.
        for guide in components {
            for step in guide.steps {
                #expect(!step.body.lowercased().contains("version"),
                        "\(guide.id)/\(step.id) teaches a word the panel does not use")
                #expect(!step.title.lowercased().contains("version"), "\(guide.id)/\(step.id)")
            }
            #expect(!guide.summary.lowercased().contains("version"), "\(guide.id)")
            #expect(!guide.title.lowercased().contains("version"), "\(guide.id)")
        }
    }

    @Test func theTrackSaysAdjustableNowhere() {
        // The other invented word. Everything a copy may set is a PROPERTY.
        for guide in components {
            for step in guide.steps {
                #expect(!step.body.lowercased().contains("adjustable"),
                        "\(guide.id)/\(step.id) teaches a word the panel does not use")
                #expect(!step.title.lowercased().contains("adjustable"), "\(guide.id)/\(step.id)")
            }
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

    // MARK: The states guide

    /// Reached by its id, which is what a saved place in a track points at. The
    /// guide was called "One name, two looks" until 2026-09-15; the id stays.
    private func statesGuide() throws -> TutorialGuide {
        try #require(TutorialCatalog.guide(id: "component-versions"))
    }

    @Test func theStatesGuideNamesTheFourStatesAButtonReallyHas() throws {
        let guide = try statesGuide()
        let copy = (guide.title + " " + guide.summary + " "
                    + guide.steps.map { $0.title + " " + $0.body }.joined(separator: " ")).lowercased()
        for state in ["resting", "hovered", "pressed", "disabled"] {
            #expect(copy.contains(state), "the guide never mentions the \(state) state")
        }
    }

    @Test func itIsCalledAfterWhatItIsForRatherThanAfterTheMechanism() throws {
        let guide = try statesGuide()
        // "Variant" is the panel's word for the machinery. A person choosing a
        // guide off the hub is choosing a job, not a data structure.
        #expect(!guide.title.lowercased().contains("variant"))
        #expect(!guide.title.lowercased().contains("propert"))
        #expect(guide.title.lowercased().contains("state")
                || guide.title.lowercased().contains("button"))
    }

    @Test func itTeachesTheAppsOwnWordBeforeItTeachesTheJob() throws {
        // The panel asks one question called Variant and lets the author rename
        // it, with its own help saying to call it State. That rename is what
        // lets the rest of the guide say "state" without teaching a word the
        // app does not use, so it has to come before the steps that say it.
        let guide = try statesGuide()
        let ids = guide.steps.map(\.id)
        let rename = try #require(ids.firstIndex(of: "call-the-question-state"))
        let renaming = guide.steps[rename]
        #expect(renaming.body.contains("Variant"), "it never shows the word it is replacing")
        #expect(renaming.body.contains("State"))
        #expect(renaming.waits, "renaming it is something you do, not something you read")
        #expect(rename < ids.firstIndex(of: "the-other-two")!)
    }

    /// The guide tells you to pick a row off the Add menu BY NAME, so it has
    /// to spell that row the way the app spells it. The app spells it after
    /// whatever the property is called (`ComponentVariantWording`), so the
    /// first time it is "A second Variant" and, once the guide has had you
    /// rename the question to State, it is "Another State".
    @Test func itNamesTheAddRowsTheWayTheAppSpellsThem() throws {
        let guide = try statesGuide()
        let first = try #require(guide.steps.first { $0.id == "add-a-look" })
        #expect(first.body.contains(ComponentVariantWording(nil).addRow(hasAny: false)))
        let rest = try #require(guide.steps.first { $0.id == "the-other-two" })
        #expect(rest.body.contains(ComponentVariantWording("State").addRow(hasAny: true)))
    }

    @Test func itSaysWhatCarriesAcrossSoNobodyRedrawsTheButtonFourTimes() throws {
        let guide = try statesGuide()
        let differs = try #require(guide.steps.first { $0.id == "change-only-what-differs" })
        #expect(differs.waits)
        // The lesson is the sentence, not the colour: a new state arrives as an
        // exact copy, so it is one change rather than a redraw.
        let copy = guide.steps.map(\.body).joined(separator: " ").lowercased()
        #expect(copy.contains("copy"), "it never says a new state starts as a copy")
        #expect(copy.contains("redraw"), "it never says you do not redraw the button")
    }

    @Test func itSaysWhyTheStatesBelongUnderOneName() throws {
        let guide = try statesGuide()
        let copy = guide.steps.map { $0.title + " " + $0.body }.joined(separator: " ").lowercased()
        #expect(copy.contains("drift"), "it never says what one name is protecting against")
        // ...and the shipped way one edit reaches the others, which is a row
        // under the list rather than something that happens by itself.
        #expect(copy.contains("carries it") || copy.contains("carried"),
                "it never says how a change made in one state reaches the rest")
    }

    @Test func itEndsWithEveryStateOnThePageRatherThanOnACard() throws {
        let guide = try statesGuide()
        let last = try #require(guide.steps.last)
        #expect(last.anchor == .canvas, "it ends in the panel, away from the four drawings")
        #expect(last.id == "all-four-together")
        #expect(guide.sample == .componentCopies)
    }

    @Test func everyStateItAddsLandsSomewhereYouCanSeeIt() throws {
        // The guide's whole payoff is four drawings on screen at once. Each one
        // is put down by the app, not by the person, so where they land is the
        // app's answer and this is the test of it.
        var document = PhotonzDocument(canvasSize: TutorialSampleScreen.canvasSize,
                                       layers: TutorialSampleScreen.layers(for: .componentCopies))
        document.syncComponentInstances()
        let original = try #require(document.layers.first { $0.isMainComponent })
        let componentID = try #require(original.componentID)
        // The order the guide asks for: two states added from the first drawing,
        // the last one from whichever you were standing on.
        _ = document.addComponentVersion(componentID: componentID, name: "Hover")
        let pressed = document.addComponentVersion(componentID: componentID, name: "Pressed")
        _ = document.addComponentVersion(componentID: componentID, from: pressed, name: "Disabled")

        let states = document.componentVersions(of: componentID)
        #expect(states.map(\.name) == ["Default", "Hover", "Pressed", "Disabled"])
        let boxes = states.compactMap { document.canvasBounds(of: $0.layerID) }
        #expect(boxes.count == 4)
        let canvas = CGRect(origin: .zero, size: TutorialSampleScreen.canvasSize)
        for (state, box) in zip(states, boxes) {
            #expect(canvas.contains(box), "\(state.name) lands off the canvas at \(box)")
        }
        // None of them lands on top of another, or the picture the guide ends on
        // is three drawings and a pile.
        for i in boxes.indices {
            for j in boxes.indices where j > i {
                #expect(!boxes[i].intersects(boxes[j]),
                        "\(states[i].name) and \(states[j].name) overlap")
            }
        }
        // ...nor on top of the copies that came with the sample.
        for copy in document.layers.filter({ $0.isComponentInstance }) {
            let copyBox = try #require(document.canvasBounds(of: copy.id))
            for (state, box) in zip(states.dropFirst(), boxes.dropFirst()) {
                #expect(!box.intersects(copyBox), "\(state.name) lands on a copy")
            }
        }
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

    @Test func theStatesGuideHasRoomOnThePageForTheStatesItAdds() {
        // A new state lands beside the drawing it came from. A sample filling
        // the canvas would push it somewhere nobody is looking.
        let layers = TutorialSampleScreen.layers(for: .componentCopies)
        let right = layers.map(\.frame.maxX).max() ?? 0
        #expect(TutorialSampleScreen.canvasSize.width - right >= 220,
                "no room beside the original for the states the guide adds")
    }
}
