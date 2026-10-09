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
    /// Which row and column each drawing stands in, indexing `rows` and
    /// `columns`.
    public var cells: [Cell]

    /// One drawing and the cell it stands in.
    public struct Cell: Hashable, Sendable {
        public var layerID: UUID
        public var row: Int
        public var column: Int

        public init(layerID: UUID, row: Int, column: Int) {
            self.layerID = layerID
            self.row = row
            self.column = column
        }
    }

    public init(rows: [Edge], columns: [Edge], bounds: CGRect, cells: [Cell] = []) {
        self.rows = rows
        self.columns = columns
        self.bounds = bounds
        self.cells = cells
    }

    /// The cell a drawing stands in: its column across and its row down, the
    /// way the mock's `.pmcell` fills its share of the width and its row. Every
    /// column is as wide as the others (`repeat(3, 1fr)`), so a cell is the
    /// shared width centred on its column, not the width of what is in it. Nil
    /// for a drawing that is not in the grid.
    public func cellBox(of layerID: UUID) -> CGRect? {
        guard let cell = cells.first(where: { $0.layerID == layerID }),
              rows.indices.contains(cell.row), columns.indices.contains(cell.column) else { return nil }
        let across = columns[cell.column].box
        let down = rows[cell.row].box
        return CGRect(x: across.midX - columnWidth / 2, y: down.minY,
                      width: columnWidth, height: down.height)
    }

    /// Around every cell: wider than `bounds` when a column's drawings are
    /// narrower than the width the columns share. What the panel goes round,
    /// so a lit cell never pokes out of it.
    public var cellBounds: CGRect {
        cells.compactMap { cellBox(of: $0.layerID) }.reduce(bounds) { $0.union($1) }
    }

    /// The width every column shares: the room between neighbouring columns'
    /// middles less the gap between them, and never narrower than the widest
    /// drawing.
    var columnWidth: CGFloat {
        let widest = columns.map(\.box.width).max() ?? 0
        let middles = columns.map(\.box.midX)
        let spacing = zip(middles, middles.dropFirst()).map { abs($1 - $0) }.min()
        guard let spacing else { return widest }
        return max(widest, spacing - PhotonzDocument.variantGridGap)
    }

    /// The soft panel the variants mock draws round its matrix (`.pmatrix`):
    /// the column answers in a band across the top, the row answers down the
    /// left, and the drawings, all inside one rounded box. In view points,
    /// because the names in it are chrome, the same size at every zoom.
    public struct Panel: Hashable, Sendable {
        /// `--pad`, the room between the panel's edge and what it holds.
        public static let padding: CGFloat = 16
        /// `--s2`, the gap between the names and the drawings they name.
        public static let gap: CGFloat = 8
        /// `--r-md`, the panel's corner.
        public static let cornerRadius: CGFloat = 13

        /// The whole panel.
        public var frame: CGRect
        /// The band the column answers are printed in, centred over their
        /// columns.
        public var columnNameBand: CGRect
        /// Where the row answers end: they are set right against it, the way
        /// the mock right-aligns `.rv`.
        public var rowNameRight: CGFloat

        /// The panel round drawings standing in `drawings`, with the widest
        /// row answer `rowNameWidth` wide and the column answers
        /// `columnNameHeight` tall.
        public init(around drawings: CGRect, rowNameWidth: CGFloat, columnNameHeight: CGFloat) {
            let pad = Self.padding
            let gap = Self.gap
            // A cell's own padding (`.pmcell`, `--s2` by `--s1`), so the
            // names stand clear of the drawings rather than touching them.
            let cells = drawings.insetBy(dx: -gap / 2, dy: -gap)
            columnNameBand = CGRect(x: cells.minX, y: cells.minY - gap - columnNameHeight,
                                    width: cells.width, height: columnNameHeight)
            // `.rv` carries its own padding on the right, on top of the gap.
            rowNameRight = cells.minX - gap * 2
            let left = rowNameRight - rowNameWidth - pad
            let top = columnNameBand.minY - pad
            frame = CGRect(x: left, y: top,
                           width: cells.maxX + pad - left, height: cells.maxY + pad - top)
        }

        /// `.pmcell`'s corner.
        public static let litCellCornerRadius: CGFloat = 8

        /// The picked cell, lit like `.pmcell.on`: the cell with the mock's
        /// padding round it, or less when the drawings stand closer than
        /// `apart` allows, so two cells never touch however far out the grid
        /// is zoomed.
        public static func litCell(_ cell: CGRect, apart: CGFloat) -> CGRect {
            let room = min(gap, max(0, (apart - gap) / 2))
            return cell.insetBy(dx: -room, dy: -room)
        }
    }

    /// The mock's Live instance block above its matrix (`.cvblock`,
    /// `.instwrap`, `.previnst`): a stage as wide as the grid's panel holding
    /// one copy of the picked look, centred, with the component ring round it
    /// and the instance badge over it, each block under its own header
    /// (`.cv-h`). In view points, like the panel it sits over.
    public struct LiveStage: Hashable, Sendable {
        /// `.instwrap`'s `min-height`.
        public static let minHeight: CGFloat = 132
        /// `.cvblock`'s `margin-bottom`, `--s6`, between the two blocks.
        public static let blockGap: CGFloat = 32
        /// `.cv-h`'s `margin-bottom`, `--pad-sm`, between a header and its block.
        public static let headerGap: CGFloat = 12
        /// A header's line: ten point capitals.
        public static let headerHeight: CGFloat = 13
        /// `.previnst .cring`'s `inset`, the ring's distance out from the copy.
        public static let ringInset: CGFloat = 12
        /// `.previnst .cbadge`'s `top`, the badge's rise above the copy.
        public static let badgeRise: CGFloat = 32

        /// The stage itself.
        public var frame: CGRect
        /// Where the copy is drawn, centred on the stage.
        public var copy: CGRect
        /// The component ring round the copy.
        public var ring: CGRect
        /// Where the badge's top edge sits, centred over the copy.
        public var badgeTop: CGFloat
        /// The live block's header line, above the stage.
        public var header: CGRect
        /// The grid block's header line, above the grid's panel.
        public var gridHeader: CGRect

        /// The stage over a grid whose panel is `panel`, for a component whose
        /// tallest look is `tallest`, showing a look `copy` big. The stage is
        /// sized for the tallest look, so picking a smaller one never moves
        /// anything else.
        public init(above panel: CGRect, tallest: CGFloat, copy size: CGSize) {
            gridHeader = CGRect(x: panel.minX, y: panel.minY - Self.headerGap - Self.headerHeight,
                                width: panel.width, height: Self.headerHeight)
            // Room above and below the look for the badge, and a little air
            // past it, so a tall look still wears its badge inside the stage.
            let height = max(Self.minHeight, (tallest + (Self.badgeRise + Self.headerGap) * 2).rounded(.up))
            frame = CGRect(x: panel.minX, y: gridHeader.minY - Self.blockGap - height,
                           width: panel.width, height: height)
            header = CGRect(x: panel.minX, y: frame.minY - Self.headerGap - Self.headerHeight,
                            width: panel.width, height: Self.headerHeight)
            copy = CGRect(x: (frame.midX - size.width / 2).rounded(),
                          y: (frame.midY - size.height / 2).rounded(),
                          width: size.width, height: size.height)
            ring = copy.insetBy(dx: -Self.ringInset, dy: -Self.ringInset)
            badgeTop = copy.minY - Self.badgeRise
        }

        /// How far above the grid's panel the live block and both headers
        /// reach, for a component whose tallest look is `tallest`.
        public static func room(tallest: CGFloat) -> CGFloat {
            let stage = LiveStage(above: .zero, tallest: tallest, copy: .zero)
            return -stage.header.minY
        }
    }

    /// Whether the names along the edges want light ink on a panel of this
    /// colour: light on a dark panel, dark on a light one.
    public static func namesWantLightInk(onHex hex: String) -> Bool {
        (RGBA(hex: hex)?.relativeLuminance ?? 1) < 0.5
    }
}

