import CoreGraphics
import Foundation
import PhotonzCore

/// Owns the actual bitmaps referenced by `ImageRef`s in documents.
/// Documents stay value-typed; pixels live here exactly once.
public final class ImageStore: @unchecked Sendable {
    private var images: [UUID: CGImage] = [:]
    private let lock = NSLock()

    public init() {}

    @discardableResult
    public func register(_ image: CGImage) -> ImageRef {
        let ref = ImageRef(pixelSize: CGSize(width: image.width, height: image.height))
        lock.lock()
        images[ref.id] = image
        lock.unlock()
        return ref
    }

    /// Registers a bitmap under an existing ref (package loading, where the
    /// document's refs must keep resolving).
    public func register(_ image: CGImage, as ref: ImageRef) {
        lock.lock()
        images[ref.id] = image
        lock.unlock()
    }

    public func image(for ref: ImageRef) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return images[ref.id]
    }

    public func remove(_ ref: ImageRef) {
        lock.lock()
        images[ref.id] = nil
        lock.unlock()
    }
}
