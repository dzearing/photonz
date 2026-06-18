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

    @Test func arrowheadTipIsAtEndPoint() {
        let points = Geometry.arrowhead(start: CGPoint(x: 0, y: 50), end: CGPoint(x: 80, y: 50), strokeWidth: 6)
        #expect(points.count == 3)
        #expect(points[0] == CGPoint(x: 80, y: 50))
    }

    @Test func arrowheadWingsAreSymmetricAboutTheAxis() {
        let points = Geometry.arrowhead(start: CGPoint(x: 0, y: 50), end: CGPoint(x: 80, y: 50), strokeWidth: 6)
        let left = points[1]
        let right = points[2]
        // For a horizontal arrow the wings sit behind the tip, mirrored across y = 50.
        #expect(left.x == right.x)
        #expect(left.x < 80)
        #expect(abs((50 - left.y) - (right.y - 50)) < 1e-9)
        #expect(left.y != right.y)
    }

    @Test func arrowheadScalesWithStrokeWidth() {
        let thin = Geometry.arrowhead(start: .zero, end: CGPoint(x: 100, y: 0), strokeWidth: 2)
        let thick = Geometry.arrowhead(start: .zero, end: CGPoint(x: 100, y: 0), strokeWidth: 8)
        let thinLength = 100 - thin[1].x
        let thickLength = 100 - thick[1].x
        #expect(thickLength > thinLength)
    }

    @Test func arrowheadDegenerateArrowIsSafe() {
        // start == end: no direction — should not produce NaNs.
        let points = Geometry.arrowhead(start: CGPoint(x: 5, y: 5), end: CGPoint(x: 5, y: 5), strokeWidth: 4)
        for p in points {
            #expect(p.x.isFinite && p.y.isFinite)
        }
    }

    @Test func arrowheadIsClearlyWiderThanTheShaft() {
        // The whole point of the redesign: the head must read as an arrowhead,
        // not a pinprick. Full width should be several times the shaft width.
        for stroke in [CGFloat(2), 4, 6, 10] {
            let points = Geometry.arrowhead(start: CGPoint(x: 0, y: 50),
                                            end: CGPoint(x: 200, y: 50), strokeWidth: stroke)
            let fullWidth = abs(points[1].y - points[2].y)
            #expect(fullWidth >= stroke * 3.5,
                    "head full width \(fullWidth) should be >= 3.5x the \(stroke)px shaft")
        }
    }

    @Test func arrowheadHeadIsLongerThanItIsHalfWide() {
        // A sensible aspect: the head reads as a triangle pointing forward, not
        // a squat wedge. Length should exceed half-width.
        let points = Geometry.arrowhead(start: CGPoint(x: 0, y: 0),
                                        end: CGPoint(x: 200, y: 0), strokeWidth: 6)
        let headLength = 200 - points[1].x
        let halfWidth = abs(points[1].y)
        #expect(headLength > halfWidth, "head length \(headLength) should exceed half-width \(halfWidth)")
    }

    @Test func arrowheadScaleEnlargesTheHead() {
        let normal = Geometry.arrowhead(start: .zero, end: CGPoint(x: 200, y: 0),
                                        strokeWidth: 6, scale: 1)
        let big = Geometry.arrowhead(start: .zero, end: CGPoint(x: 200, y: 0),
                                     strokeWidth: 6, scale: 2)
        let normalLen = 200 - normal[1].x
        let bigLen = 200 - big[1].x
        let normalWidth = abs(normal[1].y - normal[2].y)
        let bigWidth = abs(big[1].y - big[2].y)
        #expect(bigLen > normalLen * 1.8, "scale 2 head should be markedly longer")
        #expect(bigWidth > normalWidth * 1.8, "scale 2 head should be markedly wider")
    }

    @Test func arrowShaftStopsShortOfTheTipSoItDoesNotPokeThrough() {
        let start = CGPoint(x: 0, y: 50), end = CGPoint(x: 200, y: 50)
        let shaftEnd = Geometry.arrowShaftEnd(start: start, end: end, strokeWidth: 6, scale: 1)
        let head = Geometry.arrowhead(start: start, end: end, strokeWidth: 6, scale: 1)
        let headBaseX = head[1].x // wings sit at the base of the head
        // The shaft must end before the tip (so its round cap can't poke past it)
        // and inside the head (so the filled head covers the join — no gap).
        #expect(shaftEnd.x < end.x, "shaft should stop short of the tip")
        #expect(shaftEnd.x > headBaseX, "shaft should reach into the head so there's no gap")
        #expect(abs(shaftEnd.y - 50) < 1e-9, "shaft end stays on the axis")
    }

    @Test func arrowShaftEndDegenerateIsSafe() {
        let p = Geometry.arrowShaftEnd(start: .zero, end: .zero, strokeWidth: 4, scale: 1)
        #expect(p.x.isFinite && p.y.isFinite)
    }

    @Test func arrowheadHalfWidthMatchesTheHeadGeometry() {
        // The frame-padding helper must agree with the actual wing reach, or
        // arrows clip / get loose bounding boxes.
        let points = Geometry.arrowhead(start: CGPoint(x: 0, y: 50),
                                        end: CGPoint(x: 200, y: 50), strokeWidth: 6)
        let wingReach = abs(points[1].y - 50)
        #expect(abs(Geometry.arrowheadHalfWidth(strokeWidth: 6) - wingReach) < 1e-6)
    }
}
