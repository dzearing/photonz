import Foundation
import PhotonzCore
import Testing

/// The Video track: the smallest one, and the only one that teaches in a window
/// with no canvas in it. Everything here is a fact about the DATA. That each
/// anchor really turns up in a live recording's window is proved by the walks.
@Suite("Tutorials: the Video track, in the recording window")
struct TutorialVideoTrackTests {

    /// The two guides for the small recording window, which is still what a
    /// recording opens in wherever the editor has not taken over.
    private var video: [TutorialGuide] {
        TutorialCatalog.guides(in: .video).filter { $0.sample?.opensInRecordingWindow == true }
    }

    // MARK: The track itself

    @Test func theWindowHasItsTwoGuides() {
        #expect(video.map(\.id) == ["trim-a-recording", "export-a-recording"])
    }

    @Test func theTrackTurnsUpInTheMenuAndTheWindow() {
        // Data, and nothing else edited: the track has guides on it, so it is
        // a shelf the menu and the hub both build.
        #expect(TutorialCatalog.populatedTracks.contains(.video))
        #expect(TutorialCatalog.guides(enabled: { $0 != FeatureCatalog.recordingIsADocumentFlag })
            .contains { $0.track == .video })
    }

    @Test func everyGuideIsShortEnoughToFinishInOneSitting() {
        for guide in video {
            #expect(guide.minutes <= 2, "\(guide.id) claims \(guide.minutes) minutes")
            #expect(guide.steps.count <= 8, "\(guide.id) has \(guide.steps.count) steps")
            #expect(guide.steps.count >= 3, "\(guide.id) has \(guide.steps.count) steps")
        }
    }

    @Test func theClaimOnTheCardIsMeasuredRatherThanGuessed() {
        for guide in video {
            let seconds = Int(TutorialLength.estimatedSeconds(for: guide))
            #expect(TutorialLength.claimIsHonest(for: guide),
                    "\(guide.id) claims \(guide.minutes) min, the steps come to \(seconds)s")
        }
    }

    // MARK: What it teaches in

    @Test func bothGuidesBringTheirOwnRecording() {
        // There is no canvas in a recording's window, so a guide here cannot
        // fall back on the picture somebody has open: it brings a clip.
        for guide in video {
            #expect(guide.sample == .sampleRecording, "\(guide.id) brings \(String(describing: guide.sample))")
            #expect(guide.sample?.isVideo == true)
        }
    }

    @Test func aRecordingIsNotADrawingAndNeverPretendsToBe() {
        #expect(TutorialSample.sampleRecording.isVideo)
        #expect(!TutorialSample.sampleRecording.isFlattened)
        #expect(TutorialSampleScreen.layers(for: .sampleRecording).isEmpty)
        #expect(TutorialSampleScreen.pictureLayers(for: .sampleRecording).isEmpty)
        // Every other sample is a picture, and only this one is not.
        for sample in [TutorialSample.starterScreen, .redlineScreen, .stylesScreen,
                       .componentPieces, .blankPage, .emptyWindow] {
            #expect(!sample.isVideo, "\(sample) claims to be a recording")
        }
    }

    @Test func nothingInTheTrackPointsAtThePictureEditor() {
        // A recording's window has no tool bar, no docked panel and no layers,
        // so every one of those names would resolve to nothing in it.
        for guide in video {
            for step in guide.steps {
                #expect(step.anchor.name.hasPrefix("video."),
                        "\(guide.id)/\(step.id) points at \(step.anchor.name), which is not in a recording's window")
                #expect(step.prepare.isEmpty,
                        "\(guide.id)/\(step.id) prepares something a recording's window has not got")
            }
        }
    }

    @Test func everyNameItPointsAtIsOnePromised() {
        let promised = Set(TutorialAnchor.all.map(\.name))
        for guide in video {
            for step in guide.steps {
                #expect(promised.contains(step.anchor.name),
                        "\(guide.id)/\(step.id) points at \(step.anchor.name), which nothing promises")
            }
        }
    }

    @Test func theWholeCatalogueStillPasses() {
        #expect(TutorialCatalogCheck.problems() == [])
    }

    // MARK: The rules earlier tracks settled

    @Test func noGuideEndsOnAWaitingStep() {
        // A guide whose last step waits vanishes the moment you do the thing,
        // with no closing word.
        for guide in video {
            #expect(guide.steps.last?.waits == false, "\(guide.id) ends on a waiting step")
        }
    }

    @Test func theWholeTrackPassesTheCopyRules() {
        for guide in video {
            #expect(TutorialCopyRules.problems(in: guide) == [], "\(guide.id)")
        }
    }

    @Test func nothingHereNeedsAFeatureSomebodyCanSwitchOff() {
        // The video window is not behind a flag, so both guides are offered
        // whatever anybody has turned off in Experiments. That is the whole of
        // "checked with the features it teaches flagged off as well as on"
        // here, and it is worth pinning: adding a `requires` later without
        // walking the guide again would be the failure this catches.
        for guide in video {
            #expect(guide.requires.isEmpty, "\(guide.id) needs \(guide.requires)")
        }
        #expect(TutorialCatalog.guides(enabled: { _ in false })
            .filter { $0.track == .video }.map(\.id) == video.map(\.id))
    }

    // Both guides teach the small recording window: its scissors, its
    // handles, its Save that writes the trim into the file. Once a recording
    // opens in the editor instead (on by default in Next since 2026-09-23)
    // none of those controls is on screen, so a guide pointing at them waits
    // for a window that never comes. They are not offered while it is on.
    @Test func neitherGuideIsOfferedWhenARecordingOpensInTheEditor() {
        for guide in video {
            #expect(guide.retiredBy == [FeatureCatalog.recordingIsADocumentFlag], "\(guide.id)")
        }
        let editorOn = TutorialCatalog.guides(enabled: { $0 == FeatureCatalog.recordingIsADocumentFlag })
        #expect(!editorOn.contains { $0.sample?.opensInRecordingWindow == true })
    }

    // MARK: What each guide is for

    @Test func theTrimGuideMakesYouReallyTrimSomething() throws {
        let guide = try #require(TutorialCatalog.guide(id: "trim-a-recording"))
        let waits = guide.steps.compactMap(\.advance.trigger)
        // In the order the job is done in: open it, bring each end in, keep
        // what is left.
        #expect(waits == [.trimModeOpened, .trimStartMoved, .trimEndMoved, .trimApplied])
    }

    @Test func theTrimGuideSaysWhatSavingDoesBeforeAnybodyDoesIt() throws {
        let guide = try #require(TutorialCatalog.guide(id: "trim-a-recording"))
        let last = try #require(guide.steps.last)
        // Trimming is the one edit in the app that is baked in on save, and the
        // way back has a name. Both are said out loud on the closing card.
        #expect(last.anchor == .video(.save))
        #expect(last.body.contains("original"))
        #expect(last.body.contains("Revert to Original"))
        // And it does not make anybody do it: nothing here waits on a save.
        #expect(!last.waits)
    }

    @Test func theTrimGuideDoesNotAskForPlayBeforeItHasStartedPlaying() throws {
        let guide = try #require(TutorialCatalog.guide(id: "trim-a-recording"))
        // A recording's window autoplays the moment it opens, so a first step
        // waiting on play would come up already finished every single time.
        // Nothing waits until the scissors.
        let firstWait = guide.steps.first { $0.waits }
        #expect(firstWait?.anchor == .video(.trim))
    }

    @Test func theExportGuideTeachesTheChoiceAndEndsOnTheClipboard() throws {
        let guide = try #require(TutorialCatalog.guide(id: "export-a-recording"))
        let body = guide.steps.map(\.body).joined(separator: " ")
        #expect(body.contains("MP4"))
        #expect(body.contains("GIF"))
        #expect(body.contains("HEIC"))
        // The three quality levels are the app's own words for them.
        #expect(body.contains("High"))
        #expect(body.contains("Standard"))
        #expect(body.contains("Small"))
        // The one thing it asks anybody to do is the one with no dialog in it.
        #expect(guide.steps.compactMap(\.advance.trigger) == [.recordingCopied])
    }

    @Test func theExportGuideNeverWalksAnybodyIntoASavePanel() throws {
        let guide = try #require(TutorialCatalog.guide(id: "export-a-recording"))
        // Picking a row under Export runs a modal save dialog, which would sit
        // on top of the card and leave nothing to press. So no step waits on an
        // export, and no step tells anybody to pick one of those rows.
        for step in guide.steps {
            #expect(!step.body.contains("Export MP4"),
                    "\(step.id) sends somebody into the save dialog")
        }
    }
}

