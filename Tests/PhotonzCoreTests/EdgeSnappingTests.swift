import CoreGraphics
import Foundation
import PhotonzCore
import Testing

private func map(vertical: [Double] = [], horizontal: [Double] = [],
                width: Int = 200, height: Int = 200) -> EdgeMap {
    EdgeMap(width: width, height: height,
            verticalEdges: vertical.map { EdgeCandidate(position: $0, strength: 1) },
            horizontalEdges: horizontal.map { EdgeCandidate(position: $0, strength: 1) })
}

@Suite("Edge snapping")
struct EdgeSnappingTests {

    @Test func snapsToNearestEdgeWithinTolerance() {
        let edges = map(vertical: [100])
        // Pointer 4px from the edge, tolerance 6 — captures.
        let snap = EdgeSnapping.snap(CGPoint(x: 104, y: 50), edges: edges, zoom: 1,
                                     screenTolerance: 6, snapToPixelGrid: false)
        #expect(snap.point.x == 100)
        #expect(snap.guideX == 100)
    }

    @Test func doesNotSnapBeyondTolerance() {
        let edges = map(vertical: [100])
        // 10px away with tolerance 6 — no edge capture; grid off → unchanged.
        let snap = EdgeSnapping.snap(CGPoint(x: 110, y: 50), edges: edges, zoom: 1,
                                     screenTolerance: 6, snapToPixelGrid: false)
        #expect(snap.point.x == 110)
        #expect(snap.guideX == nil)
    }

    @Test func picksTheNearerOfTwoEdges() {
        let edges = map(vertical: [100, 108])
        let snap = EdgeSnapping.snap(CGPoint(x: 106, y: 0), edges: edges, zoom: 1,
                                     screenTolerance: 6, snapToPixelGrid: false)
        #expect(snap.point.x == 108) // 106 is 2px from 108, 6px from 100
    }

    @Test func snapsToPixelGridWhenNoEdgeCaptures() {
        let edges = map() // no edges
        let snap = EdgeSnapping.snap(CGPoint(x: 42.7, y: 9.2), edges: edges, zoom: 1)
        #expect(snap.point == CGPoint(x: 43, y: 9))
        #expect(snap.guideX == nil)
        #expect(snap.guideY == nil)
    }

    @Test func toleranceScalesWithZoom() {
        let edges = map(vertical: [100])
        // 4px away. At zoom 1 tolerance=6px → snaps. At zoom 2 tolerance=3px → no snap.
        let zoomedIn = EdgeSnapping.snap(CGPoint(x: 104, y: 0), edges: edges, zoom: 2,
                                         screenTolerance: 6, snapToPixelGrid: false)
        #expect(zoomedIn.point.x == 104)
        let zoomedOut = EdgeSnapping.snap(CGPoint(x: 104, y: 0), edges: edges, zoom: 1,
                                          screenTolerance: 6, snapToPixelGrid: false)
        #expect(zoomedOut.point.x == 100)
    }

    @Test func axesSnapIndependently() {
        // x captures a vertical edge; y has no edge nearby and rounds to grid.
        let edges = map(vertical: [80])
        let snap = EdgeSnapping.snap(CGPoint(x: 83, y: 150.6), edges: edges, zoom: 1,
                                     screenTolerance: 6)
        #expect(snap.point.x == 80)
        #expect(snap.guideX == 80)
        #expect(snap.point.y == 151)
        #expect(snap.guideY == nil)
    }
}
