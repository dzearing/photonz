import SwiftUI

// MARK: - The key diamond

extension VideoKit {
    /// Where a property stands at the playhead, as its diamond says it.
    enum KeyState {
        /// Not animated. A dim outline, the quietest thing in the row.
        case dormant
        /// Animated, with no key on this frame. An outline in the key colour.
        case armed
        /// A key on this very frame. Filled.
        case onKey
    }

    /// The key diamond (`video.html` `.kfkey`): an 11pt diamond in a 16pt box.
    /// Three states told apart by weight alone, so the column of them down a
    /// panel reads "what is animating, and what is keyed here" at a glance.
    ///
    /// Drawing only; the caller wraps it in its own button, because what a
    /// click does (set a key, clear one, start animating) is the caller's.
    struct KeyDiamond: View {
        let state: KeyState
        var isHovering = false

        var body: some View {
            ZStack {
                Rectangle()
                    .fill(state == .onKey ? AnyShapeStyle(Palette.comp) : AnyShapeStyle(Color.clear))
                Rectangle()
                    .strokeBorder(stroke, lineWidth: 1.5)
            }
            // 11pt, not 8: the mock's 8px box is content-box with a 1.5px
            // border outside it, so what you see is 11px across.
            .frame(width: 11, height: 11)
            .rotationEffect(.degrees(45))
            .frame(width: 16, height: 16)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? AnyShapeStyle(Palette.panel2) : AnyShapeStyle(Color.clear)))
            .contentShape(Rectangle())
        }

        private var stroke: AnyShapeStyle {
            switch state {
            case .dormant: isHovering ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Palette.lineStrong)
            case .armed, .onKey: AnyShapeStyle(Palette.comp)
            }
        }
    }
}

// MARK: - A labelled row, and the dropdown that goes in one

extension VideoKit {
    /// A panel row (`inspector.css` `.irow`): a short label in a 76pt column
    /// and the control taking the rest. A label, never a sentence.
    struct FieldRow<Control: View>: View {
        let label: String
        var labelWidth: CGFloat = Metrics.rowLabelWidth
        @ViewBuilder let control: Control

        var body: some View {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.faint)
                    .lineLimit(1)
                    .frame(width: labelWidth, alignment: .leading)
                control
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// A segmented control that fills its row (`segmented.css`, `.seg.fill.sm`):
    /// a capsule track, equal columns, and one raised plate that slides to the
    /// picked segment rather than blinking between two.
    ///
    /// It exists because the system's segmented control cannot shrink below
    /// its own words: three caption styles came out 1.5pt wider than the panel
    /// has, and the dock centres a section that will not fit, so every section
    /// slid out past both of the panel's edges (2026-09-24). Here the columns
    /// share whatever width the row has, and when their words will not all
    /// fit whole the bar becomes a dropdown, which is what the mock's `.seg`
    /// asks for. Two to four short options; more than that is a dropdown.
    struct Segmented<Value: Hashable>: View {
        let options: [(value: Value, title: String)]
        let selection: Value?
        let pick: (Value) -> Void

        @Namespace private var plate

        var body: some View {
            // Every label whole on one row, or a dropdown: the mock's rule for
            // `.seg` is that a bar whose words do not fit is the wrong control
            // for that space. A narrowed dock gets the dropdown.
            ViewThatFits(in: .horizontal) {
                bar
                Dropdown(label: options.first { $0.value == selection }?.title ?? "",
                         value: options.first { $0.value == selection }?.title ?? "") {
                    ForEach(options, id: \.value) { option in
                        Toggle(option.title, isOn: Binding(get: { option.value == selection },
                                                           set: { _ in pick(option.value) }))
                    }
                }
            }
        }

