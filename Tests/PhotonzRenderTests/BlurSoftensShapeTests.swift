import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A blur is meant to SOFTEN a layer: its edges go fuzzy and the softness
/// spreads past the layer's box the way a shadow does. It used to be applied
/// with the picture clamped to its own box, which meant a solid rectangle came
/// back byte-for-byte identical (nothing to fade into) and a circle's halo was
/// sliced off square at the drag box.
@Suite("Blur softens a shape")
struct BlurSoftensShapeTests {

    private let canvas = CGSize(width: 300, height: 300)
    private let box = CGRect(x: 100, y: 100, width: 100, height: 100)

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let i = (y * image.width + x) * 4
        guard i + 3 < data.count else { return (0, 0, 0, 0) }
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]), Int(data[i + 3]))
    }

    /// Every alpha value in the picture, top-left indexed.
    private func alphaMap(_ image: CGImage) -> [Int] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 3, to: data.count, by: 4).map { Int(data[$0]) }
    }

    private func shape(_ kind: AnnotationShape, strokeWidth: CGFloat = 0,
                       filled: Bool = true, blur: CGFloat) -> Layer {
        var content = AnnotationContent(shape: kind, strokeWidth: strokeWidth,
                                        colorHex: "#FF0000",
                                        start: .zero,
                                        end: CGPoint(x: box.width, y: box.height))
        if filled { content.fillColorHex = "#FF0000" }
        var style = LayerStyle()
        style.blurRadius = blur
        return Layer(name: "Shape", content: .annotation(content), frame: box, style: style)
    }

    private func render(_ layer: Layer) -> CGImage {
        var doc = PhotonzDocument(canvasSize: canvas)
        doc.addLayer(layer)
        return DocumentRenderer().render(doc, store: ImageStore())!
    }

    @Test("A blurred rectangle's edge goes soft instead of staying a hard cut")
    func rectangleEdgeSoftens() {
        let sharp = render(shape(.rectangle, blur: 0))
        let soft = render(shape(.rectangle, blur: 8))

        // Sharp: the left edge is a cut — nothing at all one point out, solid
        // one point in.
        #expect(pixel(sharp, Int(box.minX) - 2, Int(box.midY)).a < 8)
        #expect(pixel(sharp, Int(box.minX) + 2, Int(box.midY)).a > 247)

        // Soft: the same edge is a ramp. Half-ish on the line, still some ink
        // well outside it, and no longer solid just inside.
        let onEdge = pixel(soft, Int(box.minX), Int(box.midY)).a
        let outside = pixel(soft, Int(box.minX) - 8, Int(box.midY)).a
        let justInside = pixel(soft, Int(box.minX) + 2, Int(box.midY)).a
        #expect((80...180).contains(onEdge), "alpha on the edge was \(onEdge), expected about half")
        #expect(outside > 8, "8pt outside the edge had alpha \(outside), expected some spill")
        #expect(justInside < 245, "2pt inside was \(justInside), expected a ramp not a wall")
        // The middle of the box is untouched: a blur softens edges, it does not
        // wash the shape out.
        #expect(pixel(soft, Int(box.midX), Int(box.midY)).a > 250)
    }

    @Test("A blurred ellipse fades out in every direction, not cut off at the drag box")
    func ellipseHaloIsNotClipped() {
        let soft = render(shape(.ellipse, blur: 8))
        // Past the box on all four sides, on the axes where the ellipse touches.
        #expect(pixel(soft, Int(box.minX) - 6, Int(box.midY)).a > 8, "left")
        #expect(pixel(soft, Int(box.maxX) + 6, Int(box.midY)).a > 8, "right")
        #expect(pixel(soft, Int(box.midX), Int(box.minY) - 6).a > 8, "top")
        #expect(pixel(soft, Int(box.midX), Int(box.maxY) + 6).a > 8, "bottom")
        // And it really is a fade: further out is fainter.
        let near = pixel(soft, Int(box.minX) - 4, Int(box.midY)).a
        let far = pixel(soft, Int(box.minX) - 14, Int(box.midY)).a
        #expect(near > far, "the halo should thin out: \(near) at 4pt, \(far) at 14pt")
    }

    @Test("Turning the blur off puts the shape back exactly as it was")
    func blurOffIsUntouched() {
        let plain = render(shape(.rectangle, blur: 0))
        var noBlurStyle = shape(.rectangle, blur: 8)
        noBlurStyle.style.blurRadius = 0
        let switchedOff = render(noBlurStyle)
        #expect(alphaMap(plain) == alphaMap(switchedOff))
    }

    /// The carve-out, and the reason for it: a capture's pixels ARE the
    /// picture. Softening a screenshot must not leave a pale rim round the
    /// canvas where the blur faded into nothing.
    @Test("Blurring a photo softens the picture without eating its edge")
    func photoKeepsItsEdge() {
        let store = ImageStore()
        let context = CGContext(data: nil, width: 300, height: 300, bitsPerComponent: 8,
                                bytesPerRow: 300 * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0, green: 0.4, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        let capture = store.register(context.makeImage()!)

        var doc = PhotonzDocument.withBaseImage(capture)
        doc.updateLayer(id: doc.layers[0].id) { $0.style.blurRadius = 10 }
        guard let output = DocumentRenderer().render(doc, store: store) else {
            Issue.record("render returned nil")
            return
        }
        for point in [(1, 1), (298, 1), (1, 298), (298, 298), (150, 0), (0, 150)] {
            let p = pixel(output, point.0, point.1)
            #expect(p.a > 250, "corner/edge \(point) came back at alpha \(p.a): a blurred capture must not fade out at the canvas edge")
        }
    }

    @Test("An arrow still blurs, and its halo is no longer clipped either")
    func arrowStillBlurs() {
        let sharp = render(shape(.arrow, strokeWidth: 6, filled: false, blur: 0))
        let soft = render(shape(.arrow, strokeWidth: 6, filled: false, blur: 8))
        let sharpInk = alphaMap(sharp).filter { $0 > 8 }.count
        let softInk = alphaMap(soft).filter { $0 > 8 }.count
        #expect(softInk > sharpInk, "a blurred arrow covers more ground: \(softInk) vs \(sharpInk)")
    }
}
