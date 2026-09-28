import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Pinching the timeline both ways** (`TimelineRowZoom.swift`).
///
/// User 2026-09-28: "I want vertical zoom to make the rows larger, but centered
/// where my mouse is." A pinch opens time out AND grows the rows, and the row
/// under the pointer stays under the pointer while it does, the same promise
/// the time zoom already keeps for the moment under it.
///
/// Written before the change, which is the rule for `PhotonzCore`.
@Suite("Pinching the timeline both ways")
struct TimelineRowZoomTests {

    // MARK: - How tall

    @Test func rowsStartCompact() {
        #expect(TimelineRowZoom.compact.scale == 1)
        #expect(TimelineRowZoom.compact.isCompact)
    }

    @Test func rowsGrowToAboutFourTimesAndNoFurther() {
        let tall = TimelineRowZoom.compact.zoomed(by: 100)
        #expect(tall.scale == TimelineRowZoom.tallest)
        #expect(TimelineRowZoom.tallest == 4)
        let short = TimelineRowZoom(scale: 2).zoomed(by: 0.01)
        #expect(short.scale == 1)
    }

    @Test func aPinchGrowsTheRowsByTheSameFactorAsTime() {
        let grown = TimelineRowZoom(scale: 1.5).zoomed(by: 2)
        #expect(grown.scale == 3)
    }

    @Test func aRowIsItsCompactHeightTimesTheScale() {
        #expect(TimelineRowZoom(scale: 2).height(28) == 56)
        #expect(TimelineRowZoom.compact.height(34) == 34)
    }

    // MARK: - Which way a pinch goes

    @Test func aPlainPinchZoomsBothWays() {
        #expect(TimelinePinchAxes(option: false, shift: false) == .both)
    }

    @Test func optionPinchesTimeAndShiftPinchesRows() {
        #expect(TimelinePinchAxes(option: true, shift: false) == .time)
        #expect(TimelinePinchAxes(option: false, shift: true) == .rows)
        #expect(TimelinePinchAxes.time.zoomsTime)
        #expect(!TimelinePinchAxes.time.zoomsRows)
        #expect(TimelinePinchAxes.rows.zoomsRows)
        #expect(!TimelinePinchAxes.rows.zoomsTime)
        #expect(TimelinePinchAxes.both.zoomsTime && TimelinePinchAxes.both.zoomsRows)
    }

    // MARK: - The row under the pointer stays under the pointer

    /// Three rows 28 tall with 6 between, starting 6 down, at a scale.
    private func rows(_ scale: CGFloat) -> [TimelineRowExtent] {
        var top: CGFloat = 6
        var out: [TimelineRowExtent] = []
        for _ in 0..<3 {
            out.append(TimelineRowExtent(top: top, height: 28 * scale))
            top += 28 * scale + 6
        }
        return out
    }

    private func contentHeight(_ rows: [TimelineRowExtent]) -> CGFloat {
        (rows.last.map { $0.top + $0.height } ?? 0) + 6
    }

    @Test func theSpotUnderThePointerLandsInTheSameRowAtTheSameShare() {
        // Pointer 50 points down a 60 point viewport, scrolled to the top:
        // that is 50 into the content, 10 points (five fourteenths) into the
        // second row (40...68). At twice the height the second row runs
        // 68...124, so the same share of it is 68 + 20 = 88, and the view has
        // to scroll to 38 to keep it at 50 on screen.
        let before = rows(1), after = rows(2)
        let offset = TimelineRowZoom.offset(keepingViewportY: 50, offset: 0,
                                            from: before, to: after,
                                            contentHeight: contentHeight(after),
                                            viewportHeight: 60)
        #expect(abs(offset - 38) < 0.001)
    }

    @Test func itHoldsThroughAWholePinchOfSmallSteps() {
        // A trackpad pinch is a run of tiny factors. After twenty of them the
        // row under the pointer, and the share of it, must still be the one
        // the pinch began on: no drift a frame at a time.
        var offset: CGFloat = 0
        var scale: CGFloat = 1
        let pointer: CGFloat = 50
        for _ in 0..<20 {
            let next = min(4, scale * 1.07)
            let after = rows(next)
            offset = TimelineRowZoom.offset(keepingViewportY: pointer, offset: offset,
                                            from: rows(scale), to: after,
                                            contentHeight: contentHeight(after),
                                            viewportHeight: 60)
            scale = next
        }
        let y = offset + pointer
        let second = rows(scale)[1]
        #expect(y >= second.top && y <= second.top + second.height)
        #expect(abs((y - second.top) / second.height - 10.0 / 28) < 0.001)
    }

