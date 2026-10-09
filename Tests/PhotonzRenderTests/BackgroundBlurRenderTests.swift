import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A background blur softens what is BEHIND a shape, wherever the shape is,
/// and leaves everything else on the canvas exactly as sharp as it was.
@Suite("Background blur rendering")
struct BackgroundBlurRenderTests {

    /// Alternating black and white columns one point wide: anything that
    /// averages a neighbourhood turns this into flat grey.
    private func stripeImage(size: Int) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size,
                                bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        for x in stride(from: 0, to: size, by: 2) {
            context.fill(CGRect(x: x, y: 0, width: 1, height: size))
        }
        return context.makeImage()!
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    /// How far apart the red of two side-by-side pixels on a row is: big on
    /// sharp stripes, near nothing once they are blurred.
    private func stripeContrast(_ data: [UInt8], width: Int, x: Int, y: Int) -> Int {
        let a = Int(data[(y * width + x) * 4])
        let b = Int(data[(y * width + x + 1) * 4])
        return abs(a - b)
    }

    private func document(_ store: ImageStore, glass: LayerStyle) -> PhotonzDocument {
        var doc = PhotonzDocument.withBaseImage(store.register(stripeImage(size: 200)))
        doc.canvasSize = CGSize(width: 200, height: 200)
        var annotation = AnnotationContent(shape: .rectangle, start: .zero,
                                           end: CGPoint(x: 100, y: 60))
        annotation.strokeWidth = 0
        annotation.cornerRadius = 30
        annotation.fillColorHex = "#FFFFFF"
        doc.addLayer(Layer(name: "Glass", content: .annotation(annotation),
                           frame: CGRect(x: 50, y: 70, width: 100, height: 60), style: glass))
        return doc
    }

    private func glass(opacity: Double, radius: CGFloat = 6) -> LayerStyle {
        var style = LayerStyle(opacity: opacity)
        style.effects = [.blur(BlurEffect(radius: radius, kind: .background))]
        return style
    }

