import CoreGraphics
import Foundation

// A chart is your data, given to it the obvious way, and it moves when your
// numbers do (task `a-chart-is-your-data-given-to-it-the-obvious-way`).
//
// The user, 2026-10-19: "i find the charts totally useless because i can't
// give it data and have it animate. Having some elements that move on the
// screen is not what i expected."
//
// So the data is the way in: a table copied out of Numbers, Excel or Google
// Sheets, or a CSV file, read here into labels and number columns
// (`ChartTable`). The first number column is the chart; every column after it
// is a later SET of the same rows (`ChartStep`), so a table of 2025 and 2026
// lands as a chart that shows 2025 and then moves to 2026.
//
// **A set is a key on the chart's own clock.** It says when its numbers have
// fully arrived; the chart travels to them over `ChartSpec.changeMS` before,
// bars growing or shrinking, the line redrawn, every number counting from the
// old value to the new. The document keeps the chart's pieces drawn from the
// first set, the way it keeps a title's words as typed; a frame drawn at a
// moment is laid out again from the numbers of that moment
// (`PhotonzDocument.chartsShown`), so the motion IS the data and nothing else.

// MARK: - A table, read out of text

/// Labels and number columns read out of a spreadsheet's copy or a CSV file.
public struct ChartTable: Hashable, Sendable {
    /// One number column: its header, where the table had one, and a value
    /// for every label.
    public struct Series: Hashable, Sendable {
        public var name: String?
        public var values: [Double]
    }

    public var labels: [String]
    public var series: [Series]
    /// A row's own colour, where it had a `#RRGGBB` cell.
    public var colours: [String?]
    /// The unit every value of the first column was written with.
    public var unit: ChartNumberFormat.Unit?
    /// The most places after the point any value of the first column has.
    public var decimals: Int
    /// Whether its cells were split by tabs, commas or semicolons at all.
    public var isDelimited: Bool

    /// Clearly a table, the test a paste on a video passes before it becomes
    /// a chart rather than whatever paste did before: cells split by a tab, a
    /// comma or a semicolon, two rows or more, and a column of numbers.
    public var isClearlyATable: Bool {
        isDelimited && labels.count >= 2 && !series.isEmpty
    }

    /// The first column's rows.
    public var rows: [ChartRow] {
        guard let first = series.first else { return [] }
        return labels.indices.map { ChartRow(label: labels[$0], value: first.values[$0], colorHex: colours[$0]) }
    }

