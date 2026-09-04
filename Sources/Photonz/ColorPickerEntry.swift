import PhotonzCore
import SwiftUI

/// The ONE way a color picker is opened. Every color row in the app goes
/// through here, so nobody can add a tenth color row that opens something else.
///
/// With `next-color-picker` on it is the designed picker; with it off it is the
/// picker the app shipped with, unchanged. The switch lives in this one place
/// rather than at each call site, which is what makes "the same picker
/// everywhere" a fact rather than an intention.
struct ColorPickerContent: View {
    let editorState: EditorState
    /// The color to open on.
    let hex: String
    /// What this color paints, in the row's own words: "Fill", "Shadow".
    let name: String
    /// The layer slot, when the color is one, so a saved color knows what it
    /// was saved for.
    var slot: ColorSlot?
    /// Whether the thing being painted can keep a transparency.
    var supportsOpacity: Bool = false
    /// Drops the outer padding when this sits inside another popover.
    var embedded: Bool = false
    var onClose: (() -> Void)?
    let onCommit: (String) -> Void

    var body: some View {
        if editorState.designedColorPickerEnabled {
            DesignedColorPicker(editorState: editorState,
                                initialHex: hex,
                                name: name,
                                slot: slot,
                                supportsOpacity: supportsOpacity,
                                embedded: embedded,
                                onClose: embedded ? nil : onClose,
                                onCommit: onCommit)
        } else {
            ColorPickerPopover(initialHex: hex,
                               recents: editorState.recentColors.colors,
                               embedded: embedded,
                               onCommit: onCommit)
        }
    }
}

/// A color row's trigger: the swatch itself, with the picker behind it.
///
/// The design study is firm about this — "the trigger is always a swatch, never
/// a labelled button, never a color well that opens something else" — and it is
/// what replaces the system color panel on the rows that used to raise it. With
/// `next-color-picker` off those rows keep the system well they always had, so
/// the release that ships today is untouched.
struct ColorWellButton: View {
    @Environment(EditorState.self) private var editorState
    let hex: String
    /// What this paints: the picker's title and the button's tip.
    let name: String
    var slot: ColorSlot?
    var supportsOpacity: Bool = false
    var size: CGFloat = 18
    /// What this well answers to, so only one picker is ever open and a walk
    /// can open this one without a pointer. Defaults to the row's own name.
    var wellKey: String?
    let onCommit: (String) -> Void

    @State private var isHovering = false

    private var key: String { wellKey ?? name.lowercased() }

    var body: some View {
        if editorState.designedColorPickerEnabled {
            Button { editorState.openColorWell = key } label: { swatch }
                .buttonStyle(.plain)
                .onHover { isHovering = $0 }
                .help("\(name) color")
                .accessibilityLabel("\(name) color")
                .popover(isPresented: editorState.colorWellBinding(key), arrowEdge: .top) {
                    ColorPickerContent(editorState: editorState,
                                       hex: hex,
                                       name: name,
                                       slot: slot,
                                       supportsOpacity: supportsOpacity,
                                       onClose: { editorState.openColorWell = nil },
                                       onCommit: onCommit)
                }
        } else {
            ColorPicker(name, selection: Binding(
                get: { Color(hex: hex) },
                set: { if let picked = $0.hexString { onCommit(picked) } }),
                        supportsOpacity: supportsOpacity)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    private var swatch: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(hex: hex))
            // Under anything that can be see-through, so a color made
            // translucent looks translucent rather than looking paler.
            .background {
                if supportsOpacity {
                    CheckerBoard(square: 4).clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.primary.opacity(isHovering ? 0.55 : 0.25), lineWidth: 1))
    }
}
