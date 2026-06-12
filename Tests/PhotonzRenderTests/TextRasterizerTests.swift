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

    @Test func bolderWeightProducesMoreInk() throws {
        let size = CGSize(width: 300, height: 80)
        var ink: [TextWeight: Int] = [:]
        for weight in [TextWeight.regular, .bold] {
            let text = TextContent(string: "Weight", fontSize: 40, colorHex: "#FFFFFF", weight: weight)
            ink[weight] = inkCount(try #require(TextRasterizer.rasterize(text, size: size)),
                                   r: 150...255, g: 150...255, b: 150...255)
        }
        let regular = try #require(ink[.regular])
        let bold = try #require(ink[.bold])
        #expect(regular > 0)
        #expect(Double(bold) > Double(regular) * 1.15,
                "bold strokes should cover noticeably more pixels than regular")
    }

    // MARK: - Natural size

    @Test func naturalSizeGrowsWithContent() {
        let short = TextRasterizer.naturalSize(TextContent(string: "Hi"))
        let long = TextRasterizer.naturalSize(TextContent(string: "Hello, wider world"))
        #expect(short.width > 0)
        #expect(short.height > 0)
        #expect(long.width > short.width)
    }

    @Test func naturalSizeWrapsUnderMaxWidth() {
        let text = TextContent(string: "A reasonably long single line of text", fontSize: 24)
        let unconstrained = TextRasterizer.naturalSize(text)
        let wrapped = TextRasterizer.naturalSize(text, maxWidth: unconstrained.width / 2)
        #expect(wrapped.width <= unconstrained.width / 2 + 1)
        #expect(wrapped.height > unconstrained.height * 1.5, "wrapping should add lines")
    }

    @Test func naturalSizeOfEmptyStringStillHasALineOfHeight() {
        // The inline editor needs a caret-height frame before any typing.
        let size = TextRasterizer.naturalSize(TextContent(string: "", fontSize: 24))
        #expect(size.height >= 24)
    }

    @Test func textRendersWithoutClippingInsideNaturalSize() throws {
        // The frame the builder derives from naturalSize must hold all the ink:
        // rendering into a generous canvas should put no ink outside it.
        let text = TextContent(string: "Clip gj", fontSize: 32, colorHex: "#FFFFFF")
        let natural = TextRasterizer.naturalSize(text)
        let image = try #require(TextRasterizer.rasterize(text, size: natural))
        let inkInside = inkCount(image, r: 150...255, g: 150...255, b: 150...255)

        let padded = try #require(TextRasterizer.rasterize(
            text, size: CGSize(width: natural.width + 40, height: natural.height + 40)))
        let inkTotal = inkCount(padded, r: 150...255, g: 150...255, b: 150...255)
        #expect(Double(inkInside) >= Double(inkTotal) * 0.98,
                "natural size should not clip glyphs (descenders, last column)")
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

    @Test func autoContrastShadowKeepsWhiteTextLegibleOnWhite() {
        // White text on a white screenshot: without the 3.6 auto shadow the
        // render would be pure white; the dark contour must leave visible ink.
        let store = ImageStore()
        let baseContext = CGContext(data: nil, width: 100, height: 100,
                                    bitsPerComponent: 8, bytesPerRow: 400,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        baseContext.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        baseContext.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let base = store.register(baseContext.makeImage()!)

        var doc = PhotonzDocument.withBaseImage(base)
        doc.addLayer(TextBuilder.layer(content: TextContent(string: "XX", fontSize: 40),
                                       at: CGPoint(x: 10, y: 25),
                                       naturalSize: CGSize(width: 80, height: 50)))

        let output = DocumentRenderer().render(doc, store: store)!
        #expect(inkCount(output, r: 0...220, g: 0...220, b: 0...220) > 30,
                "the auto-contrast shadow should darken pixels around the glyphs")
    }
}
