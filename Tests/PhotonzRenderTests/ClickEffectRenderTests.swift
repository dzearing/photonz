import CoreGraphics
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzRender

/// A click's effect reaches the pixels: a ring round the click, a dot on it,
/// or the picture dimmed everywhere but there (`ClickEffect.swift`).
@Suite("An effect at a click, in the picture")
struct ClickEffectRenderTests {

    private func grey(width: Int, height: Int) -> CGImage {
        var data = [UInt8](repeating: 128, count: width * height * 4)
        for i in stride(from: 3, to: data.count, by: 4) { data[i] = 255 }
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    /// The colour at a point counted from the TOP-left.
    private func ink(_ image: CGImage, at point: CGPoint) -> (r: Int, g: Int, b: Int) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let index = (Int(point.y) * width + Int(point.x)) * 4
        return (Int(data[index]), Int(data[index + 1]), Int(data[index + 2]))
    }

    /// A grey 400 x 200 recording filling the canvas, clicked at 300, 100.
    private func document(store: ImageStore, style: ClickEffectStyle) -> PhotonzDocument {
        let size = CGSize(width: 400, height: 200)
        let movie = MovieRef(pixelSize: size, durationMS: 4000)
        let picture = grey(width: 400, height: 200)
        for ms in stride(from: 0, through: 4000, by: MovieRef.frameStepMS) {
            store.register(picture, as: movie.frameRef(atSourceMS: ms))
        }
        var clip = Layer(name: "Clip", content: .image(movie.frameRef(atSourceMS: 0)),
                         frame: CGRect(origin: .zero, size: size))
        clip.movie = movie
        clip.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 0, sourceLengthMS: 4000)
        var document = PhotonzDocument(canvasSize: size, layers: [clip])
        document.durationMS = 4000
        let click = PointerClick(downMS: 1000, upMS: 1080, point: CGPoint(x: 300, y: 100), button: .left)
        document.setClickEffect(onClip: clip.id, recorded: [click]) {
            $0.isOn = true
            $0.style = style
            $0.size = .large
            $0.colorHex = "#FF0000"
        }
        return document
    }

    @Test func aRippleIsARingRoundTheClick() throws {
        let store = ImageStore()
        let document = document(store: store, style: .ripple)
        let drawn = document.drawn(atTimeMS: 1050)
        let ring = try #require(drawn.layers.last)
        let image = try #require(DocumentRenderer().render(drawn, store: store, scale: 1))
        // On its edge it is red; in its middle and far away it is the grey picture.
        let edge = ink(image, at: CGPoint(x: ring.frame.maxX - 1.5, y: ring.frame.midY))
        #expect(edge.r > edge.g + 30, "the ring's edge read \(edge)")
        let middle = ink(image, at: CGPoint(x: 300, y: 100))
        #expect(abs(middle.r - middle.g) < 10, "the middle read \(middle)")
        let away = ink(image, at: CGPoint(x: 40, y: 40))
        #expect(abs(away.r - 128) < 6 && abs(away.g - 128) < 6, "far away read \(away)")
    }

    @Test func aPulseIsADotOnTheClick() throws {
        let store = ImageStore()
        let document = document(store: store, style: .pulse)
        let image = try #require(DocumentRenderer().render(document.drawn(atTimeMS: 1200), store: store, scale: 1))
        let middle = ink(image, at: CGPoint(x: 300, y: 100))
        #expect(middle.r > middle.g + 40, "the middle read \(middle)")
    }

    @Test func aSpotlightDimsAwayFromTheClickAndNotOnIt() throws {
        let store = ImageStore()
        let document = document(store: store, style: .spotlight)
        let image = try #require(DocumentRenderer().render(document.drawn(atTimeMS: 1200), store: store, scale: 1))
        let middle = ink(image, at: CGPoint(x: 300, y: 100))
        let away = ink(image, at: CGPoint(x: 20, y: 20))
        #expect(abs(middle.g - 128) < 6, "the spot read \(middle)")
        #expect(away.g < 100, "away from the click read \(away)")
    }
}