    @Test func aGapBetweenRowsKeepsItsDistanceFromTheRowAbove() {
        // Pointer in the six point gap after the first row (34...40), at 37.
        let before = rows(1), after = rows(3)
        let offset = TimelineRowZoom.offset(keepingViewportY: 37, offset: 0,
                                            from: before, to: after,
                                            contentHeight: contentHeight(after),
                                            viewportHeight: 60)
        // First row now ends at 6 + 84 = 90; three points after it is 93.
        #expect(abs(offset + 37 - 93) < 0.001)
    }

    @Test func itNeverScrollsPastEitherEnd() {
        // Shrinking back to compact: the content is shorter than the viewport,
        // so there is nowhere to scroll and the offset is nought.
        let before = rows(3), after = rows(1)
        let offset = TimelineRowZoom.offset(keepingViewportY: 10, offset: 150,
                                            from: before, to: after,
                                            contentHeight: contentHeight(after),
                                            viewportHeight: 200)
        #expect(offset == 0)
        // And never past the bottom.
        let low = TimelineRowZoom.offset(keepingViewportY: 0, offset: 0,
                                         from: rows(1), to: rows(4),
                                         contentHeight: 1000, viewportHeight: 60)
        #expect(low >= 0)
    }

    @Test func noRowsMeansNothingMoves() {
        let offset = TimelineRowZoom.offset(keepingViewportY: 20, offset: 12, from: [], to: [],
                                            contentHeight: 100, viewportHeight: 60)
        #expect(offset == 12)
    }
}

/// **How you left a recording's timeline, kept for when it comes back**
/// (`TimelineViewMemory.swift`).
@Suite("Timeline zoom remembered per document")
struct TimelineViewMemoryTests {

    static let file = "/Users/someone/Movies/take.mov"

    @Test func aZoomedTimelineIsRememberedAndComesBack() {
        var memory = TimelineViewMemory()
        let zoom = TimelineZoom(scale: 12, startMS: 40_000)
        memory.remember(zoom: zoom, rows: TimelineRowZoom(scale: 2.5), for: Self.file)
        let back = memory.recall(for: Self.file)
        #expect(back?.zoom == zoom)
        #expect(back?.rows == TimelineRowZoom(scale: 2.5))
    }

    @Test func aTimelineAtItsDefaultsLeavesNoRecord() {
        var memory = TimelineViewMemory()
        memory.remember(zoom: TimelineZoom(scale: 4), rows: .compact, for: Self.file)
        memory.remember(zoom: .fit, rows: .compact, for: Self.file)
        #expect(memory.isEmpty)
        #expect(memory.recall(for: Self.file) == nil)
    }

    @Test func tallRowsAloneAreWorthRemembering() {
        var memory = TimelineViewMemory()
        memory.remember(zoom: .fit, rows: TimelineRowZoom(scale: 3), for: Self.file)
        #expect(memory.recall(for: Self.file)?.rows.scale == 3)
    }

    @Test func theOldestFileFallsOffTheEnd() {
        var memory = TimelineViewMemory()
        let start = Date(timeIntervalSince1970: 0)
        for index in 0...TimelineViewMemory.capacity {
            memory.remember(zoom: TimelineZoom(scale: 2), rows: .compact, for: "/f\(index)",
                            at: start.addingTimeInterval(Double(index)))
        }
        #expect(memory.fileCount == TimelineViewMemory.capacity)
        #expect(memory.recall(for: "/f0") == nil)
        #expect(memory.recall(for: "/f1") != nil)
    }

    @Test func itSurvivesBeingWrittenOut() throws {
        var memory = TimelineViewMemory()
        memory.remember(zoom: TimelineZoom(scale: 8, startMS: 1000), rows: TimelineRowZoom(scale: 2),
                        for: Self.file, at: Date(timeIntervalSince1970: 100))
        let data = try JSONEncoder().encode(memory)
        let back = try JSONDecoder().decode(TimelineViewMemory.self, from: data)
        #expect(back == memory)
    }
}