    /// The Secondary button's recipe: white at 74% over glass. Without the
    /// glass the stripes show through a quarter strength; with it they are
    /// gone, and outside the shape they are as sharp as ever.
    @Test func theStripesBehindTheGlassAreSoftened() {
        let store = ImageStore()
        let plain = DocumentRenderer().render(document(store, glass: LayerStyle(opacity: 0.74)), store: store)!
        let frosted = DocumentRenderer().render(document(store, glass: glass(opacity: 0.74)), store: store)!
        let before = pixels(plain)
        let after = pixels(frosted)
        #expect(stripeContrast(before, width: 200, x: 100, y: 100) > 20,
                "a translucent shape alone lets the stripes through sharp")
        #expect(stripeContrast(after, width: 200, x: 100, y: 100) < 6,
                "glass softens them to an even grey")
        #expect(stripeContrast(after, width: 200, x: 20, y: 20) > 200,
                "outside the shape the canvas is untouched")
        // Still the white tint over it: brighter than the bare stripes' grey.
        #expect(after[(100 * 200 + 100) * 4] > 170)
    }

    /// The layer's Opacity fades its paint, not its glass: a clear pane with
    /// a blur on it is a frosted pane.
    @Test func aClearPaneStillFrosts() {
        let store = ImageStore()
        let image = DocumentRenderer().render(document(store, glass: glass(opacity: 0)), store: store)!
        let data = pixels(image)
        #expect(stripeContrast(data, width: 200, x: 100, y: 100) < 6)
        let grey = Int(data[(100 * 200 + 100) * 4])
        #expect(grey > 60 && grey < 200, "the stripes averaged, not painted white — got \(grey)")
    }

    /// The glass follows the shape's own outline: just outside a rounded
    /// corner the stripes are still sharp.
    @Test func theGlassStopsAtTheShapesEdge() {
        let store = ImageStore()
        let data = pixels(DocumentRenderer().render(document(store, glass: glass(opacity: 0)), store: store)!)
        // The top-left corner of the box is (50, 70) and its radius 30, so
        // (52, 72) is outside the curve.
        #expect(stripeContrast(data, width: 200, x: 52, y: 72) > 200)
        // ...and just inside the straight top edge it is glass.
        #expect(stripeContrast(data, width: 200, x: 100, y: 73) < 20)
    }

    /// The mock's glass keeps colour alive (`--lg-blur-sm`, `saturate(180%)`
    /// beside the blur): a muted colour behind the pane comes through richer,
    /// not washed towards grey.
    @Test func theGlassKeepsTheColourBehindIt() {
        let store = ImageStore()
        let context = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8,
                                bytesPerRow: 800, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.7, green: 0.45, blue: 0.45, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        var doc = PhotonzDocument.withBaseImage(store.register(context.makeImage()!))
        doc.canvasSize = CGSize(width: 200, height: 200)
        var annotation = AnnotationContent(shape: .rectangle, start: .zero, end: CGPoint(x: 100, y: 60))
        annotation.strokeWidth = 0
        annotation.fillColorHex = "#FFFFFF"
        doc.addLayer(Layer(name: "Glass", content: .annotation(annotation),
                           frame: CGRect(x: 50, y: 70, width: 100, height: 60), style: glass(opacity: 0)))
        let data = pixels(DocumentRenderer().render(doc, store: store)!)
        let inside = (100 * 200 + 100) * 4
        let outside = (20 * 200 + 20) * 4
        let spreadIn = Int(data[inside]) - Int(data[inside + 1])
        let spreadOut = Int(data[outside]) - Int(data[outside + 1])
        #expect(spreadIn > spreadOut + 15, "richer behind the glass: \(spreadIn) against \(spreadOut)")
    }

    /// Switched off, the glass draws nothing at all.
    @Test func offIsOff() {
        let store = ImageStore()
        var style = LayerStyle(opacity: 0)
        style.effects = [.blur(BlurEffect(radius: 6, isOn: false, kind: .background))]
        let data = pixels(DocumentRenderer().render(document(store, glass: style), store: store)!)
        #expect(stripeContrast(data, width: 200, x: 100, y: 100) > 200)
    }

    /// Inside a component or a screen the glass sees the canvas under the
    /// group, not just the group's own pieces.
    @Test func glassInsideAGroupSeesTheCanvas() {
        let store = ImageStore()
        var doc = document(store, glass: glass(opacity: 0.74))
        guard let shape = doc.layers.last else { Issue.record("no shape"); return }
        doc.layers.removeLast()
        var group = GroupContent(children: [shape])
        group.layout = nil
        // A faded group is one picture, drawn into its own buffer.
        doc.addLayer(Layer(name: "Card", content: .group(group), frame: .zero,
                           style: LayerStyle(opacity: 0.99)))
        let data = pixels(DocumentRenderer().render(doc, store: store)!)
        #expect(stripeContrast(data, width: 200, x: 100, y: 100) < 6)
        #expect(stripeContrast(data, width: 200, x: 20, y: 20) > 200)
    }

    /// An export at 2x draws the same picture as the canvas, twice as big:
    /// the glass is just as soft.
    @Test func anExportAtTwiceTheSizeIsJustAsSoft() {
        let store = ImageStore()
        let doc = document(store, glass: glass(opacity: 0.74))
        let one = pixels(DocumentRenderer().render(doc, store: store)!)
        let two = DocumentRenderer().render(doc, store: store, scale: 2)!
        #expect(two.width == 400)
        let data = pixels(two)
        #expect(stripeContrast(data, width: 400, x: 200, y: 200) < 6)
        let a = Int(one[(100 * 200 + 100) * 4])
        let b = Int(data[(200 * 400 + 200) * 4])
        #expect(abs(a - b) < 8, "the same tint at both sizes — \(a) against \(b)")
    }
}
