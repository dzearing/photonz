import Foundation
import PhotonzCore
import Testing

/// The Video track: the smallest one, and the only one that teaches in a window
/// with no canvas in it. Everything here is a fact about the DATA. That each
/// anchor really turns up in a live recording's window is proved by the walks.
@Suite("Tutorials: the Video track")
struct TutorialVideoTrackTests {

    private var video: [TutorialGuide] { TutorialCatalog.guides(in: .video) }

    // MARK: The track itself

    @Test func theTrackIsWhatYouDoWithARecording() {
        #expect(video.map(\.id) == ["trim-a-recording", "export-a-recording"])
    }

    @Test func theTrackTurnsUpInTheMenuAndTheWindow() {
        // Data, and nothing else edited: the track has guides on it, so it is
        // a shelf the menu and the hub both build.
        #expect(TutorialCatalog.populatedTracks.contains(.video))
        #expect(TutorialCatalog.guides(enabled: { _ in true })
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
            .filter { $0.track == .video }.count == 2)
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
