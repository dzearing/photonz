import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The pull and the picture have to agree: whatever a drag lands on has to be
/// a line a person can actually see at the zoom they are at.
@Suite("The grid a drag pulls to is the grid on screen")
struct GridVisibleSnapTests {

    let zooms: [CGFloat] = [0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 8, 16, 32]
    let spacings: [CGFloat] = [1, 2, 4, 5, 8, 10, 16, 64, 100]

    func settings(_ spacing: CGFloat, majorEvery: Int = 8,
                  minimumCell: CGFloat = CanvasGridSettings.noMinimumCell) -> CanvasGridSettings {
        CanvasGridSettings(isVisible: true, spacing: spacing,
                           majorEvery: majorEvery, minimumCell: minimumCell)
    }

    func drawnSpacings(_ settings: CanvasGridSettings, zoom: CGFloat) -> [CGFloat] {
        CanvasGridLevels.levels(spacing: settings.drawnSpacing,
                                majorEvery: settings.majorEvery,
                                zoom: zoom).map(\.spacing)
    }

    // MARK: The one rule

    /// The acceptance item, spelled out: the spacing a drag pulls to is one of
    /// the spacings being DRAWN, at every zoom and every setting.
    @Test func thePullIsAlwaysOneOfTheSpacingsBeingDrawn() {
        for zoom in zooms {
            for spacing in spacings {
                for majorEvery in [2, 4, 8, 10] {
                    let g = settings(spacing, majorEvery: majorEvery)
                    guard let step = g.snapSpacing(atZoom: zoom) else { continue }
                    let drawn = drawnSpacings(g, zoom: zoom)
                    #expect(drawn.contains { abs($0 - step) < 1e-9 },
                            "zoom \(zoom) spacing \(spacing) every \(majorEvery): pulls to \(step), draws \(drawn)")
                }
            }
        }
    }

    /// And it is a line you can AIM at, not one fading in at the bottom of the
    /// ladder: at least the halfway point of the fade, in screen points.
    @Test func thePullIsNeverToLinesTooCloseTogetherToAimAt() {
        for zoom in zooms {
            for spacing in spacings {
                let g = settings(spacing)
                guard let step = g.snapSpacing(atZoom: zoom) else { continue }
                #expect(step * zoom >= CanvasGridLevels.minimumSnapOnScreenSpacing - 1e-9,
                        "zoom \(zoom) spacing \(spacing): \(step) points is \(step * zoom) on screen")
            }
        }
    }

    // MARK: What that means at the zoom you are actually at

    /// The user's report, as a test. A four point grid at 100% draws its 32
    /// point lines and nothing finer, so a drag lands on 32s.
    @Test func aFourPointGridAtOneHundredPercentPullsToTheThirtyTwosItDraws() {
        #expect(settings(4).snapSpacing(atZoom: 1) == 32)
    }

    @Test func zoomingInMakesThePullFiner() {
        let g = settings(4)
        #expect(g.snapSpacing(atZoom: 4) == 4)
        #expect(g.snapSpacing(atZoom: 8) == 4)
    }

    @Test func zoomingOutMakesThePullCoarser() {
        let g = settings(4)
        #expect(g.snapSpacing(atZoom: 0.5) == 32)
        #expect(g.snapSpacing(atZoom: 0.25) == 256)
    }

    /// Never the other way round: coming closer can only ever make the pull
    /// finer, so the feel changes in one direction as you zoom.
    @Test func thePullOnlyEverGetsFinerAsYouComeCloser() {
        for spacing in spacings {
            let g = settings(spacing)
            var previous = CGFloat.infinity
            for zoom in zooms {
                guard let step = g.snapSpacing(atZoom: zoom) else { continue }
                #expect(step <= previous + 1e-9,
                        "spacing \(spacing): pull went from \(previous) to \(step) at zoom \(zoom)")
                previous = step
            }
        }
    }

    // MARK: The settings that switch it off

    @Test func aHiddenGridPullsAtNothing() {
        #expect(CanvasGridSettings(isVisible: false, spacing: 4).snapSpacing(atZoom: 1) == nil)
    }

    @Test func theSwitchOffStopsThePullWithoutHidingTheGrid() {
        var g = settings(4)
        g.snapsToGrid = false
        #expect(g.isVisible)
        #expect(g.snapSpacing(atZoom: 1) == nil)
    }

    @Test func aZoomThatIsNotANumberPullsAtNothing() {
        #expect(settings(4).snapSpacing(atZoom: 0) == nil)
        #expect(settings(4).snapSpacing(atZoom: -2) == nil)
        #expect(settings(4).snapSpacing(atZoom: .nan) == nil)
    }

    /// A smallest cell raises what is drawn, so it raises the pull with it:
    /// nothing finer than the cell asked for can be landed on.
    @Test func aSmallestCellRaisesThePullTheSameWayItRaisesTheDrawing() {
        let g = settings(4, minimumCell: 16)
        for zoom in zooms {
            guard let step = g.snapSpacing(atZoom: zoom) else { continue }
            #expect(step >= 16, "zoom \(zoom): pulled to \(step) under a 16 point smallest cell")
        }
        #expect(g.snapSpacing(atZoom: 4) == 16)
    }

    // MARK: The edge really does land on a drawn line

    /// Not just the same spacing: the same LINES. The grid starts where it is
    /// told to start, and a snapped edge has to land on one of the lines the
    /// canvas draws from that same zero point.
    @Test func aSnappedEdgeLandsOnALineTheCanvasDraws() {
        for zoom in [CGFloat(0.5), 1, 2, 4] {
            for origin in [CGFloat(0), 24, -13.5] {
                var g = settings(4)
                g.origin = CGPoint(x: origin, y: origin)
                guard let step = g.snapSpacing(atZoom: zoom) else { continue }
                let out = Snapping.snapResizedFrame(CGRect(x: 200, y: 300, width: 137.31, height: 100),
                                                    handle: .right,
                                                    canvas: CGSize(width: 4000, height: 3000),
                                                    gridSpacing: step, gridOrigin: g.origin,
                                                    zoom: zoom)
                let drawn = CanvasGridLevels.lines(spacing: step, from: out.frame.maxX - step,
                                                   to: out.frame.maxX + step, origin: origin)
                #expect(drawn.contains { abs($0 - out.frame.maxX) < 1e-6 },
                        "zoom \(zoom) origin \(origin): edge at \(out.frame.maxX), lines \(drawn)")
            }
        }
    }
}

