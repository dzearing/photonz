import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A new screen has to land somewhere you can look at it.
///
/// The canvas is the whole of where the camera may go (`Viewport.clamped`) and
/// the whole of what the renderer paints, so a frame placed past its edge is
/// both invisible and unreachable: it shows in the layers list and nowhere
/// else. So the canvas grows, right and down only, to take in every frame that
/// is put on it, and a row of screens wraps to a second row rather than growing
/// the canvas without end.
@Suite("A new screen lands where the canvas can reach it")
struct FrameCanvasRoomTests {

    private let desktop = CGSize(width: 1440, height: 1024)

    private func canvasRect(_ document: PhotonzDocument) -> CGRect {
        CGRect(origin: .zero, size: document.canvasSize)
    }

    @Test("The second screen is somewhere the canvas can be scrolled to")
    func secondScreenIsOnTheCanvas() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1600, height: 1100))
        let first = document.placementForNewFrame(size: desktop, visible: .null)
        document.addFrameMakingRoom(origin: first, size: desktop)
        let second = document.placementForNewFrame(size: desktop, visible: .null)
        let made = document.addFrameMakingRoom(origin: second, size: desktop)

        let box = document.canvasBounds(of: made.id)
        #expect(box == CGRect(x: 1600, y: 38, width: 1440, height: 1024))
        #expect(canvasRect(document).contains(box ?? .null))
    }

    @Test("Making room never moves the screen that was already there")
    func theFirstScreenHoldsStill() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1600, height: 1100))
        let first = document.placementForNewFrame(size: desktop, visible: .null)
        let one = document.addFrameMakingRoom(origin: first, size: desktop)
        let before = document.canvasBounds(of: one.id)

        let second = document.placementForNewFrame(size: desktop, visible: .null)
        document.addFrameMakingRoom(origin: second, size: desktop)

        #expect(document.canvasBounds(of: one.id) == before)
        #expect(document.layer(id: one.id)?.children.count == 0)
    }

    @Test("A screen that fits leaves the canvas exactly as it was")
    func aScreenThatFitsChangesNothing() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 4000, height: 3000))
        document.addFrameMakingRoom(origin: CGPoint(x: 100, y: 100), size: desktop)
        #expect(document.canvasSize == CGSize(width: 4000, height: 3000))
    }

    @Test("The first screen never starts off the top or left of the canvas")
    func theFirstScreenStartsOnTheCanvas() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 720, height: 480))
        let origin = document.placementForNewFrame(size: desktop, visible: .null)
        #expect(origin == .zero)

        let made = document.addFrameMakingRoom(origin: origin, size: desktop)
        #expect(canvasRect(document).contains(document.canvasBounds(of: made.id) ?? .null))
    }

    @Test("The canvas grows by the gutter, and only on the side that ran out")
    func growthTakesTheSideThatRanOut() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1600, height: 1100))
        document.addFrameMakingRoom(origin: CGPoint(x: 1600, y: 38), size: desktop)
        #expect(document.canvasSize == CGSize(width: 3040 + PhotonzDocument.frameGutter,
                                              height: 1100))
    }

    @Test("The canvas never grows past the biggest one you could ask for")
    func growthStopsAtTheCeiling() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1600, height: 1100))
        document.addFrameMakingRoom(origin: CGPoint(x: 8000, y: 0), size: desktop)
        #expect(document.canvasSize.width == PhotonzDocument.maximumCanvasSide)
    }

    @Test("A row that has run out of canvas wraps to a second row")
    func theRowWraps() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 8192, height: 2000))
        document.addFrameMakingRoom(name: "Wide", origin: .zero,
                                    size: CGSize(width: 8000, height: 400))

        let wrapped = document.placementForNewFrame(size: desktop, visible: .null)
        #expect(wrapped == CGPoint(x: 0, y: 400 + PhotonzDocument.frameGutter))
        let made = document.addFrameMakingRoom(origin: wrapped, size: desktop)
        #expect(canvasRect(document).contains(document.canvasBounds(of: made.id) ?? .null))
    }

    @Test("The screen after a wrap lines up beside the wrapped one, not above it")
    func theNextScreenJoinsTheNewRow() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 8192, height: 4000))
        document.addFrameMakingRoom(name: "Wide", origin: .zero,
                                    size: CGSize(width: 8000, height: 400))
        let wrapped = document.placementForNewFrame(size: desktop, visible: .null)
        document.addFrameMakingRoom(origin: wrapped, size: desktop)

        let third = document.placementForNewFrame(size: desktop, visible: .null)
        #expect(third == CGPoint(x: 1440 + PhotonzDocument.frameGutter, y: wrapped.y))
    }
}
