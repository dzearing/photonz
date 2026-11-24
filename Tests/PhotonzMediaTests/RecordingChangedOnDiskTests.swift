import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore
@testable import PhotonzMedia

/// A recording whose file is replaced on disk under the same name is another
/// recording: opened again, its length, size and every frame are the new
/// file's, and nothing filed under the old one can stand in for it.
@MainActor
struct RecordingChangedOnDiskTests {

    enum Way: CaseIterable { case inPlace, replaced }

    /// The way a file changes: written over where it is, or a finished new
    /// file swapped in, as an export or a re-record does.
    private static func put(_ new: URL, over old: URL, _ way: Way) throws {
        switch way {
        case .inPlace:
            let handle = try FileHandle(forWritingTo: old)
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: Data(contentsOf: new))
            try handle.close()
        case .replaced:
            _ = try FileManager.default.replaceItemAt(old, withItemAt: new)
        }
    }

    @Test(arguments: Way.allCases)
    func openedAgainItIsTheNewFileEverywhere(_ way: Way) async throws {
        let folder = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(folder) }
        let url = folder.appendingPathComponent("take.mp4")
        let next = folder.appendingPathComponent("next.mp4")
        // The old file counts its frames from nought. The new one runs longer
        // at another size, so frame 60 exists only in it.
        try await TestClip.write(to: url, seconds: 1)
        try await TestClip.write(to: next, seconds: 3, size: CGSize(width: 320, height: 180))

        let library = MovieLibrary()
        let decoder = MovieDecoder { image, _ in image }
        library.letGo = { id in Task { await decoder.forget(id) } }
        let before = try #require(await library.movie(at: url))
        #expect(before.durationMS == 1000)
        let oldFrame = try #require(await decoder.frame(of: before, at: url, sourceMS: 500))
        #expect(TestClip.frameCode(of: oldFrame)?.index == 15)

        try Self.put(next, over: url, way)

        let after = try #require(await library.movie(at: url))
        #expect(after.durationMS == 3000)
        #expect(after.pixelSize == CGSize(width: 320, height: 180))
        #expect(after.id != before.id, "the old file's frames are filed under the old id")
        #expect(after.frameRef(atFrame: 15).id != before.frameRef(atFrame: 15).id)
        // Scrubbing back from the end, before anything has played.
        for frame in [80, 60, 40, 15] {
            let ms = MovieRef.gridMS(ofFrame: frame)
            let image = try #require(await decoder.frame(of: after, at: url, sourceMS: ms))
            #expect(image.width == 320)
            #expect(TestClip.frameCode(of: image)?.index == frame)
        }
        let strip = try #require(await decoder.picture(of: after, at: url, sourceMS: 2000,
                                                       size: CGSize(width: 192, height: 192)))
        #expect(TestClip.frameCode(of: strip)?.index == 60)
        // A hand too fast for the frames goes by the new file's key frames.
        let keys = try #require(await decoder.keyFrames(of: after, at: url))
        let fresh = try #require(await MovieDecoder { image, _ in image }.keyFrames(of: after, at: url))
        #expect(keys.nearest(to: 80, within: nil)?.frame == fresh.nearest(to: 80, within: nil)?.frame)
    }

    @Test func aFileThatHasNotChangedIsTheSameRecording() async throws {
        let folder = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(folder) }
        let url = folder.appendingPathComponent("take.mp4")
        try await TestClip.write(to: url, seconds: 0.5)
        let library = MovieLibrary()
        var letGo = 0
        library.letGo = { _ in letGo += 1 }
        let first = try #require(await library.movie(at: url))
        let again = try #require(await library.movie(at: url))
        #expect(first == again)
        #expect(letGo == 0)
    }

    /// The decoder is told to let go of the old file, so a minute of scrubbing
    /// a recording that keeps changing does not pile readers up.
    @Test func theOldFilesReadersAreLetGo() async throws {
        let folder = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(folder) }
        let url = folder.appendingPathComponent("take.mp4")
        let next = folder.appendingPathComponent("next.mp4")
        try await TestClip.write(to: url, seconds: 0.5)
        try await TestClip.write(to: next, seconds: 1)
        let library = MovieLibrary()
        var letGo: [UUID] = []
        library.letGo = { letGo.append($0) }
        let before = try #require(await library.movie(at: url))
        #expect(library.changedOnDisk([before.id]).isEmpty)
        try Self.put(next, over: url, .replaced)
        #expect(library.changedOnDisk([before.id]) == [before.id: url.standardizedFileURL])
        let after = try #require(await library.movie(at: url))
        #expect(letGo == [before.id])
        // A window still holding the old id is told; the new one is not.
        #expect(library.changedOnDisk([before.id, after.id]).keys.sorted { $0.uuidString < $1.uuidString } == [before.id])
    }

    /// Saving into history moves where the recording is played from, to a copy
    /// with the same bytes: that is not a change.
    @Test func aRecordingMovedToItsKeptCopyHasNotChanged() async throws {
        let folder = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(folder) }
        let url = folder.appendingPathComponent("take.mp4")
        let kept = folder.appendingPathComponent("kept.mp4")
        try await TestClip.write(to: url, seconds: 0.5)
        let library = MovieLibrary()
        let movie = try #require(await library.movie(at: url))
        try FileManager.default.copyItem(at: url, to: kept)
        library.relocate(from: url, to: kept)
        try Data([1, 2, 3]).write(to: url)
        #expect(library.changedOnDisk([movie.id]).isEmpty)
        #expect(await library.movie(at: kept) == movie)
    }

    // MARK: A saved project

    @Test func aProjectWhoseRecordingChangedSinceItWasSavedReadsItAgain() async throws {
        let folder = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(folder) }
        let url = folder.appendingPathComponent("take.mp4")
        let next = folder.appendingPathComponent("next.mp4")
        try await TestClip.write(to: url, seconds: 0.5)
        try await TestClip.write(to: next, seconds: 2)
        let saved = try #require(MediaFileStamp.of(url))
        let held = MovieRef(pixelSize: CGSize(width: 160, height: 120), durationMS: 500)

        // Nothing has changed: the project's own reference, as it was.
        let quiet = MovieLibrary()
        #expect(quiet.adopt(held, at: url, savedAs: saved) == held)
        #expect(await quiet.movie(at: url) == held)

        try Self.put(next, over: url, .inPlace)
        let library = MovieLibrary()
        let adopted = library.adopt(held, at: url, savedAs: saved)
        #expect(adopted.id != held.id, "what was made from the old file is kept under the old id")
        let read = try #require(await library.refreshed(adopted))
        #expect(read.id == adopted.id)
        #expect(read.durationMS == 2000)
    }

    /// Written before projects kept a stamp: the file is read to be sure.
    @Test func anOldProjectsRecordingIsCheckedAgainstItsFile() async throws {
        let folder = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(folder) }
        let url = folder.appendingPathComponent("take.mp4")
        try await TestClip.write(to: url, seconds: 2)
        let library = MovieLibrary()
        let same = MovieRef(pixelSize: CGSize(width: 160, height: 120), durationMS: 1990)
        #expect(library.adopt(same, at: url, savedAs: nil) == same)
        #expect(await library.refreshed(same) == nil, "a file that says the same keeps its reference")
        let stale = MovieRef(pixelSize: CGSize(width: 160, height: 120), durationMS: 500)
        let other = MovieLibrary()
        #expect(other.adopt(stale, at: url, savedAs: nil) == stale)
        #expect(await other.refreshed(stale)?.durationMS == 2000)
    }

    @Test func whereThePointerWentIsReadAgain() async throws {
        let folder = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(folder) }
        let url = folder.appendingPathComponent("take.mp4")
        let next = folder.appendingPathComponent("next.mp4")
        try await TestClip.write(to: url, seconds: 0.5)
        try await TestClip.write(to: next, seconds: 1)
        let library = MovieLibrary()
        let before = try #require(await library.movie(at: url))
        #expect(library.pointerTrack(for: before) == nil)
        try PointerTrackSidecar.save(
            PointerTrack(pixelSize: before.pixelSize, samples: [],
                         clicks: [PointerClick(downMS: 100, upMS: 120, point: .zero, button: .left)]), for: url)
        try Self.put(next, over: url, .inPlace)
        let after = try #require(await library.movie(at: url))
        #expect(library.pointerTrack(for: after)?.clicks.count == 1)
    }
}