    /// The table `text` holds, or nil when no row of it has a number.
    ///
    /// A line is a row. Cells are split by tabs (a spreadsheet's copy), else by
    /// commas with quotes (a CSV), else by semicolons. The first cell of a row
    /// is its label; each later column where most rows hold a number is a
    /// column of values. A first row with no number in it (or only years over
    /// columns that are not years) is the header. A cell like `#FF9500` is the
    /// row's colour, wherever it sits.
    public static func reading(_ text: String) -> ChartTable? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return nil }
        let separator = Self.separator(lines)
        var grid = lines.map { line in
            Self.cells(line, separator).map { $0.trimmingCharacters(in: .whitespaces) }
        }
        var colours: [String?] = grid.map { row in
            row.first(where: Self.isColour).map { $0.uppercased() }
        }
        grid = grid.map { $0.filter { !Self.isColour($0) } }
        let width = grid.map(\.count).max() ?? 0

        // One column: a list of numbers, each a row with no label.
        if width <= 1 {
            var values: [Double] = []
            var kept: [String?] = []
            var raw: [String] = []
            for (index, row) in grid.enumerated() {
                guard let cell = row.first, let value = ChartSpec.number(in: cell) else { continue }
                values.append(value)
                kept.append(colours[index])
                raw.append(cell)
            }
            guard !values.isEmpty else { return nil }
            return ChartTable(labels: values.map { _ in "" }, series: [Series(name: nil, values: values)],
                              colours: kept, unit: Self.unit(raw), decimals: Self.decimals(raw),
                              isDelimited: separator != nil)
        }

        func cell(_ row: [String], _ column: Int) -> String { column < row.count ? row[column] : "" }
        func numeric(_ text: String) -> Bool { ChartSpec.number(in: text) != nil }

        // The header: a first row whose value cells hold no number, or only
        // years over columns whose own cells are not years.
        var header: [String]?
        if grid.count >= 2 {
            let first = grid[0]
            let body = grid.dropFirst()
            let numbersInFirst = (1..<width).filter { numeric(cell(first, $0)) }
            let yearsOverValues = !numbersInFirst.isEmpty && numbersInFirst.allSatisfy { column in
                Self.isYear(cell(first, column)) && !body.allSatisfy { Self.isYear(cell($0, column)) }
            }
            if numbersInFirst.isEmpty || yearsOverValues { header = first }
        }
        let body = Array(grid.dropFirst(header == nil ? 0 : 1))
        let bodyColours = Array(colours.dropFirst(header == nil ? 0 : 1))
        colours = []

        // The value columns: where at least half the rows hold a number.
        let columns = (1..<width).filter { column in
            let count = body.filter { numeric(cell($0, column)) }.count
            return count > 0 && count * 2 >= body.count
        }
        guard !columns.isEmpty else { return nil }

        var labels: [String] = []
        var values: [[Double]] = columns.map { _ in [] }
        var firstRaw: [String] = []
        for (index, row) in body.enumerated() {
            guard columns.contains(where: { numeric(cell(row, $0)) }) else { continue }
            labels.append(cell(row, 0))
            colours.append(bodyColours[index])
            for (slot, column) in columns.enumerated() {
                values[slot].append(ChartSpec.number(in: cell(row, column)) ?? 0)
            }
            firstRaw.append(cell(row, columns[0]))
        }
        guard !labels.isEmpty else { return nil }
        let series = columns.enumerated().map { slot, column -> Series in
            let name = header.map { cell($0, column) }.flatMap { $0.isEmpty ? nil : $0 }
            return Series(name: name, values: values[slot])
        }
        return ChartTable(labels: labels, series: series, colours: colours, unit: Self.unit(firstRaw),
                          decimals: Self.decimals(firstRaw), isDelimited: separator != nil)
    }

    // MARK: Reading cells

    /// What splits the cells of these lines: a tab wherever any line has one,
    /// else a comma where most lines have one outside quotes, else a
    /// semicolon, else nothing (one cell a line).
    static func separator(_ lines: [String]) -> Character? {
        if lines.contains(where: { $0.contains("\t") }) { return "\t" }
        func outsideQuotes(_ line: String, _ mark: Character) -> Bool {
            var quoted = false
            for character in line {
                if character == "\"" { quoted.toggle() } else if character == mark, !quoted { return true }
            }
            return false
        }
        let commas = lines.filter { outsideQuotes($0, ",") }.count
        if commas * 2 >= lines.count, commas > 0 { return "," }
        if lines.contains(where: { outsideQuotes($0, ";") }) { return ";" }
        return nil
    }

    /// A line's cells. Quotes hold a separator inside a cell, and two quotes
    /// in a row are one quote, the way a CSV writes them.
    static func cells(_ line: String, _ separator: Character?) -> [String] {
        guard let separator else { return [line] }
        if separator == "\t" { return line.components(separatedBy: "\t") }
        var cells: [String] = []
        var current = ""
        var quoted = false
        var characters = Array(line).makeIterator()
        var pending: Character?
        while let character = pending ?? characters.next() {
            pending = nil
            if character == "\"" {
                if quoted, let next = characters.next() {
                    if next == "\"" { current.append("\"") } else {
                        quoted = false
                        pending = next
                    }
                } else {
                    quoted.toggle()
                }
            } else if character == separator, !quoted {
                cells.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current)
        return cells
    }

    static func isColour(_ cell: String) -> Bool {
        let digits = cell.dropFirst()
        return cell.hasPrefix("#") && digits.count == 6 && digits.allSatisfy(\.isHexDigit)
    }

    static func isYear(_ cell: String) -> Bool {
        guard cell.count == 4, cell.allSatisfy(\.isNumber), let year = Int(cell) else { return false }
        return (1900...2100).contains(year)
    }

    /// The unit every one of these cells is written with, nil where they do
    /// not all agree.
    static func unit(_ cells: [String]) -> ChartNumberFormat.Unit? {
        let written = cells.filter { !$0.isEmpty }
        guard !written.isEmpty else { return nil }
        let marks: [(ChartNumberFormat.Unit, (String) -> Bool)] = [
            (.dollars, { $0.contains("$") }), (.euros, { $0.contains("€") }), (.pounds, { $0.contains("£") }),
            (.percent, { $0.hasSuffix("%") }), (.thousands, { $0.uppercased().hasSuffix("K") }),
            (.millions, { $0.uppercased().hasSuffix("M") }), (.billions, { $0.uppercased().hasSuffix("B") }),
        ]
        return marks.first { _, test in written.allSatisfy(test) }?.0
    }

    /// The most places after the point any of these cells shows, up to three.
    static func decimals(_ cells: [String]) -> Int {
        let most = cells.map { cell -> Int in
            guard let point = cell.lastIndex(of: ".") else { return 0 }
            return cell[cell.index(after: point)...].prefix(while: \.isNumber).count
        }.max() ?? 0
        return min(most, ChartNumberFormat.decimalRange.upperBound)
    }
}

