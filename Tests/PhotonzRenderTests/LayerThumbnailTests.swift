import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Layer thumbnails")
struct LayerThumbnailTests {

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

    @Test func thumbnailShrinksToMaxDimensionPreservingAspect() {
        let store = ImageStore()
        let ref = store.register(solidImage(width: 400, height: 200, r: 0, g: 0, b: 255))
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 200))
        let layer = Layer(name: "L", content: .image(ref),
                          frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        doc.addLayer(layer)

        let thumb = DocumentRenderer().thumbnail(for: layer.id, in: doc, store: store, maxDimension: 40)
        #expect(thumb != nil)
        #expect(thumb?.width == 40)
        #expect(thumb?.height == 20)
        if let thumb {
            let p = pixel(thumb, x: 20, y: 10)
            #expect(p.b > 240 && p.a > 240)
        }
    }

    @Test func smallLayersAreNotUpscaled() {
        let store = ImageStore()
        let ref = store.register(solidImage(width: 16, height: 8, r: 255, g: 0, b: 0))
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        let layer = Layer(name: "Small", content: .image(ref),
                          frame: CGRect(x: 0, y: 0, width: 16, height: 8))
        doc.addLayer(layer)

        let thumb = DocumentRenderer().thumbnail(for: layer.id, in: doc, store: store, maxDimension: 40)
        #expect(thumb?.width == 16)
        #expect(thumb?.height == 8)
    }

    @Test func unknownLayerReturnsNil() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10))
        #expect(DocumentRenderer().thumbnail(for: UUID(), in: doc, store: ImageStore(),
                                             maxDimension: 40) == nil)
    }

    // MARK: A level line keeps a picture

    /// A line drawn with Shift lies flat, so its box is a few points tall and
    /// hundreds wide. Shrunk to 80 wide that is one row of pixels, and the
    /// layers row fitting it into its slot left half a point: an empty grey
    /// tile beside a row called Line.
    private func lineThumbnail(to end: CGPoint, minimumAspect: CGFloat?) -> CGImage? {
        let layer = AnnotationBuilder.layer(
            content: AnnotationContent(shape: .line, strokeWidth: 4, colorHex: "#E5483B"),
            from: CGPoint(x: 120, y: 380), to: end)
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 800))
        doc.addLayer(layer)
        return DocumentRenderer().thumbnail(for: layer.id, in: doc, store: ImageStore(),
                                            maxDimension: 80, minimumAspect: minimumAspect)
    }

    /// The strongest alpha along each row (or column) of `image`.
    private func alphaProfile(_ image: CGImage, alongRows: Bool) -> [UInt8] {
        let count = alongRows ? image.height : image.width
        return (0..<count).map { index in
            let span = alongRows ? image.width : image.height
            return (0..<span).map { step in
                alongRows ? pixel(image, x: step, y: index).a : pixel(image, x: index, y: step).a
            }.max() ?? 0
        }
    }

    @Test func aLevelLineIsCentredOnABandTallEnoughToShow() throws {
        let thumb = try #require(lineThumbnail(to: CGPoint(x: 420, y: 380), minimumAspect: 0.25))
        #expect(thumb.width == 80)
        #expect(thumb.height == 20)
        let rows = alphaProfile(thumb, alongRows: true)
        // The stroke is there at full strength, in the middle, and nowhere near
        // the top or bottom edge.
        let inked = rows.indices.filter { rows[$0] > 128 }
        #expect(!inked.isEmpty)
        #expect(inked.allSatisfy { (8...11).contains($0) })
        #expect(rows[0] == 0 && rows[19] == 0)
    }

    @Test func anUprightLineIsCentredTheSameWay() throws {
        let thumb = try #require(lineThumbnail(to: CGPoint(x: 120, y: 684), minimumAspect: 0.25))
        #expect(thumb.height == 80)
        #expect(thumb.width == 20)
        let columns = alphaProfile(thumb, alongRows: false)
        let inked = columns.indices.filter { columns[$0] > 128 }
        #expect(!inked.isEmpty)
        #expect(inked.allSatisfy { (8...11).contains($0) })
    }

    @Test func withoutAFloorALevelLineIsOneRowAsBefore() throws {
        let thumb = try #require(lineThumbnail(to: CGPoint(x: 420, y: 380), minimumAspect: nil))
        #expect(thumb.height == 1)
    }

    @Test func aPictureAlreadyInsideTheFloorIsUntouched() {
        let store = ImageStore()
        let ref = store.register(solidImage(width: 400, height: 200, r: 0, g: 0, b: 255))
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 200))
        let layer = Layer(name: "L", content: .image(ref),
                          frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        doc.addLayer(layer)
        let thumb = DocumentRenderer().thumbnail(for: layer.id, in: doc, store: store,
                                                 maxDimension: 40, minimumAspect: 0.25)
        #expect(thumb?.width == 40)
        #expect(thumb?.height == 20)
    }

    @Test func aSmallFlatLayerIsPaddedWithoutBeingEnlarged() throws {
        let store = ImageStore()
        let ref = store.register(solidImage(width: 40, height: 2, r: 255, g: 0, b: 0))
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        let layer = Layer(name: "Rule", content: .image(ref),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 2))
        doc.addLayer(layer)
        let thumb = try #require(DocumentRenderer().thumbnail(for: layer.id, in: doc, store: store,
                                                              maxDimension: 80, minimumAspect: 0.25))
        #expect(thumb.width == 40)
        #expect(thumb.height == 10)
        let rows = alphaProfile(thumb, alongRows: true)
        #expect(rows.indices.filter { rows[$0] > 240 } == [4, 5])
    }
}