/// Which line caught the edge, so the canvas can light that one up.
@Suite("A grid snap says which line it landed on")
struct GridSnapHighlightTests {
    let canvas = CGSize(width: 1000, height: 800)
    let size = CGSize(width: 100, height: 40)
    /// A layer to line up with, far from the drags below unless one aims at it.
    let peer = CGRect(x: 600, y: 400, width: 120, height: 60)

    @Test func aMovedLayerReportsTheGridLineItsLeadingEdgeLandedOn() {
        let out = Snapping.snapFrameOrigin(CGPoint(x: 213, y: 307), size: size, canvas: canvas,
                                           gridSpacing: 32, zoom: 1)
        #expect(out.origin == CGPoint(x: 224, y: 320))
        #expect(out.gridX == 224)
        #expect(out.gridY == 320)
        // It is the grid, not an alignment: no yellow rule for this.
        #expect(out.guideX == nil)
        #expect(out.guideY == nil)
    }

    @Test func aGridThatIsNotPullingReportsNoLine() {
        let out = Snapping.snapFrameOrigin(CGPoint(x: 213, y: 307), size: size, canvas: canvas,
                                           gridSpacing: nil, zoom: 1)
        #expect(out.gridX == nil)
        #expect(out.gridY == nil)
    }

    /// A real edge beats the grid, and then it is the real edge that is showing
    /// — the grid line must not be lit up underneath it as well.
    @Test func aLayerEdgeBeatsTheGridAndTheGridLineGoesOut() {
        let out = Snapping.snapFrameOrigin(CGPoint(x: 598, y: 307), size: size, canvas: canvas,
                                           peers: [peer], gridSpacing: 32, zoom: 1)
        #expect(out.origin.x == 600)
        #expect(out.guideX == 600)
        #expect(out.gridX == nil)
        // The other axis still has nothing but the grid, and says so.
        #expect(out.gridY == 320)
    }

    @Test func aResizedEdgeReportsTheGridLineItLandedOn() {
        let out = Snapping.snapResizedFrame(CGRect(x: 100, y: 100, width: 137, height: 90),
                                            handle: .right, canvas: canvas,
                                            gridSpacing: 32, zoom: 1)
        #expect(out.frame.maxX == 224)
        #expect(out.gridX == 224)
        #expect(out.guideX == nil)
    }

    /// A side handle touches one axis. The axis the pointer never held must not
    /// light a line up either.
    @Test func aSideHandleLightsNoLineOnTheAxisItNeverTouched() {
        let out = Snapping.snapResizedFrame(CGRect(x: 100, y: 101.7, width: 137, height: 90),
                                            handle: .right, canvas: canvas,
                                            gridSpacing: 32, zoom: 1)
        #expect(out.gridY == nil)
    }
}

/// A grid set to columns draws nothing across the canvas, so there is no line
/// down there to land on.
@Suite("A columns-only grid pulls sideways and nowhere else")
struct GridColumnsOnlySnapTests {
    let canvas = CGSize(width: 1000, height: 800)

    @Test func aMoveIsPulledSidewaysOnlyWhenThereAreNoRows() {
        let out = Snapping.snapFrameOrigin(CGPoint(x: 213, y: 307), size: CGSize(width: 100, height: 40),
                                           canvas: canvas, gridSpacing: 32,
                                           gridAxes: .columns, zoom: 1)
        #expect(out.origin == CGPoint(x: 224, y: 307))
        #expect(out.gridX == 224)
        #expect(out.gridY == nil)
    }

