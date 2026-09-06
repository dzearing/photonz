import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Synthetic gradient fields, mirroring what the analyzer produces.
private struct Field {
    var w: Int, h: Int
    var gx: [Double]
    var gy: [Double]

    init(w: Int, h: Int) {
        self.w = w
        self.h = h
        gx = [Double](repeating: 0, count: w * h)
        gy = [Double](repeating: 0, count: w * h)
    }

    mutating func addHorizontalEdge(row: Int, x0: Int, x1: Int, magnitude: Double = 2) {
        for x in max(0, x0)...min(w - 1, x1) { gy[row * w + x] = magnitude }
    }

    mutating func addVerticalEdge(col: Int, y0: Int, y1: Int, magnitude: Double = 2) {
        for y in max(0, y0)...min(h - 1, y1) { gx[y * w + col] = magnitude }
    }

    var map: EdgeMap {
        EdgeMap(width: w, height: h, gxMagnitude: gx, gyMagnitude: gy)
    }
}

@Suite("Annotation snapping")
struct AnnotationSnappingTests {

    // MARK: Which axes an endpoint may catch

    @Test func aBoxCornerCatchesBothAxes() {
        for shape in [AnnotationShape.rectangle, .ellipse, .highlight] {
            let axes = AnnotationSnapping.axes(shape: shape, opposite: CGPoint(x: 0, y: 0),
                                               moving: CGPoint(x: 200, y: 4))
            #expect(axes.x)
            #expect(axes.y)
        }
    }

    @Test func aFlatArrowOnlyCatchesTheEdgeItPointsAt() {
        // Pointing right along a near-horizontal shaft: the tip lands on the
        // vertical border ahead of it and must not slide up or down an edge.
        let axes = AnnotationSnapping.axes(shape: .arrow, opposite: CGPoint(x: 0, y: 0),
                                           moving: CGPoint(x: 200, y: 4))
        #expect(axes.x)
        #expect(!axes.y)
    }

    @Test func anUprightArrowOnlyCatchesTheHorizontalEdge() {
        let axes = AnnotationSnapping.axes(shape: .arrow, opposite: CGPoint(x: 0, y: 0),
                                           moving: CGPoint(x: 4, y: 200))
        #expect(!axes.x)
        #expect(axes.y)
    }

    @Test func aDiagonalArrowCatchesBothSoItCanLandOnACorner() {
        let axes = AnnotationSnapping.axes(shape: .arrow, opposite: CGPoint(x: 0, y: 0),
                                           moving: CGPoint(x: 200, y: 120))
        #expect(axes.x)
        #expect(axes.y)
    }

    @Test func anEndpointWithNoShaftYetCatchesBothAxes() {
        // The tail is placed before there is any direction to read.
        let axes = AnnotationSnapping.axes(shape: .arrow, opposite: nil,
                                           moving: CGPoint(x: 10, y: 10))
        #expect(axes.x)
        #expect(axes.y)
        let zero = AnnotationSnapping.axes(shape: .arrow, opposite: CGPoint(x: 10, y: 10),
                                           moving: CGPoint(x: 10, y: 10))
        #expect(zero.x)
        #expect(zero.y)
    }

    // MARK: Snapping the endpoint itself

    @Test func anArrowTipLandsOnTheVerticalEdgeItPointsAt() {
        var f = Field(w: 400, h: 400)
        f.addVerticalEdge(col: 200, y0: 50, y1: 150)
        let snap = AnnotationSnapping.snap(CGPoint(x: 197, y: 100), shape: .arrow,
                                           opposite: CGPoint(x: 40, y: 100),
                                           edges: f.map, zoom: 1)
        #expect(snap.point.x == 200)
        #expect(snap.guideX == 200)
    }

    @Test func aFlatArrowTipDoesNotDriftAlongTheEdgeItLandsOn() {
        // A horizontal edge sits 3px under the tip. A near-horizontal arrow must
        // ignore it: it is pointing at the border ahead, not the line below.
        var f = Field(w: 400, h: 400)
        f.addVerticalEdge(col: 200, y0: 50, y1: 150)
        f.addHorizontalEdge(row: 103, x0: 150, x1: 250)
        let snap = AnnotationSnapping.snap(CGPoint(x: 197, y: 100), shape: .arrow,
                                           opposite: CGPoint(x: 40, y: 100),
                                           edges: f.map, zoom: 1)
        #expect(snap.point.x == 200)
        #expect(snap.point.y == 100)
        #expect(snap.guideY == nil)
    }

    @Test func aDiagonalArrowTipLandsOnACorner() {
        var f = Field(w: 400, h: 400)
        f.addVerticalEdge(col: 200, y0: 100, y1: 300)
        f.addHorizontalEdge(row: 150, x0: 200, x1: 380)
        let snap = AnnotationSnapping.snap(CGPoint(x: 197, y: 153), shape: .arrow,
                                           opposite: CGPoint(x: 60, y: 40),
                                           edges: f.map, zoom: 1)
        #expect(snap.point.x == 200)
        #expect(snap.point.y == 150)
    }

