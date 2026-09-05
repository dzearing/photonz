import CoreGraphics
import Foundation

/// Putting a stack's or a grid's contents where they belong.
///
/// Everything here is a box in the group's own space, so a photo, a shape, a
/// piece of text and a group are all just boxes and none of them needs a case
/// of its own.
///
/// Three rules, and they are the whole file:
///
/// - **The flow decides the axis it runs along.** A column stack sets every Y;
///   a row stack sets every X; a grid sets both, one cell at a time.
/// - **The placement rules decide the other axis** (`LayerPlacement`), so
///   "centre the rows" and "stretch the rows" are the menus that were already
///   there, and one layer can still say something different for itself.
/// - **A plain group flows from its own corner.** Its box is whatever its
///   contents add up to, so laying out from (0, 0) in its own space is what
///   keeps the stack still while an item inside it is dragged past another.
///   A screen has a real box, so it flows inside that box, minus its padding.
///
/// Order comes from where things ARE, not from the order they were drawn in:
/// drag a row above the one over it and it takes that place, which is the only
/// reading of that drag a stack can honour.
enum GroupFlow {

    /// One thing being placed: the box it occupies in the group's own space,
    /// and what it does on the axis the flow is NOT deciding.
    ///
    /// The box is the box a person can SEE (`Layer.contentBounds`), never the
    /// layer's own frame, because a measured text box carries a few points of
    /// empty room on its far edges. Flow by the frame and a gap of 8 between
    /// two lines of type reads as 12, and a label centred beside a shape sits
    /// two points off centre. `moved` hands the slack back when it puts the
    /// layer at the box, so the words land where the flow put them and the box
    /// still has the room its measurement asked for.
    struct Item {
        var box: CGRect
        var horizontal: PlacementSpan
        var vertical: PlacementSpan
    }

    /// The box the contents flow inside, one axis at a time: a number where the
    /// group has a size of its own, and nil where it is as big as what is in
    /// it. A screen's box is its frame; a stack's is whatever it was told, and
    /// a stack told nothing hugs on both axes, which is every stack that
    /// existed before a stack could be given a size.
    struct Bounds {
        var width: CGFloat?
        var height: CGFloat?
        /// True where the number above is not a size this group was given but
        /// the smallest or the largest it may be, holding open (or holding in)
        /// a box that is still the size of its contents. It is the difference
        /// between "you dragged this 300 wide, so things stay where you put
        /// them" and "a floor made room nobody has put anything in yet", which
        /// is the room a centred word should centre in.
        var limitedWidth = false
        var limitedHeight = false

        static let hugging = Bounds(width: nil, height: nil)

        /// The box this group flows inside. A screen's frame wins, because a
        /// screen is a real box you build on and its size is the size it is.
        static func of(_ layer: Layer, _ group: GroupContent, _ layout: GroupLayout) -> Bounds {
            guard !group.isFrame else {
                let box = layer.frame.standardized
                return Bounds(width: box.width, height: box.height)
            }
            return Bounds(width: layout.usedWidth, height: layout.usedHeight)
        }
    }

    // MARK: - The whole tree

    /// This layer with every stack and grid inside it arranged, innermost
    /// first, so a stack of stacks settles in one pass: the inner one is the
    /// size it is going to be before the outer one measures it.
    static func flowing(_ layer: Layer) -> Layer {
        guard let group = layer.group else { return layer }
        var out = layer
        out.children = group.children.map(flowing)
        guard let layout = group.layout else { return out }
        out.children = placed(out.children, layout: layout,
                              contentPlacement: group.contentPlacement,
                              bounds: Bounds.of(layer, group, layout),
                              onAScreen: group.isFrame)
        return out
    }

    // MARK: - One group's contents

