import CoreGraphics
import Foundation

/// An SVG file opened as a document, the way a picture opens
/// (`opening-an-svg-file-gives-you-its-drawing-to-edi`).
///
/// The drawing arrives as the shapes it is made of, one layer each, so every
/// path can be picked and reshaped. Where shapes would lose part of it (text,
/// a clip, a style sheet: `leftOut`), the app shows it as one sharp picture
/// instead (`VectorArt`), because a drawing that opens looking wrong is worse
/// than one that opens whole.
///
/// **An icon on the 24 grid opens as an Icon picture**: 512 points across and
/// 24 units across, what File, New, Image, Icon makes
/// (`PhotonzDocument.pictureIconUnit`). It gets the keylines, the previews and
/// the units, and writes its file in 24 units again. Taken at its word it would
/// be a canvas 24 points wide, a speck in the window, since a fit never
/// enlarges (`Viewport.fit`).
///
/// **Nothing lands on the grid.** Fitting a new drawing to an icon's units is
/// for drawings made for it (`IconGridLanding`); here the numbers are somebody
/// else's work, and they stay what the file said.
public struct SVGOpening: Sendable {

    /// The sizes this reads, every one of which is a picture in a file.
    public static let fileExtensions: Set<String> = ["svg", "svgz"]

    public static func isSVGFile(_ url: URL) -> Bool {
        fileExtensions.contains(url.pathExtension.lowercased())
    }

    public static let compressedMessage = "This is a compressed SVG. Save it as a plain .svg and open that."
    public static let unreadableMessage = "This file is damaged, or it is not really an SVG."
    public static let nothingDrawnMessage = "This SVG has nothing drawn in it."
    public static let missingMessage = "The file could not be read."

    /// The canvas, in points.
    public let canvasSize: CGSize
    /// Whether it opens as an Icon picture.
    public let isIcon: Bool
    /// The drawing as layers on that canvas, bottom first.
    public let layers: [Layer]
    /// What those layers do not carry, one word each; empty when they are the
    /// whole drawing.
    public let leftOut: Set<String>

    /// Whether the file said how big it is. One that holds nothing but text
    /// and gives no size has to be asked of whatever can draw it.
    public let knowsItsSize: Bool

    /// A drawing only macOS could read, at the size it said it was.
    public init(pictureOfSize size: CGSize) {
        canvasSize = Self.canvas(for: size)
        isIcon = false
        layers = []
        leftOut = []
        knowsItsSize = true
    }

    private init(_ artwork: SVGArtwork, named name: String) {
        let grid = CGSize(width: IconKeylines.artboardSide, height: IconKeylines.artboardSide)
        let drawn = artwork.bounds
        let asked = artwork.ownSize ?? artwork.viewBox?.size ?? drawn.size
        isIcon = artwork.ownSize == grid || artwork.viewBox?.size == grid
        canvasSize = isIcon ? CGSize(width: IconUnits.pictureSide, height: IconUnits.pictureSide)
                            : Self.canvas(for: asked)
        let box = CGRect(origin: .zero, size: canvasSize)
        layers = artwork.nested(artwork.layers(named: name, fitting: box, within: artwork.viewBox ?? drawn)
                                    .map(Self.lineOnItsEdge),
                                named: name)
        leftOut = artwork.leftOut
        knowsItsSize = artwork.ownSize != nil || artwork.viewBox != nil || !drawn.isNull
    }

    /// An SVG's line rides the edge of its shape, half each side. A box or an
    /// oval here starts with its line inside the edge, which on a file's
    /// numbers comes out half a line too small all round: the outline of a
    /// mail icon stops short of the flap drawn to meet it.
    private static func lineOnItsEdge(_ layer: Layer) -> Layer {
        var layer = layer
        // The line a box arrives with is its Border (`OutlineRetirement`).
        layer.style.borderPosition = .center
        return layer
    }

    /// What is in these bytes, or a sentence saying why nothing can be made of
    /// them here. `name` is what parts with no id of their own are called.
    public static func read(_ data: Data, named name: String) -> Result<SVGOpening, SVGArtworkError> {
        if data.starts(with: [0x1F, 0x8B]) { return .failure(SVGArtworkError(compressedMessage)) }
        switch SVGArtwork.read(text(of: data), keepingGroups: true) {
        case .success(let artwork):
            guard !artwork.parts.isEmpty || !artwork.leftOut.isEmpty else {
                return .failure(SVGArtworkError(nothingDrawnMessage))
            }
            return .success(SVGOpening(artwork, named: name))
        case .failure:
            return .failure(SVGArtworkError(unreadableMessage))
        }
    }

    /// The file's words: most are UTF-8, a few say another encoding, and those
    /// lose nothing that matters here by being read as Latin 1.
    private static func text(of data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let wide = String(data: data, encoding: .utf16) { return wide }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// A size as a canvas can be: whole points, at least one, and no bigger
    /// than the biggest there is, keeping its shape on the way down.
    private static func canvas(for size: CGSize) -> CGSize {
        let longest = max(size.width, size.height)
        let scale = longest > BlankCanvas.maximumSide ? BlankCanvas.maximumSide / longest : 1
        func side(_ length: CGFloat) -> CGFloat {
            min(max((length * scale).rounded(.up), BlankCanvas.minimumSide), BlankCanvas.maximumSide)
        }
        return CGSize(width: side(size.width), height: side(size.height))
    }

    /// The document of the drawing's shapes, on `ground`: the canvas a blank
    /// picture has, which Export leaves out of a file unless it is asked for.
    public func document(on ground: ImageRef) -> PhotonzDocument {
        var document = PhotonzDocument.withBaseImage(ground)
        document.layers += layers
        document.madeAsIcon = isIcon
        return document
    }

    /// The document of the drawing as one picture filling the canvas.
    public func pictureDocument(of picture: ImageRef, named name: String, on ground: ImageRef) -> PhotonzDocument {
        var document = PhotonzDocument.withBaseImage(ground)
        document.layers.append(Layer(name: name, content: .image(picture), frame: CGRect(origin: .zero, size: canvasSize)))
        document.madeAsIcon = isIcon
        return document
    }
}
