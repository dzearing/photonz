import CoreGraphics
import PhotonzCore
import Testing

/// The shelf's height math. Every expected number here was measured against a
/// real `LazyVGrid(columns: [.adaptive(minimum: 68, spacing: 8)], spacing: 8)`
/// laid out at the same width, so these tests are the contract that keeps the
/// arithmetic and SwiftUI's own layout in step.
@Suite("LibraryShelfLayout")
struct LibraryShelfLayoutTests {

    // MARK: Columns

    @Test func fitsAsManyTilesAcrossAsTheWidthAllows() {
        #expect(LibraryShelfLayout.columnCount(width: 140) == 1)
        #expect(LibraryShelfLayout.columnCount(width: 190) == 2)
        #expect(LibraryShelfLayout.columnCount(width: 236) == 3)
        #expect(LibraryShelfLayout.columnCount(width: 300) == 4)
        #expect(LibraryShelfLayout.columnCount(width: 380) == 5)
    }

    @Test func neverDropsBelowOneColumnHoweverNarrowTheDockGets() {
        #expect(LibraryShelfLayout.columnCount(width: 0) == 1)
        #expect(LibraryShelfLayout.columnCount(width: -50) == 1)
        #expect(LibraryShelfLayout.columnCount(width: 12) == 1)
    }

    // MARK: Rows

    @Test func wrapsTilesIntoRows() {
        #expect(LibraryShelfLayout.rowCount(tileCount: 0, width: 236) == 0)
        #expect(LibraryShelfLayout.rowCount(tileCount: 1, width: 236) == 1)
        #expect(LibraryShelfLayout.rowCount(tileCount: 3, width: 236) == 1)
        #expect(LibraryShelfLayout.rowCount(tileCount: 4, width: 236) == 2)
        #expect(LibraryShelfLayout.rowCount(tileCount: 13, width: 236) == 5)
    }

    // MARK: Height

    @Test func oneTileIsOneRowTall() {
        #expect(LibraryShelfLayout.contentHeight(tileCount: 1, width: 236) == 72)
    }

    @Test func aFullRowIsNoTallerThanOneTile() {
        #expect(LibraryShelfLayout.contentHeight(tileCount: 2, width: 236) == 72)
        #expect(LibraryShelfLayout.contentHeight(tileCount: 3, width: 236) == 72)
    }

    @Test func everyExtraRowAddsATileAndAGap() {
        #expect(LibraryShelfLayout.contentHeight(tileCount: 4, width: 236) == 148)
        #expect(LibraryShelfLayout.contentHeight(tileCount: 9, width: 236) == 224)
        #expect(LibraryShelfLayout.contentHeight(tileCount: 13, width: 236) == 376)
    }

    @Test func matchesTheMeasuredGridAtEveryDockWidth() {
        // width: tile count: measured height, from a real LazyVGrid.
        let measured: [CGFloat: [Int: CGFloat]] = [
            140: [1: 72, 2: 148, 3: 224, 4: 300, 6: 452, 9: 680, 13: 984],
            190: [1: 72, 2: 72, 3: 148, 4: 148, 6: 224, 9: 376, 13: 528],
            236: [1: 72, 2: 72, 3: 72, 4: 148, 6: 148, 9: 224, 13: 376],
            300: [1: 72, 2: 72, 3: 72, 4: 72, 6: 148, 9: 224, 13: 300],
            380: [1: 72, 2: 72, 3: 72, 4: 72, 6: 148, 9: 148, 13: 224],
        ]
        for (width, byCount) in measured {
            for (count, height) in byCount {
                #expect(LibraryShelfLayout.contentHeight(tileCount: count, width: width) == height,
                        "width \(width), \(count) tiles")
            }
        }
    }

    @Test func anEmptyShelfAsksForNoHeightAtAll() {
        #expect(LibraryShelfLayout.contentHeight(tileCount: 0, width: 236) == 0)
    }

    @Test func aShortShelfHugsItsTilesAndALongOneStopsAtTheCap() {
        // What the panel actually asks for: hug the content, cap at the
        // user's ceiling so the sections below stay in view.
        #expect(LibraryShelfLayout.shelfHeight(tileCount: 1, width: 236, cap: 220) == 72)
        #expect(LibraryShelfLayout.shelfHeight(tileCount: 4, width: 236, cap: 220) == 148)
        #expect(LibraryShelfLayout.shelfHeight(tileCount: 13, width: 236, cap: 220) == 220)
    }

    @Test func aShelfWhoseWidthIsNotKnownYetKeepsTheCap() {
        // First layout pass: nothing has measured the dock yet. Better to
        // stand at the ceiling for one frame than to guess tall and shrink.
        #expect(LibraryShelfLayout.shelfHeight(tileCount: 1, width: 0, cap: 220) == 220)
    }

    @Test func theTileMetricsAddUpToTheRowHeightTheGridDraws() {
        // The tile views build themselves from these, so the arithmetic and
        // the drawing cannot drift apart.
        let tile = LibraryShelfLayout.tilePadding * 2
            + LibraryShelfLayout.thumbnailHeight
            + LibraryShelfLayout.captionSpacing
            + LibraryShelfLayout.captionHeight
        #expect(tile == LibraryShelfLayout.tileHeight)
        #expect(LibraryShelfLayout.tileHeight == 68)
    }
}
