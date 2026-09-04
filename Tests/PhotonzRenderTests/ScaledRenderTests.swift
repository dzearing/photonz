import CoreGraphics
import CoreImage
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Scaled render")
struct ScaledRenderTests {

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

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }

    /// Every pixel, over white, so alpha differences show up as colour ones.
    private func pixels(_ image: CGImage) -> [UInt8] {
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

    /// Whether two pictures are the same picture, as a plain yes or no so a
    /// failure prints one word instead of a megabyte of bytes.
    private func samePixels(_ a: CGImage, _ b: CGImage) -> Bool {
        a.width == b.width && a.height == b.height && pixels(a) == pixels(b)
    }

    /// Share of neighbouring pixel pairs that swing hard from one to the next:
    /// a sharp edge makes that jump in one step, a blown-up one spreads it.
    private func hardEdges(_ image: CGImage) -> Double {
        let data = pixels(image)
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

    /// A capture with a redline on it: words, a chip and an arrow caption over
    /// a photo, which is what an export at 2x is actually asked to produce.
    private func redlineDocument(store: ImageStore) -> PhotonzDocument {
        let ref = store.register(solidImage(width: 400, height: 200, r: 240, g: 240, b: 244))
        var doc = PhotonzDocument.withBaseImage(ref)
        doc.canvasSize = CGSize(width: 400, height: 200)
        doc.layers[0].frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        var text = TextContent(string: "Padding 16", fontSize: 18)
        text.colorHex = "#101014"
        let size = TextRasterizer.naturalSize(text)
        doc.layers.append(Layer(name: "Label", content: .text(text),
                                frame: CGRect(x: 20, y: 20, width: size.width, height: size.height)))
        return doc
    }

    @Test func scaleTwoDoublesPixelDimensions() {
        let store = ImageStore()
        let ref = store.register(solidImage(width: 64, height: 32, r: 0, g: 0, b: 255))
        let doc = PhotonzDocument.withBaseImage(ref)

        let output = DocumentRenderer().render(doc, store: store, scale: 2)
        #expect(output?.width == 128)
        #expect(output?.height == 64)
        if let output {
            let p = pixel(output, x: 64, y: 32)
            #expect(p.b > 240 && p.a > 240)
            // No soft rim: the picture reaches the edge of the file it is
            // saved into, corner to corner.
            for corner in [(0, 0), (127, 0), (0, 63), (127, 63)] {
                let edge = pixel(output, x: corner.0, y: corner.1)
                #expect(edge.b > 240 && edge.a > 240, "corner \(corner) faded")
            }
        }
    }

    @Test func scaleOneMatchesPlainRender() {
        let store = ImageStore()
        let ref = store.register(solidImage(width: 40, height: 40, r: 255, g: 0, b: 0))
        let doc = PhotonzDocument.withBaseImage(ref)
        let output = DocumentRenderer().render(doc, store: store, scale: 1)
        #expect(output?.width == 40)
        #expect(output?.height == 40)
    }

    /// The whole point of exporting at 2x: the words are DRAWN twice as big,
    /// not photographed at one size and enlarged.
    @Test func aLabelExportedAtTwoIsSharperThanTheSameExportBlownUp() throws {
        let store = ImageStore()
        let doc = redlineDocument(store: store)
        let renderer = DocumentRenderer()

        let crisp = try #require(renderer.render(doc, store: store, scale: 2))
        // What exporting at 2x used to hand back: the document-sized picture,
        // enlarged with the best resampling there is.
        let onex = try #require(renderer.render(doc, store: store))
        let blown = CIImage(cgImage: onex).applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: 2.0, kCIInputAspectRatioKey: 1.0
        ])
        let box = CGRect(x: 0, y: 0, width: doc.canvasSize.width * 2, height: doc.canvasSize.height * 2)
        let soft = try #require(CIContext().createCGImage(blown.cropped(to: box), from: box))

        #expect(crisp.width == soft.width && crisp.height == soft.height)
        #expect(hardEdges(crisp) > hardEdges(soft) * 1.5)
    }

    /// An export at 2x is the canvas's own crisp path, so what you save is
    /// exactly what a zoomed-in canvas shows.
    @Test func anExportAtTwoIsTheCanvasTileAtTwo() throws {
        let store = ImageStore()
        let doc = redlineDocument(store: store)
        let renderer = DocumentRenderer()
        let export = try #require(renderer.render(doc, store: store, scale: 2))
        let tile = try #require(renderer.renderTile(doc, store: store,
                                                    region: CGRect(origin: .zero, size: doc.canvasSize),
                                                    scale: 2))
        #expect(export.width == tile.image.width)
        #expect(export.height == tile.image.height)
        #expect(samePixels(export, tile.image))
    }

    /// And an export at 1x is byte for byte the picture it has always been.
    @Test func anExportAtOneIsThePixelsItAlwaysWas() throws {
        let store = ImageStore()
        let doc = redlineDocument(store: store)
        let renderer = DocumentRenderer()
        let plain = try #require(renderer.render(doc, store: store))
        let scaled = try #require(renderer.render(doc, store: store, scale: 1))
        #expect(samePixels(scaled, plain))
    }

    /// The picture under the redline must not pay for the words on top of it:
    /// a capture has no more detail to give, so it is enlarged with the same
    /// quality the old export enlarged the whole composite with.
    @Test func theCaptureUnderneathIsNoSofterThanItWas() throws {
        let store = ImageStore()
        let ref = store.register(stripedImage(width: 300, height: 200))
        var doc = PhotonzDocument.withBaseImage(ref)
        doc.canvasSize = CGSize(width: 300, height: 200)
        doc.layers[0].frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        let renderer = DocumentRenderer()

        let now = try #require(renderer.render(doc, store: store, scale: 2))
        let onex = try #require(renderer.render(doc, store: store))
        let blown = CIImage(cgImage: onex).applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: 2.0, kCIInputAspectRatioKey: 1.0
        ])
        let box = CGRect(x: 0, y: 0, width: 600, height: 400)
        let was = try #require(CIContext().createCGImage(blown.cropped(to: box), from: box))
        #expect(hardEdges(now) >= hardEdges(was) * 0.95)
    }

    /// Fine detail, the kind a screenshot is full of and a soft enlargement
    /// smears: 2pt dark stripes every 4pt.
    private func stripedImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.05, blue: 0.08, alpha: 1))
        for i in stride(from: 0, to: width, by: 4) {
            ctx.fill(CGRect(x: i, y: 20, width: 2, height: height - 40))
        }
        return ctx.makeImage()!
    }

    /// A canvas whose size does not land on whole pixels at this scale still
    /// exports a whole number of them, with the picture filling all of them.
    @Test func aFractionalScaleStillExportsWholePixels() throws {
        let store = ImageStore()
        let ref = store.register(solidImage(width: 41, height: 27, r: 0, g: 160, b: 0))
        let doc = PhotonzDocument.withBaseImage(ref)
        let output = try #require(DocumentRenderer().render(doc, store: store, scale: 1.5))
        #expect(output.width == 62)   // 41 * 1.5 = 61.5
        #expect(output.height == 41)  // 27 * 1.5 = 40.5
        let inside = pixel(output, x: output.width - 2, y: output.height - 2)
        #expect(inside.g > 140 && inside.a > 240)
    }
}
