import CoreGraphics
import Testing
@testable import PhotonzCore

struct CornerPlacementTests {

    private let bounds = CGSize(width: 400, height: 300)
    private let panel = CGSize(width: 120, height: 80)

    @Test func anEmptySurfaceKeepsThePreferredCorner() {
        #expect(CornerPlacement.firstClear(size: panel, in: bounds, inset: 10,
                                           avoiding: []) == .topLeading)
    }

    @Test func aPanelStepsAsideWhenSomethingIsUnderIt() {
        let measurement = CGRect(x: 0, y: 0, width: 200, height: 120)
        #expect(CornerPlacement.firstClear(size: panel, in: bounds, inset: 10,
                                           avoiding: [measurement]) == .topTrailing)
    }

    @Test func aPanelKeepsWalkingUntilItFindsRoom() {
        let across = CGRect(x: 0, y: 0, width: 400, height: 120)
        #expect(CornerPlacement.firstClear(size: panel, in: bounds, inset: 10,
                                           avoiding: [across]) == .bottomLeading)
    }

    @Test func aFullSurfaceStaysWhereTheUserLastSawIt() {
        let everywhere = CGRect(x: 0, y: 0, width: 400, height: 300)
        #expect(CornerPlacement.firstClear(size: panel, in: bounds, inset: 10,
                                           avoiding: [everywhere]) == .topLeading)
    }

    @Test func cornersSitInsetFromTheirEdges() {
        let r = CornerPlacement.frame(for: .bottomTrailing, size: panel, in: bounds, inset: 10)
        #expect(r.maxX == 390)
        #expect(r.maxY == 290)
    }
}
