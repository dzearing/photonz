import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The Looks track: how a layer is painted, and what can be added to it.
///
/// Four guides. The first two teach the split the panel turns on (Appearance is
/// what a layer IS, Effects is the list you ADD to), and the last two teach the
/// two ways a layer reaches what is UNDER it: a lens changes it, a blending
/// mode mixes with it.
///
/// Everything here is a fact about the DATA, because that is all a guide is.
/// That each anchor really turns up in a live window is proved by the walks.
@Suite("Tutorials: the Looks track")
struct TutorialLooksTrackTests {

    private var looks: [TutorialGuide] { TutorialCatalog.guides(in: .looks) }

    // MARK: The track itself

    @Test func theTrackRunsFromWhatALayerIsToWhatItDoesToWhatIsUnderIt() {
        let ids = looks.map(\.id)
        #expect(ids == ["what-a-shape-is-made-of", "add-a-shadow-a-border-a-glow",
                        "blur-what-is-underneath", "mix-with-what-is-below"])
    }

    @Test func everyGuideInTheTrackIsShortEnoughToFinishInOneSitting() {
        for guide in looks {
            #expect(guide.minutes <= 3, "\(guide.id) claims \(guide.minutes) minutes")
            #expect(guide.steps.count <= 8, "\(guide.id) has \(guide.steps.count) steps")
            #expect(guide.steps.count >= 3, "\(guide.id) has \(guide.steps.count) steps")
        }
    }

    @Test func nothingInTheTrackTeachesOverYourOwnPicture() {
        // Every guide here restyles something, and restyling somebody's own
        // work while showing them round is the one thing a tutorial may never
        // do. Each brings a screen of its own.
        for guide in looks {
            #expect(guide.sample != nil, "\(guide.id) would teach over whatever you had open")
        }
    }

    @Test func nothingInTheTrackAsksYouToDrawAShapeFirst() {
        // The shapes share ONE slot in the tool bar, and the slot wears
        // whichever member you picked up last. So a step pointing at the
        // rectangle points at nothing on an app whose shapes slot is wearing
        // the line, and a guide about STYLING a shape should not start with a
        // drawing lesson anyway. Every guide here styles what its sample
        // brought with it.
        for guide in looks {
            for step in guide.steps {
                for shape in [Tool.rectangle, .ellipse, .line] {
                    #expect(step.anchor != .tool(shape),
                            "\(guide.id)/\(step.id) points at a tool that shares a slot")
                }
            }
        }
    }

    @Test func aStepThatPointsIntoThePanelOpensThePanelFirst() {
        for guide in looks {
            for step in guide.steps where step.anchor.panelSectionID != nil {
                #expect(step.prepare.contains(.showPanel),
                        "\(guide.id)/\(step.id) points into the panel without opening it")
                #expect(step.prepare.contains(.revealTarget),
                        "\(guide.id)/\(step.id) points into the panel without scrolling to it")
            }
        }
    }

    @Test func noGuideEndsByVanishingOnYou() {
        for guide in looks {
            #expect(guide.steps.last?.waits == false,
                    "\(guide.id) ends on a step that waits, so it vanishes rather than finishing")
        }
    }

    @Test func everyGuideHasYouDoSomethingRatherThanReadFiveCards() {
        // A track about how things LOOK is one you have to watch change. Every
        // guide here waits on the person really doing something at least twice.
        for guide in looks {
            let waits = guide.steps.filter(\.waits).count
            #expect(waits >= 2, "\(guide.id) waits on you \(waits) times")
        }
    }

    // MARK: What the copy is allowed to say

    @Test func theCopyNamesKeysRatherThanMenuRows() {
        for guide in looks {
            for step in guide.steps {
                #expect(!step.body.contains("▸"),
                        "\(guide.id)/\(step.id) names a menu row, which can move under a flag")
            }
        }
    }

    @Test func nothingInTheTrackSaysOutline() {
        // Outline stopped being a row on 2026-09-08: a layer's edge is a Border
        // in the Effects list now (`OutlineRetirement.swift`). The word is the
        // one thing this track could easily still be teaching, because it is
        // what the task that asked for it was written against.
        for guide in looks {
            for step in guide.steps {
                #expect(!step.body.lowercased().contains("outline"),
                        "\(guide.id)/\(step.id) teaches a row that is not in the panel")
                #expect(!step.title.lowercased().contains("outline"), "\(guide.id)/\(step.id)")
            }
            #expect(!guide.summary.lowercased().contains("outline"), "\(guide.id)")
        }
    }

    @Test func theWholeTrackPassesTheCopyRules() {
        for guide in looks {
            #expect(TutorialCopyRules.problems(in: guide) == [], "\(guide.id)")
        }
    }

    // MARK: Flags

    @Test func everyGuideSaysWhichFeatureItNeeds() {
        let known = Set(FeatureCatalog.flags(for: .next).map(\.name))
        for guide in looks {
            #expect(!guide.requires.isEmpty, "\(guide.id) names no feature")
            for flag in guide.requires {
                #expect(known.contains(flag),
                        "\(guide.id) needs \(flag), which is not a feature the app has")
            }
        }
    }

    @Test func switchingTheSplitOffLeavesOnlyTheGuideThatDoesNotNeedIt() {
        // Three of the four teach a panel that only exists with the split on:
        // two teach the split itself and the mixing row is inside Appearance.
        // The lens is its own section and its own tool, so it stands on its own
        // and a guide is never asked for a flag it does not need.
        let shown = TutorialCatalog.guides(enabled: { $0 != FeatureCatalog.shapePartsFlag })
        let ids = shown.filter { $0.track == .looks }.map(\.id)
        #expect(ids == ["blur-what-is-underneath"])
        #expect(TutorialCatalog.populatedTracks(in: shown).contains(.looks))
    }

    @Test func switchingEverythingThisTrackNeedsOffTakesTheShelfAway() {
        let off = Set([FeatureCatalog.shapePartsFlag, FeatureCatalog.lensFlag])
        let shown = TutorialCatalog.guides(enabled: { !off.contains($0) })
        #expect(shown.allSatisfy { $0.track != .looks })
        #expect(!TutorialCatalog.populatedTracks(in: shown).contains(.looks))
        #expect(TutorialCatalog.populatedTracks(in: shown).contains(.basics))
    }

    @Test func switchingTheLensOffTakesOnlyTheLensGuideAway() {
        let shown = TutorialCatalog.guides(enabled: { $0 != FeatureCatalog.lensFlag })
        let ids = shown.filter { $0.track == .looks }.map(\.id)
        #expect(ids == ["what-a-shape-is-made-of", "add-a-shadow-a-border-a-glow",
                        "mix-with-what-is-below"])
    }

    @Test func switchingTheMixingOffTakesOnlyTheMixingGuideAway() {
        let shown = TutorialCatalog.guides(enabled: { $0 != FeatureCatalog.blendModeFlag })
        let ids = shown.filter { $0.track == .looks }.map(\.id)
        #expect(ids == ["what-a-shape-is-made-of", "add-a-shadow-a-border-a-glow",
                        "blur-what-is-underneath"])
    }

    // MARK: What each guide is for

    @Test func theFirstGuideTeachesTheSplitOnOneShape() throws {
        let guide = try #require(TutorialCatalog.guide(id: "what-a-shape-is-made-of"))
        let anchors = guide.steps.map(\.anchor)
        // It has to point at BOTH sections, because the split is the lesson.
        #expect(anchors.contains(.panelSection("color")))
        #expect(anchors.contains(.panelSection("effects")))
        // And it has you pick the shape yourself first, so the panel filling up
        // is something you did rather than something that was already there.
        #expect(guide.steps.first?.advance.trigger == .layerSelected)
        // It picks the CARD rather than the button, and that is not a taste:
        // the button wears a label, so half the clicks aimed at it land on the
        // words and pick the text layer, whose colour row is not a Fill at all.
        // Measured on the probe on 2026-09-13, where the walk clicked the
        // middle of the button and the panel came up with no Fill row on it.
        #expect(guide.steps.first?.id == "pick-the-card")
    }

    @Test func theEffectsGuideReallyAddsTwoThings() throws {
        let guide = try #require(TutorialCatalog.guide(id: "add-a-shadow-a-border-a-glow"))
        let waits = guide.steps.filter(\.waits)
        #expect(waits.count >= 3, "adding an effect is the whole guide, so it waits on it")
        #expect(waits.allSatisfy { $0.advance.trigger == .layerSelected
                                   || $0.advance.trigger == .editMade })
        // The edge somebody used to look for under Appearance is named here,
        // in the list it actually lives in now.
        let copy = guide.steps.map(\.body).joined(separator: " ")
        #expect(copy.lowercased().contains("border"))
    }

    @Test func theLensGuideTeachesTheToolAndTheReasonPeopleWantIt() throws {
        let guide = try #require(TutorialCatalog.guide(id: "blur-what-is-underneath"))
        #expect(guide.steps.compactMap(\.advance.trigger).contains(.toolPicked(.lens)))
        let copy = guide.steps.map(\.body).joined(separator: " ")
        #expect(copy.contains("K"), "the guide never says which key picks the lens up")
        // The reason most people reach for this: hiding something before
        // sending a screenshot on. Said out loud, including what really leaves
        // the app.
        #expect(copy.lowercased().contains("pixelate"))
        #expect(guide.steps.contains { $0.body.lowercased().contains("flatten") })
    }

    @Test func theMixingGuideHasSomethingToMixWithBeforeItStarts() throws {
        let guide = try #require(TutorialCatalog.guide(id: "mix-with-what-is-below"))
        let sample = try #require(guide.sample)
        // A box lying over a picture, already there: the guide is about the one
        // setting, not about drawing a box first.
        let live = TutorialSampleScreen.layers(for: sample)
        #expect(live.count == 1, "the mixing sample brings \(live.count) layers to mix")
        #expect(sample.isFlattened, "there would be nothing under the box worth mixing with")
        #expect(guide.steps.first?.advance.trigger == .layerSelected)
        let copy = guide.steps.map(\.body).joined(separator: " ")
        #expect(copy.contains("Multiply"))
    }

    // MARK: The samples this track added

    @Test func theAccountScreenIsAPictureWithSomethingWorthHidingOnIt() {
        let picture = TutorialSampleScreen.pictureLayers(for: .accountScreen)
        #expect(picture.count >= 6, "too plain to be a screenshot somebody would send")
        // A real address, so the blur guide is teaching the thing people
        // actually do rather than blurring a heading.
        #expect(picture.contains { ($0.text?.string ?? "").contains("@") })
        // Nothing live on top: it is a picture, exactly like a capture.
        #expect(TutorialSampleScreen.layers(for: .accountScreen).isEmpty)
    }

    @Test func theTintedScreenIsTheSamePictureWithOneBoxOverIt() {
        #expect(TutorialSampleScreen.pictureLayers(for: .tintedScreen).map(\.name)
                == TutorialSampleScreen.pictureLayers(for: .accountScreen).map(\.name))
        let live = TutorialSampleScreen.layers(for: .tintedScreen)
        #expect(live.count == 1)
        let box = live[0]
        // Solid and plain: it has to COVER the row it lies on, so that changing
        // one setting is visibly the whole difference.
        #expect(box.annotation?.fillColorHex != nil)
        #expect(box.style.blendMode == .normal)
        #expect(box.style.opacity == 1)
    }

    @Test func theBoxLiesOverSomethingRatherThanBesideIt() throws {
        // The mixing lesson is "the words come back through it", which needs
        // the box to be ON a row of words.
        let box = try #require(TutorialSampleScreen.layers(for: .tintedScreen).first)
        let words = TutorialSampleScreen.pictureLayers(for: .accountScreen)
            .filter { ($0.text?.string ?? "").contains("@") }
        #expect(words.contains { $0.frame.intersects(box.frame) })
    }
}
