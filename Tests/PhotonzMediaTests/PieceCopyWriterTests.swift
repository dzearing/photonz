import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import Testing

/// An edit that is nothing but cuts, written by copying what it keeps
/// (`PieceCopyWriter`), checked frame by frame against real MP4s stored the
/// way the Mac stores a screen recording.
@Suite("Copying the pieces of a cut recording")
struct PieceCopyWriterTests {

    private static let fps = Double(TestClip.fps)

    /// Which frame of the source the timeline shows at a moment of it.
    private static func sourceFrame(atMS ms: Double) -> Int { Int((ms / 1000 * fps).rounded(.down)) }

    /// Checks the frame showing at each sampled moment of `film` is the frame
    /// the timeline showed at the matching moment of the source. Moments
    /// within two milliseconds of a frame's edge are skipped, since either
    /// frame is right there, and the first and last are 5ms inside the piece:
    /// the frame grabber asks on a grid of 1/600s, so "1ms in" can land on the
    /// moment before the piece starts.
    private func expectFramesMatch(_ film: URL, pieces: [Range<Int>],
                                   sourceLocation: SourceLocation = #_sourceLocation) async throws {
        var start = 0.0
        for piece in pieces {
            let length = Double(piece.count)
            var moments: [Double] = [5, length / 2, length - 5]
            moments += stride(from: 40.0, to: length, by: 170).map { $0 }
            for offset in moments where offset >= 0 && offset < length {
                let sourceMS = Double(piece.lowerBound) + offset
                let edge = (sourceMS / 1000 * Self.fps).truncatingRemainder(dividingBy: 1)
                guard edge > 0.06, edge < 0.94 else { continue }
                let code = try #require(await TestClip.frameCode(at: (start + offset) / 1000, in: film),
                                        sourceLocation: sourceLocation)
                #expect(code.index == Self.sourceFrame(atMS: sourceMS),
                        "at \(start + offset)ms of the file: frame \(code.index), the timeline shows frame \(Self.sourceFrame(atMS: sourceMS)) (source \(sourceMS)ms)",
                        sourceLocation: sourceLocation)
            }
            start += length
        }
    }

    /// Where each key frame shows on the timeline's clock, in whole
    /// milliseconds rounded up so a piece starting there starts on it.
    private static func keyFrameMS(of url: URL) async throws -> [Int] {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let segment = try #require(try await track.load(.segments).first)
        let offset = segment.timeMapping.source.start.seconds - segment.timeMapping.target.start.seconds
        let cursor = try #require(track.makeSampleCursorAtFirstSampleInDecodeOrder())
        var keys: [Int] = []
        repeat {
            if cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue {
                keys.append(Int(((cursor.presentationTimeStamp.seconds - offset) * 1000).rounded(.up)))
            }
        } while cursor.stepInDecodeOrder(byCount: 1) == 1
        return keys.sorted()
    }

    @Test("Cuts between key frames keep exactly the frames the timeline shows")
    func cutsLandOnTheTimelinesFrames() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let source = dir.appendingPathComponent("recording.mp4")
        try await TestClip.write(to: source, seconds: 8, size: CGSize(width: 320, height: 240),
                                 likeAScreenRecording: true)
        let out = dir.appendingPathComponent("edit.mp4")
        // Mid-frame cuts, a piece carried earlier, and one shorter than a
        // second inside a single group of frames.
        let pieces = [450..<2_017, 5_210..<7_300, 2_517..<2_800, 3_900..<4_955]
        let outcome = try await PieceCopyWriter.write(source: source, ranges: pieces, mix: [],
                                                      soundURLs: [:], to: out)
        #expect(outcome.copiedFrames > 0)
        #expect(outcome.renderedFrames > 0)
        let length = Double(pieces.reduce(0) { $0 + $1.count }) / 1000
        let landed = await TestClip.duration(of: out)
        #expect(abs(landed - length) < 1 / Self.fps, "ran \(landed)s, the edit is \(length)s")
        try await expectFramesMatch(out, pieces: pieces)
    }

    @Test("Cuts on key frames copy every frame and draw none")
    func cutsOnKeyFramesCopyEverything() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let source = dir.appendingPathComponent("recording.mp4")
        try await TestClip.write(to: source, seconds: 5, size: CGSize(width: 320, height: 240),
                                 likeAScreenRecording: true)
        let out = dir.appendingPathComponent("edit.mp4")
        // Whole groups of frames, from one key frame to the next, read off the
        // file rather than assumed: the encoder decides where they fall.
        let keys = try await Self.keyFrameMS(of: source)
        try #require(keys.count >= 4)
        let pieces = [keys[2]..<(keys[3] - 1), keys[0]..<(keys[1] - 1)]
        let outcome = try await PieceCopyWriter.write(source: source, ranges: pieces, mix: [],
                                                      soundURLs: [:], to: out)
        #expect(outcome.renderedFrames == 0)
        #expect(outcome.copiedFrames > 0)
        try await expectFramesMatch(out, pieces: pieces)
    }

    @Test("The mix rides under the copied pictures, as long as the edit")
    func theSoundComesAlong() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let source = dir.appendingPathComponent("recording.mp4")
        try await TestClip.write(to: source, seconds: 6, size: CGSize(width: 320, height: 240),
                                 likeAScreenRecording: true)
        let tone = dir.appendingPathComponent("tone.m4a")
        try TestTone.writeFlat(to: tone, seconds: 4)
        var document = PhotonzDocument(canvasSize: CGSize(width: 320, height: 240), layers: [])
        let sound = SoundRef(durationMS: 4000)
        _ = document.addSound(sound, name: "tone", atMS: 0)
        document.durationMS = 3_500

        let out = dir.appendingPathComponent("edit.mp4")
        let pieces = [300..<2_000, 3_700..<5_500]
        try await PieceCopyWriter.write(
            source: source, ranges: pieces,
            mix: AudioMixSegment.windowed(document.audioMix(), to: 0..<3_500),
            soundURLs: [sound.id: tone], to: out)
        let asset = AVURLAsset(url: out)
        #expect(try await !asset.loadTracks(withMediaType: .audio).isEmpty)
        let landed = try await asset.load(.duration).seconds
        #expect(abs(landed - 3.5) < 1 / Self.fps)
        try await expectFramesMatch(out, pieces: pieces)
    }

    @Test("A file whose picture is itself an edit is left to the ordinary path")
    func anEditedFileIsNotCopied() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let source = dir.appendingPathComponent("recording.mp4")
        try await TestClip.write(to: source, seconds: 3, size: CGSize(width: 320, height: 240),
                                 likeAScreenRecording: true)
        // Two stretches of it laid back to back in a QuickTime movie, which
        // keeps them as two entries of an edit list rather than one stretch.
        let asset = AVURLAsset(url: source)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let composition = AVMutableComposition()
        let lane = try #require(composition.addMutableTrack(withMediaType: .video,
                                                            preferredTrackID: kCMPersistentTrackID_Invalid))
        try lane.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1)),
                                 of: track, at: .zero)
        try lane.insertTimeRange(CMTimeRange(start: CMTime(value: 2, timescale: 1),
                                             duration: CMTime(value: 1, timescale: 1)),
                                 of: track, at: CMTime(value: 1, timescale: 1))
        let session = try #require(AVAssetExportSession(asset: composition,
                                                        presetName: AVAssetExportPresetPassthrough))
        let edited = dir.appendingPathComponent("edited.mov")
        try await session.export(to: edited, as: .mov)
        await #expect(throws: PieceCopyWriter.CopyError.self) {
            try await PieceCopyWriter.write(source: edited, ranges: [0..<1_500], mix: [],
                                            soundURLs: [:], to: dir.appendingPathComponent("out.mp4"))
        }
    }
}
