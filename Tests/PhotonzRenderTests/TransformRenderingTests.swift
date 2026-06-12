import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Transform rendering")
struct TransformRenderingTests {

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

    /// First half blue, second half green. `horizontal: true` splits left/right;
    /// `false` splits top/bottom (blue on top, in visual top-left terms).
    private func twoToneImage(width: Int, height: Int, horizontal: Bool) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let blue = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        let green = CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        if horizontal {
            context.setFillColor(blue)
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            context.setFillColor(green)
            context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        } else {
            // CGContext origin is bottom-left: the upper half (visually) is y >= height/2.
            context.setFillColor(blue)
            context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
            context.setFillColor(green)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        }
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

    /// Red 100x100 base plus one transformed layer.
    private func renderOneLayer(content: CGImage, frame: CGRect, transform: LayerTransform) -> CGImage {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100, r: 255, g: 0, b: 0))
        let patch = store.register(content)
        var doc = PhotonzDocument.withBaseImage(base)
        doc.addLayer(Layer(name: "Patch", content: .image(patch), frame: frame, transform: transform))
        return DocumentRenderer().render(doc, store: store)!
    }

    @Test func quarterTurnMakesHorizontalBarVertical() {
        // 60x20 bar centered at (50, 50) becomes a 20x60 vertical bar.
        let output = renderOneLayer(content: solidImage(width: 60, height: 20, r: 0, g: 0, b: 255),
                                    frame: CGRect(x: 20, y: 40, width: 60, height: 20),
                                    transform: LayerTransform(rotation: .pi / 2))
        let above = pixel(output, x: 50, y: 30)
        let below = pixel(output, x: 50, y: 70)
        let left = pixel(output, x: 30, y: 50)
        #expect(above.b > 240, "bar should now extend above center")
        #expect(below.b > 240, "bar should now extend below center")
        #expect(left.r > 240 && left.b < 16, "old horizontal extent should be base red again")
    }

    @Test func rotationIsClockwiseOnScreen() {
        // Left half of the bar is blue; after a clockwise quarter turn it points up.
        let output = renderOneLayer(content: twoToneImage(width: 60, height: 20, horizontal: true),
                                    frame: CGRect(x: 20, y: 40, width: 60, height: 20),
                                    transform: LayerTransform(rotation: .pi / 2))
        let top = pixel(output, x: 50, y: 30)
        let bottom = pixel(output, x: 50, y: 70)
        #expect(top.b > 240 && top.g < 16, "blue (left) end should rotate to the top")
        #expect(bottom.g > 240 && bottom.b < 16, "green (right) end should rotate to the bottom")
    }

    @Test func flipHorizontalMirrorsContent() {
        let output = renderOneLayer(content: twoToneImage(width: 40, height: 40, horizontal: true),
                                    frame: CGRect(x: 30, y: 30, width: 40, height: 40),
                                    transform: LayerTransform(flipHorizontal: true))
        let left = pixel(output, x: 35, y: 50)
        let right = pixel(output, x: 65, y: 50)
        #expect(left.g > 240 && left.b < 16, "green half should now be on the left")
        #expect(right.b > 240 && right.g < 16, "blue half should now be on the right")
    }

    @Test func flipVerticalMirrorsContent() {
        let output = renderOneLayer(content: twoToneImage(width: 40, height: 40, horizontal: false),
                                    frame: CGRect(x: 30, y: 30, width: 40, height: 40),
                                    transform: LayerTransform(flipVertical: true))
        let top = pixel(output, x: 50, y: 35)
        let bottom = pixel(output, x: 50, y: 65)
        #expect(top.g > 240 && top.b < 16, "green half should now be on top")
        #expect(bottom.b > 240 && bottom.g < 16, "blue half should now be on the bottom")
    }

    @Test func positiveSkewXSlantsBottomEdgeRight() {
        // tan(π/4) = 1: rows 16px below center shift right by 16.
        let output = renderOneLayer(content: solidImage(width: 40, height: 40, r: 0, g: 0, b: 255),
                                    frame: CGRect(x: 30, y: 30, width: 40, height: 40),
                                    transform: LayerTransform(skewX: .pi / 4))
        let bottomRight = pixel(output, x: 80, y: 66)
        let topRight = pixel(output, x: 80, y: 34)
        let topLeft = pixel(output, x: 20, y: 34)
        #expect(bottomRight.b > 240, "bottom rows should shift right past the original extent")
        #expect(topRight.r > 240 && topRight.b < 16, "top rows shift left, leaving base red here")
        #expect(topLeft.b > 240, "top rows should shift left past the original extent")
    }

    @Test func transformedLayerStaysCenteredOnFrameCenter() {
        // A square rotated 45° keeps its center; corners poke out diagonally.
        let output = renderOneLayer(content: solidImage(width: 40, height: 40, r: 0, g: 0, b: 255),
                                    frame: CGRect(x: 30, y: 30, width: 40, height: 40),
                                    transform: LayerTransform(rotation: .pi / 4))
        let center = pixel(output, x: 50, y: 50)
        let aboveCenter = pixel(output, x: 50, y: 24)
        let oldCorner = pixel(output, x: 33, y: 33)
        #expect(center.b > 240, "center should remain covered")
        #expect(aboveCenter.b > 240, "rotated corner should extend above the old top edge")
        #expect(oldCorner.r > 240 && oldCorner.b < 16, "old corner should be uncovered after rotation")
    }
}
