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

    /// And the move is invisible: a box saved with a stroke of its own opens
    /// with that stroke as a Border in its Effects list, painting exactly the
    /// pixels it painted before (`OutlineRetirement.swift`).
    @Test func aSavedStrokeOpensAsABorderAndLooksTheSame() throws {
        // Written the way a document before the retirement holds it: a stroke
        // on the shape and nothing in the Effects list.
        var saved = box(strokeWidth: 0, colorHex: "#0000FF", style: LayerStyle())
        var annotation = try #require(saved.annotation)
        annotation.strokeWidth = 6
        saved.content = .annotation(annotation)
        saved.style.effects = []
        // What the old renderer drew for it: the shape's own stroke.
        let before = rendered(saved)

        let opened = saved.retiringItsOutline()
        #expect(opened.annotation?.strokeWidth == 0)
        #expect(opened.style.borderEffects.first?.width == 6)
        #expect(rendered(opened) == before)
    }

    /// The same for an oval, whose ring has followed the oval since 2026-09-08
    /// (`RingShape.swift`) — which is the whole reason its outline could retire
    /// at all.
    @Test func anOvalsSavedStrokeOpensAsABorderAndLooksTheSame() throws {
        var saved = Layer(name: "Oval",
                          content: .annotation(AnnotationContent(shape: .ellipse,
                                                                 strokeWidth: 0,
                                                                 colorHex: "#0000FF",
                                                                 start: .zero,
                                                                 end: CGPoint(x: 100, y: 60))),
                          frame: CGRect(x: 20, y: 20, width: 100, height: 60))
        var annotation = try #require(saved.annotation)
        annotation.strokeWidth = 6
        saved.content = .annotation(annotation)
        let before = rendered(saved)

        let opened = saved.retiringItsOutline()
        #expect(opened.annotation?.strokeWidth == 0)
        #expect(rendered(opened) == before)
    }
}

/// A label's edge is a Border like every other layer's, and on a label it
/// follows the LETTERS rather than the box — which is what the ring stored on
/// the style always did there (`OutlineRetirement.swift`).
@Suite("A label's border outlines its letters")
struct LabelBorderRenderTests {

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

    private func rendered(_ layer: Layer) -> (pixels: [UInt8], width: Int) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 200, height: 90))
        doc.addLayer(layer)
        let image = DocumentRenderer().render(doc, store: ImageStore())!
        return (pixels(image), image.width)
    }

    private func label(_ style: LayerStyle) -> Layer {
        var text = TextContent(string: "Hi", fontSize: 40, colorHex: "#FFFFFF")
        text.weight = .bold
        return Layer(name: "Label", content: .text(text),
                     frame: CGRect(x: 20, y: 20, width: 160, height: 50), style: style)
    }

    private func isRed(_ p: [UInt8], _ w: Int, _ x: Int, _ y: Int) -> Bool {
        let i = (y * w + x) * 4
        return p[i] > 180 && p[i + 1] < 90 && p[i + 2] < 90
    }

    @Test("A border on a label puts ink round the letters and none round the box")
    func outlinesTheLetters() {
        var style = LayerStyle()
        style.borderWidth = 4
        style.borderColorHex = "#FF0000"
        let out = rendered(label(style))
        // The layer's box runs from 20,20 to 180,70. Its corners stay clear: a
        // ring round the box would paint them.
        #expect(!isRed(out.pixels, out.width, 22, 22))
        #expect(!isRed(out.pixels, out.width, 178, 68))
        // ...and somewhere along the first letter there IS red, because the
        // outline follows the glyphs.
        let ink = (20..<70).contains { y in (20..<90).contains { x in isRed(out.pixels, out.width, x, y) } }
        #expect(ink, "the letters should be outlined")
    }
}
