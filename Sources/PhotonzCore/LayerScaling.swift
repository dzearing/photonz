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
        // A group told the smallest and the largest it may get stops there when
        // its handle is dragged past it, so the number in the Layout section
        // and the box on the canvas can never disagree after a drag.
        let held = CGRect(origin: box.origin,
                          size: CGSize(width: layout.heldWidth(max(0, box.width)),
                                       height: layout.heldHeight(max(0, box.height))))
        if box.width != current.width { layout.width = held.width }
        if box.height != current.height { layout.height = held.height }
        // A group that arranges nothing still places its contents the way it
        // always did when its handle is dragged: the rules on each piece say
        // whether it holds an edge, keeps its offset from the middle or grows.
        // The drag simply also gives the group that size of its own, so an
        // axis that was closing around its contents stops.
        var out = layout.arranges ? layer : resizing(layer, to: held)
        out.frame.origin = held.origin
        out.setGroupLayout(layout)
        return GroupFlow.flowing(out)
    }

    /// A COPY of a component, resized. Nothing inside it is touched: its
    /// contents are refilled from its original after every edit, so scaling
    /// them is work that is thrown away and a stretched copy would snap back.
    ///
    /// Instead the box it was given is kept as the copy's OWN size, one axis at
    /// a time, and written back over the original's after every sync
    /// (`InstanceSizing`). Only the side that actually changed is claimed, so
    /// dragging a copy wider leaves its height still following the original.
    ///
    /// The size is also put straight onto the copy's working layout — or onto
    /// its frame, where it is a copy of a screen — so the drag is on screen
    /// before the sync that confirms it has run.
    static func resizingCopy(_ layer: Layer, to box: CGRect) -> Layer {
        let current = layer.localBounds
        var own = layer.instanceSize ?? .following
        if box.width != current.width { own.width = max(0, box.width) }
        if box.height != current.height { own.height = max(0, box.height) }
        var out = layer
        out.setInstanceSize(own)
        if layer.isFrame {
            out.frame = CGRect(origin: box.origin,
                               size: CGSize(width: own.usedWidth ?? layer.frame.width,
                                            height: own.usedHeight ?? layer.frame.height))
        } else {
            var layout = layer.group?.layout ?? layer.workingLayout
            if let width = own.usedWidth { layout.width = width }
            if let height = own.usedHeight { layout.height = height }
            out.setGroupLayout(layout)
            out.frame.origin = box.origin
        }
        // What is inside lines up in the new box by the same rules it would
        // follow on the original: a bar that stretches spreads, a title that
        // centres re-centres, a button pinned to the right stays pinned. The
        // sync works the same answer out again from the original's contents
        // (`InstanceSizing.fitted`); this is what makes the drag look right
        // while it is still in the hand.
        out.children = placingContents(out.children,
                                       from: CGRect(origin: .zero, size: current.size),
                                       to: CGRect(origin: .zero, size: out.localBounds.size),
                                       container: layer.group?.contentPlacement,
                                       unsetHoldsStill: layer.isFrame)
        return GroupFlow.flowing(out)
    }

    /// The children of a container moved from one box into another, both given
    /// in the children's OWN space.
    ///
    /// `resizing` is this plus working the two boxes out from a layer and where
    /// its handle was dragged to. A copy of a component knows them already
    /// without a drag, because the box its contents arrive in is its original's
    /// and the box they belong in is its own (`InstanceSizing.fitted`).
    static func placingContents(_ children: [Layer], from before: CGRect, to after: CGRect,
                                container: LayerPlacement?,
                                unsetHoldsStill: Bool = false) -> [Layer] {
        let sx = factor(from: before.width, to: after.width)
        let sy = factor(from: before.height, to: after.height)
        return children.map { child in
            let resolved = LayerPlacement.resolving(child: child.placement, container: container)
            let placement = unsetHoldsStill ? resolved.onAScreen : resolved
            let target = placing(child.localBounds, from: before, to: after,
                                 sx: sx, sy: sy, as: placement,
                                 canScaleX: before.width > 0, canScaleY: before.height > 0)
            // A text box normally throws away a height handed to it, so a
            // child STRETCHED down the container says so: the height in
            // `target` is the container's answer, not a guess.
            guard child.isGroup else {
                return child.resized(to: target,
                                     fillingHeight: before.height > 0
                                         && placement.vertical == .stretch)
            }
            // A child that arranges itself is told its new size rather than
            // scaled, so a stack stretched across a screen dragged wider fills
            // the width with its own rows instead of magnifying them.
            //
            // A COPY in here is placed the same way and claims nothing: this is
            // the container's answer, not somebody choosing a size for that
            // copy, so it goes on following its original.
            if child.isComponentInstance {
                return child.resized(to: target, placedByContainer: true)
            }
            if child.group?.layout != nil, !child.isFrame {
                return rearranging(child, to: target)
            }
            return resizing(child, to: target)
        }
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
        var out = layer
        out.children = placingContents(layer.children, from: before, to: after,
                                       container: layer.group?.contentPlacement,
                                       unsetHoldsStill: unsetHoldsStill)
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
