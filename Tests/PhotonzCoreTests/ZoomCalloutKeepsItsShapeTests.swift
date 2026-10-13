import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Resizing a zoom callout's magnified box never stretches the picture in it:
/// a handle drag keeps the box the SOURCE's shape by default, and a box given
/// another shape (Shift on the canvas, a typed height) takes the source with
/// it, about the source's own centre. The user, 2026-10-13: "when i resize the
/// magnification window, it does not preserve aspect ratio by default".
@Suite("Zoom callout keeps its shape")
struct ZoomCalloutKeepsItsShapeTests {

    /// A 60 x 40 source at 2x: a 120 x 80 box at (200, 100).
    private func callout(source: CGRect = CGRect(x: 20, y: 30, width: 60, height: 40),
                         frame: CGRect = CGRect(x: 200, y: 100, width: 120, height: 80)) -> Layer {
        Layer(name: "Zoom",
              content: .zoomCallout(ZoomCalloutContent(sourceRect: source,
                                                       magnification: frame.width / source.width)),
              frame: frame)
    }

    private func aspect(_ r: CGRect) -> CGFloat { r.width / r.height }

    private func within(_ a: CGFloat, _ b: CGFloat, percent: CGFloat = 0.5) -> Bool {
        abs(a - b) / b <= percent / 100
    }

    // MARK: The box can never take a shape its source does not have

    @Test func aSameShapedResizeLeavesTheSourceAlone() {
        let layer = callout().resized(to: CGRect(x: 200, y: 100, width: 180, height: 120))
        #expect(layer.zoomCallout?.sourceRect == CGRect(x: 20, y: 30, width: 60, height: 40))
        #expect(layer.zoomCallout?.magnification == 3)
    }

    @Test func aBoxOfAnotherShapeReshapesTheSourceAboutItsCentre() throws {
        // 180 wide is 3x; 60 tall at 3x is a source 20 tall, centred where the
        // 40 tall one was (y 50).
        let layer = callout().resized(to: CGRect(x: 200, y: 100, width: 180, height: 60))
        let source = try #require(layer.zoomCallout?.sourceRect)
        #expect(layer.zoomCallout?.magnification == 3)
        #expect(source.width == 60)
        #expect(abs(source.height - 20) < 0.0001)
        #expect(abs(source.midX - 50) < 0.0001 && abs(source.midY - 50) < 0.0001)
        #expect(within(aspect(source), aspect(layer.frame), percent: 0.01))
    }

    @Test func aTallerBoxTakesATallerSource() throws {
        let layer = callout().resized(to: CGRect(x: 200, y: 100, width: 120, height: 160))
        let source = try #require(layer.zoomCallout?.sourceRect)
        #expect(layer.zoomCallout?.magnification == 2)
        #expect(abs(source.height - 80) < 0.0001 && abs(source.midY - 50) < 0.0001)
    }

    // MARK: A handle drag keeps the source's shape unless told otherwise

    @Test func aCornerDragKeepsTheSourceShapeAtTenSizes() {
        let layer = callout()
        let start = layer.frame
        for step in 1...10 {
            let pointer = CGPoint(x: start.maxX + CGFloat(step) * 23 - 90,
                                  y: start.maxY + CGFloat(step * step) * 3 - 40)
            let frame = ZoomCalloutBuilder.draggedFrame(layer, from: start, handle: .bottomRight,
                                                        to: pointer, keepingShape: true)
            #expect(within(aspect(frame), 1.5), "box \(frame) is not the source's 3:2")
            // Anchored at the opposite corner.
            #expect(frame.minX == start.minX && frame.minY == start.minY)
            let resized = layer.resized(to: frame)
            #expect(resized.zoomCallout?.sourceRect == layer.zoomCallout?.sourceRect)
            #expect(abs((resized.zoomCallout?.magnification ?? 0) - frame.width / 60) < 0.0001)
        }
    }

