import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("Paint-bucket fill")
struct FillTests {

    private let solid = ImageRef(pixelSize: CGSize(width: 8, height: 8))

    private func annotationLayer(_ shape: AnnotationShape) -> Layer {
        AnnotationBuilder.layer(
            content: AnnotationContent(shape: shape, strokeWidth: 4, colorHex: "#112233",
                                       start: .zero, end: CGPoint(x: 100, y: 80)),
            from: .zero, to: CGPoint(x: 100, y: 80))
    }

    @Test func imageLayerBecomesASolidAndDropsItsCrop() {
        var layer = Layer(name: "Photo", content: .image(ImageRef(pixelSize: CGSize(width: 400, height: 300))),
                          frame: CGRect(x: 10, y: 10, width: 400, height: 300),
                          crop: CGRect(x: 50, y: 50, width: 100, height: 100))
        layer = Fill.filled(layer, colorHex: "#00FF00", solidRef: solid)!
        #expect(layer.imageRef == solid)
        #expect(layer.crop == nil)
        #expect(layer.frame == CGRect(x: 10, y: 10, width: 400, height: 300), "fill never moves the layer")
    }

    @Test func imageLayerWithoutASolidRefIsRefused() {
        let layer = Layer(name: "Photo", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(Fill.filled(layer, colorHex: "#00FF00", solidRef: nil) == nil)
    }

    @Test func boxShapesGetAnInteriorFillKeepingTheirStroke() {
        for shape in [AnnotationShape.rectangle, .ellipse] {
            let filled = Fill.filled(annotationLayer(shape), colorHex: "#ABCDEF", solidRef: nil)
            #expect(filled?.annotation?.fillColorHex == "#ABCDEF")
            #expect(filled?.annotation?.colorHex == "#112233", "stroke color survives")
        }
    }

    @Test func strokeShapesRecolorTheStroke() {
        for shape in [AnnotationShape.line, .arrow, .highlight] {
            let filled = Fill.filled(annotationLayer(shape), colorHex: "#ABCDEF", solidRef: nil)
            #expect(filled?.annotation?.colorHex == "#ABCDEF")
        }
    }

    @Test func textAndMeasureRecolor() {
        let text = Layer(name: "T", content: .text(TextContent(string: "hi", fontSize: 20, colorHex: "#000000")),
                         frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        if case .text(let c)? = Fill.filled(text, colorHex: "#FF0000", solidRef: nil)?.content {
            #expect(c.colorHex == "#FF0000")
        } else { Issue.record("text fill failed") }

        // A measure's "color" is its ink — outline + readout. The chip fill is
        // its own inspector control, so the bucket leaves it alone.
        let measure = MeasureBuilder.layer(
            content: MeasureContent(mode: .horizontal, strokeWidth: 1, strokeColorHex: "#000000",
                                    chipColorHex: "#123456", textColorHex: "#000000"),
            from: .zero, to: CGPoint(x: 50, y: 0))
        let filled = Fill.filled(measure, colorHex: "#FF0000", solidRef: nil)?.measure
        #expect(filled?.strokeColorHex == "#FF0000")
        #expect(filled?.textColorHex == "#FF0000")
        #expect(filled?.chipColorHex == "#123456")
    }

    @Test func collageFillsItsBackdrop() {
        let layer = Collage.layer(content: CollageContent(slots: [CollageSlot()], backdropColorHex: nil),
                                  frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        #expect(Fill.filled(layer, colorHex: "#123456", solidRef: nil)?.collage?.backdropColorHex == "#123456")
    }

    @Test func zoomCalloutRefusesFill() {
        guard let layer = ZoomCalloutBuilder.layer(from: .zero, to: CGPoint(x: 60, y: 60),
                                                   canvas: CGSize(width: 500, height: 500)) else {
            Issue.record("callout build failed"); return
        }
        #expect(Fill.filled(layer, colorHex: "#123456", solidRef: solid) == nil)
    }
}
