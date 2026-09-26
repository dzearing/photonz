import CoreGraphics
import PhotonzCore
import Testing

/// The floating tool bar covers a band along the bottom of the canvas. A
/// picture fitted to the whole view had its bottom edge, where captions sit,
/// under that bar (the user, 2026-09-25). These pin the camera's answer: fit
/// and centre in the part of the view nothing covers, and leave a camera a
/// person moved alone.
@Suite("Viewport, with the bottom of the view covered")
struct ViewportObscuredTests {

    /// 64pt covered: the bar (48pt) floating 16pt off the floor.
    let covered: CGFloat = 64

    @Test func fitCentresAboveTheCoveredBand() {
        // 1000x800 view with 64pt covered -> 1000x736 clear. A 200x100 picture
        // at 100% sits centred in the clear part, not in the whole view.
        let vp = Viewport.fit(documentSize: CGSize(width: 200, height: 100),
                              in: CGSize(width: 1000, height: 800),
                              padding: 0, obscuredBottom: covered)
        #expect(vp.zoom == 1)
        #expect(vp.documentFrameInView == CGRect(x: 400, y: (736 - 100) / 2, width: 200, height: 100))
        #expect(vp.obscuredBottom == covered)
    }

    @Test func aTallPictureIsScaledToTheClearHeight() {
        // Portrait 1000x2000 in a 1048x848 view with 24pt padding: the clear
        // height is 848 - 64 = 784, less 48 of padding = 736 -> zoom 0.368.
        let vp = Viewport.fit(documentSize: CGSize(width: 1000, height: 2000),
                              in: CGSize(width: 1048, height: 848),
                              padding: 24, obscuredBottom: covered)
        #expect(abs(vp.zoom - 736.0 / 2000) < 1e-9)
        let frame = vp.documentFrameInView
        #expect(abs(frame.minY - 24) < 1e-9)
        #expect(abs(frame.maxY - (848 - covered - 24)) < 1e-9)
    }

    @Test func aWidePictureNeverReachesTheBand() {
        // Width binds; the picture is centred in the clear part and its bottom
        // lands above the band.
        let vp = Viewport.fit(documentSize: CGSize(width: 4000, height: 2000),
                              in: CGSize(width: 1048, height: 848),
                              padding: 24, obscuredBottom: covered)
        #expect(abs(vp.zoom - 0.25) < 1e-9)
        #expect(abs(vp.documentFrameInView.minY - (784 - 500) / 2) < 1e-9)
        #expect(vp.documentFrameInView.maxY <= 848 - covered)
    }

    @Test func noCoverFitsExactlyAsBefore() {
        let before = Viewport.fit(documentSize: CGSize(width: 4000, height: 2000),
                                  in: CGSize(width: 1048, height: 848))
        let after = Viewport.fit(documentSize: CGSize(width: 4000, height: 2000),
                                 in: CGSize(width: 1048, height: 848), obscuredBottom: 0)
        #expect(before == after)
    }

    @Test func aFittedPictureDoesNotJumpWhenPannedOrScrolled() {
        // The first two-finger scroll after a fit must not drop the picture
        // back to the middle of the whole view.
        let vp = Viewport.fit(documentSize: CGSize(width: 200, height: 100),
                              in: CGSize(width: 1000, height: 800),
                              padding: 0, obscuredBottom: covered)
        #expect(vp.panned(by: CGPoint(x: 0, y: 40)) == vp)
        #expect(vp.clamped() == vp)
    }

    @Test func zoomedInByHandTheBandCanBeScrolledUnder() {
        // Bigger than the whole view: it scrolls edge to edge of the WHOLE
        // view, so a person can deliberately bring the bottom under the bar.
        var vp = Viewport(documentSize: CGSize(width: 1000, height: 1000),
                          viewSize: CGSize(width: 500, height: 500),
                          zoom: 1, origin: .zero, obscuredBottom: covered)
        vp = vp.panned(by: CGPoint(x: 0, y: -10_000))
        #expect(abs(vp.origin.y - (500 - 1000)) < 1e-9)
        vp = vp.panned(by: CGPoint(x: 0, y: 10_000))
        #expect(vp.origin.y == 0)
    }

    @Test func betweenTheClearHeightAndTheViewItKeepsWhereItWasPut() {
        // 460pt tall in a 500pt view with 64 covered: too tall for the clear
        // part, short enough for the whole view. It stays where the person
        // left it, inside the whole view, rather than being snapped anywhere.
        let vp = Viewport(documentSize: CGSize(width: 100, height: 460),
                          viewSize: CGSize(width: 500, height: 500),
                          zoom: 1, origin: CGPoint(x: 0, y: 30), obscuredBottom: covered)
        #expect(vp.clamped().origin.y == 30)
        #expect(vp.panned(by: CGPoint(x: 0, y: 100)).origin.y == 40)
        #expect(vp.panned(by: CGPoint(x: 0, y: -100)).origin.y == 0)
    }

    @Test func resizingKeepsTheMiddleOfTheClearPartStill() {
        let vp = Viewport(documentSize: CGSize(width: 2000, height: 2000),
                          viewSize: CGSize(width: 600, height: 600),
                          zoom: 1, origin: CGPoint(x: -500, y: -500), obscuredBottom: covered)
        let middle = vp.documentPoint(fromView: CGPoint(x: 300, y: (600 - covered) / 2))
        let grown = vp.resized(viewSize: CGSize(width: 800, height: 700))
        let after = grown.viewPoint(fromDocument: middle)
        #expect(abs(after.x - 400) < 1e-9)
        #expect(abs(after.y - (700 - covered) / 2) < 1e-9)
        #expect(grown.obscuredBottom == covered)
    }

    @Test func revealingStopsAboveTheBand() {
        // A box near the bottom of a big document, scrolled into view, lands
        // with its bottom edge padding clear of the band, not of the floor.
        let vp = Viewport(documentSize: CGSize(width: 2000, height: 2000),
                          viewSize: CGSize(width: 600, height: 600),
                          zoom: 1, origin: .zero, obscuredBottom: covered)
        let moved = vp.revealing(CGRect(x: 100, y: 1500, width: 100, height: 100))
        let box = CGRect(origin: moved.viewPoint(fromDocument: CGPoint(x: 100, y: 1500)),
                         size: CGSize(width: 100, height: 100))
        #expect(abs(box.maxY - (600 - covered - 24)) < 1e-9)
    }

    @Test func aBandTallerThanTheViewDoesNotBreakTheMaths() {
        let vp = Viewport.fit(documentSize: CGSize(width: 200, height: 100),
                              in: CGSize(width: 300, height: 50),
                              obscuredBottom: 500)
        #expect(vp.zoom > 0)
        #expect(vp.origin.x.isFinite && vp.origin.y.isFinite)
    }
}
