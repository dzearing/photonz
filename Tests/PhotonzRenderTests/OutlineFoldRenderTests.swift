import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The line round a shape is ONE ring however it is stored, which is what let
/// the old Border slider silently cover the shape's own stroke. These pin that
/// down in pixels: the two ways of drawing it land in the same place, and
/// folding an old border onto the stroke leaves the box looking exactly as it
/// did.
@Suite("Outline fold rendering")
struct OutlineFoldRenderTests {

    private func white(_ w: Int, _ h: Int) -> CGImage {
        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()!
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private func box(strokeWidth: CGFloat, colorHex: String, style: LayerStyle) -> Layer {
        Layer(name: "Box",
              content: .annotation(AnnotationContent(shape: .rectangle,
                                                     strokeWidth: strokeWidth,
                                                     colorHex: colorHex,
                                                     start: .zero,
                                                     end: CGPoint(x: 100, y: 60))),
              frame: CGRect(x: 20, y: 20, width: 100, height: 60),
              style: style)
    }

    private func rendered(_ layer: Layer) -> [UInt8] {
        let store = ImageStore()
        let base = store.register(white(160, 100))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.addLayer(layer)
        return pixels(DocumentRenderer().render(doc, store: store)!)
    }

    private var blueBorder: LayerStyle {
        var style = LayerStyle()
        style.borderWidth = 6
        style.borderColorHex = "#0000FF"
        return style
    }

    /// Why there was ever anything to fix: at the same width the two rings are
    /// the same pixels, so the panel was offering one thing twice.
    @Test func aStrokeAndABorderOfTheSameWidthPaintTheSameRing() {
        let stroked = rendered(box(strokeWidth: 6, colorHex: "#0000FF", style: LayerStyle()))
        let bordered = rendered(box(strokeWidth: 0, colorHex: "#FF0000", style: blueBorder))
        #expect(stroked == bordered)
    }

    /// And the fold is invisible: a box drawn before this change looks the same
    /// after its old border has been moved onto its stroke.
    @Test func foldingAnOldBorderOntoTheStrokeChangesNothingOnScreen() {
        let legacy = box(strokeWidth: 0, colorHex: "#FF0000", style: blueBorder)
        let before = rendered(legacy)

        var doc = PhotonzDocument(canvasSize: CGSize(width: 160, height: 100))
        doc.addLayer(legacy)
        doc.setOutlineWidth(layerIDs: [legacy.id], to: 6)
        let folded = doc.layer(id: legacy.id)!
        #expect(folded.style.borderWidth == 0)
        #expect(rendered(folded) == before)
    }
}
