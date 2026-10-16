import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore
@testable import PhotonzRender

/// An SVG brought into a video stays sharp at any size (`video-title-wt.html`,
/// the Media shelf: "It keeps its own scale, so blowing one up on a 4K frame
/// stays crisp"). The store keeps the file's bytes, the renderer draws them at
/// the size the frame is seen at, and a saved package carries them.
@Suite("An SVG stays sharp at any size")
struct VectorArtTests {

    /// The logo the walks bring in: an orange tile with a white dot and two
    /// bars of type, 240 by 96.
    static let logoSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="240" height="96" viewBox="0 0 240 96">
      <rect x="4" y="4" width="88" height="88" rx="20" fill="#FF6A3D"/>
      <circle cx="48" cy="48" r="22" fill="#FFFFFF"/>
      <rect x="108" y="30" width="124" height="14" rx="7" fill="#1E2A44"/>
      <rect x="108" y="54" width="84" height="12" rx="6" fill="#5B6B8C"/>
    </svg>
    """

    init() { VectorArtTestReader.install() }

    private func logo() throws -> VectorArt {
        try #require(VectorArt.read(Data(Self.logoSVG.utf8)))
    }

    // MARK: - Reading

    @Test func anSVGIsReadAtTheSizeItSays() throws {
        let art = try logo()
        #expect(art.size == CGSize(width: 240, height: 96))
        #expect(art.pixelSize == CGSize(width: 240, height: 96))
    }

    @Test func bytesThatAreNoDrawingReadAsNothing() {
        #expect(VectorArt.read(Data("hello".utf8)) == nil)
        // A drawing with no size and no view box has nothing to be drawn at.
        #expect(VectorArt.read(Data("<svg xmlns='http://www.w3.org/2000/svg'><g/></svg>".utf8)) == nil)
    }

    /// The store keeps the file's own bytes beside a picture of it at its own
    /// size, which is what a thumbnail or a flattened copy reads.
    @Test func theStoreKeepsTheDrawingBesideAPictureOfIt() throws {
        let store = ImageStore()
        let art = try logo()
        let ref = try #require(store.register(art))
        #expect(ref.pixelSize == CGSize(width: 240, height: 96))
        let picture = try #require(store.image(for: ref))
        #expect(picture.width == 240 && picture.height == 96)
        #expect(store.vector(for: ref) == art)
        #expect(store.snapshot().vector(for: ref) == art)
        // New pixels under the same ref are what it now is.
        store.register(picture, as: ref)
        #expect(store.vector(for: ref) == nil)
    }

    // MARK: - How big it is drawn

    /// Never fewer pixels than the frame, so it is only ever brought down.
    @Test func itIsNeverDrawnSmallerThanItsFrame() throws {
        for side in stride(from: 1.0, through: 6000.0, by: 7.3) {
            let size = CGSize(width: side, height: side * 0.4)
            let drawn = try #require(VectorArt.drawingSize(for: CGSize(width: max(side, 1),
                                                                      height: max(side * 0.4, 1))))
            #expect(CGFloat(drawn.width) >= size.width.rounded(.down), "\(side)")
            #expect(CGFloat(drawn.width) <= max(size.width * 1.2, size.width + 2), "\(side)")
        }
    }

    /// A logo growing from its own size to fill a 4K frame, one pixel a
    /// frame, is drawn a handful of times rather than once a frame.
    @Test func aGrowingLogoIsDrawnAHandfulOfTimes() {
        var sizes = Set<Int>()
        for width in 240...3840 {
            if let drawn = VectorArt.drawingSize(for: CGSize(width: width, height: width * 2 / 5)) {
                sizes.insert(drawn.width)
            }
        }
        #expect(sizes.count <= 18)
    }

    @Test func aDrawingFarPastTheFrameIsHeldToAWorkableSize() throws {
        let drawn = try #require(VectorArt.drawingSize(for: CGSize(width: 40_000, height: 16_000)))
        #expect(drawn.width <= VectorArt.longestDrawnSide)
        #expect(drawn.width * drawn.height <= VectorArt.mostDrawnPixels + drawn.width + drawn.height)
    }

    // MARK: - Sharp on a 4K frame

    /// How many pixels it takes the orange tile's left edge to go from clear
    /// to solid, along the row through its middle: one or two for a hard
    /// edge, about the blow-up factor for a picture stretched.
    static func edgeRamp(_ image: CGImage, row: Int, from: Int, to: Int) -> Int {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var ramp = 0
        for x in from..<to {
            let alpha = Int(bytes[(row * width + x) * 4 + 3])
            if alpha > 25 && alpha < 230 { ramp += 1 }
        }
        return ramp
    }

    /// The same logo blown up sixteen times across a 3840 by 2160 frame, once
    /// as the SVG and once as a 240 by 96 bitmap of it.
    private func fourKFrame(_ ref: ImageRef) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 3840, height: 2160), layers: [])
        document.addLayer(Layer(name: "Acme Logo", content: .image(ref),
                                frame: CGRect(x: 0, y: 312, width: 3840, height: 1536)))
        return document
    }

    @Test func anSVGFillingA4KFrameIsAsSharpAsOneDrawnThere() throws {
        let art = try logo()
        // What the drawing looks like drawn natively at that size: the bar.
        let native = try #require(art.drawn(width: 3840, height: 1536))
        let nativeRamp = Self.edgeRamp(native, row: 768, from: 0, to: 400)

        let store = ImageStore()
        let ref = try #require(store.register(art))
        let frame = try #require(DocumentRenderer().render(fourKFrame(ref), store: store))
        let drawnRamp = Self.edgeRamp(frame, row: 312 + 768, from: 0, to: 400)

        // The weak version, the same art kept as pixels, fails the same bar.
        let bitmapStore = ImageStore()
        let bitmap = bitmapStore.register(try #require(store.image(for: ref)))
        let soft = try #require(DocumentRenderer().render(fourKFrame(bitmap), store: bitmapStore))
        let softRamp = Self.edgeRamp(soft, row: 312 + 768, from: 0, to: 400)

        // A hard edge is a pixel or two of blend wherever it falls (drawn a
        // step past the frame and brought down, it reads 2 where the native
        // draw, its edge on a pixel boundary, reads 0); the bitmap stretched
        // sixteen times reads 12.
        #expect(nativeRamp <= 1)
        #expect(drawnRamp <= nativeRamp + 2, "drawn \(drawnRamp) native \(nativeRamp)")
        #expect(softRamp >= 8, "a stretched bitmap read \(softRamp)")
    }

    /// An export at twice the document's size draws the drawing at the
    /// export's pixels too, as it does the words in a title.
    @Test func anExportAtTwiceTheSizeDrawsItSharp() throws {
        let store = ImageStore()
        let ref = try #require(store.register(try logo()))
        var document = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080), layers: [])
        document.addLayer(Layer(name: "Acme Logo", content: .image(ref),
                                frame: CGRect(x: 0, y: 156, width: 1920, height: 768)))
        let frame = try #require(DocumentRenderer().render(document, store: store, scale: 2))
        #expect(frame.width == 3840)
        #expect(Self.edgeRamp(frame, row: 312 + 768, from: 0, to: 400) <= 3)
    }

    /// Held still, it is drawn once: the next frame comes out of the cache.
    @Test func aStillLogoIsDrawnOnce() throws {
        let store = ImageStore()
        let ref = try #require(store.register(try logo()))
        let renderer = DocumentRenderer()
        let document = fourKFrame(ref)
        _ = renderer.render(document, store: store)
        let misses = renderer.contentCacheMisses
        _ = renderer.render(document, store: store)
        #expect(renderer.contentCacheMisses == misses)
    }

    // MARK: - Saved and opened again

    @Test func theSVGTravelsInASavedProjectAndOpensSharp() throws {
        let store = ImageStore()
        let art = try logo()
        let ref = try #require(store.register(art))
        let document = fourKFrame(ref)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vector-\(UUID().uuidString).photonz")
        defer { try? FileManager.default.removeItem(at: url) }
        try PackageIO.write(document, store: store, to: url)
        let svg = url.appendingPathComponent("images").appendingPathComponent("\(ref.id.uuidString).svg")
        #expect(try Data(contentsOf: svg) == art.data)

        let reopened = ImageStore()
        let opened = try PackageIO.read(from: url, into: reopened)
        #expect(reopened.vector(for: ref) == art)
        let frame = try #require(DocumentRenderer().render(opened, store: reopened))
        #expect(Self.edgeRamp(frame, row: 312 + 768, from: 0, to: 400) <= 3)
    }

    /// A drawing on the shelf that nothing draws yet is carried too.
    @Test func aShelvedSVGIsCarriedInASavedProject() throws {
        let store = ImageStore()
        let ref = try #require(store.register(try logo()))
        var document = PhotonzDocument(canvasSize: CGSize(width: 1280, height: 720), layers: [])
        document.bringIntoLibrary([DocumentMediaSource(media: .picture(ref), name: "Acme Logo.svg")])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vector-shelf-\(UUID().uuidString).photonz")
        defer { try? FileManager.default.removeItem(at: url) }
        try PackageIO.write(document, store: store, to: url)
        let reopened = ImageStore()
        _ = try PackageIO.read(from: url, into: reopened)
        #expect(reopened.vector(for: ref) != nil)
    }

    // MARK: - Dragged over the canvas

    @Test func anSVGOverAVideoLandsAsAPictureAtItsOwnSize() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-drop-\(UUID().uuidString)-Logo.svg")
        try Data(Self.logoSVG.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CanvasFileDrop.of(url, takingMedia: true) == .picture(CGSize(width: 240, height: 96)))
    }
}

/// The app's way of reading an SVG (`SVGDrawing` in the app), here so the
/// renderer's tests draw drawings the way the app does.
enum VectorArtTestReader {
    static func install() {
        VectorArt.install(VectorArt.Reader(
            size: { data in NSImage(data: data)?.size },
            draw: { data, width, height in
                guard let image = NSImage(data: data),
                      let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return nil }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
                NSGraphicsContext.restoreGraphicsState()
                return context.makeImage()
            }))
    }
}
