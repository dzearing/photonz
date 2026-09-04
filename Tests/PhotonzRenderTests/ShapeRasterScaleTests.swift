import CoreGraphics
import CoreImage
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Everything drawn from shapes and type — a caliper's number, an arrow's
/// caption, a box's stroke — baked at the resolution it will be SHOWN at, the
/// way a label already is. Zooming in used to blow a document-sized picture of
/// them up, so they went soft standing next to sharp words.
@Suite("Shape raster scale")
struct ShapeRasterScaleTests {

    // MARK: - Measuring sharpness

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

    /// Share of neighbouring pixel pairs that swing hard from one to the next.
    /// A sharp edge makes that jump in a single step; a picture blown up four
    /// times spreads the same jump over four gentle ones, so this collapses.
    private func hardEdges(_ image: CGImage) -> Double {
        let data = sample(image)
        let w = image.width, h = image.height
        var hard = 0
        for y in 0..<h {
            for x in 1..<w {
                let i = (y * w + x) * 4, j = (y * w + x - 1) * 4
                let a = Double(data[i]) * 0.3 + Double(data[i + 1]) * 0.59 + Double(data[i + 2]) * 0.11
                let b = Double(data[j]) * 0.3 + Double(data[j + 1]) * 0.59 + Double(data[j + 2]) * 0.11
                if abs(a - b) > 90 { hard += 1 }
            }
        }
        return Double(hard) / Double(h * (w - 1))
    }

    /// The same picture drawn small and blown up: what a zoomed-in canvas used
    /// to show for everything that was not a label.
    private func blownUp(_ image: CGImage, by scale: CGFloat) -> CGImage {
        let big = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(big, from: big.extent)!
    }

