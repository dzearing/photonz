import CoreGraphics
import Testing
@testable import PhotonzCore

struct PanelPlacementTests {

    private let bounds = CGSize(width: 400, height: 300)
    private let panel = CGSize(width: 120, height: 80)

    @Test func anEmptySurfaceKeepsThePreferredCorner() {
        #expect(PanelPlacement.firstClear(size: panel, in: bounds, inset: 10,
                                          avoiding: []) == .topLeading)
    }

    @Test func aPanelStepsAsideWhenSomethingIsUnderIt() {
        let measurement = CGRect(x: 0, y: 0, width: 200, height: 120)
        #expect(PanelPlacement.firstClear(size: panel, in: bounds, inset: 10,
                                          avoiding: [measurement]) == .topTrailing)
    }

    @Test func aPanelKeepsWalkingUntilItFindsRoom() {
        let across = CGRect(x: 0, y: 0, width: 400, height: 120)
        #expect(PanelPlacement.firstClear(size: panel, in: bounds, inset: 10,
                                          avoiding: [across]) == .bottomLeading)
    }

    @Test func aFullSurfaceStaysWhereTheUserLastSawIt() {
        let everywhere = CGRect(x: 0, y: 0, width: 400, height: 300)
        #expect(PanelPlacement.firstClear(size: panel, in: bounds, inset: 10,
                                          avoiding: [everywhere]) == .topLeading)
    }

    @Test func cornersSitInsetFromTheirEdges() {
        let r = PanelPlacement.frame(for: .bottomTrailing, size: panel, in: bounds, inset: 10)
        #expect(r.maxX == 390)
        #expect(r.maxY == 290)
    }

    @Test func edgeSlotsSitHalfwayDownTheirEdge() {
        let left = PanelPlacement.frame(for: .leading, size: panel, in: bounds, inset: 10)
        #expect(left.minX == 10)
        #expect(left.midY == 150)
        let right = PanelPlacement.frame(for: .trailing, size: panel, in: bounds, inset: 10)
        #expect(right.maxX == 390)
        #expect(right.midY == 150)
    }

    @Test func cornersComeBeforeEdgeSlots() {
        // A corner is where a key conventionally lives, so the edge slots are
        // only ever a fallback: the preference order walks all four corners
        // first, then the leading edge, then the trailing edge.
        #expect(PanelAnchor.allCases == [.topLeading, .topTrailing,
                                         .bottomLeading, .bottomTrailing,
                                         .leading, .trailing])
    }

    @Test func whenEveryCornerIsTakenThePanelSlidesDownTheLeadingEdge() {
        // Both top corners under measurements, both bottom corners under
        // chrome: the panel steps down the left edge instead of sitting on a
        // measurement or behind the chrome.
        let topLeft = CGRect(x: 0, y: 0, width: 200, height: 100)
        let topRight = CGRect(x: 200, y: 0, width: 200, height: 100)
        let chrome = CGRect(x: 0, y: 220, width: 400, height: 80)
        let anchor = PanelPlacement.firstClear(size: panel, in: bounds, inset: 10,
                                               avoiding: [topLeft, topRight],
                                               blocked: [chrome])
        #expect(anchor == .leading)
        let frame = PanelPlacement.frame(for: anchor, size: panel, in: bounds, inset: 10)
        #expect(!frame.intersects(topLeft))
        #expect(!frame.intersects(topRight))
        #expect(!frame.intersects(chrome))
    }

    @Test func theTrailingEdgeIsTheLastResortBeforeCoveringAMeasurement() {
        let topLeft = CGRect(x: 0, y: 0, width: 200, height: 100)
        let topRight = CGRect(x: 200, y: 0, width: 200, height: 100)
        let leftEdge = CGRect(x: 0, y: 100, width: 150, height: 120)
        let chrome = CGRect(x: 0, y: 220, width: 400, height: 80)
        #expect(PanelPlacement.firstClear(size: panel, in: bounds, inset: 10,
                                          avoiding: [topLeft, topRight, leftEdge],
                                          blocked: [chrome]) == .trailing)
    }

    @Test func aBlockedCornerIsNeverTakenEvenWhenEveryCornerIsBusy() {
        // Measurements fill the top half and chrome runs along the bottom, so
        // every corner and both edge slots are busy. The legend would rather
        // sit over a measurement than disappear behind chrome, so it takes the
        // first corner that only a measurement is under.
        let topLeft = CGRect(x: 0, y: 0, width: 200, height: 150)
        let topRight = CGRect(x: 200, y: 0, width: 200, height: 150)
        let chrome = CGRect(x: 0, y: 220, width: 400, height: 80)
        #expect(PanelPlacement.firstClear(size: panel, in: bounds, inset: 10,
                                          avoiding: [topLeft, topRight],
                                          blocked: [chrome]) == .topLeading)
    }

    @Test func aBottomCornerBesideTheChromeIsStillFairGame() {
        // Chrome that stops short of the corner leaves it usable.
        let across = CGRect(x: 0, y: 0, width: 400, height: 120)
        let pill = CGRect(x: 140, y: 220, width: 120, height: 40)
        #expect(PanelPlacement.firstClear(size: panel, in: bounds, inset: 10,
                                          avoiding: [across],
                                          blocked: [pill]) == .bottomLeading)
    }

    @Test func theLegendOnANarrowCanvasCoversNoMeasurementAndNoChrome() {
        // The 2026-09-02 report: a 435 pt canvas (a 700 pt window with the
        // inspector open), three legend rows, Size, Spacing and Alignment
        // measurements filling both top corners. The legend used to fall back
        // to the top-left corner, on top of the Size caliper. This is the
        // exact call the editor makes.
        let legend = CGSize(width: 140, height: 79)
        let canvas = CGSize(width: 435, height: 500)
        let piles = [CGRect(x: 0, y: 0, width: 220, height: 150),
                     CGRect(x: 215, y: 0, width: 220, height: 150)]
        let chrome = EditorChromeLayout.bottomChrome(
            canvasSize: canvas, toolBarWidth: 0,
            noticeSize: MeasureModeHint.reservedSize)
        let anchor = PanelPlacement.firstClear(size: legend, in: canvas, inset: 10,
                                               avoiding: piles, blocked: chrome)
        #expect(anchor == .leading)
        let frame = PanelPlacement.frame(for: anchor, size: legend, in: canvas, inset: 10)
        for pile in piles { #expect(!frame.intersects(pile)) }
        for rect in chrome { #expect(!frame.intersects(rect)) }
    }

    @Test func theLegendNeverSitsUnderTheMeasureHintOnANarrowCanvas() {
        // Three legend rows, measurements piled into both top corners, and a
        // canvas from a 700 pt window's 435 pt up to 800 pt wide: whichever
        // slot the legend takes, it covers no measurement, and the mode hint's
        // pill and the tool bar never cross it. The hint's slot is reserved
        // whether or not a pill is up, so the answer cannot change while the
        // hint appears and fades.
        let legend = CGSize(width: 140, height: 79)
        for width in stride(from: 435, through: 800, by: 15) {
            let canvas = CGSize(width: CGFloat(width), height: 500)
            let piles = [CGRect(x: 0, y: 0, width: 300, height: 150),
                         CGRect(x: canvas.width - 300, y: 0, width: 300, height: 150)]
            let chrome = EditorChromeLayout.bottomChrome(
                canvasSize: canvas, toolBarWidth: 0,
                noticeSize: MeasureModeHint.reservedSize)
            let anchor = PanelPlacement.firstClear(size: legend, in: canvas, inset: 10,
                                                   avoiding: piles, blocked: chrome)
            let frame = PanelPlacement.frame(for: anchor, size: legend, in: canvas, inset: 10)
            let hint = EditorChromeLayout.bottomNoticeFrame(
                canvasSize: canvas, noticeSize: MeasureModeHint.reservedSize)
            #expect(!frame.intersects(hint), "legend crosses the hint at \(width) pt")
            for rect in chrome {
                #expect(!frame.intersects(rect), "legend crosses chrome at \(width) pt")
            }
            for pile in piles {
                #expect(!frame.intersects(pile), "legend covers a measurement at \(width) pt")
            }
        }
    }
}