// MARK: - Sets of numbers over time

/// A later set of a chart's numbers: one value for each of its rows, fully
/// arrived at `atMS` of the chart's own clock, and the title it then shows.
public struct ChartStep: Hashable, Codable, Sendable {
    public var atMS: Int
    public var values: [Double]
    public var title: String?

    public init(atMS: Int, values: [Double], title: String? = nil) {
        self.atMS = atMS
        self.values = values
        self.title = title
    }
}

extension ChartSpec {

    /// How long a chart takes to travel from one set to the next.
    public static let changeMS = 900
    /// When the first later set of a pasted table has arrived: after every
    /// bar has grown in and held a beat.
    public static let firstChangeMS = 3_600
    /// How far apart the later sets of a pasted table arrive.
    public static let changeEveryMS = 2_400
    /// The most sets a chart holds.
    public static let maxSets = 8
    /// The least time between two sets.
    public static let closestSetsMS = 200

    /// A chart of a table: its first column of numbers, titled by that
    /// column's header, every later column a set arriving after it.
    public init(table: ChartTable, kind: ChartKind = .bar) {
        let first = table.series.first
        self.init(kind: kind, title: first?.name ?? "", rows: table.rows,
                  format: ChartNumberFormat(unit: table.unit ?? .none, decimals: table.decimals))
        let later = table.series.dropFirst().prefix(Self.maxSets - 1)
        let steps = later.enumerated().map { index, series in
            ChartStep(atMS: Self.firstChangeMS + index * Self.changeEveryMS, values: series.values,
                      title: series.name)
        }
        self.steps = steps.isEmpty ? nil : steps
    }

    /// How many sets of numbers it has: its rows and each later one.
    public var setCount: Int { 1 + (steps?.count ?? 0) }

    /// How long its clip needs to be to show every set and hold the last.
    public var clipLengthMS: Int {
        max(TitleKind.chart.lengthMS, (steps?.map(\.atMS).max() ?? 0) + Self.changeEveryMS)
    }

    /// The numbers of set `index`, nought being the rows themselves.
    public func values(ofSet index: Int) -> [Double] {
        let spec = tidied
        guard index > 0, let steps = spec.steps, steps.indices.contains(index - 1) else {
            return spec.rows.map(\.value)
        }
        return steps[index - 1].values
    }

    /// The set in force at `ms` of the chart's own clock: the last one whose
    /// change has begun.
    public func setIndex(atMS ms: Int) -> Int {
        (tidied.steps ?? []).filter { $0.atMS - Self.changeMS <= ms }.count
    }

    /// The least and the most it ever shows, with nought always inside:
    /// the axis every set is drawn against, so a bar that grows really grows.
    var valueRange: (lo: Double, hi: Double) {
        if let axis { return (axis.lowerBound, axis.upperBound) }
        let all = rows.map(\.value) + (steps ?? []).flatMap(\.values)
        return (min(0, all.min() ?? 0), max(0, all.max() ?? 0))
    }

    /// This chart as it stands at `ms` of its own clock: its rows holding the
    /// numbers of that moment, part way from one set to the next during a
    /// change, and the title of the set it has reached half way through.
    /// Its sets stay on it, so it is drawn against the same axis.
    public func shown(atMS ms: Int) -> ChartSpec {
        var spec = tidied
        guard let steps = spec.steps else { return spec }
        let range = spec.valueRange
        spec.axis = range.lo...range.hi
        var values = spec.rows.map(\.value)
        var title = spec.title
        var arrived = Int.min
        for step in steps {
            let start = max(step.atMS - Self.changeMS, arrived)
            if ms >= step.atMS {
                values = step.values
                if let named = step.title { title = named }
                arrived = step.atMS
                continue
            }
            if ms > start {
                let progress = EasingCurve.easeInOut.value(at: Double(ms - start) / Double(max(1, step.atMS - start)))
                values = zip(values, step.values).map { $0 + ($1 - $0) * progress }
                if progress >= 0.5, let named = step.title { title = named }
            }
            break
        }
        for index in spec.rows.indices where index < values.count { spec.rows[index].value = values[index] }
        spec.title = title
        return spec
    }

