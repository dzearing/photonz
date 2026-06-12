import CoreGraphics
import PhotonzCore
import Testing

@Suite("Resize handles")
struct HandlesTests {
    let frame = CGRect(x: 100, y: 100, width: 200, height: 100)

    // MARK: Placement

    @Test func handlePointsSitOnCornersAndEdgeMidpoints() {
        #expect(Handles.point(for: .topLeft, in: frame) == CGPoint(x: 100, y: 100))
        #expect(Handles.point(for: .bottomRight, in: frame) == CGPoint(x: 300, y: 200))
        #expect(Handles.point(for: .top, in: frame) == CGPoint(x: 200, y: 100))
        #expect(Handles.point(for: .left, in: frame) == CGPoint(x: 100, y: 150))
    }

    // MARK: Hit-testing (tolerance in screen points)

    @Test func nearbyPointHitsTheHandle() {
        let hit = Handles.hit(at: CGPoint(x: 302, y: 198), frame: frame, zoom: 1)
        #expect(hit == .bottomRight)
    }

    @Test func farPointHitsNothing() {
        #expect(Handles.hit(at: CGPoint(x: 200, y: 150), frame: frame, zoom: 1) == nil)
    }

    @Test func toleranceShrinksInDocSpaceWhenZoomedIn() {
        // 4 doc points off the corner: hits at 1× (4 screen pts) but not at 4× (16 screen pts).
        let p = CGPoint(x: 304, y: 200)
        #expect(Handles.hit(at: p, frame: frame, zoom: 1) == .bottomRight)
        #expect(Handles.hit(at: p, frame: frame, zoom: 4) == nil)
    }

    @Test func nearestHandleWinsBetweenCornerAndEdge() {
        // Halfway region: closer to the top edge midpoint than to either top corner.
        let hit = Handles.hit(at: CGPoint(x: 195, y: 99), frame: frame, zoom: 1)
        #expect(hit == .top)
    }

    // MARK: Corner resize

    @Test func cornerDragMovesTwoEdgesAndAnchorsTheOpposite() {
        let r = Handles.resize(frame, dragging: .bottomRight, to: CGPoint(x: 350, y: 260), preserveAspect: false)
        #expect(r == CGRect(x: 100, y: 100, width: 250, height: 160))
    }

    @Test func topLeftDragAnchorsBottomRight() {
        let r = Handles.resize(frame, dragging: .topLeft, to: CGPoint(x: 150, y: 80), preserveAspect: false)
        #expect(r == CGRect(x: 150, y: 80, width: 150, height: 120))
    }

    @Test func cornerWithAspectKeepsTheRatioUsingTheDominantAxis() {
        // 2:1 frame. Drag bottomRight to +100 wide, +10 tall → width dominates:
        // scale 1.5 → 300×150 anchored at (100,100).
        let r = Handles.resize(frame, dragging: .bottomRight, to: CGPoint(x: 400, y: 210), preserveAspect: true)
        #expect(r == CGRect(x: 100, y: 100, width: 300, height: 150))
    }

    @Test func topLeftWithAspectStaysAnchoredAtBottomRight() {
        // Scale down to 0.5 via the y axis (drag to y=150 → height 50 dominates… use
        // x dominant instead: to (200,190) → width 100 → scale 0.5 → 100×50,
        // anchored at maxX/maxY (300,200).
        let r = Handles.resize(frame, dragging: .topLeft, to: CGPoint(x: 200, y: 190), preserveAspect: true)
        #expect(r == CGRect(x: 200, y: 150, width: 100, height: 50))
    }

    // MARK: Edge resize

    @Test func edgeDragMovesOnlyItsAxis() {
        let r = Handles.resize(frame, dragging: .right, to: CGPoint(x: 380, y: 999), preserveAspect: false)
        #expect(r == CGRect(x: 100, y: 100, width: 280, height: 100))
    }

    @Test func topEdgeDragMovesTheTopOnly() {
        let r = Handles.resize(frame, dragging: .top, to: CGPoint(x: 0, y: 60), preserveAspect: false)
        #expect(r == CGRect(x: 100, y: 60, width: 200, height: 140))
    }

    @Test func edgeWithAspectScalesTheOtherAxisAroundItsCenter() {
        // Right edge to x=400 → width 300 (×1.5) → height 150 centered on y 150.
        let r = Handles.resize(frame, dragging: .right, to: CGPoint(x: 400, y: 0), preserveAspect: true)
        #expect(r == CGRect(x: 100, y: 75, width: 300, height: 150))
    }

    // MARK: Degenerate drags never invert

    @Test func draggingPastTheOppositeEdgeClampsToMinSize() {
        let r = Handles.resize(frame, dragging: .right, to: CGPoint(x: 50, y: 150), preserveAspect: false)
        #expect(r == CGRect(x: 100, y: 100, width: 1, height: 100))
    }

    @Test func cornerDraggedThroughTheAnchorClampsBothAxes() {
        let r = Handles.resize(frame, dragging: .bottomRight, to: CGPoint(x: 0, y: 0), preserveAspect: false)
        #expect(r == CGRect(x: 100, y: 100, width: 1, height: 1))
    }
}
