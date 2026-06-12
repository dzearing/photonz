import Foundation
import PhotonzCore
import Testing

@Suite("CaptureHistory")
struct CaptureHistoryTests {

    private func entry(_ seconds: TimeInterval) -> CaptureEntry {
        CaptureEntry(id: UUID(), createdAt: Date(timeIntervalSinceReferenceDate: seconds))
    }

    @Test func newestCaptureComesFirst() {
        var history = CaptureHistory()
        let old = entry(100)
        let new = entry(200)
        history.add(old)
        history.add(new)
        #expect(history.entries.map(\.id) == [new.id, old.id])
    }

    @Test func loadingUnorderedEntriesSortsNewestFirst() {
        let a = entry(300), b = entry(100), c = entry(200)
        let history = CaptureHistory(entries: [b, a, c])
        #expect(history.entries.map(\.id) == [a.id, c.id, b.id])
    }

    @Test func addingBeyondTheCapReturnsThePrunedOldest() {
        var history = CaptureHistory(limit: 3)
        let entries = (1...4).map { entry(TimeInterval($0)) }
        var pruned: [CaptureEntry] = []
        for e in entries { pruned += history.add(e) }
        // The first (oldest) entry fell off; the three newest remain.
        #expect(pruned.map(\.id) == [entries[0].id])
        #expect(history.entries.map(\.id) == [entries[3].id, entries[2].id, entries[1].id])
    }

    @Test func removeReturnsTheEntrySoCallersCanDeleteItsFile() {
        var history = CaptureHistory()
        let e = entry(1)
        history.add(e)
        let removed = history.remove(id: e.id)
        #expect(removed?.id == e.id)
        #expect(history.entries.isEmpty)
        #expect(history.remove(id: e.id) == nil)
    }

    @Test func entriesRoundTripThroughCodable() throws {
        var history = CaptureHistory()
        history.add(entry(42))
        let data = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(CaptureHistory.self, from: data)
        #expect(decoded == history)
    }

    @Test func fileNameIsStableAndUnique() {
        let e = entry(1)
        #expect(e.fileName == "capture-\(e.id.uuidString).png")
    }
}
