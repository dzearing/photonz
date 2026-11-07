import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// File ▸ Open on an SVG (`SVGOpening`): its own size, its own shapes, and a
/// plain word about anything that cannot come in that way.
@Suite("Opening an SVG gives you its drawing")
struct SVGOpeningTests {

    static let unit: CGFloat = 512.0 / 24

    static func read(_ text: String, named name: String = "drawing") throws -> SVGOpening {
        try SVGOpening.read(Data(text.utf8), named: name).get()
    }

    static func near(_ a: CGFloat, _ b: CGFloat, _ slack: CGFloat = 0.01) -> Bool { abs(a - b) <= slack }

    static func refusal(_ data: Data) -> String? {
        if case .failure(let error) = SVGOpening.read(data, named: "drawing") { return error.message }
        return nil
    }

    /// The canvas as a blank picture is, which is what the app puts under it.
    static func ground(_ size: CGSize) -> ImageRef { ImageRef(id: UUID(), pixelSize: size) }

    static let arrow = """
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" \
        stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">\
        <path d="M12 20V5"/><path d="M6.5 10.5 12 5l5.5 5.5"/></svg>
        """

    // MARK: Its size

    @Test("An icon on the 24 grid opens as an Icon picture, 24 units across at 512 points")
    func iconOnTheGrid() throws {
        let opening = try Self.read(Self.arrow)
        #expect(opening.isIcon)
        #expect(opening.canvasSize == CGSize(width: 512, height: 512))
        let document = opening.document(on: Self.ground(opening.canvasSize))
        #expect(document.madeAsIcon)
        #expect(document.isIconCanvas)
        #expect(document.svgSize == CGSize(width: 24, height: 24))
    }

    @Test("A view box of 24 with no width of its own is on the 24 grid, and so is 24 wide over a bigger view box")
    func gridReadBothWays() throws {
        #expect(try Self.read(##"<svg viewBox="0 0 24 24"><path d="M2 2h20v20z"/></svg>"##).isIcon)
        #expect(try Self.read(##"<svg width="24" height="24" viewBox="0 -960 960 960"><path d="M80 -80h800v-800z"/></svg>"##).isIcon)
    }

