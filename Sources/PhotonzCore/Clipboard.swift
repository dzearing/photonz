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
        var placed = size
        if size.width > canvas.width || size.height > canvas.height {
            placed = Geometry.aspectFit(size, in: canvas)
        }
        return CGRect(x: (canvas.width - placed.width) / 2,
                      y: (canvas.height - placed.height) / 2,
                      width: placed.width, height: placed.height)
    }
}
