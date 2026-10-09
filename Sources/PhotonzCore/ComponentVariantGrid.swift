import CoreGraphics
import Foundation

/// A component asking two variant questions, laid out the way the variants
/// mock draws its sheet (`docs/design/mocks/pages/ui-variants.html`,
/// `.pmatrix`): one row per answer to the first question, one column per
/// answer to the rest, and the answers printed along the edges.
///
/// The drawings are ordinary drawings on the Edit Original page, so the grid is
/// only a place to put them: Edit Original lays them out in it when it opens,
/// and the names along the edges are read back off where the drawings actually
/// stand. A drawing somebody dragged out of its cell turns the edges off
/// rather than leaving them naming the wrong drawings.
public struct ComponentVariantGrid: Hashable, Sendable {

    /// One answer along an edge, and the box of every drawing giving it.
    public struct Edge: Hashable, Sendable {
        public var name: String
        public var box: CGRect

        public init(name: String, box: CGRect) {
            self.name = name
            self.box = box
        }
    }

    /// The first question's answers, top to bottom.
    public var rows: [Edge]
    /// The other questions' answers, left to right. With three questions a
    /// column is a pair of answers, "Large · Hovered".
    public var columns: [Edge]
    /// Around every drawing in the grid.
    public var bounds: CGRect

    public init(rows: [Edge], columns: [Edge], bounds: CGRect) {
        self.rows = rows
        self.columns = columns
        self.bounds = bounds
    }
}

extension PhotonzDocument {

    /// Room left of the grid for the row names and above it for the column
    /// names, in canvas points: the names are chrome, the same size at every
    /// zoom, so this is room for them at a zoom of one.
    static func variantGridLabelRoom(rows: [String]) -> CGSize {
        let longest = rows.map(\.count).max() ?? 0
        return CGSize(width: max(56, CGFloat(longest) * 7 + 24), height: 32)
    }

    /// Which row and column each drawing of a component sits in, or nil for a
    /// component asking fewer than two questions.
    private func variantGridCells(of componentID: UUID)
        -> (rows: [String], columns: [String], cells: [(ComponentVersion, row: Int, column: Int)])? {
        let properties = componentVariantProperties(of: componentID)
        guard properties.count >= 2 else { return nil }
        let rows = properties[0].options.map(\.name)
        let rest = Array(properties.dropFirst())
        var placed: [(drawing: ComponentVersion, row: Int, column: String)] = []
        var columns: [(name: String, rank: [Int])] = []
        for drawing in componentVersions(of: componentID) {
            let answers = componentVariantAnswers(of: componentID, drawing: drawing)
            guard let row = rows.firstIndex(of: drawing.option) else { continue }
            let names = rest.map { answers[$0.id] ?? "" }
            let rank = zip(rest, names).map { property, name in
                property.options.firstIndex { $0.name == name } ?? property.options.count
            }
            let name = names.joined(separator: ComponentNaming.answerSeparator)
            if !columns.contains(where: { $0.name == name }) { columns.append((name, rank)) }
            placed.append((drawing, row, name))
        }
        // Columns run in the order each question gives its answers, the first
        // of the rest counting most: Small, Medium, Large.
        columns.sort { $0.rank.lexicographicallyPrecedes($1.rank) }
        let order = columns.map(\.name)
        let cells = placed.map { ($0.drawing, row: $0.row, column: order.firstIndex(of: $0.column) ?? 0) }
        return (rows, order, cells)
    }

    /// The grid a component's drawings stand in, read off where they actually
    /// are, or nil when there is no grid to name: the component asks fewer
    /// than two questions, a drawing is not on this page, or a drawing has
    /// been moved out of line so that two rows or two columns overlap.
    public func componentVariantGrid(of componentID: UUID) -> ComponentVariantGrid? {
        guard let layout = variantGridCells(of: componentID) else { return nil }
        var rowBoxes = [CGRect?](repeating: nil, count: layout.rows.count)
        var columnBoxes = [CGRect?](repeating: nil, count: layout.columns.count)
        var all: CGRect?
        for (drawing, row, column) in layout.cells {
            guard layers.contains(where: { $0.id == drawing.layerID }),
                  let box = canvasBounds(of: drawing.layerID) else { return nil }
            rowBoxes[row] = rowBoxes[row]?.union(box) ?? box
            columnBoxes[column] = columnBoxes[column]?.union(box) ?? box
            all = all?.union(box) ?? box
        }
        guard let all else { return nil }
        let rows = zip(layout.rows, rowBoxes).compactMap { name, box in
            box.map { ComponentVariantGrid.Edge(name: name, box: $0) }
        }
        let columns = zip(layout.columns, columnBoxes).compactMap { name, box in
            box.map { ComponentVariantGrid.Edge(name: name, box: $0) }
        }
        func apart(_ spans: [(CGFloat, CGFloat)]) -> Bool {
            let sorted = spans.sorted { $0.0 < $1.0 }
            return zip(sorted, sorted.dropFirst()).allSatisfy { $0.1 <= $1.0 }
        }
        guard apart(rows.map { ($0.box.minY, $0.box.maxY) }),
              apart(columns.map { ($0.box.minX, $0.box.maxX) }) else { return nil }
        return ComponentVariantGrid(rows: rows, columns: columns, bounds: all)
    }

