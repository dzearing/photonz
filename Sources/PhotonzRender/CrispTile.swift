import CoreGraphics
import Foundation

/// A patch of the composite drawn with more pixels than the document has, so a
/// zoomed-in canvas can show sharp words where it would otherwise be stretching
/// a document-sized picture over four or sixteen screen pixels each.
public struct CrispTile: Sendable {
    /// The pixels: `region` drawn at `scale` pixels per document point.
    public let image: CGImage
    /// The part of the document, in document points, that `image` covers.
    /// It settles on whole output pixels, so it can differ from what was asked
    /// for by a fraction of a point.
    public let region: CGRect
    /// Output pixels per document point.
    public let scale: CGFloat

    public init(image: CGImage, region: CGRect, scale: CGFloat) {
        self.image = image
        self.region = region
        self.scale = scale
    }
}
