import AppKit
import PhotonzCore
import SwiftUI

/// Which color row has its name field open. One field at a time, and the app
/// rather than the row holds it, so moving the selection closes it.
struct ColorStyleNamingRequest: Hashable {
    let layerID: UUID
    let slot: ColorSlot
}

// MARK: - The styles button that sits beside a color (Next, `next-styles`)

/// What every color row in the inspector grows when styles are on
/// (`docs/design/ui-building.md`, step D8): a small button that saves this
/// color under a name, or points the row at a name you already have.
///
/// Two states, and the row reads differently in each:
///
/// - **A color of its own.** The row keeps its color well and this button is a
///   swatch outline: "Save as Style" makes one, and any style already on the
///   shelf can be picked straight from the menu.
/// - **Wearing a style.** The well is replaced by the style's NAME, because a
///   color that belongs to a style is not a color you edit here: you change the
///   style, on the shelf, and everything wearing it follows. "Unlink" is in the
///   menu and says what it does, so the way back to a one-off color is one
///   click and never a surprise.
///
/// The mock hangs this off a Fill section of its own; the app already has a
/// Fill row inside Annotation, a Color row inside Text and a Background row
/// inside Frame, so the control goes on those rather than a fourth place to
/// look for a color.
struct ColorStyleControl: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let slot: ColorSlot

    private var style: ColorStyle? { editorState.colorStyle(layerID: layerID, slot: slot) }
    private var styles: [ColorStyle] { editorState.colorStyles }
    /// A slot with nothing in it (a box with no fill, a frame you see through)
    /// has no color to save and nothing to paint.
    private var hasColor: Bool {
        editorState.document?.layer(id: layerID)?.colorHex(for: slot) != nil
    }

    var body: some View {
        if Experiments.shared.colorStylesEnabled {
            Menu {
                if let style {
                    Section("Using \(style.name)") {
                        Button("Edit \(style.name) in the Library") {
                            editorState.selectLibraryItem(style.id.uuidString)
                        }
                        Button("Unlink") {
                            editorState.unlinkColorStyle(layerID: layerID, slot: slot)
                        }
                    }
                } else if hasColor {
                    Button("Save as Style") {
                        editorState.beginNamingColorStyle(layerID: layerID, slot: slot)
                    }
                }
                if !styles.isEmpty {
                    Section("Use a style") {
                        ForEach(styles) { option in
                            Button {
                                editorState.useColorStyle(layerID: layerID, slot: slot,
                                                          styleID: option.id)
                            } label: {
                                Label {
                                    Text(option.name)
                                } icon: {
                                    Image(systemName: option.id == style?.id
                                          ? "checkmark.circle.fill" : "circle.fill")
                                }
                            }
                        }
                    }
                }
            } label: {
                label
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(style.map { "This \(slot.title.lowercased()) uses the style \($0.name)" }
                  ?? "Save this \(slot.title.lowercased()) as a named style, or use one you already saved")
        }
    }

    /// Wearing a style: its NAME, with the menu's own chevron beside it so it
    /// reads as something to open rather than a stray word. Otherwise the
    /// quiet swatch glyph.
    ///
    /// A menu's label is drawn by AppKit, which keeps text and symbols and
    /// drops anything else, so the style's color is drawn by the ROW next
    /// door rather than in here (a swatch put in this label came out blank).
    @ViewBuilder private var label: some View {
        if let style {
            Text(style.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Image(systemName: "swatchpalette")
        }
    }
}

/// A color row's two halves: the well you edit a one-off color with, and the
/// styles button, with the name field that saving opens sitting under them.
///
/// While a style is on, the well steps aside for a plain swatch and the
/// style's name: the color is still there to see, it is just not edited here.
/// One color, one place to change it, and that place is the style.
struct ColorStyleRow<Well: View>: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let slot: ColorSlot
    @ViewBuilder let well: Well

    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    private var style: ColorStyle? { editorState.colorStyle(layerID: layerID, slot: slot) }
    private var isNaming: Bool {
        editorState.colorStyleNaming == ColorStyleNamingRequest(layerID: layerID, slot: slot)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                if let style {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: style.colorHex))
                        .frame(width: 18, height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                        .help("This color comes from the style \(style.name)")
                } else {
                    well
                }
                ColorStyleControl(layerID: layerID, slot: slot)
            }
            if isNaming { namingField }
        }
        // Saving asks for the name first, IN the dock, rather than making a
        // style called something and hoping you find where to rename it. It
        // opens on a name nobody is using, with the text selected, so naming it
        // is typing and Return is enough.
        .onChange(of: isNaming, initial: true) { _, naming in
            guard naming else { return }
            draft = editorState.suggestedColorStyleName
            nameFocused = true
            DispatchQueue.main.async { NSApp.keyWindow?.firstResponder?.trySelectAllText() }
        }
    }

    private var namingField: some View {
        HStack(spacing: 6) {
            TextField("Style name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .controlSize(.small)
                .focused($nameFocused)
                .onSubmit(save)
                // Escape drops it: nothing was made, so there is nothing to
                // undo either.
                .onExitCommand { editorState.endNamingColorStyle() }
            Button("Save", action: save)
                .controlSize(.small)
                .help("Saves this color under that name")
        }
        .padding(.top, 2)
    }

    private func save() {
        editorState.saveColorStyle(layerID: layerID, slot: slot, name: draft)
    }
}

