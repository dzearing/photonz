import CoreGraphics
import Foundation
import Synchronization

/// A drawing kept as the bytes of its own file, an SVG, so it can be drawn
/// afresh at whatever size it is shown (`video-title-wt.html`, the Media
/// shelf: "It keeps its own scale, so blowing one up on a 4K frame stays
/// crisp").
///
/// Everything else the app holds is pixels at one size, which is right for a
/// screenshot and wrong for a logo: blown up, a bitmap only has its own pixels
/// to give and goes soft. So the `ImageStore` keeps an SVG's bytes beside a
/// picture of it at its own size. The picture is what every reader of pixels
/// gets (a thumbnail, a flattened copy, a drag out to the Finder); the
/// renderer asks for the drawing instead and draws it at the size the frame
/// is about to be seen at.
public struct VectorArt: Sendable, Equatable {
    /// The file, exactly as it came in. A saved package carries these bytes.
    public let data: Data
    /// How big the drawing says it is, in points: its own width and height,
    /// or its view box when it states none.
    public let size: CGSize

    /// What reads and draws vector art. macOS draws an SVG through AppKit,
    /// which this module never imports, so the app hands one over at launch
    /// (`install`). With none installed an SVG reads as nothing at all.
    public struct Reader: Sendable {
        /// The drawing's own size, or nil for bytes that are not one.
        public var size: @Sendable (Data) -> CGSize?
        /// The drawing filling `width` by `height` pixels, transparent
        /// round it.
        public var draw: @Sendable (Data, Int, Int) -> CGImage?

        public init(size: @escaping @Sendable (Data) -> CGSize?,
                    draw: @escaping @Sendable (Data, Int, Int) -> CGImage?) {
            self.size = size
            self.draw = draw
        }
    }

    private static let installed = Mutex<Reader?>(nil)

    /// Makes `reader` the one every SVG is read and drawn with.
    public static func install(_ reader: Reader) {
        installed.withLock { $0 = reader }
    }

    public static var reader: Reader? { installed.withLock { $0 } }

    /// The longest side a drawing is ever drawn at, and the most pixels: a
    /// 4K frame covered edge to edge fits with room to spare, a logo grown
    /// past the frame by a hundred times does not ask for a gigapixel.
    public static let longestDrawnSide = 8192
    public static let mostDrawnPixels = 16_000_000

    public init(data: Data, size: CGSize) {
        self.data = data
        self.size = size
    }

    /// `data` read as vector art: nil when no reader is installed, or when the
    /// bytes are not a drawing with a size.
    public static func read(_ data: Data) -> VectorArt? {
        guard let reader, let size = reader.size(data),
              size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite
        else { return nil }
        return VectorArt(data: data, size: size)
    }

    public static func read(contentsOf url: URL) -> VectorArt? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return read(data)
    }

    /// The size in whole pixels the picture of it at its own size has, which
    /// is the size its `ImageRef` says.
    public var pixelSize: CGSize {
        CGSize(width: max(1, size.width.rounded(.up)), height: max(1, size.height.rounded(.up)))
    }

    /// The drawing at `width` by `height` pixels.
    public func drawn(width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, let reader = Self.reader else { return nil }
        return reader.draw(data, width, height)
    }

    /// How many pixels to draw a drawing at for a frame `size` pixels big.
    ///
    /// Never fewer than the frame has, so the drawing is only ever brought
    /// DOWN into it, which keeps every edge hard. Rounded up to a step a
    /// quarter of a doubling apart, so a logo growing through an animation is
    /// drawn a handful of times rather than once a frame; the step costs at
    /// most a fifth more pixels than the frame. Held under `longestDrawnSide`
    /// and `mostDrawnPixels`, where it is simply as sharp as that allows.
    public static func drawingSize(for size: CGSize) -> (width: Int, height: Int)? {
        guard size.width >= 1, size.height >= 1, size.width.isFinite, size.height.isFinite else { return nil }
        let longest = max(size.width, size.height)
        // A side already sitting on a step stays on it rather than being
        // pushed to the next by the rounding error in the logarithm.
        let stepped = pow(2, (log2(longest) * 4 - 1e-9).rounded(.up) / 4)
        var scale = max(1, stepped / longest)
        scale = min(scale, CGFloat(longestDrawnSide) / longest)
        let area = size.width * size.height * scale * scale
        if area > CGFloat(mostDrawnPixels) { scale *= (CGFloat(mostDrawnPixels) / area).squareRoot() }
        let width = max(1, Int((size.width * scale).rounded(.up)))
        let height = max(1, Int((size.height * scale).rounded(.up)))
        return (width, height)
    }
}
