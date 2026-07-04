import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Collage rendering")
struct CollageRenderingTests {

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

    @Test func fillsSlotsWithPhotosAndBackdropInGutters() {
        let store = ImageStore()
        let red = store.register(solidImage(width: 100, height: 100, r: 255, g: 0, b: 0))
        let blue = store.register(solidImage(width: 80, height: 40, r: 0, g: 0, b: 255))
        let content = CollageContent(template: .row, gutter: 10,
                                     slots: [CollageSlot(imageRef: red), CollageSlot(imageRef: blue)],
                                     backdropColorHex: "#FFFFFF")
        let raster = CollageRasterizer.rasterize(content, size: CGSize(width: 210, height: 100), store: store)!
        // Cells: width (210 - 30)/2 = 90, height 80, at x=10 and x=110.
        let left = pixel(raster, x: 50, y: 50)
        #expect(left.r > 200 && left.g < 60 && left.b < 60)
        let right = pixel(raster, x: 150, y: 50)
        #expect(right.b > 200 && right.r < 60)
        let gutter = pixel(raster, x: 105, y: 50)
        #expect(gutter.r > 240 && gutter.g > 240 && gutter.b > 240)
    }

    @Test func emptySlotsAndNilBackdropRenderTransparent() {
        let store = ImageStore()
        let red = store.register(solidImage(width: 100, height: 100, r: 255, g: 0, b: 0))
        let content = CollageContent(template: .row, gutter: 10,
                                     slots: [CollageSlot(imageRef: red), CollageSlot()],
                                     backdropColorHex: nil)
        let raster = CollageRasterizer.rasterize(content, size: CGSize(width: 210, height: 100), store: store)!
        #expect(pixel(raster, x: 50, y: 50).a > 200)   // filled slot opaque
        #expect(pixel(raster, x: 150, y: 50).a == 0)   // empty slot transparent
        #expect(pixel(raster, x: 105, y: 50).a == 0)   // gutter transparent
    }

    @Test func photoAspectFillsWithoutDistortion() {
        // A 200×100 image, left half red / right half green, into a square
        // cell: the fill crop keeps the CENTER 100px band, so both colors
        // still appear (split at the cell's midline) — nothing is squashed.
        let store = ImageStore()
        let context = CGContext(data: nil, width: 200, height: 100,
                                bitsPerComponent: 8, bytesPerRow: 800,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        let ref = store.register(context.makeImage()!)

        let content = CollageContent(template: .row, gutter: 0,
                                     slots: [CollageSlot(imageRef: ref)], backdropColorHex: nil)
        let raster = CollageRasterizer.rasterize(content, size: CGSize(width: 100, height: 100), store: store)!
        let left = pixel(raster, x: 25, y: 50)
        #expect(left.r > 200 && left.g < 60)
        let right = pixel(raster, x: 75, y: 50)
        #expect(right.g > 200 && right.r < 60)
    }

    @Test func rendersInsideADocumentAtTheLayerFrame() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 400, height: 300, r: 255, g: 255, b: 255))
        let red = store.register(solidImage(width: 100, height: 100, r: 255, g: 0, b: 0))
        var doc = PhotonzDocument.withBaseImage(base)
        let content = CollageContent(template: .row, gutter: 10,
                                     slots: [CollageSlot(imageRef: red)], backdropColorHex: "#000000")
        doc.addLayer(Collage.layer(content: content, frame: CGRect(x: 100, y: 50, width: 200, height: 200)))
        let composite = DocumentRenderer().render(doc, store: store)!
        let inCell = pixel(composite, x: 200, y: 150)     // cell interior → red
        #expect(inCell.r > 200 && inCell.g < 60)
        let inGutter = pixel(composite, x: 105, y: 150)   // backdrop margin → black
        #expect(inGutter.r < 40 && inGutter.g < 40 && inGutter.b < 40)
        let outside = pixel(composite, x: 50, y: 150)     // canvas → white base
        #expect(outside.r > 240 && outside.g > 240)
    }
}
