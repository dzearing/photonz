import CoreGraphics
import Foundation

/// Magnetizes the ends of a drawn annotation — an arrow's tip, a line's tail, a
/// box's corner — to the UI boundaries already detected in the picture
/// (`EdgeMap`) and to the pixel grid.
///
/// The reason this exists is arithmetic: a Retina capture opens at half zoom, so
/// one step of the mouse moves the point TWO image pixels and landing on a
/// border by eye is luck. The caliper solved that long ago; an arrow that points
/// at the same border deserves the same magnet, drawn with the same yellow line.
///
/// What is different from a caliper foot is which axes may catch. A caliper leg
/// is gated by the direction the HAND is travelling. An arrow is gated by the
/// direction the ARROW is pointing, which is steadier and closer to what the
/// user means: an arrow lying flat is pointing at a vertical border, so its tip
/// takes that border's x and keeps the height you chose along it; a diagonal
/// arrow is pointing into a corner and takes both. Box shapes always take both,
/// because a corner is a corner.
public enum AnnotationSnapping {

    /// How square-on a line has to be before its cross axis stops catching:
    /// within about 17 degrees of an axis the shaft reads as pointing straight
    /// along it. Anything more oblique is aimed at a corner and takes both.
    public static let axisPurityRatio: CGFloat = 0.3

    /// The axes this endpoint may catch edges on. `opposite` is the end that is
    /// staying put (nil while the first point is still being placed).
    public static func axes(shape: AnnotationShape, opposite: CGPoint?,
                            moving: CGPoint) -> (x: Bool, y: Bool) {
        guard shape == .line || shape == .arrow, let opposite else { return (true, true) }
        let dx = abs(moving.x - opposite.x)
        let dy = abs(moving.y - opposite.y)
        guard dx > 0 || dy > 0 else { return (true, true) }
        if dy < dx * axisPurityRatio { return (x: true, y: false) }
        if dx < dy * axisPurityRatio { return (x: false, y: true) }
        return (true, true)
    }

    /// Snaps one end of an annotation being drawn or re-shaped.
    /// - point: where the pointer is, in document coordinates.
    /// - shape: what is being drawn (decides the axis gate above).
    /// - opposite: the end staying put, or nil when there is not one yet.
    /// - free: the user refused the magnet (⌘, or a constrained ⇧ drag whose
    ///   angle owns the point); the pointer position is returned untouched.
    /// - holding: the lines this drag is already standing on, so a caught edge
    ///   is not taken and given back under a wobbling hand.
    public static func snap(_ point: CGPoint, shape: AnnotationShape,
                            opposite: CGPoint?, edges: EdgeMap, zoom: CGFloat,
                            free: Bool = false,
                            screenTolerance: CGFloat = 8,
                            holding: SnapHold = .none) -> EdgeSnapping.Snap {
        guard !free else { return EdgeSnapping.Snap(point: point) }
        // What this pointer would catch on its own, with no memory of the drag.
        var snap = EdgeSnapping.snap(point, edges: edges, zoom: zoom,
                                     screenTolerance: screenTolerance,
                                     includeCenters: false, snapToPixelGrid: true)
        // …then the drag's memory, but only where it is still the best answer.
        //
        // A caught line keeps a drag until the pointer is clearly away from it,
        // which is what stops a wobbling hand taking a line and giving it back.
        // A mark being DRAWN sweeps right across the picture to reach what it
        // points at, though, and crossing a line is not catching one: a text
        // baseline picked up on the way would ride along for the rest of the
        // sweep and park the tip a dozen points short of the border you aimed
        // at — the very complaint this exists to answer. So a held line that is
        // farther from the pointer than a line the pointer can reach by itself
        // is treated as left behind rather than held.
        var kept = holding
        if let x = kept.x, let fresh = snap.guideX, abs(x - point.x) > abs(fresh - point.x) {
            kept.x = nil
        }
        if let y = kept.y, let fresh = snap.guideY, abs(y - point.y) > abs(fresh - point.y) {
            kept.y = nil
        }
        if kept.x != nil || kept.y != nil {
            snap = EdgeSnapping.snap(point, edges: edges, zoom: zoom,
                                     screenTolerance: screenTolerance,
                                     includeCenters: false, snapToPixelGrid: true,
                                     holding: kept)
        }
        let allowed = axes(shape: shape, opposite: opposite, moving: point)
        if !allowed.x {
            snap.point.x = point.x.rounded()
            snap.guideX = nil
        }
        if !allowed.y {
            snap.point.y = point.y.rounded()
            snap.guideY = nil
        }
        return snap
    }
}
