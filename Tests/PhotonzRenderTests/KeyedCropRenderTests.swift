import CoreGraphics
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzRender

/// A keyed crop reaches the pixels as a wipe, and a picture cropped by hand
/// keeps its cut when a scale key grows it (task
/// `keyframe-anything-and-see-and-shape-the-keys-on`).
@Suite("A keyed crop in the picture")
struct KeyedCropRenderTests {

    /// Left half green, right half red.
    private func halves(width: Int, height: Int) -> CGImage {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if x < width / 2 { data[i + 1] = 255 } else { data[i] = 255 }
                data[i + 3] = 255
            }
        }
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    private func ink(_ image: CGImage, at point: CGPoint) -> (r: Int, g: Int, b: Int) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let row = height - 1 - Int(point.y)
        let index = (row * width + Int(point.x)) * 4
        return (Int(data[index]), Int(data[index + 1]), Int(data[index + 2]))
    }

    /// Black ground, and the two-colour picture over all of it, for 4s.
    private func picture(store: ImageStore) -> (PhotonzDocument, UUID) {
        let canvas = CGSize(width: 200, height: 100)
        let ground = Layer(name: "Ground",
                           content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                                                  colorHex: "#000000",
                                                                  start: .zero, end: CGPoint(x: 200, y: 100),
                                                                  fillColorHex: "#000000")),
                           frame: CGRect(origin: .zero, size: canvas))
        let ref = store.register(halves(width: 200, height: 100))
        var shot = Layer(name: "Shot", content: .image(ref), frame: CGRect(origin: .zero, size: canvas))
        shot.time = LayerTime(inMS: 0, outMS: 4000)
        var document = PhotonzDocument(canvasSize: canvas, layers: [ground, shot])
        document.durationMS = 4000
        return (document, shot.id)
    }

    private func render(_ document: PhotonzDocument, store: ImageStore, atMS ms: Int) -> CGImage? {
        DocumentRenderer().render(document.drawn(atTimeMS: ms), store: store, scale: 1)
    }

    @Test func aLeftCropWipesThePictureAwayAndLeavesTheRestWhereItWas() throws {
        let store = ImageStore()
        var (document, id) = picture(store: store)
        document.startKeying(layerID: id, .motion(.cropLeft), atDocumentTimeMS: 0)
        document.setKeyedValue(.number(50), layerID: id, .motion(.cropLeft), atDocumentTimeMS: 2000)
        let before = try #require(render(document, store: store, atMS: 0))
        let after = try #require(render(document, store: store, atMS: 3000))
        #expect(ink(before, at: CGPoint(x: 20, y: 50)).g > 200)
        // The green half is gone, the ground shows through where it was...
        #expect(ink(after, at: CGPoint(x: 20, y: 50)) == (0, 0, 0))
        #expect(ink(after, at: CGPoint(x: 90, y: 50)).g < 40)
        // ...and the red half is exactly where it always was, not stretched.
        #expect(ink(after, at: CGPoint(x: 110, y: 50)).r > 200)
        #expect(ink(after, at: CGPoint(x: 190, y: 50)).r > 200)
    }

    @Test func aPictureCroppedByHandKeepsItsCutWhenAScaleKeyGrowsIt() throws {
        let store = ImageStore()
        var (document, id) = picture(store: store)
        // Keep the green half only, then grow it to 150% about its middle.
        document.updateLayer(id: id) { $0.cropContent(to: CGRect(x: 0, y: 0, width: 100, height: 100)) }
        document.setKeyedValue(.number(150), layerID: id, .motion(.scale), atDocumentTimeMS: 0)
        let grown = try #require(render(document, store: store, atMS: 1000))
        // The grown box runs -25...125; all of it is the green half.
        #expect(ink(grown, at: CGPoint(x: 110, y: 50)).g > 200)
        #expect(ink(grown, at: CGPoint(x: 110, y: 50)).r < 40)
        #expect(ink(grown, at: CGPoint(x: 150, y: 50)) == (0, 0, 0))
    }
}
