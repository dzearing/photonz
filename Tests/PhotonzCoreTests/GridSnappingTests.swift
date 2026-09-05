import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("Snapping a drag to the canvas grid")
struct GridSnapToGridSettingTests {

    @Test func snappingIsOnBeforeAnyoneAsks() {
        #expect(CanvasGridSettings().snapsToGrid)
    }

    @Test func settingsWrittenBeforeTheSwitchExistedComeBackSnapping() throws {
        let old = #"{"isVisible":true,"axes":"columnsAndRows","spacing":8,"majorEvery":8}"#
        let decoded = try JSONDecoder().decode(CanvasGridSettings.self,
                                               from: Data(old.utf8))
        #expect(decoded.snapsToGrid)
        #expect(decoded.spacing == 8)
    }

    @Test func theSwitchSurvivesASaveAndALoad() throws {
        var settings = CanvasGridSettings(isVisible: true)
        settings.snapsToGrid = false
        let round = try JSONDecoder().decode(CanvasGridSettings.self,
                                             from: JSONEncoder().encode(settings))
        #expect(round.snapsToGrid == false)
    }

    // MARK: What a drag actually pulls to

    @Test func aHiddenGridPullsAtNothing() {
        #expect(CanvasGridSettings(isVisible: false, spacing: 4).snapSpacing == nil)
    }

    @Test func theSwitchOffStopsThePullWithoutHidingTheGrid() {
        var settings = CanvasGridSettings(isVisible: true, spacing: 4)
        settings.snapsToGrid = false
        #expect(settings.isVisible)
        #expect(settings.snapSpacing == nil)
    }

    /// A grid set to four means things land on fours, and on the SAME fours
    /// however close you happen to be standing. A pull that got coarser as you
    /// zoomed out would make the same drag give different answers at different
    /// zooms, which is its own kind of jumping.
    @Test func theDragPullsToTheSpacingThatWasTypedIn() {
        #expect(CanvasGridSettings(isVisible: true, spacing: 4).snapSpacing == 4)
        #expect(CanvasGridSettings(isVisible: true, spacing: 16).snapSpacing == 16)
    }
}

@Suite("Moving a layer with the grid on")
struct GridMoveSnappingTests {
    let canvas = CGSize(width: 1000, height: 800)
    let size = CGSize(width: 100, height: 40)

    func move(_ x: CGFloat, _ y: CGFloat, peers: [CGRect] = [],
              grid: CGFloat? = 4, zoom: CGFloat = 1) -> Snapping.Result {
        Snapping.snapFrameOrigin(CGPoint(x: x, y: y), size: size, canvas: canvas,
                                 peers: peers, gridSpacing: grid, zoom: zoom)
    }

    @Test func theLeadingEdgeLandsOnALine() {
        #expect(move(303.2, 201.9).origin == CGPoint(x: 304, y: 200))
    }

    @Test func theGridDrawsNoGuideOfItsOwn() {
        // Every position on the axis lands on a line while the grid is pulling,
        // so a guide for it would be on for the whole drag and would say
        // nothing. The yellow lines are for the things you catch now and then.
        let result = move(303.2, 201.9)
        #expect(result.guideX == nil)
        #expect(result.guideY == nil)
    }

    /// A peer edge that is NOT on the grid is still reachable: the magnets win,
    /// and the grid only decides where a drag lands when nothing else caught it.
    @Test func anotherLayersEdgeBeatsTheGrid() {
        let peer = CGRect(x: 313, y: 100, width: 100, height: 40)
        let result = move(315, 500, peers: [peer])
        #expect(result.origin.x == 313)
        #expect(result.guideX == 313)
    }

    @Test func withNoGridTheMoveIsExactlyWhatItWasBefore() {
        #expect(move(303.2, 201.9, grid: nil).origin == CGPoint(x: 303.2, y: 201.9))
    }
}

@Suite("Resizing a layer by a handle")
struct ResizeSnappingTests {
    let canvas = CGSize(width: 1000, height: 800)
    /// A button already on the canvas, for the resized one to find.
    let peer = CGRect(x: 600, y: 100, width: 120, height: 60)

    func resize(_ frame: CGRect, _ handle: ResizeHandle, peers: [CGRect] = [],
                grid: CGFloat? = nil, zoom: CGFloat = 1) -> Snapping.FrameResult {
        Snapping.snapResizedFrame(frame, handle: handle, canvas: canvas,
                                  peers: peers, gridSpacing: grid, zoom: zoom)
    }

    // MARK: The grid

    @Test func theDraggedEdgeLandsOnALineAndTheOtherOneStaysPut() {
        let out = resize(CGRect(x: 203, y: 300, width: 122.4, height: 100), .right, grid: 4)
        #expect(out.frame.minX == 203)      // untouched
        #expect(out.frame.maxX == 324)      // 325.4 pulled onto the line
    }

    @Test func theLeftEdgeMovesAndTheRightOneStaysPut() {
        let out = resize(CGRect(x: 201.5, y: 300, width: 120, height: 100), .left, grid: 4)
        #expect(out.frame.minX == 200)
        #expect(out.frame.maxX == 321.5)
    }

    @Test func aCornerLandsOnALineOnBothAxes() {
        let out = resize(CGRect(x: 100, y: 100, width: 205.3, height: 154.4),
                         .bottomRight, grid: 4)
        #expect(out.frame.maxX == 304)
        #expect(out.frame.maxY == 256)
        #expect(out.frame.origin == CGPoint(x: 100, y: 100))
    }

