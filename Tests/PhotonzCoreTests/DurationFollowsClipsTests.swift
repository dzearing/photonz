import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A video's length that ended with its last clip goes on ending with it**
/// (`DurationFollowsClips.swift`; user 2026-10-29: "when i delete the max
/// video clip ... the max length doesn't get reduced ... It should always be
/// 2x the max Duration").
///
/// A clip landing past the end stretches the written length to hold it. A
/// trim already shrank it again, and nothing else did: delete that clip, or
/// drag it back, and the video went on running to where it had been, the
/// timeline zooming out to twice a length nothing filled.
///
/// Written before the change, which is the rule for `PhotonzCore`.
@Suite("A video's length follows its last clip")
struct DurationFollowsClipsTests {

    static let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    static func movie(seconds: Int) -> MovieRef {
        MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: seconds * 1000)
    }

    /// An eight second recording with a nine second clip let go at ten:
    /// nineteen long.
    static func recordingWithASecondClip() -> (History, UUID) {
        var doc = PhotonzDocument(canvasSize: frame.size)
        doc.durationMS = 8000
        doc.addClip(movie(seconds: 8), name: "first", atMS: 0, frame: frame)
        var history = History(document: doc)
        var second = UUID()
        history.perform { second = $0.addClip(movie(seconds: 9), name: "second", atMS: 10_000, frame: frame) }
        return (history, second)
    }

    @Test func deletingTheLastClipEndsTheVideoWithTheOneBeforeIt() {
        var (history, second) = Self.recordingWithASecondClip()
        #expect(history.current.documentDurationMS == 19_000)
        history.perform { _ = $0.removeLayer(id: second) }
        #expect(history.current.documentDurationMS == 8000)
    }

    @Test func movingTheLastClipBackEndsTheVideoWhereItNowEnds() {
        var (history, second) = Self.recordingWithASecondClip()
        history.perform { $0.updateLayer(id: second) { $0.time = $0.time?.moved(toInMS: 4000) } }
        #expect(history.current.documentDurationMS == 13_000)
    }

    @Test func undoingTheDeleteBringsTheLengthBack() {
        var (history, second) = Self.recordingWithASecondClip()
        history.perform { _ = $0.removeLayer(id: second) }
        history.undo()
        #expect(history.current.documentDurationMS == 19_000)
    }

    @Test func aBlankVideoKeepsTheLengthItWasMadeWith() {
        // Ten seconds chosen, a two second clip at three: the tail after it
        // is the person's, and taking the clip away leaves ten.
        var history = History(document: .emptyVideo(size: Self.frame.size, lengthMS: 10_000))
        var clip = UUID()
        history.perform { clip = $0.addClip(Self.movie(seconds: 2), name: "c", atMS: 3000, frame: Self.frame) }
        #expect(history.current.documentDurationMS == 10_000)
        history.perform { _ = $0.removeLayer(id: clip) }
        #expect(history.current.documentDurationMS == 10_000)
    }

    @Test func aBlankVideoGrownByAClipShrinksBackOnlyToWhatIsLeft() {
        // Four seconds chosen, a nine second clip at two grows it to eleven;
        // dragging that clip back to nought ends the video at nine.
        var history = History(document: .emptyVideo(size: Self.frame.size, lengthMS: 4000))
        var clip = UUID()
        history.perform { clip = $0.addClip(Self.movie(seconds: 9), name: "c", atMS: 2000, frame: Self.frame) }
        #expect(history.current.documentDurationMS == 11_000)
        history.perform { $0.updateLayer(id: clip) { $0.time = $0.time?.moved(toInMS: 0) } }
        #expect(history.current.documentDurationMS == 9000)
    }

    @Test func deletingEveryClipLeavesTheLengthAlone() {
        // Nothing left to end with: the length stays as it was rather than
        // the video vanishing from under the timeline.
        var (history, second) = Self.recordingWithASecondClip()
        let first = history.current.layers.first { $0.name == "first" }?.id
        history.perform { $0.removeLayers(ids: Set([second] + [first].compactMap { $0 })) }
        #expect(history.current.documentDurationMS == 19_000)
    }

    @Test func aDocumentWithNoTimeIsLeftWithNone() {
        var history = History(document: PhotonzDocument(canvasSize: Self.frame.size))
        history.perform { $0.addLayer(Layer(name: "box", content: .text(TextContent(string: "box")), frame: Self.frame)) }
        #expect(history.current.durationMS == nil)
    }
}
