import CoreGraphics
import Foundation
import PhotonzCore

/// Turns a document into an SVG file.
///
/// `SVGExport` in PhotonzCore does the writing; it is pure, so the two things
/// it cannot do for itself are supplied here: a PICTURE of any layer that has
/// no vector answer, and the OUTLINE of a text layer's letters. This is the
/// only place the two meet (`docs/design/svg-export.md`).
public enum SVGExporter {

    /// How many pixels a fallback picture gets per document point. Two, so a
    /// picture that had to be embedded still looks right on a retina screen
    /// and survives being scaled up a little — the rest of the file is
    /// resolution-free and this part cannot be.
    public static let pictureScale: CGFloat = 2

    /// The document as SVG, with everything that had to fall back to a picture
    /// named in the result.
    public static func export(_ document: PhotonzDocument, store: ImageStore,
                              renderer: DocumentRenderer = DocumentRenderer(),
                              animation: SVGExport.Animation = .still,
                              background: SVGExport.Background = .keep) -> SVGExport.Result {
        SVGExport.write(document, animation: animation,
                        picture: { layer, origin in
                            picture(of: layer, at: origin, in: document,
                                    store: store, renderer: renderer)
                        },
                        outlineText: { layer, text in
                            guard let outline = TextRasterizer.outlinePath(text, size: layer.frame.size)
                            else { return nil }
                            return SVGExport.pathData(outline)
                        },
                        flatImages: FlatBitmap.colors(in: document, store: store),
                        background: background)
    }

    /// The canvas this drawing sits on, when it is a flat colour Export could
    /// offer to leave out. Nil for a screenshot, a photograph, or anything
    /// whose bottom layer is part of the drawing (`SVGExport.backdrop`).
    public static func backdrop(in document: PhotonzDocument,
                                store: ImageStore) -> SVGExport.Backdrop? {
        SVGExport.backdrop(in: document,
                           flatImages: FlatBitmap.colors(in: document, store: store))
    }

    // MARK: - What would ride along as pixels

    /// Everything in `document` that would go out as an embedded picture, with
    /// the flat ones taken out: a blank canvas's white background is a
    /// rectangle in the file, so nothing should warn about a photograph in it.
    public static func embeddedPictures(in document: PhotonzDocument,
                                        store: ImageStore) -> [SVGExport.Fallback] {
        SVGExport.embeddedPictures(in: document,
                                   flatImages: FlatBitmap.colors(in: document, store: store))
    }

    /// Everything the file could not say in shapes at all, read the same way.
    public static func fallbacks(in document: PhotonzDocument,
                                 store: ImageStore) -> [SVGExport.Fallback] {
        SVGExport.fallbacks(in: document,
                            flatImages: FlatBitmap.colors(in: document, store: store))
    }

    /// The document as SVG bytes, ready to be written to a file.
    public static func data(_ document: PhotonzDocument, store: ImageStore,
                            renderer: DocumentRenderer = DocumentRenderer(),
                            animation: SVGExport.Animation = .still,
                            background: SVGExport.Background = .keep)
        -> (data: Data, fallbacks: [SVGExport.Fallback], unmoved: [SVGExport.Fallback])? {
        let result = export(document, store: store, renderer: renderer, animation: animation,
                            background: background)
        guard let data = result.text.data(using: .utf8) else { return nil }
        return (data, result.fallbacks, result.unmoved)
    }

    // MARK: - A picture of one layer

    /// A picture of `layer` exactly where the canvas shows it.
    ///
    /// An untouched photograph goes out as ITSELF: its own pixels, nothing
    /// re-rendered, which is both the smallest file and the sharpest picture.
    /// Anything else is drawn through the real renderer, so a shadow, a blur or
    /// a rounded corner comes out looking the way it looks on the canvas.
    static func picture(of layer: Layer, at origin: CGPoint, in document: PhotonzDocument,
                        store: ImageStore, renderer: DocumentRenderer) -> SVGExport.Picture? {
        if case .image(let ref) = layer.content, isUntouched(layer),
           let bitmap = store.image(for: ref),
           let png = ImageCodec.encode(bitmap, format: .png) {
            return SVGExport.Picture(png: png,
                                     box: CGRect(origin: origin, size: layer.frame.size))
        }
        let canvas = CGRect(origin: .zero, size: document.canvasSize)
        guard let reach = document.canvasBounds(of: layer.id) else { return nil }
        let box = reach.insetBy(dx: -layer.reachPadding, dy: -layer.reachPadding)
            .integral.intersection(canvas)
        guard !box.isNull, box.width >= 1, box.height >= 1 else { return nil }

        let scale = pictureScale
        let cut = CGRect(x: box.minX * scale, y: box.minY * scale,
                         width: box.width * scale, height: box.height * scale)
        // A lens and a zoom callout draw what is UNDER them, so rendered alone
        // they would come out as empty glass. The composite through their own
        // box is the honest picture, and laying it back over the same spot
        // paints the pixels that were already there.
        let whole: CGImage?
        switch layer.content {
        case .lens, .zoomCallout:
            whole = renderer.render(document, store: store, scale: scale)
        default:
            // Drawn at FULL strength, because the file says the fade itself, on
            // the `<image>` the picture lands in. Baked in here as well it is
            // applied twice, and a half-faded layer came back a quarter of what
            // it is on the canvas (`SVGExport.Writer.picture`).
            var solid = document
            solid.updateLayer(id: layer.id) { $0.style.opacity = 1 }
            whole = renderer.render(solid, store: store, only: layer.id, scale: scale)
        }
        guard let whole, let cropped = whole.cropping(to: cut),
              let png = ImageCodec.encode(cropped, format: .png) else { return nil }
        return SVGExport.Picture(png: png, box: box)
    }

    /// Whether a picture layer is the picture itself: nothing cropped, turned,
    /// rounded off or added to it.
    private static func isUntouched(_ layer: Layer) -> Bool {
        layer.crop == nil && layer.transform.isIdentity
            && !layer.style.cornerRadii.isRound
            && !layer.style.effects.contains { $0.isOn }
    }
}
