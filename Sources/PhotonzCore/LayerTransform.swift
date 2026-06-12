import CoreGraphics
import Foundation

/// Non-destructive geometric transform applied to a layer at render time.
///
/// Angles are radians, expressed in the document's top-left coordinate space:
/// positive `rotation` turns the layer clockwise on screen, positive `skewX`
/// slants the bottom edge to the right, and positive `skewY` slants the right
/// edge downward. Flips mirror the layer around its own center.
public struct LayerTransform: Hashable, Codable, Sendable {
    public var rotation: CGFloat
    public var skewX: CGFloat
    public var skewY: CGFloat
    public var flipHorizontal: Bool
    public var flipVertical: Bool

    public static let identity = LayerTransform()

    public init(rotation: CGFloat = 0, skewX: CGFloat = 0, skewY: CGFloat = 0,
                flipHorizontal: Bool = false, flipVertical: Bool = false) {
        self.rotation = rotation
        self.skewX = skewX
        self.skewY = skewY
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
    }

    public var isIdentity: Bool {
        rotation == 0 && skewX == 0 && skewY == 0 && !flipHorizontal && !flipVertical
    }

    /// The affine transform around `center`, composed flip → skew → rotation.
    public func affineTransform(around center: CGPoint) -> CGAffineTransform {
        var t = CGAffineTransform(translationX: -center.x, y: -center.y)
        if flipHorizontal {
            t = t.concatenating(CGAffineTransform(scaleX: -1, y: 1))
        }
        if flipVertical {
            t = t.concatenating(CGAffineTransform(scaleX: 1, y: -1))
        }
        if skewX != 0 || skewY != 0 {
            t = t.concatenating(CGAffineTransform(a: 1, b: tan(skewY), c: tan(skewX), d: 1, tx: 0, ty: 0))
        }
        if rotation != 0 {
            t = t.concatenating(CGAffineTransform(rotationAngle: rotation))
        }
        return t.concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    }
}
