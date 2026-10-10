import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A measurement drawn on its own (the layers list thumbnail, a drag preview,
/// Copy Layer) reads the number the canvas reads. On a Retina capture the
/// document's `pixelScale` is 2 and a Logical measurement halves its raw span;
/// a single-layer render that forgot the scale printed the raw span instead,
/// 33 px in the thumbnail beside a 16 px chip on the canvas.
@Suite("A measurement drawn alone keeps the capture's pixel scale")
struct RetinaMeasureSpriteTests {

    private func bytes(_ image: CGImage?) -> [UInt8]? {
        guard let image, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(data: &data, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// The same Logical gap in a 1x and a 2x document. Its chip reads 64 on
    /// the first and 32 on the second, so any honest picture of it differs.
    private func documents() -> (oneX: PhotonzDocument, twoX: PhotonzDocument, id: UUID) {
        let content = MeasureContent(start: .zero, end: CGPoint(x: 64, y: 0), mode: .horizontal,
                                     unit: .points)
        let layer = MeasureBuilder.layer(content: content,
                                         from: CGPoint(x: 40, y: 90), to: CGPoint(x: 104, y: 90))
        let oneX = PhotonzDocument(canvasSize: CGSize(width: 240, height: 180), layers: [layer])
        var twoX = oneX
        twoX.pixelScale = 2
        return (oneX, twoX, layer.id)
    }

    /// The 2x document's own canvas, cropped to the measurement: what a person
    /// reads on the canvas.
    @Test func theCanvasItselfReadsDifferentlyAtTwoX() throws {
        let (oneX, twoX, _) = documents()
        let renderer = DocumentRenderer()
        let store = ImageStore()
        let differ = try #require(bytes(renderer.render(oneX, store: store)))
            != (try #require(bytes(renderer.render(twoX, store: store))))
        #expect(differ)
    }

    @Test func theLayersListThumbnailReadsTheCanvasNumber() throws {
        let (oneX, twoX, id) = documents()
        let renderer = DocumentRenderer()
        let store = ImageStore()
        let atOne = try #require(bytes(renderer.thumbnail(for: id, in: oneX, store: store,
                                                         maxDimension: 400)))
        let atTwo = try #require(bytes(renderer.thumbnail(for: id, in: twoX, store: store,
                                                         maxDimension: 400)))
        let differ = atOne != atTwo
        #expect(differ)
    }

    @Test func aDragPreviewReadsTheCanvasNumber() throws {
        let (oneX, twoX, id) = documents()
        let renderer = DocumentRenderer()
        let store = ImageStore()
        let atOne = try #require(bytes(renderer.renderSprite(for: id, in: oneX, store: store, padding: 4)))
        let atTwo = try #require(bytes(renderer.renderSprite(for: id, in: twoX, store: store, padding: 4)))
        let differ = atOne != atTwo
        #expect(differ)
    }

    /// Copy Layer's picture is the canvas with only that layer on it, so on a
    /// 2x capture it is exactly the canvas's own pixels for that layer.
    @Test func copyingTheLayerAloneMatchesTheCanvas() throws {
        let (_, twoX, id) = documents()
        let renderer = DocumentRenderer()
        let store = ImageStore()
        let same = try #require(bytes(renderer.render(twoX, store: store, only: id)))
            == (try #require(bytes(renderer.render(twoX, store: store))))
        #expect(same)
    }
}
