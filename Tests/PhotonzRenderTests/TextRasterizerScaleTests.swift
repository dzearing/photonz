import CoreGraphics
import CoreImage
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Baking a label at the resolution it will be SHOWN at, so zooming past 100%
/// does not blow a document-size picture of the words up into a soft one.
@Suite("Text rasterizer scale")
struct TextRasterizerScaleTests {

    private func sample(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// Share of pixels sitting at an in-between luminance. Sharp glyph edges
    /// resolve to a thin fringe; a picture that has been blown up smears that
    /// fringe across every pixel it now covers.
    private func softness(_ image: CGImage) -> Double {
        let data = sample(image)
        var mid = 0, total = 0
        for i in stride(from: 0, to: data.count, by: 4) {
            let l = Double(data[i]) * 0.3 + Double(data[i + 1]) * 0.59 + Double(data[i + 2]) * 0.11
            total += 1
            if l > 40 && l < 215 { mid += 1 }
        }
        return Double(mid) / Double(total)
    }

    /// Rows/columns the ink occupies, as a fraction of the picture — the shape
    /// the words make, independent of how many pixels it is drawn with.
    private func inkBounds(_ image: CGImage) -> CGRect {
        let data = sample(image)
        let w = image.width, h = image.height
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let l = Double(data[i]) * 0.3 + Double(data[i + 1]) * 0.59 + Double(data[i + 2]) * 0.11
                if l < 128 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return .null }
        return CGRect(x: CGFloat(minX) / CGFloat(w), y: CGFloat(minY) / CGFloat(h),
                      width: CGFloat(maxX - minX + 1) / CGFloat(w),
                      height: CGFloat(maxY - minY + 1) / CGFloat(h))
    }

    private func label() -> TextContent {
        var text = TextContent(string: "Padding 16", fontSize: 18)
        text.colorHex = "#101014"
        return text
    }

    private var box: CGSize { TextRasterizer.naturalSize(label()) }

    @Test func scaleMultipliesThePixelsNotThePoints() throws {
        let image = try #require(TextRasterizer.rasterize(label(), size: box, scale: 3))
        #expect(image.width == Int((box.width * 3).rounded()))
        #expect(image.height == Int((box.height * 3).rounded()))
    }

    @Test func defaultScaleIsWhatItAlwaysWas() throws {
        let plain = try #require(TextRasterizer.rasterize(label(), size: box))
        let one = try #require(TextRasterizer.rasterize(label(), size: box, scale: 1))
        #expect(plain.width == one.width && plain.height == one.height)
        #expect(sample(plain) == sample(one))
    }

    @Test func theWordsSitInTheSamePlaceAtEveryScale() throws {
        let small = try #require(TextRasterizer.rasterize(label(), size: box))
        let big = try #require(TextRasterizer.rasterize(label(), size: box, scale: 4))
        let a = inkBounds(small), b = inkBounds(big)
        #expect(abs(a.minX - b.minX) < 0.02)
        #expect(abs(a.minY - b.minY) < 0.02)
        #expect(abs(a.width - b.width) < 0.02)
        #expect(abs(a.height - b.height) < 0.02)
    }

    @Test func bakingAtTheZoomBeatsBlowingUpTheDocumentSizedPicture() throws {
        let crisp = try #require(TextRasterizer.rasterize(label(), size: box, scale: 4))
        let placed = try #require(TextRasterizer.rasterize(label(), size: box))
        let blownUp = CIImage(cgImage: placed).transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        let soft = try #require(CIContext().createCGImage(blownUp, from: blownUp.extent))
        // The blown-up copy smears its glyph edges over four times the pixels.
        #expect(softness(crisp) < softness(soft) / 2)
    }

    /// Pixels the drawing actually paints, at any scale.
    private func coverage(_ image: CGImage) -> Double {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var on = 0
        for i in stride(from: 3, to: data.count, by: 4) where data[i] > 200 { on += 1 }
        return Double(on) / Double(w * h)
    }

    @Test func aGlyphOutlineSurvivesTheScale() throws {
        let outlined = try #require(TextRasterizer.rasterize(label(), size: box,
                                                             borderWidth: 2, borderColorHex: "#FFFFFF",
                                                             scale: 3))
        let plain = try #require(TextRasterizer.rasterize(label(), size: box, scale: 3))
        // The outline paints around every letter, so more of the box is covered.
        #expect(coverage(outlined) > coverage(plain) * 1.5)
    }

    @Test func nonsenseScalesDrawNothing() {
        #expect(TextRasterizer.rasterize(label(), size: box, scale: 0) == nil)
        #expect(TextRasterizer.rasterize(label(), size: box, scale: -2) == nil)
    }
}