    /// Puts a component's drawings into the grid: a row per answer to its
    /// first question, a column per answer to the rest, each drawing centred
    /// in its cell, the grid's top left at `origin` (where the grid already
    /// starts when nil). Drawings answering the same combination share a cell,
    /// side by side. The page grows to hold it. Answers false, moving nothing,
    /// when the component asks fewer than two questions or a drawing of it is
    /// not loose on this page.
    @discardableResult
    public mutating func layOutComponentVariantGrid(componentID: UUID,
                                                    origin: CGPoint? = nil) -> Bool {
        guard let layout = variantGridCells(of: componentID) else { return false }
        let gap = Self.editingSpaceGap
        var boxes: [UUID: CGRect] = [:]
        for (drawing, _, _) in layout.cells {
            guard layers.contains(where: { $0.id == drawing.layerID }),
                  let box = canvasBounds(of: drawing.layerID) else { return false }
            boxes[drawing.layerID] = box
        }
        guard let first = boxes.values.first else { return false }
        let start = origin ?? boxes.values.dropFirst().reduce(first) { $0.union($1) }.origin

        // What each cell holds, and how big it is.
        var held = [[UUID]](repeating: [], count: layout.rows.count * layout.columns.count)
        for (drawing, row, column) in layout.cells {
            held[row * layout.columns.count + column].append(drawing.layerID)
        }
        func size(_ cell: [UUID]) -> CGSize {
            let parts = cell.compactMap { boxes[$0] }
            return CGSize(width: parts.reduce(0) { $0 + $1.width } + gap * CGFloat(max(parts.count - 1, 0)),
                          height: parts.map(\.height).max() ?? 0)
        }
        var widths = [CGFloat](repeating: 0, count: layout.columns.count)
        var heights = [CGFloat](repeating: 0, count: layout.rows.count)
        for row in layout.rows.indices {
            for column in layout.columns.indices {
                let cell = size(held[row * layout.columns.count + column])
                widths[column] = max(widths[column], cell.width)
                heights[row] = max(heights[row], cell.height)
            }
        }

        var top = start.y
        var far = CGPoint(x: start.x, y: start.y)
        for row in layout.rows.indices {
            var left = start.x
            for column in layout.columns.indices {
                let cell = held[row * layout.columns.count + column]
                let room = size(cell)
                var x = left + ((widths[column] - room.width) / 2).rounded()
                for id in cell {
                    guard let box = boxes[id] else { continue }
                    let y = top + ((heights[row] - box.height) / 2).rounded()
                    let dx = x - box.minX
                    let dy = y - box.minY
                    updateLayer(id: id) { $0.frame.origin = CGPoint(x: $0.frame.origin.x + dx,
                                                                    y: $0.frame.origin.y + dy) }
                    x += box.width + gap
                }
                left += widths[column] + gap
            }
            far.x = max(far.x, left - gap)
            top += heights[row] + gap
        }
        far.y = top - gap
        let margin = Self.editingSpaceMargin
        canvasSize = CGSize(width: max(canvasSize.width, (far.x + margin).rounded(.up)),
                            height: max(canvasSize.height, (far.y + margin).rounded(.up)))
        return true
    }

    /// The same, at the top left of an Edit Original page, leaving the margin
    /// and the room the names along the edges need. Used when the page opens
    /// and after a drawing is added on it, so the grid stays a grid.
    @discardableResult
    public mutating func layOutComponentVariantGridOnPage(componentID: UUID) -> Bool {
        let rows = componentVariantProperties(of: componentID).first?.options.map(\.name) ?? []
        let labels = Self.variantGridLabelRoom(rows: rows)
        let margin = Self.editingSpaceMargin
        return layOutComponentVariantGrid(componentID: componentID,
                                          origin: CGPoint(x: margin + labels.width,
                                                          y: margin + labels.height))
    }
}
