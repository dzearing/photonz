import CoreGraphics
import Testing
@testable import PhotonzCore

/// How tall the History pane may be dragged, and how tall its tiles are at
/// that height (user 2026-10-28: "i'd like the pane to be resizable on the
/// outer edge").
@Suite("The History pane resizes from its bottom edge")
struct HistoryPaneSizeTests {

    @Test func itOpensAtTheStandardHeightUntilDragged() {
        #expect(HistoryPaneSize.height(kept: nil, screenHeight: 1000) == HistoryPaneSize.standard)
    }

    @Test func aDraggedHeightIsKeptWithinItsLimits() {
        #expect(HistoryPaneSize.height(kept: 300, screenHeight: 1000) == 300)
        #expect(HistoryPaneSize.height(kept: 20, screenHeight: 1000) == HistoryPaneSize.shortest)
        #expect(HistoryPaneSize.height(kept: 5000, screenHeight: 1000) == 600)
    }

    @Test func aSmallScreenStillGetsTheStandardHeight() {
        #expect(HistoryPaneSize.tallest(screenHeight: 200) == HistoryPaneSize.standard)
    }

    @Test func draggingTheBottomEdgeFollowsThePointer() {
        // The pane's top stays under the menu bar; its height is how far down
        // the pointer is, less where on the edge it was taken hold of.
        let height = HistoryPaneSize.dragged(top: 900, pointerY: 560, grabbedBelowBottom: 4,
                                             screenHeight: 1000)
        #expect(height == 336)
    }

    @Test func theTilesGrowWithThePane() {
        #expect(HistoryPaneSize.tileHeight(paneHeight: HistoryPaneSize.standard) == 100)
        #expect(HistoryPaneSize.tileHeight(paneHeight: HistoryPaneSize.standard + 100) == 200)
        #expect(HistoryPaneSize.tileHeight(paneHeight: 10) == HistoryPaneSize.smallestTile)
    }
}

@Suite("The History pane runs edge to edge along the top")
struct HistoryPaneEdgeToEdgeTests {

    @Test func itTouchesBothSidesAndTheTopOfTheVisibleScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1079)
        let layout = HistoryOverlayLayout.edgeToEdge(screen: screen, height: 208)
        #expect(layout.presentedFrame == CGRect(x: 0, y: 871, width: 1728, height: 208))
        #expect(layout.hiddenFrame.minY == screen.maxY)
    }

    @Test func aSecondDisplayIsHonoured() {
        let screen = CGRect(x: 1728, y: -200, width: 2560, height: 1415)
        let layout = HistoryOverlayLayout.edgeToEdge(screen: screen, height: 208)
        #expect(layout.presentedFrame.minX == 1728)
        #expect(layout.presentedFrame.width == 2560)
        #expect(layout.presentedFrame.maxY == screen.maxY)
    }
}
