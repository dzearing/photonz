import Foundation
import Testing
@testable import PhotonzCore

/// How a file is told from another that took its name.
struct MediaFileStampTests {

    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaFileStamp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func aFileLeftAloneKeepsItsStampAndAMissingOneHasNone() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a")
        #expect(MediaFileStamp.of(file) == nil)
        try Data("one".utf8).write(to: file)
        #expect(MediaFileStamp.of(file) != nil)
        #expect(MediaFileStamp.of(file) == MediaFileStamp.of(file))
    }

    @Test func writtenOverOrReplacedItIsAnotherFile() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a"), other = folder.appendingPathComponent("b")
        try Data("one".utf8).write(to: file)
        let first = MediaFileStamp.of(file)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("two".utf8))
        try handle.close()
        let second = MediaFileStamp.of(file)
        #expect(second != first, "the same length written over in place")
        // The same size and the very same date, in a file of its own.
        try Data("six".utf8).write(to: other)
        let date = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]
        _ = try FileManager.default.replaceItemAt(file, withItemAt: other)
        try FileManager.default.setAttributes([.modificationDate: date as Any], ofItemAtPath: file.path)
        #expect(MediaFileStamp.of(file) != second)
    }

    /// A copy with its date kept holds what it was copied from, which is all a
    /// project moved to another disk can be asked.
    @Test func aCopyHoldsTheSameContents() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a"), copy = folder.appendingPathComponent("b")
        try Data("one".utf8).write(to: file)
        try FileManager.default.copyItem(at: file, to: copy)
        let (a, b) = (try #require(MediaFileStamp.of(file)), try #require(MediaFileStamp.of(copy)))
        #expect(a != b)
        #expect(a.sameContents(as: b))
        try Data("another".utf8).write(to: copy)
        #expect(!a.sameContents(as: try #require(MediaFileStamp.of(copy))))
    }

    @Test func aTableForgetsAFileThatChanged() {
        let url = URL(fileURLWithPath: "/a.mp4"), moved = URL(fileURLWithPath: "/b.mp4")
        let one = MediaFileStamp(bytes: 1, modifiedNS: 1, fileID: 1)
        let two = MediaFileStamp(bytes: 1, modifiedNS: 2, fileID: 1)
        var table = MediaIdentities<String>()
        #expect(table.known(at: url, stamp: one) == nil)
        table.file("first", at: url, stamp: one)
        #expect(table.known(at: url, stamp: one) == "first")
        #expect(table.known(at: url, stamp: two) == nil)
        #expect(table.known(at: url, stamp: nil) == nil)
        #expect(table.filed(at: url) == "first")
        table.relocate(from: url, to: moved, stamp: two)
        #expect(table.filed(at: url) == nil)
        #expect(table.known(at: moved, stamp: two) == "first")
    }
}
