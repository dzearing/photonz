import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The one-click blur-behind recipe: one full-canvas raster becomes two
/// layers — a blurred backdrop and a sharp focal cutout cropped to the
/// selection — so everything except the selection reads as blurred.
@Suite("Blur behind")
struct BlurBehindTests {

    private func makeDocument() -> PhotonzDocument {
        PhotonzDocument.withBaseImage(ImageRef(pixelSize: CGSize(width: 800, height: 600)))
    }

    @Test func addsBlurredBackdropAndSharpFocusOnTop() {
        var doc = makeDocument()
        let ref = ImageRef(pixelSize: CGSize(width: 800, height: 600))
        let selection = CGRect(x: 100, y: 100, width: 200, height: 150)

        let layers = doc.blurBehind(selection: selection, rasterized: ref, blurRadius: 20)

        #expect(doc.layers.count == 3)
        #expect(doc.layers[1].id == layers.blur.id)
        #expect(doc.layers[2].id == layers.focus.id)

        // The blurred backdrop covers the whole canvas.
        #expect(layers.blur.frame == CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(layers.blur.style.blurRadius == 20)
        #expect(layers.blur.content == .image(ref))

        // The focus layer shares the same raster, cropped to the selection,
        // and stays sharp.
        #expect(layers.focus.frame == selection)
        #expect(layers.focus.crop == selection) // 1:1 canvas raster → same rect
        #expect(layers.focus.style.blurRadius == 0)
        #expect(layers.focus.content == .image(ref))
    }

    @Test func selectionIsClampedToCanvas() {
        var doc = makeDocument()
        let ref = ImageRef(pixelSize: CGSize(width: 800, height: 600))
        let layers = doc.blurBehind(selection: CGRect(x: 700, y: 500, width: 300, height: 300),
                                    rasterized: ref, blurRadius: 12)
        #expect(layers.focus.frame == CGRect(x: 700, y: 500, width: 100, height: 100))
    }
}
