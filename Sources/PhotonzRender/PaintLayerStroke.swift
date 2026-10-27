import CoreGraphics
import Foundation
import PhotonzCore

/// The stroke under the hand, painted in its layer's own pixels at the scale
/// the canvas shows that layer, onto the raster the layer keeps
/// (`PaintRasterCache`), with the code that lands it (`LiveMarker`).
///
/// So what the hand sees is what lands. The user, 2026-10-25: "when I draw, it
/// seems like all of the previous strokes are recomputed because they change
/// and then swap into this higher resolution". Before this the live stroke was
/// marked in the view's pixels, over a copy of the layer drawn into them, while
/// the layer landed at its own: a wash's grain, a bristle's ridges and the paper
/// under charcoal all fell on a different grid of pixels, and the stroke
/// changed on the release over a tenth of what it covered. And a wash replayed
/// every earlier stroke still wet for its water on every press; here the washes
/// come with the kept raster.
///
/// The overlay it marks is what the stroke lays over the layer (the stroke
/// alone, shown at its opacity, for the media that are not
/// `showsAtFullStrength`), the same size as the layer's raster. The canvas
/// shows it a piece at a time (`picture(of:)`), so a move costs what it
/// touched rather than the whole layer.
public final class PaintLayerStroke {
    /// The layer's raster, in pixels.
    public let width: Int
    public let height: Int
    /// Pixels per point.
    public let scale: CGFloat
    /// What the overlay is shown at when it is not shown as it is.
    public let opacity: CGFloat
    /// Whether the overlay already holds what lands over the paint, at its
    /// strength, rather than the stroke alone.
    public var showsAtFullStrength: Bool { marker.showsAtFullStrength }
    /// Whether the end is thinned in as it goes (`LiveMarker.tapersItsEnd`):
    /// a mouse stroke's. The canvas turns it off when the first sample comes
    /// from a pen, whose own press thins its end.
    public var tapersItsEnd: Bool {
        get { marker.tapersItsEnd }
        set { marker.tapersItsEnd = newValue }
    }

    private let overlayData: NSMutableData
    private let overlay: CGContext
    /// The paper a smudge drags or a stroke on a new layer lands on: a copy
    /// of its own. Nil when the stroke reads the kept raster as it is.
    private let paperData: NSMutableData?
    private let paper: CGContext
    /// Held for as long as `paper` reads its bytes.
    private let base: PaintLayerBase?
    private let marker: PaintRasterizer.LiveMarker

    /// `stroke` in the layer's own points, landing on `base` (the layer as it
    /// stands at `scale`), or on fresh paper the size of `size` points when
    /// it starts a layer. Nil for a box with no pixels in it.
    public init?(stroke: BrushStroke, base: PaintLayerBase?, size: CGSize, scale: CGFloat) {
        guard scale > 0, scale.isFinite else { return nil }
        let width = base?.width ?? Int((size.width * scale).rounded())
        let height = base?.height ?? Int((size.height * scale).rounded())
        guard width >= 1, height >= 1 else { return nil }
        let bytesPerRow = width * 4
        let count = bytesPerRow * height
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        // Zeroed as it is first touched, so a big layer costs what is painted.
        guard let overlayData = NSMutableData(length: count),
              let overlay = CGContext(data: overlayData.mutableBytes, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: space,
                                      bitmapInfo: info) else { return nil }
        // A smudge moves the paint it reads as it goes, so it works on a copy;
        // everything else only reads the layer, and reads the kept bytes.
        let paperData: NSMutableData?
        let paperBytes: UnsafeMutableRawPointer
        if let base, stroke.settings.mode != .smudge {
            paperData = nil
            paperBytes = UnsafeMutableRawPointer(mutating: base.bytes)
        } else {
            guard let copy = NSMutableData(length: count) else { return nil }
            if let base { copy.replaceBytes(in: NSRange(location: 0, length: count), withBytes: base.bytes) }
            paperData = copy
            paperBytes = copy.mutableBytes
        }
        guard let paper = CGContext(data: paperBytes, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow, space: space, bitmapInfo: info) else { return nil }
        // The washes still wet when it begins, as the renderer hands them on.
        var wet = base?.wet ?? WetWashes()
        let washes = stroke.settings.medium == .watercolour && stroke.settings.mode == .paint
            ? wet.under(stroke) : []
        guard let marker = PaintRasterizer.LiveMarker(
            stroke: stroke, bitmap: overlay, pointsToPixels: CGAffineTransform(scaleX: scale, y: scale),
            clip: CGRect(x: 0, y: 0, width: width, height: height), working: paper, earlier: [],
            wet: washes) else { return nil }
        self.width = width
        self.height = height
        self.scale = scale
        self.opacity = CGFloat(stroke.settings.opacity / 100)
        self.overlayData = overlayData
        self.overlay = overlay
        self.paperData = paperData
        self.paper = paper
        self.base = base
        self.marker = marker
    }

    /// Marks `dabs`, the next ones the walker settled (in the layer's
    /// points), and says which pixels of the overlay changed, top-left, or
    /// null for none.
    @discardableResult
    public func mark(_ dabs: [BrushDab]) -> CGRect { marker.mark(dabs) }

    /// The pointer has come up: anything the medium held back goes down.
    @discardableResult
    public func finish() -> CGRect { marker.finish() }

    /// The overlay's pixels inside `rect` (top-left pixels), as a picture of
    /// their own: cut to the layer, or, `padded`, the whole of `rect` with
    /// nothing in it past the layer's edge. Nil for a rect with no pixels in
    /// it.
    public func picture(of rect: CGRect, padded: Bool = false, in space: CGColorSpace? = nil) -> CGImage? {
        guard let piece = picture(of: rect, padded: padded) else { return nil }
        // In the screen's own colours, so Core Animation hands it straight to
        // the screen: given sRGB, it matched every piece to the screen on the
        // main thread as it went up, a third of a big brush's move.
        guard let space, space != piece.colorSpace,
              let context = CGContext(data: nil, width: piece.width, height: piece.height, bitsPerComponent: 8,
                                      bytesPerRow: piece.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else { return piece }
        context.setBlendMode(.copy)
        context.draw(piece, in: CGRect(x: 0, y: 0, width: piece.width, height: piece.height))
        return context.makeImage() ?? piece
    }

    private func picture(of rect: CGRect, padded: Bool) -> CGImage? {
        let layer = CGRect(x: 0, y: 0, width: width, height: height)
        let frame = padded ? rect.integral : rect.integral.intersection(layer)
        let cut = frame.intersection(layer)
        guard !frame.isNull, frame.width >= 1, frame.height >= 1, !cut.isNull, cut.width >= 1 else { return nil }
        let w = Int(frame.width), h = Int(frame.height)
        let x = Int(cut.minX), y = Int(cut.minY), runWidth = Int(cut.width)
        let dx = Int(cut.minX - frame.minX), dy = Int(cut.minY - frame.minY)
        let rowBytes = w * 4
        var piece = Data(count: rowBytes * h)
        let source = overlayData.bytes
        piece.withUnsafeMutableBytes { out in
            guard let to = out.baseAddress else { return }
            for row in 0..<Int(cut.height) {
                (to + (row + dy) * rowBytes + dx * 4)
                    .copyMemory(from: source + ((y + row) * width + x) * 4, byteCount: runWidth * 4)
            }
        }
        guard let provider = CGDataProvider(data: piece as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
