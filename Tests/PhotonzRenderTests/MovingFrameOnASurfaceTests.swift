import CoreGraphics
import CoreVideo
import Foundation
import IOSurface
import PhotonzCore
@testable import PhotonzRender
import Testing

/// A whole picture of a video the canvas shows is drawn onto a GPU surface
/// and shown from there (`DocumentRenderer.renderInteractiveFrame`), rather
/// than read back off the GPU into a bitmap and copied again for the canvas.
/// On the 6 minute reference edit the read back and the copy were about two
/// milliseconds of every picture a hand dragging the playhead waited for
/// (`a-long-edit-with-transitions-plays-scrubs-and-ed`, pass 17). The surface
/// has to show exactly what the bitmap showed, and a small edit after it must
/// still be drawn right.
@Suite("A video's picture kept on a surface")
struct MovingFrameOnASurfaceTests {

    static let canvas = CGSize(width: 64, height: 40)

    static func movie() -> MovieRef { MovieRef(pixelSize: canvas, durationMS: 8000) }
    static func ms(_ frame: Int) -> Int { MovieRef.gridMS(ofFrame: frame) }

    /// A frame with a different colour on each half, so the way up shows.
    static func file(_ movie: MovieRef, frame: Int, top: String, bottom: String,
                     in store: ImageStore) throws {
        let width = Int(canvas.width), height = Int(canvas.height)
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        func colour(_ hex: String) -> CGColor {
            let v = Int(hex.dropFirst(), radix: 16) ?? 0
            return CGColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255,
                           blue: CGFloat(v & 255) / 255, alpha: 1)
        }
        context.setFillColor(colour(bottom))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        context.setFillColor(colour(top))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        store.register(try #require(context.makeImage()), as: movie.frameRef(atSourceMS: ms(frame)))
    }

    static func drawn(_ document: PhotonzDocument, frame: Int, movie: MovieRef) -> PhotonzDocument {
        var inHand = MovieFramesInHand()
        inHand.insert(movie: movie.id, frameIndex: frame)
        return document.drawn(atTimeMS: ms(frame), framesInHand: inHand)
    }

    static func bytes(_ image: CGImage) -> [UInt8] {
        FrameOnASurfaceTests.bytes(image)
    }

    @Test("A video's picture comes on a surface, and shows what the read back showed")
    func theSurfaceShowsTheSamePicture() throws {
        let movie = Self.movie()
        let document = PhotonzDocument.recording(movie, name: "Take 1")
        let store = ImageStore()
        try Self.file(movie, frame: 10, top: "#20E040", bottom: "#E02010", in: store)
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))

        let onASurface = DocumentRenderer()
        let readBack = DocumentRenderer()
        readBack.drawsMovingPicturesOnASurface = false
        let shown = Self.drawn(document, frame: 10, movie: movie)
        let new = try #require(onASurface.renderInteractiveFrame(shown, store: store, colorSpace: p3))
        let old = try #require(readBack.renderInteractive(shown, store: store, colorSpace: p3))
        #expect(new.surface != nil, "a video's whole picture is drawn onto a surface")
        #expect(new.image.width == old.width && new.image.height == old.height)
        #expect(new.image.colorSpace?.name == p3.name)
        #expect(FrameOnASurfaceTests.largestDifference(Self.bytes(old), Self.bytes(new.image)) <= 1)
        // The right way up: green along the top.
        let top = Self.bytes(new.image)
        #expect(top[1] > 200 && top[0] < 80)
        if let surface = new.surface {
            #expect(IOSurfaceGetWidth(surface) == old.width && IOSurfaceGetHeight(surface) == old.height)
        }
    }

    @Test("A small change after a picture on a surface is drawn right, and a still one is patched again")
    func aSmallEditAfterASurfaceIsDrawnRight() throws {
        let movie = Self.movie()
        var document = PhotonzDocument.recording(movie, name: "Take 1")
        let store = ImageStore()
        try Self.file(movie, frame: 10, top: "#2040E0", bottom: "#2040E0", in: store)
        let spot = try #require(SolidImage.make(size: CGSize(width: 6, height: 6), hex: "#FFFFFF"))
        let spotRef = store.register(spot)
        document.layers.append(Layer(name: "Spot", content: .image(spotRef),
                                     frame: CGRect(x: 2, y: 2, width: 6, height: 6)))
        let renderer = DocumentRenderer()
        let first = try #require(renderer.renderInteractiveFrame(Self.drawn(document, frame: 10, movie: movie),
                                                                 store: store))
        #expect(first.surface != nil)

        // The spot moves a little: a patch's worth.
        for x in [10, 20, 30] {
            document.layers[document.layers.count - 1].frame.origin.x = CGFloat(x)
            let shown = Self.drawn(document, frame: 10, movie: movie)
            let frame = try #require(renderer.renderInteractiveFrame(shown, store: store))
            let fresh = try #require(DocumentRenderer().renderInteractive(shown, store: store))
            #expect(FrameOnASurfaceTests.largestDifference(Self.bytes(fresh), Self.bytes(frame.image)) <= 1,
                    "the spot at \(x) drew as a fresh render does")
        }
    }

    @Test("A still picture is never put on a surface: its edits stay patches")
    func aStillPictureStaysInTheBitmap() throws {
        let store = ImageStore()
        let base = try #require(SolidImage.make(size: CGSize(width: 64, height: 40), hex: "#FF0000"))
        let document = PhotonzDocument.withBaseImage(store.register(base))
        #expect(!document.hasTime)
        let frame = try #require(DocumentRenderer().renderInteractiveFrame(document, store: store))
        #expect(frame.surface == nil)
    }

    @Test("Pictures one after another reuse a few surfaces rather than making one each")
    func surfacesAreReused() throws {
        let movie = Self.movie()
        let document = PhotonzDocument.recording(movie, name: "Take 1")
        let store = ImageStore()
        let renderer = DocumentRenderer()
        var seen = Set<UInt32>()
        for frame in 0..<24 {
            try Self.file(movie, frame: frame, top: frame.isMultiple(of: 2) ? "#FF0000" : "#00FF00",
                          bottom: "#0000FF", in: store)
            let drawn = try #require(renderer.renderInteractiveFrame(Self.drawn(document, frame: frame, movie: movie),
                                                                     store: store))
            let surface = try #require(drawn.surface)
            seen.insert(IOSurfaceGetID(surface))
        }
        #expect(seen.count <= 4, "\(seen.count) surfaces for 24 pictures")
    }
}