    @Test func aBottomEdgeIsNotPulledWhenThereAreNoRows() {
        let out = Snapping.snapResizedFrame(CGRect(x: 100, y: 100, width: 137, height: 93),
                                            handle: .bottom, canvas: canvas,
                                            gridSpacing: 32, gridAxes: .columns, zoom: 1)
        #expect(out.frame.maxY == 193)
        #expect(out.gridY == nil)
    }

    @Test func aRightEdgeIsStillPulledWhenThereAreNoRows() {
        let out = Snapping.snapResizedFrame(CGRect(x: 100, y: 100, width: 137, height: 93),
                                            handle: .right, canvas: canvas,
                                            gridSpacing: 32, gridAxes: .columns, zoom: 1)
        #expect(out.frame.maxX == 224)
        #expect(out.gridX == 224)
    }

    @Test func graphPaperStillPullsBothWays() {
        let out = Snapping.snapFrameOrigin(CGPoint(x: 213, y: 307), size: CGSize(width: 100, height: 40),
                                           canvas: canvas, gridSpacing: 32,
                                           gridAxes: .columnsAndRows, zoom: 1)
        #expect(out.origin == CGPoint(x: 224, y: 320))
    }
}

/// The pull is now as coarse as the lines on screen, so the halfway mark
/// between two lines is a cliff: a hand wobbling either side of it would throw
/// the whole box a cell back and forth. A lit line holds a little past halfway.
@Suite("A lit grid line holds through a wobble")
struct GridSnapHoldTests {
    let canvas = CGSize(width: 2000, height: 1600)
    let size = CGSize(width: 100, height: 40)

    func move(_ x: CGFloat, holding held: SnapHold = .none) -> Snapping.Result {
        Snapping.snapFrameOrigin(CGPoint(x: x, y: 700), size: size, canvas: canvas,
                                 gridSpacing: 32, zoom: 1, holding: held)
    }

    @Test func withNothingHeldTheNearestLineWins() {
        #expect(move(215).gridX == 224)
        #expect(move(207).gridX == 192)
    }

    /// Just past halfway (208 between 192 and 224), and the line already lit
    /// keeps the box: four screen points of room for a shaking hand.
    @Test func aLineJustPassedKeepsTheBoxUntilThePointerIsClearOfIt() {
        #expect(move(209, holding: SnapHold(x: 192)).gridX == 192)
        #expect(move(212, holding: SnapHold(x: 192)).gridX == 192)
    }

    /// But only a little past: keep walking and the next line takes it.
    @Test func walkingOnHandsTheBoxToTheNextLine() {
        #expect(move(213, holding: SnapHold(x: 192)).gridX == 224)
        #expect(move(230, holding: SnapHold(x: 192)).gridX == 224)
    }

    /// The room is a hand's, not a cell's, so however coarse the grid is the
    /// box never trails the pointer by more than half a cell plus a wobble.
    @Test func theBoxNeverTrailsThePointerByMoreThanHalfACellAndAWobble() {
        for spacing in [CGFloat(16), 32, 256] {
            for zoom in [CGFloat(0.25), 1, 4] {
                let slack = min(8 / zoom * SnapHold.gridReleaseSlack, spacing / 2)
                let limit = spacing / 2 + slack + 1e-6
                for step in 0...40 {
                    let x = 512 + CGFloat(step) * spacing / 8
                    let out = Snapping.snapFrameOrigin(CGPoint(x: x, y: 700), size: size,
                                                       canvas: canvas, gridSpacing: spacing,
                                                       zoom: zoom, holding: SnapHold(x: 512))
                    guard let landed = out.gridX else { continue }
                    #expect(abs(landed - x) <= limit,
                            "spacing \(spacing) zoom \(zoom): pointer \(x), box \(landed)")
                }
            }
        }
    }

    /// One slow pass across a line with a shaking hand: caught once, let go
    /// once, and never handed back to a line it had already left.
    @Test func aWobblingPassCrossesOnceAndOnlyOnce() {
        let shake: [CGFloat] = [0, 1.4, -1, 0.6, -0.4, 1.2, -1.2, 0.3]
        var held = SnapHold()
        var lines: [CGFloat] = []
        for step in 0...60 {
            let x = 190 + CGFloat(step) * 0.7 + shake[step % shake.count]
            let out = move(x, holding: held)
            held.caught(x: out.gridX, y: out.gridY)
            if lines.last != out.gridX { lines.append(out.gridX ?? .nan) }
        }
        #expect(lines == [192, 224], "the lit line went \(lines)")
    }

    /// A line the drag is NOT standing on has no say, so nothing sticks to a
    /// line it has never been on.
    @Test func aLineTheDragWasNeverOnDoesNotHoldIt() {
        #expect(move(215, holding: SnapHold(x: 100)).gridX == 224)
    }

    /// ⌘ has already dropped the magnets by the time this is asked, and a freed
    /// hold carries no line at all.
    @Test func aFreedHoldCarriesNothing() {
        var held = SnapHold(x: 192)
        held.free()
        #expect(held.x == nil)
    }
}