    @Test func everyCornerHoldsItsOpposite() {
        let layer = callout()
        let start = layer.frame
        for handle in ResizeHandle.allCases where handle.isCorner {
            let grab = Handles.point(for: handle, in: start)
            let frame = ZoomCalloutBuilder.draggedFrame(layer, from: start, handle: handle,
                                                        to: CGPoint(x: grab.x + (handle.movesMaxX ? 30 : -30),
                                                                    y: grab.y + (handle.movesMaxY ? 5 : -5)),
                                                        keepingShape: true)
            #expect(within(aspect(frame), 1.5))
            #expect(Handles.point(for: handle.opposite, in: frame)
                    == Handles.point(for: handle.opposite, in: start))
            #expect(frame.width > start.width)
        }
    }

    @Test func anEdgeDragGrowsTheOtherSideAboutItsMiddle() {
        let layer = callout()
        let start = layer.frame
        let right = ZoomCalloutBuilder.draggedFrame(layer, from: start, handle: .right,
                                                    to: CGPoint(x: start.maxX + 60, y: start.midY + 7),
                                                    keepingShape: true)
        #expect(right.minX == start.minX && right.width == 180)
        #expect(abs(right.height - 120) < 0.0001 && abs(right.midY - start.midY) < 0.0001)

        let bottom = ZoomCalloutBuilder.draggedFrame(layer, from: start, handle: .bottom,
                                                     to: CGPoint(x: start.midX, y: start.maxY - 20),
                                                     keepingShape: true)
        #expect(bottom.minY == start.minY && bottom.height == 60)
        #expect(abs(bottom.width - 90) < 0.0001 && abs(bottom.midX - start.midX) < 0.0001)
    }

    @Test func aBoxAlreadyStretchedComesBackToTheSourceShape() {
        // A callout saved before this rule, pulled out of shape. The first
        // drag brings the box back to the source's 3:2 rather than locking in
        // the stretch.
        let layer = callout(frame: CGRect(x: 200, y: 100, width: 120, height: 200))
        let frame = ZoomCalloutBuilder.draggedFrame(layer, from: layer.frame, handle: .bottomRight,
                                                    to: CGPoint(x: 340, y: 300), keepingShape: true)
        #expect(within(aspect(frame), 1.5))
        #expect(frame.origin == layer.frame.origin)
    }

    @Test func shiftFreesTheShapeAndTheSourceFollows() throws {
        let layer = callout()
        let start = layer.frame
        let frame = ZoomCalloutBuilder.draggedFrame(layer, from: start, handle: .bottom,
                                                    to: CGPoint(x: start.midX, y: start.maxY + 40),
                                                    keepingShape: false)
        // Free: only the edge held moves.
        #expect(frame == CGRect(x: 200, y: 100, width: 120, height: 120))
        let resized = layer.resized(to: frame)
        let source = try #require(resized.zoomCallout?.sourceRect)
        #expect(resized.zoomCallout?.magnification == 2)
        #expect(within(aspect(source), aspect(frame), percent: 0.01))
        #expect(abs(source.midY - 50) < 0.0001 && source.width == 60)
    }

    @Test func otherLayersDragTheWayTheyAlwaysHave() {
        let image = Layer(name: "Image", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        let start = image.frame
        for keeping in [true, false] {
            #expect(ZoomCalloutBuilder.draggedFrame(image, from: start, handle: .bottomRight,
                                                    to: CGPoint(x: 150, y: 60), keepingShape: keeping)
                    == Handles.resize(start, dragging: .bottomRight, to: CGPoint(x: 150, y: 60),
                                      preserveAspect: keeping))
        }
    }

    @Test func onlyACalloutKeepsItsShapeByDefault() {
        #expect(callout().resizeKeepsShapeByDefault)
        let image = Layer(name: "Image", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(!image.resizeKeepsShapeByDefault)
    }
}
