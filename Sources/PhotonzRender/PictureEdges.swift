import CoreGraphics
import Foundation
import PhotonzCore

/// The see-through edge of each picture, traced once and kept.
///
/// A Border that follows the shape of a cut-out runs round the edge its
/// transparency makes (`PictureEdge` in PhotonzCore does the tracing). Reading
/// a picture's alpha and tracing it costs a few milliseconds, which is nothing
/// once and far too much on every frame of a Width drag, so the answer is kept
/// for as long as the same pixels sit under the same picture.
public enum PictureEdges {

    /// The longest side a picture is traced at. A ring follows the edge to
    /// within a pixel of this, which on a cut-out bigger than it is a fraction
    /// of a point on the canvas, and it keeps a 4000 pixel photograph from
    /// being walked a pixel at a time.
    static let traceSide = 768

    /// The edge of the picture under `ref`, in fractions of the picture from
    /// its top-left corner, or nil where it is solid to its edges (or has no
    /// pixels at all).
    public static func edge(for ref: ImageRef, store: ImageStore) -> CGPath? {
        guard let image = store.image(for: ref) else { return nil }
        return edge(of: image, id: ref.id)
    }

    /// Whether the picture under `ref` has a see-through edge for a ring to
    /// follow: what decides whether its Border row asks Shape or Box.
    public static func hasEdge(_ ref: ImageRef, store: ImageStore) -> Bool {
        edge(for: ref, store: store) != nil
    }

    private struct Kept {
        let picture: ObjectIdentifier
        let edge: CGPath?
    }

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var kept: [UUID: Kept] = [:]
    }

    private static let cache = Cache()

    static func edge(of image: CGImage, id: UUID) -> CGPath? {
        let picture = ObjectIdentifier(image)
        cache.lock.lock()
        if let hit = cache.kept[id], hit.picture == picture {
            cache.lock.unlock()
            return hit.edge
        }
        cache.lock.unlock()
        let edge = trace(image)
        cache.lock.lock()
        // A picture held under a ref keeps the CGImage alive, so its identity
        // cannot be handed to another picture while this entry is used.
        if cache.kept.count > 256 { cache.kept.removeAll() }
        cache.kept[id] = Kept(picture: picture, edge: edge)
        cache.lock.unlock()
        return edge
    }

    /// Reads the picture's alpha, no bigger than `traceSide`, and traces it.
    static func trace(_ image: CGImage) -> CGPath? {
        // A picture with no alpha channel at all is solid to its edges, and
        // saying so costs nothing.
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return nil
        default: break
        }
        let longest = max(image.width, image.height)
        guard longest > 0 else { return nil }
        let shrink = min(1, CGFloat(traceSide) / CGFloat(longest))
        let width = max(1, Int((CGFloat(image.width) * shrink).rounded()))
        let height = max(1, Int((CGFloat(image.height) * shrink).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // The bitmap's first row is the picture's top row: Core Graphics
        // draws y-up into memory that is read top row first, so the image
        // lands the right way round.
        let alpha = (0..<(width * height)).map { pixels[$0 * 4 + 3] }
        return PictureEdge.outline(alpha: alpha, width: width, height: height)
    }
}
