import CoreGraphics
import Foundation

/// Geometry for the selection chrome's transform gestures: the rotate knob
/// and ⌥-corner skew drags. Views feed pointer positions; the math (snap,
/// conventions, rotation compensation) lives here.
public enum TransformDrag {

    /// 15°, the rotation snap step (⇧).
    public static let rotationSnapStep = CGFloat.pi / 12

    /// The pointer's angle around `center` in top-left screen space: 0 points
    /// right, positive grows clockwise — matching `LayerTransform.rotation`.
    public static func pointerAngle(_ p: CGPoint, around center: CGPoint) -> CGFloat {
        atan2(p.y - center.y, p.x - center.x)
    }

    /// The rotation a knob drag produces: the start rotation plus how far the
    /// pointer swung around the center, optionally snapped to 15°.
    public static func rotation(from start: CGFloat, grabAngle: CGFloat,
                                currentAngle: CGFloat, snapped: Bool) -> CGFloat {
        let rotation = start + (currentAngle - grabAngle)
        guard snapped else { return rotation }
        return (rotation / rotationSnapStep).rounded() * rotationSnapStep
    }

    /// An ⌥-corner drag mapped to skew: the dragged corner follows the
    /// pointer. Horizontal pointer motion adjusts `skewX` against the corner's
    /// half-height lever, vertical motion adjusts `skewY` against the
    /// half-width; an existing rotation is compensated (skew composes before
    /// rotation), so the corner tracks the pointer on screen either way.
    public static func skewed(_ start: LayerTransform, corner: ResizeHandle,
                              by delta: CGPoint, frameSize: CGSize) -> LayerTransform {
        guard corner.isCorner, frameSize.width > 0, frameSize.height > 0 else { return start }
        // Pointer delta into pre-rotation (skew-stage) space.
        var d = delta
        if start.rotation != 0 {
            d = delta.applying(CGAffineTransform(rotationAngle: -start.rotation))
        }
        // The corner's lever arms from the center, in skew-stage coordinates.
        let leverY: CGFloat = corner == .topLeft || corner == .topRight
            ? -frameSize.height / 2 : frameSize.height / 2
        let leverX: CGFloat = corner == .topLeft || corner == .bottomLeft
            ? -frameSize.width / 2 : frameSize.width / 2
        var result = start
        result.skewX = atan(tan(start.skewX) + d.x / leverY)
        result.skewY = atan(tan(start.skewY) + d.y / leverX)
        return result
    }
}

extension Layer {
    /// The frame's corners mapped through the layer's transform, clockwise
    /// from top-left: the polygon the selection outline should draw for a
    /// rotated/skewed layer.
    public var transformedCorners: [CGPoint] {
        let corners = [CGPoint(x: frame.minX, y: frame.minY),
                       CGPoint(x: frame.maxX, y: frame.minY),
                       CGPoint(x: frame.maxX, y: frame.maxY),
                       CGPoint(x: frame.minX, y: frame.maxY)]
        guard !transform.isIdentity else { return corners }
        let t = transform.affineTransform(around: CGPoint(x: frame.midX, y: frame.midY))
        return corners.map { $0.applying(t) }
    }
}