    /// The children of one group, moved to where its layout puts them.
    ///
    /// Two shapes, and the second one is why a button can be as wide as its
    /// label: a stack or a grid ARRANGES what it holds, and a group with no
    /// kind simply CLOSES around what is already there. Either way the surface
    /// behind everything is dealt with last, once there is a box for it to
    /// take.
    private static func placed(_ children: [Layer], layout: GroupLayout,
                               contentPlacement: LayerPlacement?,
                               bounds: Bounds, onAScreen: Bool) -> [Layer] {
        let rules = resolving(children, contentPlacement, onAScreen: onAScreen)
        // Whatever the group was going to be, held to the smallest and the
        // largest it may get, so the flow lays out in the room it is actually
        // allowed rather than overflowing a ceiling quietly.
        let bounds = holding(children, rules: rules, layout: layout, bounds: bounds,
                             contentPlacement: contentPlacement, onAScreen: onAScreen)
        var out = layout.arranges
            ? arranged(children, rules: rules, layout: layout, bounds: bounds)
            : closedAround(children, rules: rules, layout: layout, bounds: bounds)
        // A piece told to stretch BOTH ways is not one of the things being
        // arranged: it is the surface behind them, painted to the box's own
        // edges. The room at the edges is room INSIDE that surface, which is
        // what a button's fill is, so it takes the whole box rather than the
        // part left over.
        let box = CGRect(origin: .zero,
                         size: size(of: out, layout: layout,
                                    contentPlacement: contentPlacement,
                                    bounds: bounds, onAScreen: onAScreen))
        for index in out.indices where rules[index].isSurface {
            out[index] = moved(out[index], to: box, fillingHeight: true)
        }
        return out
    }

    // MARK: - The smallest and the largest it may get

    /// The box this group is allowed, once its limits have had their say.
    ///
    /// An axis with a size of its own only needs that number held. An axis
    /// that is the size of its CONTENTS has to be laid out once to find out
    /// how big that is, so a limit that actually bites costs one extra pass
    /// and a limit that does not costs nothing at all: where the number comes
    /// back unchanged the axis goes on hugging, byte for byte the layout it
    /// would have had before limits existed.
    private static func holding(_ children: [Layer], rules: [ResolvedPlacement],
                                layout: GroupLayout, bounds: Bounds,
                                contentPlacement: LayerPlacement?,
                                onAScreen: Bool) -> Bounds {
        // A screen's box is its own frame, which is a size somebody gave it
        // and not one it worked out, so nothing here has anything to hold.
        guard layout.limitsSize, !onAScreen else { return bounds }
        var natural = CGSize(width: bounds.width ?? 0, height: bounds.height ?? 0)
        if bounds.width == nil || bounds.height == nil {
            let first = layout.arranges
                ? arranged(children, rules: rules, layout: layout, bounds: bounds)
                : closedAround(children, rules: rules, layout: layout, bounds: bounds)
            natural = size(of: first, layout: layout, contentPlacement: contentPlacement,
                           bounds: bounds, onAScreen: onAScreen, held: false)
        }
        let width = held(bounds.width, hugging: natural.width, by: layout.heldWidth)
        let height = held(bounds.height, hugging: natural.height, by: layout.heldHeight)
        return Bounds(width: width.side, height: height.side,
                      limitedWidth: width.limited, limitedHeight: height.limited)
    }

    /// One axis held to its limits: the number it ends up with, and whether a
    /// limit is what put it there.
    private static func held(_ side: CGFloat?, hugging natural: CGFloat,
                             by hold: (CGFloat) -> CGFloat) -> (side: CGFloat?, limited: Bool) {
        guard let side else {
            let limited = hold(natural)
            return limited == natural ? (nil, false) : (limited, true)
        }
        return (hold(side), false)
    }

    /// What each child does on each axis, once its own rule and the group's
    /// default have been put together.
    private static func resolving(_ children: [Layer], _ contentPlacement: LayerPlacement?,
                                  onAScreen: Bool) -> [ResolvedPlacement] {
        children.map { child in
            let resolved = LayerPlacement.resolving(child: child.placement,
                                                    container: contentPlacement)
            return onAScreen ? resolved.onAScreen : resolved
        }
    }

    // MARK: - A group that closes around what is inside it

