import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A frame of a recording read in passing (small, while a hand moves the
/// playhead) is a scrub preview, enlarged to its box in one plain pass; the
/// better resampler took three of the five passes each picture of a dragged
/// playhead cost on the 6 minute reference edit
/// (`scrubbing-a-long-edit-never-trails-the-pointer-b`, pass 2). A sharp
/// frame, a punch-in on one and a photo keep the better resampler.
@Suite("Enlarging a frame read in passing")
struct FramesReadInPassingRenderTests {

    /// Stripes a pixel or two wide: what an enlarging resampler shows its
    /// difference on.
    private func stripes(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for x in 0..<width {
            let on = (x / 2) % 2 == 0
            context.setFillColor(CGColor(srgbRed: on ? 0.95 : 0.05, green: 0.4, blue: on ? 0.1 : 0.8, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
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

    /// `frame` drawn into a box `box` big, as a clip of `movie` or, with no
    /// movie, as a photo.
    private func drawn(_ frame: CGImage, box: CGSize, movie: MovieRef?) throws -> [UInt8] {
        let store = ImageStore()
        let ref = store.register(frame)
        var layer = Layer(name: "Clip", content: .image(ref), frame: CGRect(origin: .zero, size: box))
        layer.movie = movie
        let doc = PhotonzDocument(canvasSize: box, layers: [layer])
        let renderer = DocumentRenderer(compositing: .linearLight)
        return rgba(try #require(renderer.renderInteractive(doc, store: store)))
    }

    @Test("A frame read in passing is enlarged the plain way, not as a photo is")
    func previewIsPlain() throws {
        let movie = MovieRef(pixelSize: CGSize(width: 1600, height: 1000), durationMS: 10_000)
        let rough = stripes(80, 50)
        #expect(MovieSweep.isReadInPassing(frameWidth: rough.width, of: movie))
        let asClip = try drawn(rough, box: CGSize(width: 240, height: 150), movie: movie)
        let asPhoto = try drawn(rough, box: CGSize(width: 240, height: 150), movie: nil)
        #expect(asClip != asPhoto)
    }

    @Test("A sharp frame punched in on is enlarged exactly as a photo is")
    func sharpKeepsTheBetterResampler() throws {
        let movie = MovieRef(pixelSize: CGSize(width: 900, height: 40), durationMS: 10_000)
        let sharp = stripes(900, 40)
        #expect(!MovieSweep.isReadInPassing(frameWidth: sharp.width, of: movie))
        let box = CGSize(width: 1350, height: 60)
        #expect(try drawn(sharp, box: box, movie: movie) == drawn(sharp, box: box, movie: nil))
    }
}
