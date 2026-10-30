import Foundation
@testable import PhotonzMedia
import Testing

/// A file written beside where it goes and swapped in whole (`FileSwap`), so
/// a save over the very file being read from, or one that stops part way,
/// never leaves a missing or half-written file where the old one was.
@Suite("Writing a file beside where it goes")
struct FileSwapTests {

    private struct Stop: Error {}

    @Test("A write over the file it reads from reads the old one and lands the new one")
    func writingOverTheSourceReadsTheOldFile() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let file = dir.appendingPathComponent("Recording.mp4")
        try Data("the recording".utf8).write(to: file)
        // What the export routes do to their destination before writing:
        // remove it, then read the source, which here is the same file.
        try await FileSwap.write(to: file) { scratch in
            try? FileManager.default.removeItem(at: scratch)
            let read = try Data(contentsOf: file)
            try (read + Data(", edited".utf8)).write(to: scratch)
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "the recording, edited")
    }

    @Test("A write that fails leaves the file that was there as it was, and nothing beside it")
    func aFailedWriteLeavesTheOldFile() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let file = dir.appendingPathComponent("Recording.mp4")
        try Data("the recording".utf8).write(to: file)
        await #expect(throws: Stop.self) {
            try await FileSwap.write(to: file) { scratch in
                try Data("half".utf8).write(to: scratch)
                throw Stop()
            }
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "the recording")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["Recording.mp4"])
    }

    @Test("Nothing is at the destination until the write is whole")
    func nothingLandsUntilItIsWhole() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let file = dir.appendingPathComponent("Edit.mp4")
        let route = try await FileSwap.write(to: file) { scratch -> String in
            #expect(scratch != file)
            #expect(!FileManager.default.fileExists(atPath: file.path))
            try Data("whole".utf8).write(to: scratch)
            return "drawn"
        }
        #expect(route == "drawn")
        #expect(try String(contentsOf: file, encoding: .utf8) == "whole")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["Edit.mp4"])
    }

    @Test("A write that leaves nothing behind is an error, and the old file stays")
    func anEmptyWriteIsRefused() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let file = dir.appendingPathComponent("Recording.mp4")
        try Data("the recording".utf8).write(to: file)
        await #expect(throws: (any Error).self) {
            try await FileSwap.write(to: file) { _ in }
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "the recording")
    }
}
