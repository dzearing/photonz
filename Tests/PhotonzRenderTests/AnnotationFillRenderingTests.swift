import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Annotation fill rendering")
struct AnnotationFillRenderingTests {

    /// Reads RGBA at (x, y) in top-left coordinates.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = (y * width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }

    private func rasterize(_ shape: AnnotationShape, fill: String?,
                           cornerRadius: CGFloat = 0) -> CGImage {
        var content = AnnotationContent(shape: shape, strokeWidth: 4, colorHex: "#FF0000",
                                        cornerRadius: cornerRadius, fillColorHex: fill)
        content.start = CGPoint(x: 10, y: 10)
        content.end = CGPoint(x: 110, y: 90)
        return AnnotationRasterizer.rasterize(content, size: CGSize(width: 120, height: 100))!
    }

    @Test func filledRectanglePaintsInteriorAndKeepsStroke() {
        let img = rasterize(.rectangle, fill: "#0000FF")
        let interior = pixel(img, x: 60, y: 50)
        #expect(interior.b > 200 && interior.r < 80, "interior takes the fill color")
        let edge = pixel(img, x: 12, y: 50)
        #expect(edge.r > 200 && edge.b < 80, "stroke keeps its own color")
        #expect(pixel(img, x: 3, y: 3).a == 0, "outside stays transparent")
    }

    @Test func noFillLeavesTheInteriorTransparent() {
        let img = rasterize(.rectangle, fill: nil)
        #expect(pixel(img, x: 60, y: 50).a == 0)
        let rounded = rasterize(.rectangle, fill: nil, cornerRadius: 12)
        #expect(pixel(rounded, x: 60, y: 50).a == 0)
    }

    @Test func filledEllipsePaintsInsideTheOvalOnly() {
        let img = rasterize(.ellipse, fill: "#0000FF")
        let center = pixel(img, x: 60, y: 50)
        #expect(center.b > 200 && center.r < 80, "ellipse center takes the fill")
        #expect(pixel(img, x: 13, y: 13).a == 0, "box corner outside the oval stays clear")
    }

    @Test func zeroRadiusRectangleHasSharpCorners() {
        // A thick stroke with ROUND line joins fakes a corner radius the
        // inspector doesn't show (reads 0 while the shape looks rounded).
        // Rectangles must stroke with miter joins: at radius 0 the stroke's
        // outer corner is square, so the box's own corner pixel is painted.
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 16, colorHex: "#FF0000")
        content.start = CGPoint(x: 20, y: 20)
        content.end = CGPoint(x: 100, y: 80)
        let img = AnnotationRasterizer.rasterize(content, size: CGSize(width: 120, height: 100))!
        #expect(pixel(img, x: 21, y: 21).a > 200, "outer stroke corner is square, not rounded off")
    }

    @Test func roundedRectangleFillFollowsTheCorners() {
        let img = rasterize(.rectangle, fill: "#0000FF", cornerRadius: 20)
        let center = pixel(img, x: 60, y: 50)
        #expect(center.b > 200, "rounded interior filled")
        #expect(pixel(img, x: 13, y: 13).a == 0, "sharp corner clipped away by the radius")
    }
}
