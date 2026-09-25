import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The documents the Video track's guides open on (`TutorialVideoSample`).
///
/// A guide that says "drag b-roll onto V1" needs a b-roll on the shelf, and one
/// that says "pick Cross dissolve" needs a cut that can pay for one. Both are
/// facts about the sample, so they are pinned here rather than hoped for.
@Suite("Tutorials: the recordings a video guide opens on")
struct TutorialVideoSampleTests {

    static let take = MovieRef(pixelSize: CGSize(width: 1280, height: 800), durationMS: 8000)
    static let broll = MovieRef(pixelSize: CGSize(width: 1280, height: 800), durationMS: 8000)

    static func opened() -> PhotonzDocument {
        var doc = PhotonzDocument.recording(Self.take, name: "Tutorial Sample")
        doc.rememberMedia(.recording(Self.take), named: "Tutorial Sample.mp4")
        return doc
    }

    @Test("The recording the cut, clip, title and export guides share has b-roll waiting on the shelf, not on the timeline")
    func brollWaitsOnTheShelf() {
        let doc = TutorialVideoSample.shaped(Self.opened(), for: .videoRecording, broll: Self.broll)
        let shelf = DocumentMedia.clips(in: doc).map(\.name)
        #expect(shelf == ["Tutorial Sample.mp4", TutorialVideoSample.brollFileName])
        #expect(doc.allLayers.filter { $0.movie != nil }.count == 1)
        #expect(doc.documentDurationMS == 8000)
    }

    @Test("The transition guide's recording meets b-roll on V1, and the cut can pay for a dissolve")
    func twoClipsMeetWithSpareEitherSide() throws {
        let doc = TutorialVideoSample.shaped(Self.opened(), for: .videoTwoClips, broll: Self.broll)
        let clips = doc.allLayers.filter { $0.movie != nil }
        #expect(clips.count == 2)
        // The cut sits well right of the middle, so the tiles that open at it
        // stay clear of the guide's card, which is centred over the timeline.
        #expect(doc.documentDurationMS == 9000)
        let v1 = try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
        let points = doc.editPoints(onTrack: v1)
        #expect(points.count == 1)
        let point = try #require(points.first)
        let cut = try #require(doc.documentCut(at: .edit(outgoing: point.outgoing, incoming: point.incoming)))
        #expect(cut.incomingName == "b-roll")
        #expect(cut.cut.spareAfterOutMS ?? 0 >= 1000)
        #expect(cut.cut.spareBeforeInMS ?? 0 >= 1000)
        // The tile the mock picks first is the one that needs an overlap.
        #expect(cut.cut.fitted(.dissolve) != nil)
        // Nothing starts on it yet: putting one on is the lesson.
        #expect(cut.cut.transition == nil)
        #expect(DocumentMedia.clips(in: doc).map(\.name).contains(TutorialVideoSample.brollFileName))
    }

    @Test("Without b-roll the sample is the recording as opened, and the talk is never touched")
    func nothingToAdd() {
        let opened = Self.opened()
        #expect(TutorialVideoSample.shaped(opened, for: .videoRecording, broll: nil) == opened)
        #expect(TutorialVideoSample.shaped(opened, for: .videoTwoClips, broll: nil) == opened)
        #expect(TutorialVideoSample.shaped(opened, for: .videoTalk, broll: Self.broll) == opened)
    }

    @Test("Each video sample has a folder of its own, so opening one never rewrites a file another window is reading")
    func eachSampleHasItsOwnFolder() {
        let samples: [TutorialSample] = [.videoRecording, .videoTwoClips, .videoTalk]
        let folders = Set(samples.map(TutorialVideoSample.folderName))
        #expect(folders.count == samples.count)
    }
}
