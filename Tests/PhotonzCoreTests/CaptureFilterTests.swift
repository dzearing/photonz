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

    // ⌘→ / ⌘← in the history strip: one step along the segments, in the
    // order they are drawn, stopping at either end rather than wrapping.
    @Test func stepsAlongTheSegmentsAndStopsAtTheEnds() {
        #expect(CaptureFilter.all.stepped(by: 1) == .screenshots)
        #expect(CaptureFilter.screenshots.stepped(by: 1) == .videos)
        #expect(CaptureFilter.videos.stepped(by: 1) == .videos)
        #expect(CaptureFilter.videos.stepped(by: -1) == .screenshots)
        #expect(CaptureFilter.screenshots.stepped(by: -1) == .all)
        #expect(CaptureFilter.all.stepped(by: -1) == .all)
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

    private func entry(_ name: String, _ kind: CaptureKind) -> CaptureEntry {
        CaptureEntry(url: URL(fileURLWithPath: "/tmp/\(name)"),
                     createdAt: Date(timeIntervalSinceReferenceDate: 0),
                     kind: kind)
    }

    // A filter switch keeps the focused capture when the new filter shows it,
    // and otherwise lands on the new filter's first capture.
    @Test func aSwitchKeepsTheFocusedCaptureWhenTheNewFilterHasIt() {
        let all = [entry("s0.png", .image), entry("s1.png", .image), entry("r2.mp4", .video),
                   entry("s3.png", .image), entry("r5.mp4", .video)]
        let shots = CaptureFilter.screenshots.apply(to: all)
        let videos = CaptureFilter.videos.apply(to: all)
        // s1 in All is s1 in Screenshots.
        #expect(HistorySelection.carry(1, from: all, to: shots) == 1)
        // s3 in Screenshots is s3 in All.
        #expect(HistorySelection.carry(2, from: shots, to: all) == 3)
        // r5 in Videos is r5 in All.
        #expect(HistorySelection.carry(1, from: videos, to: all) == 4)
        // r2 is not a screenshot: the first screenshot.
        #expect(HistorySelection.carry(2, from: all, to: shots) == 0)
        // Nothing focused before: the first capture.
        #expect(HistorySelection.carry(nil, from: all, to: videos) == 0)
        // A stale index past the old list: the first capture.
        #expect(HistorySelection.carry(9, from: all, to: videos) == 0)
        // Nothing to focus in an empty filter.
        #expect(HistorySelection.carry(0, from: all, to: []) == nil)
    }
}

@Suite("History filter keys flag")
struct HistoryFilterKeysFlagTests {
    @Test("⌘← / ⌘→ on the history filter is on by default in Next and absent from Current")
    func flag() {
        #expect(FeatureCatalog.historyFilterKeysFlag == "next-history-filter-keys")
        #expect(FeatureCatalog.defaultSettings(for: .next).isEnabled(FeatureCatalog.historyFilterKeysFlag))
        #expect(!FeatureCatalog.flags(for: .current).contains { $0.name == FeatureCatalog.historyFilterKeysFlag })
    }
}