    /// The children of a group that arranges nothing: everything stays where
    /// it was put, and on an axis the group was given no size, the whole lot
    /// moves as one to the room kept at that edge so the box can close around
    /// it. Moving them as one is the point — a hugging axis has no spare room
    /// to place anything in, so the arrangement somebody made by hand is kept
    /// exactly and only the box changes.
    private static func closedAround(_ children: [Layer], rules: [ResolvedPlacement],
                                     layout: GroupLayout, bounds: Bounds) -> [Layer] {
        let padding = layout.usedPadding
        let box = hugged(children, rules: rules, layout: layout, bounds: bounds)
        let dx = shift(children, rules, horizontal: true, bounds: bounds,
                       box: box.width, near: padding.left, far: padding.right)
        let dy = shift(children, rules, horizontal: false, bounds: bounds,
                       box: box.height, near: padding.top, far: padding.bottom)
        var out = children
        for index in children.indices {
            // The surface behind everything is placed once, at the end, from
            // the box the rest of the contents made. Squeezing it into the room
            // inside the edges first would hand it a box with nothing in it
            // wherever the room is bigger than the size the group was given,
            // and a shape with no height cannot be given one back.
            guard !rules[index].isSurface else { continue }
            let current = children[index].contentBounds
            // A piece told to stretch takes the room inside the edges, which on
            // a hugging axis is exactly as much room as the rest of the
            // contents made.
            let x = rules[index].horizontal == .stretch
                ? (padding.left, max(0, box.width - padding.horizontal))
                : (current.minX + dx, current.width)
            let y = rules[index].vertical == .stretch
                ? (padding.top, max(0, box.height - padding.vertical))
                : (current.minY + dy, current.height)
            out[index] = moved(children[index],
                               to: CGRect(x: x.0, y: y.0, width: x.1, height: y.1),
                               fillingHeight: rules[index].vertical == .stretch)
        }
        return out
    }

    /// How far the whole block of contents moves on one axis.
    ///
    /// Three cases, and the third is the one limits added. An axis that is the
    /// size of its contents pulls them back to the room at its near edge, so
    /// the box can close around them. An axis the group was GIVEN a size on
    /// leaves them exactly where they were put, because that size came from a
    /// handle somebody dragged and things staying put is what a group that
    /// arranges nothing means. An axis a LIMIT is holding open has room nobody
    /// has put anything in yet, so the block goes where its contents agree it
    /// should: a centred word centres in the room the floor made rather than
    /// sitting jammed against the left padding.
    ///
    /// Contents too big for the room start at the near edge whatever the rule
    /// says, so a word wider than its ceiling overhangs the far edge rather
    /// than escaping off the near one where nothing else in the app looks.
    private static func shift(_ children: [Layer], _ rules: [ResolvedPlacement],
                              horizontal: Bool, bounds: Bounds, box: CGFloat,
                              near: CGFloat, far: CGFloat) -> CGFloat {
        let low = self.near(children, rules, horizontal: horizontal)
        let side = horizontal ? bounds.width : bounds.height
        guard side != nil else { return near - low }
        guard horizontal ? bounds.limitedWidth : bounds.limitedHeight else { return 0 }
        let extent = max(0, box - near - far)
        let length = span(children, rules, horizontal: horizontal)
        guard length <= extent else { return near - low }
        let rule = agreed(children, rules, horizontal: horizontal)
        return span(size: length, start: near, extent: extent, rule: rule).low - low
    }

    /// The one thing every piece being measured says about this axis, or the
    /// near edge where they say different things. A block moves as one, so a
    /// block whose pieces disagree has no single answer to move by.
    private static func agreed(_ children: [Layer], _ rules: [ResolvedPlacement],
                               horizontal: Bool) -> PlacementSpan {
        let spans = Set(measuring(children, rules, horizontal: horizontal)
            .map { horizontal ? rules[$0].horizontal.span : rules[$0].vertical.span })
        return spans.count == 1 ? (spans.first ?? .leading) : .leading
    }

    // MARK: - How big the group ends up

    /// The size a group with a layout occupies: the number it was given on an
    /// axis, and on an axis it was given none, its contents plus the room it
    /// keeps at both of that axis' edges.
    ///
    /// A piece that stretches along an axis is not measured on that axis. It is
    /// trying to be the size of the box, so measuring it would make the box the
    /// size of the thing sizing itself to the box. Where every piece stretches
    /// there is nothing else to go on, so they are measured after all and the
    /// group keeps the size it had.
    static func size(of children: [Layer], layout: GroupLayout,
                     contentPlacement: LayerPlacement?, bounds: Bounds,
                     onAScreen: Bool, held: Bool = true) -> CGSize {
        let rules = resolving(children, contentPlacement, onAScreen: onAScreen)
        let padding = layout.usedPadding
        // A stack and a grid flow from their own corner, so the room at the
        // near edge is already in where the contents start and only the far
        // edge is still to be added. A group that arranges nothing is measured
        // from wherever its contents sit, at both edges.
        let box = layout.arranges
            ? CGSize(
                width: bounds.width ?? (children.isEmpty
                    ? padding.horizontal : far(children, rules, horizontal: true) + padding.right),
                height: bounds.height ?? (children.isEmpty
                    ? padding.vertical : far(children, rules, horizontal: false) + padding.bottom))
            : hugged(children, rules: rules, layout: layout, bounds: bounds)
        // The smallest and the largest it may get have the last word, so the
        // box on the canvas and the numbers in the Layout section agree even
        // where nobody has re-run the flow.
        guard held, !onAScreen else { return box }
        return layout.held(box)
    }

