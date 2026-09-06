import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Drawing a new shape with the grid on.
///
/// Moving and resizing a layer have pulled to the grid for a while; drawing one
/// did not, so a box drawn on graph paper came out wherever the pointer
/// happened to start and stop. These pin down the promise the rest of the
/// canvas already keeps: both ends of a draw land on lines you can see, a real
/// picture edge still outranks the grid, and ⌘ still hands back the pointer.
@Suite("Drawing on the grid")
struct AnnotationGridSnappingTests {

    /// No detected edges at all, so nothing but the grid can move a point.
    private var blank: EdgeMap {
        EdgeMap(width: 64, height: 64,
                gxMagnitude: [Double](repeating: 0, count: 64 * 64),
                gyMagnitude: [Double](repeating: 0, count: 64 * 64))
    }

    // MARK: The two ends land on the grid

    @Test func theFirstCornerLandsOnTheGrid() {
        let snap = AnnotationSnapping.snap(CGPoint(x: 407, y: 293), shape: .rectangle,
                                           opposite: nil, edges: blank, zoom: 1,
                                           gridSpacing: 32)
        #expect(snap.point == CGPoint(x: 416, y: 288))
        #expect(snap.gridX == 416)
        #expect(snap.gridY == 288)
    }

    @Test func theSecondCornerLandsOnTheGridToo() {
        let snap = AnnotationSnapping.snap(CGPoint(x: 500, y: 360), shape: .rectangle,
                                           opposite: CGPoint(x: 416, y: 288),
                                           edges: blank, zoom: 1, gridSpacing: 32)
        #expect(snap.point == CGPoint(x: 512, y: 352))
    }

    /// The complaint, end to end: the drag from the report used to produce
    /// exactly (400,300,100,60) — every number off every line.
    @Test func theReportedDragNowProducesAWholeNumberOfCells() {
        let a = AnnotationSnapping.snap(CGPoint(x: 400, y: 300), shape: .rectangle,
                                        opposite: nil, edges: blank, zoom: 1,
                                        gridSpacing: 32).point
        let b = AnnotationSnapping.snap(CGPoint(x: 500, y: 360), shape: .rectangle,
                                        opposite: a, edges: blank, zoom: 1,
                                        gridSpacing: 32).point
        #expect(a == CGPoint(x: 416, y: 288))
        #expect(b == CGPoint(x: 512, y: 352))
        #expect((b.x - a.x).truncatingRemainder(dividingBy: 32) == 0)
        #expect((b.y - a.y).truncatingRemainder(dividingBy: 32) == 0)
    }

    /// The grid is counted from where the grid starts, not from zero, or a
    /// snapped corner sits beside a drawn line rather than on it.
    @Test func theGridIsCountedFromWhereItStarts() {
        let snap = AnnotationSnapping.snap(CGPoint(x: 100, y: 100), shape: .rectangle,
                                           opposite: nil, edges: blank, zoom: 1,
                                           gridSpacing: 32, gridOrigin: CGPoint(x: 10, y: 6))
        #expect(snap.point == CGPoint(x: 106, y: 102))
    }

    /// Columns only: there is no line across to land on, so the vertical stays
    /// exactly where the hand put it.
    @Test func aColumnsOnlyGridPullsSidewaysAndLeavesTheRestAlone() {
        let snap = AnnotationSnapping.snap(CGPoint(x: 407, y: 293), shape: .rectangle,
                                           opposite: nil, edges: blank, zoom: 1,
                                           gridSpacing: 32, gridAxes: .columns)
        #expect(snap.point.x == 416)
        #expect(snap.point.y == 293)
        #expect(snap.gridY == nil)
    }

    // MARK: Nothing pulling

    @Test func withNoGridTheDrawIsExactlyWhatItAlwaysWas() {
        let plain = AnnotationSnapping.snap(CGPoint(x: 407, y: 293), shape: .rectangle,
                                            opposite: nil, edges: blank, zoom: 1)
        #expect(plain.point == CGPoint(x: 407, y: 293))
        #expect(plain.gridX == nil)
        #expect(plain.gridY == nil)
    }

    @Test func commandStillHandsBackThePointer() {
        let snap = AnnotationSnapping.snap(CGPoint(x: 407.4, y: 293.2), shape: .rectangle,
                                           opposite: CGPoint(x: 384, y: 288),
                                           edges: blank, zoom: 1, free: true,
                                           gridSpacing: 32)
        #expect(snap.point == CGPoint(x: 407.4, y: 293.2))
        #expect(snap.gridX == nil)
        #expect(snap.gridY == nil)
    }

    // MARK: A real edge still wins

    @Test func aDetectedEdgeOutranksTheGrid() {
        var field = Field(w: 64, h: 64)
        field.addVerticalEdge(col: 30, y0: 0, y1: 63)
        let snap = AnnotationSnapping.snap(CGPoint(x: 31, y: 20), shape: .rectangle,
                                           opposite: nil, edges: field.map, zoom: 1,
                                           gridSpacing: 32)
        #expect(snap.guideX == 30)
        #expect(snap.point.x == 30)
        // The grid did not place this one, so no grid line lights up for it.
        #expect(snap.gridX == nil)
    }

