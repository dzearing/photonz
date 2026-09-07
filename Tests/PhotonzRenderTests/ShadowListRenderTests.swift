import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A layer can throw more than one shadow, and it can throw one INTO itself.
///
/// The Appearance list became a list you add to on 2026-09-07, which is only
/// worth anything if the canvas agrees: two shadows have to be two shadows, the
/// order of the list has to be the order they paint in, a switched-off entry
/// has to draw nothing, and an inner shadow has to stay inside the layer.
/// `docs/design/shape-parts.md`, "How the list grows".
@Suite("Shadow list rendering")
struct ShadowListRenderTests {

    private let canvas = CGSize(width: 200, height: 200)

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

    private func rgba(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let data = rgba(image)
        let offset = (y * image.width + x) * 4
        return (Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2]))
    }

    /// A white canvas with one 60×60 patch in the middle of it, styled however
    /// the test asks.
    private func document(_ store: ImageStore, style: LayerStyle) -> PhotonzDocument {
        let base = store.register(solidImage(width: 200, height: 200, r: 255, g: 255, b: 255))
        let patch = store.register(solidImage(width: 60, height: 60, r: 255, g: 255, b: 255))
        var doc = PhotonzDocument(canvasSize: canvas, layers: [
            Layer(name: "Base", content: .image(base),
                  frame: CGRect(origin: .zero, size: canvas), isLocked: true)
        ])
        doc.addLayer(Layer(name: "Patch", content: .image(patch),
                           frame: CGRect(x: 70, y: 70, width: 60, height: 60), style: style))
        return doc
    }

    private func render(_ style: LayerStyle) throws -> CGImage {
        let store = ImageStore()
        let doc = document(store, style: style)
        return try #require(DocumentRenderer().render(doc, store: store))
    }

    // MARK: Two shadows are two shadows

    @Test("A second shadow paints as well as the first, not instead of it")
    func twoShadowsBothPaint() throws {
        // One thrown left, one thrown right, so each has a patch of canvas of
        // its own to darken and neither can be mistaken for the other.
        let left = ShadowStyle(radius: 1, offset: CGSize(width: -14, height: 0),
                               colorHex: "#000000", opacity: 1)
        let right = ShadowStyle(radius: 1, offset: CGSize(width: 14, height: 0),
                                colorHex: "#000000", opacity: 1)
        let both = try render(LayerStyle(shadows: [left, right]))
        #expect(pixel(both, x: 60, y: 100).r < 120)
        #expect(pixel(both, x: 139, y: 100).r < 120)

        // With only the first, the right-hand side is still white canvas.
        let one = try render(LayerStyle(shadows: [left]))
        #expect(pixel(one, x: 60, y: 100).r < 120)
        #expect(pixel(one, x: 139, y: 100).r > 240)
    }

    @Test("The order of the list is the order they paint in")
    func orderIsPaintOrder() throws {
        // Two hard shadows thrown the same way, one red and one blue, so where
        // they overlap you see whichever is nearer the eye. Nearest the eye is
        // the TOP of the Appearance list, which is index 0.
        let red = ShadowStyle(radius: 0, offset: CGSize(width: 0, height: 20),
                              colorHex: "#FF0000", opacity: 1)
        let blue = ShadowStyle(radius: 0, offset: CGSize(width: 0, height: 20),
                               colorHex: "#0000FF", opacity: 1)
        let redOnTop = try render(LayerStyle(shadows: [red, blue]))
        let blueOnTop = try render(LayerStyle(shadows: [blue, red]))

        // A point below the patch, inside both shadows.
        let a = pixel(redOnTop, x: 100, y: 145)
        let b = pixel(blueOnTop, x: 100, y: 145)
        #expect(a.r > 200 && a.b < 60)
        #expect(b.b > 200 && b.r < 60)
    }

    @Test("A switched-off entry draws nothing at all")
    func offDrawsNothing() throws {
        let hard = ShadowStyle(radius: 0, offset: CGSize(width: 0, height: 20),
                               colorHex: "#000000", opacity: 1, isOn: false)
        let image = try render(LayerStyle(shadows: [hard]))
        #expect(pixel(image, x: 100, y: 145).r > 240)
    }

    // MARK: An inner shadow stays inside

    @Test("An inner shadow darkens the layer and leaves the canvas alone")
    func innerShadowStaysInside() throws {
        let inner = ShadowStyle(radius: 4, offset: CGSize(width: 0, height: 10),
                                colorHex: "#000000", opacity: 1, kind: .inner)
        let image = try render(LayerStyle(shadows: [inner]))
        // Just inside the patch's top edge: darkened, because the shadow is
        // cast down from the edge above it.
        #expect(pixel(image, x: 100, y: 74).r < 140)
        // The middle of the patch is still its own white.
        #expect(pixel(image, x: 100, y: 120).r > 230)
        // And the canvas just above the patch is untouched: an inner shadow
        // never leaves the layer, which is the whole difference from a drop.
        #expect(pixel(image, x: 100, y: 66).r > 240)
    }

    @Test("An inner shadow and a drop shadow live in the same list")
    func innerAndDropTogether() throws {
        let drop = ShadowStyle(radius: 1, offset: CGSize(width: 0, height: 20),
                               colorHex: "#000000", opacity: 1)
        let inner = ShadowStyle(radius: 4, offset: CGSize(width: 0, height: 10),
                                colorHex: "#000000", opacity: 1, kind: .inner)
        let image = try render(LayerStyle(shadows: [inner, drop]))
        #expect(pixel(image, x: 100, y: 145).r < 120)   // the drop, on the canvas
        #expect(pixel(image, x: 100, y: 74).r < 140)    // the inner, inside the layer
    }

    // MARK: Nothing that already draws changes

    @Test("One drop shadow paints exactly what it always painted")
    func oneShadowIsUnchanged() throws {
        let shadow = ShadowStyle(radius: 6, offset: CGSize(width: 0, height: 8),
                                 colorHex: "#000000", opacity: 0.5)
        let viaList = try render(LayerStyle(shadows: [shadow]))
        let viaSingle = try render(LayerStyle(shadow: shadow))
        #expect(rgba(viaList) == rgba(viaSingle))
    }
}