        private var bar: some View {
            SegmentColumns(spacing: 2) {
                ForEach(options, id: \.value) { option in
                    let isOn = option.value == selection
                    Button {
                        pick(option.value)
                    } label: {
                        Text(option.title)
                            .font(.system(size: 11, weight: isOn ? .semibold : .medium))
                            .foregroundStyle(isOn ? Palette.ink : Palette.dim)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            // 6 where the mock's `.seg.sm` says 8, so Bottom,
                            // Middle and Top fit whole beside a row label at
                            // the dock's default width.
                            .padding(.horizontal, 6)
                            .frame(maxHeight: .infinity)
                            .background {
                                if isOn {
                                    Capsule()
                                        .fill(Palette.raised)
                                        .overlay(Capsule().strokeBorder(Palette.edgeLo))
                                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                                        .matchedGeometryEffect(id: "plate", in: plate)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .kitControl(option.title, detail: isOn ? "on" : "off")
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(2)
            .frame(height: Metrics.controlSmall)
            .frame(minWidth: 0, maxWidth: .infinity)
            .background(Capsule().fill(Palette.glassThin))
            .overlay(Capsule().strokeBorder(Palette.edgeLo))
            .animation(.spring(duration: 0.24), value: selection)
        }
    }

    /// The columns of a `Segmented`: each segment its own width, and what the
    /// row has over is shared out equally, so the plate is never a sliver
    /// beside a wide neighbour. Short of room, every segment gives up the same
    /// share of its width and its label is cut short, so no one word is
    /// sacrificed for the others while there is room for all of them.
    struct SegmentColumns: Layout {
        var spacing: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let natural = widths(subviews)
            let gaps = spacing * CGFloat(max(0, subviews.count - 1))
            let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            let width = proposal.width ?? (natural.reduce(0, +) + gaps)
            return CGSize(width: width, height: proposal.height ?? height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let natural = widths(subviews)
            guard !natural.isEmpty else { return }
            let gaps = spacing * CGFloat(natural.count - 1)
            let room = max(0, bounds.width - gaps)
            let total = natural.reduce(0, +)
            let sized: [CGFloat] = total <= room
                ? natural.map { $0 + (room - total) / CGFloat(natural.count) }
                : natural.map { total > 0 ? $0 * room / total : room / CGFloat(natural.count) }
            var x = bounds.minX
            for (index, subview) in subviews.enumerated() {
                subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                              proposal: ProposedViewSize(width: sized[index], height: bounds.height))
                x += sized[index] + spacing
            }
        }

        private func widths(_ subviews: Subviews) -> [CGFloat] {
            subviews.map { $0.sizeThatFits(.unspecified).width }
        }
    }

    /// A value you read rather than set (`.field .v`): the mock's filled box
    /// with the value in it, the same height as a small dropdown so a column
    /// of rows mixing the two lines up.
    struct ValueFace: View {
        let value: String
        var tint: AnyShapeStyle?

        var body: some View {
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(tint ?? AnyShapeStyle(Palette.ink))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .frame(height: Metrics.controlSmall)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.panel))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line))
        }
    }

    /// The face of a dropdown (`.select`): the value, an optional swatch in
    /// front of it, a chevron at the end, on a raised panel-coloured button.
    /// `DropdownRow` puts it on a menu; this is split out so the same face can
    /// be drawn anywhere a menu cannot be (a snapshot, a disabled row).
    struct SelectFace: View {
        enum Size { case small, regular }

        let value: String
        var swatch: AnyShapeStyle?
        var size: Size = .regular
        /// A component's dropdown wears the component colour on its edge.
        var isComponent = false

        @State private var isHovering = false

        var body: some View {
            let radius: CGFloat = size == .small ? 6 : 8
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    if let swatch {
                        RoundedRectangle(cornerRadius: 4).fill(swatch).frame(width: 14, height: 14)
                    }
                    Text(value)
                        .font(.system(size: size == .small ? 11 : 11.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, size == .small ? 8 : 10)
            .frame(height: size == .small ? Metrics.controlSmall : Metrics.control)
            .background(RoundedRectangle(cornerRadius: radius).fill(Palette.panel))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .strokeBorder(borderStyle))
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .kitHover(value) { isHovering = $0 }
        }

        private var borderStyle: AnyShapeStyle {
            if isHovering { return AnyShapeStyle(Palette.accent.opacity(0.45)) }
            return isComponent ? AnyShapeStyle(Palette.compLine) : AnyShapeStyle(Palette.line)
        }
    }

    /// A labelled dropdown: `FieldRow` with a `SelectFace` that opens a menu.
    /// A list of more than three exclusive choices is one of these, never a
    /// column of radio buttons.
    struct DropdownRow<Items: View>: View {
        let label: String
        let value: String
        var swatch: AnyShapeStyle?
        var size: SelectFace.Size = .small
        @ViewBuilder let items: Items

        var body: some View {
            FieldRow(label: label) {
                Dropdown(label: label, value: value, swatch: swatch, size: size) { items }
            }
        }
    }

    /// The dropdown on its own (`.select`), for a row that already has its
    /// word, or none.
    struct Dropdown<Items: View>: View {
        /// What accessibility calls it, and so what a walk reads it back by.
        let label: String
        let value: String
        var swatch: AnyShapeStyle?
        var size: SelectFace.Size = .small
        @ViewBuilder let items: Items

        var body: some View {
            // The mock's face, with a real pop-up button laid over it to
            // take the click. A borderless menu is the one AppKit builds as
            // a real pop-up button, which a walk can open and choose from
            // like any other menu in the panel, and it cannot wear a
            // face of its own, so it wears this one.
            SelectFace(value: value, swatch: swatch, size: size)
                .overlay {
                    Menu {
                        items
                    } label: {
                        // Clear, not just faint: the pop-up draws its own
                        // title, and at 1% opacity it still showed as a
                        // ghost of the value beside the face's own
                        // (2026-09-24). A walk reads the title, so it stays.
                        Text(value).foregroundStyle(Color.clear)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(0.011)
                    .accessibilityLabel(label)
                    .accessibilityValue(value)
                }
        }
    }
}
