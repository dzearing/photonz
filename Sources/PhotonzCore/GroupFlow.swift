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

    /// The children of one stack or grid, moved to where the layout puts them.
    /// A hidden layer takes no place in the flow and is not moved: hiding a row
    /// closes the space it held, and showing it again puts it back.
    private static func placed(_ children: [Layer], layout: GroupLayout,
                               contentPlacement: LayerPlacement?,
                               bounds: Bounds, onAScreen: Bool) -> [Layer] {
        let taking = children.indices.filter { children[$0].isVisible }
        guard !taking.isEmpty else { return children }
        let items = taking.map { index -> Item in
            let child = children[index]
            let resolved = LayerPlacement.resolving(child: child.placement,
                                                    container: contentPlacement)
            let effective = onAScreen ? resolved.onAScreen : resolved
            return Item(box: child.localBounds,
                        horizontal: effective.horizontal.span,
                        vertical: effective.vertical.span)
        }
        let order = flowOrder(items.map(\.box), layout: layout)
        let targets = laidOut(order.map { items[$0] }, layout: layout, bounds: bounds)
        var out = children
        for (slot, position) in order.enumerated() {
            let child = children[taking[position]]
            out[taking[position]] = moved(child, to: targets[slot])
        }
        return out
    }

    /// A layer put at a box. A move is a move — the layer is shifted, not
    /// re-fitted — because a caliper's feet and an arrow's ends are remapped by
    /// a resize and there is nothing to remap when only the corner changed.
    private static func moved(_ layer: Layer, to box: CGRect) -> Layer {
        let current = layer.localBounds
        guard current != box else { return layer }
        guard current.size == box.size else { return layer.resized(to: box) }
        var out = layer
        out.frame = layer.frame.offsetBy(dx: box.minX - current.minX, dy: box.minY - current.minY)
        return out
    }

    // MARK: - The maths

    /// Where each box lands, in the order handed in.
    static func laidOut(_ items: [Item], layout: GroupLayout, bounds: Bounds) -> [CGRect] {
        guard !items.isEmpty else { return [] }
        switch layout.kind {
        case .stack:
            return stacked(items, layout: layout, bounds: bounds)
        case .grid:
            return gridded(items, layout: layout, bounds: bounds)
        }
    }

    /// The room across one axis, once the padding is taken off both edges, or
    /// nil where the group is as big as what is in it and there is no room to
    /// share out.
    private static func room(_ side: CGFloat?, padding: CGFloat) -> CGFloat? {
        side.map { max(0, $0 - padding * 2) }
    }

    private static func stacked(_ items: [Item], layout: GroupLayout,
                                bounds: Bounds) -> [CGRect] {
        let horizontal = layout.direction.isHorizontal
        let padding = layout.usedPadding
        // Everything starts one padding in from the corner the group flows
        // from, whether that corner belongs to a screen, to a stack with a size
        // of its own, or to a stack that is exactly as big as its contents.
        let crossStart = padding
        // The cross axis runs across the room inside the group's own width;
        // where it has none of its own, across the widest thing in it, which is
        // what that group's box IS.
        let crossExtent = room(horizontal ? bounds.height : bounds.width, padding: padding)
            ?? (items.map { horizontal ? $0.box.height : $0.box.width }.max() ?? 0)
        var cursor = padding
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
        let cellWidth = room(bounds.width, padding: padding)
            .map { max(0, ($0 - gap * CGFloat(columns - 1)) / CGFloat(columns)) }
            ?? (items.map(\.box.width).max() ?? 0)
        let cellHeight = items.map(\.box.height).max() ?? 0
        let originX = padding
        let originY = padding
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