    // MARK: The one cell floor

    /// A box shorter than half a cell would otherwise quantize both corners
    /// onto the same line, and a zero sized drag reads as a click: you drag,
    /// and nothing appears.
    @Test func aBoxDrawnSmallerThanOneCellStillComesOutOneCell() {
        let anchor = CGPoint(x: 384, y: 288)
        let snap = AnnotationSnapping.snap(CGPoint(x: 394, y: 297), shape: .rectangle,
                                           opposite: anchor, edges: blank, zoom: 1,
                                           gridSpacing: 32)
        #expect(snap.point == CGPoint(x: 416, y: 320))
    }

    @Test func theFloorFollowsTheDirectionTheHandWent() {
        let anchor = CGPoint(x: 384, y: 288)
        let snap = AnnotationSnapping.snap(CGPoint(x: 374, y: 279), shape: .rectangle,
                                           opposite: anchor, edges: blank, zoom: 1,
                                           gridSpacing: 32)
        #expect(snap.point == CGPoint(x: 352, y: 256))
    }

    /// Before the pointer has moved enough to be a drag there is nothing to
    /// floor: a click with a drawing tool must still draw nothing.
    @Test func aClickIsNotFlooredIntoAWholeCell() {
        let anchor = CGPoint(x: 384, y: 288)
        let snap = AnnotationSnapping.snap(CGPoint(x: 386, y: 289), shape: .rectangle,
                                           opposite: anchor, edges: blank, zoom: 1,
                                           gridSpacing: 32)
        #expect(snap.point == anchor)
    }

    /// A flat arrow may only catch sideways, so the floor may only push it
    /// sideways: a whole cell of drop would tilt a mark the hand drew level.
    @Test func aFlatArrowIsNeverPushedOffItsLine() {
        let anchor = CGPoint(x: 384, y: 288)
        let snap = AnnotationSnapping.snap(CGPoint(x: 400, y: 290), shape: .arrow,
                                           opposite: anchor, edges: blank, zoom: 1,
                                           gridSpacing: 32)
        #expect(snap.point.x == 416)
        #expect(snap.point.y == 288)
    }

    // MARK: The shapeless box tools

    /// A frame and a zoom callout are drawn by the same drag but carry no
    /// annotation shape. They are boxes, and they land on the grid like one.
    @Test func aFrameLandsOnTheGrid() {
        let snap = AnnotationSnapping.snap(CGPoint(x: 407, y: 293), shape: nil,
                                           opposite: nil, edges: blank, zoom: 1,
                                           gridSpacing: 32)
        #expect(snap.point == CGPoint(x: 416, y: 288))
    }

    @Test func aFrameWithNoGridIsUntouched() {
        let snap = AnnotationSnapping.snap(CGPoint(x: 407.4, y: 293.2), shape: nil,
                                           opposite: nil, edges: blank, zoom: 1)
        #expect(snap.point == CGPoint(x: 407.4, y: 293.2))
    }

    // MARK: Holding a line

    /// A lit grid line keeps the drag through a wobble, exactly as it does for
    /// a move, so a shaking hand does not throw the corner a cell back and
    /// forth across the halfway mark.
    @Test func aLitLineHoldsThroughAWobble() {
        let anchor = CGPoint(x: 384, y: 288)
        var held = SnapHold.none
        held.caught(x: 512, y: 352)
        let snap = AnnotationSnapping.snap(CGPoint(x: 528.5, y: 352), shape: .rectangle,
                                           opposite: anchor, edges: blank, zoom: 1,
                                           gridHolding: held, gridSpacing: 32)
        #expect(snap.point.x == 512)
    }

    /// The two memories are separate on purpose. A held line comes straight
    /// back out as the guide, so a grid line handed to the EDGE memory would
    /// claim to be a border found in the picture: the yellow guide would light
    /// for a line of graph paper, and the grid's own quantize would be skipped.
    @Test func aGridLineNeverComesBackAsAPictureEdge() {
        let anchor = CGPoint(x: 640, y: 320)
        var gridHeld = SnapHold.none
        gridHeld.caught(x: 640, y: 320)
        let snap = AnnotationSnapping.snap(CGPoint(x: 650, y: 330), shape: .rectangle,
                                           opposite: anchor, edges: blank, zoom: 1,
                                           gridHolding: gridHeld, gridSpacing: 32)
        #expect(snap.guideX == nil)
        #expect(snap.guideY == nil)
        // …and the floor still gets its turn, so the 10pt drag is a whole cell.
        #expect(snap.point == CGPoint(x: 672, y: 352))
        #expect(snap.gridX == 672)
    }
}

/// Synthetic gradient field, same shape as the one in AnnotationSnappingTests.
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

    mutating func addVerticalEdge(col: Int, y0: Int, y1: Int, magnitude: Double = 2) {
        for y in max(0, y0)...min(h - 1, y1) { gx[y * w + col] = magnitude }
    }

    var map: EdgeMap {
        EdgeMap(width: w, height: h, gxMagnitude: gx, gyMagnitude: gy)
    }
}
