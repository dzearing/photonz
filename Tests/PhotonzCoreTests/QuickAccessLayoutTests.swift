import CoreGraphics
import Testing
@testable import PhotonzCore

/// Corner placement + entrance geometry for the post-capture Quick Access
/// Overlay (phase 11.7). Pure math; the AppKit panel shell just animates between
/// the two frames.
@Suite("QuickAccessLayout")
struct QuickAccessLayoutTests {

    // A 1440×900 display whose visibleFrame clears a 24pt menu bar.
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 876)
    private let size = CGSize(width: 240, height: 180)

    @Test func bottomLeftSitsInsetFromTheBottomLeftCorner() {
        let l = QuickAccessLayout(screen: screen, size: size, corner: .bottomLeft, margin: 24)
        #expect(l.restingFrame == CGRect(x: 24, y: 24, width: 240, height: 180))
    }

    @Test func bottomRightInsetsFromTheRightEdge() {
        let l = QuickAccessLayout(screen: screen, size: size, corner: .bottomRight, margin: 24)
        #expect(l.restingFrame.maxX == screen.maxX - 24)
        #expect(l.restingFrame.minY == 24)
    }

    @Test func topRightHugsTheTopRight() {
        let l = QuickAccessLayout(screen: screen, size: size, corner: .topRight, margin: 24)
        #expect(l.restingFrame.maxX == screen.maxX - 24)
        #expect(l.restingFrame.maxY == screen.maxY - 24)
    }

    @Test func topLeftHugsTheTopLeft() {
        let l = QuickAccessLayout(screen: screen, size: size, corner: .topLeft, margin: 24)
        #expect(l.restingFrame.minX == 24)
        #expect(l.restingFrame.maxY == screen.maxY - 24)
    }

    @Test func bottomCornersSlideUpFromBelowTheScreen() {
        let l = QuickAccessLayout(screen: screen, size: size, corner: .bottomLeft, margin: 24)
        // Hidden frame is fully below the bottom edge; only y differs from resting.
        #expect(l.hiddenFrame.minX == l.restingFrame.minX)
        #expect(l.hiddenFrame.maxY <= screen.minY)
    }

    @Test func topCornersSlideDownFromAboveTheScreen() {
        let l = QuickAccessLayout(screen: screen, size: size, corner: .topRight, margin: 24)
        #expect(l.hiddenFrame.minX == l.restingFrame.minX)
        #expect(l.hiddenFrame.minY >= screen.maxY)
    }

    @Test func honorsSecondaryDisplayOrigin() {
        let secondary = CGRect(x: 1440, y: -200, width: 1280, height: 800)
        let l = QuickAccessLayout(screen: secondary, size: size, corner: .bottomRight, margin: 24)
        #expect(l.restingFrame.maxX == secondary.maxX - 24)
        #expect(l.restingFrame.minY == secondary.minY + 24)
    }
}
