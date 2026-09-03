import CoreGraphics
import Foundation

/// Resizing a group: the layout scales, the type does not.
///
/// Dragging a handle on a group multiplies every child's position and box by
/// the amount the group's box changed by, all the way down. What is drawn from
/// its box grows with it (photos, collages, shapes, lines and arrows); what is
/// measured in points holds still (text size, stroke width, corner radius,
/// shadow, a caliper's ticks). That is the same call every interface tool
/// makes, and it is why a card made wider does not blow up its label.
/// See `docs/design/ui-building.md`, "Resizing a group scales the layout, not
/// the type".
///
/// The scaling is expressed once, here, as a multiply on a rect, so a leaf goes
/// through the same `resized(to:)` its own handles use and every content kind
/// keeps its existing remap (an arrow's endpoints, a caliper's feet, a zoom
/// callout's magnification) rather than growing a second one.
enum LayerScaling {

    /// A group re-fitted so the box it occupies in its parent's space becomes
    /// `box`. Contents scale about the group's own anchor, and the anchor moves
    /// by the same factor, so nothing inside is renumbered against an origin
    /// that wandered.
    ///
    /// An axis with nothing in it (a group of one horizontal rule has no
    /// height) is not stretched: there is nothing there to multiply, and
    /// dividing by it would hand back infinities.
    static func resizing(_ layer: Layer, to box: CGRect) -> Layer {
        let current = layer.localBounds
        let sx = factor(from: current.width, to: box.width)
        let sy = factor(from: current.height, to: box.height)
        var out = layer
        out.children = layer.children.map { scaling($0, sx: sx, sy: sy) }
        // The anchor keeps its place relative to the box it is being dragged to.
        out.frame = CGRect(x: box.minX + (layer.frame.minX - current.minX) * sx,
                           y: box.minY + (layer.frame.minY - current.minY) * sy,
                           width: layer.frame.width * sx,
                           height: layer.frame.height * sy)
        return out
    }

    /// One layer, and everything under it, multiplied about the origin of the
    /// space it is stored in. A nested group (a frame included) scales its own
    /// box AND its contents: a screen inside a group that shrank should get
    /// smaller along with what is drawn on it, not stay huge and be clipped.
    private static func scaling(_ layer: Layer, sx: CGFloat, sy: CGFloat) -> Layer {
        let target = CGRect(x: layer.frame.minX * sx, y: layer.frame.minY * sy,
                            width: layer.frame.width * sx, height: layer.frame.height * sy)
        guard layer.isGroup else { return layer.resized(to: target) }
        var out = layer
        out.children = layer.children.map { scaling($0, sx: sx, sy: sy) }
        out.frame = target
        return out
    }

    /// How much one side of the box grew. A side that was nothing stays
    /// nothing, and a result that is not a real number changes nothing.
    private static func factor(from current: CGFloat, to target: CGFloat) -> CGFloat {
        guard current > 0 else { return 1 }
        let scale = target / current
        return scale.isFinite && scale > 0 ? scale : 1
    }
}