    @Test func aBoxCornerLandsOnTheElementUnderIt() {
        var f = Field(w: 400, h: 400)
        f.addVerticalEdge(col: 120, y0: 60, y1: 260)
        f.addHorizontalEdge(row: 80, x0: 120, x1: 340)
        let snap = AnnotationSnapping.snap(CGPoint(x: 123, y: 77), shape: .rectangle,
                                           opposite: CGPoint(x: 340, y: 260),
                                           edges: f.map, zoom: 1)
        #expect(snap.point.x == 120)
        #expect(snap.point.y == 80)
    }

    @Test func aFarEndpointIsLeftWhereThePointerIs() {
        var f = Field(w: 400, h: 400)
        f.addVerticalEdge(col: 200, y0: 50, y1: 150)
        let snap = AnnotationSnapping.snap(CGPoint(x: 160, y: 100), shape: .arrow,
                                           opposite: CGPoint(x: 40, y: 100),
                                           edges: f.map, zoom: 1)
        #expect(snap.point.x == 160)
        #expect(snap.guideX == nil)
    }

    @Test func aFreedEndpointStaysExactlyUnderThePointer() {
        var f = Field(w: 400, h: 400)
        f.addVerticalEdge(col: 200, y0: 50, y1: 150)
        let snap = AnnotationSnapping.snap(CGPoint(x: 197.4, y: 100.6), shape: .arrow,
                                           opposite: CGPoint(x: 40, y: 100),
                                           edges: f.map, zoom: 1, free: true)
        #expect(snap.point == CGPoint(x: 197.4, y: 100.6))
        #expect(snap.guideX == nil)
        #expect(snap.guideY == nil)
    }

    @Test func anUncaughtEndpointStillLandsOnAWholePixel() {
        let f = Field(w: 400, h: 400)
        let snap = AnnotationSnapping.snap(CGPoint(x: 160.4, y: 100.6), shape: .arrow,
                                           opposite: CGPoint(x: 40, y: 100),
                                           edges: f.map, zoom: 1)
        #expect(snap.point == CGPoint(x: 160, y: 101))
    }

    @Test func aCaughtEdgeIsKeptWhileThePointerWobbles() {
        // The hold is what stops a line being taken and given back between
        // frames; annotations read the same one every other snapping drag does.
        var f = Field(w: 400, h: 400)
        f.addVerticalEdge(col: 200, y0: 50, y1: 150)
        let held = SnapHold(x: 200)
        let snap = AnnotationSnapping.snap(CGPoint(x: 189, y: 100), shape: .arrow,
                                           opposite: CGPoint(x: 40, y: 100),
                                           edges: f.map, zoom: 1, holding: held)
        #expect(snap.point.x == 200)
        #expect(snap.guideX == 200)
    }

    @Test func aLineCrossedOnTheWayDoesNotRideAlongToTheTarget() {
        // The sweep to the target crossed a text edge at y=121 and caught it.
        // The pointer is now at 97, three pixels off the border at y=100 it was
        // aimed at: the border wins, because a line you have gone past is not a
        // line you are standing on.
        var f = Field(w: 400, h: 400)
        f.addHorizontalEdge(row: 100, x0: 300, x1: 380)
        f.addHorizontalEdge(row: 121, x0: 300, x1: 380)
        let snap = AnnotationSnapping.snap(CGPoint(x: 340, y: 97), shape: .arrow,
                                           opposite: CGPoint(x: 340, y: 300),
                                           edges: f.map, zoom: 0.5,
                                           holding: SnapHold(y: 121))
        #expect(snap.point.y == 100)
        #expect(snap.guideY == 100)
    }

    @Test func aHeldLineStillWinsWhenNothingNearerIsOffered() {
        // Same hold, but the pointer has only drifted: with no rival line in
        // reach the hold keeps it, so a wobble cannot drop the guide.
        var f = Field(w: 400, h: 400)
        f.addHorizontalEdge(row: 121, x0: 300, x1: 380)
        let snap = AnnotationSnapping.snap(CGPoint(x: 340, y: 100), shape: .arrow,
                                           opposite: CGPoint(x: 340, y: 300),
                                           edges: f.map, zoom: 0.5,
                                           holding: SnapHold(y: 121))
        #expect(snap.point.y == 121)
        #expect(snap.guideY == 121)
    }

    @Test func theTailSnapsTooWhenItIsTheEndBeingDragged() {
        // Dragging the START of a flat arrow: the shaft is still horizontal, so
        // the tail catches the vertical edge behind it and keeps its height.
        var f = Field(w: 400, h: 400)
        f.addVerticalEdge(col: 60, y0: 50, y1: 150)
        f.addHorizontalEdge(row: 97, x0: 20, x1: 200)
        let snap = AnnotationSnapping.snap(CGPoint(x: 63, y: 100), shape: .arrow,
                                           opposite: CGPoint(x: 300, y: 100),
                                           edges: f.map, zoom: 1)
        #expect(snap.point.x == 60)
        #expect(snap.point.y == 100)
    }
}
