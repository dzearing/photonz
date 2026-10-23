import CoreGraphics
import Foundation

// A sheet of components as a table (the user, 2026-10-20, of a sheet Ask made:
// "there is no table, no alignment, no titles, no clean design").
//
// Every component add_component made with `labels` is a row of one table, and
// each labelled add_component lays the whole table out again: a header row
// naming each state once over its column, the components' names down the left
// on one edge, every look centred in its cell on one grid, and the same gap
// between every pair of rows. A row whose states are not the header's (a
// toggle's Off and On) starts a header row of its own. Nothing here knows
// which components or states a sheet holds: the rows and their looks are
// whatever the calls made, and the columns are named by what most rows call
// them.

/// Where the table landed: the states each header row names, and the box
/// round the header rows, the names and every look.
public struct AgentSheetLayout: Hashable, Sendable {
    /// Each header row's states, top first, one per column from the left.
    public var headers: [[String]]
    /// How many columns the grid has: the most states any header row names.
    public var columns: Int
    public var frame: CGRect
}

extension AgentNewComponent {
    /// Between the bottom of one row (its looks, or the names under them) and
    /// the top of the next.
    public static let rowGap: CGFloat = 32
    /// Between the header row and the first row's looks.
    public static let headerGap: CGFloat = 16
    /// The least room across a cell leaves either side of its widest look or
    /// name, both sides together.
    public static let cellGap: CGFloat = 32
    /// The secondary label grey the state names are set in.
    static let stateNameHex = "#6E6E73"
    /// Room right of the widest row name before the first column.
    static let nameGap: CGFloat = 32
}

extension PhotonzDocument {

    /// One labelled component: its name's words and its looks, first look first.
    struct SheetRow {
        var componentID: UUID
        var name: String
        var label: UUID
        var looks: [(name: String, layer: UUID)]
        var top: CGFloat
    }

    /// Every labelled component at the top of the picture, top row first. A
    /// component is labelled when the words add_component set for its name
    /// are still beside it. Its looks are what the canvas shows of it: its
    /// versions' originals, or in the editor, which parks every original in
    /// the Library (`parkOriginals`), the copies standing in their place.
    func sheetRows() -> [SheetRow] {
        var byComponent: [UUID: [Layer]] = [:]
        var order: [UUID] = []
        for layer in layers {
            guard let componentID = layer.componentID ?? layer.instanceOf else { continue }
            if byComponent[componentID] == nil { order.append(componentID) }
            byComponent[componentID, default: []].append(layer)
        }
        var usedLabels: Set<UUID> = []
        var rows: [SheetRow] = []
        for componentID in order {
            let versions = componentVersions(of: componentID)
            func version(of layer: Layer) -> ComponentVersion? {
                if layer.isMainComponent { return versions.first { $0.layerID == layer.id } }
                return versions.first { $0.id == layer.instanceVersionID } ?? versions.first
            }
            // In the order the component lists its versions, the first look first.
            func rank(_ layer: Layer) -> Int { version(of: layer).flatMap { versions.firstIndex(of: $0) } ?? versions.count }
            let shown = (byComponent[componentID] ?? []).enumerated()
                .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
            guard let first = shown.first, let box = canvasBounds(of: first.id) else { continue }
            let name = first.name
            let label = layers.filter {
                !usedLabels.contains($0.id) && $0.name == Self.rowLabelName(name) && $0.text?.string == name
            }.min { abs($0.frame.midY - box.midY) < abs($1.frame.midY - box.midY) }
            guard let label else { continue }
            usedLabels.insert(label.id)
            var looks = shown.map { (name: version(of: $0)?.name ?? name, layer: $0.id) }
            if versions.count == 1, let said = layers.filter({
                // One look is never renamed as a version: the words naming it
                // say what it is, under it or over its column.
                guard let words = $0.text?.string else { return false }
                return $0.name == Self.captionName(row: name, look: words)
                    || ($0.name == Self.headerName(words) && abs($0.frame.midX - box.midX) <= 1
                        && $0.frame.maxY <= box.minY)
            }).max(by: { $0.frame.minY < $1.frame.minY })?.text?.string {
                looks[0].name = said
            }
            let top = shown.compactMap { canvasBounds(of: $0.id)?.minY }.min() ?? box.minY
            rows.append(SheetRow(componentID: componentID, name: name, label: label.id, looks: looks,
                                 top: min(top, label.frame.minY)))
        }
        return rows.sorted { $0.top < $1.top }
    }

