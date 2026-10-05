import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// An original kept in the component library is never in the picture: not on
/// the canvas, not in an export, not in a copy as image. Only its instances
/// are drawn (the user, 2026-10-04: "when i drag a component to the canvas,
/// why are there 2 copies").
@Suite("Originals in the component library are not drawn")
struct ComponentLibraryRenderTests {

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

    /// A grey 200×200 base with a red 40×40 square made a component at
    /// (20, 20), its original moved into the library, and one instance placed
    /// at (140, 140).
    @Test func onlyTheInstanceIsDrawn() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 200, height: 200, r: 100, g: 100, b: 100))
        let red = store.register(solidImage(width: 40, height: 40, r: 255, g: 0, b: 0))
        var doc = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200), layers: [
            Layer(name: "Base", content: .image(base),
                  frame: CGRect(x: 0, y: 0, width: 200, height: 200), isLocked: true),
            Layer(name: "Square", content: .image(red), frame: CGRect(x: 20, y: 20, width: 40, height: 40))
        ])
        guard let group = doc.groupLayers(ids: [doc.layers[1].id], name: "Tile"),
              let componentID = doc.makeComponent(id: group.id) else {
            Issue.record("no component"); return
        }
        // The canvas's copy stands where the group was; take it away so the
        // only drawing of the square left anywhere is the original.
        let standIn = doc.parkOriginals()[group.id] ?? UUID()
        doc.removeLayer(id: standIn)
        doc.insertComponentInstance(of: componentID, at: CGPoint(x: 160, y: 160))
        doc.syncComponentInstances()

        let picture = DocumentRenderer().render(doc, store: store)!
        // Where the original stood: the base shows, nothing red.
        #expect(pixel(picture, x: 40, y: 40).r == 100)
        // The instance is drawn.
        #expect(pixel(picture, x: 160, y: 160).r > 200)
        #expect(pixel(picture, x: 160, y: 160).g < 60)
    }
}
