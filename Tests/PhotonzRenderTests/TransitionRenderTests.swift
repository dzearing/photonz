import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// A transition, drawn by the renderer that was never told transitions exist
/// (`docs/design/video-transitions.md`).
///
/// The model's own tests say what `drawn(atTimeMS:)` hands back; these say what
/// comes out of the renderer when it is handed that, which is the question a
/// person actually has: **is the frame on the cut black.** The two are worth
/// keeping apart, because the first one passed while the second one did not.
@Suite("What a transition looks like once it is drawn")
struct TransitionRenderTests {

    static let canvas = CGSize(width: 120, height: 80)

    /// A two piece clip whose pieces are two different flat colours, so a
    /// pixel is enough to say which shot is on screen and how much of it.
    static func document() throws -> (document: PhotonzDocument, store: ImageStore) {
        let store = ImageStore()
        let red = try #require(SolidImage.make(size: canvas, hex: "#FF0000"))
        var clip = Layer(name: "Recording", content: .image(store.register(red)),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.movie = MovieRef(pixelSize: canvas, durationMS: 8000)
        clip.time = LayerTime(inMS: 0, outMS: 6000, sourceInMS: 0, sourceLengthMS: 8000)
        clip.setClipPieces(ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 3000),
                                               ClipPiece(sourceInMS: 5000, lengthMS: 3000)],
                                      sourceLengthMS: 8000))
        var document = PhotonzDocument(canvasSize: canvas, layers: [clip])
        document.durationMS = 6000
        return (document, store)
    }

    /// The frames a clip would have fetched, filed under the references the
    /// document asks for: the first piece red, the second blue. This is what
    /// `MovieFrameFetcher` does in the app, said in one line for a test.
    static func fillFrames(_ document: PhotonzDocument, store: ImageStore, atMS ms: Int) throws {
        for request in document.movieFrames(atTimeMS: ms) {
            let isSecondPiece = request.sourceMS >= 4000
            let image = try #require(SolidImage.make(size: canvas,
                                                     hex: isSecondPiece ? "#0000FF" : "#FF0000"))
            store.register(image, as: request.ref)
        }
    }

    static func middlePixel(_ document: PhotonzDocument, store: ImageStore,
                            atMS ms: Int) throws -> (r: Int, g: Int, b: Int) {
        try fillFrames(document, store: store, atMS: ms)
        let shown = document.drawn(atTimeMS: ms)
        let image = try #require(DocumentRenderer().render(shown, store: store))
        return try pixel(image, x: image.width / 2, y: image.height / 2)
    }

    static func pixel(_ image: CGImage, x: Int, y: Int) throws -> (r: Int, g: Int, b: Int) {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(data: &bytes, width: image.width, height: image.height,
                                             bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                             space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    @Test("Half way through a dissolve, the picture is half one shot and half the other")
    func aDissolveIsHalfAndHalf() throws {
        let (base, store) = try Self.document()
        var document = base
        let put = document.setClipTransition(try #require(document.layers.first).id, atCut: 1,
                                             to: ClipTransition(kind: .dissolve, lengthMS: 1000))
        #expect(put)
        // Before it, the first shot alone.
        let before = try Self.middlePixel(document, store: store, atMS: 1000)
        #expect(before.r > 200 && before.b < 40)
        // On the cut, both of them at once. The numbers are not 128: the
        // composite happens in linear light, where half way between two
        // colours reads about 188 once it is written back out as sRGB.
        let middle = try Self.middlePixel(document, store: store, atMS: 3000)
        #expect(middle.r > 120 && middle.r < 230)
        #expect(middle.b > 120 && middle.b < 230)
        // After it, the second shot alone.
        let after = try Self.middlePixel(document, store: store, atMS: 5000)
        #expect(after.b > 200 && after.r < 40)
    }

    @Test("On a dip to black, the frame on the cut really is black")
    func aDipIsBlackOnTheCut() throws {
        let (base, store) = try Self.document()
        var document = base
        let put = document.setClipTransition(try #require(document.layers.first).id, atCut: 1,
                                             to: ClipTransition(kind: .dipToBlack, lengthMS: 1000))
        #expect(put)
        let onTheCut = try Self.middlePixel(document, store: store, atMS: 3000)
        #expect(onTheCut.r < 12 && onTheCut.g < 12 && onTheCut.b < 12)
        // Half way into it, on its way down, and still nothing like black.
        let halfway = try Self.middlePixel(document, store: store, atMS: 2750)
        #expect(halfway.r > 90 && halfway.r < 250)
        // ...and clear of it, the shot is its own colour again.
        let clear = try Self.middlePixel(document, store: store, atMS: 1000)
        #expect(clear.r > 200)
    }

    @Test("A dip to white goes through white")
    func aDipToWhiteIsWhiteOnTheCut() throws {
        let (base, store) = try Self.document()
        var document = base
        let put = document.setClipTransition(try #require(document.layers.first).id, atCut: 1,
                                             to: ClipTransition(kind: .dipToWhite, lengthMS: 1000))
        #expect(put)
        let onTheCut = try Self.middlePixel(document, store: store, atMS: 3000)
        #expect(onTheCut.r > 240 && onTheCut.g > 240 && onTheCut.b > 240)
    }
}
