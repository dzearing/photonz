import AppKit
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// What an SVG will weigh, worked out before it is saved.
///
/// The Export sheet says the size of every picture format before you save it,
/// and SVG was the one that did not — which is backwards, because SVG is the
/// format people hand to somebody else. The number comes from writing the file
/// (`SVGExporter.data`) rather than from a formula, so these check the two
/// things that makes true: it moves when the file moves, and it is cheap
/// enough to ask for while somebody is still choosing.
@Suite("What an SVG will weigh")
struct SVGPreflightSizeTests {

    static let canvas = CGSize(width: 900, height: 700)

    /// An icon on a blank canvas, with as many shapes on it as a real one has.
    static func icon(shapes: Int) throws -> (document: PhotonzDocument, store: ImageStore) {
        let store = ImageStore()
        let white = try #require(SolidImage.make(size: canvas, hex: "#FFFFFF"))
        var document = PhotonzDocument.withBaseImage(store.register(white))
        for index in 0..<shapes {
            var content = PathContent(anchors: [
                PathAnchor(point: CGPoint(x: 0, y: 0)),
                PathAnchor(point: CGPoint(x: 60, y: 4)),
                PathAnchor(point: CGPoint(x: 30, y: 52))
            ], isClosed: true)
            content.fillColorHex = "#2E6BFF"
            content.colorHex = "#2E6BFF"
            content.strokeWidth = 0
            let column = CGFloat(index % 10) * 80 + 20
            let row = CGFloat(index / 10) * 60 + 20
            document.layers.append(Layer(name: "Shape \(index)", content: .path(content),
                                         frame: CGRect(x: column, y: row, width: 60, height: 52)))
        }
        return (document, store)
    }

    private static func bytes(_ document: PhotonzDocument, store: ImageStore,
                              background: SVGExport.Background = .keep) throws -> Int {
        try #require(SVGExporter.data(document, store: store, background: background)).data.count
    }

    /// The number the sheet shows is the file, not an estimate of it.
    @Test func theSizeIsTheFileItself() throws {
        let (document, store) = try Self.icon(shapes: 3)
        let written = try #require(SVGExporter.data(document, store: store))
        let again = try Self.bytes(document, store: store)
        #expect(written.data.count == again)
        #expect(written.data.count > 0)
    }

    /// The case the Export sheet exists to answer: ticking the background box
    /// writes a different file, so it has to read as a different number.
    @Test func leavingTheCanvasOutChangesWhatItWeighs() throws {
        let (document, store) = try Self.icon(shapes: 3)
        let withCanvas = try Self.bytes(document, store: store, background: .keep)
        let without = try Self.bytes(document, store: store, background: .drop)
        #expect(without < withCanvas,
                "a file with no canvas rectangle in it is smaller than one with")
    }

    /// More drawing is a bigger file, which is the other thing a person
    /// watching this number expects of it.
    @Test func moreShapesWeighMore() throws {
        let (small, smallStore) = try Self.icon(shapes: 2)
        let (large, largeStore) = try Self.icon(shapes: 20)
        let smallBytes = try Self.bytes(small, store: smallStore)
        let largeBytes = try Self.bytes(large, store: largeStore)
        #expect(smallBytes < largeBytes)
    }

    /// A drawing with a photograph in it cannot be weighed without rendering
    /// the photograph, which is not a trade worth making while somebody is
    /// still choosing a format. The sheet says nothing rather than a guess, and
    /// this is the signal it reads.
    @Test func aDrawingCarryingAPhotographIsNotWeighed() throws {
        var (document, store) = try Self.icon(shapes: 2)
        let photo = try #require(SVGExportBackgroundTests.twoTone(size: CGSize(width: 40,
                                                                              height: 40)))
        document.layers.append(Layer(name: "Photo", content: .image(store.register(photo)),
                                     frame: CGRect(x: 400, y: 400, width: 40, height: 40)))
        #expect(!SVGExporter.embeddedPictures(in: document, store: store).isEmpty)
    }

    /// The sheet asks for this while it is opening, on the main actor, so it
    /// has to be over before anybody could see it happen. A hundred shapes is
    /// far past any real icon.
    @Test func weighingAnIconIsFastEnoughToDoWhileTheSheetOpens() throws {
        let (document, store) = try Self.icon(shapes: 100)
        MachineSpeed.checkInterleaved("SVG preflight, 100 shapes", baselineMS: 4) {
            _ = SVGExporter.data(document, store: store)
        }
    }
}
