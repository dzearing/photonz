import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// Copying a picture leaves a blank canvas out the way Export does.
///
/// Export learned to leave the white canvas out of an icon first, and Copy went
/// on putting it on the clipboard, so the icon you saved was see-through and
/// the icon you pasted was not. These check the picture a copy draws, and that
/// only the canvas's own bitmap is read to decide it, because Copy is pressed
/// far more often than Export is.
@Suite("A copied picture leaves a blank canvas out")
struct CopyBackgroundTests {

    typealias Scenery = PictureExportBackgroundTests

    @Test func aCopyOfAnIconOnABlankCanvasIsEmptyInEveryCorner() throws {
        let (document, store) = try Scenery.iconOnABlankCanvas()
        let pixels = try Self.copied(document, store: store, background: .drop)
        for corner in Scenery.corners {
            #expect(Scenery.alpha(pixels, at: corner) == 0)
        }
        // The drawing itself comes with it.
        #expect(Scenery.alpha(pixels, at: CGPoint(x: 100, y: 60)) == 255)
    }

    @Test func aCopyWithTheCanvasAskedForIsWhiteInEveryCorner() throws {
        let (document, store) = try Scenery.iconOnABlankCanvas()
        let pixels = try Self.copied(document, store: store, background: .keep)
        for corner in Scenery.corners {
            #expect(Scenery.alpha(pixels, at: corner) == 255)
        }
    }

    @Test func aCopyOfAScreenshotCarriesItsBackground() throws {
        let store = ImageStore()
        let shot = try #require(SVGExportBackgroundTests.twoTone(size: Scenery.canvas))
        let document = PhotonzDocument.withBaseImage(store.register(shot))
        #expect(document.copied(with: .drop, store: store) == document)
        let pixels = try Self.copied(document, store: store, background: .drop)
        for corner in Scenery.corners {
            #expect(Scenery.alpha(pixels, at: corner) == 255)
        }
    }

    @Test func onlyTheBottomLayerIsReadForACanvas() throws {
        var (document, store) = try Scenery.iconOnABlankCanvas()
        // A flat sticker over the canvas is part of the drawing: it is never
        // the canvas, so there is no reason to walk its pixels.
        let sticker = try #require(SolidImage.make(size: CGSize(width: 40, height: 40), hex: "#FF0000"))
        document.layers.append(Layer(name: "Sticker", content: .image(store.register(sticker)),
                                     frame: CGRect(x: 10, y: 10, width: 40, height: 40)))
        let read = FlatBitmap.canvasColor(in: document, store: store)
        #expect(read.count == 1)
        guard case .image(let ref) = document.layers[0].content else {
            Issue.record("the canvas is a bitmap")
            return
        }
        #expect(read[ref.id] != nil)
    }

    @Test func aHiddenCanvasIsNotTheOneRead() throws {
        var (document, store) = try Scenery.iconOnABlankCanvas()
        document.layers[0].isVisible = false
        #expect(FlatBitmap.canvasColor(in: document, store: store).isEmpty)
        #expect(document.copied(with: .drop, store: store) == document)
    }

    // MARK: - Scenery

    static func copied(_ document: PhotonzDocument, store: ImageStore,
                       background: SVGExport.Background) throws -> [UInt8] {
        let drawn = document.copied(with: background, store: store)
        let image = try #require(DocumentRenderer().render(drawn, store: store))
        let png = try #require(ImageCodec.encode(image, format: .png))
        return try Scenery.read(png)
    }
}
