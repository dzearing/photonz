import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("Rasterize layer (vector → pixels)")
struct RasterizeLayerTests {

    private func annotationLayer(shape: AnnotationShape = .rectangle) -> Layer {
        var style = LayerStyle(opacity: 0.5, blurRadius: 4, cornerRadius: 8,
                               borderWidth: 2, shadow: ShadowStyle())
        style.blendMode = .normal
        return Layer(name: "Rect",
                     content: .annotation(AnnotationContent(shape: shape)),
                     frame: CGRect(x: 20, y: 30, width: 100, height: 60),
                     crop: CGRect(x: 5, y: 5, width: 90, height: 50),
                     transform: LayerTransform(rotation: 0.2),
                     style: style)
    }

    @Test("Only annotation layers report as rasterizable")
    func isRasterizableGating() {
        #expect(annotationLayer().isRasterizable)
        for shape in AnnotationShape.allCases {
            #expect(annotationLayer(shape: shape).isRasterizable)
        }
        let image = Layer(name: "Bg", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(!image.isRasterizable)
        let text = Layer(name: "T", content: .text(TextContent(string: "hi")),
                         frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(!text.isRasterizable)
    }

    @Test("Rasterizing swaps content to the image ref, keeps identity, resets baked style")
    func rasterizeReplacesContentAndResetsStyle() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 300, height: 300))
        let layer = annotationLayer()
        doc.addLayer(layer)

        let ref = ImageRef(pixelSize: CGSize(width: 108, height: 68))
        let paddedFrame = CGRect(x: 16, y: 26, width: 108, height: 68)
        doc.rasterizeLayer(id: layer.id, rasterized: ref, frame: paddedFrame)

        let result = doc.layer(id: layer.id)
        #expect(result != nil)
        // Identity, name, slot, visibility, lock preserved.
        #expect(result?.id == layer.id)
        #expect(result?.name == "Rect")
        // Content is now the bitmap.
        #expect(result?.content == .image(ref))
        // Frame is the padded footprint.
        #expect(result?.frame == paddedFrame)
        // The now-baked style is reset so effects aren't double-applied.
        #expect(result?.style.opacity == 1)
        #expect(result?.style.blurRadius == 0)
        #expect(result?.style.cornerRadius == 0)
        #expect(result?.style.borderWidth == 0)
        #expect(result?.style.shadow == nil)
        // Crop and transform are baked into the pixels, so they reset too.
        #expect(result?.crop == nil)
        #expect(result?.transform == .identity)
    }

    @Test("Blend mode is carried over (it can't be baked into an isolated layer)")
    func blendModePreserved() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 300, height: 300))
        // Highlight always multiplies against what's below — relational, so
        // the rasterized image layer must keep multiplying to look identical.
        let highlight = annotationLayer(shape: .highlight)
        doc.addLayer(highlight)
        let ref = ImageRef(pixelSize: CGSize(width: 100, height: 60))
        doc.rasterizeLayer(id: highlight.id, rasterized: ref,
                           frame: CGRect(x: 20, y: 30, width: 100, height: 60))
        #expect(doc.layer(id: highlight.id)?.style.blendMode == .multiply)
        #expect(doc.layer(id: highlight.id)?.effectiveBlendMode == .multiply)
    }

    @Test("Rasterizing keeps the layer's stacking slot")
    func keepsStackingSlot() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 300, height: 300))
        let bottom = Layer(name: "Bottom",
                           content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                           frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let mid = annotationLayer()
        let top = Layer(name: "Top",
                        content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                        frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        doc.addLayer(bottom)
        doc.addLayer(mid)
        doc.addLayer(top)

        let ref = ImageRef(pixelSize: CGSize(width: 100, height: 60))
        doc.rasterizeLayer(id: mid.id, rasterized: ref,
                           frame: CGRect(x: 20, y: 30, width: 100, height: 60))
        #expect(doc.index(of: mid.id) == 1)
        #expect(doc.layers.count == 3)
    }
}
