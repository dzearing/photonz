import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzMedia
import Testing

/// The promise consumers rely on: after a save, **the stored file is the
/// trimmed one**. Anything that hands out the recording — drag from history,
/// copy to the clipboard, a future consumer nobody has written yet — gets the
/// trimmed media without knowing trimming exists.
@Suite("Video save commits to the stored asset")
struct VideoAssetCommitTests {

    private func makeRecording(seconds: Double = 3,
                               size: CGSize = CGSize(width: 160, height: 120)) async throws -> (dir: URL, media: URL) {
        let dir = TestClip.makeScratchDirectory()
        let media = dir.appendingPathComponent("Recording.mp4")
        try await TestClip.write(to: media, seconds: seconds, size: size)
        return (dir, media)
    }

    private func pixelSize(of url: URL) async -> CGSize {
        await VideoExporter.orientedNaturalSize(of: url)
    }

    // MARK: - The regression that matters

    @Test func savingATrimMakesTheStoredFileTheTrimmedOne() async throws {
        let (dir, media) = try await makeRecording()
        defer { TestClip.cleanUp(dir) }
        let full = await TestClip.duration(of: media)

        let edits = VideoEdits(trim: VideoTrim(inPoint: 1, outPoint: 2, duration: full))
        let plan = try #require(VideoCommitPlanner.plan(mediaURL: media, edits: edits))
        try await VideoAssetCommit.commit(plan)

        let stored = await TestClip.duration(of: media)
        #expect(abs(stored - 1) < 0.15,
                "the stored recording should now BE ~1s of media, got \(stored)s")
    }

    @Test func theUntouchedOriginalIsKeptSoTheEditStaysReversible() async throws {
        let (dir, media) = try await makeRecording()
        defer { TestClip.cleanUp(dir) }
        let full = await TestClip.duration(of: media)

        let edits = VideoEdits(trim: VideoTrim(inPoint: 1, outPoint: 2, duration: full))
        try await VideoAssetCommit.commit(try #require(VideoCommitPlanner.plan(mediaURL: media, edits: edits)))

        let original = VideoOriginals.url(for: media)
        #expect(FileManager.default.fileExists(atPath: original.path))
        let originalDuration = await TestClip.duration(of: original)
        #expect(abs(originalDuration - full) < 0.001, "the original keeps its full length")
        #expect(original.path.contains("/.photonz-originals/"),
                "originals hide from the capture folder scan")
    }

    @Test func aSavedRecordingReadsAsCleanAndRecordsHowItWasDerived() async throws {
        let (dir, media) = try await makeRecording()
        defer { TestClip.cleanUp(dir) }
        let full = await TestClip.duration(of: media)

        let edits = VideoEdits(trim: VideoTrim(inPoint: 1, outPoint: 2, duration: full))
        try await VideoAssetCommit.commit(try #require(VideoCommitPlanner.plan(mediaURL: media, edits: edits)))

        let committed = VideoSaveState.committedEdits(for: media)
        #expect(committed.trim?.inPoint == 1)
        #expect(!VideoSaveState.needsSave(edits: edits, committed: committed))
        #expect(VideoCommitPlanner.plan(mediaURL: media, edits: edits) == nil,
                "saving again with the same edits is a no-op")
    }

    // MARK: - Composition and reversal

    @Test func savingTwiceMeasuresTheSecondTrimAgainstTheOriginalNotTheFirstSave() async throws {
        let (dir, media) = try await makeRecording()
        defer { TestClip.cleanUp(dir) }
        let full = await TestClip.duration(of: media)

        try await VideoAssetCommit.commit(try #require(VideoCommitPlanner.plan(
            mediaURL: media, edits: VideoEdits(trim: VideoTrim(inPoint: 1, outPoint: 2, duration: full)))))
        #expect(abs((await TestClip.duration(of: media)) - 1) < 0.15)

        // A tighter window, still expressed in ORIGINAL-file seconds.
        try await VideoAssetCommit.commit(try #require(VideoCommitPlanner.plan(
            mediaURL: media, edits: VideoEdits(trim: VideoTrim(inPoint: 1.2, outPoint: 1.8, duration: full)))))

        let stored = await TestClip.duration(of: media)
        #expect(abs(stored - 0.6) < 0.15,
                "expected ~0.6s of the original, got \(stored)s (a stacked trim would be shorter)")
    }

    @Test func clearingTheTrimAndSavingRestoresTheFullClip() async throws {
        let (dir, media) = try await makeRecording()
        defer { TestClip.cleanUp(dir) }
        let full = await TestClip.duration(of: media)

        try await VideoAssetCommit.commit(try #require(VideoCommitPlanner.plan(
            mediaURL: media, edits: VideoEdits(trim: VideoTrim(inPoint: 1, outPoint: 2, duration: full)))))
        #expect(abs((await TestClip.duration(of: media)) - 1) < 0.15)

        try await VideoAssetCommit.commit(try #require(VideoCommitPlanner.plan(
            mediaURL: media, edits: VideoEdits())))

        let restored = await TestClip.duration(of: media)
        #expect(abs(restored - full) < 0.001, "the full clip comes back byte-for-byte from the original")
        #expect(VideoEditsSidecar.load(for: media) == nil, "nothing left to describe")
        #expect(VideoSaveState.committedEdits(for: media).isEmpty)
    }

    // MARK: - Crop

    @Test func savingACropMakesTheStoredFileTheCroppedSize() async throws {
        let (dir, media) = try await makeRecording(size: CGSize(width: 160, height: 120))
        defer { TestClip.cleanUp(dir) }

        let crop = VideoCrop(rect: CGRect(x: 0, y: 0, width: 80, height: 60),
                             videoSize: CGSize(width: 160, height: 120))
        try await VideoAssetCommit.commit(try #require(VideoCommitPlanner.plan(
            mediaURL: media, edits: VideoEdits(crop: crop))))

        let size = await pixelSize(of: media)
        #expect(size == CGSize(width: 80, height: 60), "stored file should be the cropped size, got \(size)")
        let originalSize = await pixelSize(of: VideoOriginals.url(for: media))
        #expect(originalSize == CGSize(width: 160, height: 120))
    }

    // MARK: - Identity

    @Test func theStoredRecordingKeepsItsNameAndCreationDate() async throws {
        let (dir, media) = try await makeRecording()
        defer { TestClip.cleanUp(dir) }
        let full = await TestClip.duration(of: media)
        let before = try FileManager.default.attributesOfItem(atPath: media.path)[.creationDate] as? Date

        try await VideoAssetCommit.commit(try #require(VideoCommitPlanner.plan(
            mediaURL: media, edits: VideoEdits(trim: VideoTrim(inPoint: 1, outPoint: 2, duration: full)))))

        #expect(FileManager.default.fileExists(atPath: media.path))
        let after = try FileManager.default.attributesOfItem(atPath: media.path)[.creationDate] as? Date
        let drift = abs((after ?? .distantPast).timeIntervalSince(before ?? .distantFuture))
        #expect(drift < 1, "history sorts by creation date — a save must not reshuffle the recording")
    }
}