    /// Where the ink sits, as a fraction of the picture: the shape the drawing
    /// makes, independent of how many pixels it is drawn with.
    private func inkBounds(_ image: CGImage) -> CGRect {
        let data = sample(image)
        let w = image.width, h = image.height
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let l = Double(data[i]) * 0.3 + Double(data[i + 1]) * 0.59 + Double(data[i + 2]) * 0.11
                if l < 200 {
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

    private func closeEnough(_ a: CGRect, _ b: CGRect, within: CGFloat = 0.02) -> Bool {
        abs(a.minX - b.minX) < within && abs(a.minY - b.minY) < within
            && abs(a.width - b.width) < within && abs(a.height - b.height) < within
    }

    // MARK: - Fixtures

    private func captionedArrow() -> Layer {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.caption = "Save"
        return AnnotationBuilder.layer(content: content,
                                       from: CGPoint(x: 220, y: 80), to: CGPoint(x: 60, y: 80))
    }

    private func caliper() -> Layer {
        let content = MeasureContent(start: .zero, end: CGPoint(x: 160, y: 0), mode: .horizontal)
        return MeasureBuilder.layer(content: content,
                                    from: CGPoint(x: 40, y: 90), to: CGPoint(x: 200, y: 90))
    }

    // MARK: - Shapes

    @Test func askingAShapeForMorePixelsGetsThem() throws {
        let layer = captionedArrow()
        let content = try #require(layer.annotation)
        let crisp = try #require(AnnotationRasterizer.rasterize(content, size: layer.frame.size, scale: 3))
        #expect(crisp.width == Int((layer.frame.width * 3).rounded()))
        #expect(crisp.height == Int((layer.frame.height * 3).rounded()))
    }

    @Test func aStrokeStaysWhereItWasAtEveryScale() throws {
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 3, colorHex: "#34C759")
        content.cornerRadius = 6
        let layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 20, y: 20), to: CGPoint(x: 180, y: 120))
        let drawn = try #require(layer.annotation)
        let plain = try #require(AnnotationRasterizer.rasterize(drawn, size: layer.frame.size))
        let crisp = try #require(AnnotationRasterizer.rasterize(drawn, size: layer.frame.size, scale: 4))
        #expect(closeEnough(inkBounds(plain), inkBounds(crisp)))
    }

    @Test func aShapeStrokeIsSharperThanTheSameStrokeBlownUp() throws {
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 3, colorHex: "#34C759")
        content.cornerRadius = 6
        let layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 20, y: 20), to: CGPoint(x: 180, y: 120))
        let drawn = try #require(layer.annotation)
        let plain = try #require(AnnotationRasterizer.rasterize(drawn, size: layer.frame.size))
        let crisp = try #require(AnnotationRasterizer.rasterize(drawn, size: layer.frame.size, scale: 4))
        #expect(hardEdges(crisp) > hardEdges(blownUp(plain, by: 4)) * 2)
    }

    /// The pill is the point of this task: the words in it come from a bitmap
    /// of glyphs, and that bitmap used to be made at document size whatever the
    /// context was drawing at, so the caption stayed soft while its capsule
    /// sharpened around it.
    @Test func anArrowCaptionIsSharperThanTheSameCaptionBlownUp() throws {
        let layer = captionedArrow()
        let content = try #require(layer.annotation)
        let plain = try #require(AnnotationRasterizer.rasterize(content, size: layer.frame.size))
        let crisp = try #require(AnnotationRasterizer.rasterize(content, size: layer.frame.size, scale: 4))
        #expect(hardEdges(crisp) > hardEdges(blownUp(plain, by: 4)) * 2)
    }

    // MARK: - Measures

    @Test func askingACaliperForMorePixelsGetsThem() throws {
        let layer = caliper()
        let content = try #require(layer.measure)
        let crisp = try #require(MeasureRasterizer.rasterize(content, size: layer.frame.size,
                                                             pixelScale: 1, scale: 3))
        #expect(crisp.width == Int((layer.frame.width * 3).rounded()))
        #expect(crisp.height == Int((layer.frame.height * 3).rounded()))
    }

    @Test func aCaliperStaysWhereItWasAtEveryScale() throws {
        let layer = caliper()
        let content = try #require(layer.measure)
        let plain = try #require(MeasureRasterizer.rasterize(content, size: layer.frame.size, pixelScale: 1))
        let crisp = try #require(MeasureRasterizer.rasterize(content, size: layer.frame.size,
                                                             pixelScale: 1, scale: 4))
        #expect(closeEnough(inkBounds(plain), inkBounds(crisp)))
    }

    @Test func aMeasurementChipIsSharperThanTheSameChipBlownUp() throws {
        let layer = caliper()
        let content = try #require(layer.measure)
        let plain = try #require(MeasureRasterizer.rasterize(content, size: layer.frame.size, pixelScale: 1))
        let crisp = try #require(MeasureRasterizer.rasterize(content, size: layer.frame.size,
                                                             pixelScale: 1, scale: 4))
        #expect(hardEdges(crisp) > hardEdges(blownUp(plain, by: 4)) * 2)
    }

    // MARK: - Collage

    @Test func askingACollageForMorePixelsGetsThem() throws {
        let store = ImageStore()
        var data = [UInt8](repeating: 0, count: 400 * 300 * 4)
        let source = CGContext(data: &data, width: 400, height: 300, bitsPerComponent: 8,
                               bytesPerRow: 400 * 4,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        source.setFillColor(CGColor(srgbRed: 0.16, green: 0.35, blue: 0.78, alpha: 1))
        source.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        let ref = store.register(try #require(source.makeImage()))
        let collage = CollageContent(template: .row, gutter: 0,
                                     slots: [CollageSlot(imageRef: ref)], backdropColorHex: "#FFFFFF")
        let size = CGSize(width: 200, height: 100)
        let crisp = try #require(CollageRasterizer.rasterize(collage, size: size, store: store, scale: 3))
        #expect(crisp.width == 600)
        #expect(crisp.height == 300)
    }
}
