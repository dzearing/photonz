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
                Text(caption(layout) + (sizeSentence(layout).map { " " + $0 } ?? ""))
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
        // A screen is a box you were given; a group either takes the size its
        // contents make or holds a size of its own, which is what lets a menu
        // be 320 wide before there is a screen to build it on.
        if !current.isFrame {
            sizeRow("Width", hugs: layout.hugsWidth, measured: current.localBounds.width) { size in
                editorState.updateArrangement(id: layer.id) { $0.width = size }
            }
            sizeRow("Height", hugs: layout.hugsHeight, measured: current.localBounds.height) { size in
                editorState.updateArrangement(id: layer.id) { $0.height = size }
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
        // A group that arranges itself has edges of its own, whether it was
        // given a size or takes the one its contents make, so it can keep
        // space clear inside them the same way a screen does.
        number("Padding", value: layout.usedPadding,
               help: current.isFrame ? "The space kept clear inside the screen's edges."
                                     : "The space kept clear inside the group's edges.") { value in
            editorState.updateArrangement(id: layer.id) { $0.padding = value }
        }
    }

    /// One axis' Hug-or-Fixed row. Choosing Fixed starts from the size the
    /// group is at that moment, so nothing moves when you press it, and the
    /// number itself is typed in W or H above rather than in a second field
    /// here that would have to agree with it.
    private func sizeRow(_ title: String, hugs: Bool, measured: CGFloat,
                         commit: @escaping (CGFloat?) -> Void) -> some View {
        row(title) {
            Picker("", selection: Binding(get: { hugs },
                                          set: { commit($0 ? nil : measured.rounded()) })) {
                Text("Hug").tag(true)
                Text("Fixed").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 152)
            .help(hugs
                ? "This group is as \(title == "Width" ? "wide" : "tall") as what is inside it. Fixed holds the size it is now, and W and H above set it."
                : "This group holds the \(title.lowercased()) it was given. Type it in \(title == "Width" ? "W" : "H") above, or drag a handle.")
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

    /// What a size of its own means for what is inside it, in words. A stack
    /// told how wide it is does NOT widen its rows on its own — the Horizontal
    /// row below still owns that axis — so the caption says where that switch
    /// is rather than leaving somebody staring at a 320-wide stack of 40-wide
    /// rows wondering what they got wrong.
    private func sizeSentence(_ layout: GroupLayout) -> String? {
        guard !current.isFrame, layout.kind == .stack else { return nil }
        let flowsAcross = layout.direction.isHorizontal
        guard let across = flowsAcross ? layout.usedHeight : layout.usedWidth else { return nil }
        let word = flowsAcross ? "tall" : "wide"
        let axis = flowsAcross ? "Vertical" : "Horizontal"
        let placement = current.contentPlacementDefault
        let fills = flowsAcross ? placement.vertical == .stretch : placement.horizontal == .stretch
        let size = Int(across.rounded())
        return fills
            ? "It is \(size) \(word), and everything in it fills that."
            : "It is \(size) \(word). Set \(axis) below to Stretch and everything in it fills that."
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
