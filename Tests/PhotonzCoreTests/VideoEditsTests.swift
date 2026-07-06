import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("VideoEdits persistence")
struct VideoEditsTests {

    private let videoSize = CGSize(width: 1920, height: 1080)

    private func makeEdits() -> VideoEdits {
        VideoEdits(
            trim: VideoTrim(inPoint: 1, outPoint: 2, duration: 10),
            crop: VideoCrop(rect: CGRect(x: 100, y: 50, width: 800, height: 600), videoSize: videoSize))
    }

    // MARK: - Value semantics

    @Test func roundTripsThroughJSON() throws {
        let edits = makeEdits()
        let data = try JSONEncoder().encode(edits)
        let decoded = try JSONDecoder().decode(VideoEdits.self, from: data)
        #expect(decoded == edits)
    }

    @Test func isEmptyOnlyWhenNoEdits() {
        #expect(VideoEdits().isEmpty)
        #expect(!VideoEdits(trim: VideoTrim(inPoint: 1, outPoint: 2, duration: 10)).isEmpty)
        #expect(!makeEdits().isEmpty)
    }

    @Test func normalizedDropsFullClipTrim() {
        let edits = VideoEdits(trim: VideoTrim(duration: 10))
        #expect(edits.normalized(videoSize: videoSize).isEmpty)
    }

    @Test func normalizedDropsFullFrameCrop() {
        let edits = VideoEdits(crop: VideoCrop(fullFrame: videoSize))
        #expect(edits.normalized(videoSize: videoSize).isEmpty)
    }

    @Test func normalizedKeepsRealEdits() {
        let normalized = makeEdits().normalized(videoSize: videoSize)
        #expect(normalized.trim != nil)
        #expect(normalized.crop != nil)
    }

    // MARK: - Sidecar IO

    @Test func sidecarURLSharesTheBasename() {
        let media = URL(fileURLWithPath: "/a/b/Recording 2026-07-04 at 18.32.19.mp4")
        let sidecar = VideoEditsSidecar.url(for: media)
        #expect(sidecar.path == "/a/b/Recording 2026-07-04 at 18.32.19.photonzedits")
    }

    @Test func sidecarExtensionIsNotACaptureKind() {
        // The capture folder scan must never surface a sidecar as history entry.
        let sidecar = VideoEditsSidecar.url(for: URL(fileURLWithPath: "/a/r.mp4"))
        #expect(CaptureLibrary.kind(forPathExtension: sidecar.pathExtension) == nil)
    }

    @Test func savesAndLoadsNextToTheMedia() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoEditsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("Recording.mp4")

        let edits = makeEdits()
        VideoEditsSidecar.save(edits, for: media)
        #expect(VideoEditsSidecar.load(for: media) == edits)
    }

    @Test func loadReturnsNilWhenNoSidecarExists() {
        let media = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoEditsTests-missing-\(UUID().uuidString).mp4")
        #expect(VideoEditsSidecar.load(for: media) == nil)
    }

    @Test func savingEmptyEditsRemovesTheSidecar() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoEditsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("Recording.mp4")

        VideoEditsSidecar.save(makeEdits(), for: media)
        #expect(FileManager.default.fileExists(atPath: VideoEditsSidecar.url(for: media).path))

        VideoEditsSidecar.save(VideoEdits(), for: media)
        #expect(!FileManager.default.fileExists(atPath: VideoEditsSidecar.url(for: media).path))
    }
}
