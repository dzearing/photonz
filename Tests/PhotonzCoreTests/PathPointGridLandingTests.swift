import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Dragging a point of a path with Snap to grid on: the point you grabbed
/// lands on a crossing of the grid the canvas is drawing, exactly as a point
/// placed with the Pen does, and everything else picked travels with it.
@Suite("A dragged path point lands on the grid")
struct PathPointGridLandingTests {

    static func square() -> PathContent {
        PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)), PathAnchor(point: CGPoint(x: 100, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 100)), PathAnchor(point: CGPoint(x: 0, y: 100))
        ], isClosed: true)
    }

    static func layer(turned radians: CGFloat = 0) -> Layer {
        var layer = PathBuilder.layer(square(), at: CGPoint(x: 200, y: 120))
        if radians != 0 { layer.transform = LayerTransform(rotation: radians) }
        return layer
    }

    static func near(_ a: CGPoint, _ b: CGPoint, _ slack: CGFloat = 1e-6) -> Bool {
        abs(a.x - b.x) <= slack && abs(a.y - b.y) <= slack
    }

    /// Where the grabbed point ends up on the canvas, the way the drag works
    /// it out: the point plus the pointer's travel in the shape's own space.
    static func landed(_ anchor: CGPoint, start: CGPoint, pointer: CGPoint,
                       in space: PathEditSpace) -> CGPoint {
        space.document(CGPoint(x: anchor.x + pointer.x - start.x,
                               y: anchor.y + pointer.y - start.y))
    }

    static let grid = NudgeGrid(spacing: 32)

    // MARK: - The crossing

    @Test func theGridNamesItsNearestCrossing() {
        #expect(Self.grid.crossing(nearest: CGPoint(x: 340, y: 261)) == CGPoint(x: 352, y: 256))
        let shifted = NudgeGrid(spacing: 32, origin: CGPoint(x: 10, y: 5))
        #expect(shifted.crossing(nearest: CGPoint(x: 340, y: 261)) == CGPoint(x: 330, y: 261))
    }

    @Test func aGridOfColumnsLeavesTheUpAndDownAlone() {
        let columns = NudgeGrid(spacing: 32, axes: .columns)
        #expect(columns.crossing(nearest: CGPoint(x: 340, y: 261)) == CGPoint(x: 352, y: 261))
    }

    // MARK: - The drag

    @Test func theGrabbedPointLandsOnTheCrossingNotThePointer() throws {
        let layer = Self.layer()
        let space = PathEditSpace(layer: layer)
        // The corner at 100,100 sits at 300,220 on the canvas. The press lands a
        // point off it, as a hand's does, and the pointer travels 40 by 41.
        let anchor = CGPoint(x: 100, y: 100)
        let press = CGPoint(x: 301, y: 221)
        let start = space.local(press)
        let landing = space.gridLanding(pointer: CGPoint(x: 341, y: 262), dragging: anchor,
                                        pressedAt: start, on: Self.grid)
        // 340,261 is nearest the crossing at 352,256.
        #expect(Self.near(Self.landed(anchor, start: start, pointer: landing.pointer, in: space),
                          CGPoint(x: 352, y: 256)))
        #expect(landing.lineX == 352)
        #expect(landing.lineY == 256)
    }

    @Test func nothingPullingReadsThePointerAsItIs() {
        let space = PathEditSpace(layer: Self.layer())
        let anchor = CGPoint(x: 100, y: 100)
        let start = space.local(CGPoint(x: 301, y: 221))
        let landing = space.gridLanding(pointer: CGPoint(x: 341, y: 262), dragging: anchor,
                                        pressedAt: start, on: nil)
        #expect(Self.near(landing.pointer, space.local(CGPoint(x: 341, y: 262))))
        #expect(landing.lineX == nil)
        #expect(landing.lineY == nil)
    }

    @Test func aGridOfColumnsOnlyHoldsTheLeftAndRight() {
        let space = PathEditSpace(layer: Self.layer())
        let anchor = CGPoint(x: 100, y: 100)
        let start = space.local(CGPoint(x: 300, y: 220))
        let landing = space.gridLanding(pointer: CGPoint(x: 341, y: 262), dragging: anchor,
                                        pressedAt: start,
                                        on: NudgeGrid(spacing: 32, axes: .columns))
        #expect(Self.near(Self.landed(anchor, start: start, pointer: landing.pointer, in: space),
                          CGPoint(x: 352, y: 262)))
        #expect(landing.lineX == 352)
        #expect(landing.lineY == nil)
    }

    /// The grid is the canvas's, and it stays upright when the shape is turned:
    /// snapping in the shape's own space would land the point on a grid turned
    /// with the drawing, off every line on screen.
    @Test func aPointOfATurnedShapeLandsOnTheUprightGrid() {
        let space = PathEditSpace(layer: Self.layer(turned: .pi / 7))
        let anchor = CGPoint(x: 100, y: 100)
        let press = space.document(anchor)
        let start = space.local(press)
        let pointer = CGPoint(x: press.x + 47, y: press.y - 23)
        let landing = space.gridLanding(pointer: pointer, dragging: anchor,
                                        pressedAt: start, on: Self.grid)
        let on = Self.landed(anchor, start: start, pointer: landing.pointer, in: space)
        let expected = Self.grid.crossing(nearest: CGPoint(x: press.x + 47, y: press.y - 23))
        #expect(Self.near(on, expected, 1e-6))
        let steps = CGPoint(x: on.x / 32, y: on.y / 32)
        #expect(Self.near(steps, CGPoint(x: steps.x.rounded(), y: steps.y.rounded())))
    }

    /// Two points picked: the one under the hand lands on the grid and the
    /// other keeps its offset, because both take the same travel.
    @Test func theOtherPickedPointsKeepTheirOffset() {
        let layer = Self.layer()
        let space = PathEditSpace(layer: layer)
        var content = Self.square()
        let anchor = CGPoint(x: 100, y: 100)
        let start = space.local(CGPoint(x: 300, y: 220))
        let landing = space.gridLanding(pointer: CGPoint(x: 341, y: 262), dragging: anchor,
                                        pressedAt: start, on: Self.grid)
        content.moveAnchors([2, 3], by: CGPoint(x: landing.pointer.x - start.x,
                                                y: landing.pointer.y - start.y))
        #expect(Self.near(space.document(content.anchors[2].point), CGPoint(x: 352, y: 256)))
        #expect(Self.near(space.document(content.anchors[3].point), CGPoint(x: 252, y: 256)))
    }
}
