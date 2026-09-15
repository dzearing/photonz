import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzMedia
import Testing

/// What a cut recording actually turns into, checked against real MP4s rather
/// than against bookkeeping.
///
/// `TestClip` paints each frame's own number into the picture as black and
/// white stripes. That makes a frame self-identifying — read the stripes and
/// you know which moment of the SOURCE it came from — which is how these tests
/// prove a dropped piece is really gone and a join really joins, instead of
/// only proving the file came out the right length.
@Suite("Cutting a recording, end to end")
struct VideoCutExportTests {

    /// Which second of the SOURCE recording the frame shown at `seconds` came
    /// from, read out of the frame's own stripes.
    private func sourceSeconds(ofFrameAt seconds: Double, in url: URL,
                               sourceLocation: SourceLocation = #_sourceLocation) async throws -> Double {
        let code = try #require(await TestClip.frameCode(at: seconds, in: url),
                                "no frame at \(seconds)s of \(url.lastPathComponent)",
                                sourceLocation: sourceLocation)
        // Black and white survive any colour handling, so a faint read means
        // the picture itself stopped carrying a legible number, not that the
        // machine renders colour differently.
        #expect(code.margin > 0.2,
                "the stripes at \(seconds)s read faintly (margin \(code.margin)): the frame number is not legible",
                sourceLocation: sourceLocation)
        return code.seconds
    }

    @Test("Exporting a recording with the middle dropped writes only what is left")
    func exportDropsTheMiddle() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let source = dir.appendingPathComponent("source.mp4")
        try await TestClip.write(to: source, seconds: 6)

        // Keep 0...2 and 4...6; drop the two seconds in the middle.
        var cuts = VideoCutList(duration: 6)
        let did1 = cuts.split(atTimeline: 2)
        #expect(did1)
        let did2 = cuts.split(atTimeline: 4)
        #expect(did2)
        let did3 = cuts.removePiece(at: 1)
        #expect(did3)
        #expect(cuts.timelineDuration == 4)

        let out = dir.appendingPathComponent("cut.mp4")
        try await VideoExporter.exportMP4(from: source, to: out, cuts: cuts, crop: nil)

        let length = await TestClip.duration(of: out)
        #expect(abs(length - 4) < 0.2, "kept four of six seconds, got \(length)")

        // Half a second BEFORE the join is still the opening piece.
        let early = try await sourceSeconds(ofFrameAt: 1.5, in: out)
        #expect(abs(early - 1.5) < 0.1, "a frame 1.5s in should be source 1.5s, read \(early)s")

        // Half a second AFTER the join is source 4.5s, NOT source 2.5s. This is
        // the whole claim: the dropped two seconds are not in the file.
        let late = try await sourceSeconds(ofFrameAt: 2.5, in: out)
        #expect(abs(late - 4.5) < 0.1, "a frame 2.5s in should be source 4.5s, read \(late)s")
        #expect(late > early, "time still runs forwards across the join")
    }

    @Test("Dropping the first piece makes the recording start at the cut")
    func exportStartsAtTheCut() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let source = dir.appendingPathComponent("source.mp4")
        try await TestClip.write(to: source, seconds: 6)

        var cuts = VideoCutList(duration: 6)
        let did4 = cuts.split(atTimeline: 3)
        #expect(did4)
        let did5 = cuts.removePiece(at: 0)
        #expect(did5)

        let out = dir.appendingPathComponent("cut.mp4")
        try await VideoExporter.exportMP4(from: source, to: out, cuts: cuts, crop: nil)

        let length = await TestClip.duration(of: out)
        #expect(abs(length - 3) < 0.2)
        // The first frame out is the frame the cut was made on.
        let first = try await sourceSeconds(ofFrameAt: 0.2, in: out)
        #expect(abs(first - 3.2) < 0.1, "the export should open on source 3.2s, read \(first)s")
    }

    @Test("The frame reader tells a cut recording from an uncut one")
    func frameReaderTellsCutFromUncut() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let source = dir.appendingPathComponent("source.mp4")
        try await TestClip.write(to: source, seconds: 6)

        // The recording itself reads as itself: 2.5s in is source 2.5s.
        let inSource = try await sourceSeconds(ofFrameAt: 2.5, in: source)
        #expect(abs(inSource - 2.5) < 0.1, "the source at 2.5s should be source 2.5s, read \(inSource)s")

        // An export that drops nothing leaves every moment where it was. This
        // is what a cut that quietly did nothing would produce.
        let whole = VideoCutList(duration: 6)
        let uncut = dir.appendingPathComponent("uncut.mp4")
        try await VideoExporter.exportMP4(from: source, to: uncut, cuts: whole, crop: nil)
        let keptEverything = try await sourceSeconds(ofFrameAt: 2.5, in: uncut)
        #expect(abs(keptEverything - 2.5) < 0.1,
                "an export with nothing dropped should still be source 2.5s at 2.5s, read \(keptEverything)s")

        // Dropping the middle moves that same moment two seconds along, so the
        // reader would catch an export that kept the dropped piece.
        var cuts = VideoCutList(duration: 6)
        _ = cuts.split(atTimeline: 2)
        _ = cuts.split(atTimeline: 4)
        _ = cuts.removePiece(at: 1)
        let out = dir.appendingPathComponent("cut.mp4")
        try await VideoExporter.exportMP4(from: source, to: out, cuts: cuts, crop: nil)
        let afterTheCut = try await sourceSeconds(ofFrameAt: 2.5, in: out)
        #expect(abs(afterTheCut - 4.5) < 0.1,
                "the cut export at 2.5s should be source 4.5s, read \(afterTheCut)s")
        #expect(afterTheCut - keptEverything > 1.5,
                "the two files must not read alike, or the test could not tell a broken cut from a good one")
    }

    @Test("The player's composition is the kept pieces, back to back")
    func compositionPlaysTheKeptPieces() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let source = dir.appendingPathComponent("source.mp4")
        try await TestClip.write(to: source, seconds: 6)

        var cuts = VideoCutList(duration: 6)
        let did6 = cuts.split(atTimeline: 2)
        #expect(did6)
        let did7 = cuts.split(atTimeline: 4)
        #expect(did7)
        let did8 = cuts.removePiece(at: 1)
        #expect(did8)

        let composition = try #require(
            await VideoCompositionBuilder.composition(of: source, cuts: cuts))
        let length = try await composition.load(.duration).seconds
        #expect(abs(length - 4) < 0.2, "the composition plays four seconds, got \(length)")

        // One asset, so the frames either side of the join are neighbours in it:
        // there is nothing for playback to seek over.
        let track = try #require(try await composition.loadTracks(withMediaType: .video).first)
        let ranges = try await track.load(.segments).map(\.timeMapping.target)
        #expect(ranges.count == 2)
        #expect(abs(ranges[0].start.seconds) < 0.05)
        #expect(abs(ranges[1].start.seconds - ranges[0].duration.seconds) < 0.05,
                "the second piece starts exactly where the first ends: no gap")
    }

    @Test("Saving a cut recording bakes the pieces into the stored file")
    func commitBakesTheCuts() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let media = dir.appendingPathComponent("recording.mp4")
        try await TestClip.write(to: media, seconds: 6)

        var cuts = VideoCutList(duration: 6)
        let did9 = cuts.split(atTimeline: 2)
        #expect(did9)
        let did10 = cuts.removePiece(at: 0)
        #expect(did10)

        let edits = VideoEdits(cuts: cuts)
        let plan = try #require(VideoCommitPlanner.plan(mediaURL: media, edits: edits))
        try await VideoAssetCommit.commit(plan)

        // The file history hands out IS the shortened recording.
        let length = await TestClip.duration(of: media)
        #expect(abs(length - 4) < 0.2, "the stored file is four seconds, got \(length)")
        // The untouched original is still there, so the cut stays reversible.
        #expect(VideoOriginals.exists(for: media))
        let original = await TestClip.duration(of: VideoOriginals.url(for: media))
        #expect(abs(original - 6) < 0.2)
        // And the sidecar remembers how it got that way.
        let recalled = try #require(VideoEditsSidecar.load(for: media))
        #expect(recalled.cuts == cuts)
        #expect(!VideoSaveState.needsSave(edits: edits,
                                          committed: VideoSaveState.committedEdits(for: media)))
    }

    @Test("A copied GIF of a cut recording samples only the kept pieces")
    func animatedExportSkipsDroppedPieces() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let source = dir.appendingPathComponent("source.mp4")
        try await TestClip.write(to: source, seconds: 6)

        var cuts = VideoCutList(duration: 6)
        let did11 = cuts.split(atTimeline: 2)
        #expect(did11)
        let did12 = cuts.split(atTimeline: 4)
        #expect(did12)
        let did13 = cuts.removePiece(at: 1)
        #expect(did13)

        let out = dir.appendingPathComponent("cut.gif")
        try await VideoExporter.exportAnimated(from: source, to: out, format: .gif,
                                               cuts: cuts, targetFPS: 10, maxDimension: 160)
        #expect(FileManager.default.fileExists(atPath: out.path))

        // Ten frames a second over four kept seconds, not over the six recorded.
        let plan = AnimatedExportPlanner.plan(cuts: cuts, sourceSize: CGSize(width: 160, height: 120),
                                              targetFPS: 10, maxDimension: 160)
        #expect(plan.frameCount == 40)
        // No sample lands in the dropped middle.
        for index in 0..<plan.frameCount {
            let t = plan.sampleTime(index)
            #expect(t < 2.0001 || t > 3.9999, "frame \(index) sampled the dropped piece at \(t)s")
        }
    }
}
