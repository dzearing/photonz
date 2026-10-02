import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A recording opened while macOS is still closing its file: it opens at once
/// on the last frame the stream delivered, standing in for the file, and when
/// the file lands its real length and size are taken on under the same
/// identity, so nothing done in the meantime is lost and the frame already on
/// screen keeps drawing until the file's own frames are read.
struct ClosingRecordingTests {

    private let size = CGSize(width: 3456, height: 2234)

    private func closing(lastFrameMS: Int = 5_012, stoppedMS: Int = 5_012,
                         hasSound: Bool = true) -> ClosingRecording {
        ClosingRecording(pixelSize: size, lastFrameMS: lastFrameMS, stoppedMS: stoppedMS, hasSound: hasSound)
    }

    // MARK: - The stand-in

    @Test func theStandInRunsOneFramePastTheLastFrame() {
        let standIn = closing().standIn()
        #expect(standIn.durationMS == 5_012 + MovieRef.frameStepMS)
        #expect(standIn.pixelSize == size)
        #expect(standIn.hasSound)
    }

    /// A screen that stopped changing before Stop sends no more frames, but
    /// the file still runs to Stop, so the stand-in does too and the length on
    /// screen does not jump when the file lands.
    @Test func theStandInRunsToStopWhenTheScreenWentStillFirst() {
        let standIn = closing(lastFrameMS: 2_617, stoppedMS: 3_240).standIn()
        #expect(standIn.durationMS == 3_240)
    }

    /// The playhead waits at the end, where the picture is the last frame:
    /// nothing changed on screen after it, which is why it was the last.
    @Test func thePlayheadWaitsOnTheLastMoment() {
        let still = closing(lastFrameMS: 2_617, stoppedMS: 3_240)
        #expect(still.waitingMS == 3_239)
        let busy = closing()
        #expect(busy.waitingMS == busy.standIn().durationMS - 1)
        #expect(busy.standIn().frameIndex(atSourceMS: busy.waitingMS) >= 5_012 / MovieRef.frameStepMS)
    }

    @Test func aRecordingStoppedBeforeItsFirstFrameStillHasAFrameOfLength() {
        let recording = closing(lastFrameMS: -40, stoppedMS: -40)
        #expect(recording.lastFrameMS == 0)
        #expect(recording.standIn().durationMS == MovieRef.frameStepMS)
        #expect(recording.waitingMS == MovieRef.frameStepMS - 1)
    }

    @Test func theStandInIsAnOrdinaryRecordingDocument() {
        let doc = PhotonzDocument.recording(closing().standIn(), name: "Recording")
        #expect(doc.hasTime)
        #expect(doc.canvasSize == size)
        #expect(doc.durationMS == 5_012 + MovieRef.frameStepMS)
    }

    // MARK: - The file lands

    private func landed(from standIn: MovieRef, durationMS: Int, pixelSize: CGSize? = nil,
                        hasSound: Bool = true) -> MovieRef {
        MovieRef(id: standIn.id, pixelSize: pixelSize ?? standIn.pixelSize,
                 durationMS: durationMS, hasSound: hasSound)
    }

    @Test func anUntouchedRecordingRunsTheLengthOfTheFileOnceItLands() {
        let standIn = closing().standIn()
        var doc = PhotonzDocument.recording(standIn, name: "Recording")
        doc.rememberMedia(.recording(standIn), named: "Recording.mp4")
        let real = landed(from: standIn, durationMS: 5_120)
        doc.adoptLandedRecording(real)

        let opened = PhotonzDocument.recording(real, name: "Recording")
        let clip = doc.layers.first
        #expect(clip?.movie == real)
        #expect(clip?.time == opened.layers.first?.time)
        #expect(doc.durationMS == 5_120)
        #expect(doc.canvasSize == size)
        #expect(doc.media.first?.media == .recording(real))
        #expect(doc.media.first?.name == "Recording.mp4")
    }

