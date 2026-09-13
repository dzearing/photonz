import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The Colours and Styles track: name a colour or a piece of type once, use the
/// name everywhere, and change it in one place.
///
/// Four guides. The first two are the whole bargain for colour (make a name,
/// then change the name and watch everything wearing it move), the third is the
/// same bargain for type, and the fourth is the shelf all of it lands on.
///
/// Everything here is a fact about the DATA, because that is all a guide is.
/// That each anchor really turns up in a live window is proved by the walks.
@Suite("Tutorials: the Colours and Styles track")
struct TutorialColorsAndStylesTrackTests {

    private var track: [TutorialGuide] { TutorialCatalog.guides(in: .colorsAndStyles) }

    // MARK: The track itself

    @Test func theTrackRunsFromNamingOneColourToTheShelfItAllLandsOn() {
        let ids = track.map(\.id)
        #expect(ids == ["save-a-colour-as-a-style", "change-it-everywhere",
                        "text-styles", "the-library"])
    }

    @Test func everyGuideInTheTrackIsShortEnoughToFinishInOneSitting() {
        for guide in track {
            #expect(guide.minutes <= 3, "\(guide.id) claims \(guide.minutes) minutes")
            #expect(guide.steps.count <= 8, "\(guide.id) has \(guide.steps.count) steps")
            #expect(guide.steps.count >= 3, "\(guide.id) has \(guide.steps.count) steps")
        }
    }

    @Test func theTimeOnEachCardIsMeasuredRatherThanGuessed() {
        for guide in track {
            let worth = Int(TutorialLength.estimatedSeconds(for: guide))
            #expect(TutorialLength.claimIsHonest(for: guide),
                    "\(guide.id) claims \(guide.minutes) min and is worth \(worth) seconds")
        }
    }

    @Test func nothingInTheTrackTeachesOverYourOwnPicture() {
        // Every guide here repaints or re-sets something, and doing that to
        // somebody's own work while showing them round is the one thing a
        // tutorial may never do.
        for guide in track {
            #expect(guide.sample != nil, "\(guide.id) would teach over whatever you had open")
        }
    }

    @Test func theWholeTrackTeachesOnOneScreen() {
        // One sample rather than four. Somebody doing the track back to back
        // sees the same card each time, so the second guide starts on ground
        // the first one already covered rather than on a fresh unfamiliar
        // picture.
        for guide in track {
            #expect(guide.sample == .stylesScreen, "\(guide.id) brings \(String(describing: guide.sample))")
        }
    }

    @Test func theTracksSampleStaysLiveBecauseYouCannotRestylePixels() {
        // The redlining samples are flattened on purpose: Measure reads the
        // picture. This track is the opposite. A colour you can name is a
        // colour on a LAYER, so a flattened sample would leave every guide
        // here with nothing to pick.
        #expect(TutorialSample.stylesScreen.isFlattened == false)
        #expect(TutorialSampleScreen.pictureLayers(for: .stylesScreen).isEmpty)
    }

    @Test func noGuideEndsByVanishingOnYou() {
        for guide in track {
            #expect(guide.steps.last?.waits == false,
                    "\(guide.id) ends on a step that waits, so it vanishes rather than finishing")
        }
    }

    @Test func everyGuideHasYouDoSomethingRatherThanReadFiveCards() {
        for guide in track {
            let waits = guide.steps.filter(\.waits).count
            #expect(waits >= 2, "\(guide.id) waits on you \(waits) times")
        }
    }

    // MARK: What a step is allowed to point at

    @Test func aStepThatPointsIntoThePanelOpensThePanelFirst() {
        for guide in track {
            for step in guide.steps where step.anchor.panelSectionID != nil {
                #expect(step.prepare.contains(.showPanel),
                        "\(guide.id)/\(step.id) points into the panel without opening it")
                #expect(step.prepare.contains(.revealTarget),
                        "\(guide.id)/\(step.id) points into the panel without scrolling to it")
            }
        }
    }

    @Test func aStepThatPointsAtTheShelfBringsTheShelfOnScreen() {
        // The Library is a panel group of its own and it can be switched off
        // in the dock. A step ringing it without asking for it would ring
        // whatever had scrolled into its place.
        for guide in track {
            for step in guide.steps where step.anchor == .panelSection("library") {
                #expect(step.prepare.contains(.showLibrary),
                        "\(guide.id)/\(step.id) points at the Library without showing it")
            }
        }
    }

    @Test func nothingInTheTrackAsksYouToDrawAShapeFirst() {
        // The Looks track's rule, and it holds here for the same reason: the
        // shapes share one slot in the tool bar and the slot wears whichever
        // you used last, so a step pointing at the rectangle points at nothing
        // on an app whose slot is wearing the line. Every guide here restyles
        // what its sample brought.
        for guide in track {
            for step in guide.steps {
                for shape in [Tool.rectangle, .ellipse, .line] {
                    #expect(step.anchor != .tool(shape),
                            "\(guide.id)/\(step.id) points at a tool that shares a slot")
                }
            }
        }
    }

    @Test func everyAnchorInTheTrackIsOneTheAppPromises() {
        #expect(TutorialCatalogCheck.problems(in: track).isEmpty,
                "\(TutorialCatalogCheck.problems(in: track))")
    }

    // MARK: The features a guide leans on

    @Test func everyGuideAsksForTheShelfAndTheStylesItTeaches() {
        // A saved colour and a saved text style both live on the Library's
        // Styles shelf, and both switches can be turned off in Experiments. A
        // guide offered with either off would ring a button that is not there,
        // so it is left out of the menu entirely instead.
        for guide in track {
            #expect(guide.requires.contains(FeatureCatalog.libraryFlag),
                    "\(guide.id) does not ask for the Library")
            #expect(guide.requires.contains(FeatureCatalog.stylesFlag),
                    "\(guide.id) does not ask for styles")
        }
    }

    @Test func aGuideThatAsksYouToDragAStyleAsksForDragging() {
        // Carrying a colour or a style by hand is its own switch
        // (`next-color-drag`), and with it off there is nothing to pick up.
        // Only the two guides that really ask for a drag carry the
        // requirement, so switching dragging off does not cost somebody the
        // whole track.
        let dragging = track.filter { $0.requires.contains(FeatureCatalog.colorDragFlag) }
        #expect(dragging.map(\.id) == ["text-styles", "the-library"])
        for guide in dragging {
            #expect(guide.steps.contains { $0.body.lowercased().contains("drag") },
                    "\(guide.id) asks for dragging and never mentions it")
        }
        for guide in track where !guide.requires.contains(FeatureCatalog.colorDragFlag) {
            #expect(guide.steps.allSatisfy { !$0.body.lowercased().contains("drag") },
                    "\(guide.id) asks you to drag without asking for dragging")
        }
    }

    @Test func switchingStylesOffTakesTheWholeShelfAway() {
        // Nothing here means anything without saved styles, so with that
        // switch off the track is not dimmed or half offered: it is not in the
        // menu and not in the window, and the Colours and Styles submenu goes
        // with it.
        let shown = TutorialCatalog.guides(enabled: { $0 != FeatureCatalog.stylesFlag })
        #expect(!shown.contains { $0.track == .colorsAndStyles })
        #expect(!TutorialCatalog.populatedTracks(in: shown).contains(.colorsAndStyles))
    }

    @Test func switchingDraggingOffCostsTwoGuidesAndNotTheTrack() {
        // Saving a colour and changing it everywhere are menu work and survive
        // with dragging off. Only the two guides that ask you to carry
        // something go, and the shelf stays on the menu.
        let shown = TutorialCatalog.guides(enabled: { $0 != FeatureCatalog.colorDragFlag })
        let left = shown.filter { $0.track == .colorsAndStyles }.map(\.id)
        #expect(left == ["save-a-colour-as-a-style", "change-it-everywhere"])
        #expect(TutorialCatalog.populatedTracks(in: shown).contains(.colorsAndStyles))
    }

    // MARK: What the copy is allowed to say

    @Test func theCopyReadsLikeProductCopy() {
        for guide in track {
            #expect(TutorialCopyRules.problems(in: guide).isEmpty,
                    "\(TutorialCopyRules.problems(in: guide))")
        }
    }

    @Test func aGuideNamesOnlyLayersItsSampleReallyBrought() {
        // The Components track's rule. A step that says "click Privacy Switch"
        // over a picture with no such layer is a step nobody can follow, and
        // the sample is the only thing that decides what is on the page.
        let names = Set(TutorialSampleScreen.layers(for: .stylesScreen).map(\.name))
        let named = ["Notifications Switch", "Privacy Switch", "Notifications",
                     "Privacy", "Storage"]
        for name in named {
            #expect(names.contains(name), "the sample has no layer called \(name)")
        }
    }

    @Test func theSampleGivesTheTrackThreeOfEachToWorkWith() {
        // Three is the smallest number that can show what a name does: two
        // wearing it and one that never had it. Two would only show a change.
        let layers = TutorialSampleScreen.layers(for: .stylesScreen)
        let switches = layers.filter { $0.name.hasSuffix("Switch") }
        #expect(switches.count == 3, "the sample has \(switches.count) switches")
        let fills = Set(switches.compactMap { layer -> String? in
            if case .annotation(let annotation) = layer.content { return annotation.fillColorHex }
            return nil
        })
        #expect(fills.count == 1, "the switches are painted \(fills.count) different colours")
        // The headings are the other way round on purpose. One is set the way
        // a heading should be and the other two are the same words typed in a
        // hurry, so every step of the text guide CHANGES something you can
        // see. Three already alike made that whole guide invisible.
        func treatment(_ name: String) -> String? {
            guard let layer = layers.first(where: { $0.name == name }),
                  case .text(let text) = layer.content else { return nil }
            return "\(text.fontName) \(text.fontSize) \(text.weight) \(text.colorHex)"
        }
        let good = try! #require(treatment("Notifications"))
        let second = try! #require(treatment("Privacy"))
        let third = try! #require(treatment("Storage"))
        #expect(good != second, "nothing visibly changes when the name is put on the second one")
        #expect(second == third, "the two unset headings are not set alike")
    }

    @Test func theSwitchAStepAsksYouToClickCarriesNoWordsOnIt() {
        // The trap the Looks track found and the Components track found again
        // one level down: a click aimed at a box with a label on it lands on
        // the label and picks the text layer. Every target this track asks for
        // by click is a switch, and a switch has nothing written on it.
        let layers = TutorialSampleScreen.layers(for: .stylesScreen)
        for layer in layers where layer.name.hasSuffix("Switch") {
            let overlapping = layers.filter { other in
                other.id != layer.id && other.frame.intersects(layer.frame)
                    && { if case .text = other.content { return true } else { return false } }()
            }
            #expect(overlapping.isEmpty,
                    "\(layer.name) has \(overlapping.count) pieces of text lying over it")
        }
    }

    // MARK: The shape of each guide

    @Test func theFirstGuideEndsWithTheRowWearingTheNameItJustSaved() {
        let guide = try! #require(TutorialCatalog.guide(id: "save-a-colour-as-a-style"))
        #expect(guide.steps.map(\.anchor).contains(.panelSection("library")),
                "saving a colour never shows you where it landed")
        #expect(guide.steps.contains { $0.anchor == .panelSection("color") && $0.waits },
                "nothing in the guide has you actually save one")
    }

    @Test func theSecondGuideEndsOnTheLayerThatDidNotMove() {
        // The payoff of the whole track, and it needs the layer that never had
        // the name: two switches repainting together says "an edit reached two
        // layers", and only the third one standing still says "because those
        // two follow a name and this one does not".
        let guide = try! #require(TutorialCatalog.guide(id: "change-it-everywhere"))
        let last = try! #require(guide.steps.last)
        #expect(last.anchor == .canvas)
        #expect(last.body.contains("third"), "the closing step is \(last.body)")
    }

    @Test func theTextGuideTeachesBothWaysToPutAStyleOnSomething() {
        let guide = try! #require(TutorialCatalog.guide(id: "text-styles"))
        #expect(guide.steps.contains { $0.anchor == .panelSection("text") && $0.waits },
                "the text guide never uses the Style row")
        #expect(guide.steps.contains { $0.anchor == .panelSection("library") && $0.waits },
                "the text guide never drags a style off the shelf")
    }

    @Test func theLibraryGuideSaysWhatEachShelfHolds() {
        let guide = try! #require(TutorialCatalog.guide(id: "the-library"))
        let words = guide.steps.map(\.body).joined(separator: " ")
        for scope in ["Media", "Comps", "Styles", "Systems"] {
            #expect(words.contains(scope), "the Library guide never mentions \(scope)")
        }
    }
}
