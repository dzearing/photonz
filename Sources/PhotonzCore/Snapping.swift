import CoreGraphics
import Foundation

/// Drag-to-move snapping: layer edges and centers attract to canvas edges and
/// the canvas center. Tolerance is expressed in screen points so the magnetic
/// feel is constant at any zoom level.
public enum Snapping {
    public struct Result: Equatable, Sendable {
        /// The (possibly snapped) frame origin.
        public var origin: CGPoint
        /// Canvas-space x of the vertical guide that captured, for drawing.
        public var guideX: CGFloat?
        /// Canvas-space y of the horizontal guide that captured.
        public var guideY: CGFloat?

        public init(origin: CGPoint, guideX: CGFloat? = nil, guideY: CGFloat? = nil) {
            self.origin = origin
            self.guideX = guideX
            self.guideY = guideY
        }
    }

    public static func snapFrameOrigin(_ proposed: CGPoint, size: CGSize, canvas: CGSize,
                                       zoom: CGFloat, screenTolerance: CGFloat = 8) -> Result {
        let tolerance = zoom > 0 ? screenTolerance / zoom : screenTolerance
        let x = snapAxis(origin: proposed.x, length: size.width, canvasLength: canvas.width, tolerance: tolerance)
        let y = snapAxis(origin: proposed.y, length: size.height, canvasLength: canvas.height, tolerance: tolerance)
        return Result(origin: CGPoint(x: x.origin, y: y.origin), guideX: x.guide, guideY: y.guide)
    }

    /// Snaps one axis: the frame's leading edge, center, and trailing edge each
    /// attract to the canvas edge/center/edge; the nearest in-tolerance pair wins.
    private static func snapAxis(origin: CGFloat, length: CGFloat, canvasLength: CGFloat,
                                 tolerance: CGFloat) -> (origin: CGFloat, guide: CGFloat?) {
        let candidates: [(offset: CGFloat, target: CGFloat)] = [
            (0, 0),
            (length / 2, canvasLength / 2),
            (length, canvasLength),
        ]
        var best: (origin: CGFloat, guide: CGFloat, distance: CGFloat)?
        for c in candidates {
            let distance = abs(origin + c.offset - c.target)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                best = (c.target - c.offset, c.target, distance)
            }
        }
        guard let best else { return (origin, nil) }
        return (best.origin, best.guide)
    }
}
