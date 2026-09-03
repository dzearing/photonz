import AppKit
import PhotonzCore
import SwiftUI

/// Which color row has its name field open. One field at a time, and the app
/// rather than the row holds it, so moving the selection closes it. The slot is
/// the whole address: the row speaks for whatever is picked, so there is only
/// ever one Fill row on screen.
struct ColorStyleNamingRequest: Hashable {
    let slot: ColorSlot
}

// MARK: - The styles button that sits beside a color (Next, `next-styles`)

/// What every color row in the inspector grows when styles are on
/// (`docs/design/ui-building.md`, step D8): a small button that saves this
/// color under a name, or points the row at a name you already have.
///
/// It speaks for the WHOLE selection. One layer picked or twenty, choosing
/// Accent here paints every picked layer that has this kind of color, in one
/// step that one undo puts back, which is what turns "set these three boxes to
/// Accent" into one move instead of three.
///
/// Three states, and the row reads differently in each:
///
/// - **A color of its own.** The row keeps its color well and this button is a
///   swatch outline: "Save as Style" makes one, and any style already on the
///   shelf can be picked straight from the menu.
/// - **Wearing a style.** The well becomes a plain swatch and this button says
///   the style's NAME beside a palette mark, because a color that belongs to a
///   style is not a color you edit here: you change the style, on the shelf,
///   and everything wearing it follows. "Unlink" is in the menu and says what
///   it does, so the way back to a one-off color is one click and never a
///   surprise. The row's own label never moves out of the way for the name —
///   losing it was exactly what made a rectangle's settings unreadable.
/// - **Disagreeing.** Layers wearing different styles, or different colors, say
///   Mixed rather than naming one of them: a row printing Accent over three
///   layers when only one wears it is how you unlink a style you never meant to
///   touch. Picking a name still lands on all of them, which is the way out.
///
/// The menu offers only the saved colors meant for the part the row paints, and
/// says which part that is, so a color kept for hairlines is not on the list as
/// something to fill a box with.
///
/// The mock hangs this off a Fill section of its own; the app already has an
/// Outline and a Fill row inside a shape's settings, a Color row inside Text
/// and a Background row inside Frame, so the control goes on those rather than
/// a fourth place to look for a color. With several layers picked those
/// sections are gone, and the Color section (`SelectionColorInspector`) is the
/// one place instead.
struct ColorStyleControl: View {
    @Environment(EditorState.self) private var editorState
    let slot: ColorSlot
    /// What the row beside this paints, in the row's own words: "Outline",
    /// "Fill", "Background", "Text". The menu says it out loud, so a shorter
    /// list reads as scoped rather than as colors having gone missing.
    let part: String

    private var selection: ColorStyleSelection { editorState.colorStyleSelection(slot: slot) }
    /// Only the saved colors meant for this part. A color kept for hairlines
    /// is not something to fill a box with, and offering it was how the menu
    /// stopped meaning anything.
    private var styles: [ColorStyle] { editorState.colorStyles(for: slot) }

