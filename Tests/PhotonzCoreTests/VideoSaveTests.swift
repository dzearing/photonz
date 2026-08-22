import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("Video save — originals, committed state, commit plan")
struct VideoSaveTests {

    private func scratch() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotonzVideoSaveTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func touch(_ url: URL, bytes: String = "x") {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? Data(bytes.utf8).write(to: url)
    }

    // MARK: - Where the preserved original lives

    @Test func originalSitsInAHiddenSiblingFolderKeepingTheMediaExtension() {
        let media = URL(fileURLWithPath: "/tmp/shots/Recording 1.mp4")
        let original = VideoOriginals.url(for: media)
        #expect(original.lastPathComponent == "Recording 1.mp4")
        #expect(original.deletingLastPathComponent().lastPathComponent == ".photonz-originals")
        #expect(original.deletingLastPathComponent().deletingLastPathComponent().path == "/tmp/shots")
    }

    @Test func editSourceIsTheMediaFileUntilAnOriginalIsPreserved() {
        let dir = scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("Recording.mp4")
        touch(media)

        #expect(!VideoOriginals.exists(for: media))
        #expect(VideoOriginals.editSource(for: media) == media)

        touch(VideoOriginals.url(for: media))
        #expect(VideoOriginals.exists(for: media))
        #expect(VideoOriginals.editSource(for: media) == VideoOriginals.url(for: media))
    }

    // MARK: - What the stored file already has baked in

    @Test func nothingIsCommittedWhenNoOriginalIsPreserved() {
        let dir = scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("Recording.mp4")
        touch(media)

        // A legacy sidecar describes a trim that was never baked into the file.
        VideoEditsSidecar.save(VideoEdits(trim: VideoTrim(inPoint: 1, outPoint: 2, duration: 3)),
                               for: media)

        #expect(VideoSaveState.committedEdits(for: media).isEmpty,
                "with no preserved original the file is raw, whatever the sidecar claims")
    }

    @Test func committedEditsAreTheSidecarOnceAnOriginalIsPreserved() {
        let dir = scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("Recording.mp4")
        touch(media)
        touch(VideoOriginals.url(for: media))

        let trim = VideoTrim(inPoint: 1, outPoint: 2, duration: 3)
        VideoEditsSidecar.save(VideoEdits(trim: trim), for: media)

        #expect(VideoSaveState.committedEdits(for: media).trim == trim)
    }

    // MARK: - Dirty rule

    @Test func aLegacySidecarTrimReadsAsUnsavedSoTheUserIsPromptedNotSilentlyLosingIt() {
        let pending = VideoEdits(trim: VideoTrim(inPoint: 1, outPoint: 2, duration: 3))
        #expect(VideoSaveState.needsSave(edits: pending, committed: VideoEdits()))
    }

    @Test func matchingEditsAreClean() {
        let trim = VideoTrim(inPoint: 1, outPoint: 2, duration: 3)
        #expect(!VideoSaveState.needsSave(edits: VideoEdits(trim: trim),
                                          committed: VideoEdits(trim: trim)))
        #expect(!VideoSaveState.needsSave(edits: VideoEdits(), committed: VideoEdits()))
    }

    @Test func subSampleDriftIsNotADirtyDocument() {
        let trim = VideoTrim(inPoint: 1, outPoint: 2, duration: 3)
        let drifted = VideoTrim(inPoint: 1 + 1e-9, outPoint: 2 - 1e-9, duration: 3)
        #expect(!VideoSaveState.needsSave(edits: VideoEdits(trim: drifted),
                                          committed: VideoEdits(trim: trim)))
    }

    @Test func aRealTrimChangeIsDirty() {
        let committed = VideoTrim(inPoint: 1, outPoint: 2, duration: 3)
        let tightened = VideoTrim(inPoint: 1.5, outPoint: 2, duration: 3)
        #expect(VideoSaveState.needsSave(edits: VideoEdits(trim: tightened),
                                         committed: VideoEdits(trim: committed)))
    }

    @Test func clearingACommittedTrimIsDirtyBecauseTheFileMustGoBackToFullLength() {
        let committed = VideoTrim(inPoint: 1, outPoint: 2, duration: 3)
        #expect(VideoSaveState.needsSave(edits: VideoEdits(),
                                         committed: VideoEdits(trim: committed)))
    }

    @Test func aCropChangeIsDirty() {
        let size = CGSize(width: 100, height: 80)
        let a = VideoCrop(rect: CGRect(x: 0, y: 0, width: 50, height: 40), videoSize: size)
        let b = VideoCrop(rect: CGRect(x: 10, y: 0, width: 50, height: 40), videoSize: size)
        #expect(VideoSaveState.needsSave(edits: VideoEdits(crop: b), committed: VideoEdits(crop: a)))
        #expect(!VideoSaveState.needsSave(edits: VideoEdits(crop: a), committed: VideoEdits(crop: a)))
    }

    // MARK: - Commit plan

    @Test func nothingToCommitPlansNothing() {
        let media = URL(fileURLWithPath: "/tmp/shots/Recording.mp4")
        #expect(VideoCommitPlanner.plan(mediaURL: media, edits: VideoEdits(),
                                        committed: VideoEdits(), hasOriginal: false) == nil)
    }

    @Test func theFirstCommitReadsTheMediaFileAndPreservesItAsTheOriginal() throws {
        let media = URL(fileURLWithPath: "/tmp/shots/Recording.mp4")
        let edits = VideoEdits(trim: VideoTrim(inPoint: 1, outPoint: 2, duration: 3))
        let plan = try #require(VideoCommitPlanner.plan(mediaURL: media, edits: edits,
                                                        committed: VideoEdits(), hasOriginal: false))
        #expect(plan.source == media)
        #expect(plan.destination == media)
        #expect(plan.originalToPreserve == VideoOriginals.url(for: media))
        #expect(plan.edits == edits)
    }

    @Test func laterCommitsReEncodeFromThePreservedOriginalSoTrimsNeverStack() throws {
        let media = URL(fileURLWithPath: "/tmp/shots/Recording.mp4")
        let committed = VideoEdits(trim: VideoTrim(inPoint: 1, outPoint: 2, duration: 3))
        let tighter = VideoEdits(trim: VideoTrim(inPoint: 1.2, outPoint: 1.8, duration: 3))
        let plan = try #require(VideoCommitPlanner.plan(mediaURL: media, edits: tighter,
                                                        committed: committed, hasOriginal: true))
        #expect(plan.source == VideoOriginals.url(for: media),
                "the trim is always measured against the untouched original")
        #expect(plan.destination == media)
        #expect(plan.originalToPreserve == nil, "the original is preserved once, never re-preserved")
        #expect(plan.edits == tighter)
    }

    @Test func revertingToTheFullClipCopiesTheOriginalBackWithNoReEncode() throws {
        let media = URL(fileURLWithPath: "/tmp/shots/Recording.mp4")
        let committed = VideoEdits(trim: VideoTrim(inPoint: 1, outPoint: 2, duration: 3))
        let plan = try #require(VideoCommitPlanner.plan(mediaURL: media, edits: VideoEdits(),
                                                        committed: committed, hasOriginal: true))
        #expect(plan.source == VideoOriginals.url(for: media))
        #expect(plan.edits.isEmpty)
        #expect(!plan.requiresReencode, "restoring the full clip is a copy, not a re-encode")
    }
}
