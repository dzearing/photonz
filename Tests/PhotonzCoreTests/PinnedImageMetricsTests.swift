import CoreGraphics
import Testing
@testable import PhotonzCore

/// Sizing + opacity math for pin-to-screen floating windows (phase 11.8). The
/// AppKit window shell uses these; keeping them pure makes them testable.
@Suite("PinnedImageMetrics")
struct PinnedImageMetricsTests {

    @Test func landscapeFitsByWidth() {
        let s = PinnedImageMetrics.fittedSize(imageSize: CGSize(width: 800, height: 400), maxDimension: 360)
        #expect(s == CGSize(width: 360, height: 180))
    }

    @Test func portraitFitsByHeight() {
        let s = PinnedImageMetrics.fittedSize(imageSize: CGSize(width: 400, height: 800), maxDimension: 360)
        #expect(s == CGSize(width: 180, height: 360))
    }

    @Test func smallImageIsNotUpscaled() {
        let s = PinnedImageMetrics.fittedSize(imageSize: CGSize(width: 120, height: 90), maxDimension: 360)
        #expect(s == CGSize(width: 120, height: 90))
    }

    @Test func roundsToWholePixels() {
        let s = PinnedImageMetrics.fittedSize(imageSize: CGSize(width: 333, height: 100), maxDimension: 360)
        // 333 < 360, no scale → unchanged, integral.
        #expect(s == CGSize(width: 333, height: 100))
    }

    @Test func invalidSizesYieldZero() {
        #expect(PinnedImageMetrics.fittedSize(imageSize: .zero, maxDimension: 360) == .zero)
        #expect(PinnedImageMetrics.fittedSize(imageSize: CGSize(width: 100, height: 100), maxDimension: 0) == .zero)
    }

    @Test func opacityClampsToTheLegibleRange() {
        #expect(PinnedImageMetrics.clampOpacity(0.05) == PinnedImageMetrics.minOpacity)
        #expect(PinnedImageMetrics.clampOpacity(1.5) == PinnedImageMetrics.maxOpacity)
        #expect(PinnedImageMetrics.clampOpacity(0.6) == 0.6)
    }
}
