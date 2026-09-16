import AppKit
import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// An icon drawn on a blank canvas, handed to somebody else.
///
/// The canvas a drawing is made on is a real full-size bitmap of white
/// (`FlatBitmap`), and until Export could leave it out, every icon went out
/// with a white rectangle the size of the canvas behind it: fine on a white
/// page, a white box on anything else. These check the whole path — a real
/// bitmap, read for its colour, written out and drawn back — rather than the
/// text of the file.
@Suite("An exported icon carries only what was drawn")
struct SVGExportBackgroundTests {

    static let canvas = CGSize(width: 200, height: 160)

    /// A blue triangle on a white canvas, exactly as New Canvas plus the Pen
    /// leaves it.
    static func iconOnABlankCanvas(_ hex: String = "#FFFFFF")
        throws -> (document: PhotonzDocument, store: ImageStore) {
        let store = ImageStore()
        let white = try #require(SolidImage.make(size: canvas, hex: hex))
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

    @Test func theCanvasADrawingSitsOnIsFoundThroughTheRealBitmap() throws {
        let (document, store) = try Self.iconOnABlankCanvas()
        let found = SVGExporter.backdrop(in: document, store: store)
        #expect(found?.layerID == document.layers[0].id)
    }

    @Test func aScreenshotIsNeverTakenForTheCanvas() throws {
        // A picture with two colours in it is a picture, not a canvas.
        let store = ImageStore()
        let shot = try #require(Self.twoTone(size: Self.canvas))
        let document = PhotonzDocument.withBaseImage(store.register(shot))
        #expect(SVGExporter.backdrop(in: document, store: store) == nil)
    }

    @Test func keepingTheBackgroundDrawsWhatTheCanvasDraws() throws {
        let (document, store) = try Self.iconOnABlankCanvas()
        let renderer = DocumentRenderer()
        let mine = try #require(renderer.render(document, store: store))
        let theirs = try #require(try Self.rasterize(document, store: store, background: .keep))
        #expect(SVGExportRenderTests.meanDifference(
            between: SVGExportRenderTests.pixels(of: mine, size: Self.canvas),
            and: theirs) <= 1)
    }

    @Test func droppingTheBackgroundDrawsTheIconOverNothing() throws {
        var (document, store) = try Self.iconOnABlankCanvas()
        let theirs = try #require(try Self.rasterize(document, store: store, background: .drop))
        // Nothing at all in the corner...
        #expect(Self.alpha(theirs, x: 4, y: 4) == 0)
        #expect(Self.alpha(theirs, x: 195, y: 155) == 0)
        // ...and the triangle exactly where it was.
        #expect(Self.alpha(theirs, x: 100, y: 60) == 255)

        // And it is the same icon: the canvas with its background hidden draws
        // the same picture the file does.
        document.layers[0].isVisible = false
        let mine = try #require(DocumentRenderer().render(document, store: store))
        #expect(SVGExportRenderTests.meanDifference(
            between: SVGExportRenderTests.pixels(of: mine, size: Self.canvas),
            and: theirs) <= 1)
    }

    @Test func aScreenshotKeepsItsPictureEvenWhenTheBackgroundIsDropped() throws {
        let store = ImageStore()
        let shot = try #require(Self.twoTone(size: Self.canvas))
        let document = PhotonzDocument.withBaseImage(store.register(shot))
        let dropped = SVGExporter.export(document, store: store, background: .drop)
        let kept = SVGExporter.export(document, store: store, background: .keep)
        #expect(dropped.text == kept.text)
        #expect(dropped.text.contains("<image "))
    }

    // MARK: - Scenery

    /// A picture that is two colours, so it can never pass for a flat canvas.
    static func twoTone(size: CGSize) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)
                                          ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        return context.makeImage()
    }

    /// The exported file, drawn back at canvas size.
    static func rasterize(_ document: PhotonzDocument, store: ImageStore,
                          background: SVGExport.Background) throws -> [UInt8]? {
        let result = SVGExporter.export(document, store: store, background: background)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-svg-bg-\(UUID().uuidString).svg")
        try result.text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return SVGExportRenderTests.rasterize(url, size: document.canvasSize)
    }

    /// How opaque one pixel of a rasterized file is, counting y from the top
    /// the way the document does.
    static func alpha(_ bytes: [UInt8], x: Int, y: Int) -> UInt8 {
        let flipped = Int(canvas.height) - 1 - y
        let index = (flipped * Int(canvas.width) + x) * 4 + 3
        return bytes.indices.contains(index) ? bytes[index] : 0
    }
}
