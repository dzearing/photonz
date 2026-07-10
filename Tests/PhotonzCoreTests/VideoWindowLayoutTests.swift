import CoreGraphics
import PhotonzCore
import Testing

@Suite("VideoWindowLayout")
struct VideoWindowLayoutTests {
    // A typical laptop visible frame (menu bar already excluded), AppKit
    // bottom-left origin.
    private let visible = CGRect(x: 0, y: 25, width: 1512, height: 920)
    private let minSize = CGSize(width: 760, height: 520)

    @Test func growsWindowByThePlayerAreaDelta() {
        // Player area is 400×300 inside an 800×600 window; the video wants
        // 600×500 → the window grows by exactly the same +200/+200.
        let current = CGRect(x: 100, y: 100, width: 800, height: 600)
        let frame = VideoWindowLayout.frame(
            current: current, playerArea: CGSize(width: 400, height: 300),
            targetPlayerArea: CGSize(width: 600, height: 500),
            minSize: minSize, visible: visible)
        #expect(frame.size == CGSize(width: 1000, height: 800))
    }

    @Test func keepsTopLeftAnchoredWhileGrowing() {
        // Windows visually grow down/right: the top-left corner stays put, so
        // in AppKit coords the origin.y drops by the height delta. (Placed high
        // enough that the growth doesn't hit the visible frame's bottom.)
        let current = CGRect(x: 100, y: 200, width: 800, height: 600)
        let frame = VideoWindowLayout.frame(
            current: current, playerArea: CGSize(width: 400, height: 300),
            targetPlayerArea: CGSize(width: 500, height: 400),
            minSize: minSize, visible: visible)
        #expect(frame.minX == 100)
        #expect(frame.maxY == current.maxY)
    }

    @Test func clampsToVisibleFrameForHugeVideos() {
        let current = CGRect(x: 100, y: 100, width: 800, height: 600)
        let frame = VideoWindowLayout.frame(
            current: current, playerArea: CGSize(width: 400, height: 300),
            targetPlayerArea: CGSize(width: 5000, height: 4000),
            minSize: minSize, visible: visible)
        #expect(frame.width == visible.width)
        #expect(frame.height == visible.height)
        #expect(visible.contains(frame))
    }

    @Test func neverShrinksBelowMinimumSize() {
        // A tiny recording still opens a usable window.
        let current = CGRect(x: 100, y: 100, width: 800, height: 600)
        let frame = VideoWindowLayout.frame(
            current: current, playerArea: CGSize(width: 400, height: 300),
            targetPlayerArea: CGSize(width: 120, height: 80),
            minSize: minSize, visible: visible)
        #expect(frame.width == minSize.width)
        #expect(frame.height == minSize.height)
    }

    @Test func shiftsBackOnScreenWhenGrowthWouldOverflow() {
        // Window near the right/bottom edge grows past the visible frame → it
        // slides left/up to stay fully on screen.
        let current = CGRect(x: 1300, y: 30, width: 200, height: 200)
        let frame = VideoWindowLayout.frame(
            current: current, playerArea: CGSize(width: 100, height: 100),
            targetPlayerArea: CGSize(width: 700, height: 700),
            minSize: CGSize(width: 100, height: 100), visible: visible)
        #expect(visible.contains(frame))
        #expect(frame.size == CGSize(width: 800, height: 800))
    }

    @Test func degenerateInputsFallBackToCurrentFrame() {
        let current = CGRect(x: 100, y: 100, width: 800, height: 600)
        let frame = VideoWindowLayout.frame(
            current: current, playerArea: .zero,
            targetPlayerArea: .zero,
            minSize: minSize, visible: .zero)
        #expect(frame == current)
    }
}
