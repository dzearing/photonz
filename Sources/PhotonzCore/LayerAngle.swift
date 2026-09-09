import CoreGraphics
import Foundation

/// The angle a layer has been turned to, as a number a person reads and types.
///
/// The model keeps rotation in radians (`LayerTransform.rotation`), because
/// that is what the maths wants. Nobody types radians. Everything a person
/// sees or types is DEGREES, and this is the one place the two meet, so no
/// surface can invent its own conversion or its own idea of what 370 means.
///
/// Degrees run the same way the knob does: positive turns the layer clockwise
/// on screen, which is the direction you dragged to get there.
public enum LayerAngle {

    /// The mark after the number. A degree sign rather than a word, because it
    /// sits in a row of `px` numbers and the whole point of it being there is
    /// that one glance tells you this number is not a length.
    public static let unitSuffix = "\u{00B0}"

    /// A turn all the way round. Named so the wrapping below reads as what it
    /// is rather than as a magic 360.
    public static let fullTurn: CGFloat = 360

    /// Degrees for a stored angle.
    public static func degrees(fromRadians radians: CGFloat) -> CGFloat {
        guard radians.isFinite else { return 0 }
        return radians * 180 / .pi
    }

    /// The angle to store for a typed number of degrees.
    public static func radians(fromDegrees degrees: CGFloat) -> CGFloat {
        guard degrees.isFinite else { return 0 }
        return degrees * .pi / 180
    }

    /// The same turn said the shortest way: greater than -180 and up to 180.
    ///
    /// Swinging the knob round twice leaves 730 behind it, and a field reading
    /// 730 is describing the gesture rather than the layer — the shape on
    /// screen is at 10. Half a turn is written 180 rather than -180, so a
    /// layer stood on its head reads the way people say it.
    public static func normalized(_ degrees: CGFloat) -> CGFloat {
        guard degrees.isFinite else { return 0 }
        var turned = degrees.truncatingRemainder(dividingBy: fullTurn)
        if turned <= -fullTurn / 2 {
            turned += fullTurn
        } else if turned > fullTurn / 2 {
            turned -= fullTurn
        }
        // A negative zero prints as "-0", which reads as a layer turned some
        // tiny amount widdershins rather than as one standing straight.
        return turned == 0 ? 0 : turned
    }

    /// The number the field actually shows: whole degrees, said the shortest
    /// way. Rounded first and wrapped again, so 179.6 reads 180 rather than
    /// -180 arriving by the back door.
    public static func display(_ degrees: CGFloat) -> CGFloat {
        normalized(normalized(degrees).rounded())
    }

    /// Whether two angles are the same turn, once both are said the shortest
    /// way. Typing the number that is already in the box changes nothing, and
    /// "nothing" has to include typing 45 at a layer sitting on 405.
    public static func isSameTurn(_ a: CGFloat, _ b: CGFloat) -> Bool {
        normalized(a) == normalized(b)
    }
}
