import CoreGraphics
import PhotonzCore
import Testing

/// The camera a freshly opened document lands on: the zoom the window was
/// sized for, unless the canvas it actually got is too short for it.
@Suite("Viewport opening")
struct ViewportOpeningTests {

    @Test func aPictureTheCanvasHoldsOpensAtItsPlannedZoom() {
        // 800×500 at 100% in a 1200×800 canvas with a 60pt tool bar: room to spare.
        let vp = Viewport.opening(documentSize: CGSize(width: 800, height: 500),
                                  in: CGSize(width: 1200, height: 800),
                                  plannedZoom: 1, obscuredBottom: 60)
        #expect(vp.zoom == 1)
        #expect(vp.documentFrameInView.maxY <= vp.clearHeight)
    }

    @Test func aRecordingUnderATimelineFitsAboveTheToolBarInstead() {
        // The guide sample: 1280×800 planned at 0.987 for a maxed window, but
        // the timeline under the canvas leaves it only 730pt.
        let vp = Viewport.opening(documentSize: CGSize(width: 1280, height: 800),
                                  in: CGSize(width: 1463, height: 730),
                                  plannedZoom: 0.987, obscuredBottom: 60)
        #expect(vp.zoom < 0.987)
        let frame = vp.documentFrameInView
        #expect(frame.minY >= 0)
        #expect(frame.maxY <= vp.clearHeight)
        #expect(vp == Viewport.fit(documentSize: CGSize(width: 1280, height: 800),
                                   in: CGSize(width: 1463, height: 730), obscuredBottom: 60))
    }

    @Test func aRetinaPictureKeepsItsHundredPercentRatherThanFittingUp() {
        // 2× pixels: 100% is zoom 0.5, and the fit (which may go to 1) never
        // pulls an opening zoom UP.
        let vp = Viewport.opening(documentSize: CGSize(width: 1000, height: 600),
                                  in: CGSize(width: 1400, height: 900),
                                  plannedZoom: 0.5, obscuredBottom: 60)
        #expect(vp.zoom == 0.5)
    }

    @Test func aPlannedZoomIsCentredInTheClearPartOfTheCanvas() {
        let vp = Viewport.opening(documentSize: CGSize(width: 400, height: 200),
                                  in: CGSize(width: 1000, height: 660),
                                  plannedZoom: 1, obscuredBottom: 60)
        #expect(vp.documentFrameInView == CGRect(x: 300, y: 200, width: 400, height: 200))
    }
}
