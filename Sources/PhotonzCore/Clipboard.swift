import CoreGraphics
import Foundation

/// The pasteboard payload for copying layers within (or between) Photonz
/// windows. Image-content layers carry their bitmap as encoded data because
/// `ImageRef` only means something inside the source window's ImageStore.
public struct LayerTransfer: Codable, Sendable {
    public var layer: Layer
    /// Encoded bitmap (PNG) for image-content layers; nil for text,
    /// annotation, and zoom-callout layers, which are pure model data.
    public var imageData: Data?

    public init(layer: Layer, imageData: Data? = nil) {
        self.layer = layer
        self.imageData = imageData
    }

    /// Custom pasteboard type identifying a serialized Photonz layer.
    public static let pasteboardType = "com.photonz.layer"
}

public enum PastePlacement {
    /// Where an image pasted from the system clipboard lands: centered on the
    /// canvas at full size, scaled down (aspect-fit) only when it would
    /// overflow.
    public static func frame(forImageOf size: CGSize, canvas: CGSize) -> CGRect {
        frame(forImageOf: size, in: CGRect(origin: .zero, size: canvas))
    }

    /// The same rule against any box, which is what lets an image dropped on a
    /// screen sit centred in THAT screen rather than in the whole canvas: full
    /// size when it fits, aspect-fitted when it does not.
    public static func frame(forImageOf size: CGSize, in box: CGRect) -> CGRect {
        var placed = size
        if size.width > box.width || size.height > box.height {
            placed = Geometry.aspectFit(size, in: box.size)
        }
        return CGRect(x: box.midX - placed.width / 2,
                      y: box.midY - placed.height / 2,
                      width: placed.width, height: placed.height)
    }
}

extension PhotonzDocument {

    /// A layer ready to leave the document: itself, with its position moved
    /// into CANVAS space.
    ///
    /// Copying a button out of a screen has to remember where that button was
    /// on the canvas, not where it was inside its screen, or pasting it back
    /// would fling it to the top left of the world. Only the layer's own
    /// origin moves: a group's contents stay in the group's space, exactly as
    /// they are stored, so nothing inside it shifts.
    public func detachedLayer(id: UUID) -> Layer? {
        guard var layer = layer(id: id), let origin = parentOrigin(of: id) else { return nil }
        layer.frame = layer.frame.offsetBy(dx: origin.x, dy: origin.y)
        return layer
    }

    /// Where an image arriving from outside the document should land, in
    /// canvas coordinates.
    ///
    /// `point` is where the pointer let go, in canvas coordinates, or nil for
    /// a paste, which has no pointer. Landing on a frame means landing IN it:
    /// the image is sized to fit that screen — a picture that arrives four
    /// times too big and clipped to its middle is not what anybody meant — and
    /// it lands under the pointer, nudged just far enough to sit wholly on the
    /// screen rather than half over its edge. A paste, having no pointer,
    /// lands in the middle of the screen it falls on.
    ///
    /// Everywhere else — bare canvas, or a document with no frames at all —
    /// this is the placement it has always been.
    public func placementForIncomingImage(size: CGSize, at point: CGPoint? = nil) -> CGRect {
        let onCanvas = PastePlacement.frame(forImageOf: size, canvas: canvasSize)
        let probe = point ?? CGPoint(x: onCanvas.midX, y: onCanvas.midY)
        guard let frameID = frameID(under: probe), let box = canvasBounds(of: frameID) else {
            return onCanvas
        }
        let fitted = PastePlacement.frame(forImageOf: size, in: box)
        guard let point else { return fitted }
        let placed = CGRect(x: point.x - fitted.width / 2, y: point.y - fitted.height / 2,
                            width: fitted.width, height: fitted.height)
        return CGRect(x: min(max(placed.minX, box.minX), box.maxX - fitted.width),
                      y: min(max(placed.minY, box.minY), box.maxY - fitted.height),
                      width: fitted.width, height: fitted.height)
    }
}
