import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The Building UI track: how to build a screen rather than annotate one.
///
/// Four guides in the order a screen gets built. Draw the screen, hand it the
/// spacing, give it room and the columns you design to, and line up by hand
/// whatever is left over.
///
/// Everything here is a fact about the DATA, because that is all a guide is.
/// That each anchor really turns up in a live window is proved by the walks
/// (`Scripts/playtest/tutorial-frames-are-screens-walk.json` and its three
/// neighbours).
@Suite("Tutorials: the Building UI track")
struct TutorialBuildingUITrackTests {

    private var building: [TutorialGuide] { TutorialCatalog.guides(in: .buildingUI) }

    // MARK: The track itself

    @Test func theTrackRunsFromDrawingAScreenToLiningUpWhatIsLeft() {
        let ids = building.map(\.id)
        #expect(ids == ["frames-are-screens", "let-a-screen-arrange-itself",
                        "padding-and-columns", "line-things-up"])
    }

    @Test func everyGuideInTheTrackIsShortEnoughToFinishInOneSitting() {
        for guide in building {
            #expect(guide.minutes <= 3, "\(guide.id) claims \(guide.minutes) minutes")
            #expect(guide.steps.count <= 8, "\(guide.id) has \(guide.steps.count) steps")
            #expect(guide.steps.count >= 3, "\(guide.id) has \(guide.steps.count) steps")
        }
    }

    @Test func everyGuideClaimsATimeItCanActuallyBeFinishedIn() {
        for guide in building {
            #expect(TutorialLength.claimIsHonest(for: guide),
                    "\(guide.id) claims \(guide.minutes) min, work is \(Int(TutorialLength.estimatedSeconds(for: guide)))s")
        }
    }

    @Test func nothingInTheTrackTeachesOverYourOwnPicture() {
        // Every guide here draws, stacks, pads or deletes something, and doing
        // any of that to somebody's own work while showing them round is the
        // one thing a tutorial may never do.
        for guide in building {
            #expect(guide.sample != nil, "\(guide.id) would teach over whatever you had open")
            #expect(guide.sample?.isFlattened == false,
                    "\(guide.id) brings a picture, and a screen cannot be built out of pixels")
        }
    }

    @Test func aStepThatPointsIntoThePanelOpensThePanelFirst() {
        for guide in building {
            for step in guide.steps where step.anchor.panelSectionID != nil {
                #expect(step.prepare.contains(.showPanel),
                        "\(guide.id)/\(step.id) points into the panel without opening it")
                #expect(step.prepare.contains(.revealTarget),
                        "\(guide.id)/\(step.id) points into the panel without scrolling to it")
            }
        }
    }

    @Test func noGuideEndsByVanishingOnYou() {
        for guide in building {
            #expect(guide.steps.last?.waits == false,
                    "\(guide.id) ends on a step that waits, so it vanishes rather than finishing")
        }
    }

    @Test func everyGuideHasYouBuildSomethingRatherThanReadSixCards() {
        for guide in building {
            let waits = guide.steps.filter(\.waits).count
            #expect(waits >= 3, "\(guide.id) waits on you \(waits) times")
        }
    }

    // MARK: The sections these guides point into

    @Test func everySectionTheTrackRingsIsOneTheAppPromises() {
        // The two this track added are the ones that only exist while a SCREEN
        // is the thing selected, which is why every guide that rings them picks
        // the screen first.
        let promised = Set(TutorialAnchor.all)
        for guide in building {
            for step in guide.steps {
                #expect(promised.contains(step.anchor),
                        "\(guide.id)/\(step.id) points at \(step.anchor.name)")
            }
        }
        #expect(TutorialAnchor.knownPanelSections.contains("frame"))
        #expect(TutorialAnchor.knownPanelSections.contains("columns"))
    }

    @Test func aStepRingingASectionOnlyAScreenHasPicksTheScreenFirst() {
        // Frame and Columns are drawn only while the selection is a screen or
        // something on one. A step ringing either of them before anything has
        // been picked is a step pointing at a section that is not in the panel.
        let screenOnly: Set<String> = ["frame", "columns"]
        for guide in building {
            var picked = false
            for step in guide.steps {
                if step.advance.trigger == .layerSelected { picked = true }
                // Drawing a screen leaves it selected, which is the other way
                // in and the one the first guide uses.
                if step.anchor == .canvas, step.advance.trigger == .editMade { picked = true }
                guard let section = step.anchor.panelSectionID,
                      screenOnly.contains(section) else { continue }
                #expect(picked,
                        "\(guide.id)/\(step.id) rings \(section) before anything is picked")
            }
        }
    }

    // MARK: What the copy is allowed to say

    @Test func theCopyNamesKeysRatherThanMenuRows() {
        for guide in building {
            for step in guide.steps {
                #expect(!step.body.contains("\u{25B8}"),
                        "\(guide.id)/\(step.id) names a menu row, which can move under a flag")
            }
        }
    }

    @Test func theTrackSaysScreenRatherThanArtboard() {
        // The app has never had an artboard. A frame is a screen everywhere it
        // is spoken about, and a guide teaches the word the product uses.
        for guide in building {
            let copy = (guide.title + " " + guide.summary + " "
                        + guide.steps.map { $0.title + " " + $0.body }.joined(separator: " "))
                .lowercased()
            #expect(!copy.contains("artboard"), "\(guide.id) says artboard")
            #expect(!copy.contains("auto layout"),
                    "\(guide.id) says auto layout, which is not a word on any control")
        }
    }

    @Test func theWholeTrackPassesTheCopyRules() {
        for guide in building {
            #expect(TutorialCopyRules.problems(in: guide) == [], "\(guide.id)")
        }
    }

    // MARK: Flags

    @Test func everyGuideSaysWhichFeatureItNeeds() {
        let known = Set(FeatureCatalog.flags(for: .next).map(\.name))
        for guide in building {
            #expect(!guide.requires.isEmpty, "\(guide.id) names no feature")
            for flag in guide.requires {
                #expect(known.contains(flag),
                        "\(guide.id) needs \(flag), which is not a feature the app has")
            }
        }
    }

    @Test func everyGuideAboutAScreenAsksForTheWholeChainItStandsOn() {
        // A screen is a group with a size, so frames need groups. The app
        // resolves that chain itself, but the catalogue asks flag by flag, so a
        // guide naming only the last link would still be offered to somebody
        // who switched off the first.
        for guide in building where guide.sample != .crookedBoxes {
            #expect(guide.requires.contains(FeatureCatalog.framesFlag), "\(guide.id)")
            #expect(guide.requires.contains(FeatureCatalog.layerGroupsFlag), "\(guide.id)")
        }
    }

    @Test func theTwoGuidesThatTypeIntoLayoutAskForIt() {
        // Arrangement, Gap and Padding are all in the Layout section, and that
        // whole section is behind `next-auto-layout`. A guide that asked you to
        // type into rows that are not there is the exact failure the flags
        // exist to stop.
        for id in ["let-a-screen-arrange-itself", "padding-and-columns"] {
            let guide = TutorialCatalog.guide(id: id)
            #expect(guide?.requires.contains(FeatureCatalog.autoLayoutFlag) == true, "\(id)")
        }
    }

    @Test func switchingScreensOffTakesEveryGuideAboutOneAway() {
        let shown = TutorialCatalog.guides(enabled: { $0 != FeatureCatalog.framesFlag })
        #expect(shown.allSatisfy { $0.id != "frames-are-screens" })
        #expect(shown.allSatisfy { $0.id != "let-a-screen-arrange-itself" })
        #expect(shown.allSatisfy { $0.id != "padding-and-columns" })
        // Lining layers up has nothing to do with screens, so it stays.
        #expect(shown.contains { $0.id == "line-things-up" })
        #expect(TutorialCatalog.populatedTracks(in: shown).contains(.buildingUI))
    }

    @Test func switchingLiningUpOffLeavesTheScreenGuidesAlone() {
        let shown = TutorialCatalog.guides(enabled: { $0 != FeatureCatalog.alignLayersFlag })
        #expect(shown.allSatisfy { $0.id != "line-things-up" })
        #expect(shown.contains { $0.id == "frames-are-screens" })
    }

    @Test func switchingEveryScreenFeatureOffEmptiesTheTrackCompletely() {
        let off: Set<String> = [FeatureCatalog.framesFlag, FeatureCatalog.alignLayersFlag]
        let shown = TutorialCatalog.guides(enabled: { !off.contains($0) })
        #expect(shown.allSatisfy { $0.track != .buildingUI })
        #expect(!TutorialCatalog.populatedTracks(in: shown).contains(.buildingUI))
        #expect(TutorialCatalog.populatedTracks(in: shown).contains(.basics))
    }

    // MARK: What each guide is for

    @Test func theFirstGuideHasYouDrawAScreenAndThenDrawOnIt() throws {
        let guide = try #require(TutorialCatalog.guide(id: "frames-are-screens"))
        let ids = guide.steps.map(\.id)
        #expect(ids.firstIndex(of: "drag-one-out")! < ids.firstIndex(of: "draw-a-card")!,
                "there is nothing to draw on until the screen exists")
        // It opens on a page with nothing on it, or there is nothing to draw.
        #expect(guide.sample == .blankPage)
        #expect(TutorialSampleScreen.layers(for: .blankPage).isEmpty)
        // The frame tool is at the end of the tool bar and nobody finds it by
        // accident, so the guide hands it over rather than assuming it.
        #expect(guide.steps.contains { $0.advance.trigger == .toolPicked(.frame) })
        // And it ends in the layers list, because what the guide is really
        // teaching is that the card went INSIDE the screen.
        #expect(guide.steps.last?.anchor == .panelSection("layers"))
    }

    @Test func theArrangingGuidePicksTheScreenBeforeItTypesIntoLayout() throws {
        let guide = try #require(TutorialCatalog.guide(id: "let-a-screen-arrange-itself"))
        let ids = guide.steps.map(\.id)
        #expect(ids.firstIndex(of: "pick-the-screen")! < ids.firstIndex(of: "stack-them")!)
        #expect(ids.firstIndex(of: "stack-them")! < ids.firstIndex(of: "type-a-gap")!,
                "a gap means nothing until something is arranging itself")
        // The last thing it does is take something away, and the point of the
        // guide is that nothing had to be tidied up after.
        #expect(guide.steps.contains { $0.id == "take-one-away" && $0.waits })
        #expect(guide.sample == .handPlacedScreen)
    }

    @Test func thePaddingGuideTeachesTheTwoTogetherAndInThatOrder() throws {
        // The two were a real source of confusion until they were connected:
        // a screen has ONE inset from its edge, and the columns are drawn
        // inside it. So the room comes first and the columns follow it.
        let guide = try #require(TutorialCatalog.guide(id: "padding-and-columns"))
        let ids = guide.steps.map(\.id)
        #expect(ids.firstIndex(of: "give-it-room")! < ids.firstIndex(of: "show-the-columns")!)
        #expect(guide.steps.contains { $0.id == "columns-start-at-the-padding" })
        let copy = guide.steps.map(\.body).joined(separator: " ").lowercased()
        #expect(copy.contains("padding"), "the guide never names the room it is about")
        #expect(guide.sample == .tightScreen)
    }

    @Test func theLiningUpGuideTeachesBothKeysAndShowsTheRowOnce() throws {
        let guide = try #require(TutorialCatalog.guide(id: "line-things-up"))
        let copy = guide.steps.map(\.body).joined(separator: " ")
        // An edge and a spacing: the two halves of the feature, and the two
        // different key shapes, so neither is a surprise later.
        #expect(copy.contains("\u{2325}W"), "the align key is never named")
        #expect(copy.contains("\u{2303}\u{2325}H"), "the spacing key is never named")
        // The panel is shown once, because somebody has to know the row is
        // there, and only once, because a person lining up a screen has a hand
        // on the mouse.
        let panel = guide.steps.filter { $0.anchor.panelSectionID != nil }
        #expect(panel.count == 1, "the guide sends you to the panel \(panel.count) times")
        #expect(panel.first?.anchor == .panelSection("arrange"))
        #expect(guide.sample == .crookedBoxes)
    }

    // MARK: The samples the track brings

    @Test func everySampleLeavesACanvasStepSomewhereClearToPutItsCard() throws {
        // A step pointing at the whole canvas has no side of the canvas to sit
        // beside, so its card is drawn INSIDE the picture. It used to go across
        // the top whatever was under it, and every sample here had to leave a
        // band of empty page for it. Now it looks for the quiet part, so what a
        // sample owes is only that quiet space exists.
        //
        // The window a tutorial opens at, modelled: the canvas is the window
        // bar the panel and the title bar, and the page is drawn in the middle
        // of it at its own size.
        let window = CGRect(x: 0, y: 0, width: 1280, height: 900)
        let canvas = CGRect(x: 0, y: 52, width: 960, height: 848)
        let page = CGRect(x: canvas.midX - TutorialSampleScreen.canvasSize.width / 2,
                          y: canvas.midY - TutorialSampleScreen.canvasSize.height / 2,
                          width: TutorialSampleScreen.canvasSize.width,
                          height: TutorialSampleScreen.canvasSize.height)
        // A wordy step at the width the card is drawn at.
        let card = CGSize(width: 320, height: 150)
        for sample in [TutorialSample.handPlacedScreen, .tightScreen, .crookedBoxes] {
            let drawn = TutorialSampleScreen.layers(for: sample)
                .map { $0.frame.offsetBy(dx: page.minX, dy: page.minY) }
            let placed = TutorialCalloutLayout.place(anchor: canvas, size: card,
                                                     container: window, busy: drawn)
            for box in drawn {
                #expect(!placed.frame.intersects(box),
                        "\(sample): the card landed on \(box)")
            }
            #expect(canvas.contains(placed.frame), "\(sample): the card left the canvas")
        }
    }

    @Test func noScreenSampleHangsOffItsPage() throws {
        for sample in [TutorialSample.handPlacedScreen, .tightScreen] {
            let screen = try #require(TutorialSampleScreen.layers(for: sample).first)
            #expect(screen.frame.minY >= 0, "\(sample)'s screen starts above the page")
            #expect(screen.frame.maxY <= TutorialSampleScreen.canvasSize.height,
                    "\(sample)'s screen hangs off the bottom of the page")
        }
    }

    @Test func theScreenSamplesAreRealScreensWithASurfaceAndAName() throws {
        for sample in [TutorialSample.handPlacedScreen, .tightScreen] {
            let screen = try #require(TutorialSampleScreen.layers(for: sample).first)
            #expect(screen.isFrame, "\(sample) does not bring a screen")
            #expect(screen.group?.backgroundHex != nil,
                    "\(sample)'s screen paints nothing, so it has no edge on the page")
            #expect(screen.name == "Home", "a screen a step asks you to click by name")
            #expect(screen.children.count == 3)
        }
    }

    @Test func theArrangingSamplesCardsWerePlacedByEyeAndNotEvenly() throws {
        // The guide's first line says they were nudged into place, and its
        // third says handing it to the screen tidies that up. Evenly spaced
        // cards would make both sentences false.
        let screen = try #require(TutorialSampleScreen.layers(for: .handPlacedScreen).first)
        #expect(screen.group?.layout == nil, "the guide is the thing that arranges it")
        let tops = screen.children.map(\.frame.minY)
        let gaps = zip(tops.dropFirst(), tops).map { $0 - $1 }
        #expect(Set(gaps).count > 1, "the cards are already evenly spaced")
    }

    @Test func thePaddingSamplesScreenKeepsNoRoomAndItsCardsFillIt() throws {
        // Both halves matter. No room, or typing a number into Padding shows
        // nothing; cards that stretch, or the same number slides them sideways
        // and the screen clips them at the far edge instead of drawing them in.
        let screen = try #require(TutorialSampleScreen.layers(for: .tightScreen).first)
        #expect(screen.group?.layout?.padding == GroupPadding.none)
        #expect(screen.group?.layout?.kind == .stack)
        #expect(screen.group?.contentPlacement?.horizontal == .stretch)
        for card in screen.children {
            #expect(card.frame.width == screen.frame.width,
                    "\(card.name) does not run the full width, so it is not flush to the edges")
        }
    }

    @Test func typingRoomIntoThePaddingSampleBringsItsCardsInOnBothSides() throws {
        // The guide's third step promises this in so many words, so it is
        // checked rather than hoped for.
        var document = PhotonzDocument(canvasSize: TutorialSampleScreen.canvasSize)
        document.layers = TutorialSampleScreen.layers(for: .tightScreen)
        let id = try #require(document.layers.first?.id)
        document.updateGroupLayout(id: id) { $0.padding = GroupPadding(24) }
        document.reflowLayouts()
        let screen = try #require(document.layer(id: id))
        for card in screen.children {
            #expect(card.frame.minX == 24, "\(card.name) did not come in from the left")
            #expect(card.frame.width == screen.frame.width - 48,
                    "\(card.name) kept its width, so it hangs over the far edge")
        }
    }

    @Test func theLiningUpSampleIsCrookedOnBothCountsAndHasRoomToSelectFrom() throws {
        let boxes = TutorialSampleScreen.layers(for: .crookedBoxes)
        #expect(boxes.count == 3)
        #expect(Set(boxes.map(\.frame.minY)).count == 3, "two of them already share an edge")
        let gaps = zip(boxes.dropFirst(), boxes).map { $0.frame.minX - $1.frame.maxX }
        #expect(Set(gaps).count > 1, "the boxes are already evenly spaced")
        // The guide asks you to start a selection on the clear page to the LEFT
        // of them, so there has to be clear page there to start on. A canvas
        // step's card looks for quiet space too, and it prefers the top of the
        // picture, which is why the drag is asked for from the side.
        let left = boxes.map(\.frame.minX).min() ?? 0
        #expect(left >= 80, "there is no clear page beside the boxes to drag from")
    }
}
