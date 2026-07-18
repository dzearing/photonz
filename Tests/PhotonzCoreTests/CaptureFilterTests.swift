import Foundation
import PhotonzCore
import Testing

@Suite("CaptureFilter")
struct CaptureFilterTests {
    private func entry(_ name: String, _ kind: CaptureKind) -> CaptureEntry {
        CaptureEntry(url: URL(fileURLWithPath: "/tmp/\(name)"),
                     createdAt: Date(timeIntervalSinceReferenceDate: 0),
                     kind: kind)
    }

    @Test func titlesArePlainHumanCopy() {
        #expect(CaptureFilter.all.title == "All")
        #expect(CaptureFilter.screenshots.title == "Screenshots")
        #expect(CaptureFilter.videos.title == "Videos")
    }

    @Test func allCasesInDisplayOrder() {
        #expect(CaptureFilter.allCases == [.all, .screenshots, .videos])
    }

    @Test func matchesByKind() {
        #expect(CaptureFilter.all.matches(.image))
        #expect(CaptureFilter.all.matches(.video))
        #expect(CaptureFilter.screenshots.matches(.image))
        #expect(!CaptureFilter.screenshots.matches(.video))
        #expect(CaptureFilter.videos.matches(.video))
        #expect(!CaptureFilter.videos.matches(.image))
    }

    @Test func applyKeepsOrderAndDropsNonMatching() {
        let items = [entry("a.png", .image), entry("b.mp4", .video), entry("c.png", .image)]
        #expect(CaptureFilter.all.apply(to: items).map(\.fileName) == ["a.png", "b.mp4", "c.png"])
        #expect(CaptureFilter.screenshots.apply(to: items).map(\.fileName) == ["a.png", "c.png"])
        #expect(CaptureFilter.videos.apply(to: items).map(\.fileName) == ["b.mp4"])
    }
}

@Suite("HistorySelection")
struct HistorySelectionTests {
    @Test func emptyListHasNoSelection() {
        #expect(HistorySelection.move(nil, by: 1, count: 0) == nil)
        #expect(HistorySelection.move(3, by: -1, count: 0) == nil)
    }

    @Test func nilStartsAtFirstItemThenMoves() {
        // No prior selection: a right press lands on the first item.
        #expect(HistorySelection.move(nil, by: 1, count: 5) == 0)
        #expect(HistorySelection.move(nil, by: -1, count: 5) == 0)
    }

    @Test func movesAndClampsWithinBounds() {
        #expect(HistorySelection.move(0, by: 1, count: 5) == 1)
        #expect(HistorySelection.move(4, by: 1, count: 5) == 4) // clamp at end
        #expect(HistorySelection.move(0, by: -1, count: 5) == 0) // clamp at start
        #expect(HistorySelection.move(2, by: -1, count: 5) == 1)
    }

    @Test func clampsAnOutOfRangeIndex() {
        // Selected item removed and the list shrank: keep the index valid.
        #expect(HistorySelection.clamp(9, count: 3) == 2)
        #expect(HistorySelection.clamp(1, count: 3) == 1)
        #expect(HistorySelection.clamp(0, count: 0) == nil)
        #expect(HistorySelection.clamp(nil, count: 3) == nil)
    }
}
