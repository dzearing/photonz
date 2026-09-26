import CoreGraphics
import Testing
@testable import PhotonzCore

// A recording opens to watch, with the editing tucked away until you want it
// (queue task a-recording-opens-to-watch-with-the-editing-tuck, 2026-09-25).
@Suite("How a recording's timeline opens")
struct TimelineOpeningTests {

    private func movie() -> MovieRef {
        MovieRef(pixelSize: CGSize(width: 1280, height: 800), durationMS: 8000)
    }

    @Test("a fresh recording opens with the timeline tucked away")
    func freshRecordingCollapsed() {
        let document = PhotonzDocument.recording(movie(), name: "Recording")
        #expect(TimelineOpening.opensOpen(document, remembered: nil) == false)
    }

    @Test("the last choice sticks for the next recording")
    func rememberedChoice() {
        let document = PhotonzDocument.recording(movie(), name: "Recording")
        #expect(TimelineOpening.opensOpen(document, remembered: true))
        #expect(TimelineOpening.opensOpen(document, remembered: false) == false)
    }

    @Test("a recording somebody has already trimmed reopens expanded")
    func trimmedReopensOpen() throws {
        var document = PhotonzDocument.recording(movie(), name: "Recording")
        let clipID = try #require(document.allLayers.first(where: \.isClip)?.id)
        let clip = try #require(document.layer(id: clipID))
        var session = try #require(ClipTrimSession(layer: clip))
        session.dragOut(toMS: 6000)
        _ = document.applyTrim(session)
        #expect(document.isUntouchedRecording == false)
        #expect(TimelineOpening.opensOpen(document, remembered: false))
    }

    @Test("a recording cut into pieces reopens expanded")
    func cutReopensOpen() throws {
        var document = PhotonzDocument.recording(movie(), name: "Recording")
        let clipID = try #require(document.allLayers.first(where: \.isClip)?.id)
        let didSplit = document.splitClip(clipID, atMS: 3000)
        #expect(didSplit)
        #expect(TimelineOpening.opensOpen(document, remembered: false))
    }

    @Test("a guide's sample opens expanded, because its cards point at the tracks")
    func guideOpensOpen() {
        let document = PhotonzDocument.recording(movie(), name: "Recording")
        #expect(TimelineOpening.opensOpen(document, remembered: false, forAGuide: true))
    }

    @Test("a screenshot is never an untouched recording")
    func screenshot() {
        let document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [])
        #expect(document.isUntouchedRecording == false)
    }
}

@Suite("Which timeline keys start an edit")
struct TimelineKeysOpenTheTimelineTests {

    @Test("watching keys leave the timeline tucked away")
    func watchingKeys() {
        let watching: [TimelineKeyCommand] = [
            .playPause, .shuttle(.forward), .shuttle(.stop), .stepFrames(1), .stepFrames(-5),
            .editPoint(forward: true), .goToStart, .goToEnd, .selectTool, .trackSelectForwardTool,
        ]
        for command in watching { #expect(command.opensTheTimeline == false, "\(command)") }
    }

    @Test("editing keys bring it up")
    func editingKeys() {
        let editing: [TimelineKeyCommand] = [
            .markIn, .markOut, .clearIn, .clearOut, .addMarker, .splitAtPlayhead, .lift, .rippleDelete,
            .extractMarked, .liftMarked, .rippleTrimToPlayhead(.start), .rippleTrimToPlayhead(.end),
            .applyDefaultTransition, .toggleSnapping, .bladeTool, .zoomIn, .zoomOut, .zoomToFit,
        ]
        for command in editing { #expect(command.opensTheTimeline, "\(command)") }
    }
}

@Suite("What the tucked-away timeline row says")
struct TimelineRailSummaryTests {

    @Test("the time and the length, as the mock writes them")
    func nothingPicked() {
        #expect(TimelineOpening.railSummary(pickedName: nil, time: "0:04", length: "0:15") == "0:04 / 0:15")
    }

    @Test("the thing picked comes first")
    func picked() {
        #expect(TimelineOpening.railSummary(pickedName: "Intro", time: "0:04", length: "0:15")
                == "Intro  ·  0:04 / 0:15")
    }

    @Test("a blank name is no name")
    func blankName() {
        #expect(TimelineOpening.railSummary(pickedName: "  ", time: "0:04", length: "0:15") == "0:04 / 0:15")
    }

    @Test("the row's words are labels, not sentences")
    func copyIsChrome() {
        for line in [TimelineOpening.railName, TimelineOpening.railHint] {
            #expect(CopyBudget.chromeFaults(line).isEmpty, "\(line)")
        }
    }
}
