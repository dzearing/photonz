import CoreGraphics
import Foundation
import ImageIO
import PhotonzCore
import PhotonzRender
import Testing

/// An icon exported as a PICTURE, with and without the canvas it was drawn on.
///
/// SVG could leave the canvas out first; a PNG handed to somebody else has the
/// same problem and needed the same answer. These read the real file back, so
/// what is checked is the bytes that would land on disk rather than the
/// intention behind them.
@Suite("An icon exported as a picture can leave its canvas out")
struct PictureExportBackgroundTests {

    static let canvas = CGSize(width: 200, height: 160)

    static func iconOnABlankCanvas() throws -> (document: PhotonzDocument, store: ImageStore) {
        let store = ImageStore()
        let white = try #require(SolidImage.make(size: canvas, hex: "#FFFFFF"))
        var document = PhotonzDocument.withBaseImage(store.register(white))
        var content = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 90, y: 0)),
            PathAnchor(point: CGPoint(x: 45, y: 80))
        ], isClosed: true)
        content.fillColorHex = "#2E6BFF"
        content.colorHex = "#2E6BFF"
        content.strokeWidth = 0
        document.layers.append(Layer(name: "Triangle", content: .path(content),
                                     frame: CGRect(x: 55, y: 40, width: 90, height: 80)))
        return (document, store)
    }

    // MARK: - What the formats can hold

    @Test func onlyTheFormatsThatCanHoldTransparencySayTheyCan() {
        #expect(ImageCodec.Format.png.holdsTransparency)
        #expect(ImageCodec.Format.webp.holdsTransparency)
        #expect(!ImageCodec.Format.jpeg.holdsTransparency)
        #expect(!ImageCodec.Format.heic.holdsTransparency)
    }

    // MARK: - The file itself

    @Test func aPNGWithTheCanvasLeftOutIsEmptyInEveryCorner() async throws {
        let (document, store) = try Self.iconOnABlankCanvas()
        let png = try await Self.write(document, store: store, format: .png, background: .drop)
        let pixels = try Self.read(png)
        for corner in Self.corners {
            #expect(Self.alpha(pixels, at: corner) == 0)
        }
        // The drawing itself is untouched: the middle of the triangle is solid.
        #expect(Self.alpha(pixels, at: CGPoint(x: 100, y: 60)) == 255)
    }

    @Test func aPNGWithTheCanvasKeptIsWhiteInEveryCorner() async throws {
        let (document, store) = try Self.iconOnABlankCanvas()
        let png = try await Self.write(document, store: store, format: .png, background: .keep)
        let pixels = try Self.read(png)
        for corner in Self.corners {
            #expect(Self.alpha(pixels, at: corner) == 255)
        }
    }

    @Test func aFormatThatCannotHoldTransparencyKeepsTheCanvasWhateverItIsAsked()
        async throws {
        let (document, store) = try Self.iconOnABlankCanvas()
        let asked = try await Self.write(document, store: store, format: .jpeg, background: .drop)
        let kept = try await Self.write(document, store: store, format: .jpeg, background: .keep)
        #expect(asked == kept)
    }

    @Test func aScreenshotCarriesItsBackgroundEvenWhenTheCanvasIsAskedFor() async throws {
        let store = ImageStore()
        let shot = try #require(SVGExportBackgroundTests.twoTone(size: Self.canvas))
        let document = PhotonzDocument.withBaseImage(store.register(shot))
        let dropped = try await Self.write(document, store: store, format: .png, background: .drop)
        let kept = try await Self.write(document, store: store, format: .png, background: .keep)
        #expect(dropped == kept)
        let pixels = try Self.read(dropped)
        for corner in Self.corners {
            #expect(Self.alpha(pixels, at: corner) == 255)
        }
    }

    @Test func leavingTheCanvasOutIsADifferentFileToWeigh() async throws {
        let (document, store) = try Self.iconOnABlankCanvas()
        let sizer = ExportSizer(renderer: DocumentRenderer(), store: store)
        let dropped = await sizer.byteCount(of: document, frameID: nil, scale: 1, format: .png,
                                            quality: 1, background: .drop)
        let kept = await sizer.byteCount(of: document, frameID: nil, scale: 1, format: .png,
                                         quality: 1, background: .keep)
        #expect(dropped != nil)
        #expect(kept != nil)
        #expect(dropped != kept)
    }

    // MARK: - Scenery

    static let corners = [CGPoint(x: 4, y: 4), CGPoint(x: 195, y: 4),
                          CGPoint(x: 4, y: 155), CGPoint(x: 195, y: 155)]

    static func write(_ document: PhotonzDocument, store: ImageStore,
                      format: ImageCodec.Format,
                      background: SVGExport.Background) async throws -> Data {
        let sizer = ExportSizer(renderer: DocumentRenderer(), store: store)
        return try #require(await sizer.data(of: document, frameID: nil, scale: 1,
                                             format: format, quality: 1,
                                             background: background))
    }

    /// The written file drawn back into straight sRGB bytes. Core Graphics
    /// draws from the bottom up, so row zero is the bottom of the picture and
    /// `alpha(_:at:)` turns a document point back into it.
    static func read(_ data: Data) throws -> [UInt8] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = Int(canvas.width), height = Int(canvas.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { raw in
            let context = try #require(CGContext(data: raw.baseAddress, width: width,
                                                 height: height, bitsPerComponent: 8,
                                                 bytesPerRow: width * 4,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)
                                                     ?? CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo
                                                     .premultipliedLast.rawValue))
            context.draw(image, in: CGRect(origin: .zero, size: canvas))
        }
        return bytes
    }

    /// How opaque one pixel is, at a point counted from the TOP left the way
    /// the document counts.
    static func alpha(_ bytes: [UInt8], at point: CGPoint) -> UInt8 {
        let flipped = Int(canvas.height) - 1 - Int(point.y)
        let index = (flipped * Int(canvas.width) + Int(point.x)) * 4 + 3
        return bytes.indices.contains(index) ? bytes[index] : 0
    }
}
