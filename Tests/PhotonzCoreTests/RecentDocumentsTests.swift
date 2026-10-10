import Foundation
import Testing
@testable import PhotonzCore

/// The documents you opened and saved, newest first: what the front door's
/// Recent and File > Open Recent list.
@Suite("Recent documents")
struct RecentDocumentsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func file(_ name: String) -> URL { URL(fileURLWithPath: "/Users/someone/\(name)") }

    @Test("A document you open goes to the top")
    func newestFirst() {
        var recent = RecentDocuments()
        recent.note(file("a.photonz"), at: now)
        recent.note(file("b.png"), at: now.addingTimeInterval(10))
        #expect(recent.items.map(\.name) == ["b", "a"])
        #expect(recent.items.first?.usedAt == now.addingTimeInterval(10))
    }

    @Test("Opening one again moves it up instead of listing it twice")
    func noDuplicates() {
        var recent = RecentDocuments()
        recent.note(file("a.photonz"), at: now)
        recent.note(file("b.png"), at: now.addingTimeInterval(10))
        // The same file reached by a different spelling of its path.
        recent.note(URL(fileURLWithPath: "/Users/someone/./a.photonz"), at: now.addingTimeInterval(20))
        #expect(recent.items.map(\.name) == ["a", "b"])
    }

    @Test("It keeps the Mac's usual ten")
    func capped() {
        var recent = RecentDocuments()
        for n in 0..<15 { recent.note(file("\(n).png"), at: now.addingTimeInterval(TimeInterval(n))) }
        #expect(recent.items.count == RecentDocuments.limit)
        #expect(RecentDocuments.limit == 10)
        #expect(recent.items.first?.name == "14")
        #expect(recent.items.last?.name == "5")
    }

    @Test("Clear Menu empties it, and one can be taken off on its own")
    func clearAndRemove() {
        var recent = RecentDocuments()
        recent.note(file("a.photonz"), at: now)
        recent.note(file("b.png"), at: now)
        recent.remove(file("a.photonz"))
        #expect(recent.items.map(\.name) == ["b"])
        recent.clear()
        #expect(recent.items.isEmpty)
    }

    @Test("A file that has gone is not offered")
    func goneFilesAreLeftOut() {
        var recent = RecentDocuments()
        recent.note(file("kept.png"), at: now)
        recent.note(file("gone.png"), at: now)
        #expect(recent.existing { $0.lastPathComponent != "gone.png" }.map(\.name) == ["kept"])
    }

    @Test("Open Recent names each file, and the folder too where two share a name")
    func menuTitles() {
        let documents = [RecentDocument(url: URL(fileURLWithPath: "/Users/someone/Desktop/card.photonz"), usedAt: now),
                         RecentDocument(url: URL(fileURLWithPath: "/Users/someone/Work/card.photonz"), usedAt: now),
                         RecentDocument(url: URL(fileURLWithPath: "/Users/someone/Work/hero.png"), usedAt: now)]
        #expect(RecentDocuments.menuTitles(documents)
                == ["card.photonz (Desktop)", "card.photonz (Work)", "hero.png"])
    }

    @Test("It survives being written down and read back")
    func codable() throws {
        var recent = RecentDocuments()
        recent.note(file("a.photonz"), at: now)
        let data = try JSONEncoder().encode(recent)
        #expect(try JSONDecoder().decode(RecentDocuments.self, from: data) == recent)
    }

    @Test("Recent is on by default in Next and absent from Current")
    func flag() {
        #expect(FeatureCatalog.defaultSettings(for: .next).isEnabled(FeatureCatalog.recentDocumentsFlag))
        #expect(!FeatureCatalog.flags(for: .current).contains { $0.name == FeatureCatalog.recentDocumentsFlag })
    }
}
