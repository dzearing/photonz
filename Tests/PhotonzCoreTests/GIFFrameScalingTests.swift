import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// **A smaller GIF is a lighter one.** A GIF frame brought down with a wide
/// filter turns every crisp edge of a screen recording into a run of in-between
/// greys, and a GIF pays for every colour it has to tell apart: a 640 pixel
/// recording of text came out heavier at Small (480) than at Standard (kept at
/// 640). A frame is brought down in at most two steps instead: the wide filter
/// to twice the size it ends at, where it has to throw a lot away, then one
/// plain step that never spans more than two pixels.
@Suite("A GIF frame is brought down in at most two steps")
struct GIFFrameScalingTests {

    @Test("Down by two or less is one plain step")
    func downByTwoOrLessIsOneStep() {
        let small = CGSize(width: 480, height: 300)
        #expect(GIFFrameScaling.firstStep(from: CGSize(width: 640, height: 400), to: small) == nil)
        #expect(GIFFrameScaling.firstStep(from: CGSize(width: 960, height: 600), to: small) == nil)
        #expect(GIFFrameScaling.firstStep(from: small, to: small) == nil)
    }

    @Test("Down by more than two stops first at twice the size it ends at")
    func downByMoreStopsAtTwice() {
        #expect(GIFFrameScaling.firstStep(from: CGSize(width: 1920, height: 1200),
                                          to: CGSize(width: 480, height: 300))
                == CGSize(width: 960, height: 600))
        #expect(GIFFrameScaling.firstStep(from: CGSize(width: 2560, height: 1600),
                                          to: CGSize(width: 800, height: 500))
                == CGSize(width: 1600, height: 1000))
    }

    @Test("A frame tall and narrow is measured by the side that shrinks most")
    func tallFrameUsesTheSideThatShrinksMost() {
        // 300 wide stays under twice 160, 1200 tall does not under twice 480.
        #expect(GIFFrameScaling.firstStep(from: CGSize(width: 300, height: 1200),
                                          to: CGSize(width: 120, height: 480))
                == CGSize(width: 240, height: 960))
    }

    @Test("A frame with no size has no step")
    func noSizeNoStep() {
        #expect(GIFFrameScaling.firstStep(from: .zero, to: CGSize(width: 480, height: 300)) == nil)
        #expect(GIFFrameScaling.firstStep(from: CGSize(width: 640, height: 400), to: .zero) == nil)
    }
}
