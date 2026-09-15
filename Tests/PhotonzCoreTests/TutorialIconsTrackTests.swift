import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The Icons track: drawing an icon end to end rather than touring the Pen,
/// and then making it move.
///
/// Nine guides, in the order the job is done in. Set up the square the icon
/// will really be used in, draw the outline with the Pen, reshape it, learn the
/// other way into an outline, and get a file out that an icon set will take.
/// Then tell it to move, time it, let its two parts move at different moments,
/// and hand it over still swinging.
///
/// Everything here is a fact about the DATA, because that is all a guide is.
/// That each anchor really turns up in a live window is proved by the walks
/// (`Scripts/playtest/tutorial-start-on-an-icon-frame-walk.json` and its four
/// neighbours).
@Suite("Tutorials: the Icons track")
struct TutorialIconsTrackTests {

    private var icons: [TutorialGuide] { TutorialCatalog.guides(in: .icons) }

    // MARK: The track itself

    @Test func theTrackRunsFromAnEmptyFrameToAFileYouCanHandOver() {
        let ids = icons.map(\.id)
        #expect(ids == ["start-on-an-icon-frame", "draw-it-with-the-pen",
                        "reshape-what-you-drew", "turn-a-shape-into-a-path",
                        "get-a-clean-svg-out",
                        // And then the same icon, moving. The still hand-off
                        // ends the drawing job; animating is the next chapter
                        // and it has a hand-off of its own at the end of it.
                        "make-something-move", "get-the-timing-right",
                        "two-parts-out-of-phase", "export-an-animated-svg"])
    }

    @Test func theTrackHasANameAndABlurbOfItsOwn() {
        #expect(TutorialTrack.icons.title == "Icons")
        #expect(!TutorialTrack.icons.blurb.isEmpty)
        #expect(TutorialCopyRules.problems(in: TutorialTrack.icons.blurb,
                                           label: "icons blurb") == [])
    }

    @Test func everyGuideInTheTrackIsShortEnoughToFinishInOneSitting() {
        for guide in icons {
            #expect(guide.minutes <= 3, "\(guide.id) claims \(guide.minutes) minutes")
            #expect(guide.steps.count <= 8, "\(guide.id) has \(guide.steps.count) steps")
            #expect(guide.steps.count >= 3, "\(guide.id) has \(guide.steps.count) steps")
        }
    }

    @Test func everyGuideClaimsATimeItCanActuallyBeFinishedIn() {
        for guide in icons {
            #expect(TutorialLength.claimIsHonest(for: guide),
                    "\(guide.id) claims \(guide.minutes) min, work is \(Int(TutorialLength.estimatedSeconds(for: guide)))s")
        }
    }

    @Test func nothingInTheTrackTeachesOverYourOwnPicture() {
        // Every guide here draws, reshapes, converts or exports something, and
        // doing any of that to somebody's own work while showing them round is
        // the one thing a tutorial may never do.
        for guide in icons {
            #expect(guide.sample != nil, "\(guide.id) would teach over whatever you had open")
            #expect(guide.sample?.isFlattened == false,
                    "\(guide.id) brings a picture, and an icon cannot be drawn out of pixels")
        }
    }

    @Test func everyGuideAfterTheFirstBringsTheFrameWithIt() {
        // The first guide has you MAKE the frame, so it must arrive without
        // one. The rest teach inside it, so they must arrive with one.
        #expect(TutorialCatalog.guide(id: "start-on-an-icon-frame")?.sample == .blankPage)
        let inAFrame: Set<TutorialSample> = [.iconFrame, .iconPath, .iconBox, .iconBell,
                                             .iconBellSwinging, .iconBellInStep,
                                             .iconBellRinging]
        for guide in icons where guide.id != "start-on-an-icon-frame" {
            let sample = guide.sample
            #expect(sample.map(inAFrame.contains) == true,
                    "\(guide.id) teaches inside an icon frame but does not bring one")
        }
    }

    @Test func aStepThatPointsIntoThePanelOpensThePanelFirst() {
        for guide in icons {
            for step in guide.steps where step.anchor.panelSectionID != nil {
                #expect(step.prepare.contains(.showPanel),
                        "\(guide.id)/\(step.id) points into the panel without opening it")
                #expect(step.prepare.contains(.revealTarget),
                        "\(guide.id)/\(step.id) points into the panel without scrolling to it")
            }
        }
    }

    @Test func noGuideEndsByVanishingOnYou() {
        for guide in icons {
            #expect(guide.steps.last?.waits == false,
                    "\(guide.id) ends on a step that waits, so it vanishes rather than finishing")
        }
    }

    @Test func everyGuideHasYouDoSomethingRatherThanReadSixCards() {
        for guide in icons {
            let waits = guide.steps.filter(\.waits).count
            #expect(waits >= 2, "\(guide.id) waits on you \(waits) times")
        }
    }

    // MARK: Pointing at a sheet

    @Test func aStepThatPointsAtASheetWaitsForThatSheetFirst() {
        // A sheet's name only answers while the sheet is up. A step pointing at
        // one before anything opened it is a card pointing at nothing, which is
        // the exact failure the live check exists to catch.
        for guide in icons {
            var open: Set<TutorialAnchor.Dialog> = []
            for step in guide.steps {
                if case .waitsFor(.dialogOpened(let dialog)) = step.advance { open.insert(dialog) }
                for dialog in TutorialAnchor.Dialog.allCases
                where step.anchor == .dialog(dialog) {
                    #expect(open.contains(dialog),
                            "\(guide.id)/\(step.id) points at the \(dialog.rawValue) sheet before anything opens it")
                }
            }
        }
    }

    @Test func theSheetAnchorsAreOnesTheAppPromises() {
        let promised = Set(TutorialAnchor.all)
        #expect(promised.contains(.dialog(.newFrame)))
        #expect(promised.contains(.dialog(.export)))
    }

    @Test func everySectionAndControlTheTrackRingsIsOneTheAppPromises() {
        let promised = Set(TutorialAnchor.all)
        for guide in icons {
            for step in guide.steps {
                #expect(promised.contains(step.anchor),
                        "\(guide.id)/\(step.id) points at \(step.anchor.name)")
            }
        }
    }

    // MARK: What the copy is allowed to say

    @Test func theWholeTrackPassesTheCopyRules() {
        for guide in icons {
            #expect(TutorialCopyRules.problems(in: guide) == [], "\(guide.id)")
        }
    }

    @Test func theCopyNeverNamesAMenuPath() {
        // A row can move under a flag, and an arrow between menu names is the
        // shape that goes stale first. The two commands with no key of their
        // own are named in a sentence instead.
        for guide in icons {
            for step in guide.steps {
                #expect(!step.body.contains("\u{25B8}"),
                        "\(guide.id)/\(step.id) names a menu path")
            }
        }
    }

    @Test func theTrackSaysWhatTheProductSays() {
        // The app has no artboard and no nodes. A point is a point, a lever is
        // a lever, and a path is a path (`docs/design/vector-paths.md`).
        for guide in icons {
            let copy = (guide.title + " " + guide.summary + " "
                        + guide.steps.map { $0.title + " " + $0.body }.joined(separator: " "))
                .lowercased()
            #expect(!copy.contains("artboard"), "\(guide.id) says artboard")
            #expect(!copy.contains("node"), "\(guide.id) says node")
            #expect(!copy.contains("bezier"), "\(guide.id) says bezier")
        }
    }

    // MARK: Flags

    @Test func everyGuideSaysWhichFeatureItNeeds() {
        let known = Set(FeatureCatalog.flags(for: .next).map(\.name))
        for guide in icons {
            #expect(!guide.requires.isEmpty, "\(guide.id) names no feature")
            for flag in guide.requires {
                #expect(known.contains(flag),
                        "\(guide.id) needs \(flag), which is not a feature the app has")
            }
        }
    }

    @Test func everyGuideAsksForTheWholeChainTheIconFrameStandsOn() {
        // An icon frame is a frame, and a frame is a group with a size. The app
        // resolves that chain itself, but the catalogue asks flag by flag, so a
        // guide naming only the last link would still be offered to somebody
        // who switched off the first.
        for guide in icons {
            #expect(guide.requires.contains(FeatureCatalog.iconFramesFlag), "\(guide.id)")
            #expect(guide.requires.contains(FeatureCatalog.framesFlag), "\(guide.id)")
            #expect(guide.requires.contains(FeatureCatalog.layerGroupsFlag), "\(guide.id)")
        }
    }

    @Test func switchingThePenOffTakesEveryGuideThatNeedsItAway() {
        // The first guide is about the frame, the grid and the keylines, none
        // of which is the Pen, so it stays. Everything after it draws, reshapes
        // or exports an outline, and all of that needs the Pen.
        let shown = TutorialCatalog.guides(enabled: { $0 != FeatureCatalog.penFlag })
        #expect(shown.contains { $0.id == "start-on-an-icon-frame" })
        for id in ["draw-it-with-the-pen", "reshape-what-you-drew",
                   "turn-a-shape-into-a-path", "get-a-clean-svg-out"] {
            #expect(shown.allSatisfy { $0.id != id }, "\(id) survived the Pen going off")
        }
        // The shelf itself survives, because one guide on it still stands up.
        #expect(TutorialCatalog.populatedTracks(in: shown).contains(.icons))
    }

    @Test func switchingIconFramesOffEmptiesTheTrackCompletely() {
        let shown = TutorialCatalog.guides(enabled: { $0 != FeatureCatalog.iconFramesFlag })
        #expect(shown.allSatisfy { $0.track != .icons })
        #expect(!TutorialCatalog.populatedTracks(in: shown).contains(.icons))
        #expect(TutorialCatalog.populatedTracks(in: shown).contains(.basics))
    }

    @Test func switchingSVGExportOffLeavesTheDrawingGuidesAlone() {
        let shown = TutorialCatalog.guides(enabled: { $0 != FeatureCatalog.svgExportFlag })
        #expect(shown.allSatisfy { $0.id != "get-a-clean-svg-out" })
        #expect(shown.contains { $0.id == "draw-it-with-the-pen" })
    }

    // MARK: What each guide is for

    @Test func theFirstGuideMakesTheFrameAndThenTurnsOnWhatKeepsItSharp() throws {
        let guide = try #require(TutorialCatalog.guide(id: "start-on-an-icon-frame"))
        let ids = guide.steps.map(\.id)
        #expect(ids.firstIndex(of: "take-twenty-four")! < ids.firstIndex(of: "show-the-grid")!,
                "there is nothing for the grid to be about until the frame exists")
        // The grid and the keylines are the point of the guide, so both are
        // waited on rather than described and hoped for.
        #expect(guide.steps.contains { $0.advance == .waitsFor(.gridShown) })
        #expect(guide.steps.contains { $0.advance == .waitsFor(.keylinesShown) })
        // It opens on a page with nothing on it, or there is nothing to make.
        #expect(guide.sample == .blankPage)
        #expect(TutorialSampleScreen.layers(for: .blankPage).isEmpty)
    }

    @Test func theDrawingGuideTeachesTheCurveAsItsOwnShape() throws {
        // Being unable to find the curve at all is what a real first session
        // with the Pen ran aground on, so it is not a sentence tacked onto the
        // step about clicking corners: it is a shape of its own, with a step
        // that waits until it has really been drawn.
        let guide = try #require(TutorialCatalog.guide(id: "draw-it-with-the-pen"))
        let ids = guide.steps.map(\.id)
        #expect(ids.firstIndex(of: "click-the-corners")! < ids.firstIndex(of: "pull-a-curve")!)
        let curve = try #require(guide.step(id: "pull-a-curve"))
        #expect(curve.advance == .waitsFor(.editMade))
        #expect(curve.body.lowercased().contains("drag"))
        #expect(guide.steps.contains { $0.advance == .waitsFor(.toolPicked(.pen)) })
        #expect(guide.sample == .iconFrame)
    }

    @Test func theReshapingGuideWaitsOnTheTwoGesturesNobodyGuesses() throws {
        let guide = try #require(TutorialCatalog.guide(id: "reshape-what-you-drew"))
        for id in ["bend-a-corner", "straighten-one-side"] {
            let step = try #require(guide.step(id: id))
            #expect(step.advance == .waitsFor(.editMade), "\(id) does not wait on the gesture")
            #expect(step.title.lowercased().contains("double click"),
                    "\(id) does not name the double click")
        }
        // It opens on a shape with corners, or there is nothing to bend.
        #expect(guide.sample == .iconPath)
    }

    @Test func theTurningGuideComesAfterTheReshapingOne() throws {
        // What Turn Into Path hands you is a shape you reshape, so it means
        // nothing until the points have been taught.
        let ids = icons.map(\.id)
        #expect(ids.firstIndex(of: "reshape-what-you-drew")!
                < ids.firstIndex(of: "turn-a-shape-into-a-path")!)
        let guide = try #require(TutorialCatalog.guide(id: "turn-a-shape-into-a-path"))
        #expect(guide.sample == .iconBox, "it must arrive as a box rather than as a path")
        #expect(guide.steps.contains { $0.id == "one-undo-back" && !$0.waits },
                "a one way turn has to say how to get back")
    }

    @Test func theExportGuideExplainsTheSheetBeforeItOpensIt() throws {
        let guide = try #require(TutorialCatalog.guide(id: "get-a-clean-svg-out"))
        let ids = guide.steps.map(\.id)
        #expect(ids.firstIndex(of: "what-it-asks")! < ids.firstIndex(of: "open-export")!)
        #expect(ids.firstIndex(of: "before-you-save")! < ids.firstIndex(of: "open-export")!)
        #expect(guide.step(id: "open-export")?.advance == .waitsFor(.dialogOpened(.export)))
        #expect(guide.steps.last?.anchor == .dialog(.export))
    }

    // MARK: The samples the track brings

    @Test func everyIconSampleIsOneFrameAtTheSizeIconsAreDesignedAt() {
        for sample in [TutorialSample.iconFrame, .iconPath, .iconBox] {
            let layers = TutorialSampleScreen.layers(for: sample)
            #expect(layers.count == 1, "\(sample.rawValue) is not one frame")
            let frame = layers[0]
            #expect(frame.isFrame, "\(sample.rawValue) does not bring a frame")
            #expect(frame.frame.size == CGSize(width: 24, height: 24),
                    "\(sample.rawValue) is \(frame.frame.size), not the 24 point icon size")
            #expect(IconPreviews.isIconSize(frame.frame.size),
                    "\(sample.rawValue) would get no previews and no keylines")
        }
    }

    @Test func theIconFrameSitsOnWholeGridCells() {
        // The canvas draws its lines every four points from the canvas origin.
        // A frame parked half a cell off would teach the opposite of what the
        // track is for, because its own edges would run between the lines.
        let box = TutorialSampleScreen.iconFrameBox
        let spacing = CanvasGridSettings.defaultSpacing
        #expect(box.minX.truncatingRemainder(dividingBy: spacing) == 0)
        #expect(box.minY.truncatingRemainder(dividingBy: spacing) == 0)
    }

    @Test func theDrawnShapeIsAllHardCornersOnTheGrid() throws {
        // The reshaping guide's first real lesson is bending a corner, and a
        // shape that arrived bent has nothing to bend.
        let frame = try #require(TutorialSampleScreen.layers(for: .iconPath).first)
        let path = try #require(frame.children.first?.path)
        #expect(path.isClosed)
        #expect(path.anchors.count == 5)
        for anchor in path.anchors {
            #expect(anchor.handleIn == nil && anchor.handleOut == nil,
                    "the bookmark arrived with a curve already in it")
        }
        // Two points on a 24 point frame, and the line a 24 point frame gives a
        // freshly drawn shape, so the sample looks like something just drawn.
        #expect(path.strokeWidth == IconStrokeWeight.startingWidth(
            armed: AnnotationContent.defaultStrokeWidth,
            onFrameSized: CGSize(width: 24, height: 24)))
    }

    @Test func theBoxSampleIsAShapeRatherThanAPath() throws {
        // Turn Into Path only applies to a box, an oval or a line, so a sample
        // that arrived as a path would leave the guide's one command dimmed.
        let frame = try #require(TutorialSampleScreen.layers(for: .iconBox).first)
        let box = try #require(frame.children.first)
        #expect(box.path == nil, "the box sample arrived as a path")
        #expect(box.annotation?.shape == .rectangle)
        #expect((box.annotation?.cornerRadius ?? 0) > 0,
                "the rounding is the point: it is what turns into curves you can pull")
    }

    // MARK: The four guides about moving

    private var motionGuides: [TutorialGuide] {
        icons.filter { ["make-something-move", "get-the-timing-right",
                        "two-parts-out-of-phase", "export-an-animated-svg"].contains($0.id) }
    }

    @Test func theMovingGuidesComeAfterTheDrawingOnes() {
        // You cannot animate an icon you have not drawn, and every one of these
        // opens on a bell that was drawn the way the guides before them teach.
        let ids = icons.map(\.id)
        #expect(ids.firstIndex(of: "draw-it-with-the-pen")!
                < ids.firstIndex(of: "make-something-move")!)
    }

    @Test func everyMovingGuideNeedsTheMotionList() {
        for guide in motionGuides {
            #expect(guide.requires.contains(FeatureCatalog.motionFlag), "\(guide.id)")
        }
        // Switch Motion off and all four go, and the shelf survives on the
        // drawing guides.
        let shown = TutorialCatalog.guides(enabled: { $0 != FeatureCatalog.motionFlag })
        for guide in motionGuides {
            #expect(shown.allSatisfy { $0.id != guide.id },
                    "\(guide.id) survived the Motion list going off")
        }
        #expect(shown.contains { $0.id == "draw-it-with-the-pen" })
        #expect(TutorialCatalog.populatedTracks(in: shown).contains(.icons))
    }

    @Test func theTrackTeachesAPropertyRatherThanANamedMotion() {
        // There is no list of canned motions in the app and there was never
        // going to be: a bell does not pulse, it swings. So the copy may not
        // teach one either.
        for guide in motionGuides {
            let copy = (guide.title + " " + guide.summary + " "
                        + guide.steps.map { $0.title + " " + $0.body }.joined(separator: " "))
                .lowercased()
            for invented in ["pulse", "wiggle", "bounce", "spin", "preset", "effect preset"] {
                #expect(!copy.contains(invented), "\(guide.id) teaches a named motion: \(invented)")
            }
        }
        // And the word it does use is the app's word.
        let first = TutorialCatalog.guide(id: "make-something-move")
        let body = first?.step(id: "add-a-rotation")?.body.lowercased() ?? ""
        #expect(body.contains("propert"), "the first motion is not described as a property")
    }

    @Test func theFirstMovingGuideTeachesThePivotInTheSameSitting() throws {
        // The pivot is not a refinement of the swing. A person who stops after
        // adding a Rotation has an icon that rocks like a bobblehead, so the
        // repair is in the same guide or the guide taught the wrong thing.
        let guide = try #require(TutorialCatalog.guide(id: "make-something-move"))
        let ids = guide.steps.map(\.id)
        #expect(ids.firstIndex(of: "add-a-rotation")! < ids.firstIndex(of: "the-bobblehead")!)
        #expect(ids.firstIndex(of: "the-bobblehead")!
                < ids.firstIndex(of: "say-what-it-turns-around")!)
        let pivot = try #require(guide.step(id: "say-what-it-turns-around"))
        #expect(pivot.advance == .waitsFor(.editMade))
        #expect(pivot.body.lowercased().contains("hangs"))
        // It opens on a bell that does not move, or there is nothing to make.
        #expect(guide.sample == .iconBell)
    }

    @Test func theTimingGuideTeachesTheWaitAsWellAsTheLength() throws {
        // "Timing" that only ever means duration leaves a person unable to say
        // when a thing happens, which is the whole of the guide after it.
        let guide = try #require(TutorialCatalog.guide(id: "get-the-timing-right"))
        let wait = try #require(guide.step(id: "make-it-wait-first"))
        #expect(wait.advance == .waitsFor(.editMade))
        #expect(wait.body.lowercased().contains("holds still"))
        #expect(guide.step(id: "how-long-it-takes")?.advance == .waitsFor(.editMade))
        #expect(guide.step(id: "the-shape-it-moves-on")?.advance == .waitsFor(.editMade))
        // It opens on something already moving, or it spends a third of itself
        // making one.
        #expect(guide.sample == .iconBellSwinging)
    }

    @Test func thePhaseGuideOpensOnTheThingThatLooksWrong() throws {
        let guide = try #require(TutorialCatalog.guide(id: "two-parts-out-of-phase"))
        #expect(guide.sample == .iconBellInStep)
        // Every step about the lag points at the strip, because a lag is a
        // comparison and a comparison needs both bars on one ruler.
        #expect(guide.steps.contains { $0.anchor == .timingStrip })
        let drag = try #require(guide.step(id: "drag-it-late"))
        #expect(drag.anchor == .timingStrip)
        #expect(drag.advance == .waitsFor(.editMade))
        // And the strip is a name the app promises.
        #expect(Set(TutorialAnchor.all).contains(.timingStrip))
    }

    @Test func thePhaseGuideOnlyRingsTheStripWhereSomethingIsMoving() {
        // The strip is the one anchor that comes and goes with the DOCUMENT
        // rather than with a sheet: a still picture has no strip at all. So a
        // guide pointing at it has to bring a sample that already moves.
        for guide in TutorialCatalog.guides
        where guide.steps.contains(where: { $0.anchor == .timingStrip }) {
            let sample = guide.sample
            let layers = sample.map(TutorialSampleScreen.layers(for:)) ?? []
            #expect(layers.contains { $0.hasMotionInside },
                    "\(guide.id) rings the timing strip over a picture that does not move")
        }
    }

    @Test func theAnimatedExportGuideSaysHowToCheckTheFile() throws {
        let guide = try #require(TutorialCatalog.guide(id: "export-an-animated-svg"))
        #expect(guide.sample == .iconBellRinging)
        #expect(guide.requires.contains(FeatureCatalog.animatedSVGExportFlag))
        let ids = guide.steps.map(\.id)
        // The sheet is explained before it is opened, same rule the still SVG
        // guide follows, so nobody reads a card over the thing it describes.
        #expect(ids.firstIndex(of: "where-it-is-going")!
                < ids.firstIndex(of: "open-the-export-sheet")!)
        #expect(guide.step(id: "open-the-export-sheet")?.advance
                == .waitsFor(.dialogOpened(.export)))
        let last = try #require(guide.steps.last)
        #expect(last.anchor == .dialog(.export))
        // A file you cannot check is a file you have to take on trust.
        #expect(last.body.lowercased().contains("browser"))
    }

    // MARK: The bell

    @Test func theBellIsTwoPartsSoPhaseHasSomewhereToShow() throws {
        let frame = try #require(TutorialSampleScreen.layers(for: .iconBell).first)
        #expect(frame.children.map(\.name) == ["Bell", "Clapper"])
        #expect(frame.children.allSatisfy { $0.path != nil }, "the bell is not drawn as shapes")
        #expect(frame.children.allSatisfy { !$0.hasMotion },
                "the guide that makes the first motion opened on something already moving")
        // It is drawn inside the margin every icon in a set keeps to.
        let live = try #require(IconKeylines.guides(in: CGRect(origin: .zero,
                                                               size: frame.frame.size))?.liveArea)
        for child in frame.children {
            #expect(live.contains(child.frame.standardized),
                    "\(child.name) hangs outside the keylines")
        }
    }

    @Test func bothPartsOfTheBellTurnAboutThePointItHangsFrom() throws {
        // The lesson the bell exists for. Each part turns about the SAME place
        // on the drawing, which is a different fraction of each one's own box:
        // the top middle of the body, and a long way above the clapper.
        let frame = try #require(TutorialSampleScreen.layers(for: .iconBellInStep).first)
        var mounts: [CGPoint] = []
        for child in frame.children {
            let turn = try #require(child.motions?.first)
            #expect(turn.property == .rotation)
            // A layer's pivot box IS its frame, and a frame's children are
            // stated in the frame's own coordinates, so this comes back in the
            // one space both parts share.
            mounts.append(turn.turnsAbout.point(in: child.turnPivotBox))
        }
        #expect(mounts.count == 2)
        #expect(abs(mounts[0].x - mounts[1].x) < 0.001, "the two parts hang from different places")
        #expect(abs(mounts[0].y - mounts[1].y) < 0.001, "the two parts hang from different places")
        // And the body's mount really is its own top centre, which is what lets
        // the first guide repair the swing with one named choice.
        let body = try #require(frame.children.first)
        #expect(body.motions?.first?.turnsAbout.named == .topCentre)
    }

    @Test func theFourBellSamplesAreTheFourStagesOfOneIcon() throws {
        func turns(_ sample: TutorialSample) throws -> [LayerMotion] {
            let frame = try #require(TutorialSampleScreen.layers(for: sample).first)
            return frame.children.compactMap { $0.motions?.first }
        }
        #expect(try turns(.iconBell).isEmpty)
        #expect(try turns(.iconBellSwinging).count == 1)
        let inStep = try turns(.iconBellInStep)
        #expect(inStep.count == 2)
        #expect(inStep.allSatisfy { $0.timing.startMS == 0 },
                "the guide about phase opened on something already out of phase")
        let ringing = try turns(.iconBellRinging)
        #expect(ringing.count == 2)
        #expect(ringing.map(\.timing.startMS) == [0, 90],
                "the finished bell does not have its clapper arriving late")
    }

    @Test func theFinishedBellWritesAFileThatReallyPlays() throws {
        // The guide's last card tells you to open the file in a browser and
        // watch it ring, so the file has to be one a browser can play with
        // nothing else loaded: the motion written as text, both parts in it,
        // and the lag between them in the file rather than only on screen.
        //
        // Checked in a real browser on 2026-09-15 (Chrome, the file opened on
        // its own): both parts turn, and the clapper's angle trails the body's
        // all the way round the lap. What is held here is what made that true.
        let frame = try #require(TutorialSampleScreen.layers(for: .iconBellRinging).first)
        let document = PhotonzDocument(canvasSize: frame.frame.size, layers: frame.children)
        let written = SVGExport.write(document,
                                      animation: .moving(cycleMS: document.motionCycleLengthMS))
        let text = written.text
        #expect(written.fallbacks.isEmpty, "part of the bell went out as a picture")
        #expect(!text.contains("<image"), "there is a bitmap inside the file")
        // Two moving parts, each turning about the point the bell hangs from.
        #expect(text.components(separatedBy: "<animateTransform").count - 1 == 2)
        #expect(text.components(separatedBy: "type=\"rotate\"").count - 1 == 2)
        #expect(text.contains("repeatCount=\"indefinite\""), "it plays once and stops")
        // The lap is the longest motion plus the lag, so the late part fits.
        #expect(document.motionCycleLengthMS == 990)
        // The two parts do NOT share a keyTimes list: that difference IS the
        // lag, and a file where they matched would play in lockstep however
        // right the app looked.
        let keyTimes = text.split(separator: "\n").compactMap { line -> Substring? in
            guard let start = line.range(of: " keyTimes=\"") else { return nil }
            guard let end = line[start.upperBound...].firstIndex(of: "\"") else { return nil }
            return line[start.upperBound..<end]
        }
        #expect(keyTimes.count == 2)
        #expect(keyTimes[0] != keyTimes[1], "both parts move on the same clock, so nothing lags")
    }

    @Test func theSwingingBellStaysInsideItsOwnFrame() throws {
        // A 24 point file whose drawing leaves the box at the ends of the swing
        // is clipped by whatever draws it, and the person finds out from the
        // browser rather than from the app. Measured at both extremes of the
        // throw, about the point the bell hangs from.
        let frame = try #require(TutorialSampleScreen.layers(for: .iconBellRinging).first)
        let box = CGRect(origin: .zero, size: frame.frame.size)
        for child in frame.children {
            let turn = try #require(child.motions?.first)
            let pivot = turn.turnsAbout.point(in: child.turnPivotBox)
            for degrees in [-12.0, 12.0] {
                let radians = degrees * .pi / 180
                for corner in [CGPoint(x: child.frame.minX, y: child.frame.minY),
                               CGPoint(x: child.frame.maxX, y: child.frame.minY),
                               CGPoint(x: child.frame.minX, y: child.frame.maxY),
                               CGPoint(x: child.frame.maxX, y: child.frame.maxY)] {
                    let dx = corner.x - pivot.x, dy = corner.y - pivot.y
                    let turned = CGPoint(x: pivot.x + dx * cos(radians) - dy * sin(radians),
                                         y: pivot.y + dx * sin(radians) + dy * cos(radians))
                    #expect(box.insetBy(dx: -0.01, dy: -0.01).contains(turned),
                            "\(child.name) swings to \(turned), outside its own 24 point frame")
                }
            }
        }
    }

    @Test func theEmptyFrameSampleReallyIsEmpty() throws {
        let frame = try #require(TutorialSampleScreen.layers(for: .iconFrame).first)
        #expect(frame.children.isEmpty, "there would be nothing to draw")
    }
}
