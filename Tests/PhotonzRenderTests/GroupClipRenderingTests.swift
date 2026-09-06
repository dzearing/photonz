import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A group given a size of its own draws like a screen once it is told to: what
/// hangs off its edge is simply not in the picture, and a rounded corner cuts
/// with the corner rather than with the square box.
@Suite("Clipping a sized group")
struct GroupClipRenderingTests {

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

    private let canvas = CGSize(width: 200, height: 200)

    /// A grey 200×200 base, so what a group cuts away reads against it.
    private func document(_ store: ImageStore, _ layers: [Layer]) -> PhotonzDocument {
        let base = store.register(solidImage(width: 200, height: 200, r: 100, g: 100, b: 100))
        var doc = PhotonzDocument(canvasSize: canvas, layers: [
            Layer(name: "Base", content: .image(base),
                  frame: CGRect(origin: .zero, size: canvas), isLocked: true)
        ])
        for layer in layers { doc.addLayer(layer) }
        return doc
    }

    /// A card at (50, 50) told it is 100×100, holding a red patch that runs 60
    /// points past its right-hand edge.
    private func card(_ store: ImageStore) -> Layer {
        let ref = store.register(solidImage(width: 160, height: 20, r: 255, g: 0, b: 0))
        let overhang = Layer(name: "Title", content: .image(ref),
                             frame: CGRect(x: 0, y: 20, width: 160, height: 20))
        var content = GroupContent(children: [overhang])
        content.layout = .free(width: 100, height: 100)
        return Layer(name: "Card", content: .group(content),
                     frame: CGRect(x: 50, y: 50, width: 0, height: 0))
    }

    @Test func whatLeavesTheBoxIsDrawnUntilTheSwitchIsOn() {
        let store = ImageStore()
        var doc = document(store, [card(store)])
        let id = doc.layers[1].id

        // Off: the overhang is drawn past the card's right-hand edge (x = 150).
        let open = DocumentRenderer().render(doc, store: store)!
        #expect(pixel(open, x: 120, y: 75).r > 200)
        #expect(pixel(open, x: 180, y: 75).r > 200)
        #expect(pixel(open, x: 180, y: 75).g < 60)

        // On: the same picture stops at the edge and the canvas shows again.
        doc.setClipsContents(id: id, true)
        let clipped = DocumentRenderer().render(doc, store: store)!
        #expect(pixel(clipped, x: 120, y: 75).r > 200)
        #expect(pixel(clipped, x: 180, y: 75).r == 100)
        #expect(pixel(clipped, x: 180, y: 75).g == 100)
    }

    @Test func aRoundedCardCutsWithItsCorner() {
        let store = ImageStore()
        let fill = store.register(solidImage(width: 160, height: 160, r: 255, g: 0, b: 0))
        let flood = Layer(name: "Fill", content: .image(fill),
                          frame: CGRect(x: 0, y: 0, width: 160, height: 160))
        var content = GroupContent(children: [flood])
        content.layout = .free(width: 100, height: 100)
        var card = Layer(name: "Card", content: .group(content),
                         frame: CGRect(x: 50, y: 50, width: 0, height: 0))
        card.style.cornerRadius = 30
        var doc = document(store, [card])
        doc.setClipsContents(id: doc.layers[1].id, true)

        let image = DocumentRenderer().render(doc, store: store)!
        // The middle is the card; the very corner of its box is cut away with
        // the round rather than filled to the square.
        #expect(pixel(image, x: 100, y: 100).r > 200)
        #expect(pixel(image, x: 52, y: 52).r == 100)
        #expect(pixel(image, x: 52, y: 52).g == 100)
    }

    @Test func whatIsCutOffIsNotExportedEither() {
        let store = ImageStore()
        var doc = document(store, [card(store)])
        doc.setClipsContents(id: doc.layers[1].id, true)
        // The export path is the same composite the canvas shows, read back as
        // a region: nothing past the card's edge is in it.
        let region = DocumentRenderer().rasterize(region: CGRect(x: 150, y: 60, width: 40,
                                                                 height: 30),
                                                  of: doc, store: store)!
        #expect(pixel(region, x: 20, y: 15).r == 100)
    }
}
