import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The Redlining track: the app's real daily job, taught in five short guides.
/// Measure a gap, measure a size, draw one by hand and control the magnets,
/// collect what you measured, and hand the list to somebody else.
///
/// Everything here is a fact about the DATA, because that is all a guide is.
/// That each anchor really turns up in a live window is proved by the walks.
@Suite("Tutorials: the Redlining track")
struct TutorialRedliningTrackTests {

    private var redlining: [TutorialGuide] { TutorialCatalog.guides(in: .redlining) }

    // MARK: The track itself

    @Test func theTrackRunsInTheOrderTheJobIsDoneIn() {
        let ids = redlining.map(\.id)
        #expect(ids == ["measure-a-gap", "measure-a-size", "snap-or-free",
                        "measurements-panel", "export-a-spec-list"])
    }

    @Test func everyGuideInTheTrackIsShortEnoughToFinishInOneSitting() {
        for guide in redlining {
            #expect(guide.minutes <= 3, "\(guide.id) claims \(guide.minutes) minutes")
            #expect(guide.steps.count <= 8, "\(guide.id) has \(guide.steps.count) steps")
            #expect(guide.steps.count >= 3, "\(guide.id) has \(guide.steps.count) steps")
        }
    }

    @Test func everyGuideInTheAppClaimsALengthItsOwnStepsSupport() {
        // The number on the card is a promise. It is measured off the guide:
        // the words to read, a beat per step, and longer again for a step that
        // waits on you really doing something. A guide that grows three steps
        // and keeps saying two minutes fails here rather than in somebody's
        // afternoon. Over the WHOLE catalogue, not just this track.
        for guide in TutorialCatalog.guides {
            let seconds = Int(TutorialLength.estimatedSeconds(for: guide))
            #expect(TutorialLength.claimIsHonest(for: guide),
                    "\(guide.id) claims \(guide.minutes) min and reads as \(seconds)s")
        }
    }

    @Test func nothingInTheTrackTeachesOverYourOwnPicture() {
        // A redlining guide measures a picture, and what somebody happens to
        // have open is their work. Every guide brings a screen of its own.
        for guide in redlining {
            #expect(guide.sample != nil, "\(guide.id) would teach over whatever you had open")
        }
    }

    @Test func everyGuideMeasuresAPictureRatherThanADrawing() throws {
        // The whole track depends on the app finding elements and gaps in the
        // PIXELS. A sample made of live shapes has no pixels to find, so every
        // redlining sample is one that gets flattened into a picture first.
        for guide in redlining {
            let sample = try #require(guide.sample)
            #expect(sample.isFlattened,
                    "\(guide.id) brings \(sample.rawValue), which the detector cannot read")
        }
    }

    @Test func aStepThatPointsIntoThePanelOpensThePanelFirst() {
        for guide in redlining {
            for step in guide.steps where step.anchor.panelSectionID != nil {
                #expect(step.prepare.contains(.showPanel),
                        "\(guide.id)/\(step.id) points into the panel without opening it")
                #expect(step.prepare.contains(.revealTarget),
                        "\(guide.id)/\(step.id) points into the panel without scrolling to it")
            }
        }
    }

    @Test func noGuideEndsByVanishingOnYou() {
        // A guide whose last step waits on something simply disappears the
        // moment you do it: no closing word, no Done, nothing to say it is
        // over. Measured on 2026-09-13, when the size guide ended on its own
        // click and the callout evaporated mid lesson. Every guide now ends on
        // a step you press Done on.
        for guide in redlining {
            #expect(guide.steps.last?.waits == false,
                    "\(guide.id) ends on a step that waits, so it vanishes rather than finishing")
        }
    }

    // MARK: What the copy is allowed to say

    @Test func theCopyNamesKeysRatherThanMenuRows() {
        // Same rule the Basics track settled: a menu row moves under a feature
        // flag and a key does not, so a guide says the key.
        for guide in redlining {
            for step in guide.steps {
                #expect(!step.body.contains("▸"),
                        "\(guide.id)/\(step.id) names a menu row, which can move under a flag")
                #expect(!step.body.contains(" menu"),
                        "\(guide.id)/\(step.id) sends somebody to a menu instead of a key")
            }
        }
    }

    @Test func theWholeTrackPassesTheCopyRules() {
        for guide in redlining {
            #expect(TutorialCopyRules.problems(in: guide) == [], "\(guide.id)")
        }
    }

    // MARK: Flags

    @Test func everyGuideSaysWhichFeatureItNeeds() {
        // Each of these teaches something that rides a flag. A guide for a
        // feature somebody has switched off is a guide pointing at a control
        // that is not there, so it says what it needs and the app leaves it out.
        let known = Set(FeatureCatalog.flags(for: .next).map(\.name))
        for guide in redlining {
            #expect(!guide.requires.isEmpty, "\(guide.id) names no feature")
            for flag in guide.requires {
                #expect(known.contains(flag),
                        "\(guide.id) needs \(flag), which is not a feature the app has")
            }
        }
    }

    @Test func switchingTheMeasureFeaturesOffTakesTheWholeTrackAway() {
        let off = Set([FeatureCatalog.measureModesFlag, FeatureCatalog.measurePanelFlag])
        let shown = TutorialCatalog.guides(enabled: { !off.contains($0) })
        #expect(shown.allSatisfy { $0.track != .redlining })
        // And the shelf goes with it rather than standing there empty.
        #expect(!TutorialCatalog.populatedTracks(in: shown).contains(.redlining))
        // Basics is untouched: it needs nothing that can be switched off.
        #expect(TutorialCatalog.populatedTracks(in: shown).contains(.basics))
    }

    @Test func switchingOnlyThePanelOffLeavesTheMeasuringGuidesThere() {
        let shown = TutorialCatalog.guides(enabled: { $0 != FeatureCatalog.measurePanelFlag })
        let ids = shown.filter { $0.track == .redlining }.map(\.id)
        #expect(ids == ["measure-a-gap", "measure-a-size", "snap-or-free"])
    }

    // MARK: What each guide is for

    @Test func theGapGuideMakesYouSwitchModeAndReallyMeasureSomething() throws {
        let guide = try #require(TutorialCatalog.guide(id: "measure-a-gap"))
        let waits = guide.steps.compactMap(\.advance.trigger)
        #expect(waits.contains(.toolPicked(.measure)))
        #expect(waits.contains(.measureMode(.gap)))
        #expect(waits.contains(.editMade))
        // The tool comes before the mode: the mode chip is on the tool's own
        // button, and there is nothing to press until the tool is in hand.
        let tool = try #require(waits.firstIndex(of: .toolPicked(.measure)))
        let mode = try #require(waits.firstIndex(of: .measureMode(.gap)))
        #expect(tool < mode)
    }

    @Test func theSizeGuideTeachesTheKeysThatChangeWhatIsPicked() throws {
        let guide = try #require(TutorialCatalog.guide(id: "measure-a-size"))
        #expect(guide.steps.compactMap(\.advance.trigger).contains(.measureMode(.size)))
        #expect(guide.steps.contains { $0.body.contains("[") && $0.body.contains("]") })
    }

    @Test func theSnappingGuideIsAboutTheTwoKeysThatChangeWhereAFootLands() throws {
        let guide = try #require(TutorialCatalog.guide(id: "snap-or-free"))
        #expect(guide.steps.compactMap(\.advance.trigger).contains(.measureMode(.distance)))
        let copy = guide.steps.map(\.body).joined(separator: " ")
        #expect(copy.contains("\u{2318}"), "the guide never says which key frees the magnets")
        #expect(copy.contains("\u{21E7}"), "the guide never says which key holds the direction")
        // The tool's own settings are only in the panel while the tool is in
        // HAND, and placing a caliper hands the pointer back. So that step goes
        // before the drawing, not after it: at the end it pointed at nothing
        // and the card fell to the middle of the window (walk, 2026-09-13).
        let ids = guide.steps.map(\.id)
        let settings = try #require(ids.firstIndex(of: "what-it-snaps-to"))
        let drawing = try #require(ids.firstIndex(of: "draw-one"))
        #expect(settings < drawing)
    }

    @Test func thePanelGuideArrivesWithSomethingInTheList() throws {
        let guide = try #require(TutorialCatalog.guide(id: "measurements-panel"))
        let sample = try #require(guide.sample)
        // A list guide that opens on an empty list teaches nothing, so its
        // sample carries measurements already made.
        let measures = TutorialSampleScreen.layers(for: sample).filter { $0.measure != nil }
        #expect(measures.count >= 2)
        #expect(guide.steps.allSatisfy { $0.anchor == .panelSection("measurements") })
    }

    @Test func theExportGuideEndsWithTheListOnTheClipboard() throws {
        let guide = try #require(TutorialCatalog.guide(id: "export-a-spec-list"))
        let waits = guide.steps.compactMap(\.advance.trigger)
        #expect(waits.contains(.specListCopied))
        #expect(waits.contains(.pictureCopied))
        let measures = TutorialSampleScreen.layers(for: try #require(guide.sample))
            .filter { $0.measure != nil }
        #expect(measures.count >= 2, "there would be nothing to copy")
    }

    // MARK: The sample

    @Test func theSampleScreenHasSomethingWorthMeasuringInIt() {
        let picture = TutorialSampleScreen.pictureLayers(for: .redlineScreen)
        #expect(picture.count >= 6, "too plain to redline")
        // Nothing is left live on top of a plain redlining screen: it is a
        // picture, exactly like a screenshot somebody took.
        #expect(TutorialSampleScreen.layers(for: .redlineScreen).isEmpty)
    }

    @Test func theMeasuredSampleIsTheSameScreenWithTheMeasurementsOnTop() {
        // Layer identity is minted fresh every time, so compare what is drawn.
        #expect(TutorialSampleScreen.pictureLayers(for: .measuredScreen).map(\.name)
                == TutorialSampleScreen.pictureLayers(for: .redlineScreen).map(\.name))
        #expect(TutorialSampleScreen.pictureLayers(for: .measuredScreen).map(\.frame)
                == TutorialSampleScreen.pictureLayers(for: .redlineScreen).map(\.frame))
        let live = TutorialSampleScreen.layers(for: .measuredScreen)
        #expect(live.allSatisfy { $0.measure != nil })
    }

    @Test func theSampleMeasurementsSayWhatTheyAreInASpecList() throws {
        // The export guide's promise, rendered: the list a person copies has a
        // line per measurement with a name, a number and what kind it is.
        var document = PhotonzDocument(canvasSize: TutorialSampleScreen.canvasSize)
        document.layers = TutorialSampleScreen.layers(for: .measuredScreen)
        let list = MeasureSpecList.render(document: document, name: "Tutorial Sample")
        #expect(list.contains("Tutorial Sample"))
        #expect(list.contains("(spacing)"))
        #expect(list.contains("(size)"))
    }
}