    /// Its sets in order, each with a number for every row (a row added
    /// since takes its own first value), two never closer than
    /// `closestSetsMS`, and none at all written as nil.
    func tidiedSteps() -> [ChartStep]? {
        guard let steps, !steps.isEmpty else { return nil }
        var kept: [ChartStep] = []
        for var step in steps.sorted(by: { $0.atMS < $1.atMS }).prefix(Self.maxSets - 1) {
            if let last = kept.last, step.atMS - last.atMS < Self.closestSetsMS { continue }
            step.values = rows.indices.map { $0 < step.values.count ? step.values[$0] : rows[$0].value }
            if step.title?.isEmpty == true { step.title = nil }
            kept.append(step)
        }
        return kept.isEmpty ? nil : kept
    }
}

// MARK: - Drawn at a moment

extension ChartPen {

    /// `group` posed with the numbers of `spec`: each piece keeps everything
    /// it has (its id, its keys, its style, its count) and takes only its
    /// place, size, shape and words from the new drawing. A piece with keys
    /// that move it is moved along with them, so its in still lands on it.
    func posed(_ group: Layer, _ spec: ChartSpec) -> Layer {
        guard let background = group.children.first(where: { $0.name == "Background" }) else { return group }
        let offset = background.frame.origin
        let drawn = Dictionary(pieces(spec).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var posed = group
        posed.children = group.children.map { old in
            guard old.name != "Background", var piece = drawn[old.name] else { return old }
            piece.frame = piece.frame.offsetBy(dx: offset.x, dy: offset.y)
            var moved = old
            switch (old.content, piece.content) {
            case (.text(var was), .text(let now)):
                was.string = now.string
                moved.content = .text(was)
                moved.frame = piece.frame
            case (.path(var was), .path(let now)):
                was.anchors = now.anchors
                moved.content = .path(was)
                moved.frame = piece.frame
            default:
                // A box or a dot is drawn to its size, so it is resized
                // rather than given a bigger frame to be clipped by.
                if piece.frame != old.frame { moved = old.resized(to: piece.frame) }
            }
            let shift = CGVector(dx: piece.frame.minX - old.frame.minX, dy: piece.frame.minY - old.frame.minY)
            if shift.dx != 0 || shift.dy != 0 {
                moved.motions = old.motions?.map { $0.translatingPosition(by: shift) }
            }
            return moved
        }
        return posed
    }
}

extension LayerMotion {

    /// A move carried along by `shift`: every place it passes through, the
    /// same distance over. Anything that is not a move comes back as it was.
    func translatingPosition(by shift: CGVector) -> LayerMotion {
        guard property == .position else { return self }
        func moved(_ value: MotionValue) -> MotionValue {
            guard case .point(let point) = value else { return value }
            return .point(CGPoint(x: point.x + shift.dx, y: point.y + shift.dy))
        }
        var motion = self
        motion.from = moved(from)
        motion.to = moved(to)
        motion.stops = stops?.map { stop in
            var stop = stop
            stop.value = moved(stop.value)
            return stop
        }
        return motion
    }
}

extension PhotonzDocument {

    /// Whether any chart in it has a later set, the one thing that makes a
    /// frame lay a chart out again.
    var hasChartSets: Bool {
        func has(_ layer: Layer) -> Bool {
            guard case .group(let content) = layer.content else { return false }
            if let chart = content.titleRecipe?.chart { return chart.steps != nil }
            return content.children.contains(where: has)
        }
        return layers.contains(where: has)
    }

