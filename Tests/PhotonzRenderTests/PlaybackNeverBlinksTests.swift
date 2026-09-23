import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// Playing a recording never blinks (`playing-a-recording-never-blinks`).
///
/// What the model's tests say about which frame a late moment points at, said
/// here as the pixels the canvas actually gets, through `renderInteractive`,
/// which is what the canvas draws with. Two ways it used to blink: a frame not
/// yet read drew as nothing, and the redraw that ran when it landed handed back
/// the cached nothing because the document had not changed.
@Suite("Playing a recording never draws an empty frame")
struct PlaybackNeverBlinksTests {

    static let canvas = CGSize(width: 64, height: 40)

    static func movie() -> MovieRef {
        MovieRef(pixelSize: canvas, durationMS: 8000)
    }

    static func ms(_ frame: Int) -> Int { frame * MovieRef.frameStepMS }

    static func file(_ movie: MovieRef, frame: Int, hex: String, in store: ImageStore,
                     size: CGSize = canvas) throws {
        let image = try #require(SolidImage.make(size: size, hex: hex))
        store.register(image, as: movie.frameRef(atSourceMS: ms(frame)))
    }

    static func middle(_ image: CGImage?) throws -> (r: Int, g: Int, b: Int, a: Int) {
        let image = try #require(image)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(data: &bytes, width: image.width, height: image.height,
                                             bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = ((image.height / 2) * image.width + image.width / 2) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]), Int(bytes[offset + 3]))
    }

    @Test("A moment whose frame is not read yet shows the frame before it, never transparent")
    func aLateFrameHoldsTheLastPicture() throws {
        let movie = Self.movie()
        let document = PhotonzDocument.recording(movie, name: "Take 1")
        let store = ImageStore()
        let renderer = DocumentRenderer()
        try Self.file(movie, frame: 10, hex: "#FF0000", in: store)
        var inHand = MovieFramesInHand()
        inHand.insert(movie: movie.id, frameIndex: 10)

        let before = try Self.middle(renderer.renderInteractive(
            document.drawn(atTimeMS: Self.ms(10), framesInHand: inHand), store: store))
        #expect(before.r > 200 && before.a == 255)

        // Frame 11 is still being read when the playhead reaches it.
        let late = try Self.middle(renderer.renderInteractive(
            document.drawn(atTimeMS: Self.ms(11), framesInHand: inHand), store: store))
        #expect(late.a == 255, "the clip area went empty while its frame was being read")
        #expect(late.r > 200)
    }

    @Test("When the late frame lands, the redraw shows it")
    func theLandingRedrawShowsTheNewFrame() throws {
        let movie = Self.movie()
        let document = PhotonzDocument.recording(movie, name: "Take 1")
        let store = ImageStore()
        let renderer = DocumentRenderer()
        try Self.file(movie, frame: 10, hex: "#FF0000", in: store)
        var inHand = MovieFramesInHand()
        inHand.insert(movie: movie.id, frameIndex: 10)
        _ = renderer.renderInteractive(document.drawn(atTimeMS: Self.ms(11), framesInHand: inHand),
                                       store: store)

        try Self.file(movie, frame: 11, hex: "#0000FF", in: store)
        inHand.insert(movie: movie.id, frameIndex: 11)
        let landed = try Self.middle(renderer.renderInteractive(
            document.drawn(atTimeMS: Self.ms(11), framesInHand: inHand), store: store))
        #expect(landed.b > 200 && landed.r < 40)
    }

    @Test("A frame that was missing and then lands is drawn, even though the document did not change")
    func aMissingPictureThatLandsIsNotANoOp() throws {
        // The very first frame of a recording: nothing in hand to hold, so the
        // first draw is empty. The frame landing must not be answered with that
        // empty frame from the cache.
        let movie = Self.movie()
        let shown = PhotonzDocument.recording(movie, name: "Take 1").drawn(atTimeMS: 0)
        let store = ImageStore()
        let renderer = DocumentRenderer()
        let empty = try Self.middle(renderer.renderInteractive(shown, store: store))
        #expect(empty.a == 0)

        try Self.file(movie, frame: 0, hex: "#00FF00", in: store)
        let landed = try Self.middle(renderer.renderInteractive(shown, store: store))
        #expect(landed.g > 200 && landed.a == 255)
    }

    @Test("A frame read again at a bigger size is redrawn with the bigger one")
    func aPictureReplacedUnderTheSameRefIsRedrawn() throws {
        let movie = Self.movie()
        let shown = PhotonzDocument.recording(movie, name: "Take 1").drawn(atTimeMS: 0)
        let store = ImageStore()
        let renderer = DocumentRenderer()
        try Self.file(movie, frame: 0, hex: "#FF0000", in: store,
                      size: CGSize(width: 16, height: 10))
        let small = try Self.middle(renderer.renderInteractive(shown, store: store))
        #expect(small.r > 200)

        try Self.file(movie, frame: 0, hex: "#0000FF", in: store)
        let big = try Self.middle(renderer.renderInteractive(shown, store: store))
        #expect(big.b > 200 && big.r < 40)
    }
}