    /// A side handle moves ONE edge. Nothing may quietly tidy up the axis the
    /// pointer never touched, or a stack of rows would resettle every time one
    /// of them was made wider.
    @Test func aSideHandleLeavesTheOtherAxisAloneEntirely() {
        let start = CGRect(x: 100, y: 101.7, width: 200, height: 98.3)
        let out = resize(start, .right, grid: 4)
        #expect(out.frame.minY == 101.7)
        #expect(out.frame.maxY == 200)
        #expect(out.guideY == nil)
    }

    /// The acceptance item, spelled out: whatever the zoom and whatever the
    /// spacing, the edge comes to rest ON a line rather than near one.
    @Test func anEdgeLandsOnALineAtEveryZoomAndEverySpacing() {
        for zoom in [CGFloat(0.25), 0.5, 1, 2, 4, 8] {
            for spacing in [CGFloat(1), 4, 10, 16, 64] {
                let settings = CanvasGridSettings(isVisible: true, spacing: spacing)
                guard let step = settings.snapSpacing else { continue }
                let start = CGRect(x: 200, y: 300, width: 137.31, height: 100)
                let out = resize(start, .right, grid: step, zoom: zoom)
                let offGrid = abs(out.frame.maxX.truncatingRemainder(dividingBy: step))
                #expect(min(offGrid, step - offGrid) < 1e-6,
                        "zoom \(zoom) spacing \(spacing): maxX \(out.frame.maxX) is not on a \(step) line")
                // And it STAYS there: snapping the answer again changes nothing.
                let again = resize(out.frame, .right, grid: step, zoom: zoom)
                #expect(again.frame == out.frame)
            }
        }
    }

    // MARK: The other layers, and the canvas

    @Test func aDraggedEdgeCatchesAnotherLayersEdge() {
        let out = resize(CGRect(x: 200, y: 110, width: 397, height: 40), .right, peers: [peer])
        #expect(out.frame.maxX == 600)
        #expect(out.guideX == 600)
    }

    @Test func aDraggedEdgeCatchesAnotherLayersFarEdge() {
        let out = resize(CGRect(x: 200, y: 110, width: 523, height: 40), .right, peers: [peer])
        #expect(out.frame.maxX == 720)
        #expect(out.guideX == 720)
    }

    @Test func aDraggedEdgeCatchesAnotherLayersMiddle() {
        let out = resize(CGRect(x: 200, y: 110, width: 458, height: 40), .right, peers: [peer])
        #expect(out.frame.maxX == 660)
        #expect(out.guideX == 660)
    }

    @Test func theGuideReachesAcrossBothBoxes() {
        let out = resize(CGRect(x: 200, y: 300, width: 397, height: 40), .right, peers: [peer])
        // The resized box sits at y 300...340, the peer at 100...160.
        #expect(out.guideXSpan == Snapping.Span(start: 100, end: 340))
    }

    @Test func aDraggedEdgeCatchesTheCanvasEdge() {
        let out = resize(CGRect(x: 200, y: 300, width: 797, height: 40), .right)
        #expect(out.frame.maxX == 1000)
        #expect(out.guideX == 1000)
        #expect(out.guideXSpan == nil)      // a canvas line runs the whole way
    }

    @Test func aDraggedEdgeCatchesTheCanvasMiddle() {
        let out = resize(CGRect(x: 100, y: 300, width: 397, height: 40), .right)
        #expect(out.frame.maxX == 500)
    }

    @Test func aPeerEdgeBeatsAGridLine() {
        // The peer's left edge is on 600, which IS a grid line here; move it off
        // one so the two answers differ and the peer has to be the one that wins.
        let odd = CGRect(x: 601, y: 100, width: 120, height: 60)
        let out = resize(CGRect(x: 200, y: 110, width: 399, height: 40), .right,
                         peers: [odd], grid: 4)
        #expect(out.frame.maxX == 601)
        #expect(out.guideX == 601)
    }

    @Test func farFromEverythingWithNoGridNothingMoves() {
        // Clear of the canvas edges and of its middle lines, x 500 and y 400.
        let start = CGRect(x: 203.4, y: 201.6, width: 122.3, height: 97.7)
        let out = resize(start, .bottomRight, peers: [peer])
        #expect(out.frame == start)
        #expect(out.guideX == nil)
        #expect(out.guideY == nil)
    }

    /// Tolerance is in SCREEN points, so the magnet feels the same size at any
    /// zoom: the same eight point reach is eighty document points at 0.1x.
    @Test func theMagnetIsTheSameSizeOnScreenAtEveryZoom() {
        let near = CGRect(x: 200, y: 110, width: 380, height: 40)   // maxX 580, 20 short
        #expect(resize(near, .right, peers: [peer], zoom: 1).frame.maxX == 580)
        #expect(resize(near, .right, peers: [peer], zoom: 0.25).frame.maxX == 600)
    }

    // MARK: Never make a nonsense rectangle

    @Test func aSnapMayNotTurnTheBoxInsideOut() {
        // A sliver two points wide beside a peer edge four points past its own
        // left edge: taking the peer would give it a negative width.
        let sliver = CGRect(x: 600, y: 110, width: 2, height: 40)
        let behind = CGRect(x: 560, y: 100, width: 38, height: 60)   // right edge 598
        let out = Snapping.snapResizedFrame(sliver, handle: .right, canvas: canvas,
                                            peers: [behind], gridSpacing: nil, zoom: 1)
        #expect(out.frame.width >= 1)
        #expect(out.frame.maxX == 602)
        #expect(out.guideX == nil)
    }

    @Test func aGridStepMayNotCollapseTheBox() {
        let sliver = CGRect(x: 600, y: 110, width: 1.2, height: 40)
        let out = resize(sliver, .right, grid: 64)
        #expect(out.frame.width >= 1)
    }
}
