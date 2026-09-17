import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// What a document looks like when an export is told to leave the canvas out.
///
/// The picture path cannot write a file with a layer missing the way the SVG
/// writer can simply not write a rectangle: it renders the document. So the
/// answer for a picture is the document itself with the canvas hidden, and
/// these hold that to the same rules the SVG side follows — the canvas goes,
/// nothing else does, and a drawing with no canvas under it is untouched.
@Suite("Leaving the canvas out of an export")
struct ExportBackgroundTests {

    static let canvas = CGSize(width: 200, height: 160)

    /// A blank white canvas with a shape drawn on it, exactly as New Canvas
    /// plus the Pen leaves it.
    static func iconOnABlankCanvas() -> (document: PhotonzDocument, flat: [UUID: RGBA]) {
        let ref = ImageRef(pixelSize: canvas)
        var document = PhotonzDocument.withBaseImage(ref)
        document.canvasSize = canvas
        var content = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 90, y: 0)),
            PathAnchor(point: CGPoint(x: 45, y: 80))
        ], isClosed: true)
        content.fillColorHex = "#2E6BFF"
        document.layers.append(Layer(name: "Triangle", content: .path(content),
                                     frame: CGRect(x: 55, y: 40, width: 90, height: 80)))
        return (document, [ref.id: RGBA(r: 1, g: 1, b: 1, a: 1)])
    }

    @Test func droppingTheBackgroundHidesTheCanvasAndNothingElse() {
        let (document, flat) = Self.iconOnABlankCanvas()
        let dropped = document.drawn(with: .drop, flatImages: flat)
        #expect(dropped.layers[0].isVisible == false)
        #expect(dropped.layers[1].isVisible)
        #expect(dropped.layers.count == document.layers.count)
        #expect(dropped.canvasSize == document.canvasSize)
    }

    @Test func keepingTheBackgroundChangesNothingAtAll() {
        let (document, flat) = Self.iconOnABlankCanvas()
        #expect(document.drawn(with: .keep, flatImages: flat) == document)
    }

    @Test func aScreenshotHasNoCanvasToLeaveOut() {
        // No flat colour known for the bottom bitmap: it is a photograph, so
        // there is nothing under the drawing to take away.
        let (document, _) = Self.iconOnABlankCanvas()
        #expect(document.drawn(with: .drop, flatImages: [:]) == document)
    }

    @Test func aDrawingWithNoCanvasUnderItIsUntouched() {
        var (document, flat) = Self.iconOnABlankCanvas()
        document.layers.removeFirst()
        #expect(document.drawn(with: .drop, flatImages: flat) == document)
    }
}