    @Test func aFileShorterThanTheStandInShortensTheClip() {
        let standIn = closing().standIn()
        var doc = PhotonzDocument.recording(standIn, name: "Recording")
        doc.adoptLandedRecording(landed(from: standIn, durationMS: 4_990))
        #expect(doc.layers.first?.time?.outMS == 4_990)
        #expect(doc.layers.first?.time?.sourceLengthMS == 4_990)
        #expect(doc.durationMS == 4_990)
    }

    /// A title put on in the moment before the file landed is still there.
    @Test func whatWasAddedWhileItLandedIsKept() {
        let standIn = closing().standIn()
        var doc = PhotonzDocument.recording(standIn, name: "Recording")
        let title = Layer(name: "Title", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        doc.layers.append(title)
        doc.adoptLandedRecording(landed(from: standIn, durationMS: 5_120))
        #expect(doc.layers.count == 2)
        #expect(doc.layers.last == title)
    }

    /// A clip somebody already trimmed keeps the stretch they chose; it only
    /// learns how much file there is either side of it.
    @Test func aClipTrimmedWhileItLandedKeepsItsTrim() {
        let standIn = closing().standIn()
        var doc = PhotonzDocument.recording(standIn, name: "Recording")
        doc.layers[0].time = LayerTime(inMS: 0, outMS: 2_000, sourceInMS: 1_000,
                                       sourceLengthMS: standIn.durationMS)
        doc.adoptLandedRecording(landed(from: standIn, durationMS: 5_120))
        let time = doc.layers.first?.time
        #expect(time?.inMS == 0)
        #expect(time?.outMS == 2_000)
        #expect(time?.sourceInMS == 1_000)
        #expect(time?.sourceLengthMS == 5_120)
    }

    /// The encoder can round a dimension; the canvas and the clip follow it
    /// rather than drawing the picture a pixel out of place.
    @Test func aPictureSizeTheFileRoundedIsTakenOn() {
        let standIn = closing().standIn()
        var doc = PhotonzDocument.recording(standIn, name: "Recording")
        let rounded = CGSize(width: 3456, height: 2232)
        doc.adoptLandedRecording(landed(from: standIn, durationMS: 5_120, pixelSize: rounded))
        #expect(doc.canvasSize == rounded)
        #expect(doc.layers.first?.frame.size == rounded)
    }

    @Test func otherRecordingsAreLeftAlone() {
        let standIn = closing().standIn()
        let other = MovieRef(pixelSize: CGSize(width: 640, height: 480), durationMS: 2_000)
        var doc = PhotonzDocument.recording(standIn, name: "Recording")
        var bRoll = Layer(name: "b-roll", content: .image(other.frameRef(atSourceMS: 0)),
                          frame: CGRect(origin: .zero, size: other.pixelSize))
        bRoll.movie = other
        bRoll.time = LayerTime(inMS: 0, outMS: other.durationMS, sourceLengthMS: other.durationMS)
        doc.layers.append(bRoll)
        doc.rememberMedia(.recording(other), named: "b-roll.mov")
        doc.adoptLandedRecording(landed(from: standIn, durationMS: 5_120))
        #expect(doc.layers.last == bRoll)
        #expect(doc.media.contains { $0.media == .recording(other) })
    }

    /// A document that ran longer than the recording, because somebody made
    /// it so, keeps its own length.
    @Test func aLengthSomebodyChoseIsKept() {
        let standIn = closing().standIn()
        var doc = PhotonzDocument.recording(standIn, name: "Recording")
        doc.durationMS = 9_000
        doc.adoptLandedRecording(landed(from: standIn, durationMS: 5_120))
        #expect(doc.durationMS == 9_000)
    }

    @Test func aFileThatIsNotThisRecordingChangesNothing() {
        let standIn = closing().standIn()
        let doc = PhotonzDocument.recording(standIn, name: "Recording")
        var patched = doc
        patched.adoptLandedRecording(MovieRef(pixelSize: size, durationMS: 1_000))
        #expect(patched == doc)
    }
}
