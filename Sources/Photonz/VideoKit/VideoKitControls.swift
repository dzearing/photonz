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
}
