import CoreGraphics
import Testing
@testable import PhotonzCore

/// Bringing something into view without moving the camera any further than it
/// has to (`Viewport.revealing`).
///
/// Adding a version of a component puts a whole new drawing down somewhere on
/// the canvas, and there is no promise it is anywhere near what you were
/// looking at. The camera goes and gets it. It moves the least it can, and it
/// never moves at all when the thing is already on screen, because a canvas
/// that jumps for no reason is worse than one that never moves.
struct ViewportRevealTests {

    /// A 4000x3000 document in an 800x600 view at 1:1, parked at the top left.
    private func viewport(zoom: CGFloat = 1, origin: CGPoint = .zero) -> Viewport {
        Viewport(documentSize: CGSize(width: 4000, height: 3000),
                 viewSize: CGSize(width: 800, height: 600),
                 zoom: zoom, origin: origin).clamped()
    }

    @Test func somethingAlreadyOnScreenDoesNotMoveTheCamera() {
        let start = viewport()
        let revealed = start.revealing(CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(revealed == start)
    }

    @Test func somethingJustOffTheRightEdgeIsBroughtIn() {
        let start = viewport()
        let target = CGRect(x: 900, y: 100, width: 200, height: 100)
        let revealed = start.revealing(target, padding: 24)
        // On screen, with the padding honoured...
        let box = CGRect(origin: revealed.viewPoint(fromDocument: target.origin),
                         size: CGSize(width: target.width * revealed.zoom,
                                      height: target.height * revealed.zoom))
        #expect(box.maxX <= 800 - 24 + 0.01)
        #expect(box.minX >= -0.01)
        // ...and no further than it had to go: the same zoom, and the vertical
        // untouched because nothing was wrong with it.
        #expect(revealed.zoom == start.zoom)
        #expect(revealed.origin.y == start.origin.y)
    }

    @Test func somethingBelowTheViewIsBroughtUp() {
        let start = viewport()
        let target = CGRect(x: 100, y: 1400, width: 200, height: 100)
        let revealed = start.revealing(target, padding: 24)
        let top = revealed.viewPoint(fromDocument: target.origin).y
        #expect(top >= 24 - 0.01)
        #expect(top + target.height * revealed.zoom <= 600 - 24 + 0.01)
        #expect(revealed.origin.x == start.origin.x)
    }

    /// Something too big to see at this zoom: the camera pulls back until it
    /// fits, rather than showing a corner of it and calling that revealed.
    @Test func somethingTooBigToFitPullsTheCameraBack() {
        let start = viewport()
        let target = CGRect(x: 200, y: 200, width: 2000, height: 1500)
        let revealed = start.revealing(target, padding: 24)
        #expect(revealed.zoom < start.zoom)
        let box = CGRect(origin: revealed.viewPoint(fromDocument: target.origin),
                         size: CGSize(width: target.width * revealed.zoom,
                                      height: target.height * revealed.zoom))
        #expect(box.width <= 800 + 0.01)
        #expect(box.height <= 600 + 0.01)
    }

    /// Never the other way: revealing a small thing does not zoom you in on it.
    @Test func revealingSomethingSmallNeverZoomsIn() {
        let start = viewport(zoom: 0.5)
        let revealed = start.revealing(CGRect(x: 3000, y: 2500, width: 40, height: 20))
        #expect(revealed.zoom <= start.zoom)
    }

    @Test func anEmptyRectIsLeftAlone() {
        let start = viewport()
        #expect(start.revealing(.null) == start)
        #expect(start.revealing(CGRect(x: 900, y: 100, width: 0, height: 0)) == start)
    }
    // MARK: - Bringing the thing it came from along

    /// A new drawing that arrives next to an old one is only half a story on
    /// its own: "where did that come from" is answered by seeing both. So the
    /// camera takes the pair when the pair fits.
    @Test func theThingItCameFromComesAlongWhenBothFit() {
        let start = viewport()
        let source = CGRect(x: 1000, y: 100, width: 200, height: 100)
        let arrival = CGRect(x: 1240, y: 100, width: 200, height: 100)
        let revealed = start.revealing(arrival, alongside: source, padding: 24)
        for rect in [source, arrival] {
            let box = CGRect(origin: revealed.viewPoint(fromDocument: rect.origin),
                             size: CGSize(width: rect.width * revealed.zoom,
                                          height: rect.height * revealed.zoom))
            #expect(box.minX >= -0.01 && box.maxX <= 800 + 0.01)
            #expect(box.minY >= -0.01 && box.maxY <= 600 + 0.01)
        }
        // Taking both along must not cost any zoom: the pair fitted as it was.
        #expect(revealed.zoom == start.zoom)
    }

    /// A pair too far apart to see together does not drag the camera back to
    /// a bird's eye view. The new drawing wins and the old one is let go.
    @Test func aPairTooFarApartShowsTheNewOneRatherThanZoomingOut() {
        let start = viewport()
        let source = CGRect(x: 100, y: 100, width: 200, height: 100)
        let arrival = CGRect(x: 3400, y: 2600, width: 200, height: 100)
        let revealed = start.revealing(arrival, alongside: source, padding: 24)
        #expect(revealed.zoom == start.zoom)
        #expect(revealed == start.revealing(arrival, padding: 24))
    }

    @Test func aPairAlreadyOnScreenDoesNotMoveTheCamera() {
        let start = viewport()
        let revealed = start.revealing(CGRect(x: 400, y: 100, width: 200, height: 100),
                                       alongside: CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(revealed == start)
    }

}
