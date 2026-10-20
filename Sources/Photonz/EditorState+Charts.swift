import AppKit
import Foundation
import PhotonzCore

// Animated charts (`AnimatedChart.swift`, task
// `animated-charts-you-can-drop-into-a-video`). The panel's Chart section edits
// the data of the picked chart, or of the chart a picked piece sits in: its
// rows, typed or pasted out of a spreadsheet, its unit and decimals. Each
// change is one undo step, and like a title knob it is shown on the chart held
// still with every row arrived, never by starting to play.
//
// A chart is your data first (task
// `a-chart-is-your-data-given-to-it-the-obvious-way`): a table pasted on a
// video or a CSV file let go on it lands as a chart of it, a chart just added
// asks for its numbers, and a chart can hold later sets of numbers along its
// clip (`ChartData.swift`). The table shows the set the playhead is in, so
// typing a number at 4s changes the numbers the chart shows at 4s, the way a
// value typed at a key changes that key.
extension EditorState {

    /// The chart the Chart section speaks for, and its data.
    var chartInHand: (id: UUID, spec: ChartSpec)? {
        guard Experiments.shared.animatedChartsEnabled, let id = titleInHandID,
              let spec = document?.chartSpec(layerID: id) else { return nil }
        return (id, spec)
    }

    /// One undo step that changes the data of the chart in hand.
    func editChartInHand(_ change: @escaping (inout ChartSpec) -> Void) {
        guard let id = chartInHand?.id, var probe = document, probe.editChart(layerID: id, change) else { return }
        discardDragPreview()
        perform { $0.editChart(layerID: id, change) }
        holdTitleStill(id)
    }

    // MARK: Asking for the numbers

    /// The Chart section brought into view, with the keyboard in its first
    /// value when `typing`: what a chart just added does, so the numbers are
    /// the first thing anybody is asked for.
    func askForChartData(typing: Bool) {
        guard chartInHand != nil else { return }
        chartFirstValueWaiting = typing
        chartDataRequest += 1
    }

    // MARK: Sets of numbers

    /// Where the playhead is on the chart in hand's own clock.
    private var chartClockInHand: Int? {
        guard let id = chartInHand?.id, let layer = document?.layer(id: id) else { return nil }
        return layer.motionClockMS(atDocumentTimeMS: documentTimeMS)
    }

    /// The set of the chart in hand the playhead is in: the one the table
    /// shows and every number typed into it changes.
    var chartSetInHand: Int {
        guard let spec = chartInHand?.spec, let clock = chartClockInHand else { return 0 }
        return spec.setIndex(atMS: clock)
    }

    /// Whether the playhead is at a moment of the chart in hand where a new
    /// set can go: inside its clip, and not on top of one it already has.
    var canAddChartSetAtPlayhead: Bool {
        guard let id = chartInHand?.id, let clock = chartClockInHand else { return false }
        return document?.canAddChartSet(layerID: id, atMS: clock) == true
    }

    /// A new set of numbers arriving at the playhead, holding what the chart
    /// shows there until a number is typed into it. One undo step.
    func addChartSetAtPlayhead() {
        guard canAddChartSetAtPlayhead, let id = chartInHand?.id, let clock = chartClockInHand else { return }
        pauseDocument()
        discardDragPreview()
        perform { $0.addChartSet(layerID: id, atMS: clock) }
        documentMomentChanged()
        askForChartData(typing: true)
    }

    /// The set the playhead is in taken away; the first set stays.
    func removeChartSetInHand() {
        let index = chartSetInHand
        guard index > 0, let id = chartInHand?.id, var probe = document,
              probe.removeChartSet(layerID: id, set: index) else { return }
        discardDragPreview()
        perform { $0.removeChartSet(layerID: id, set: index) }
        documentMomentChanged()
    }

    /// The playhead put where set `index` of the chart in hand has arrived.
    func showChartSet(_ index: Int) {
        guard let id = chartInHand?.id, let ms = document?.chartSetDocumentMS(layerID: id, set: index) else { return }
        pauseDocument()
        moveDocumentPlayhead(toMS: ms)
        documentMomentChanged()
    }

    // MARK: Pasting and dropping a table

