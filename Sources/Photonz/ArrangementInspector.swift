import PhotonzCore
import SwiftUI

/// A group that arranges its own contents (Next, `next-auto-layout`).
///
/// Three words at the top of the Layout section — Free, Stack, Grid — and then
/// the two or three numbers that shape whichever one is picked. Free is what
/// every group has always been: things stay where you put them. Stack lays
/// them along one axis with an even gap. Grid fills rows of equal cells.
///
/// The mock (`ui-autolayout`) draws eight controls here, including a
/// distribution row and a per-child hug/fill/fixed row. Both are cut on
/// purpose. Three of distribution's four options only mean anything in a
/// container BIGGER than its contents, and a plain group is exactly as big as
/// its contents. Per-child hug/fill/fixed would be a second control saying what
/// the Horizontal and Vertical rows right below already say, so the stack
/// reuses those instead: the flow owns the axis it runs along, and the
/// placement rows own the other one.
///
/// Every number is typed, never dragged for, because "12 points between the
/// rows" is the thing being built to.
struct ArrangementInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer

    private var current: Layer { editorState.document?.layer(id: layer.id) ?? layer }
    private var layout: GroupLayout? { current.group?.layout }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Arrangement") {
                Picker("", selection: Binding(get: { layout?.kind },
                                              set: { editorState.setArrangement(id: layer.id,
                                                                                kind: $0) })) {
                    Text("Free").tag(GroupLayoutKind?.none)
                    ForEach(GroupLayoutKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(GroupLayoutKind?.some(kind))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 152)
            }
            if let layout {
                numbers(layout)
                Text(caption(layout))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func numbers(_ layout: GroupLayout) -> some View {
        if layout.kind == .stack {
            row("Direction") {
                Picker("", selection: Binding(get: { layout.direction },
                                              set: { direction in
                    editorState.updateArrangement(id: layer.id) { $0.direction = direction }
                })) {
                    ForEach(StackDirection.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 152)
            }
        } else {
            number("Columns", value: CGFloat(layout.usedColumns), minimum: 1,
                   help: "How many cells a row holds before the next one wraps.") { value in
                editorState.updateArrangement(id: layer.id) { $0.columns = Int(value.rounded()) }
            }
        }
        number(layout.kind == .grid ? "Column gap" : "Gap", value: layout.usedGap,
               help: "The space between one thing and the next.") { value in
            editorState.updateArrangement(id: layer.id) { $0.gap = value }
        }
        if layout.kind == .grid {
            number("Row gap", value: layout.usedRowGap,
                   help: "The space between one row and the next.") { value in
                editorState.updateArrangement(id: layer.id) { $0.rowGap = value }
            }
        }
        // Padding needs edges to be kept clear of, and only a screen has any:
        // a group's box IS whatever its contents add up to.
        if current.isFrame {
            number("Padding", value: layout.usedPadding,
                   help: "The space kept clear inside the screen's edges.") { value in
                editorState.updateArrangement(id: layer.id) { $0.padding = value }
            }
        }
    }

    /// What the arrangement is doing, in words, including which axis has
    /// stopped being yours to set. A live menu that changes nothing is worse
    /// than a sentence saying who owns it.
    private func caption(_ layout: GroupLayout) -> String {
        let noun = current.isFrame ? "screen" : "group"
        switch layout.kind {
        case .stack:
            let axis = layout.direction.isHorizontal ? "across" : "down"
            let owned = layout.direction.isHorizontal ? "Horizontal" : "Vertical"
            let other = layout.direction.isHorizontal ? "Vertical" : "Horizontal"
            return "Everything in this \(noun) lines up \(axis), \(Int(layout.usedGap)) apart. "
                + "\(owned) is the stack's now; \(other) below still says where each one sits, "
                + "and any one layer can answer it differently for itself."
        case .grid:
            return "Everything in this \(noun) fills \(layout.usedColumns) "
                + "\(layout.usedColumns == 1 ? "column" : "columns"), a row at a time. "
                + "Horizontal and Vertical below say where each one sits inside its cell."
        }
    }

    /// One labelled row. The label never wraps: "Arrangement" broken over two
    /// lines is the panel telling you it has run out of room, and the control
    /// beside it can give up the points instead.
    private func row(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()
            Spacer(minLength: 8)
            control()
        }
    }

    private func number(_ title: String, value: CGFloat, minimum: CGFloat = 0,
                        help: String,
                        commit: @escaping (CGFloat) -> Void) -> some View {
        row(title) {
            LayoutNumberField(title: title, value: value, minimum: minimum,
                              help: help, commit: commit)
        }
    }
}

/// One typed number on an arrangement.
///
/// The draft lives in the field until it lands, and it lands on Return and on
/// clicking away, because a number typed and then abandoned is the most common
/// way a person loses an edit. Up and down step it by 1, Shift by 10, without
/// leaving the field — the same keys the geometry fields answer to, through the
/// same `NumberFieldEntry` rules, so no two number fields in this app can drift
/// apart.
private struct LayoutNumberField: View {
    /// The row's own word, which is also what the field answers to by name:
    /// it is the placeholder and the accessibility label, so a walk can put
    /// the keyboard in "Gap" the way a person puts the pointer there.
    let title: String
    let value: CGFloat
    let minimum: CGFloat
    let help: String
    let commit: (CGFloat) -> Void

    @State private var text = ""
    @State private var isFinishing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 62)
            .focused($isFocused)
            .help(help)
            .accessibilityLabel(title)
            .onAppear { text = Self.format(value) }
            .onChange(of: value) { if !isFocused { text = Self.format(value) } }
            .onChange(of: isFocused) { _, focused in
                if focused { isFinishing = false } else if !isFinishing { land() }
            }
            .numberFieldKeys(commit: { isFinishing = true; land() },
                             revert: { isFinishing = true; text = Self.format(value) },
                             step: { direction, coarse in
                                 step(direction: direction, coarse: coarse)
                             })
    }

    /// The draft, landed. Text that is not a number snaps back to the number
    /// the group really has rather than being guessed at.
    private func land() {
        guard let typed = Double(text.trimmingCharacters(in: .whitespaces)) else {
            text = Self.format(value)
            return
        }
        let clamped = max(minimum, CGFloat(typed).rounded())
        text = Self.format(clamped)
        guard clamped != value else { return }
        commit(clamped)
    }

    private func step(direction: Int, coarse: Bool) {
        let typed = Double(text.trimmingCharacters(in: .whitespaces))
        let base = typed.map { CGFloat($0) } ?? value
        let next = max(minimum, (base + CGFloat(direction * (coarse ? 10 : 1))).rounded())
        text = Self.format(next)
        guard next != value else { return }
        commit(next)
    }

    private static func format(_ value: CGFloat) -> String { "\(Int(value.rounded()))" }
}
