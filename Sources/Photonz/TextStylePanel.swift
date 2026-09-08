import AppKit
import PhotonzCore
import SwiftUI

// The Style row in the Text section, and the text tiles on the Library's
// Styles shelf (Next, `next-styles`). The colour half of the same idea is
// `ColorStylePanel.swift`, and everything here is deliberately the same shape
// as its opposite number there: one menu that saves a name or wears one, one
// tile on one shelf, one section behind the tile where the style is edited.

// MARK: - The styles button that sits over the type

/// What the Text section grows when styles are on: a small button that saves
/// what this text is set in under a name, or points it at a name you already
/// have.
///
/// It speaks for the WHOLE selection. One heading picked or twenty, choosing
/// Heading here re-sets every picked piece of text, in one step that one undo
/// puts back.
///
/// Three states, exactly the way a colour row reads:
///
/// - **Type of its own.** The button is a quiet glyph: "Save as Style" makes
///   one, and any style already on the shelf can be picked straight from the
///   menu.
/// - **Wearing a style.** The button says the style's NAME beside a type mark,
///   so a linked Text section and a plain one never look alike. The Font, Size
///   and Weight menus still answer — a person who opens Size wants a different
///   size — and choosing in one takes the text off the style, which the row
///   says in words before the click and one undo puts back.
/// - **Disagreeing.** Text wearing different styles, or set differently, says
///   Mixed rather than naming one of them. Picking a name still lands on all of
///   them, which is the way out.
struct TextStyleControl: View {
    @Environment(EditorState.self) private var editorState

    private var selection: TextStyleSelection { editorState.textStyleSelection }

