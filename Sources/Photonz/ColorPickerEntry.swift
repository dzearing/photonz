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
    /// What to open on: a flat color, or the gradient already in the slot.
    let paint: Paint
    /// What this color paints, in the row's own words: "Fill", "Shadow".
    let name: String
    /// The layer slot, when the color is one, so a saved color knows what it
    /// was saved for.
    var slot: ColorSlot?
    /// Whether the thing being painted can keep a transparency.
    var supportsOpacity: Bool = false
    /// Whether the slot can hold a gradient. Off by default, so a row that has
    /// never had one to offer is exactly what it was.
    var supportsGradient: Bool = false
    /// Drops the outer padding when this sits inside another popover.
    var embedded: Bool = false
    var onClose: (() -> Void)?
    /// What to paint on every frame of a drag, so the picture follows the pull
    /// instead of appearing when you let go. Nothing here is recorded — the
    /// gesture is one undo step, written by `onCommit` on release. A row with
    /// no live path leaves this out and the colour lands on release, as before.
    var onPreview: ((Paint) -> Void)?
    let onCommit: (Paint) -> Void

    /// The flat-color way in, which is every row that only ever holds one.
    init(editorState: EditorState, hex: String, name: String, slot: ColorSlot? = nil,
         supportsOpacity: Bool = false, embedded: Bool = false,
         onClose: (() -> Void)? = nil, onPreview: ((String) -> Void)? = nil,
         onCommit: @escaping (String) -> Void) {
        self.init(editorState: editorState, paint: Paint(hex: hex), name: name, slot: slot,
                  supportsOpacity: supportsOpacity, supportsGradient: false,
                  embedded: embedded, onClose: onClose,
                  onPreview: onPreview.map { live in { live($0.hex) } },
                  onCommit: { onCommit($0.hex) })
    }

    /// The way in for a slot that can hold a gradient.
    init(editorState: EditorState, paint: Paint, name: String, slot: ColorSlot? = nil,
         supportsOpacity: Bool = false, supportsGradient: Bool = false,
         embedded: Bool = false, onClose: (() -> Void)? = nil,
         onPreview: ((Paint) -> Void)? = nil,
         onCommit: @escaping (Paint) -> Void) {
        self.editorState = editorState
        self.paint = paint
        self.name = name
        self.slot = slot
        self.supportsOpacity = supportsOpacity
        self.supportsGradient = supportsGradient
        self.embedded = embedded
        self.onClose = onClose
        self.onPreview = onPreview
        self.onCommit = onCommit
    }

    var body: some View {
        if editorState.designedColorPickerEnabled {
            DesignedColorPicker(editorState: editorState,
                                initialPaint: paint,
                                name: name,
                                slot: slot,
                                supportsOpacity: supportsOpacity,
                                supportsGradient: supportsGradient,
                                embedded: embedded,
                                onClose: embedded ? nil : onClose,
                                onPreview: onPreview,
                                onCommit: onCommit)
        } else {
            // The picker that shipped before the designed one knows nothing
            // about ramps, so it hands back the flat color it always did.
            ColorPickerPopover(initialHex: paint.hex,
                               recents: editorState.recentColors.colors,
                               embedded: embedded,
                               onCommit: { onCommit(Paint(hex: $0)) })
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
    /// What to paint on every frame of a drag inside the picker this opens.
    /// Left out where there is nothing to paint live.
    var onPreview: ((String) -> Void)?
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
                // Every well in the panel is called Color; what it paints is
                // the row it sits on, so a walk says `press "Color" in
                // "Shadow"`. The system picker below is not marked, because
                // its panel belongs to macOS and a walk cannot drive it.
                .playtestControl("Color", detail: name,
                                 payload: { ColorDrag.itemProvider(paint: Paint(hex: hex),
                                                                   source: key) })
                // A colour well on a Mac has always been something you can
                // pull a colour off and drop a colour onto, so every row that
                // goes through here gets it at once: a shadow's colour, a
                // collage backdrop, the measure chip. None of them can hold a
                // ramp, so a gradient dropped here lands as its flat colour
                // and the swatch says so before it does.
                .colorSwatchDrag(key: key, part: name,
                                 paint: { Paint(hex: hex) },
                                 onDrop: { landing in onCommit(landing.paint.hex) })
                .popover(isPresented: editorState.colorWellBinding(key), arrowEdge: .top) {
                    ColorPickerContent(editorState: editorState,
                                       hex: hex,
                                       name: name,
                                       slot: slot,
                                       supportsOpacity: supportsOpacity,
                                       onClose: { editorState.openColorWell = nil },
                                       onPreview: onPreview,
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
