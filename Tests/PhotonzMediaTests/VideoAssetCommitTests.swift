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

    // A save long enough to wait for draws a bar in the corner, and a bar
    // needs a number. This is the number: the encoder's own count, threaded out
    // of the commit. Without it the bar would sit at zero for the whole save,
    // which is the silence the bar exists to end.
    @Test func aCommitReportsHowFarThroughTheEncodeItIs() async throws {
        let (dir, media) = try await makeRecording(seconds: 4)
        defer { TestClip.cleanUp(dir) }
        let full = await TestClip.duration(of: media)

        let reported = Reported()
        let edits = VideoEdits(trim: VideoTrim(inPoint: 0, outPoint: full - 0.5, duration: full))
        let plan = try #require(VideoCommitPlanner.plan(mediaURL: media, edits: edits))
        let started = Date()
        try await VideoAssetCommit.commit(plan, onProgress: { reported.add($0) })
        let took = Date().timeIntervalSince(started)

        let fractions = reported.all
        #expect(!fractions.isEmpty, "a commit that re-encodes has to say how far through it is")
        #expect(fractions.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(fractions.last == 1, "the last word from a finished encode is that it is finished")
        // Readings arrive about five times a second, so a commit that ran for
        // longer than that has to have said something before it finished. A
        // commit shorter than one interval is not held to it: that is a machine
        // being fast, not the plumbing being broken, and pinning it would make
        // this flaky on exactly the runs where the bar never appears anyway.
        if took > 0.5 {
            #expect(fractions.count > 1,
                    "a \(String(format: "%.2f", took))s encode said nothing until it was over")
        }
    }

    /// Collects the fractions off whichever thread the encoder reports them on.
    private final class Reported: @unchecked Sendable {
        private let lock = NSLock()
        private var fractions: [Double] = []
        func add(_ fraction: Double) {
            lock.lock(); defer { lock.unlock() }
            fractions.append(fraction)
        }
        var all: [Double] {
            lock.lock(); defer { lock.unlock() }
            return fractions
        }
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

    // MARK: - A save that cannot happen

    // A failed save must FAIL, loudly, and leave everything as it was: the
    // recording untouched on disk and the edits still in the window. The app
    // reads the thrown error back to the person in an alert; the thing under
    // test here is that it throws at all rather than reporting a quiet
    // success, which is what "I click Save and it does nothing" was made of.
    @Test func aSaveWithNothingToReadFromFailsRatherThanReportingSuccess() async throws {
        let (dir, media) = try await makeRecording()
        defer { TestClip.cleanUp(dir) }
        let full = await TestClip.duration(of: media)
        let edits = VideoEdits(trim: VideoTrim(inPoint: 1, outPoint: 2, duration: full))
        let plan = try #require(VideoCommitPlanner.plan(mediaURL: media, edits: edits))

        // The recording goes away between the plan and the commit, which is
        // what a file deleted, renamed or unmounted underneath you looks like.
        try FileManager.default.removeItem(at: media)

        await #expect(throws: (any Error).self) {
            try await VideoAssetCommit.commit(plan)
        }
    }

    // Nothing half-written is left behind either: a failed commit must not
    // leave a preserved "original" that a later save would then edit FROM,
    // which would quietly make the failure permanent.
    @Test func aFailedSaveLeavesNoOriginalBehindForTheNextSaveToTrust() async throws {
        let (dir, media) = try await makeRecording()
        defer { TestClip.cleanUp(dir) }
        let full = await TestClip.duration(of: media)
        let edits = VideoEdits(trim: VideoTrim(inPoint: 1, outPoint: 2, duration: full))
        let plan = try #require(VideoCommitPlanner.plan(mediaURL: media, edits: edits))
        try FileManager.default.removeItem(at: media)

        _ = try? await VideoAssetCommit.commit(plan)

        #expect(!VideoOriginals.exists(for: media),
                "a commit that never ran must not leave a preserved original behind")
    }
}