    /// The box of a group that closes around its contents: the room at both
    /// edges plus however much room the contents themselves take up.
    private static func hugged(_ children: [Layer], rules: [ResolvedPlacement],
                               layout: GroupLayout, bounds: Bounds) -> CGSize {
        let padding = layout.usedPadding
        return CGSize(
            width: bounds.width ?? (padding.horizontal + span(children, rules, horizontal: true)),
            height: bounds.height ?? (padding.vertical + span(children, rules, horizontal: false)))
    }

    /// The children that decide the size on one axis: everything that is not
    /// stretching along it, or everything there is when they all are.
    private static func measurable(_ children: [Layer], _ rules: [ResolvedPlacement],
                                   horizontal: Bool) -> [CGRect] {
        measuring(children, rules, horizontal: horizontal).map { children[$0].contentBounds }
    }

    /// The same children, as indices, so the rule they agree on can be read
    /// off exactly the set that decided the size.
    private static func measuring(_ children: [Layer], _ rules: [ResolvedPlacement],
                                  horizontal: Bool) -> [Int] {
        let taking = children.indices
            .filter { horizontal ? rules[$0].horizontal != .stretch : rules[$0].vertical != .stretch }
        return taking.isEmpty ? Array(children.indices) : taking
    }

    /// Where the contents begin on one axis, and how much room they take.
    private static func near(_ children: [Layer], _ rules: [ResolvedPlacement],
                             horizontal: Bool) -> CGFloat {
        let boxes = measurable(children, rules, horizontal: horizontal)
        return boxes.map { horizontal ? $0.minX : $0.minY }.min() ?? 0
    }

    private static func far(_ children: [Layer], _ rules: [ResolvedPlacement],
                            horizontal: Bool) -> CGFloat {
        let boxes = measurable(children, rules, horizontal: horizontal)
        return boxes.map { horizontal ? $0.maxX : $0.maxY }.max() ?? 0
    }

    private static func span(_ children: [Layer], _ rules: [ResolvedPlacement],
                             horizontal: Bool) -> CGFloat {
        let boxes = measurable(children, rules, horizontal: horizontal)
        guard !boxes.isEmpty else { return 0 }
        let low = boxes.map { horizontal ? $0.minX : $0.minY }.min() ?? 0
        let high = boxes.map { horizontal ? $0.maxX : $0.maxY }.max() ?? 0
        return max(0, high - low)
    }

    /// The room a group's contents already have inside it, which is what a
    /// group asked to close around them starts with: read it off where things
    /// already sit and nothing moves at the moment it starts hugging. A piece
    /// that fills the box is the box, not something with room around it, so it
    /// is what the room is measured FROM.
    static func room(around children: [Layer], contentPlacement: LayerPlacement?,
                     inside box: CGRect?) -> GroupPadding {
        let rules = resolving(children, contentPlacement, onAScreen: false)
        guard !children.isEmpty else { return .none }
        let outer = box ?? children.dropFirst()
            .reduce(children[0].localBounds) { $0.union($1.localBounds) }
        return GroupPadding(
            top: max(0, near(children, rules, horizontal: false) - outer.minY),
            right: max(0, outer.maxX - far(children, rules, horizontal: true)),
            bottom: max(0, outer.maxY - far(children, rules, horizontal: false)),
            left: max(0, near(children, rules, horizontal: true) - outer.minX))
    }

    // MARK: - A group that arranges its own contents