    /// Rows out of the clipboard's text (a spreadsheet's copy, a CSV), in
    /// place of the chart's own. False, and nothing changed, when the
    /// clipboard holds no row with a number in it.
    @discardableResult
    func pasteChartRows() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string) else { return false }
        return replaceChartRows(with: text)
    }

    /// The table `text` holds, in place of the chart's numbers: its rows,
    /// and a later set for every further column of numbers. A header names
    /// the chart, and a unit every value was written with is its unit.
    @discardableResult
    func replaceChartRows(with text: String) -> Bool {
        guard let table = ChartTable.reading(text), !table.rows.isEmpty, let chart = chartInHand,
              let time = document?.layer(id: chart.id)?.time else { return false }
        let fresh = ChartSpec(table: table, kind: chart.spec.kind)
        let steps = Self.fitted(fresh.steps, into: time)
        editChartInHand { spec in
            spec.rows = fresh.rows
            spec.steps = steps
            if table.series.first?.name != nil { spec.title = fresh.title }
            if table.unit != nil { spec.format = fresh.format }
        }
        return true
    }

    /// Sets of a pasted table placed inside a chart's clip: where they would
    /// run past its end, spread evenly from the first change to a beat
    /// before its out.
    private static func fitted(_ steps: [ChartStep]?, into time: LayerTime) -> [ChartStep]? {
        guard var steps, let last = steps.last else { return steps }
        let latest = time.sourceInMS + time.lengthMS - 1_200
        guard last.atMS > latest else { return steps }
        let first = min(time.sourceInMS + ChartSpec.firstChangeMS, latest)
        let gap = steps.count > 1 ? (latest - first) / (steps.count - 1) : 0
        for index in steps.indices { steps[index].atMS = first + gap * index }
        return steps
    }

    /// ⌘V on a video with a table on the clipboard: a chart of it at the
    /// playhead, or, with a chart picked, that chart's numbers replaced.
    /// False where the clipboard holds no clear table (a label and a number
    /// on two rows or more, split by tabs, commas or semicolons) or this is
    /// not a video, so paste does what it always did.
    func pasteTableAsChart() -> Bool {
        guard Experiments.shared.animatedChartsEnabled, canInsertTitle,
              let text = NSPasteboard.general.string(forType: .string),
              let table = ChartTable.reading(text), table.isClearlyATable else { return false }
        if chartInHand != nil { return replaceChartRows(with: text) }
        insertChart(.bar, spec: ChartSpec(table: table))
        return chartInHand != nil
    }

    /// Whether a file let go on this window would land as a chart: a CSV or
    /// tab separated file, on a video.
    var takesChartFiles: Bool {
        Experiments.shared.animatedChartsEnabled && canInsertTitle
    }

    /// A chart of the table in the file at `url`, at the playhead. Untitled
    /// by its header, it takes the file's name. False when the file holds no
    /// table.
    @discardableResult
    func addChart(fromFile url: URL) -> Bool {
        guard takesChartFiles,
              let text = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1)),
              let table = ChartTable.reading(text), !table.rows.isEmpty else { return false }
        var spec = ChartSpec(table: table)
        if spec.title.isEmpty { spec.title = url.deletingPathExtension().lastPathComponent }
        insertChart(.bar, spec: spec)
        return chartInHand != nil
    }

    // MARK: Rows

    func addChartRow() {
        editChartInHand { spec in
            let last = spec.rows.last
            spec.rows.append(ChartRow(label: "Item \(spec.rows.count + 1)", value: last?.value ?? 1))
        }
    }

    func removeChartRow(_ index: Int) {
        editChartInHand { spec in
            guard spec.rows.indices.contains(index), spec.rows.count > spec.kind.rowLimit.lowerBound else { return }
            // Each set loses that row's number too, before the rows are
            // counted again.
            if var steps = spec.steps {
                for step in steps.indices where steps[step].values.indices.contains(index) {
                    steps[step].values.remove(at: index)
                }
                spec.steps = steps
            }
            spec.rows.remove(at: index)
        }
    }

    func setChartLabel(_ index: Int, _ label: String) {
        editChartInHand { spec in
            guard spec.rows.indices.contains(index) else { return }
            spec.rows[index].label = label
        }
    }

    /// A value typed into a row: anything that reads as a number, money and
    /// percents included, into the set the playhead is in. Words that are
    /// not a number change nothing.
    func setChartValue(_ index: Int, _ typed: String) {
        guard let value = ChartSpec.number(in: typed) else { return }
        let set = chartSetInHand
        editChartInHand { spec in
            guard spec.rows.indices.contains(index) else { return }
            guard set > 0 else {
                spec.rows[index].value = value
                return
            }
            guard var steps = spec.tidied.steps, steps.indices.contains(set - 1),
                  steps[set - 1].values.indices.contains(index) else { return }
            steps[set - 1].values[index] = value
            spec.steps = steps
        }
    }

    /// The numbers the table shows: those of the set the playhead is in.
    var chartValuesInHand: [Double] {
        chartInHand.map { $0.spec.values(ofSet: chartSetInHand) } ?? []
    }

    /// The colour each row is drawn in, for its swatch.
    var chartRowColoursInHand: [String] {
        guard let id = chartInHand?.id else { return [] }
        return document?.chartRowColours(layerID: id) ?? []
    }

    /// A row's own colour, or nil to wear the theme's again.
    func setChartColour(_ index: Int, _ hex: String?) {
        editChartInHand { spec in
            guard spec.rows.indices.contains(index) else { return }
            spec.rows[index].colorHex = hex
        }
    }

    func setChartKind(_ kind: ChartKind) {
        editChartInHand { $0.kind = kind }
    }

    func setChartUnit(_ unit: ChartNumberFormat.Unit) {
        editChartInHand { spec in
            spec.format = ChartNumberFormat(unit: unit, decimals: spec.format.decimals)
        }
    }

    func setChartDecimals(_ decimals: Int) {
        editChartInHand { spec in
            spec.format = ChartNumberFormat(prefix: spec.format.prefix, suffix: spec.format.suffix,
                                            decimals: decimals)
        }
    }

    /// A big number's change beside it ("+18%"), or none when emptied.
    func setChartDelta(_ delta: String) {
        let trimmed = delta.trimmingCharacters(in: .whitespaces)
        editChartInHand { $0.delta = trimmed.isEmpty ? nil : trimmed }
    }
}
