import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A paint layer draws its strokes where they went, in their colour, with a
/// soft round tip, and nothing else (`docs/design/brushes.md`, slice 1). Oil
/// paint still paints with that tip until its own slice; the dry media, the
/// marker and the airbrush have theirs (`DryMediaRenderingTests`,
/// `MarkerAirbrushRenderingTests`).
@Suite("Paint rendering")
struct PaintRenderingTests {

    private func bytes(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let data = bytes(image)
        let offset = (y * image.width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }

    private func white(_ size: Int) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()!
    }

    private func stroke(from a: CGPoint, to b: CGPoint, size: Double = 10, opacity: Double = 100,
                        hex: String = "#0000FF") -> BrushStroke {
        var settings = BrushSettings(medium: .oil)
        settings.set("size", to: size)
        settings.set("opacity", to: opacity)
        return BrushStroke(samples: [StrokeSample(point: a, ms: 0), StrokeSample(point: b, ms: 16)],
                           settings: settings, colorHex: hex, seed: 3)
    }

    @Test func aStrokePaintsAlongItsLineAndNowhereElse() throws {
        let paint = PaintContent(strokes: [stroke(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 90, y: 50))])
        let image = try #require(PaintRasterizer.rasterize(paint, size: CGSize(width: 100, height: 100)))
        let middle = pixel(image, x: 50, y: 50)
        #expect(middle.a == 255 && middle.b == 255 && middle.r == 0, "solid on the line")
        #expect(pixel(image, x: 50, y: 20).a == 0, "untouched off it")
        // The edge is soft: half way out the tip is partly covered.
        let edge = pixel(image, x: 50, y: 54)
        #expect(edge.a > 0 && edge.a < 255)
    }

    @Test func opacityIsTheWholeStrokesNotEachDabs() throws {
        let paint = PaintContent(strokes: [stroke(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 90, y: 50),
                                                  opacity: 50)])
        let image = try #require(PaintRasterizer.rasterize(paint, size: CGSize(width: 100, height: 100)))
        // Dozens of dabs overlap in the middle and it is still half covered.
        let middle = Int(pixel(image, x: 50, y: 50).a)
        #expect(abs(middle - 128) <= 3)
    }

    @Test func aSecondStrokeBuildsOnTheFirst() throws {
        let one = stroke(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 90, y: 50), opacity: 50)
        let two = stroke(from: CGPoint(x: 50, y: 10), to: CGPoint(x: 50, y: 90), opacity: 50)
        let image = try #require(PaintRasterizer.rasterize(PaintContent(strokes: [one, two]),
                                                           size: CGSize(width: 100, height: 100)))
        #expect(pixel(image, x: 50, y: 50).a > pixel(image, x: 20, y: 50).a)
    }

    @Test func aPaintLayerCompositesAboveThePictureAndReopensIdentically() throws {
        let store = ImageStore()
        let base = store.register(white(120))
        var doc = PhotonzDocument.withBaseImage(base)
        let baseID = try #require(doc.layers.first?.id)
        doc.paintStroke(stroke(from: CGPoint(x: 20, y: 60), to: CGPoint(x: 100, y: 60), hex: "#FF0000"),
                        onto: baseID)
        let image = try #require(DocumentRenderer().render(doc, store: store))
        let on = pixel(image, x: 60, y: 60)
        #expect(on.r == 255 && on.g == 0 && on.b == 0)
        let off = pixel(image, x: 60, y: 20)
        #expect(off.r == 255 && off.g == 255 && off.b == 255, "the picture shows where nothing was painted")
        let reopened = try JSONDecoder().decode(PhotonzDocument.self, from: JSONEncoder().encode(doc))
        let again = try #require(DocumentRenderer().render(reopened, store: store))
        #expect(bytes(again) == bytes(image))
    }
}
