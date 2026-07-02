import CoreGraphics
import Foundation

/// Magnetizes a dragged measure corner to the strong UI boundaries detected in
/// the screenshot (`EdgeMap`, 16.4) and to the integer pixel grid.
///
/// Snapping is per-axis and independent: a corner can capture its x to a vertical
/// edge while its y stays free (then rounds to the pixel grid). Tolerance is given
/// in screen points and divided by `zoom`, so the magnet feels the same at any
/// zoom. Pixel-grid snapping lands thin 1px sizer lines crisply on the grid; an
/// edge capture always beats the grid (and is reported back so the UI can draw a
/// highlight on the captured edge).
public enum EdgeSnapping {

    public struct Snap: Equatable, Sendable {
        /// The snapped point.
        public var point: CGPoint
        /// The x of the vertical edge that captured (for a highlight), or nil if
        /// x only snapped to the pixel grid / stayed free.
        public var guideX: CGFloat?
        /// The y of the horizontal edge that captured, or nil.
        public var guideY: CGFloat?

        public init(point: CGPoint, guideX: CGFloat? = nil, guideY: CGFloat? = nil) {
            self.point = point
            self.guideX = guideX
            self.guideY = guideY
        }
    }

    /// Snaps `point` against `edges`.
    /// - zoom: canvas zoom; tolerance is `screenTolerance / zoom` in image space.
    /// - snapToPixelGrid: when no edge captures an axis, round it to whole pixels.
    public static func snap(_ point: CGPoint, edges: EdgeMap, zoom: CGFloat,
                            screenTolerance: CGFloat = 6,
                            snapToPixelGrid: Bool = true) -> Snap {
        let tolerance = zoom > 0 ? screenTolerance / zoom : screenTolerance
        let x = snapAxis(point.x, candidates: edges.verticalEdges,
                         tolerance: tolerance, pixelGrid: snapToPixelGrid)
        let y = snapAxis(point.y, candidates: edges.horizontalEdges,
                         tolerance: tolerance, pixelGrid: snapToPixelGrid)
        return Snap(point: CGPoint(x: x.value, y: y.value), guideX: x.guide, guideY: y.guide)
    }

    /// Snaps a single axis value to the nearest in-tolerance edge candidate,
    /// falling back to the pixel grid. Returns the captured edge position as the
    /// guide (nil for a grid/free result).
    private static func snapAxis(_ value: CGFloat, candidates: [EdgeCandidate],
                                 tolerance: CGFloat, pixelGrid: Bool) -> (value: CGFloat, guide: CGFloat?) {
        var best: (position: CGFloat, distance: CGFloat)?
        for candidate in candidates {
            let position = CGFloat(candidate.position)
            let distance = abs(position - value)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                best = (position, distance)
            }
        }
        if let best {
            return (best.position, best.position)
        }
        return (pixelGrid ? value.rounded() : value, nil)
    }
}
