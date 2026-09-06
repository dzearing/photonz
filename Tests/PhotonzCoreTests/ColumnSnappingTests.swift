import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Dragging on a screen that is showing its columns.
///
/// The promise the user was given when they chose this over a draw-only
/// overlay: a column edge catches a drag exactly the way another layer's edge
/// does, and NOTHING else pulls any differently than it did before. A
/// screenshot, a plain canvas and a screen with its columns switched off must
/// each drag byte for byte as they did, so a redline never has a new magnet in
/// it.
@Suite("Columns pull a drag")
struct ColumnSnappingTests {

    /// A 1000 wide screen at the canvas origin with five 176 wide columns:
    /// margin 20, gutter 20, so the edges are 20/196, 216/392, 412/588,
    /// 608/784, 804/980, and the middles are 108, 304, 500, 696 and 892.
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private var bands: [CGRect] {
        FrameColumns(count: 5, gutter: 20, margin: 20).bands(in: screen)
    }
    private let canvas = CGSize(width: 2000, height: 1200)

    private func move(_ origin: CGPoint, size: CGSize = CGSize(width: 100, height: 50),
                      columns: [CGRect]) -> Snapping.Result {
        Snapping.snapFrameOrigin(origin, size: size, canvas: canvas,
                                 peers: [], columnBands: columns, zoom: 1)
    }

    // MARK: Catching

    @Test("A box dropped near a column's left edge lands exactly on it")
    func leadingEdgeCatches() {
        let result = move(CGPoint(x: 219, y: 400), columns: bands)
        #expect(result.origin.x == 216)
        #expect(result.guideX == 216)
    }

    @Test("A box dropped near a column's right edge sits flush against it")
    func trailingEdgeCatches() {
        // The box's RIGHT edge reaches for 392, the right edge of column two.
        let result = move(CGPoint(x: 289, y: 400), columns: bands)
        #expect(result.origin.x == 292)
        #expect(result.origin.x + 100 == 392)
        #expect(result.guideX == 392)
    }

    @Test("A box can centre itself in a column")
    func centreCatches() {
        // Column three runs 412 to 588, so its middle is 500 and a 100 wide
        // box centred on it starts at 450.
        let result = move(CGPoint(x: 453, y: 400), columns: bands)
        #expect(result.origin.x == 450)
        #expect(result.guideX == 500)
    }

    @Test("The line that appears reaches down the screen the column is on")
    func theGuideIsAsShortAsTheColumn() {
        let result = move(CGPoint(x: 219, y: 400), columns: bands)
        let span = try? #require(result.guideXSpan)
        // From the top of the screen to the bottom of it, taking in the
        // dragged box: a short line beside the thing it caught, not a rule
        // down the whole picture.
        #expect(span?.start == 0)
        #expect(span?.end == 800)
    }

    @Test("Halfway between two ways of landing, nothing pulls")
    func outOfReachDoesNothing() {
        // 235 is nineteen points from the nearest thing this box could line up
        // with either side of it — column two's left edge one way, its middle
        // the other — which is well outside the reach of any magnet here.
        let result = move(CGPoint(x: 235, y: 400), columns: bands)
        #expect(result.origin == CGPoint(x: 235, y: 400))
        #expect(result.guideX == nil)
    }

    // MARK: Nothing else changes

    @Test("A column never pulls the other way: the top and bottom are untouched")
    func columnsOnlyPullSideways() {
        // 403 is three points below the screen's top edge, well inside the
        // reach a magnet would have. A column is a sideways idea, so nothing
        // happens down the other axis.
        let result = move(CGPoint(x: 700, y: 403), columns: bands)
        #expect(result.origin.y == 403)
        #expect(result.guideY == nil)
    }

    @Test("With no columns showing, a drag is exactly what it always was")
    func noColumnsIsNoChange() {
        let withColumns = move(CGPoint(x: 235, y: 403), columns: [])
        let asItAlwaysWas = Snapping.snapFrameOrigin(CGPoint(x: 235, y: 403),
                                                     size: CGSize(width: 100, height: 50),
                                                     canvas: canvas, peers: [], zoom: 1)
        #expect(withColumns == asItAlwaysWas)
        #expect(withColumns.origin == CGPoint(x: 235, y: 403))
    }

    @Test("A screenshot with annotations on it drags as it always did")
    func aRedlineIsUntouched() {
        // Two annotations on a capture, no screens anywhere: the peers are the
        // only thing pulling, and the answer is the same with the column list
        // in the call as without it.
        let peers = [CGRect(x: 100, y: 100, width: 80, height: 40),
                     CGRect(x: 400, y: 300, width: 120, height: 60)]
        for x in stride(from: 90.0, through: 130.0, by: 1.0) {
            let before = Snapping.snapFrameOrigin(CGPoint(x: x, y: 250), size: CGSize(width: 60, height: 30),
                                                  canvas: canvas, peers: peers, zoom: 1)
            let after = Snapping.snapFrameOrigin(CGPoint(x: x, y: 250), size: CGSize(width: 60, height: 30),
                                                 canvas: canvas, peers: peers, columnBands: [], zoom: 1)
            #expect(before == after)
        }
    }

    @Test("A real edge beats a column edge when both are in reach")
    func aRealEdgeWins() {
        // A button already sitting at 218, two points off the column edge at
        // 216. Lining up with the button is what the person is doing.
        let peers = [CGRect(x: 218, y: 100, width: 100, height: 40)]
        let result = Snapping.snapFrameOrigin(CGPoint(x: 217.5, y: 400),
                                              size: CGSize(width: 100, height: 50),
                                              canvas: canvas, peers: peers,
                                              columnBands: bands, zoom: 1)
        #expect(result.origin.x == 218)
        #expect(result.guideX == 218)
    }

    // MARK: Resizing

    @Test("Dragging a box's right edge stretches it to the column edge")
    func resizeCatchesAColumn() {
        let result = Snapping.snapResizedFrame(CGRect(x: 20, y: 100, width: 369, height: 50),
                                               handle: .right, canvas: canvas,
                                               peers: [], columnBands: bands, zoom: 1)
        // 20 + 369 = 389, three points short of column two's right edge.
        #expect(result.frame.maxX == 392)
        #expect(result.guideX == 392)
        // ...and its height is exactly what it was.
        #expect(result.frame.minY == 100)
        #expect(result.frame.height == 50)
    }

    @Test("Dragging a box's bottom edge never catches a column")
    func resizeIgnoresColumnsDownTheOtherAxis() {
        let proposed = CGRect(x: 500, y: 100, width: 100, height: 697)
        let result = Snapping.snapResizedFrame(proposed, handle: .bottom, canvas: canvas,
                                               peers: [], columnBands: bands, zoom: 1)
        #expect(result.frame == proposed)
        #expect(result.guideY == nil)
    }

    // MARK: Holding on

    @Test("A caught column edge holds through a wobble, like every other line")
    func aColumnEdgeHolds() {
        // Caught at 216, then the hand drifts nine points: past the eight point
        // reach a fresh catch would need, but a line you can see is a line you
        // keep until you clearly leave it.
        let result = Snapping.snapFrameOrigin(CGPoint(x: 225, y: 400),
                                              size: CGSize(width: 100, height: 50),
                                              canvas: canvas, peers: [], columnBands: bands,
                                              zoom: 1, holding: SnapHold(x: 216, y: nil))
        #expect(result.origin.x == 216)
        #expect(result.guideX == 216)
    }
}
