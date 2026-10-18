import PhotonzCore
import SwiftUI

/// **Chart**: the data of the picked chart (`AnimatedChart.swift`, task
/// `animated-charts-you-can-drop-into-a-video`).
///
/// No mock draws this section; its rows are the panel's own controls
/// (UX-PATTERNS §4): a dropdown for the kind and the unit, a small table of
/// rows (label, value, colour) with a paste button for rows copied out of a
/// spreadsheet, and segments for the decimals. Above Title, because the data
/// is what a person came to change; the look is Title's.
struct ChartInspector: View {
    @Environment(EditorState.self) private var editorState

    static let sectionHelp = "The chart's numbers. Type them, or copy rows from a spreadsheet and press Paste."

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let chart = editorState.chartInHand {
                kind(chart.spec)
                table(chart.id, chart.spec)
                unit(chart.spec)
                decimals(chart.spec)
                if chart.spec.kind == .bigNumber { delta(chart.id, chart.spec) }
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Kind

    private func kind(_ spec: ChartSpec) -> some View {
        VideoKit.DropdownRow(
            label: "Kind", value: spec.kind.name,
            choices: .picking(ChartKind.allCases, current: spec.kind, title: \.name) { editorState.setChartKind($0) })
        .panelReadout(spec.kind.name)
        .playtestField("Chart Kind")
        .panelHelp("Bars, a line, a donut, one big number or cards side by side.")
    }

    // MARK: Data

    private func table(_ id: UUID, _ spec: ChartSpec) -> some View {
        let canRemove = spec.rows.count > spec.kind.rowLimit.lowerBound
        let canAdd = spec.rows.count < spec.kind.rowLimit.upperBound
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                PanelRowLabel(text: "Data")
                Spacer(minLength: 4)
                Button { editorState.pasteChartRows() } label: {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .panelHelp("Paste rows copied from a spreadsheet: a label and a number on each line.")
                .accessibilityLabel("Paste Rows")
                .playtestControl("Paste Rows", detail: "Chart")
                Button { editorState.addChartRow() } label: {
                    Image(systemName: "plus").font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .disabled(!canAdd)
                .panelHelp("Add a row.")
                .accessibilityLabel("Add Row")
                .playtestControl("Add Row", detail: "Chart")
            }
            .playtestField("Chart Data")
            ForEach(Array(spec.rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 4) {
                    ChartCellField(text: row.label, prompt: "Label", name: "Row \(index + 1) Label",
                                   identity: "\(id)-\(index)") { editorState.setChartLabel(index, $0) }
                    ChartCellField(text: Self.typed(row.value), prompt: "0", name: "Row \(index + 1) Value",
                                   identity: "\(id)-\(index)", alignment: .trailing) {
                        editorState.setChartValue(index, $0)
                    }
                    .frame(width: 64)
                    ColorWellButton(hex: row.colorHex ?? (editorState.titleRecipeInHand?.theme.accent ?? "#FFFFFF"),
                                    name: "Row \(index + 1)", size: 14,
                                    wellKey: "chart.row.\(index)", isNone: row.colorHex == nil,
                                    onNone: { editorState.setChartColour(index, nil) }) {
                        editorState.setChartColour(index, $0)
                    }
                    Button { editorState.removeChartRow(index) } label: {
                        Image(systemName: "minus").font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canRemove)
                    .panelHelp("Remove this row.")
                    .accessibilityLabel("Remove Row \(index + 1)")
                    .playtestControl("Remove Row", detail: "\(index + 1)")
                }
                .playtestField("Chart Row \(index + 1)")
            }
        }
    }

    /// A value as a person would type it: no unit, no thousands, only the
    /// decimals it really has.
    static func typed(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 { return String(Int64(value)) }
        return String(value)
    }

    // MARK: Format

    private func unit(_ spec: ChartSpec) -> some View {
        let value = spec.format.unit?.title ?? "Custom"
        return VideoKit.DropdownRow(
            label: "Unit", value: value,
            choices: .picking(ChartNumberFormat.Unit.allCases, current: spec.format.unit,
                              title: \.title) { editorState.setChartUnit($0) })
        .panelReadout(value)
        .playtestField("Chart Unit")
        .panelHelp("What every number is written with.")
    }

    private func decimals(_ spec: ChartSpec) -> some View {
        PanelFieldRow("Decimals") {
            SegmentedControl("Decimals", selection: spec.format.decimals,
                             options: ChartNumberFormat.decimalRange.map { .init($0, "\($0)") },
                             size: .small) { editorState.setChartDecimals($0) }
        }
        .panelReadout("\(spec.format.decimals)")
        .playtestField("Chart Decimals")
        .panelHelp("How many places after the point.")
    }

    private func delta(_ id: UUID, _ spec: ChartSpec) -> some View {
        PanelFieldRow("Change") {
            ChartCellField(text: spec.delta ?? "", prompt: "+18%", name: "Chart Change",
                           identity: "\(id)-delta") { editorState.setChartDelta($0) }
        }
        .playtestField("Chart Change")
        .panelHelp("The change shown under the number, like +18%.")
    }
}

/// One cell of the chart's table. It holds a draft while it has the keyboard:
/// Return, Tab or clicking away land it as one undo step, Escape drops it.
struct ChartCellField: View {
    let text: String
    let prompt: String
    /// Its accessibility name, which is how a walk puts the keyboard in it.
    let name: String
    /// Which row of which chart it speaks for: a new one starts a fresh draft.
    let identity: String
    var alignment: TextAlignment = .leading
    let commit: (String) -> Void

    @State private var draft = ""
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(prompt, text: $draft)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .multilineTextAlignment(alignment)
            .focused($focused)
            .accessibilityLabel(name)
            .onAppear { draft = text }
            .onChange(of: text) { _, new in if !editing { draft = new } }
            .onChange(of: identity) { _, _ in
                editing = false
                draft = text
            }
            .onSubmit {
                land()
                KeyboardHandback.toCanvas()
            }
            .onKeyPress(.escape) {
                editing = false
                draft = text
                KeyboardHandback.toCanvas()
                return .handled
            }
            .onChange(of: focused) { _, isFocused in
                if isFocused { editing = true } else if editing { land() }
            }
            .onDisappear { if editing { land() } }
    }

    private func land() {
        editing = false
        if draft != text { commit(draft) }
    }
}
