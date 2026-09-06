import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Drawing a mark near a pinned guide.
///
/// Moving and resizing a layer have caught pinned guides since guides landed;
/// drawing did not, because the ends of an arrow, a line or a box go down a
/// different path. These pin down the promise the goal makes: a guide means the
/// same thing wherever you are drawing.
@Suite("Drawing catches pinned guides")
struct AnnotationGuideSnappingTests {

    /// No detected edges at all, so nothing but a guide or the grid can move a
    /// point.
    private var blank: EdgeMap {
        EdgeMap(width: 64, height: 64,
                gxMagnitude: [Double](repeating: 0, count: 64 * 64),
                gyMagnitude: [Double](repeating: 0, count: 64 * 64))
    }

    private func guide(_ axis: CanvasGuideAxis, _ at: CGFloat) -> CanvasGuide {
        CanvasGuide(axis: axis, position: at)
    }

    // MARK: Both ends of a drawn mark

    @Test func anArrowTipCatchesAVerticalGuide() {
        let snap = AnnotationSnapping.snap(CGPoint(x: 316, y: 200), shape: .arrow,
                                           opposite: CGPoint(x: 100, y: 200),
                                           edges: blank, zoom: 1,
                                           guides: [guide(.vertical, 320)])
        #expect(snap.point.x == 320)
        // The same field a dragged layer fills, so the same yellow line lights.
        #expect(snap.guideX == 320)
    }

    @Test func theEndPlacedFirstCatchesOneToo() {
        let snap = AnnotationSnapping.snap(CGPoint(x: 316, y: 200), shape: .line,
                                           opposite: nil, edges: blank, zoom: 1,
                                           guides: [guide(.vertical, 320)])
        #expect(snap.point.x == 320)
        #expect(snap.guideX == 320)
    }

    @Test func aHorizontalGuideCatchesTheOtherAxis() {
        let snap = AnnotationSnapping.snap(CGPoint(x: 300, y: 196), shape: .arrow,
                                           opposite: CGPoint(x: 300, y: 40),
                                           edges: blank, zoom: 1,
                                           guides: [guide(.horizontal, 200)])
        #expect(snap.point.y == 200)
        #expect(snap.guideY == 200)
        #expect(snap.guideX == nil)
    }

    @Test func aBoxCornerCatchesGuidesOnBothAxesAtOnce() {
        let snap = AnnotationSnapping.snap(CGPoint(x: 316, y: 196), shape: .rectangle,
                                           opposite: CGPoint(x: 100, y: 100),
                                           edges: blank, zoom: 1,
                                           guides: [guide(.vertical, 320),
                                                    guide(.horizontal, 200)])
        #expect(snap.point == CGPoint(x: 320, y: 200))
        #expect(snap.guideX == 320)
        #expect(snap.guideY == 200)
    }

    /// A frame or a zoom callout carries no annotation shape and takes no edge
    /// magnets, but it is a box: it lands on a guide the way it lands on the
    /// grid.
    @Test func aShapelessBoxCatchesAGuide() {
        let snap = AnnotationSnapping.snap(CGPoint(x: 316, y: 196), shape: nil,
                                           opposite: CGPoint(x: 100, y: 100),
                                           edges: blank, zoom: 1,
                                           guides: [guide(.vertical, 320)])
        #expect(snap.point.x == 320)
        #expect(snap.guideX == 320)
        // Nothing pinned across, so the other axis is left exactly where the
        // hand put it.
        #expect(snap.point.y == 196)
    }

    /// A guide is pinned on purpose, so unlike an edge found in the picture it
    /// catches whichever way the mark is pointing: an arrow drawn along a
    /// pinned line comes out lying exactly on it.
    @Test func aGuideCatchesEvenTheAxisTheArrowIsNotPointingAlong() {
        let snap = AnnotationSnapping.snap(CGPoint(x: 300, y: 197), shape: .arrow,
                                           opposite: CGPoint(x: 100, y: 200),
                                           edges: blank, zoom: 1,
                                           guides: [guide(.horizontal, 200)])
        #expect(snap.point.y == 200)
        #expect(snap.guideY == 200)
    }

