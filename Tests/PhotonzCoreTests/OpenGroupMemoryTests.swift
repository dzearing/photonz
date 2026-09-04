import Foundation
import PhotonzCore
import Testing

/// Which groups were left open in the layers list is remembered per file, so a
/// picture looks the way you left it when you come back to it. These tests pin
/// the three things that make that safe: what comes back is only ever groups
/// the document still has, a document you tidied up leaves nothing behind, and
/// the record cannot grow without end.
@Suite("OpenGroupMemory")
struct OpenGroupMemoryTests {

    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    private var allThree: Set<UUID> { [a, b, c] }

    // MARK: Remembering

    @Test func aFileNeverSeenHasNothingOpen() {
        let memory = OpenGroupMemory()
        #expect(memory.openGroups(for: "/pictures/hero.photonz", stillInDocument: allThree).isEmpty)
    }

    @Test func givesBackTheGroupsThatWereOpen() {
        var memory = OpenGroupMemory()
        memory.remember([a, c], for: "/pictures/hero.photonz", stillInDocument: allThree)
        #expect(memory.openGroups(for: "/pictures/hero.photonz", stillInDocument: allThree) == [a, c])
    }

    @Test func eachFileIsRememberedOnItsOwn() {
        var memory = OpenGroupMemory()
        memory.remember([a], for: "/pictures/one.photonz", stillInDocument: allThree)
        memory.remember([b], for: "/pictures/two.photonz", stillInDocument: allThree)
        #expect(memory.openGroups(for: "/pictures/one.photonz", stillInDocument: allThree) == [a])
        #expect(memory.openGroups(for: "/pictures/two.photonz", stillInDocument: allThree) == [b])
    }

    @Test func openingMoreGroupsReplacesWhatWasRemembered() {
        var memory = OpenGroupMemory()
        memory.remember([a], for: "/f.photonz", stillInDocument: allThree)
        memory.remember([a, b], for: "/f.photonz", stillInDocument: allThree)
        #expect(memory.openGroups(for: "/f.photonz", stillInDocument: allThree) == [a, b])
    }

    // MARK: A group that no longer exists leaves nothing behind

    @Test func aDeletedGroupIsNotWrittenDown() {
        var memory = OpenGroupMemory()
        // b was open, then the group was deleted, so the document only has a and c.
        memory.remember([a, b], for: "/f.photonz", stillInDocument: [a, c])
        #expect(memory.openGroups(for: "/f.photonz", stillInDocument: [a, c]) == [a])
    }

    @Test func aGroupDeletedAfterTheFactIsNotHandedBack() {
        var memory = OpenGroupMemory()
        memory.remember([a, b], for: "/f.photonz", stillInDocument: allThree)
        // Next time the file opens, b is gone from the document.
        #expect(memory.openGroups(for: "/f.photonz", stillInDocument: [a, c]) == [a])
    }

    @Test func closingEveryGroupLeavesNoRecordAtAll() {
        var memory = OpenGroupMemory()
        memory.remember([a, b], for: "/f.photonz", stillInDocument: allThree)
        memory.remember([], for: "/f.photonz", stillInDocument: allThree)
        #expect(memory.isEmpty)
    }

    @Test func aDocumentWithNoGroupsLeftLeavesNoRecord() {
        var memory = OpenGroupMemory()
        memory.remember([a], for: "/f.photonz", stillInDocument: allThree)
        memory.remember([a], for: "/f.photonz", stillInDocument: [])
        #expect(memory.isEmpty)
    }

    @Test func forgettingAFileClearsIt() {
        var memory = OpenGroupMemory()
        memory.remember([a], for: "/f.photonz", stillInDocument: allThree)
        memory.forget("/f.photonz")
        #expect(memory.openGroups(for: "/f.photonz", stillInDocument: allThree).isEmpty)
        #expect(memory.isEmpty)
    }

    // MARK: It cannot grow without end

    @Test func onlyTheMostRecentFilesAreKept() {
        var memory = OpenGroupMemory()
        let start = Date(timeIntervalSince1970: 0)
        for i in 0...OpenGroupMemory.capacity {
            memory.remember([a], for: "/file-\(i).photonz", stillInDocument: allThree,
                            at: start.addingTimeInterval(Double(i)))
        }
        #expect(memory.fileCount == OpenGroupMemory.capacity)
        // The very first file is the one that fell off the end.
        #expect(memory.openGroups(for: "/file-0.photonz", stillInDocument: allThree).isEmpty)
        #expect(memory.openGroups(for: "/file-\(OpenGroupMemory.capacity).photonz",
                                  stillInDocument: allThree) == [a])
    }

    @Test func openingAFileAgainKeepsItFromFallingOffTheEnd() {
        var memory = OpenGroupMemory()
        let start = Date(timeIntervalSince1970: 0)
        for i in 0..<OpenGroupMemory.capacity {
            memory.remember([a], for: "/file-\(i).photonz", stillInDocument: allThree,
                            at: start.addingTimeInterval(Double(i)))
        }
        // The oldest file is used again, so the second oldest is now the stale one.
        memory.remember([b], for: "/file-0.photonz", stillInDocument: allThree,
                        at: start.addingTimeInterval(1000))
        memory.remember([c], for: "/newcomer.photonz", stillInDocument: allThree,
                        at: start.addingTimeInterval(1001))
        #expect(memory.fileCount == OpenGroupMemory.capacity)
        #expect(memory.openGroups(for: "/file-0.photonz", stillInDocument: allThree) == [b])
        #expect(memory.openGroups(for: "/file-1.photonz", stillInDocument: allThree).isEmpty)
    }

    // MARK: It survives a launch

    @Test func roundTripsThroughItsStoredForm() throws {
        var memory = OpenGroupMemory()
        memory.remember([a, b], for: "/f.photonz", stillInDocument: allThree)
        let data = try JSONEncoder().encode(memory)
        let read = try JSONDecoder().decode(OpenGroupMemory.self, from: data)
        #expect(read.openGroups(for: "/f.photonz", stillInDocument: allThree) == [a, b])
    }

    @Test func theSameOpenGroupsInAnyOrderAreTheSameRecord() {
        // What is open is a set, so the record must not depend on the order the
        // groups happened to be opened in. That is what lets the app skip a
        // write when nothing about the list actually changed.
        var memory = OpenGroupMemory()
        let stamp = Date(timeIntervalSince1970: 12345)
        memory.remember([c, a, b], for: "/f.photonz", stillInDocument: allThree, at: stamp)
        var same = OpenGroupMemory()
        same.remember([b, c, a], for: "/f.photonz", stillInDocument: allThree, at: stamp)
        #expect(memory == same)
        #expect(memory.files["/f.photonz"]?.groupIDs == [a, b, c].sorted { $0.uuidString < $1.uuidString })
    }
}