    /// The children of one stack or grid, moved to where the layout puts them.
    /// A hidden layer takes no place in the flow and is not moved: hiding a row
    /// closes the space it held, and showing it again puts it back. Neither
    /// does the surface behind everything, which is not a row at all.
    private static func arranged(_ children: [Layer], rules: [ResolvedPlacement],
                                 layout: GroupLayout, bounds: Bounds) -> [Layer] {
        let taking = children.indices.filter { children[$0].isVisible && !rules[$0].isSurface }
        guard !taking.isEmpty else { return children }
        let items = taking.map { index in
            Item(box: children[index].contentBounds,
                 horizontal: rules[index].horizontal.span,
                 vertical: rules[index].vertical.span)
        }
        let order = flowOrder(items.map(\.box), layout: layout)
        let targets = laidOut(order.map { items[$0] }, layout: layout, bounds: bounds)
        var out = children
        for (slot, position) in order.enumerated() {
            let child = children[taking[position]]
            // The height in that box is only the flow's answer where the flow
            // decides heights at all, so a Stretch in a column fills nothing.
            out[taking[position]] = moved(child, to: targets[slot],
                                          fillingHeight: layout.decidesHeight
                                              && items[position].vertical == .stretch)
        }
        return out
    }

    /// A layer put at a box a person can see. A move is a move — the layer is
    /// shifted, not re-fitted — because a caliper's feet and an arrow's ends
    /// are remapped by a resize and there is nothing to remap when only the
    /// corner changed.
    ///
    /// `visible` is what the flow decided, so it is measured in what can be
    /// seen. The layer's own box is that plus whatever empty room it carries
    /// beyond its content, which is nothing at all for everything but a
    /// measured text box: put the words at the box and the slack goes on past
    /// the far edges, into the gap, where it was always sitting and where
    /// nobody can see it.
    private static func moved(_ layer: Layer, to visible: CGRect,
                              fillingHeight: Bool = false) -> Layer {
        let current = layer.localBounds
        let content = layer.contentBounds
        let full = CGRect(x: visible.minX, y: visible.minY,
                          width: visible.width + (current.width - content.width),
                          height: visible.height + (current.height - content.height))
        // Nothing that HAS a size is ever squashed to none: a shape with no
        // height cannot be given one back (its own resize has nothing to scale
        // from), so a group keeping more room than the size it was given leaves
        // what is inside it a point rather than losing it for good.
        let box = CGRect(x: full.minX, y: full.minY,
                         width: current.width > 0 ? max(1, full.width) : full.width,
                         height: current.height > 0 ? max(1, full.height) : full.height)
        guard current != box else { return layer }
        guard current.size == box.size else {
            // The flow is the CONTAINER deciding, so a copy placed here is not
            // being given a size of its own: it goes on following its original
            // and this width is worked out again next time the container moves.
            return layer.resized(to: box, fillingHeight: fillingHeight,
                                 placedByContainer: true)
        }
        var out = layer
        out.frame = layer.frame.offsetBy(dx: box.minX - current.minX, dy: box.minY - current.minY)
        return out
    }

    // MARK: - The maths

    /// Where each box lands, in the order handed in.
    static func laidOut(_ items: [Item], layout: GroupLayout, bounds: Bounds) -> [CGRect] {
        guard !items.isEmpty else { return [] }
        return layout.kind == .grid ? gridded(items, layout: layout, bounds: bounds)
                                    : stacked(items, layout: layout, bounds: bounds)
    }

    /// The room across one axis, once the padding on both of that axis' edges
    /// is taken off, or nil where the group is as big as what is in it and
    /// there is no room to share out.
    private static func room(_ side: CGFloat?, between padding: CGFloat) -> CGFloat? {
        side.map { max(0, $0 - padding) }
    }

    private static func stacked(_ items: [Item], layout: GroupLayout,
                                bounds: Bounds) -> [CGRect] {
        let horizontal = layout.direction.isHorizontal
        let padding = layout.usedPadding
        // Everything starts inside the near edges of the corner the group flows
        // from, whether that corner belongs to a screen, to a stack with a size
        // of its own, or to a stack that is exactly as big as its contents.
        let crossStart = horizontal ? padding.top : padding.left
        // The cross axis runs across the room inside the group's own width, once
        // both of that axis' edges have taken theirs; where the group has no
        // size of its own, across the widest thing in it, which is what that
        // group's box IS.
        let crossExtent = room(horizontal ? bounds.height : bounds.width,
                               between: horizontal ? padding.vertical : padding.horizontal)
            ?? (items.map { horizontal ? $0.box.height : $0.box.width }.max() ?? 0)
        var cursor = horizontal ? padding.left : padding.top
        var out: [CGRect] = []
        for item in items {
            let along = horizontal ? item.box.width : item.box.height
            let cross = span(size: horizontal ? item.box.height : item.box.width,
                             start: crossStart, extent: crossExtent,
                             rule: horizontal ? item.vertical : item.horizontal)
            out.append(horizontal
                ? CGRect(x: cursor, y: cross.low, width: along, height: cross.length)
                : CGRect(x: cross.low, y: cursor, width: cross.length, height: along))
            cursor += along + layout.usedGap
        }
        return out
    }

