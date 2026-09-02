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

    @Test func aBlockedCornerIsNeverTakenEvenWhenEveryCornerIsBusy() {
        // Measurements fill both top corners and chrome (the tool bar, the
        // hint pill) runs along the bottom. The legend would rather sit over
        // a measurement than disappear behind chrome, so it takes the first
        // corner that only a measurement is under.
        let topLeft = CGRect(x: 0, y: 0, width: 200, height: 120)
        let topRight = CGRect(x: 200, y: 0, width: 200, height: 120)
        let chrome = CGRect(x: 0, y: 220, width: 400, height: 80)
        #expect(CornerPlacement.firstClear(size: panel, in: bounds, inset: 10,
                                           avoiding: [topLeft, topRight],
                                           blocked: [chrome]) == .topLeading)
    }

    @Test func aBottomCornerBesideTheChromeIsStillFairGame() {
        // Chrome that stops short of the corner leaves it usable.
        let across = CGRect(x: 0, y: 0, width: 400, height: 120)
        let pill = CGRect(x: 140, y: 220, width: 120, height: 40)
        #expect(CornerPlacement.firstClear(size: panel, in: bounds, inset: 10,
                                           avoiding: [across],
                                           blocked: [pill]) == .bottomLeading)
    }

    @Test func theLegendNeverSitsUnderTheMeasureHintOnANarrowCanvas() {
        // Three legend rows, measurements piled into both top corners, and a
        // canvas from the window floor up to 800 pt wide: whichever corner the
        // legend takes, the mode hint's pill and the tool bar never cross it.
        // This is the exact call the editor makes.
        let legend = CGSize(width: 140, height: 79)
        for width in stride(from: 480, through: 800, by: 20) {
            let canvas = CGSize(width: CGFloat(width), height: 500)
            let piles = [CGRect(x: 0, y: 0, width: 300, height: 150),
                         CGRect(x: canvas.width - 300, y: 0, width: 300, height: 150)]
            let chrome = EditorChromeLayout.bottomChrome(
                canvasSize: canvas, toolBarWidth: 0,
                noticeSize: MeasureModeHint.reservedSize)
            let corner = CornerPlacement.firstClear(size: legend, in: canvas, inset: 10,
                                                    avoiding: piles, blocked: chrome)
            let frame = CornerPlacement.frame(for: corner, size: legend, in: canvas, inset: 10)
            let hint = EditorChromeLayout.bottomNoticeFrame(
                canvasSize: canvas, noticeSize: MeasureModeHint.reservedSize)
            #expect(!frame.intersects(hint), "legend crosses the hint at \(width) pt")
            for rect in chrome {
                #expect(!frame.intersects(rect), "legend crosses chrome at \(width) pt")
            }
        }
    }
}
