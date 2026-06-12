import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("Geometry")
struct GeometryTests {

    @Test func aspectFitShrinksToBounds() {
        let fit = Geometry.aspectFit(CGSize(width: 2000, height: 1000), in: CGSize(width: 500, height: 500))
        #expect(fit == CGSize(width: 500, height: 250))
    }

    @Test func aspectFitGrowsToBounds() {
        let fit = Geometry.aspectFit(CGSize(width: 10, height: 20), in: CGSize(width: 100, height: 100))
        #expect(fit == CGSize(width: 50, height: 100))
    }

    @Test func aspectFitZeroSizeIsSafe() {
        #expect(Geometry.aspectFit(.zero, in: CGSize(width: 100, height: 100)) == .zero)
    }

    @Test func aspectFillCoversBounds() {
        let fill = Geometry.aspectFill(CGSize(width: 200, height: 100), in: CGSize(width: 100, height: 100))
        #expect(fill == CGSize(width: 200, height: 100))
    }

    @Test func clampCropStaysInsideCanvas() {
        let clamped = Geometry.clampCrop(CGRect(x: -50, y: -50, width: 200, height: 200),
                                         toCanvas: CGSize(width: 100, height: 100))
        #expect(clamped == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func clampCropNormalizesNegativeRects() {
        // A drag from bottom-right to top-left produces a negative-size rect.
        let clamped = Geometry.clampCrop(CGRect(x: 80, y: 80, width: -60, height: -60),
                                         toCanvas: CGSize(width: 100, height: 100))
        #expect(clamped == CGRect(x: 20, y: 20, width: 60, height: 60))
    }

    @Test func resizeScaleComputesPerAxisFactors() {
        let scale = Geometry.resizeScale(from: CGSize(width: 100, height: 200), to: CGSize(width: 50, height: 400))
        #expect(scale == CGPoint(x: 0.5, y: 2))
    }

    @Test func skewTransformKeepsCenterFixed() {
        let center = CGPoint(x: 50, y: 50)
        let t = Geometry.skewTransform(xAngle: 0.3, yAngle: -0.2, around: center)
        let moved = center.applying(t)
        #expect(abs(moved.x - center.x) < 1e-9)
        #expect(abs(moved.y - center.y) < 1e-9)
    }

    @Test func skewTransformSlantsOffCenterPoints() {
        let t = Geometry.skewTransform(xAngle: .pi / 4, yAngle: 0, around: .zero)
        let moved = CGPoint(x: 0, y: 10).applying(t)
        // tan(45°) == 1, so y displacement of 10 shifts x by 10.
        #expect(abs(moved.x - 10) < 1e-9)
        #expect(abs(moved.y - 10) < 1e-9)
    }

    @Test func zoomCalloutPrefersLargestFreeQuadrant() {
        // Source box near the left edge: callout should go right.
        let placed = Geometry.zoomCalloutPlacement(source: CGRect(x: 10, y: 100, width: 50, height: 50),
                                                   magnification: 2,
                                                   canvas: CGSize(width: 1000, height: 300))
        #expect(placed.size == CGSize(width: 100, height: 100))
        #expect(placed.minX > 60)
    }

    @Test func zoomCalloutStaysOnCanvas() {
        let canvas = CGSize(width: 400, height: 300)
        let placed = Geometry.zoomCalloutPlacement(source: CGRect(x: 10, y: 10, width: 100, height: 100),
                                                   magnification: 3,
                                                   canvas: canvas)
        #expect(placed.minX >= 0)
        #expect(placed.minY >= 0)
        #expect(placed.maxX <= canvas.width)
        #expect(placed.maxY <= canvas.height)
    }

    @Test func leaderLinesReturnsTwoShortestConnections() {
        let lines = Geometry.leaderLines(source: CGRect(x: 0, y: 0, width: 10, height: 10),
                                         callout: CGRect(x: 100, y: 0, width: 20, height: 20))
        #expect(lines.count == 2)
        // Both connections should originate from the source's right edge (nearest side).
        for line in lines {
            #expect(line.from.x == 10)
        }
    }
}