    // MARK: Against the grid, the picture, and ⌘

    @Test func aGuideWinsOverTheGridUnderneathIt() {
        let snap = AnnotationSnapping.snap(CGPoint(x: 318, y: 400), shape: .rectangle,
                                           opposite: nil, edges: blank, zoom: 1,
                                           gridSpacing: 8,
                                           guides: [guide(.vertical, 322)])
        #expect(snap.point.x == 322)
        #expect(snap.guideX == 322)
        // The grid did not place this one, so no grid line lights for it.
        #expect(snap.gridX == nil)
    }

    @Test func awayFromEveryGuideTheGridStillPlacesIt() {
        let snap = AnnotationSnapping.snap(CGPoint(x: 101, y: 400), shape: .rectangle,
                                           opposite: nil, edges: blank, zoom: 1,
                                           gridSpacing: 8,
                                           guides: [guide(.vertical, 322)])
        #expect(snap.point.x == 104)
        #expect(snap.guideX == nil)
        #expect(snap.gridX == 104)
    }

    /// A border right under the pointer still wins: lining up with a guide four
    /// points away must not cost you the pixel edge you are standing on.
    @Test func aDetectedEdgeUnderThePointerStillOutranksAGuideFarther() {
        var field = Field(w: 64, h: 64)
        field.addVerticalEdge(col: 30, y0: 0, y1: 63)
        let snap = AnnotationSnapping.snap(CGPoint(x: 31, y: 20), shape: .rectangle,
                                           opposite: nil, edges: field.map, zoom: 1,
                                           guides: [guide(.vertical, 25)])
        #expect(snap.point.x == 30)
        #expect(snap.guideX == 30)
    }

    @Test func commandFreesAnEndFromAGuideTheWayItFreesItFromTheGrid() {
        let snap = AnnotationSnapping.snap(CGPoint(x: 316.4, y: 200.2), shape: .arrow,
                                           opposite: CGPoint(x: 100, y: 200),
                                           edges: blank, zoom: 1, free: true,
                                           gridSpacing: 8,
                                           guides: [guide(.vertical, 320)])
        #expect(snap.point == CGPoint(x: 316.4, y: 200.2))
        #expect(snap.guideX == nil)
        #expect(snap.gridX == nil)
    }

    /// A guide already caught keeps the end through a wobble, exactly as a
    /// detected edge does: a line that is showing is the line you get.
    @Test func aCaughtGuideHoldsThroughAWobble() {
        let snap = AnnotationSnapping.snap(CGPoint(x: 331, y: 200), shape: .arrow,
                                           opposite: CGPoint(x: 100, y: 200),
                                           edges: blank, zoom: 1,
                                           holding: SnapHold(x: 320),
                                           guides: [guide(.vertical, 320)])
        #expect(snap.point.x == 320)
        #expect(snap.guideX == 320)
    }

    /// A document with no guides — and ⌘, which looks the same from here —
    /// draws bit for bit what it drew before guides could be caught.
    @Test func noGuidesChangesNothing() {
        let with = AnnotationSnapping.snap(CGPoint(x: 317, y: 293), shape: .rectangle,
                                           opposite: CGPoint(x: 100, y: 100),
                                           edges: blank, zoom: 1, gridSpacing: 32,
                                           guides: [])
        let without = AnnotationSnapping.snap(CGPoint(x: 317, y: 293), shape: .rectangle,
                                              opposite: CGPoint(x: 100, y: 100),
                                              edges: blank, zoom: 1, gridSpacing: 32)
        #expect(with == without)
    }
}

/// A synthetic gradient field, so a test can put one hard border in a blank
/// picture. The other annotation suites keep their own copy for the same
/// reason: it is file-private plumbing, not API.
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