/// The Video track as Next has it: a recording opens in the EDITOR, with the
/// transport and the timeline under the picture, and these six guides teach
/// that editor. The facts about the data are here; that every step finds its
/// control in a live window is what each guide's walk proves.
@Suite("Tutorials: the Video track, in the editor")
struct TutorialVideoEditorTrackTests {

    private var editor: [TutorialGuide] {
        TutorialCatalog.guides(in: .video).filter { $0.sample?.opensInRecordingWindow == false }
    }

    private static let nextDefaults = FeatureCatalog.defaultSettings(for: .next)

    // MARK: The track itself

    @Test func theTrackIsTheEditItself() {
        // Cut, a second clip, a title that moves, a transition, captions,
        // export: the order a video gets made in.
        #expect(editor.map(\.id) == ["cut-a-recording-down", "add-a-second-clip",
                                     "a-title-that-moves", "put-a-transition-on-a-cut",
                                     "captions-from-the-speech", "export-the-video"])
    }

    @Test func nextOffersTheTrackWithNothingSwitchedOn() {
        // Help and the Tutorials window show a Video track at Next defaults,
        // and it is these six and not the retired window's two.
        let offered = TutorialCatalog.guides(enabled: { Self.nextDefaults.isEnabled($0) })
        #expect(offered.filter { $0.track == .video }.map(\.id) == editor.map(\.id))
        #expect(TutorialCatalog.populatedTracks(in: offered).contains(.video))
    }

    @Test func noneOfThemIsOfferedWhereTheRecordingWindowIsStillInUse() {
        // Where a recording still opens in its own small window, a guide
        // pointing at the timeline would point at nothing.
        let windowStill = TutorialCatalog.guides(enabled: { $0 != FeatureCatalog.recordingIsADocumentFlag })
        for guide in editor {
            #expect(guide.requires.contains(FeatureCatalog.recordingIsADocumentFlag), "\(guide.id)")
            #expect(!windowStill.contains { $0.id == guide.id }, "\(guide.id)")
        }
    }

    @Test func everyGuideIsShortEnoughToFinishInOneSitting() {
        for guide in editor {
            #expect(guide.minutes <= 2, "\(guide.id) claims \(guide.minutes) minutes")
            #expect((4...8).contains(guide.steps.count), "\(guide.id) has \(guide.steps.count) steps")
        }
    }

    @Test func theClaimOnTheCardIsMeasuredRatherThanGuessed() {
        for guide in editor {
            let seconds = Int(TutorialLength.estimatedSeconds(for: guide))
            #expect(TutorialLength.claimIsHonest(for: guide),
                    "\(guide.id) claims \(guide.minutes) min, the steps come to \(seconds)s")
        }
    }

    // MARK: What it teaches in

    @Test func everyGuideBringsARecordingThatOpensInTheEditor() {
        for guide in editor {
            let sample = guide.sample
            #expect(sample?.isVideo == true, "\(guide.id) brings \(String(describing: sample))")
            #expect(sample?.opensInRecordingWindow == false, "\(guide.id)")
            #expect(sample?.isMadeUpPicture == true, "\(guide.id): the finish card offers to move on")
        }
        // Four of them share one recording, so they teach in one window and
        // the track reads as one video being made.
        #expect(editor.filter { $0.sample == .videoRecording }.count == 4)
        #expect(TutorialCatalog.guide(id: "put-a-transition-on-a-cut")?.sample == .videoTwoClips)
        #expect(TutorialCatalog.guide(id: "captions-from-the-speech")?.sample == .videoTalk)
    }

    @Test func nothingPointsAtTheRetiredWindow() {
        // The small recording window's parts are not in the editor. The one
        // name shared with it is the transport, which the timeline wears too.
        for guide in editor {
            for step in guide.steps where step.anchor.name.hasPrefix("video.") {
                #expect(step.anchor == .video(.transport),
                        "\(guide.id)/\(step.id) points at \(step.anchor.name), which is only in the old window")
            }
        }
    }

    @Test func noStepPointsAtAToolBarButtonOtherThanText() {
        // The video tool bar is being rebuilt, so a step ringing Crop or Trim
        // there would move under it. Text stays on every bar.
        for guide in editor {
            for step in guide.steps {
                if let tool = step.anchor.tool {
                    #expect(tool == .text, "\(guide.id)/\(step.id) rings \(tool)")
                }
                #expect(step.anchor.toolGroup == nil, "\(guide.id)/\(step.id)")
            }
        }
    }

    @Test func everyNameItPointsAtIsOnePromised() {
        let promised = Set(TutorialAnchor.all)
        for guide in editor {
            for step in guide.steps {
                #expect(promised.contains(step.anchor),
                        "\(guide.id)/\(step.id) points at \(step.anchor.name), which nothing promises")
            }
        }
        #expect(TutorialCatalogCheck.problems() == [])
    }

    @Test func aStepAboutAPanelSectionBringsThePanelToIt() {
        for guide in editor {
            for step in guide.steps where step.anchor.panelSectionID != nil {
                #expect(step.prepare.contains(.revealTarget), "\(guide.id)/\(step.id)")
            }
        }
    }

    // MARK: The rules earlier tracks settled

    @Test func noGuideEndsOnAWaitingStep() {
        for guide in editor {
            #expect(guide.steps.last?.waits == false, "\(guide.id) ends on a waiting step")
        }
    }

    @Test func noGuideOpensOnAWaitingStepItCannotExplain() {
        // The first card of every guide but two says what is in front of you
        // before asking for anything. The title guide opens straight on its
        // tool and the export guide on its key, both of which are the lesson.
        for guide in editor where !["a-title-that-moves", "export-the-video"].contains(guide.id) {
            #expect(guide.steps.first?.waits == false, "\(guide.id)")
        }
    }

    @Test func theWholeTrackPassesTheCopyRules() {
        for guide in editor {
            #expect(TutorialCopyRules.problems(in: guide) == [], "\(guide.id)")
        }
    }

    // MARK: What each guide really makes you do

    private func waits(_ id: String) throws -> [TutorialTrigger] {
        try #require(TutorialCatalog.guide(id: id)).steps.compactMap(\.advance.trigger)
    }

    @Test func theCutGuideTrimsBothEndsThenCutsAndThrowsAPieceAway() throws {
        #expect(try waits("cut-a-recording-down") == [.timeTakenOut, .timeTakenOut, .clipCut, .timeTakenOut])
        let guide = try #require(TutorialCatalog.guide(id: "cut-a-recording-down"))
        let words = guide.steps.map(\.body).joined(separator: " ")
        // Premiere's keys, by name: the person already has them in their fingers.
        for key in ["press Q", "press W", "Command K", "Delete", "J, K and L"] {
            #expect(words.contains(key), "the cut guide never says \(key)")
        }
    }

    @Test func theSecondClipGuideReallyBringsOneIn() throws {
        #expect(try waits("add-a-second-clip") == [.clipAdded])
        let guide = try #require(TutorialCatalog.guide(id: "add-a-second-clip"))
        #expect(guide.steps.first?.prepare.contains(.showMediaShelf) == true)
    }

    @Test func theTitleGuideMakesAMoveOutOfTwoKeys() throws {
        #expect(try waits("a-title-that-moves")
                == [.toolPicked(.text), .titleAdded, .keyAdded, .keyAdded])
    }

    @Test func theTransitionGuidePutsOneOnTheCut() throws {
        #expect(try waits("put-a-transition-on-a-cut") == [.transitionAdded])
        let guide = try #require(TutorialCatalog.guide(id: "put-a-transition-on-a-cut"))
        #expect(guide.steps.map(\.body).joined().contains("Command T"))
    }

    @Test func theCaptionsGuideHasYouCorrectAWord() throws {
        #expect(try waits("captions-from-the-speech") == [.captionRetyped])
    }

    @Test func theExportGuideOpensTheSheetAndNeverTheSavePanel() throws {
        #expect(try waits("export-the-video") == [.dialogOpened(.export)])
        let guide = try #require(TutorialCatalog.guide(id: "export-the-video"))
        // Everything after the sheet is up is ABOUT the sheet, and points at it.
        for step in guide.steps.dropFirst() {
            #expect(step.anchor == .dialog(.export), "\(step.id)")
            #expect(!step.waits, "\(step.id) would wait behind a modal save panel")
        }
        let words = guide.steps.map(\.body).joined(separator: " ")
        for said in ["MP4", "GIF", "HEIC", "1080p", "720p"] {
            #expect(words.contains(said), "the export guide never says \(said)")
        }
    }

    @Test func everyWaitIsSomethingTheEditorReallyReports() throws {
        // A video guide in the editor waits on the document, on a tool, or on
        // the sheet: never on the retired window's own events, which nothing in
        // the editor raises.
        let retired: [TutorialTrigger] = [.trimModeOpened, .trimStartMoved, .trimEndMoved,
                                          .recordingCopied]
        for guide in editor {
            for trigger in guide.steps.compactMap(\.advance.trigger) {
                #expect(!retired.contains(trigger), "\(guide.id) waits on \(trigger)")
            }
        }
    }
}
