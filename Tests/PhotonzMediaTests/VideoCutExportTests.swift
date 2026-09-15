import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzMedia
import Testing

/// What a cut recording actually turns into, checked against real MP4s rather
/// than against bookkeeping.
///
/// `TestClip` writes a brightness ramp: red climbs from 0 at the first frame to
/// 1 at the last. That makes a frame self-identifying — read its red channel and
/// you know which moment of the SOURCE it came from — which is how these tests
/// prove a dropped piece is really gone and a join really joins, instead of
/// only proving the file came out the right length.
@Suite("Cutting a recording, end to end")
struct VideoCutExportTests {

    /// Where in the source (0...1) the frame at this brightness was recorded.
    private func sourceFraction(ofFrameAt seconds: Double, in url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        guard let image = try? await generator.image(
            at: CMTime(seconds: seconds, preferredTimescale: 600)).image else { return nil }
        return redLevel(of: image)
    }

    /// The red channel of the frame's centre pixel, 0...1.
    private func redLevel(of image: CGImage) -> Double? {
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Draw the whole frame down to one pixel: the clip is a flat colour per
        // frame, so the average IS the colour.
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Double(pixel[0]) / 255.0
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
        let early = try #require(await sourceFraction(ofFrameAt: 1.5, in: out))
        #expect(abs(early - 1.5 / 6.0) < 0.12,
                "a frame 1.5s in should look like source 1.5s, read \(early * 6)s")

        // Half a second AFTER the join is source 4.5s, NOT source 2.5s. This is
        // the whole claim: the dropped two seconds are not in the file.
        let late = try #require(await sourceFraction(ofFrameAt: 2.5, in: out))
        #expect(abs(late - 4.5 / 6.0) < 0.12,
                "a frame 2.5s in should look like source 4.5s, read \(late * 6)s")
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
        let first = try #require(await sourceFraction(ofFrameAt: 0.2, in: out))
        #expect(abs(first - 3.2 / 6.0) < 0.12,
                "the export should open on source 3.2s, read \(first * 6)s")
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