    @Test("The stated width and height are the canvas, and the view box is drawn into them")
    func statedSize() throws {
        let opening = try Self.read(##"<svg width="300" height="120" viewBox="0 0 600 240"><rect x="60" y="20" width="200" height="100" fill="#FF0000"/></svg>"##)
        #expect(!opening.isIcon)
        #expect(opening.canvasSize == CGSize(width: 300, height: 120))
        let box = try #require(opening.layers.first).frame
        #expect(Self.near(box.minX, 30) && Self.near(box.minY, 10))
        #expect(Self.near(box.width, 100) && Self.near(box.height, 50))
    }

    @Test("Inches, millimetres and points come to their size in points; a percentage says nothing")
    func units() throws {
        let page = try Self.read(##"<svg width="210mm" height="297mm" viewBox="0 0 210 297"><path d="M0 0h10v10z"/></svg>"##)
        #expect(page.canvasSize == CGSize(width: 794, height: 1123))
        let inches = try Self.read(##"<svg width="1in" height="2in"><path d="M0 0h10v10z"/></svg>"##)
        #expect(inches.canvasSize == CGSize(width: 96, height: 192))
        let full = try Self.read(##"<svg width="100%" height="100%" viewBox="0 0 640 480"><path d="M0 0h10v10z"/></svg>"##)
        #expect(full.canvasSize == CGSize(width: 640, height: 480))
    }

    @Test("A width and height with no view box leaves every number where the file put it")
    func noViewBox() throws {
        let opening = try Self.read(##"<svg width="200" height="100"><rect x="20" y="30" width="40" height="10" fill="#000"/></svg>"##)
        #expect(opening.canvasSize == CGSize(width: 200, height: 100))
        #expect(try #require(opening.layers.first).frame == CGRect(x: 20, y: 30, width: 40, height: 10))
    }

    @Test("A file that gives no size at all is as big as what it draws")
    func noSizeAtAll() throws {
        let opening = try Self.read(##"<svg><rect x="10" y="20" width="60" height="30" fill="#000"/></svg>"##)
        #expect(opening.canvasSize == CGSize(width: 60, height: 30))
        #expect(try #require(opening.layers.first).frame.origin == .zero)
    }

    @Test("A drawing bigger than any canvas comes down to the biggest one, keeping its shape")
    func tooBig() throws {
        let opening = try Self.read(##"<svg viewBox="0 0 100000 50000"><rect width="100000" height="50000" fill="#000"/></svg>"##)
        #expect(opening.canvasSize == CGSize(width: BlankCanvas.maximumSide, height: BlankCanvas.maximumSide / 2))
        #expect(Self.near(try #require(opening.layers.first).frame.width, BlankCanvas.maximumSide))
    }

    // MARK: Its shapes

    @Test("Every part stays where the file drew it, off the grid as much as on it")
    func nothingSnaps() throws {
        let opening = try Self.read(Self.arrow)
        #expect(opening.layers.count == 2)
        guard case .path(let path) = opening.layers[1].content else { Issue.record("not a path"); return }
        let origin = opening.layers[1].frame.origin
        let first = try #require(path.anchors.first).point
        #expect(Self.near(first.x + origin.x, 6.5 * Self.unit))
        #expect(Self.near(first.y + origin.y, 10.5 * Self.unit))
        #expect(Self.near(path.strokeWidth, 1.75 * Self.unit))
        #expect(path.lineEnd == .round)
    }

    @Test("Parts are named after the file, and a part with an id after its id")
    func names() throws {
        let opening = try Self.read(##"<svg viewBox="0 0 24 24"><path d="M2 2h20v20z"/><circle id="left-eye" cx="4" cy="4" r="2"/></svg>"##,
                                    named: "cloud-upload")
        #expect(opening.layers.map(\.name) == ["cloud-upload 1", "Left eye"])
    }

    @Test("A named group stays a group, in the place the file put it")
    func groupsStay() throws {
        let opening = try Self.read("""
            <svg viewBox="0 0 100 100">
              <rect width="100" height="100" fill="#FFFFFF"/>
              <g id="face"><circle cx="30" cy="30" r="10"/><circle cx="70" cy="30" r="10"/></g>
            </svg>
            """)
        #expect(opening.layers.count == 2)
        let group = opening.layers[1]
        #expect(group.name == "Face")
        #expect(group.children.count == 2)
        #expect(Self.near(group.frame.minX, 20) && Self.near(group.frame.minY, 20))
    }

    @Test("The document is the canvas a blank picture is, with the drawing's layers on it, free to pick")
    func theDocument() throws {
        let opening = try Self.read(Self.arrow)
        let ground = Self.ground(opening.canvasSize)
        let document = opening.document(on: ground)
        #expect(document.canvasSize == opening.canvasSize)
        #expect(document.layers.count == 3)
        #expect(document.layers[0].isLocked)
        #expect(document.layers[0].imageRef == ground)
        #expect(document.layers.dropFirst().allSatisfy { !$0.isLocked })
    }

    @Test("An icon opened and written again says the same numbers, with no canvas in the file")
    func roundTrip() throws {
        let opening = try Self.read(Self.arrow)
        let ground = Self.ground(opening.canvasSize)
        let document = opening.document(on: ground)
        let written = SVGExport.write(document, flatImages: [ground.id: RGBA(r: 1, g: 1, b: 1, a: 1)], background: .drop).text
        #expect(written.contains(#"viewBox="0 0 24 24""#))
        #expect(written.contains(##"translate(12 5)" d="M0 15 L0 0""##))
        #expect(written.contains(##"translate(6.5 5)" d="M0 5.5 L5.5 0 L11 5.5""##))
        #expect(written.contains(##"stroke-width="1.75""##))
        #expect(!written.contains("<rect"))
    }

    // MARK: What shapes cannot carry

    @Test("A drawing made only of what the app draws keeps everything", arguments: [
        ##"<svg viewBox="0 0 10 10"><title>Hi</title><desc>x</desc><defs/><path d="M0 0h9v9z"/></svg>"##,
        ##"<svg viewBox="0 0 10 10"><defs><linearGradient id="a"><stop stop-color="#000"/><stop offset="1" stop-color="#FFF"/></linearGradient></defs><path fill="url(#a)" d="M0 0h9v9z"/></svg>"##,
        ##"<svg viewBox="0 0 10 10"><style></style><path d="M0 0h9v9z"/></svg>"##,
        ##"<svg viewBox="0 0 10 10"><defs><clipPath id="unused"><rect width="1" height="1"/></clipPath></defs><path stroke-dasharray="none" d="M0 0h9v9z"/></svg>"##,
    ])
    func keepsEverything(text: String) throws {
        #expect(try Self.read(text).leftOut.isEmpty)
    }

    @Test("Anything the shapes would lose is named", arguments: [
        (##"<svg viewBox="0 0 10 10"><path d="M0 0h9v9z"/><text>Hi</text></svg>"##, "text"),
        (##"<svg viewBox="0 0 10 10"><path d="M0 0h9v9z"/><image href="a.png"/></svg>"##, "image"),
        (##"<svg viewBox="0 0 10 10"><defs><path id="p" d="M0 0h9v9z"/></defs><path d="M0 0h1v1z"/><use href="#p"/></svg>"##, "use"),
        (##"<svg viewBox="0 0 10 10"><style>path:hover{fill:red}</style><path d="M0 0h9v9z"/></svg>"##, "style"),
        (##"<svg viewBox="0 0 10 10"><style>@keyframes a{from{opacity:0}to{opacity:1}}</style><path d="M0 0h9v9z"/></svg>"##, "style"),
        (##"<svg viewBox="0 0 10 10"><style>#a .b{fill:red}</style><path d="M0 0h9v9z"/></svg>"##, "style"),
        (##"<svg viewBox="0 0 100 100"><defs><clipPath id="c"><rect width="50" height="50"/></clipPath></defs><path clip-path="url(#c)" d="M0 0h90v90z"/></svg>"##, "clip-path"),
        (##"<svg viewBox="0 0 100 100"><defs><clipPath id="c"><circle cx="50" cy="50" r="90"/></clipPath></defs><path clip-path="url(#c)" d="M0 0h90v90z"/></svg>"##, "clip-path"),
        (##"<svg viewBox="0 0 100 100"><defs><clipPath id="c"><rect width="100" height="100" rx="20"/></clipPath></defs><path clip-path="url(#c)" d="M0 0h90v90z"/></svg>"##, "clip-path"),
        (##"<svg viewBox="0 0 10 10"><path clip-path="url(#c)" d="M0 0h9v9z"/></svg>"##, "clip-path"),
        (##"<svg viewBox="0 0 10 10"><g mask="url(#m)"><path d="M0 0h9v9z"/></g></svg>"##, "mask"),
        (##"<svg viewBox="0 0 10 10"><path style="filter:url(#f)" d="M0 0h9v9z"/></svg>"##, "filter"),
        (##"<svg viewBox="0 0 10 10"><path fill="url(#nothing)" d="M0 0h9v9z"/></svg>"##, "paint"),
        (##"<svg viewBox="0 0 10 10"><defs><linearGradient id="a"><stop stop-color="#000"/><stop offset="1" stop-color="#FFF"/></linearGradient></defs><path fill="none" stroke="url(#a)" d="M0 0h9"/></svg>"##, "paint"),
        (##"<svg viewBox="0 0 10 10"><path stroke="#000" stroke-dasharray="2 2" d="M0 0h9"/></svg>"##, "stroke-dasharray"),
        (##"<svg viewBox="0 0 10 10"><path d="M0 0h9v9z"/><svg x="1"><path d="M0 0h1v1z"/></svg></svg>"##, "svg"),
    ])
    func namesWhatItLoses(text: String, word: String) throws {
        #expect(try Self.read(text).leftOut.contains(word))
    }

    @Test("A clip as big as the canvas cuts nothing, which is what a design tool wraps every export in", arguments: [
        ##"<svg viewBox="0 0 24 24"><g clip-path="url(#c)"><path d="M2 2h20v20z"/></g><defs><clipPath id="c"><rect width="24" height="24" fill="white"/></clipPath></defs></svg>"##,
        ##"<svg viewBox="0 0 24 24"><defs><clipPath id="c"><rect x="-2" y="-2" width="40" height="40"/></clipPath></defs><path clip-path="url(#c)" d="M2 2h20v20z"/></svg>"##,
        ##"<svg viewBox="0 0 24 24"><defs><clipPath id="c"><rect width="12" height="12"/></clipPath></defs><g transform="scale(2)"><path clip-path="url(#c)" d="M1 1h10v10z"/></g></svg>"##,
    ])
    func wholeCanvasClip(text: String) throws {
        let opening = try Self.read(text)
        #expect(opening.leftOut.isEmpty)
        #expect(opening.layers.count == 1)
    }

    @Test("An Illustrator file's classes paint its shapes, and the file's own words beat them")
    func classes() throws {
        let opening = try Self.read("""
            <svg viewBox="0 0 100 100">
              <defs><style type="text/css"><![CDATA[
                /* made by a design tool */
                .st0{fill:none;stroke:#ED2024;stroke-width:2;}
                .st1, .st2 { fill: #00FF00 }
                .big{stroke-width:9}
              ]]></style></defs>
              <path class="st0" d="M0 0L50 50"/>
              <rect class="st1" x="1" y="1" width="9" height="9"/>
              <rect class="st2" style="fill:#0000FF" x="11" y="1" width="9" height="9"/>
              <path class="st0 big" stroke="#000000" d="M60 0L90 50"/>
            </svg>
            """)
        #expect(opening.leftOut.isEmpty)
        #expect(opening.layers.count == 4)
        let artwork = try SVGArtwork.parse("""
            <svg viewBox="0 0 100 100"><style>.st0{fill:none;stroke:#ED2024;stroke-width:2}.st1,.st2{fill:#00FF00}.big{stroke-width:9}</style>
            <path class="st0" d="M0 0L50 50"/><rect class="st1" width="9" height="9"/>
            <rect class="st2" style="fill:#0000FF" width="9" height="9"/><path class="st0 big" stroke="#000000" d="M60 0L90 50"/></svg>
            """).get()
        #expect(artwork.parts[0].fill == nil)
        #expect(artwork.parts[0].stroke == "#ED2024")
        #expect(artwork.parts[0].strokeWidth == 2)
        #expect(artwork.parts[1].fill == "#00FF00")
        #expect(artwork.parts[2].fill == "#0000FF")
        #expect(artwork.parts[3].strokeWidth == 9)
        #expect(artwork.parts[3].stroke == "#ED2024")
    }

    @Test("A style sheet laid out over many lines reads the same, which is how Illustrator writes one")
    func classesOverManyLines() throws {
        let artwork = try SVGArtwork.parse("""
            <svg viewBox="0 0 100 100">
              <defs>
                <style>
                  .st0 {
                    fill: #ff8236;
                  }

                  .st1 {
                    fill: #fff;
                    stroke-width: 3;
                  }
                </style>
              </defs>
              <rect class="st0" width="9" height="9"/><rect class="st1" stroke="#000" width="9" height="9"/>
            </svg>
            """).get()
        #expect(artwork.leftOut.isEmpty)
        #expect(artwork.parts.map(\.fill) == ["#FF8236", "#FFFFFF"])
        #expect(artwork.parts[1].strokeWidth == 3)
    }

    @Test("A box's line rides its edge as the file drew it, so the box keeps the file's own numbers")
    func boxLinesRideTheEdge() throws {
        let opening = try Self.read(##"<svg viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2"><rect x="2" y="4" width="20" height="16" rx="2"/><circle cx="12" cy="12" r="3"/></svg>"##)
        for layer in opening.layers {
            #expect(layer.outlinePosition == .center)
        }
        #expect(Self.near(opening.layers[0].frame.minX, 2 * Self.unit))
        #expect(Self.near(opening.layers[0].frame.width, 20 * Self.unit))
        let ground = Self.ground(opening.canvasSize)
        let written = SVGExport.write(opening.document(on: ground), flatImages: [ground.id: RGBA(r: 1, g: 1, b: 1, a: 1)],
                                      background: .drop).text
        #expect(written.contains(##"x="2""##) && written.contains(##"width="20""##) && written.contains(##"height="16""##))
    }

    @Test("A colour written rgb() is that colour, on a shape or handed down to one")
    func rgbColours() throws {
        let artwork = try SVGArtwork.parse(##"<svg fill="rgb(169, 94, 210)" viewBox="0 0 20 20"><path d="M0 0h9v9z"/><path fill="rgb(100%,0%,0%)" d="M0 0h9v9z"/></svg>"##).get()
        #expect(artwork.parts.map(\.fill) == ["#A95ED2", "#FF0000"])
    }

    @Test("What is hidden loses nothing")
    func hiddenLosesNothing() throws {
        let opening = try Self.read(##"<svg viewBox="0 0 10 10"><path d="M0 0h9v9z"/><g display="none"><text>Hi</text></g></svg>"##)
        #expect(opening.leftOut.isEmpty)
    }

    // MARK: The plain word

    @Test("A compressed SVG is named for what it is")
    func compressed() {
        let message = Self.refusal(Data([0x1F, 0x8B, 0x08, 0x00, 0x00]))
        #expect(message == SVGOpening.compressedMessage)
    }

    @Test("Bytes that are not a drawing say so in one short sentence", arguments: [
        "hello there",
        ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M1 1"##,
    ])
    func broken(text: String) throws {
        let message = try #require(Self.refusal(Data(text.utf8)))
        #expect(!message.contains("—"))
        #expect(!message.contains("<"))
        #expect(message.count <= 80)
    }

    @Test("An SVG with nothing in it can be told from a broken one")
    func nothingDrawn() {
        #expect(Self.refusal(Data(##"<svg viewBox="0 0 10 10"></svg>"##.utf8)) == SVGOpening.nothingDrawnMessage)
    }

    @Test("A file that is all text has no shapes and still comes through, for a picture of it")
    func onlyText() throws {
        let opening = try Self.read(##"<svg width="100" height="40"><text>Hi</text></svg>"##)
        #expect(opening.layers.isEmpty)
        #expect(opening.leftOut == ["text"])
        #expect(opening.canvasSize == CGSize(width: 100, height: 40))
        #expect(opening.knowsItsSize)
        #expect(try !Self.read("<svg><text>Hi</text></svg>").knowsItsSize)
    }

    @Test("Bytes that are not UTF-8 are read as well as they can be, never crashed on")
    func oddBytes() throws {
        var data = Data(##"<?xml version="1.0" encoding="ISO-8859-1"?><svg viewBox="0 0 10 10"><path id="caf"##.utf8)
        data.append(0xE9)
        data.append(contentsOf: Array(##"" d="M0 0h9v9z"/></svg>"##.utf8))
        #expect(try SVGOpening.read(data, named: "x").get().layers.count == 1)
    }

    // MARK: The canvas alone

    @Test("The size a drawing asks for is known even for a file that can only come in as a picture")
    func sizeForAPicture() throws {
        let opening = try Self.read(##"<svg viewBox="0 0 24 24"><path d="M2 2h20v20z"/><text>Hi</text></svg>"##)
        #expect(opening.isIcon)
        #expect(opening.canvasSize == CGSize(width: 512, height: 512))
        let drawn = opening.pictureDocument(of: ImageRef(id: UUID(), pixelSize: CGSize(width: 24, height: 24)),
                                            named: "drawing", on: Self.ground(opening.canvasSize))
        #expect(drawn.layers.count == 2)
        #expect(drawn.layers[1].frame == CGRect(x: 0, y: 0, width: 512, height: 512))
        #expect(!drawn.layers[1].isLocked)
        #expect(drawn.layers[1].name == "drawing")
    }
}
