import CoreGraphics
import Testing
@testable import PhotonzCore

// The slide into Edit drawn as layers (queue task
// edit-mode-s-contents-come-in-with-the-slide-not, 2026-11-17): the window is
// laid out as Edit once, at the key, and the picture, the panel and the dock
// are moved back to where View had them and slid home. Re-laying out the
// whole window on every frame of the slide was most of its main thread.
@Suite("The slide into Edit, as layers")
struct ViewEditSlideTests {

    private let doc = CGSize(width: 2880, height: 1800)

    /// View: the picture across the whole window.
    private var view: Viewport {
        Viewport(documentSize: doc, viewSize: CGSize(width: 1728, height: 942),
                 zoom: 0.45, origin: CGPoint(x: 216, y: 66))
    }

    /// Edit: a smaller canvas, the picture smaller and further left.
    private var edit: Viewport {
        Viewport(documentSize: doc, viewSize: CGSize(width: 1447, height: 637),
                 zoom: 0.3, origin: CGPoint(x: 291, y: 30))
    }

    private func drawn(_ point: CGPoint, by viewport: Viewport) -> CGPoint {
        viewport.viewPoint(fromDocument: point)
    }

    @Test("all the way back, the picture Edit draws sits exactly where View drew it")
    func startsWhereViewWas() {
        let slide = ViewEditSlide(from: view, dockHeightFrom: 48)
        let move = slide.pictureMove(to: edit, progress: 1)
        for corner in [CGPoint.zero, CGPoint(x: 2880, y: 0), CGPoint(x: 0, y: 1800), CGPoint(x: 2880, y: 1800)] {
            let moved = drawn(corner, by: edit).applying(move)
            let was = drawn(corner, by: view)
            #expect(abs(moved.x - was.x) < 0.001)
            #expect(abs(moved.y - was.y) < 0.001)
        }
    }

    @Test("home, the picture is not moved at all")
    func landsWhereEditIs() {
        let slide = ViewEditSlide(from: view, dockHeightFrom: 48)
        #expect(slide.pictureMove(to: edit, progress: 0) == .identity)
    }

    @Test("half way, every corner is half way between the two")
    func halfWay() {
        let slide = ViewEditSlide(from: view, dockHeightFrom: 48)
        let move = slide.pictureMove(to: edit, progress: 0.5)
        for corner in [CGPoint.zero, CGPoint(x: 2880, y: 1800)] {
            let moved = drawn(corner, by: edit).applying(move)
            let a = drawn(corner, by: view), b = drawn(corner, by: edit)
            #expect(abs(moved.x - (a.x + b.x) / 2) < 0.001)
            #expect(abs(moved.y - (a.y + b.y) / 2) < 0.001)
        }
    }

    @Test("a picture that changed size in between, or no zoom at all, is not moved")
    func nothingToMatch() {
        let slide = ViewEditSlide(from: view, dockHeightFrom: 48)
        var other = edit
        other.documentSize = CGSize(width: 100, height: 100)
        #expect(slide.pictureMove(to: other, progress: 1) == .identity)
        var flat = edit
        flat.zoom = 0
        #expect(slide.pictureMove(to: flat, progress: 1) == .identity)
    }

    @Test("the dock starts as tall as View had it, its tracks below the window, and rises")
    func dockRises() {
        let slide = ViewEditSlide(from: view, dockHeightFrom: 48)
        #expect(slide.dockDrop(dockHeight: 353, progress: 1) == 305)
        #expect(slide.dockDrop(dockHeight: 353, progress: 0.5) == 152.5)
        #expect(slide.dockDrop(dockHeight: 353, progress: 0) == 0)
        // Never pushed up past where it lands.
        #expect(slide.dockDrop(dockHeight: 30, progress: 1) == 0)
    }

    @Test("the panel starts just off the window's right edge")
    func panelSlidesIn() {
        #expect(ViewEditSlide.panelShift(width: 281, progress: 1) == 281)
        #expect(ViewEditSlide.panelShift(width: 281, progress: 0.25) == 70.25)
        #expect(ViewEditSlide.panelShift(width: 281, progress: 0) == 0)
    }
}
