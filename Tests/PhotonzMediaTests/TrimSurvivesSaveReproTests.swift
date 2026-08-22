import Foundation
import PhotonzCore
import PhotonzMedia
import Testing

/// Reproduction of the reported defect, in the shape the shipped code has it:
/// trimming a recording writes a `.photonzedits` sidecar and leaves the media
/// file untouched, so every consumer that hands out the stored file (drag from
/// history, copy to clipboard) hands out the full-length original.
///
/// Kept as the record of the defect's mechanism: writing an edits record never
/// changed the media, while the MP4 re-encode already trimmed correctly — so the
/// fix was to route Save through it and commit the result (see
/// `VideoAssetCommitTests` for the promise that now holds).
@Suite("Trim survives save — reproduction")
struct TrimSurvivesSaveReproTests {

    @Test func sidecarRecordsTheTrimButTheStoredFileStaysFullLength() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let media = dir.appendingPathComponent("Recording.mp4")
        try await TestClip.write(to: media, seconds: 3)

        let full = await TestClip.duration(of: media)
        #expect(abs(full - 3) < 0.2, "synthesized clip should be ~3s, got \(full)")

        // What the video editor does today when you trim: persist a sidecar.
        let trim = VideoTrim(inPoint: 1, outPoint: 2, duration: full)
        VideoEditsSidecar.save(VideoEdits(trim: trim), for: media)

        // What a consumer gets: the stored file, still the whole 3 seconds.
        let afterTrim = await TestClip.duration(of: media)
        #expect(abs(afterTrim - full) < 0.001,
                "REPRO: the stored file is untouched by the trim (\(afterTrim)s)")
    }

    /// Sizing question from the report: does the existing MP4 re-encode apply
    /// the trim correctly? It does — so the fix is about routing Save through it
    /// and committing the result, not about writing new trim math.
    @Test func exportMP4AlreadyProducesACorrectlyTrimmedFile() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let media = dir.appendingPathComponent("Recording.mp4")
        try await TestClip.write(to: media, seconds: 3)
        let full = await TestClip.duration(of: media)

        let out = dir.appendingPathComponent("Exported.mp4")
        try await VideoExporter.exportMP4(from: media, to: out,
                                          trim: VideoTrim(inPoint: 1, outPoint: 2, duration: full),
                                          crop: nil)

        let exported = await TestClip.duration(of: out)
        #expect(abs(exported - 1) < 0.15, "exported clip should be ~1s, got \(exported)")
    }
}
