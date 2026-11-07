import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A small square SVG on a grid of its own (`a-small-svg-icon-opens-big-enough-to-work-on`):
/// it opens as an Icon picture the size a 24 unit one is, and keeps its own units.
@Suite("A small SVG icon opens big enough to work on")
struct SmallSVGIconTests {

    static func read(_ text: String) throws -> SVGOpening {
        try SVGOpening.read(Data(text.utf8), named: "drawing").get()
    }

    static func icon(side: Int) -> String {
        ##"<svg xmlns="http://www.w3.org/2000/svg" width="\##(side)" height="\##(side)" viewBox="0 0 \##(side) \##(side)"><path d="M2 2h4v4z" stroke="#222" stroke-width="1.5"/></svg>"##
    }

    static func document(_ opening: SVGOpening) -> (PhotonzDocument, ImageRef) {
        let ground = ImageRef(id: UUID(), pixelSize: opening.canvasSize)
        return (opening.document(on: ground), ground)
    }

    @Test("Each small square size opens as an Icon picture, its own units across", arguments: [14, 16, 20, 22, 32, 48, 64])
    func opensOnItsGrid(side: Int) throws {
        let opening = try Self.read(Self.icon(side: side))
        #expect(opening.isIcon)
        #expect(opening.canvasSize == CGSize(width: 512, height: 512))
        let (document, _) = Self.document(opening)
        #expect(document.opensAsIcon)
        #expect(document.pictureIconUnit == 512 / CGFloat(side))
        #expect(abs(document.svgSize.width - CGFloat(side)) < 1e-9)
    }

    @Test("A view box alone says the grid, and so does a width over a bigger view box")
    func gridFromEither() throws {
        #expect(try Self.read(##"<svg viewBox="0 0 16 16"><path d="M2 2h4v4z"/></svg>"##).isIcon)
        let (document, _) = Self.document(try Self.read(##"<svg width="20" height="20" viewBox="0 0 960 960"><path d="M80 80h800v800z"/></svg>"##))
        #expect(document.pictureIconUnit == 512.0 / 20)
    }

    @Test("A 24 unit icon writes nothing new into its document")
    func twentyFourIsUnchanged() throws {
        let (document, _) = Self.document(try Self.read(Self.icon(side: 24)))
        #expect(document.iconPictureGrid == nil)
        #expect(document.pictureIconUnit == 512.0 / 24)
    }

    @Test("What is not a small square stays an ordinary picture at its own size",
          arguments: [(512, 512), (100, 100), (300, 120), (16, 12), (4, 4)])
    func staysAPicture(width: Int, height: Int) throws {
        let opening = try Self.read(##"<svg width="\##(width)" height="\##(height)"><path d="M1 1h2v2z"/></svg>"##)
        #expect(!opening.isIcon)
        #expect(opening.canvasSize == CGSize(width: width, height: height))
        #expect(Self.document(opening).0.pictureIconUnit == nil)
    }

    @Test("It writes its own numbers again, on its own view box", arguments: [14, 16, 48])
    func writesItsUnits(side: Int) throws {
        let (document, ground) = Self.document(try Self.read(Self.icon(side: side)))
        let written = SVGExport.write(document, flatImages: [ground.id: RGBA(r: 1, g: 1, b: 1, a: 1)], background: .drop).text
        #expect(written.contains(#"viewBox="0 0 \#(side) \#(side)""#))
        #expect(written.contains(#"stroke-width="1.5""#))
    }

    @Test("Saved and opened again it is still on its own grid")
    func survivesSaving() throws {
        let (document, _) = Self.document(try Self.read(Self.icon(side: 16)))
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: JSONEncoder().encode(document))
        #expect(back.pictureIconUnit == 32)
    }

    @Test("Fit gives the view it opened at")
    func fitIsTheOpeningView() throws {
        let canvas = try Self.read(Self.icon(side: 16)).canvasSize
        let view = CGSize(width: 836, height: 768)
        #expect(Viewport.opening(documentSize: canvas, in: view, plannedZoom: 1, obscuredBottom: 60)
                == Viewport.fit(documentSize: canvas, in: view, obscuredBottom: 60))
    }
}
