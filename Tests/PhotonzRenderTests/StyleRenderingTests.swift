import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Style rendering")
struct StyleRenderingTests {

    private func solidImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                                     blue: CGFloat(b) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Reads the RGBA value at (x, y) in top-left coordinates.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = (y * width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }

    /// 100x100 base in the given color plus one styled 40x40 blue layer at (30, 30).
    private func renderStyledPatch(style: LayerStyle,
                                   baseColor: (r: UInt8, g: UInt8, b: UInt8) = (255, 0, 0)) -> CGImage {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100,
                                             r: baseColor.r, g: baseColor.g, b: baseColor.b))
        let patch = store.register(solidImage(width: 40, height: 40, r: 0, g: 0, b: 255))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.addLayer(Layer(name: "Patch", content: .image(patch),
                           frame: CGRect(x: 30, y: 30, width: 40, height: 40), style: style))
        return DocumentRenderer().render(doc, store: store)!
    }

    @Test func cornerRadiusClipsCorners() {
        let output = renderStyledPatch(style: LayerStyle(cornerRadius: 12))
        let corner = pixel(output, x: 31, y: 31)
        let edgeMid = pixel(output, x: 50, y: 32)
        let center = pixel(output, x: 50, y: 50)
        #expect(corner.r > 240 && corner.b < 16, "outside the rounded corner the base should show")
        #expect(edgeMid.b > 240, "edge midpoints are inside the rounded rect")
        #expect(center.b > 240, "center stays covered")
    }

    @Test func borderStrokesAtRequestedWidthAndColor() {
        let output = renderStyledPatch(style: LayerStyle(borderWidth: 4, borderColorHex: "#00FF00"))
        let onBorder = pixel(output, x: 32, y: 50)
        let inside = pixel(output, x: 38, y: 50)
        let outside = pixel(output, x: 28, y: 50)
        #expect(onBorder.g > 240 && onBorder.b < 16, "left edge should be the green border")
        #expect(inside.b > 240 && inside.g < 16, "past the 4px border the content shows")
        #expect(outside.r > 240, "the border strokes inside the frame, not outside it")
    }

    @Test func borderFollowsCornerRadius() {
        let output = renderStyledPatch(style: LayerStyle(cornerRadius: 12, borderWidth: 4, borderColorHex: "#00FF00"))
        let corner = pixel(output, x: 31, y: 31)
        let edgeMid = pixel(output, x: 50, y: 32)
        #expect(corner.r > 240, "square corner stays clipped even with a border")
        #expect(edgeMid.g > 240 && edgeMid.b < 16, "border hugs the rounded outline")
    }

    @Test func shadowDarkensBelowRightOfLayer() {
        let style = LayerStyle(shadow: ShadowStyle(radius: 4, offset: CGSize(width: 8, height: 8),
                                                   colorHex: "#000000", opacity: 0.8))
        let output = renderStyledPatch(style: style, baseColor: (255, 255, 255))
        let belowRight = pixel(output, x: 74, y: 74)
        let aboveLeft = pixel(output, x: 25, y: 25)
        let center = pixel(output, x: 50, y: 50)
        #expect(belowRight.r < 200 && belowRight.g < 200, "shadow should darken below-right of the patch")
        #expect(aboveLeft.r > 240, "no shadow above-left of the patch")
        #expect(center.b > 240, "shadow renders under the layer, not over it")
    }

    @Test func shadowDefaultOffsetFallsBelow() {
        // Default ShadowStyle: radius 12, offset (0, 4) — i.e. downward in model coords.
        let style = LayerStyle(shadow: ShadowStyle())
        let output = renderStyledPatch(style: style, baseColor: (255, 255, 255))
        let below = pixel(output, x: 50, y: 76)
        let above = pixel(output, x: 50, y: 24)
        #expect(below.r < above.r, "shadow should be stronger below the layer than above it")
    }
}
