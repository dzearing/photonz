import CoreGraphics
import Foundation

/// The loupe that rides beside the pointer during a region capture: which
/// pixels of the frozen picture it magnifies, where it sits so it never covers
/// the corner being dragged, and what its readout says. Pure geometry; the
/// overlay draws it.
public enum CaptureLoupe {

    /// How many device pixels the loupe shows across. Odd, so one pixel sits
    /// dead centre: the one under the pointer.
    public static let defaultPixelsAcross = 25

    /// Each device pixel becomes a square this many points wide.
    public static let pointsPerPixel: CGFloat = 5

    /// Distance from the pointer to the loupe's nearest edge, in points.
    public static let gap: CGFloat = 16

    /// The magnified patch: `source` is the pixel rect of the frozen picture to
    /// draw (already cut to the picture's bounds), `destination` is where it
    /// lands inside the loupe's square, in the square's own top-left points.
    /// When the patch runs off the picture's edge the destination shrinks with
    /// it, so the pointer's pixel stays in the middle and the missing part
    /// shows as empty.
    public struct Sample: Equatable, Sendable {
        public var source: CGRect
        public var destination: CGRect

        public init(source: CGRect, destination: CGRect) {
            self.source = source
            self.destination = destination
        }
    }

    // MARK: - Placement

    /// Where the loupe's top-left corner goes. Beyond the pointer with `gap`
    /// between them, on the side away from `anchor` (the drag's start) so it
    /// stays outside the box being drawn and off its active corner; below and
    /// to the right when there is no drag. Each axis flips to the other side
    /// when that side would leave `bounds`, and clamps when neither fits.
    public static func origin(pointer: CGPoint, anchor: CGPoint?, size: CGSize, gap: CGFloat,
                              within bounds: CGRect) -> CGPoint {
        let awayX: CGFloat = (anchor.map { pointer.x >= $0.x } ?? true) ? 1 : -1
        let awayY: CGFloat = (anchor.map { pointer.y >= $0.y } ?? true) ? 1 : -1
        return CGPoint(
            x: place(pointer.x, direction: awayX, extent: size.width, gap: gap,
                     low: bounds.minX, high: bounds.maxX),
            y: place(pointer.y, direction: awayY, extent: size.height, gap: gap,
                     low: bounds.minY, high: bounds.maxY))
    }

    private static func place(_ pointer: CGFloat, direction: CGFloat, extent: CGFloat, gap: CGFloat,
                              low: CGFloat, high: CGFloat) -> CGFloat {
        func origin(_ direction: CGFloat) -> CGFloat {
            direction > 0 ? pointer + gap : pointer - gap - extent
        }
        func fits(_ origin: CGFloat) -> Bool { origin >= low && origin + extent <= high }
        let preferred = origin(direction)
        if fits(preferred) { return preferred }
        let flipped = origin(-direction)
        if fits(flipped) { return flipped }
        return min(max(preferred, low), max(low, high - extent))
    }

    // MARK: - Sampling

    /// The device pixel under a pointer given in points.
    public static func pixel(at pointer: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: floor(pointer.x * scale), y: floor(pointer.y * scale))
    }

    /// The `pixelsAcross` × `pixelsAcross` patch centred on the pixel under
    /// `pointer`, cut to a picture of `imageSize` pixels, and where that cut
    /// patch lands in a loupe square `square` points wide. Nil when the pointer
    /// is off the picture entirely.
    public static func sample(pointer: CGPoint, scale: CGFloat, pixelsAcross: Int,
                              imageSize: CGSize, square: CGFloat) -> Sample? {
        guard pixelsAcross > 0, scale > 0, imageSize.width > 0, imageSize.height > 0 else { return nil }
        let centre = pixel(at: pointer, scale: scale)
        let half = CGFloat(pixelsAcross / 2)
        let full = CGRect(x: centre.x - half, y: centre.y - half,
                          width: CGFloat(pixelsAcross), height: CGFloat(pixelsAcross))
        let source = full.intersection(CGRect(origin: .zero, size: imageSize))
        guard !source.isNull, source.width >= 1, source.height >= 1 else { return nil }
        let magnification = square / CGFloat(pixelsAcross)
        let destination = CGRect(x: (source.minX - full.minX) * magnification,
                                 y: (source.minY - full.minY) * magnification,
                                 width: source.width * magnification,
                                 height: source.height * magnification)
        return Sample(source: source, destination: destination)
    }

    /// The cell in the loupe's square that holds the pointer's own pixel.
    public static func centerCell(pixelsAcross: Int, square: CGFloat) -> CGRect {
        guard pixelsAcross > 0 else { return .zero }
        let magnification = square / CGFloat(pixelsAcross)
        let index = CGFloat(pixelsAcross / 2)
        return CGRect(x: index * magnification, y: index * magnification,
                      width: magnification, height: magnification)
    }

    // MARK: - Readout

    /// The lines under the picture: the pointer, its device pixel when the
    /// display is not 1x, and the selection's size while dragging.
    ///
    /// Units follow the editor, so a size reads the same on both sides of the
    /// capture: "px" is the logical, on-screen size (what the editor reads by
    /// default, its Logical mode) and "actual px" is the raw device pixel
    /// (the editor's Actual mode). Nothing here says "pt".
    ///
    /// Coordinates floor rather than round: they name the pixel the crop
    /// starts or ends on.
    public static func readout(pointer: CGPoint, scale: CGFloat, selection: CGSize?) -> [String] {
        var lines = ["\(Int(floor(pointer.x))), \(Int(floor(pointer.y))) \(MeasureUnit.points.suffix)"]
        if scale != 1 {
            let px = pixel(at: pointer, scale: scale)
            lines.append("\(Int(px.x)), \(Int(px.y)) \(actualSuffix)")
        }
        if let selection {
            lines.append("\(WindowPick.sizeLabel(for: selection)) \(MeasureUnit.points.suffix)")
        }
        return lines
    }

    /// The device-pixel line's unit: the editor's Actual mode, spelled the way
    /// its Units readout spells it.
    static let actualSuffix = "actual \(MeasureUnit.pixels.suffix)"
}
