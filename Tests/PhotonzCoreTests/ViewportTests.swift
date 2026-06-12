import CoreGraphics
import PhotonzCore
import Testing

@Suite("Viewport")
struct ViewportTests {

    // MARK: Fitting (⌘0)

    @Test func fitCentersASmallerDocumentAtOneHundredPercent() {
        // A 200×100 document in a 1000×800 view fits at 1× (fit never upscales)
        // and sits centered.
        let vp = Viewport.fit(documentSize: CGSize(width: 200, height: 100),
                              in: CGSize(width: 1000, height: 800),
                              padding: 0)
        #expect(vp.zoom == 1)
        #expect(vp.documentFrameInView == CGRect(x: 400, y: 350, width: 200, height: 100))
    }

    @Test func fitScalesALargerDocumentDownToFitWithPadding() {
        // 4000×2000 doc, 1048×848 view, 24pt padding → usable 1000×800 →
        // scale limited by width: 1000/4000 = 0.25.
        let vp = Viewport.fit(documentSize: CGSize(width: 4000, height: 2000),
                              in: CGSize(width: 1048, height: 848),
                              padding: 24)
        #expect(abs(vp.zoom - 0.25) < 1e-9)
        // 4000×0.25 = 1000 wide → x = 24; 2000×0.25 = 500 tall → y = (848-500)/2.
        #expect(abs(vp.documentFrameInView.minX - 24) < 1e-9)
        #expect(abs(vp.documentFrameInView.minY - 174) < 1e-9)
    }

    @Test func fitWithDegenerateSizesDoesNotProduceNaN() {
        let vp = Viewport.fit(documentSize: .zero, in: CGSize(width: 100, height: 100))
        #expect(vp.zoom > 0)
        #expect(vp.origin.x.isFinite && vp.origin.y.isFinite)
    }

    // MARK: Coordinate mapping

    @Test func viewAndDocumentPointsRoundTrip() {
        let vp = Viewport(documentSize: CGSize(width: 800, height: 600),
                          viewSize: CGSize(width: 400, height: 300),
                          zoom: 0.5,
                          origin: CGPoint(x: 10, y: 20))
        let doc = CGPoint(x: 123, y: 456)
        let view = vp.viewPoint(fromDocument: doc)
        #expect(view == CGPoint(x: 10 + 123 * 0.5, y: 20 + 456 * 0.5))
        let back = vp.documentPoint(fromView: view)
        #expect(abs(back.x - doc.x) < 1e-9 && abs(back.y - doc.y) < 1e-9)
    }

    // MARK: Zooming

    @Test func zoomToCursorKeepsTheAnchoredDocumentPointFixed() {
        let vp = Viewport(documentSize: CGSize(width: 1000, height: 1000),
                          viewSize: CGSize(width: 500, height: 500),
                          zoom: 1,
                          origin: CGPoint(x: -250, y: -250))
        let anchor = CGPoint(x: 100, y: 400) // some view-space cursor position
        let docUnderCursor = vp.documentPoint(fromView: anchor)
        let zoomed = vp.zoomed(to: 2, anchorInView: anchor)
        #expect(zoomed.zoom == 2)
        let after = zoomed.viewPoint(fromDocument: docUnderCursor)
        #expect(abs(after.x - anchor.x) < 1e-6)
        #expect(abs(after.y - anchor.y) < 1e-6)
    }

    @Test func zoomIsClampedToTheAllowedRange() {
        let vp = Viewport(documentSize: CGSize(width: 100, height: 100),
                          viewSize: CGSize(width: 100, height: 100),
                          zoom: 1, origin: .zero)
        #expect(vp.zoomed(to: 10_000, anchorInView: .zero).zoom == Viewport.maxZoom)
        #expect(vp.zoomed(to: 0, anchorInView: .zero).zoom == Viewport.minZoom)
    }

    // MARK: Panning & clamping

    @Test func smallerThanViewContentIsAlwaysCentered() {
        // 100×100 doc at 1× in a 500×300 view: panning is a no-op; it re-centers.
        let vp = Viewport(documentSize: CGSize(width: 100, height: 100),
                          viewSize: CGSize(width: 500, height: 300),
                          zoom: 1, origin: .zero).clamped()
        #expect(vp.documentFrameInView.midX == 250)
        #expect(vp.documentFrameInView.midY == 150)
        let panned = vp.panned(by: CGPoint(x: 50, y: -70))
        #expect(panned == vp)
    }

    @Test func largerThanViewContentPansFreelyButNotPastEdges() {
        // 2000×2000 doc at 1× in a 500×500 view.
        let vp = Viewport(documentSize: CGSize(width: 2000, height: 2000),
                          viewSize: CGSize(width: 500, height: 500),
                          zoom: 1,
                          origin: CGPoint(x: -750, y: -750))
        // A normal pan moves the content 1:1.
        let panned = vp.panned(by: CGPoint(x: -10, y: 25))
        #expect(panned.origin == CGPoint(x: -760, y: -725))
        // Panning far past the document edge clamps so the edge meets the view edge.
        // (Expected values pre-typed: compound integer-literal expressions inside
        // #expect infer as Int and never equal a boxed CGFloat.)
        let slammed = vp.panned(by: CGPoint(x: -99_999, y: 99_999))
        let rightEdgeAtViewEdge: CGFloat = 500 - 2000
        #expect(slammed.origin.x == rightEdgeAtViewEdge)
        #expect(slammed.origin.y == 0) // top doc edge at top view edge
    }

    @Test func mixedAxesClampIndependently() {
        // Wide ribbon: 2000×100 at 1× in 500×500 — x scrolls, y centers.
        let vp = Viewport(documentSize: CGSize(width: 2000, height: 100),
                          viewSize: CGSize(width: 500, height: 500),
                          zoom: 1,
                          origin: CGPoint(x: -100, y: -3000)).clamped()
        #expect(vp.origin.x == -100)                 // valid x pan is preserved
        #expect(vp.documentFrameInView.midY == 250)  // y is centered
    }

    // MARK: View resize

    @Test func resizingTheViewKeepsTheCenteredDocumentPointCentered() {
        // Doc point at the view's center stays at the view's center across a resize.
        let vp = Viewport(documentSize: CGSize(width: 4000, height: 4000),
                          viewSize: CGSize(width: 400, height: 400),
                          zoom: 1,
                          origin: CGPoint(x: -1800, y: -1800))
        let centerDoc = vp.documentPoint(fromView: CGPoint(x: 200, y: 200))
        let resized = vp.resized(viewSize: CGSize(width: 800, height: 600))
        let newCenter = resized.viewPoint(fromDocument: centerDoc)
        #expect(abs(newCenter.x - 400) < 1e-6)
        #expect(abs(newCenter.y - 300) < 1e-6)
    }
}
