import CoreGraphics
import Foundation
import os
import PhotonzCore

/// A paint layer keeps its last raster (`docs/design/brushes.md`, decision 5).
///
/// Strokes are marked in order and each lands on the paint the ones before it
/// left, so the bitmap after strokes 0..n-1 (and the washes still wet then) is
/// exactly where stroke n starts from. A layer asked for again with strokes
/// added since is painted from the kept bitmap, only the new strokes simulated;
/// the result is byte for byte what replaying the whole list gives. Undo asks
/// for a shorter list, which is kept too while it fits.
///
/// Before this, every press of a smudge, a wash or oil re-simulated every
/// stroke on the layer on the main thread, to read the paint under it, and
/// every render after the release did it again: 200 ms a press with five
/// strokes on a 12 megapixel canvas and 420 ms with ten, measured 2026-10-25
/// (`Scripts/playtest/smudge-after-paint-keeps-up-walk.json`).
///
/// Kept within `budgetBytes`, least recently used let go first, and emptied
/// when the Mac runs short of memory (`DocumentRenderer.clearSharedCaches`).
/// A raster bigger than half the budget is never kept.
public final class PaintRasterCache: @unchecked Sendable {
    // @unchecked: every stored property below is guarded by `lock`, and the
    // entries it holds are never changed once made.

    /// The one the renderer and the canvas share, so the raster a render keeps
    /// is the one the next press reads. 128 MB: two 12 megapixel layers kept
    /// at two scales, or one with its last state for undo.
    public static let shared = PaintRasterCache(budgetBytes: 128 << 20)

    public let budgetBytes: Int

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var clock: UInt64 = 0
    private var simulated = 0
    /// One gate per bitmap size and scale, held while strokes are simulated
    /// for it, so a second request for the same layer waits for the first and
    /// takes its result instead of doing the same work alongside it.
    private var gates: [Slot: OSAllocatedUnfairLock<Void>] = [:]

    public init(budgetBytes: Int) {
        self.budgetBytes = budgetBytes
    }

    /// Strokes this cache has simulated in full.
    public var strokesSimulated: Int { lock.withLock { simulated } }

    /// The bytes of bitmap it is holding.
    public var keptBytes: Int { lock.withLock { entries.reduce(0) { $0 + $1.byteCount } } }

    /// Lets go of every kept raster.
    public func letGo() {
        lock.withLock { entries.removeAll() }
    }

    /// `content` drawn inside `size` at `scale` pixels per point, as
    /// `PaintRasterizer.rasterize` draws it.
    public func raster(_ content: PaintContent, size: CGSize, scale: CGFloat) -> CGImage? {
        guard scale > 0, scale.isFinite else { return nil }
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width >= 1, height >= 1 else { return nil }
        let visible = CGRect(origin: .zero, size: size)
        // Only what can mark the box decides its pixels.
        let strokes = content.strokes.filter { $0.bounds.intersects(visible) }
        let slot = Slot(width: width, height: height, scale: Double(scale))
        let gate = lock.withLock {
            if let gate = gates[slot] { return gate }
            let gate = OSAllocatedUnfairLock()
            gates[slot] = gate
            return gate
        }
        gate.lock()
        defer { gate.unlock() }

        let base = lock.withLock { () -> Entry? in
            let best = entries.filter { $0.slot == slot && $0.isPrefix(of: strokes) }
                .max { $0.strokes.count < $1.strokes.count }
            if let best {
                clock += 1
                best.used = clock
            }
            return best
        }
        if let base, base.strokes.count == strokes.count { return base.image }

        let byteCount = width * height * 4
        let storage = NSMutableData(length: byteCount)
        guard let storage,
              let context = CGContext(
                data: storage.mutableBytes, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var wet = WetWashes()
        if let base {
            storage.replaceBytes(in: NSRange(location: 0, length: byteCount), withBytes: base.storage.bytes)
            wet = base.wet
        }
        // Top-left points, the space the samples are stored in.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        let from = base?.strokes.count ?? 0
        for stroke in strokes[from...] {
            PaintRasterizer.paint(stroke, in: context, scale: scale, wet: &wet)
        }
        guard let provider = CGDataProvider(data: storage),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }

        lock.withLock {
            simulated += strokes.count - from
            guard byteCount * 2 <= budgetBytes else { return }
            clock += 1
            entries.append(Entry(slot: slot, strokes: strokes, storage: storage, image: image, wet: wet,
                                 byteCount: byteCount, used: clock))
            var total = entries.reduce(0) { $0 + $1.byteCount }
            while total > budgetBytes, let oldest = entries.indices.min(by: { entries[$0].used < entries[$1].used }) {
                total -= entries[oldest].byteCount
                entries.remove(at: oldest)
            }
        }
        return image
    }

    private struct Slot: Hashable {
        let width: Int
        let height: Int
        let scale: Double
    }

    /// One kept raster: the strokes it holds, its bytes, and the washes still
    /// wet after the last of them. Never changed once made, but for `used`,
    /// which only changes under the cache's lock.
    private final class Entry {
        let slot: Slot
        let strokes: [BrushStroke]
        let storage: NSMutableData
        let image: CGImage
        let wet: WetWashes
        let byteCount: Int
        var used: UInt64

        init(slot: Slot, strokes: [BrushStroke], storage: NSMutableData, image: CGImage, wet: WetWashes,
             byteCount: Int, used: UInt64) {
            self.slot = slot
            self.strokes = strokes
            self.storage = storage
            self.image = image
            self.wet = wet
            self.byteCount = byteCount
            self.used = used
        }

        func isPrefix(of list: [BrushStroke]) -> Bool {
            strokes.count <= list.count && list.starts(with: strokes)
        }
    }
}
