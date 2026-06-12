import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("TextRasterizer")
struct TextRasterizerTests {

    /// Counts pixels whose color is close to the given RGB with meaningful alpha.
    private func inkCount(_ image: CGImage, r: ClosedRange<UInt8>, g: ClosedRange<UInt8>, b: ClosedRange<UInt8>) -> Int {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for i in stride(from: 0, to: data.count, by: 4) where data[i + 3] > 200 {
            if r.contains(data[i]) && g.contains(data[i + 1]) && b.contains(data[i + 2]) {
                count += 1
            }
        }
        return count
    }

    @Test func rendersInkAtRequestedSize() throws {
        let text = TextContent(string: "Hello", fontSize: 32, colorHex: "#FFFFFF")
        let image = try #require(TextRasterizer.rasterize(text, size: CGSize(width: 200, height: 60)))
        #expect(image.width == 200)
        #expect(image.height == 60)
        #expect(inkCount(image, r: 200...255, g: 200...255, b: 200...255) > 50,
                "white glyphs should cover a meaningful pixel area")
    }

    @Test func respectsColor() throws {
        let text = TextContent(string: "Hello", fontSize: 32, colorHex: "#FF0000")
        let image = try #require(TextRasterizer.rasterize(text, size: CGSize(width: 200, height: 60)))
        #expect(inkCount(image, r: 200...255, g: 0...60, b: 0...60) > 50, "ink should be red")
        #expect(inkCount(image, r: 0...60, g: 200...255, b: 0...60) == 0, "no stray green ink")
    }

    @Test func largerFontProducesMoreInk() throws {
        let small = TextContent(string: "A", fontSize: 12, colorHex: "#FFFFFF")
        let large = TextContent(string: "A", fontSize: 48, colorHex: "#FFFFFF")
        let size = CGSize(width: 100, height: 100)
        let smallInk = inkCount(try #require(TextRasterizer.rasterize(small, size: size)),
                                r: 200...255, g: 200...255, b: 200...255)
        let largeInk = inkCount(try #require(TextRasterizer.rasterize(large, size: size)),
                                r: 200...255, g: 200...255, b: 200...255)
        #expect(smallInk > 0)
        #expect(largeInk > smallInk * 4, "ink area should grow roughly with the square of font size")
    }

    @Test func emptyStringRendersNoInk() throws {
        let text = TextContent(string: "", fontSize: 32, colorHex: "#FFFFFF")
        let image = try #require(TextRasterizer.rasterize(text, size: CGSize(width: 100, height: 40)))
        #expect(inkCount(image, r: 0...255, g: 0...255, b: 0...255) == 0)
    }

    @Test func zeroSizeReturnsNil() {
        let text = TextContent(string: "Hi", fontSize: 32)
        #expect(TextRasterizer.rasterize(text, size: .zero) == nil)
    }

    @Test func textLayerCompositesIntoDocument() {
        // End-to-end: a text layer renders ink inside its frame region.
        let store = ImageStore()
        let baseContext = CGContext(data: nil, width: 100, height: 100,
                                    bitsPerComponent: 8, bytesPerRow: 400,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        baseContext.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        baseContext.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let base = store.register(baseContext.makeImage()!)

        var doc = PhotonzDocument.withBaseImage(base)
        doc.addLayer(Layer(name: "Text",
                           content: .text(TextContent(string: "XX", fontSize: 40, colorHex: "#FF0000")),
                           frame: CGRect(x: 10, y: 25, width: 80, height: 50)))

        let output = DocumentRenderer().render(doc, store: store)!
        #expect(inkCount(output, r: 200...255, g: 0...60, b: 0...60) > 50,
                "red glyph ink should appear in the composited document")
    }
}