    /// `layer`, with every chart in it that has later sets laid out from
    /// the numbers of the moment `ms` of the document's clock is at it.
    func chartsShown(_ layer: Layer, atDocumentTimeMS ms: Int, clockMS: Int? = nil) -> Layer {
        guard case .group(var content) = layer.content else { return layer }
        let clock = layer.time != nil ? layer.motionClockMS(atDocumentTimeMS: ms) : clockMS
        if let recipe = content.titleRecipe, let chart = recipe.chart {
            guard chart.steps != nil, let clock else { return layer }
            let shown = chart.shown(atMS: clock)
            let first = chart.tidied
            guard shown.rows != first.rows || shown.title != first.title else { return layer }
            let pen = ChartPen(canvas: canvasSize, theme: recipe.theme, fonts: recipe.fonts,
                               overFootage: !recipe.showsBackground)
            return pen.posed(layer, shown)
        }
        content.children = content.children.map { chartsShown($0, atDocumentTimeMS: ms, clockMS: clock) }
        var shown = layer
        shown.content = .group(content)
        return shown
    }

    // MARK: Editing sets

    /// A new set of the chart's numbers arriving at `ms` of its own clock,
    /// holding what it shows there, so it changes nothing until somebody
    /// types a new number into it. Its index, or nil where a set is already
    /// that close, the chart holds the most it can, or `ms` is outside it.
    @discardableResult
    public mutating func addChartSet(layerID: UUID, atMS ms: Int) -> Int? {
        guard canAddChartSet(layerID: layerID, atMS: ms), let spec = chartSpec(layerID: layerID) else { return nil }
        let steps = spec.tidied.steps ?? []
        let values = spec.shown(atMS: ms).rows.map(\.value)
        guard editChart(layerID: layerID, { $0.steps = steps + [ChartStep(atMS: ms, values: values)] })
        else { return nil }
        return (chartSpec(layerID: layerID)?.steps ?? []).firstIndex { $0.atMS == ms }.map { $0 + 1 }
    }

    /// Whether a new set can arrive at `ms` of the chart's own clock: inside
    /// its clip, no closer than `closestSetsMS` to one it has, and while it
    /// holds fewer than the most it can.
    public func canAddChartSet(layerID: UUID, atMS ms: Int) -> Bool {
        guard let spec = chartSpec(layerID: layerID), let time = layer(id: layerID)?.time,
              spec.setCount < ChartSpec.maxSets else { return false }
        let start = time.sourceInMS
        guard ms > start, ms < start + time.lengthMS else { return false }
        return !(spec.tidied.steps ?? []).contains { abs($0.atMS - ms) < ChartSpec.closestSetsMS }
    }

    /// Change the numbers of set `index`, nought being the rows themselves.
    @discardableResult
    public mutating func editChart(layerID: UUID, set index: Int, _ change: (inout [Double]) -> Void) -> Bool {
        editChart(layerID: layerID) { spec in
            if index == 0 {
                var values = spec.rows.map(\.value)
                change(&values)
                for row in spec.rows.indices where row < values.count { spec.rows[row].value = values[row] }
                return
            }
            guard var steps = spec.tidiedSteps(), steps.indices.contains(index - 1) else { return }
            change(&steps[index - 1].values)
            spec.steps = steps
        }
    }

    /// Take set `index` away; the first set, being the rows, stays.
    @discardableResult
    public mutating func removeChartSet(layerID: UUID, set index: Int) -> Bool {
        editChart(layerID: layerID) { spec in
            guard index > 0, var steps = spec.tidiedSteps(), steps.indices.contains(index - 1) else { return }
            steps.remove(at: index - 1)
            spec.steps = steps.isEmpty ? nil : steps
        }
    }

    /// The moment set `index` of the chart has arrived, on the document's
    /// clock: where the playhead goes to show it. The first set's is when its
    /// rows have arrived.
    public func chartSetDocumentMS(layerID: UUID, set index: Int) -> Int? {
        guard let spec = chartSpec(layerID: layerID), let time = layer(id: layerID)?.time else { return nil }
        guard index > 0 else { return time.inMS + titleArrivalMS(layerID: layerID) }
        guard let steps = spec.tidied.steps, steps.indices.contains(index - 1) else { return nil }
        return time.inMS + steps[index - 1].atMS - time.sourceInMS
    }

    /// The colour each row of the chart is drawn in: its own, or the one the
    /// theme gives it. What its swatch in the panel shows.
    public func chartRowColours(layerID: UUID) -> [String] {
        guard let recipe = titleRecipe(layerID: layerID), let spec = recipe.chart?.tidied else { return [] }
        let pen = ChartPen(canvas: canvasSize, theme: recipe.theme, fonts: recipe.fonts, overFootage: false)
        return spec.rows.indices.map { pen.colour(spec, $0, distinct: spec.kind == .donut) }
    }
}
