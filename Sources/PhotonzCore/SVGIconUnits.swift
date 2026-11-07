import CoreGraphics
import Foundation

/// A 512 icon picture writes its SVG in the 24 units it was drawn on.
///
/// The canvas stays 512 points, so a PNG is still 512 and nothing about the
/// document changes: this is a restatement for the file alone, thrown away when
/// it is written. Everything drawn comes down by 24 / 512 through
/// `Layer.rescaled(by:)`, which is what keeps a shape on whole units whole.
///
/// Two things are not made in the file's numbers. A picture would come out 48
/// pixels across, and letters change shape with their point size, so both are
/// still asked for at the size they are drawn and only their place comes down.
///
/// A measurement stays in points, and the picture with it: its label is a fixed
/// size on purpose (`LayerContent.rescaled(by:)`), so in a 24 unit file it would
/// stand over the whole icon. A redlined icon is not a glyph being handed over.
struct SVGIconUnits {

    /// The document the file is written from.
    let document: PhotonzDocument
    /// What a length in the canvas is multiplied by to reach the file.
    let scale: CGFloat

    /// A picture asked of the document as drawn, and landed in the file's units.
    func picture(from drawn: PhotonzDocument,
                 _ make: SVGExport.PictureMaker?) -> SVGExport.PictureMaker? {
        guard scale != 1, let make else { return make }
        let scale = scale
        return { layer, origin in
            guard let picture = make(drawn.layer(id: layer.id) ?? layer,
                                     origin.magnified(by: 1 / scale)) else { return nil }
            return SVGExport.Picture(png: picture.png, box: picture.box.magnified(by: scale))
        }
    }

    /// Words outlined as the document draws them, brought down to the file.
    func outline(from drawn: PhotonzDocument,
                 _ make: SVGExport.TextOutliner?) -> SVGExport.TextOutliner? {
        guard scale != 1, let make else { return make }
        let scale = scale
        return { layer, text in
            guard let original = drawn.layer(id: layer.id), case .text(let words) = original.content
            else { return make(layer, text) }
            return make(original, words).map { Self.pathData($0, scaledBy: scale) }
        }
    }

    /// Path data with every number multiplied. `SVGExport.pathData` says places
    /// and nothing else, so each number in it is a length.
    static func pathData(_ data: String, scaledBy scale: CGFloat) -> String {
        data.replacing(/-?(?:\d+\.?\d*|\.\d+)/) { match in
            guard let value = Double(match.output) else { return String(match.output) }
            return SVGExport.num(CGFloat(value) * scale)
        }
    }
}

extension PhotonzDocument {

    /// The size an SVG of this document says it is, which the Export sheet
    /// quotes: 24 by 24 on a picture that writes units.
    public var svgSize: CGSize { inIconUnits.document.canvasSize }

    /// This document as its SVG is written from: in units on a picture that
    /// has them, and as it stands on any other.
    var inIconUnits: SVGIconUnits {
        guard let unit = pictureIconUnit, !allLayers.contains(where: { $0.measure != nil }) else {
            return SVGIconUnits(document: self, scale: 1)
        }
        let scale = 1 / unit
        var document = self
        document.canvasSize = canvasSize.applying(CGAffineTransform(scaleX: scale, y: scale))
        document.layers = layers.map { $0.rescaled(by: scale) }
        document.camera = camera?.magnified(by: Double(scale))
        return SVGIconUnits(document: document, scale: scale)
    }
}