extension PhotonzDocument {

    /// Room left of the grid for the row names and above it for the column
    /// names, in canvas points: the names are chrome, the same size at every
    /// zoom, so this is room for them at a zoom of one.
    static func variantGridLabelRoom(rows: [String]) -> CGSize {
        let longest = rows.map(\.count).max() ?? 0
        let panel = ComponentVariantGrid.Panel(around: .zero,
                                               rowNameWidth: CGFloat(longest) * 7,
                                               columnNameHeight: 12)
        return CGSize(width: -panel.frame.minX, height: -panel.frame.minY)
    }

    /// The space between two drawings in a grid: a cell's padding either
    /// side and the matrix's gap (`.pmcell`, `--s2`; `.pmatrix`, `gap`),
    /// closer than loose drawings on a page because nothing else needs the
    /// room now that the edges carry the names.
    public static let variantGridGap: CGFloat = 24

    /// Room a column's name needs across the top, in canvas points at a zoom
    /// of one: nine point capitals, a little spaced, and the gap either side,
    /// so a column of narrow drawings is never narrower than its name.
    public static func variantGridColumnNameRoom(_ name: String) -> CGFloat {
        CGFloat(name.count) * 7 + ComponentVariantGrid.Panel.gap * 2
    }

    /// What the panel round a component's grid is painted: the document's
    /// Surface, which is what the drawings were made to sit on, or white when
    /// the document keeps no Surface.
    public var componentVariantGridSurfaceHex: String {
        let surface = StarterStyle.surface
        let style = colorStyles.first { $0.id == surface.styleID }
            ?? colorStyles.first { $0.name == surface.name }
        return style?.colorHex ?? surface.colorHex
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
        // Rows and columns nobody drew in are not edges, so a cell counts
        // only the ones that are.
        func shown(_ boxes: [CGRect?]) -> [Int] {
            var index = 0
            return boxes.map { box in
                defer { if box != nil { index += 1 } }
                return index
            }
        }
        let rowIndex = shown(rowBoxes)
        let columnIndex = shown(columnBoxes)
        let cells = layout.cells.map {
            ComponentVariantGrid.Cell(layerID: $0.0.layerID, row: rowIndex[$0.row],
                                      column: columnIndex[$0.column])
        }
        return ComponentVariantGrid(rows: rows, columns: columns, bounds: all, cells: cells)
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
        let gap = Self.variantGridGap
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
        var widths = layout.columns.map { Self.variantGridColumnNameRoom($0) - gap }
        var heights = [CGFloat](repeating: 0, count: layout.rows.count)
        for row in layout.rows.indices {
            for column in layout.columns.indices {
                let cell = size(held[row * layout.columns.count + column])
                widths[column] = max(widths[column], cell.width)
                heights[row] = max(heights[row], cell.height)
            }
        }

        // Every column as wide as the widest, the way the mock's matrix
        // shares its width out (`repeat(3, 1fr)`).
        let widest = widths.max() ?? 0
        widths = widths.map { _ in widest }

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

    /// The same, at the top left of an Edit Original page, leaving the margin,
    /// the room the names along the edges need and the live copy's stage. Used when the page opens
    /// and after a drawing is added on it, so the grid stays a grid.
    @discardableResult
    public mutating func layOutComponentVariantGridOnPage(componentID: UUID) -> Bool {
        let rows = componentVariantProperties(of: componentID).first?.options.map(\.name) ?? []
        let labels = Self.variantGridLabelRoom(rows: rows)
        let margin = Self.editingSpaceMargin
        // Above the grid, the live copy of the picked look on its stage, sized
        // for the tallest look (`ComponentVariantGrid.LiveStage`).
        let tallest = componentVersions(of: componentID)
            .compactMap { canvasBounds(of: $0.layerID)?.height }.max() ?? 0
        let live = ComponentVariantGrid.LiveStage.room(tallest: tallest)
        guard layOutComponentVariantGrid(componentID: componentID,
                                         origin: CGPoint(x: margin + labels.width,
                                                         y: margin + labels.height + live)),
              let grid = componentVariantGrid(of: componentID) else { return false }
        // The page is the grid and its margin, so it opens framed on the grid
        // rather than small in the corner of a page the document's size. Only
        // as far as anything else drawn on it allows: a page never shrinks out
        // from under a drawing.
        var far = CGPoint(x: grid.bounds.maxX, y: grid.bounds.maxY)
        for layer in layers {
            guard let box = canvasBounds(of: layer.id) else { continue }
            far.x = max(far.x, box.maxX)
            far.y = max(far.y, box.maxY)
        }
        canvasSize = CGSize(width: (far.x + margin).rounded(.up),
                            height: (far.y + margin).rounded(.up))
        return true
    }
}
