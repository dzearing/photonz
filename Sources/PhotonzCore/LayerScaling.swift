import CoreGraphics
import Foundation

/// Resizing a container: the pieces are PLACED, and the type never changes size.
///
/// Dragging a handle on a group gives every child a new box, worked out from
/// what the container says its contents do and what that child says for itself
/// (`LayerPlacement`). A piece may keep its distance from an edge, keep its
/// offset from the middle, keep both distances and grow, or — the default, and
/// what every document did before placement existed — be multiplied by however
/// much the container grew.
///
/// What is drawn from its box grows with that box (photos, collages, shapes,
/// lines and arrows); what is measured in points holds still (text size, stroke
/// width, corner radius, shadow, a caliper's ticks). That is the same call every
/// interface tool makes, and it is why a card made wider does not blow up its
/// label. See `docs/design/ui-building.md`, "Resizing places the pieces".
///
/// The placement is expressed once, here, as a new rect per child, so a leaf
/// goes through the same `resized(to:)` its own handles use and every content
/// kind keeps its existing remap (an arrow's endpoints, a caliper's feet, a zoom
/// callout's magnification) rather than growing a second one.
enum LayerScaling {

    /// A group re-fitted so the box it occupies in its parent's space becomes
    /// `box`. Every child is placed inside the new box by its own rule, and the
    /// anchor moves with the box, so nothing inside is renumbered against an
    /// origin that wandered.
    ///
    /// An axis with nothing in it (a group of one horizontal rule has no
    /// height) is not touched: there is nothing there to divide by, and
    /// dividing by it would hand back infinities.
    /// A SCREEN re-fitted to `box`. A frame's own handle moves where it clips
    /// rather than magnifying what is on it, so a piece nobody has given a rule
    /// to holds still, exactly as it did before placement existed; a piece that
    /// HAS a rule follows it, which is what makes a bar stretch across a screen
    /// dragged wider and a button stay in the corner it was put in.
    static func refitting(_ frame: Layer, to box: CGRect) -> Layer {
        resizing(frame, to: box, unsetHoldsStill: true)
    }

    /// A group that ARRANGES itself, resized. Nothing inside is scaled: the
    /// group is simply told how big it is, and its own flow fills that box —
    /// which is what makes a menu 320 points wide with every row stretching to
    /// 320 rather than a menu whose type got 20% bigger.
    ///
    /// Only the side that actually changed is pinned, so typing one width into
    /// a stack leaves its height still following its rows, and only the axis
    /// the handle was dragged on stops sizing itself.
    static func rearranging(_ layer: Layer, to box: CGRect) -> Layer {
        guard var layout = layer.group?.layout else { return layer }
        let current = layer.localBounds
        if box.width != current.width { layout.width = max(0, box.width) }
        if box.height != current.height { layout.height = max(0, box.height) }
        var out = layer
        out.frame.origin = box.origin
        out.setGroupLayout(layout)
        return GroupFlow.flowing(out)
    }

    static func resizing(_ layer: Layer, to box: CGRect,
                         unsetHoldsStill: Bool = false) -> Layer {
        let current = layer.localBounds
        let sx = factor(from: current.width, to: box.width)
        let sy = factor(from: current.height, to: box.height)
        // The anchor keeps its place relative to the box it is being dragged
        // to, which makes the container's box in CHILD space a plain scale of
        // what it was, and every child's new box a sum in that one space.
        let anchor = CGPoint(x: box.minX + (layer.frame.minX - current.minX) * sx,
                             y: box.minY + (layer.frame.minY - current.minY) * sy)
        let before = current.offsetBy(dx: -layer.frame.minX, dy: -layer.frame.minY)
        let after = box.offsetBy(dx: -anchor.x, dy: -anchor.y)
        let container = layer.group?.contentPlacement
        var out = layer
        out.children = layer.children.map { child in
            let resolved = LayerPlacement.resolving(child: child.placement, container: container)
            let placement = unsetHoldsStill ? resolved.onAScreen : resolved
            let target = placing(child.localBounds, from: before, to: after,
                                 sx: sx, sy: sy, as: placement,
                                 canScaleX: current.width > 0, canScaleY: current.height > 0)
            guard child.isGroup else { return child.resized(to: target) }
            // A child that arranges itself is told its new size rather than
            // scaled, so a stack stretched across a screen dragged wider fills
            // the width with its own rows instead of magnifying them.
            if child.group?.layout != nil, !child.isFrame {
                return rearranging(child, to: target)
            }
            return resizing(child, to: target)
        }
        // A frame's stored size IS its box, so it takes the box exactly rather
        // than a multiply that rounds; an ordinary group's stored size is
        // unused and only rides along.
        out.frame = layer.isFrame
            ? CGRect(origin: anchor, size: box.size)
            : CGRect(origin: anchor,
                     size: CGSize(width: layer.frame.width * sx,
                                  height: layer.frame.height * sy))
        return out
    }

    /// One child's new box, in the space its siblings live in. `before` and
    /// `after` are the container's own box in that same space.
    private static func placing(_ box: CGRect, from before: CGRect, to after: CGRect,
                                sx: CGFloat, sy: CGFloat, as placement: ResolvedPlacement,
                                canScaleX: Bool, canScaleY: Bool) -> CGRect {
        let x = span(low: box.minX, length: box.width,
                     before: (before.minX, before.width), after: (after.minX, after.width),
                     scale: sx, rule: canScaleX ? placement.horizontal.span : .scale)
        let y = span(low: box.minY, length: box.height,
                     before: (before.minY, before.height), after: (after.minY, after.height),
                     scale: sy, rule: canScaleY ? placement.vertical.span : .scale)
        return CGRect(x: x.low, y: y.low, width: x.length, height: y.length)
    }

    /// The one axis of placement, shared by both directions: everything below
    /// is "left" and "right" only because an axis has to be called something.
    private static func span(low: CGFloat, length: CGFloat,
                             before: (low: CGFloat, length: CGFloat),
                             after: (low: CGFloat, length: CGFloat),
                             scale: CGFloat, rule: PlacementSpan) -> (low: CGFloat, length: CGFloat) {
        let leading = low - before.low
        let trailing = (before.low + before.length) - (low + length)
        switch rule {
        case .scale:
            return (after.low + leading * scale, length * scale)
        case .leading:
            return (after.low + leading, length)
        case .trailing:
            return (after.low + after.length - trailing - length, length)
        case .center:
            let offset = (low + length / 2) - (before.low + before.length / 2)
            return (after.low + after.length / 2 + offset - length / 2, length)
        case .stretch:
            return (after.low + leading, max(after.length - leading - trailing, 0))
        }
    }

    /// How much one side of the box grew. A side that was nothing stays
    /// nothing, and a result that is not a real number changes nothing.
    private static func factor(from current: CGFloat, to target: CGFloat) -> CGFloat {
        guard current > 0 else { return 1 }
        let scale = target / current
        return scale.isFinite && scale > 0 ? scale : 1
    }
}

/// The five placements with the axis taken out of their names, so the maths is
/// written once instead of once per direction.
enum PlacementSpan {
    case scale, leading, trailing, center, stretch
}

extension HorizontalPlacement {
    var span: PlacementSpan {
        switch self {
        case .scale: .scale
        case .left: .leading
        case .center: .center
        case .right: .trailing
        case .stretch: .stretch
        }
    }
}

extension VerticalPlacement {
    var span: PlacementSpan {
        switch self {
        case .scale: .scale
        case .top: .leading
        case .center: .center
        case .bottom: .trailing
        case .stretch: .stretch
        }
    }
}