    var body: some View {
        if editorState.textStylesEnabled, !selection.isEmpty {
            let selection = selection
            let style = editorState.boundTextStyle
            let styles = editorState.namedTextStyles
            Menu {
                if let style {
                    Section("Using \(style.name)") {
                        Button("Edit \(style.name) in the Library") {
                            // The shelf first, then the tile: picking a tile in
                            // a Library nobody has opened selects something
                            // there is nowhere to see.
                            editorState.showStylesShelf()
                            editorState.selectLibraryItem(style.id.uuidString)
                        }
                        Button(unlinkTitle(selection)) { editorState.unlinkTextStyle() }
                    }
                } else if selection.wearsAnyStyle {
                    // Several styles under one row: there is no name to print,
                    // but letting go of all of them is still one honest move.
                    Section("Using more than one style") {
                        Button(unlinkTitle(selection)) { editorState.unlinkTextStyle() }
                    }
                } else if selection.savableTreatment != nil {
                    Button(saveTitle(selection)) { editorState.beginNamingTextStyle() }
                }
                if !styles.isEmpty {
                    Section(selection.count > 1
                            ? "Saved text styles, for all \(selection.count)"
                            : "Saved text styles") {
                        ForEach(styles) { option in
                            Button {
                                editorState.useTextStyle(styleID: option.id)
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
                label(style, selection)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .panelHelp(help(selection, style))
        }
    }

    /// Wearing a style: a type mark and the style's NAME, with the menu's own
    /// chevron beside them so it reads as something to open rather than a stray
    /// word. Text that disagrees says Mixed in the same place, because that is
    /// the answer to the same question. Otherwise the quiet glyph on its own.
    @ViewBuilder private func label(_ style: TextStyle?,
                                    _ selection: TextStyleSelection) -> some View {
        if let style {
            HStack(spacing: 3) {
                Image(systemName: "textformat")
                Text(style.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else if selection.wearsAnyStyle {
            HStack(spacing: 3) {
                Image(systemName: "textformat")
                Text(TextStyleSelection.mixedText)
                    .font(.caption)
                    .foregroundStyle(MixedLook.style)
            }
        } else {
            Image(systemName: "textformat")
        }
    }

    private func unlinkTitle(_ selection: TextStyleSelection) -> String {
        selection.count > 1 ? "Unlink All \(selection.count)" : "Unlink"
    }

    private func saveTitle(_ selection: TextStyleSelection) -> String {
        selection.count > 1 ? "Save as Style for All \(selection.count)" : "Save as Style"
    }

    /// The hover tip. With one piece of text picked it is about that text; with
    /// several it has to say how many a pick here reaches.
    private func help(_ selection: TextStyleSelection, _ style: TextStyle?) -> String {
        let many = selection.count > 1
        let sentence: String
        switch (style, many) {
        case (.some(let style), false):
            sentence = "This text uses the style \(style.name)"
        case (.some(let style), true):
            sentence = "All \(selection.count) of these use the style \(style.name)"
        case (nil, false):
            sentence = "Save this text as a named style, or use one you already saved"
        case (nil, true):
            sentence = "Save what these \(selection.count) share as a named style, "
                + "or set them all to one you already saved"
        }
        guard let note = selection.note else { return sentence }
        return "\(sentence). \(note)"
    }
}

/// The whole Style row: the word Style, the menu, and the name field the menu
/// raises when you save. It sits at the TOP of the Text section, above Font,
/// because it is the shortest way to set every row under it at once and a
/// control that sets four rows below the four rows is a control nobody finds.
struct TextStyleRow: View {
    @Environment(EditorState.self) private var editorState

    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    private var isNaming: Bool { editorState.isNamingTextStyle }

    var body: some View {
        if editorState.textStylesEnabled, !editorState.textStyleSelection.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Style")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextStyleControl()
                    Spacer(minLength: 0)
                }
                // Named, so a walk reaches this menu by the word beside it
                // rather than by the glyph on it.
                .playtestField("Style")
                if isNaming { namingField }
            }
            // Saving asks for the name first, IN the dock, rather than making a
            // style called something and hoping you find where to rename it. It
            // opens on a name nobody is using, with the text selected, so naming
            // it is typing and Return is enough.
            .onChange(of: isNaming, initial: true) { _, naming in
                guard naming else { return }
                draft = editorState.suggestedTextStyleName
                nameFocused = true
                DispatchQueue.main.async { NSApp.keyWindow?.firstResponder?.trySelectAllText() }
            }
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
                // undo either. Both keys hand the keyboard back to the picture.
                .nameFieldKeys(commit: save,
                               revert: { editorState.endNamingTextStyle() })
            Button("Save", action: save)
                .controlSize(.small)
                .panelHelp("Saves this text style under that name")
                .playtestControl("Save")
        }
        .padding(.top, 2)
    }

    private func save() {
        editorState.saveTextStyle(name: draft)
    }
}

// MARK: - One text tile on the Styles shelf

/// A text style on the shelf: two letters drawn the way the style sets them,
/// its name, and how much of the document leans on it. Click picks it, which
/// opens the section where it is renamed, re-set or removed.
///
/// It draws the letters rather than a swatch for the same reason a saved
/// gradient draws its ramp: a shelf of identical grey squares is a shelf you
/// cannot pick a style off. The sample is short — a tile is about a hundred
/// points wide — and it is capped in size so a 96pt heading does not make one
/// tile four times the height of the ones beside it.
struct LibraryTextStyleTile: View {
    @Environment(EditorState.self) private var editorState
    let entry: LibraryEntry
    let style: TextStyle

    private var isSelected: Bool { editorState.selectedLibraryItemID == entry.id }

    /// How big the two letters are drawn, whatever the style's own size is. The
    /// tile shows what the style LOOKS like — its face, its weight, its colour —
    /// and a 96pt heading drawn at 96pt would be one letter and a clipped edge.
    private static let sampleSize: CGFloat = 26

    /// What the letters are drawn ON.
    ///
    /// Not the panel's own colour: the first build did that and a style whose
    /// text is near-black came out invisible on the dark dock, which is the one
    /// thing a tile has to not do. So the plate opposes the letters the same way
    /// the canvas contrast halo does — light letters get a dark plate, dark
    /// letters a light one — and the sample is legible whatever the style is and
    /// whichever theme the app is in.
    private var plate: Color {
        let luminance = (RGBA(hex: style.treatment.colorHex)
                         ?? RGBA(r: 1, g: 1, b: 1)).relativeLuminance
        return luminance >= 0.5 ? Color.black.opacity(0.75) : Color.white.opacity(0.85)
    }

    private func weight(_ weight: TextWeight) -> Font.Weight {
        switch weight {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }

    var body: some View {
        // A real button rather than a tap gesture on a plain view.
        //
        // The saved colour's tile next door gets away with a gesture because it
        // is also draggable, and the drag brings a real control with it. Without
        // one, a click on this tile went nowhere: the tile drew as unpicked and
        // no Style section opened, which a scripted walk caught on 2026-09-08
        // by pressing both tiles in one document and getting an answer from only
        // one of them. A button also gives the tile a keyboard route, which the
        // gesture never had.
        Button { editorState.selectLibraryItem(entry.id) } label: { tile }
            .buttonStyle(.plain)
            .panelHelp("\(entry.name) • \(TextStyleNaming.treatmentText(style.treatment))"
                       + " • \(entry.detail)")
            .playtestTarget(entry.name, kind: .tile, detail: "Styles")
    }

    private var tile: some View {
        VStack(spacing: LibraryShelfLayout.captionSpacing) {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(plate)
                Text(TextStyleNaming.sample)
                    .font(.system(size: Self.sampleSize, weight: weight(style.treatment.weight)))
                    .foregroundStyle(Color(hex: style.treatment.colorHex))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 6)
            }
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
    }
}

// MARK: - The picked text style's section

/// The section that opens when you pick a text style off the shelf. It is where
/// a style is changed, because changing it here changes every piece of text
/// wearing it, and doing that from one of those layers would look like editing
/// that layer.
struct LibraryTextStyleInspector: View {
    @Environment(EditorState.self) private var editorState

    @State private var draft = ""
    @State private var isPickerShown = false
    @FocusState private var nameFocused: Bool

    private var style: TextStyle? { editorState.selectedTextStyle }

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
                        .nameFieldKeys(commit: { commit(style) },
                                       revert: { draft = style.name })
                        .onChange(of: nameFocused) { _, focused in if !focused { commit(style) } }
                }
                fontRow(style)
                HStack(alignment: .top, spacing: 8) {
                    sizeRow(style)
                    weightRow(style)
                }
                colorRow(style)
                Text(TextStyleNaming.standing(usageCount: editorState.textStyleUsageCount(styleID: style.id)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Button("Select What Uses This") {
                        editorState.selectLayersUsingTextStyle(styleID: style.id)
                    }
                    .controlSize(.small)
                    .disabled(editorState.textStyleUsageCount(styleID: style.id) == 0)
                    .panelHelp("Selects the text this style sets")
                    Button("Remove") {
                        editorState.deleteTextStyle(styleID: style.id)
                    }
                    .controlSize(.small)
                    .panelHelp("Takes the style off the shelf. Every piece of text keeps the type it is wearing")
                }
            }
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
            .padding(.vertical, 4)
            .onAppear { draft = style.name }
            .onChange(of: style.id) { _, _ in draft = style.name }
            .onChange(of: style.name) { _, name in if !nameFocused { draft = name } }
        }
    }

    private func fontRow(_ style: TextStyle) -> some View {
        captioned("Font") {
            Picker("Font", selection: binding(style, \.fontName)) {
                ForEach(TextStyles.fontOptions(picked: [style.treatment.fontName]), id: \.self) {
                    Text($0).tag($0)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .panelHelp("Changing this re-sets every piece of text using this style")
        }
    }

    private func sizeRow(_ style: TextStyle) -> some View {
        captioned("Size") {
            Picker("Size", selection: binding(style, \.fontSize)) {
                ForEach(sizes(style), id: \.self) {
                    Text(TextStyles.sizeWords($0)).tag($0)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .panelHelp("Changing this re-sets every piece of text using this style")
        }
    }

    private func weightRow(_ style: TextStyle) -> some View {
        captioned("Weight") {
            Picker("Weight", selection: binding(style, \.weight)) {
                ForEach(TextWeight.allCases, id: \.self) {
                    Text($0.rawValue.capitalized).tag($0)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .panelHelp("Changing this re-sets every piece of text using this style")
        }
    }

    private func colorRow(_ style: TextStyle) -> some View {
        HStack(spacing: 8) {
            Text("Color")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button { isPickerShown = true } label: { swatch(style) }
                .buttonStyle(.plain)
                .panelHelp("Changing this re-sets every piece of text using this style")
                .popover(isPresented: $isPickerShown, arrowEdge: .top) {
                    ColorPickerContent(editorState: editorState,
                                       paint: Paint(hex: style.treatment.colorHex),
                                       name: style.name,
                                       supportsOpacity: true,
                                       supportsGradient: false,
                                       onClose: { isPickerShown = false }) { paint in
                        var treatment = style.treatment
                        treatment.colorHex = paint.hex
                        editorState.setTextStyle(styleID: style.id, treatment: treatment)
                    }
                }
        }
    }

    private func swatch(_ style: TextStyle) -> some View {
        PaintFill(paint: Paint(hex: style.treatment.colorHex))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .background(CheckerBoard(square: 4).clipShape(RoundedRectangle(cornerRadius: 4)))
            .frame(width: 18, height: 18)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.25), lineWidth: 1))
    }

    /// One control with its name in a small caption above it, the way the Text
    /// section itself labels things, so the style's own controls and the ones
    /// that set a layer by hand read as the same controls.
    private func captioned<Content: View>(_ label: String,
                                          @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .playtestField(label)
    }

    /// Every control writes the WHOLE treatment back, so one edit is one step
    /// however many of the four it touched.
    private func binding<Value>(_ style: TextStyle,
                                _ key: WritableKeyPath<TextTreatment, Value>) -> Binding<Value> {
        Binding(
            get: { style.treatment[keyPath: key] },
            set: { value in
                var treatment = style.treatment
                treatment[keyPath: key] = value
                editorState.setTextStyle(styleID: style.id, treatment: treatment)
            })
    }

    /// The preset sizes, plus whatever this style is already set at, so a style
    /// made from 40pt text does not lose its size just by being looked at.
    private func sizes(_ style: TextStyle) -> [CGFloat] {
        let size = style.treatment.fontSize
        guard !TextStyles.fontSizes.contains(size) else { return TextStyles.fontSizes }
        return (TextStyles.fontSizes + [size]).sorted()
    }

    private func commit(_ style: TextStyle) {
        guard let name = ComponentNaming.normalized(draft) else {
            draft = style.name   // ...a blank name is refused, so put it back
            return
        }
        guard name != style.name else { return }
        editorState.renameTextStyle(styleID: style.id, to: name)
    }
}