    var body: some View {
        if Experiments.shared.colorStylesEnabled, !selection.isEmpty {
            let selection = selection
            // Looked up in the WHOLE shelf, not in the offer list below: a
            // color already painting this slot has to be named even if it is
            // no longer offered for it, or a row wearing one style reads as
            // wearing several.
            let style = selection.boundStyleID
                .flatMap { id in editorState.colorStyles.first { $0.id == id } }
            Menu {
                if let style {
                    Section("Using \(style.name)") {
                        Button("Edit \(style.name) in the Library") {
                            editorState.selectLibraryItem(style.id.uuidString)
                        }
                        Button(unlinkTitle(selection)) { editorState.unlinkColorStyle(slot: slot) }
                    }
                } else if selection.wearsAnyStyle {
                    // Several styles under one row: there is no name to print,
                    // but letting go of all of them is still one honest move.
                    Section("Using more than one style") {
                        Button(unlinkTitle(selection)) { editorState.unlinkColorStyle(slot: slot) }
                    }
                } else if selection.savableColorHex != nil {
                    Button(saveTitle(selection)) { editorState.beginNamingColorStyle(slot: slot) }
                }
                if !styles.isEmpty {
                    Section(selection.count > 1
                            ? "\(offerTitle), for all \(selection.count)"
                            : offerTitle) {
                        ForEach(styles) { option in
                            Button {
                                editorState.useColorStyle(slot: slot, styleID: option.id)
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
                } else if !editorState.colorStyles.isEmpty {
                    // There ARE saved colors, they are just for other parts.
                    // Saying so is the difference between a scoped list and a
                    // list that looks as though the color you saved a minute
                    // ago has gone, and it points at the one place that
                    // changes what a color is for.
                    Section("Your saved colors are for other parts") {
                        Button("Change what one is for in the Library") {
                            editorState.showColorStyleShelf()
                        }
                    }
                }
            } label: {
                label(style)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(help(selection, style))
        }
    }

    /// Wearing a style: a palette mark and the style's NAME, with the menu's
    /// own chevron beside them so it reads as something to open rather than a
    /// stray word. Otherwise the quiet swatch glyph on its own.
    ///
    /// A menu's label is drawn by AppKit, which keeps text and symbols and
    /// drops anything else, so the style's color is drawn by the ROW next
    /// door rather than in here (a swatch put in this label came out blank).
    @ViewBuilder private func label(_ style: ColorStyle?) -> some View {
        if let style {
            // The glyph is what keeps the two words apart. The row's own label
            // sits in the column to the left saying what gets painted; this
            // one is the NAME OF A SAVED COLOR, and without a mark saying so
            // the two read as a pair of labels and neither means anything.
            HStack(spacing: 3) {
                Image(systemName: "swatchpalette")
                Text(style.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            Image(systemName: "swatchpalette")
        }
    }

    /// What the list of saved colors is headed. It names the part, so a list
    /// with four names on it where the document has six reads as "these are
    /// the ones that go here" rather than as colors having gone missing.
    private var offerTitle: String {
        let noun = part.lowercased()
        // ...except for a part already called Color, because "saved color
        // colors" is not a sentence.
        return noun == "color" ? "Saved colors" : "Saved \(noun) colors"
    }

    private func unlinkTitle(_ selection: ColorStyleSelection) -> String {
        selection.count > 1 ? "Unlink All \(selection.count)" : "Unlink"
    }

    private func saveTitle(_ selection: ColorStyleSelection) -> String {
        selection.count > 1 ? "Save as Style for All \(selection.count)" : "Save as Style"
    }

    /// The hover tip. With one layer picked it is about that color; with
    /// several it has to say how many layers a pick here reaches, or "Accent"
    /// over three boxes reads as a guess.
    private func help(_ selection: ColorStyleSelection, _ style: ColorStyle?) -> String {
        let noun = part.lowercased()
        let many = selection.count > 1
        let sentence: String
        switch (style, many) {
        case (.some(let style), false):
            sentence = "This \(noun) uses the style \(style.name)"
        case (.some(let style), true):
            sentence = "All \(selection.count) of these use the style \(style.name)"
        case (nil, false):
            sentence = "Save this \(noun) as a named style, or use one you already saved"
        case (nil, true):
            sentence = "Save what these \(selection.count) share as a named style, "
                + "or set them all to one you already saved"
        }
        guard let note = selection.note else { return sentence }
        return "\(sentence). \(note)"
    }
}

/// The columns every labelled color row shares.
///
/// Before this the label sat on the left, a Spacer pushed everything else to
/// the right edge, and the swatch therefore moved whenever the name beside it
/// changed length — two rows in one section, one wearing a saved name and one
/// not, put their swatches in two different places. So the row is columns now:
/// the label, the switch that turns the color on and off, the color, the menu.
/// Every one of them is a fixed width, so the swatches line up down the
/// section whatever any row happens to be wearing.
enum ColorPartLayout {
    /// Wide enough for the longest part name the inspector uses.
    static let labelWidth: CGFloat = 68
    /// The switch column, left blank in rows with nothing to switch, so a row
    /// that has a checkbox and a row that does not still agree on where the
    /// color goes.
    static let switchWidth: CGFloat = 16
    /// Wide enough for the 18pt swatch and for the word Mixed.
    static let readoutWidth: CGFloat = 52
    /// The band the label, the switch and the color all centre on, so nothing
    /// sits half a line above its neighbour.
    static let rowHeight: CGFloat = 20
    static let spacing: CGFloat = 8
}

/// One labelled color row: what it paints, the switch that turns it on and off
/// where there is one, the color, and the menu of saved colors for that part.
///
/// The label is the point. It used to be whatever the section felt like — the
/// shape's name beside a rectangle's outline, nothing at all beside its
/// inside — and when a saved color was in use the name of that color took the
/// label's place, so the one moment you most need to know which color you are
/// looking at is the moment the row stopped saying. Now the label is a column
/// of its own and never moves.
struct ColorPartRow: View {
    /// What this row paints, in words: Outline, Fill, Background, Color.
    let part: String
    let slot: ColorSlot
    private let switchControl: AnyView?
    /// The color the row edits directly. Nil for the row over several picked
    /// layers, which has no single layer to edit a one-off color on.
    private let well: AnyView?

    init(part: String, slot: ColorSlot, @ViewBuilder well: () -> some View) {
        self.part = part
        self.slot = slot
        self.switchControl = nil
        self.well = AnyView(well())
    }

    /// A row whose color can be switched off altogether, like a box's inside.
    /// The switch answers to the same label as the color beside it.
    init(part: String, slot: ColorSlot, switchControl: some View,
         @ViewBuilder well: () -> some View) {
        self.part = part
        self.slot = slot
        self.switchControl = AnyView(switchControl)
        self.well = AnyView(well())
    }

    /// The row over several picked layers: a readout and the menu.
    init(part: String, slot: ColorSlot) {
        self.part = part
        self.slot = slot
        self.switchControl = nil
        self.well = nil
    }

    var body: some View {
        // Top aligned: the menu can open a name field under itself, which
        // makes the row two lines tall, and the label belongs beside the color
        // rather than beside the field.
        HStack(alignment: .top, spacing: ColorPartLayout.spacing) {
            Text(part)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: ColorPartLayout.labelWidth,
                       height: ColorPartLayout.rowHeight, alignment: .leading)
            // The switch column is ALWAYS this wide, blank or not: a modifier
            // on a nil optional view reserves nothing, which is what put a
            // rectangle's Outline swatch and its Fill swatch at two different
            // left edges the first time this was built.
            Group {
                if let switchControl { switchControl } else { Color.clear }
            }
            .frame(width: ColorPartLayout.switchWidth,
                   height: ColorPartLayout.rowHeight, alignment: .leading)
            if let well {
                ColorStyleRow(slot: slot, part: part) { well }
            } else {
                ColorStyleRow(slot: slot, part: part)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A color row's right-hand half: the readout, and the styles button, with the
/// name field that saving opens sitting under them. `ColorPartRow` is what puts
/// a label in front of it; nothing should use this on its own.
///
/// The readout is whichever of three things is true. One layer with a color of
/// its own gets the well it always had. A color that comes from a style shows a
/// plain swatch and the style's name instead: the color is still there to see,
/// it is just not edited here. Several layers that disagree say Mixed, because
/// showing one of their colors is how three layers end up somewhere nobody
/// asked for.
struct ColorStyleRow<Well: View>: View {
    @Environment(EditorState.self) private var editorState
    let slot: ColorSlot
    /// What the row paints, passed through to the menu so it can say which
    /// saved colors it is offering and why there are not more of them.
    let part: String
    /// False for the whole-selection rows, which have no well to fall back to:
    /// there is no single layer to edit a one-off color on.
    private let hasWell: Bool
    private let well: Well

    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    init(slot: ColorSlot, part: String, @ViewBuilder well: () -> Well) {
        self.slot = slot
        self.part = part
        self.well = well()
        self.hasWell = true
    }

    /// The row over a selection: a readout and the menu, no well.
    init(slot: ColorSlot, part: String) where Well == EmptyView {
        self.slot = slot
        self.part = part
        self.well = EmptyView()
        self.hasWell = false
    }

    private var selection: ColorStyleSelection { editorState.colorStyleSelection(slot: slot) }
    private var isNaming: Bool {
        editorState.colorStyleNaming == ColorStyleNamingRequest(slot: slot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The color keeps a column of its own whatever it is showing — a
            // well, a plain swatch, or the word Mixed — so the menu beside it
            // starts in the same place in every row of the section.
            HStack(alignment: .center, spacing: 6) {
                readout(selection)
                    .frame(minWidth: ColorPartLayout.readoutWidth, alignment: .leading)
                ColorStyleControl(slot: slot, part: part)
            }
            .frame(minHeight: ColorPartLayout.rowHeight)
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

    @ViewBuilder private func readout(_ selection: ColorStyleSelection) -> some View {
        switch selection.reading {
        case .style(let id):
            if let style = editorState.colorStyles.first(where: { $0.id == id }) {
                swatch(style.colorHex)
                    .help("This color comes from the style \(style.name)")
            }
        case .mixed:
            Text(ColorStyleSelection.mixedText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("The picked layers do not share one \(part.lowercased()). "
                      + "Choosing a style sets all of them.")
        case .color(let hex):
            if hasWell {
                well
            } else {
                swatch(hex).help("The color all \(selection.count) of them share")
            }
        case .empty:
            if hasWell { well }
        }
    }

    private func swatch(_ hex: String) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(hex: hex))
            .frame(width: 18, height: 18)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.primary.opacity(0.25), lineWidth: 1))
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
                // undo either. Both keys hand the keyboard back to the picture,
                // so the next tool letter picks a tool rather than vanishing
                // into a field that has just closed.
                .nameFieldKeys(commit: save,
                               revert: { editorState.endNamingColorStyle() })
            Button("Save", action: save)
                .controlSize(.small)
                .help("Saves this color under that name")
        }
        .padding(.top, 2)
    }

    private func save() {
        editorState.saveColorStyle(slot: slot, name: draft)
    }
}

// MARK: - The color rows a whole selection gets

/// The Color section: what several picked layers are painted, and one place to
/// set all of them to the same named color.
///
/// It exists ONLY while more than one layer is picked. With one layer picked
/// its colors live where they always have, in the Annotation, Text or Frame
/// section, and this section is absent rather than a second place to look. With
/// several picked those sections are gone (they each describe one layer), so
/// this is the only color row on screen and it can safely call a shape's ink
/// Outline and a text block's ink Text.
struct SelectionColorInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let slots = editorState.colorStyleSlots
        VStack(alignment: .leading, spacing: 10) {
            ForEach(slots, id: \.self) { slot in
                row(slot)
            }
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder private func row(_ slot: ColorSlot) -> some View {
        let selection = editorState.colorStyleSelection(slot: slot)
        VStack(alignment: .leading, spacing: 2) {
            ColorPartRow(part: slot.selectionTitle, slot: slot)
            // A Fill row that quietly skips the arrow in the selection says so
            // here, rather than looking as though it did nothing.
            if let note = selection.note {
                Text(note).font(.caption2).foregroundStyle(.tertiary)
                    .padding(.leading, ColorPartLayout.labelWidth + ColorPartLayout.spacing)
            }
        }
    }

    private var caption: String {
        let count = editorState.colorStyleSelectionCount
        return "\(count) layers. A style picked here paints every one of them, in one step."
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
                        .nameFieldKeys(commit: { commit(style) },
                                       revert: { draft = style.name })
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
                // What it is offered for. A color is saved knowing where it
                // came from, so this is already right the first time you look
                // at it; it is here because one blue really is both the fill
                // of a button and the color of a link, and without a way to
                // say so you would have to save the same blue twice.
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use it for")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ForEach(ColorStyleRole.allCases, id: \.self) { role in
                        Toggle(role.title, isOn: roleBinding(style, role))
                            .toggleStyle(.checkbox)
                            .font(.callout)
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

    /// One "Use it for" checkbox. Unticking the last one does nothing rather
    /// than leaving a color that no row will ever offer.
    private func roleBinding(_ style: ColorStyle, _ role: ColorStyleRole) -> Binding<Bool> {
        Binding(
            get: { editorState.colorStyleRoles(styleID: style.id).contains(role) },
            set: { wanted in
                var roles = editorState.colorStyleRoles(styleID: style.id)
                roles.removeAll { $0 == role }
                if wanted { roles.append(role) }
                editorState.setColorStyleRoles(styleID: style.id, roles: roles)
            })
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
