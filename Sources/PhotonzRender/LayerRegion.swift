import CoreGraphics
import Foundation
import PhotonzCore

public extension DocumentRenderer {
    /// The picked layer's pixels inside a marquee, and nothing from the layers
    /// around it.
    ///
    /// The layer is drawn ALONE and in place (`render(_:store:only:)`), clipped
    /// to the marquee's path so a wand blob or an ellipse comes out with the
    /// shape it was drawn in, then trimmed to the pixels that are actually
    /// there — a marquee flung round a small drawing hands back the drawing and
    /// not a big transparent box.
    ///
    /// `frame` is where that piece sits on the canvas, in document points with
    /// a top-left origin, so it can be pasted or stacked back over the spot it
    /// came from. nil means nothing of that layer is inside the marquee, which
    /// callers report honestly rather than handing back an invisible rectangle.
    ///
    /// Both ⌘C ("copy takes the layer you picked") and ⌘J ("New Layer via
    /// Copy") take their piece from here, so the same marquee gives the same
    /// pixels whichever way you take them.
    func layerRegion(of id: UUID, in document: PhotonzDocument, store: ImageStore,
                     path: CGPath) -> (image: CGImage, frame: CGRect)? {
        let canvas = CGRect(origin: .zero, size: document.canvasSize)
        let bounds = path.boundingBoxOfPath.integral.intersection(canvas)
        guard !bounds.isNull, bounds.width >= 1, bounds.height >= 1,
              let alone = render(document, store: store, only: id),
              let clipped = RegionOps.extracted(alone, path: path),
              let trimmed = RegionOps.trimmed(clipped) else { return nil }
        // `trimmed.rect` is in the cropped picture's pixels, which run one to
        // one with document points from the marquee's top left corner.
        let frame = CGRect(x: bounds.minX + trimmed.rect.minX, y: bounds.minY + trimmed.rect.minY,
                           width: trimmed.rect.width, height: trimmed.rect.height)
        return (trimmed.image, frame)
    }
}