    private static func gridded(_ items: [Item], layout: GroupLayout,
                                bounds: Bounds) -> [CGRect] {
        let columns = layout.usedColumns
        let gap = layout.usedGap
        let rowGap = layout.usedRowGap
        let padding = layout.usedPadding
        // A cell is as big as the biggest thing going into it, so a grid of
        // cards with one taller card keeps its rows straight. Where the grid
        // has a width of its own the columns share it instead, which is what
        // makes a grid on a screen a grid rather than a huddle in the corner.
        let cellWidth = room(bounds.width, between: padding.horizontal)
            .map { max(0, ($0 - gap * CGFloat(columns - 1)) / CGFloat(columns)) }
            ?? (items.map(\.box.width).max() ?? 0)
        let cellHeight = items.map(\.box.height).max() ?? 0
        let originX = padding.left
        let originY = padding.top
        return items.enumerated().map { index, item in
            let column = index % columns
            let row = index / columns
            let cell = CGRect(x: originX + CGFloat(column) * (cellWidth + gap),
                              y: originY + CGFloat(row) * (cellHeight + rowGap),
                              width: cellWidth, height: cellHeight)
            let x = span(size: item.box.width, start: cell.minX, extent: cell.width,
                         rule: item.horizontal)
            let y = span(size: item.box.height, start: cell.minY, extent: cell.height,
                         rule: item.vertical)
            return CGRect(x: x.low, y: y.low, width: x.length, height: y.length)
        }
    }

    /// One axis the flow is not deciding: where in the space available this
    /// thing sits, and how wide it ends up.
    ///
    /// `scale` is the rule a layer nobody has touched carries, and it means
    /// "multiply by however much the container grew", which a flow never does.
    /// In a flow it reads as the start, so a fresh stack lines up on its
    /// leading edge — the answer somebody who has set nothing expects to see.
    /// Centring lands on a whole point, because a half point is the thing
    /// typed geometry exists to avoid.
    private static func span(size: CGFloat, start: CGFloat, extent: CGFloat,
                             rule: PlacementSpan) -> (low: CGFloat, length: CGFloat) {
        switch rule {
        case .scale, .leading: (start, size)
        case .center: ((start + (extent - size) / 2).rounded(), size)
        case .trailing: (start + extent - size, size)
        case .stretch: (start, extent)
        }
    }

    // MARK: - The order things flow in

    /// The order these boxes read in on screen: along the flow for a stack,
    /// row by row for a grid. Ties keep the order they were handed in, so
    /// nothing shuffles for no reason.
    static func flowOrder(_ boxes: [CGRect], layout: GroupLayout) -> [Int] {
        guard layout.kind == .stack else { return rows(of: boxes).flatMap { $0 } }
        let horizontal = layout.direction.isHorizontal
        return boxes.indices.sorted { lhs, rhs in
            let a = horizontal ? boxes[lhs].minX : boxes[lhs].minY
            let b = horizontal ? boxes[rhs].minX : boxes[rhs].minY
            return a == b ? lhs < rhs : a < b
        }
    }

    /// These boxes clustered into the rows they visually make, each row left to
    /// right. A new row starts when a box drops more than half the tallest
    /// thing below the row being read, which is the same call an eye makes.
    static func rows(of boxes: [CGRect]) -> [[Int]] {
        guard !boxes.isEmpty else { return [] }
        let tolerance = max(1, (boxes.map(\.height).max() ?? 0) / 2)
        let byTop = boxes.indices.sorted {
            boxes[$0].minY == boxes[$1].minY ? $0 < $1 : boxes[$0].minY < boxes[$1].minY
        }
        var rows: [[Int]] = []
        var top = boxes[byTop[0]].minY
        var row: [Int] = []
        for index in byTop {
            if !row.isEmpty, boxes[index].minY - top >= tolerance {
                rows.append(row)
                row = []
                top = boxes[index].minY
            }
            row.append(index)
        }
        rows.append(row)
        return rows.map { $0.sorted { boxes[$0].minX == boxes[$1].minX
            ? $0 < $1 : boxes[$0].minX < boxes[$1].minX } }
    }
}
