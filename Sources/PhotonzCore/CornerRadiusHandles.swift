import CoreGraphics
import Foundation

/// The four small handles just inside a picked shape's corners, and what a
/// pull on one of them means.
///
/// Rounding a corner used to be a number you typed. Every drawing tool lets you
/// grab a dot inside the corner and pull it instead, watching the curve follow
/// your hand, and that is what this places.
///
/// The dot sits at the CENTRE of the corner's curve — the point the arc is
/// struck from — which is the one placement that travels a point for every
/// point the hand does. Sitting it ON the arc, where it looks like it belongs,
/// would have it creep three points over a fifty point pull, and a handle that
/// does not keep up with the hand holding it feels broken. A square corner has
/// no curve at all, so its dot rests a fixed distance in from the corner, far
/// enough that it is never mistaken for the resize square sitting on the
/// corner itself.
///
/// Placement and hit-testing both read this, so every dot drawn is a target
/// and nothing else is — the same contract `Handles` keeps for the eight
/// resize handles.
public enum CornerRadiusHandles {

    /// How far in from a SQUARE corner its handle rests, in screen points.
    ///
    /// Twelve puts about seventeen screen points of diagonal between this dot
    /// and the resize square on the corner. Both carry a six point tolerance,
    /// so the two targets cannot touch, and a press aimed at one can never
    /// come back as the other — a resize that turned into a rounding is the
    /// worst thing this could do.
    public static let restInset: CGFloat = 12

    /// Screen-point slop around a rounding handle, matching the resize
    /// handles' so no target on the selection is easier to hit than another.
    public static let tolerance: CGFloat = 6

    /// How round this box can be at all: half its short edge, where its corners
    /// are already touching.
    public static func limit(in frame: CGRect) -> CGFloat {
        max(0, min(frame.width, frame.height) / 2)
    }

    /// Whether a frame this size at this zoom wears rounding handles at all.
    ///
    /// A frame too cramped to keep its edge midpoints is far too cramped to
    /// take four more dots inside it, so the threshold is the SAME one: past
    /// it the resize handles have already stepped outside the outline, and the
    /// inside of the shape belongs to picking it up and moving it.
    public static func offered(in frame: CGRect, zoom: CGFloat) -> Bool {
        let z = zoom > 0 ? zoom : 1
        return frame.width * z >= Handles.crampedSpan && frame.height * z >= Handles.crampedSpan
    }

    /// Where `corner`'s handle sits, in the space `frame` is stated in.
    ///
    /// `radii` is how round the shape is RIGHT NOW, including mid-drag, so the
    /// dot travels with the curve. A corner rounded past what the box can draw
    /// sits where the curve actually lands, not where the number asked for.
    public static func point(for corner: CornerRadii.Corner, in frame: CGRect,
                             radii: CornerRadii, zoom: CGFloat) -> CGPoint {
        let z = zoom > 0 ? zoom : 1
        let drawn = radii.fitted(in: frame.size)[corner]
        let inset = min(max(drawn, restInset / z), limit(in: frame))
        return CGPoint(x: isLeft(corner) ? frame.minX + inset : frame.maxX - inset,
                       y: isTop(corner) ? frame.minY + inset : frame.maxY - inset)
    }

    /// The corner whose handle is under `p`, if any. Nearest wins, and a frame
    /// that draws no handles answers no press.
    public static func hit(at p: CGPoint, frame: CGRect, radii: CornerRadii, zoom: CGFloat,
                           screenTolerance: CGFloat = tolerance) -> CornerRadii.Corner? {
        guard offered(in: frame, zoom: zoom) else { return nil }
        let z = zoom > 0 ? zoom : 1
        let slop = screenTolerance / z
        var best: (corner: CornerRadii.Corner, distance: CGFloat)?
        for corner in CornerRadii.Corner.allCases {
            let hp = point(for: corner, in: frame, radii: radii, zoom: zoom)
            let distance = hypot(p.x - hp.x, p.y - hp.y)
            if distance <= slop, distance < (best?.distance ?? .infinity) {
                best = (corner, distance)
            }
        }
        return best?.corner
    }

    /// How round a pull to `p` asks `corner` to be.
    ///
    /// The hand rarely stays on the diagonal, so both sides have their say:
    /// the answer is how far in the pointer has come averaged over the two
    /// edges that meet at this corner, which is exactly the pointer's distance
    /// along the diagonal the handle travels. Pulled back out past the corner
    /// the corner squares off; pushed past fully round it stops there.
    ///
    /// Whole points, because whole points are what the panel shows: a corner
    /// dragged to 30 must not read 30 while holding 30.4.
    public static func radius(draggingTo p: CGPoint, corner: CornerRadii.Corner,
                              in frame: CGRect) -> CGFloat {
        let dx = isLeft(corner) ? p.x - frame.minX : frame.maxX - p.x
        let dy = isTop(corner) ? p.y - frame.minY : frame.maxY - p.y
        return min(max(((dx + dy) / 2).rounded(), 0), limit(in: frame))
    }

    /// The four corners after this pull: one of them alone, or all four
    /// together while the modifier is held.
    public static func radii(_ radii: CornerRadii, corner: CornerRadii.Corner,
                             to radius: CGFloat, allCorners: Bool) -> CornerRadii {
        guard !allCorners else { return CornerRadii(radius) }
        var updated = radii
        updated[corner] = radius
        return updated
    }

    private static func isLeft(_ corner: CornerRadii.Corner) -> Bool {
        corner == .topLeft || corner == .bottomLeft
    }

    private static func isTop(_ corner: CornerRadii.Corner) -> Bool {
        corner == .topLeft || corner == .topRight
    }
}

extension Layer {
    /// Whether this layer wears the four corner dots on the canvas.
    ///
    /// SHAPES only, and only the ones drawn with corners. A screenshot, a
    /// group, a frame and a text block all round from the panel and always
    /// have, but they are what most selections in this app are, and four dots
    /// inside every one of them would be noise on top of the picture somebody
    /// is measuring. A locked layer offers no handles of any kind.
    public var offersCornerRadiusHandles: Bool {
        annotation != nil && hasCorners && !isLocked
    }

    /// This layer rounded like this, without touching the one it came from.
    ///
    /// For chrome that has to follow a drag before the drag has landed: the
    /// blue outline hugs a rounded shape's curve, so while a corner is being
    /// pulled the outline has to curve by the number under the hand rather
    /// than the one still on disk.
    public func rounded(_ radii: CornerRadii) -> Layer {
        var copy = self
        copy.setRoundedCorners(radii)
        return copy
    }
}