    static func rowLabelName(_ row: String) -> String { "\(row) Label" }
    static func captionName(row: String, look: String) -> String { "\(row) \(look) Label" }
    static func headerName(_ state: String) -> String { "\(state) Header" }

    /// Rows that share a header row. Each row joins the first section whose
    /// states it mostly shares (at least half its own) when the two together
    /// still fit `columns`; otherwise it starts a section of its own. A
    /// section's headers are every state its rows have, in the order they
    /// mostly come, and each look goes in the column named like it. Names
    /// match whatever their case.
    struct SheetSection: Hashable {
        var headers: [String]
        /// Indexes into the rows handed in, in the order they were.
        var rows: [Int]
        /// For each of `rows`, the column each of its looks goes in.
        var cells: [[Int]]
    }

    static func sheetSections(_ rows: [[String]]) -> [SheetSection] {
        let columns = rows.map(\.count).max() ?? 0
        func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespaces).lowercased() }
        var groups: [(keys: Set<String>, rows: [Int])] = []
        for (index, row) in rows.enumerated() {
            let keys = Set(row.map(key))
            if let at = groups.firstIndex(where: { group in
                let shared = group.keys.intersection(keys).count
                return shared > 0 && shared * 2 >= keys.count && group.keys.union(keys).count <= columns
            }) {
                groups[at].keys.formUnion(keys)
                groups[at].rows.append(index)
            } else {
                groups.append((keys, [index]))
            }
        }
        return groups.map { group in
            struct Tally { var shown: String; var first: Int; var positions: [Int] = [] }
            var tallies: [String: Tally] = [:]
            var order = 0
            for index in group.rows {
                for (position, name) in rows[index].enumerated() {
                    order += 1
                    tallies[key(name), default: Tally(shown: name, first: order)].positions.append(position)
                }
            }
            func mean(_ tally: Tally) -> Double { Double(tally.positions.reduce(0, +)) / Double(tally.positions.count) }
            let headers = tallies.values.sorted { mean($0) != mean($1) ? mean($0) < mean($1) : $0.first < $1.first }
                .map(\.shown)
            let cells = group.rows.map { index -> [Int] in
                var taken: Set<Int> = []
                return rows[index].map { name in
                    let column = headers.indices.first { !taken.contains($0) && key(headers[$0]) == key(name) }
                        ?? headers.indices.first { !taken.contains($0) } ?? 0
                    taken.insert(column)
                    return column
                }
            }
            return SheetSection(headers: headers, rows: group.rows, cells: cells)
        }
    }

    /// Lays every labelled row out as one table from where the table already
    /// starts (its first header row, else its top row): rows that share
    /// their states under one header row naming each state once over its
    /// column, names on the left, every look centred in its cell on one grid
    /// as wide as the canvas allows with the left margin kept on the right,
    /// and rows `rowGap` apart. The headers are set anew each time (any
    /// state names add_component set under the looks are taken off); the row
    /// names are moved. Nil when nothing on the canvas is labelled.
    mutating func agentArrangeSheet(measure: (TextContent, CGFloat?) -> CGSize) -> AgentSheetLayout? {
        let rows = sheetRows()
        guard !rows.isEmpty else { return nil }

        // Where the table starts: its first header row if it has one, else its top.
        let oldWords = layers.filter { layer in
            guard let words = layer.text?.string else { return false }
            if layer.name == Self.headerName(words) { return true }
            return rows.contains { layer.name == Self.captionName(row: $0.name, look: words) }
        }
        let labels = rows.compactMap { self.layer(id: $0.label) }
        guard let x = labels.map(\.frame.minX).min() else { return nil }
        let top = (oldWords.filter { $0.name.hasSuffix(" Header") }.map(\.frame.minY) + rows.map(\.top)).min() ?? 0
        removeLayers(ids: Set(oldWords.map(\.id)))

        func words(_ string: String, weight: TextWeight, color: String, name: String) -> Layer {
            let content = AgentText(string: string, origin: .zero, fontSize: AgentNewComponent.labelSize,
                                    weight: weight, colorHex: color).content
            var layer = TextBuilder.layer(content: content, at: .zero, naturalSize: measure(content, nil))
            layer.name = name
            return layer
        }
        func width(_ string: String) -> CGFloat {
            measure(AgentText(string: string, origin: .zero, fontSize: AgentNewComponent.labelSize).content, nil).width
        }
        func move(_ id: UUID, to point: CGPoint) {
            guard let box = canvasBounds(of: id) else { return }
            let dx = (point.x - box.minX).rounded(), dy = (point.y - box.minY).rounded()
            updateLayer(id: id) { $0.frame.origin.x += dx; $0.frame.origin.y += dy }
        }

        let sections = Self.sheetSections(rows.map { $0.looks.map(\.name) })
        let columns = sections.map(\.headers.count).max() ?? 0
        let sizes = rows.map { $0.looks.map { canvasBounds(of: $0.layer)?.size ?? .zero } }
        let widest = (sizes.flatMap { $0.map(\.width) } + sections.flatMap(\.headers).map(width)).max() ?? 0
        let need = (widest + AgentNewComponent.cellGap).rounded(.up)
        let nameColumn = max(AgentNewComponent.labelColumn,
                             ((rows.map { width($0.name) }.max() ?? 0) + AgentNewComponent.nameGap).rounded(.up))
        let room = canvasSize.width - 2 * x - nameColumn
        let cell = room >= need * CGFloat(columns) ? (room / CGFloat(columns)).rounded(.down) : need
        func centre(_ column: Int) -> CGFloat { x + nameColumn + (CGFloat(column) + 0.5) * cell }

        var made: [Layer] = []
        let lineHeight = measure(AgentText(string: "Ag", origin: .zero, fontSize: AgentNewComponent.labelSize).content, nil).height
        var y = top
        var bottom = top
        for section in sections {
            for (column, header) in section.headers.enumerated() {
                var layer = words(header, weight: .semibold, color: AgentNewComponent.stateNameHex,
                                  name: Self.headerName(header))
                layer.frame.origin = CGPoint(x: (centre(column) - layer.frame.width / 2).rounded(), y: y)
                made.append(layer)
            }
            y += (lineHeight + AgentNewComponent.headerGap).rounded()
            for (index, cells) in zip(section.rows, section.cells) {
                let row = rows[index]
                let band = sizes[index].map(\.height).max() ?? 0
                for (at, look) in row.looks.enumerated() {
                    let size = sizes[index][at]
                    move(look.layer, to: CGPoint(x: centre(cells[at]) - size.width / 2, y: y + (band - size.height) / 2))
                }
                if let label = self.layer(id: row.label) {
                    move(row.label, to: CGPoint(x: x, y: y + (band - label.frame.height) / 2))
                }
                bottom = y + band
                y = (bottom + AgentNewComponent.rowGap).rounded()
            }
        }
        for layer in made { addLayer(layer) }
        return AgentSheetLayout(headers: sections.map(\.headers), columns: columns,
                                frame: CGRect(x: x, y: top, width: nameColumn + CGFloat(columns) * cell,
                                              height: bottom - top))
    }

    /// The words the table set for one component: its name.
    func sheetLabels(of componentID: UUID) -> [UUID] {
        sheetRows().first { $0.componentID == componentID }.map { [$0.label] } ?? []
    }
}
