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
                              container: group.isFrame
                                  ? CGRect(origin: .zero, size: layer.frame.standardized.size)
                                  : nil,
                              onAScreen: group.isFrame)
        return out
    }

    // MARK: - One group's contents

    /// The children of one stack or grid, moved to where the layout puts them.
    /// A hidden layer takes no place in the flow and is not moved: hiding a row
    /// closes the space it held, and showing it again puts it back.
    private static func placed(_ children: [Layer], layout: GroupLayout,
                               contentPlacement: LayerPlacement?,
                               container: CGRect?, onAScreen: Bool) -> [Layer] {
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
        let targets = laidOut(order.map { items[$0] }, layout: layout, container: container)
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
    static func laidOut(_ items: [Item], layout: GroupLayout, container: CGRect?) -> [CGRect] {
        guard !items.isEmpty else { return [] }
        let padding = layout.usedPadding
        let content = container?.insetBy(dx: padding, dy: padding)
        switch layout.kind {
        case .stack:
            return stacked(items, layout: layout, content: content)
        case .grid:
            return gridded(items, layout: layout, content: content)
        }
    }

    private static func stacked(_ items: [Item], layout: GroupLayout,
                                content: CGRect?) -> [CGRect] {
        let horizontal = layout.direction.isHorizontal
        // The cross axis runs from the container's inside edge across its
        // width; with no container of its own, from the group's own corner
        // across the widest thing in it, which is what a group's box IS.
        let crossStart = content.map { horizontal ? $0.minY : $0.minX } ?? 0
        let crossExtent = content.map { horizontal ? $0.height : $0.width }
            ?? (items.map { horizontal ? $0.box.height : $0.box.width }.max() ?? 0)
        var cursor = content.map { horizontal ? $0.minX : $0.minY } ?? 0
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
                                content: CGRect?) -> [CGRect] {
        let columns = layout.usedColumns
        let gap = layout.usedGap
        let rowGap = layout.usedRowGap
        // A cell is as big as the biggest thing going into it, so a grid of
        // cards with one taller card keeps its rows straight. On a screen the
        // columns share the width instead, which is what makes a grid on a
        // screen a grid rather than a huddle in the corner.
        let cellWidth = content.map { max(0, ($0.width - gap * CGFloat(columns - 1))
                                              / CGFloat(columns)) }
            ?? (items.map(\.box.width).max() ?? 0)
        let cellHeight = items.map(\.box.height).max() ?? 0
        let originX = content?.minX ?? 0
        let originY = content?.minY ?? 0
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
