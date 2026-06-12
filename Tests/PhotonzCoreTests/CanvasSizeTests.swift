import CoreGraphics
import PhotonzCore
import Testing

@Suite("Canvas size (expand without scaling)")
struct CanvasSizeTests {
    private func doc(_ layerFrame: CGRect) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 100, height: 100),
                        layers: [Layer(name: "L",
                                       content: .image(ImageRef(pixelSize: layerFrame.size)),
                                       frame: layerFrame)])
    }

    @Test func anchorUnitsSpanTheGrid() {
        #expect(CanvasAnchor.topLeft.unit == CGPoint(x: 0, y: 0))
        #expect(CanvasAnchor.center.unit == CGPoint(x: 0.5, y: 0.5))
        #expect(CanvasAnchor.bottomRight.unit == CGPoint(x: 1, y: 1))
        #expect(CanvasAnchor.top.unit == CGPoint(x: 0.5, y: 0))
        #expect(CanvasAnchor.left.unit == CGPoint(x: 0, y: 0.5))
    }

    @Test func expandFromCenterCentersTheContent() {
        var d = doc(CGRect(x: 10, y: 10, width: 20, height: 20))
        d.setCanvasSize(CGSize(width: 200, height: 160), anchor: .center)
        #expect(d.canvasSize == CGSize(width: 200, height: 160))
        #expect(d.layers[0].frame == CGRect(x: 60, y: 40, width: 20, height: 20))
    }

    @Test func expandFromTopLeftLeavesContentInPlace() {
        var d = doc(CGRect(x: 10, y: 10, width: 20, height: 20))
        d.setCanvasSize(CGSize(width: 300, height: 200), anchor: .topLeft)
        #expect(d.layers[0].frame == CGRect(x: 10, y: 10, width: 20, height: 20))
    }

    @Test func expandFromBottomRightShiftsContentByTheFullDelta() {
        var d = doc(CGRect(x: 10, y: 10, width: 20, height: 20))
        d.setCanvasSize(CGSize(width: 150, height: 130), anchor: .bottomRight)
        #expect(d.layers[0].frame == CGRect(x: 60, y: 40, width: 20, height: 20))
    }

    @Test func contentNeverScales() {
        var d = doc(CGRect(x: 0, y: 0, width: 50, height: 50))
        d.setCanvasSize(CGSize(width: 400, height: 400), anchor: .center)
        #expect(d.layers[0].frame.size == CGSize(width: 50, height: 50))
    }

    @Test func shrinkKeepsLayersEvenWhenTheyFallOutside() {
        var d = doc(CGRect(x: 80, y: 80, width: 20, height: 20))
        d.setCanvasSize(CGSize(width: 50, height: 50), anchor: .topLeft)
        #expect(d.layers.count == 1, "canvas-size never deletes layers (unlike crop)")
        #expect(d.layers[0].frame == CGRect(x: 80, y: 80, width: 20, height: 20))
    }

    @Test func sizeClampsToAtLeastOnePixel() {
        var d = doc(CGRect(x: 0, y: 0, width: 10, height: 10))
        d.setCanvasSize(CGSize(width: 0, height: -5), anchor: .center)
        #expect(d.canvasSize == CGSize(width: 1, height: 1))
    }
}
