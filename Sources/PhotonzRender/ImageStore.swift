import CoreGraphics
import Foundation
import PhotonzCore

/// Owns the actual bitmaps referenced by `ImageRef`s in documents.
/// Documents stay value-typed; pixels live here exactly once.
public final class ImageStore: @unchecked Sendable {
    private var images: [UUID: CGImage] = [:]
    /// The drawings among them, kept as their own bytes so they are drawn
    /// sharp at any size (`VectorArt`). Each also has a picture in `images`,
    /// at its own size, for everything that reads pixels.
    private var vectors: [UUID: VectorArt] = [:]
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
    /// document's refs must keep resolving). New pixels under a drawing's ref
    /// are what it now is, so the drawing behind it is let go.
    public func register(_ image: CGImage, as ref: ImageRef) {
        lock.lock()
        images[ref.id] = image
        vectors[ref.id] = nil
        lock.unlock()
    }

    /// Keeps a drawing, with a picture of it at its own size beside it. Nil
    /// when the drawing will not draw.
    @discardableResult
    public func register(_ art: VectorArt) -> ImageRef? {
        let size = art.pixelSize
        guard let picture = art.drawn(width: Int(size.width), height: Int(size.height)) else { return nil }
        let ref = ImageRef(pixelSize: size)
        lock.lock()
        images[ref.id] = picture
        vectors[ref.id] = art
        lock.unlock()
        return ref
    }

    /// Keeps `art` as the drawing behind a picture already held under `ref`
    /// (package loading, where the picture is read from the package too).
    public func attach(_ art: VectorArt, to ref: ImageRef) {
        lock.lock()
        vectors[ref.id] = art
        lock.unlock()
    }

    /// The drawing behind a picture, or nil for a picture that is only pixels.
    public func vector(for ref: ImageRef) -> VectorArt? {
        lock.lock()
        defer { lock.unlock() }
        return vectors[ref.id]
    }

    public func image(for ref: ImageRef) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return images[ref.id]
    }

    /// A store holding exactly the pictures this one holds now, which nothing
    /// done to this one afterwards can change. Cheap: the pictures are shared,
    /// not copied. A render handed one draws what was there when it was asked
    /// for, however many frames of a recording come and go while it waits its
    /// turn (`RenderScheduler.submit(_:store:stamp:)`).
    public func snapshot() -> ImageStore {
        let copy = ImageStore()
        lock.lock()
        copy.images = images
        copy.vectors = vectors
        lock.unlock()
        return copy
    }

    /// How many pictures are held.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return images.count
    }

    /// The bytes of picture held, as decoded bitmaps: what a store costs in
    /// memory, for the budget the app is held to (`MemoryBudget`).
    public var pixelBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return images.values.reduce(0) { $0 + $1.bytesPerRow * $1.height }
    }

    /// Lets go of every picture. For a window that has closed: anything that
    /// still reaches the store after it finds nothing, rather than keeping a
    /// closed document's pixels alive.
    public func removeAll() {
        lock.lock()
        images.removeAll()
        vectors.removeAll()
        lock.unlock()
    }

    public func remove(_ ref: ImageRef) {
        lock.lock()
        images[ref.id] = nil
        vectors[ref.id] = nil
        lock.unlock()
    }
}
