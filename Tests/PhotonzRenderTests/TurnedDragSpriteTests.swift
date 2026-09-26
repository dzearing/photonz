import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The picture the canvas floats under the pointer while a turned layer is
/// dragged has to be the whole turned layer. It was the layer cut to its
/// upright box, which sliced a turned rectangle's corners off flat for the
/// whole of a move, so a person saw it lose its rotation until they let go.
@Suite("Turned drag sprite")
struct TurnedDragSpriteTests {

    private func solidImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// How much ink the picture holds: the sum of its alpha, in whole pixels.
    private func ink(_ image: CGImage) -> Double {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var total = 0.0
        for index in stride(from: 3, to: data.count, by: 4) { total += Double(data[index]) / 255 }
        return total
    }

    @Test("A turned layer's sprite holds all of it", arguments: [20.0, 45.0, 90.0, 135.0])
    func turnedSpriteIsWhole(degrees: Double) throws {
        let store = ImageStore()
        let ref = store.register(solidImage(width: 200, height: 100))
        let layer = Layer(name: "Patch", content: .image(ref),
                          frame: CGRect(x: 300, y: 300, width: 200, height: 100),
                          transform: LayerTransform(rotation: LayerAngle.radians(
                              fromDegrees: CGFloat(degrees))))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 700), layers: [layer])
        let sprite = try #require(DocumentRenderer().renderSprite(
            for: layer.id, in: doc, store: store, padding: layer.dragSpritePadding))
        // 200 by 100 is 20,000 points of ink however it is turned; the edges
        // are antialiased, so allow a pixel's worth of slack round the outline.
        #expect(abs(ink(sprite) - 20_000) < 700,
                "at \(degrees) degrees the sprite holds \(ink(sprite)) of 20000")
    }
}