// MARK: - One tile on the Styles shelf

/// A style on the shelf: its color, its name, and how much of the document
/// leans on it. Click picks it, which opens the Style section where it is
/// renamed, recolored or removed.
struct LibraryStyleTile: View {
    @Environment(EditorState.self) private var editorState
    let entry: LibraryEntry
    let style: ColorStyle

    private var isSelected: Bool { editorState.selectedLibraryItemID == entry.id }

    var body: some View {
        VStack(spacing: LibraryShelfLayout.captionSpacing) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(hex: style.colorHex))
                .frame(height: LibraryShelfLayout.thumbnailHeight)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.12)))
            Text(entry.name)
                .font(.system(size: LibraryShelfLayout.captionFontSize))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .frame(maxWidth: .infinity)
        .padding(LibraryShelfLayout.tilePadding)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { editorState.selectLibraryItem(entry.id) }
        .help("\(entry.name) • \(style.colorHex) • \(entry.detail)")
    }
}

// MARK: - The picked Styles tile's section

/// The section that opens when you pick a style off the shelf. It is where a
/// style is changed, because changing it here changes every layer wearing it,
/// and doing that from one of those layers would look like editing that layer.
struct LibraryStyleInspector: View {
    @Environment(EditorState.self) private var editorState

    @State private var draft = ""
    @State private var isPickerShown = false
    @FocusState private var nameFocused: Bool

    private var style: ColorStyle? { editorState.selectedColorStyle }

    var body: some View {
        if let style {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Name")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField("Style name", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                        .focused($nameFocused)
                        .onSubmit { commit(style) }
                        .onChange(of: nameFocused) { _, focused in if !focused { commit(style) } }
                }
                HStack(spacing: 8) {
                    Text("Color")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button { isPickerShown = true } label: { swatch(style) }
                        .buttonStyle(.plain)
                        .help("Changing this repaints every layer using this style")
                        .popover(isPresented: $isPickerShown, arrowEdge: .top) {
                            ColorPickerPopover(initialHex: style.colorHex,
                                               recents: editorState.recentColors.colors) { hex in
                                editorState.setColorStyleHex(styleID: style.id, hex: hex)
                            }
                        }
                }
                Text(standing(style))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Button("Select What Uses This") {
                        editorState.selectLayersUsingColorStyle(styleID: style.id)
                    }
                    .controlSize(.small)
                    .disabled(editorState.colorStyleUsageCount(styleID: style.id) == 0)
                    .help("Selects the layers this style paints")
                    Button("Remove") {
                        editorState.deleteColorStyle(styleID: style.id)
                    }
                    .controlSize(.small)
                    .help("Takes the style off the shelf. Every layer keeps the color it is wearing")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .onAppear { draft = style.name }
            .onChange(of: style.id) { _, _ in draft = style.name }
            .onChange(of: style.name) { _, name in if !nameFocused { draft = name } }
        }
    }

    private func swatch(_ style: ColorStyle) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(hex: style.colorHex))
            .frame(width: 18, height: 18)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.25), lineWidth: 1))
    }

    /// What the style says about itself: how much of the document an edit here
    /// would repaint, which is the one fact somebody about to change it needs.
    private func standing(_ style: ColorStyle) -> String {
        switch editorState.colorStyleUsageCount(styleID: style.id) {
        case 0: return "Nothing uses this yet. Pick it from a color row to paint with it."
        case 1: return "1 color uses this. Changing it repaints that color."
        case let count: return "\(count) colors use this. Changing it repaints them all in one step."
        }
    }

    private func commit(_ style: ColorStyle) {
        guard let name = ComponentNaming.normalized(draft) else {
            draft = style.name   // ...a blank name is refused, so put it back
            return
        }
        guard name != style.name else { return }
        editorState.renameColorStyle(styleID: style.id, to: name)
    }
}
