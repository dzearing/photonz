import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("ZoomCalloutBuilder")
struct ZoomCalloutBuilderTests {

    private let canvas = CGSize(width: 400, height: 300)

    @Test func dragBoxBecomesPixelAlignedSource() {
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: 20.4, y: 30.7),
                                             to: CGPoint(x: 80.2, y: 90.1), canvas: canvas)
        let callout = layer?.zoomCallout
        #expect(callout != nil)
        if let source = callout?.sourceRect {
            #expect(source.minX == source.minX.rounded() && source.minY == source.minY.rounded())
            #expect(source.width == source.width.rounded() && source.height == source.height.rounded())
            #expect(CGRect(origin: .zero, size: canvas).contains(source))
        }
    }

    @Test func reversedDragNormalizes() {
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: 80, y: 90),
                                             to: CGPoint(x: 20, y: 30), canvas: canvas)
        #expect(layer?.zoomCallout?.sourceRect == CGRect(x: 20, y: 30, width: 60, height: 60))
    }

    @Test func sourceClampsToCanvas() {
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: -40, y: -40),
                                             to: CGPoint(x: 60, y: 60), canvas: canvas)
        #expect(layer?.zoomCallout?.sourceRect == CGRect(x: 0, y: 0, width: 60, height: 60))
    }

    @Test func frameComesFromPlacementGeometry() {
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: 20, y: 30),
                                             to: CGPoint(x: 80, y: 90), canvas: canvas)!
        let expected = Geometry.zoomCalloutPlacement(source: CGRect(x: 20, y: 30, width: 60, height: 60),
                                                     magnification: ZoomCalloutBuilder.defaultMagnification,
                                                     canvas: canvas)
        #expect(layer.frame == expected)
    }

    @Test func tinyDragReturnsNil() {
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: 20, y: 30),
                                             to: CGPoint(x: 22, y: 31), canvas: canvas)
        #expect(layer == nil)
    }

    @Test func dragOutsideCanvasReturnsNil() {
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: -100, y: -100),
                                             to: CGPoint(x: -10, y: -10), canvas: canvas)
        #expect(layer == nil)
    }

    @Test func defaultStyleReadsAsCallout() {
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: 20, y: 30),
                                             to: CGPoint(x: 80, y: 90), canvas: canvas)!
        #expect(layer.style.borderWidth > 0)
        #expect(layer.style.cornerRadius > 0)
        #expect(layer.style.shadow != nil)
        #expect(layer.name == "Zoom")
    }

    @Test func frameResizeSyncsMagnification() {
        var layer = ZoomCalloutBuilder.layer(from: CGPoint(x: 20, y: 30),
                                             to: CGPoint(x: 80, y: 90), canvas: canvas)!
        // Source is 60×60 at 2× → frame 120×120. Stretch to 180 wide → 3×.
        layer = layer.resized(to: CGRect(x: 200, y: 100, width: 180, height: 180))
        #expect(layer.zoomCallout?.magnification == 3)
        #expect(layer.frame == CGRect(x: 200, y: 100, width: 180, height: 180))
    }

    @Test func nonCalloutLayersResizeUnchanged() {
        var layer = Layer(name: "Image", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        layer = layer.resized(to: CGRect(x: 5, y: 5, width: 20, height: 20))
        #expect(layer.frame == CGRect(x: 5, y: 5, width: 20, height: 20))
    }

    @Test func legacyPayloadDecodesToRectangleShape() throws {
        let json = #"{"sourceRect":[[10,10],[20,20]],"magnification":2}"#
        let content = try JSONDecoder().decode(ZoomCalloutContent.self, from: Data(json.utf8))
        #expect(content.shape == .rectangle)
        #expect(content.sourceRect == CGRect(x: 10, y: 10, width: 20, height: 20))
    }

    @Test func shapeRoundTripsThroughCodable() throws {
        var content = ZoomCalloutContent(sourceRect: CGRect(x: 0, y: 0, width: 10, height: 10))
        content.shape = .circle
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(ZoomCalloutContent.self, from: data)
        #expect(decoded.shape == .circle)
    }

    @Test func circleEffectiveRadiusIsHalfTheShortSide() {
        var content = ZoomCalloutContent(sourceRect: CGRect(x: 0, y: 0, width: 20, height: 20))
        content.shape = .circle
        #expect(content.effectiveCornerRadius(boxSize: CGSize(width: 60, height: 40), styleRadius: 6) == 20)
    }

    @Test func rectangleEffectiveRadiusFollowsStyle() {
        let content = ZoomCalloutContent(sourceRect: CGRect(x: 0, y: 0, width: 20, height: 20))
        #expect(content.effectiveCornerRadius(boxSize: CGSize(width: 60, height: 40), styleRadius: 6) == 6)
    }

    @Test func magnificationFrameKeepsTheCenter() {
        let layer = ZoomCalloutBuilder.layer(from: CGPoint(x: 20, y: 30),
                                             to: CGPoint(x: 80, y: 90), canvas: canvas)!
        // 60×60 source at 2× → 120×120 frame. At 3× the frame grows to
        // 180×180 around the same center.
        let frame = ZoomCalloutBuilder.frame(for: 3, of: layer)
        #expect(frame.size == CGSize(width: 180, height: 180))
        #expect(frame.midX == layer.frame.midX && frame.midY == layer.frame.midY)
        // Round-tripping through resized(to:) recovers the magnification.
        #expect(layer.resized(to: frame).zoomCallout?.magnification == 3)
    }

    @Test func magnificationFrameOfNonCalloutIsUnchanged() {
        let layer = Layer(name: "Image", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                          frame: CGRect(x: 5, y: 5, width: 10, height: 10))
        #expect(ZoomCalloutBuilder.frame(for: 3, of: layer) == layer.frame)
    }

    @Test func zoomCalloutToolIsNotAnAnnotationTool() {
        #expect(Tool.zoomCallout.annotationShape == nil)
        #expect(!Tool.zoomCallout.createsAnnotationByDrag)
        #expect(AnnotationStyles().content(for: .zoomCallout) == nil)
    }
}
