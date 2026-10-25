import CoreGraphics
import Foundation
import PhotonzCore

/// A brush tile's picture (`brush-library.html`): the brush's sample stroke
/// (`BrushSample`) painted by the very engine that paints the canvas, at the
/// brush's own settings and in the current colour. Never a stored picture, so
/// a medium added later, or a setting changed, shows on its tile at once.
public enum BrushPreview {

    /// The sample stroke for `settings` in `colorHex`, on a clear tile of
    /// `size` points at `scale` pixels each. Nil for a tile with no pixels.
    public static func image(settings: BrushSettings, colorHex: String, size: CGSize,
                             scale: CGFloat) -> CGImage? {
        let stroke = BrushSample.stroke(settings: settings, colorHex: colorHex, in: size)
        return PaintRasterizer.rasterize(PaintContent(strokes: [stroke]), size: size, scale: scale)
    }
}

/// The tile pictures already painted, so reopening the chooser or switching a
/// group chip does not paint them again. Keyed on everything that changes the
/// picture (the brush's settings, the colour, the tile's size and scale), with
/// a limit on how many it keeps, and let go under memory pressure (`NSCache`).
public final class BrushPreviewCache: Sendable {

    /// The one the app's tiles share.
    public static let shared = BrushPreviewCache(limit: 48)

    private final class Entry {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    // NSCache is thread safe; it is not marked Sendable in the SDK, and the
    // keys it holds are this class's own strings.
    private nonisolated(unsafe) let cache = NSCache<NSString, Entry>()
    /// The keys put in, so `count` can say how many are still held: NSCache
    /// will not say.
    private let keys = KeyLedger()

    public init(limit: Int) {
        cache.countLimit = max(1, limit)
    }

    /// The tile picture, painted now if it is not already held.
    public func image(settings: BrushSettings, colorHex: String, size: CGSize, scale: CGFloat) -> CGImage? {
        let key = Self.key(settings: settings, colorHex: colorHex, size: size, scale: scale) as NSString
        if let held = cache.object(forKey: key) { return held.image }
        guard let image = BrushPreview.image(settings: settings, colorHex: colorHex, size: size, scale: scale)
        else { return nil }
        cache.setObject(Entry(image), forKey: key)
        keys.insert(key as String)
        return image
    }

    /// How many pictures are held right now.
    public var count: Int {
        keys.prune { cache.object(forKey: $0 as NSString) != nil }
    }

    public func removeAll() {
        cache.removeAllObjects()
        _ = keys.prune { _ in false }
    }

    static func key(settings: BrushSettings, colorHex: String, size: CGSize, scale: CGFloat) -> String {
        let values = settings.values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        return "\(settings.medium.rawValue)|\(values.joined(separator: ","))|\(colorHex.lowercased())"
            + "|\(size.width)x\(size.height)@\(scale)"
    }
}

/// A locked set of strings: the cache's record of what it put in.
private final class KeyLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var keys = Set<String>()

    func insert(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        keys.insert(key)
    }

    /// Keeps the keys `keep` says are still held, and says how many that is.
    func prune(_ keep: (String) -> Bool) -> Int {
        lock.lock(); defer { lock.unlock() }
        keys = keys.filter(keep)
        return keys.count
    }
}
