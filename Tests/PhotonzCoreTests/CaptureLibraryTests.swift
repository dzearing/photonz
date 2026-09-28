import Foundation
import PhotonzCore
import Testing

@Suite("CaptureLibrary")
struct CaptureLibraryTests {

    private func entry(_ name: String, _ seconds: TimeInterval, _ kind: CaptureKind) -> CaptureEntry {
        CaptureEntry(url: URL(fileURLWithPath: "/tmp/\(name)"),
                     createdAt: Date(timeIntervalSinceReferenceDate: seconds),
                     kind: kind)
    }

    @Test func classifiesImageAndVideoExtensionsCaseInsensitively() {
        #expect(CaptureLibrary.kind(forPathExtension: "png") == .image)
        #expect(CaptureLibrary.kind(forPathExtension: "PNG") == .image)
        #expect(CaptureLibrary.kind(forPathExtension: "heic") == .image)
        #expect(CaptureLibrary.kind(forPathExtension: "mp4") == .video)
        #expect(CaptureLibrary.kind(forPathExtension: "MOV") == .video)
    }

    @Test func skipsNonMediaFiles() {
        #expect(CaptureLibrary.kind(forPathExtension: "json") == nil)
        #expect(CaptureLibrary.kind(forPathExtension: "") == nil)
        #expect(CaptureLibrary.isCapture(pathExtension: "txt") == false)
        #expect(CaptureLibrary.isCapture(pathExtension: "png"))
    }

    @Test func sortsNewestFirst() {
        let a = entry("a.png", 300, .image)
        let b = entry("b.png", 100, .image)
        let c = entry("c.mp4", 200, .video)
        #expect(CaptureLibrary.sortedNewestFirst([b, a, c]).map(\.fileName) == ["a.png", "c.mp4", "b.png"])
    }

    @Test func tiesBreakDeterministicallyByName() {
        let a = entry("a.png", 100, .image)
        let z = entry("z.png", 100, .image)
        // Same timestamp → stable order (z before a, descending by name).
        #expect(CaptureLibrary.sortedNewestFirst([a, z]).map(\.fileName) == ["z.png", "a.png"])
    }

    @Test func entryIdentityIsItsURL() {
        let e = entry("shot.png", 1, .image)
        #expect(e.id == URL(fileURLWithPath: "/tmp/shot.png"))
        #expect(e.fileName == "shot.png")
    }

    // MARK: - Recordings still being saved

    @Test func aRecordingStillBeingSavedIsListedWithTheRest() {
        let shot = entry("Screenshot.png", 100, .image)
        let saving = entry("Recording.mp4", 200, .video)
        let merged = CaptureLibrary.merging(listed: [shot], saving: [saving])
        #expect(merged == [saving, shot])
    }

    @Test func aRecordingThatHasLandedIsListedOnce() {
        let saving = entry("Recording.mp4", 200, .video)
        // The file on disk carries its own date, which wins.
        let landed = entry("Recording.mp4", 150, .video)
        let merged = CaptureLibrary.merging(listed: [landed], saving: [saving])
        #expect(merged == [landed])
    }

    @Test func savingRecordingsTakeTheirPlaceByDate() {
        let newer = entry("b.png", 300, .image)
        let older = entry("a.png", 100, .image)
        let saving = entry("Recording.mp4", 200, .video)
        let merged = CaptureLibrary.merging(listed: [newer, older], saving: [saving])
        #expect(merged.map(\.fileName) == ["b.png", "Recording.mp4", "a.png"])
    }

    @Test func nothingSavingLeavesTheListingAlone() {
        let listed = [entry("b.png", 300, .image), entry("a.png", 100, .image)]
        #expect(CaptureLibrary.merging(listed: listed, saving: []) == listed)
    }
}
