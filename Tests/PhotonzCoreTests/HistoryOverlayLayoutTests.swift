import CoreGraphics
import PhotonzCore
import Testing

@Suite("HistoryOverlayLayout")
struct HistoryOverlayLayoutTests {
    // A typical 1440-wide laptop visible frame (menu bar already excluded).
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 877)

    @Test func widthClampsToMaxOnWideScreens() {
        let layout = HistoryOverlayLayout(screen: screen, height: 190, maxWidth: 1100)
        #expect(layout.presentedFrame.width == 1100)
    }

    @Test func widthFillsNarrowScreensMinusInset() {
        let narrow = CGRect(x: 0, y: 0, width: 800, height: 600)
        let layout = HistoryOverlayLayout(screen: narrow, height: 190, maxWidth: 1100, horizontalInset: 24)
        let expectedWidth: CGFloat = 752 // 800 - 24*2
        #expect(layout.presentedFrame.width == expectedWidth)
    }

    @Test func presentedIsCenteredHorizontally() {
        let layout = HistoryOverlayLayout(screen: screen, height: 190)
        #expect(layout.presentedFrame.midX == screen.midX)
        #expect(layout.hiddenFrame.midX == screen.midX)
    }

    @Test func presentedPinsToTopEdgeBelowInset() {
        let layout = HistoryOverlayLayout(screen: screen, height: 190, topInset: 8)
        // Top edge sits `topInset` below the screen's top.
        #expect(layout.presentedFrame.maxY == screen.maxY - 8)
    }

    @Test func hiddenSitsFullyAboveTheTopEdge() {
        let layout = HistoryOverlayLayout(screen: screen, height: 190, topInset: 8)
        // Hidden frame's bottom is at (or above) the screen top, so the whole
        // panel is off-screen before it slides down.
        #expect(layout.hiddenFrame.minY >= screen.maxY)
        // Same width/height/x as presented — only y changes (a pure slide).
        #expect(layout.hiddenFrame.width == layout.presentedFrame.width)
        #expect(layout.hiddenFrame.height == layout.presentedFrame.height)
        #expect(layout.hiddenFrame.minX == layout.presentedFrame.minX)
    }

    @Test func slideTravelsHeightPlusInset() {
        let layout = HistoryOverlayLayout(screen: screen, height: 190, topInset: 8)
        // Showing moves the panel down by its full height + the top inset.
        let expectedTravel: CGFloat = 198 // 190 + 8
        #expect(layout.hiddenFrame.minY - layout.presentedFrame.minY == expectedTravel)
    }

    @Test func honorsScreenOriginOffsetForSecondaryDisplays() {
        // A display to the right of / above the main one has a non-zero origin;
        // the overlay must place relative to that screen, not absolute (0,0).
        let secondary = CGRect(x: 1440, y: 200, width: 1000, height: 700)
        let layout = HistoryOverlayLayout(screen: secondary, height: 190, maxWidth: 1100)
        #expect(layout.presentedFrame.midX == secondary.midX)
        #expect(layout.presentedFrame.maxY == secondary.maxY - 8)
        #expect(layout.presentedFrame.minX >= secondary.minX)
    }
}
