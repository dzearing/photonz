import CoreGraphics

/// The hold a press keeps on a measurement's handle for the length of a drag.
///
/// A caliper's feet are grabbed with several points of slack around the dot, so
/// the point a press lands on is almost never the handle itself. Putting the
/// handle wherever the pointer is, the moment the drag starts, throws that
/// slack away as a jump: a foot grabbed 8 points to its left and then pulled 6
/// points right ended up 2 points LEFT of where it had been, and the reading
/// got shorter while the hand was pulling it longer.
///
/// So the grab keeps its grip. The handle is carried at the same offset from
/// the pointer it had when the press landed, which makes the promise a person
/// already expects from dragging anything else: it moves as far as your hand
/// moved, the way your hand moved.
///
/// The grip is the offset in DOCUMENT points, worked out once at the press. The
/// magnets are then asked about the point the handle is going to rather than the
/// point the pointer is on, so a foot still lands on the edge nearest the FOOT.
public struct MeasureHandleGrip: Equatable, Sendable {
    /// Added to the pointer to get the handle: handle minus press.
    public let offset: CGSize

    /// No grip at all: the handle rides exactly under the pointer.
    public static let none = MeasureHandleGrip(offset: .zero)

    public init(offset: CGSize) {
        self.offset = offset
    }

    /// The grip a press takes on a handle, given where each of them is.
    ///
    /// `tolerance` is the slack the grab was allowed, in VIEW points, and it
    /// bounds the grip: a grip can never be bigger than the reach that let the
    /// press take hold in the first place, however the handle was found. The
    /// clamp keeps the direction and shortens the distance.
    public static func taken(pressing press: CGPoint, handle: CGPoint,
                             zoom: CGFloat, tolerance: CGFloat) -> MeasureHandleGrip {
        guard zoom > 0, tolerance > 0 else { return .none }
        let dx = handle.x - press.x, dy = handle.y - press.y
        let onScreen = hypot(dx, dy) * zoom
        guard onScreen > 0 else { return .none }
        let scale = onScreen > tolerance ? tolerance / onScreen : 1
        return MeasureHandleGrip(offset: CGSize(width: dx * scale, height: dy * scale))
    }

    /// Where the handle belongs for this pointer position.
    public func handlePoint(for pointer: CGPoint) -> CGPoint {
        CGPoint(x: pointer.x + offset.width, y: pointer.y + offset.height)
    }
}
