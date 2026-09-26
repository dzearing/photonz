import Foundation
import PhotonzCore
import Testing

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

    @Test func noGuideTeachesTheRetiredRecordingWindow() {
        // Next opens every recording in the editor (2026-09-26), so a guide
        // pointing at the small window's scissors and Save would wait for a
        // window that never comes. The two that taught it went with it.
        #expect(TutorialCatalog.guides(in: .video).allSatisfy { $0.sample?.opensInRecordingWindow == false })
        #expect(TutorialCatalog.guide(id: "trim-a-recording") == nil)
        #expect(TutorialCatalog.guide(id: "export-a-recording") == nil)
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
