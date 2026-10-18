import AppKit
import Foundation
import PhotonzCore

// Animated charts (`AnimatedChart.swift`, task
// `animated-charts-you-can-drop-into-a-video`). The panel's Chart section edits
// the data of the picked chart, or of the chart a picked piece sits in: its
// rows, typed or pasted out of a spreadsheet, its unit and decimals. Each
// change is one undo step, and like a title knob it is shown on the chart held
// still with every row arrived, never by starting to play.
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

    /// Rows out of the clipboard's text (a spreadsheet's copy, a CSV), in
    /// place of the chart's own. False, and nothing changed, when the
    /// clipboard holds no row with a number in it.
    @discardableResult
    func pasteChartRows() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string) else { return false }
        return replaceChartRows(with: text)
    }

    /// The rows `text` holds, in place of the chart's own.
    @discardableResult
    func replaceChartRows(with text: String) -> Bool {
        let rows = ChartSpec.rows(pasted: text)
        guard !rows.isEmpty, chartInHand != nil else { return false }
        editChartInHand { $0.rows = rows }
        return true
    }

    func addChartRow() {
        editChartInHand { spec in
            let last = spec.rows.last
            spec.rows.append(ChartRow(label: "Item \(spec.rows.count + 1)", value: last?.value ?? 1))
        }
    }

    func removeChartRow(_ index: Int) {
        editChartInHand { spec in
            guard spec.rows.indices.contains(index), spec.rows.count > spec.kind.rowLimit.lowerBound else { return }
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
    /// percents included. Words that are not a number change nothing.
    func setChartValue(_ index: Int, _ typed: String) {
        guard let value = ChartSpec.number(in: typed) else { return }
        editChartInHand { spec in
            guard spec.rows.indices.contains(index) else { return }
            spec.rows[index].value = value
        }
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
