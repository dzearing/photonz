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
/// It sits on every row of the Color section (`SelectionColorInspector`), which
/// is the one place a color lives whatever is picked. The mock hangs it off a
/// Fill section of its own; one section holding every color the selection has
/// is the same idea without a second place to look.
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
    /// layers, which brings a well of its own: one that paints all of them.
    private let well: AnyView?
    /// A small control that belongs to this row and sits after the color: the
    /// way back for a copy of a component whose border color is its own. It
    /// goes where the color it undoes is, rather than staying behind in the
    /// section the color came from.
    private var accessory: AnyView?

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

    /// The row in the Color section: one well that paints everything picked,
    /// and the menu.
    init(part: String, slot: ColorSlot) {
        self.part = part
        self.slot = slot
        self.switchControl = nil
        self.well = nil
    }

    /// The same row for a color that can be switched off altogether, like a
    /// box's inside or a frame's surface.
    init(part: String, slot: ColorSlot, switchControl: some View) {
        self.part = part
        self.slot = slot
        self.switchControl = AnyView(switchControl)
        self.well = nil
    }

    /// Hangs a small control off the end of the row.
    func accessory(@ViewBuilder _ content: () -> some View) -> ColorPartRow {
        var copy = self
        copy.accessory = AnyView(content())
        return copy
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
            if let accessory { accessory }
            Spacer(minLength: 0)
        }
        // Every color row holds a control called Color and one called Switch,
        // so the row's own word is what tells Fill's from Background's:
        // `press "Color" in "Fill"`.
        .playtestField(part)
    }
}

/// A color row's right-hand half: the readout, and the styles button, with the
/// name field that saving opens sitting under them. `ColorPartRow` is what puts
/// a label in front of it; nothing should use this on its own.
///
/// The readout is whichever of three things is true. A color of its own gets a
/// well — one layer's, or the whole selection's, which paints every picked
/// layer at once. A color that comes from a style shows a plain swatch and the
/// style's name instead: the color is still there to see, it is just not edited
/// here, and Unlink in the menu is the way back. Several layers that disagree
/// say Mixed, because showing one of their colors is how three layers end up
/// somewhere nobody asked for — and over a selection that word is itself the
/// well, so the way out of Mixed is the thing you were already looking at.
struct ColorStyleRow<Well: View>: View {
    @Environment(EditorState.self) private var editorState
    let slot: ColorSlot
    /// What the row paints, passed through to the menu so it can say which
    /// saved colors it is offering and why there are not more of them.
    let part: String
    /// True for the row over several picked layers. Its well paints all of
    /// them, and stands in for the word Mixed as the thing you click when they
    /// disagree.
    private let paintsSelection: Bool
    private let well: Well

    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    init(slot: ColorSlot, part: String, @ViewBuilder well: () -> Well) {
        self.slot = slot
        self.part = part
        self.well = well()
        self.paintsSelection = false
    }

    /// The row over a selection: one well for all of them, and the menu.
    init(slot: ColorSlot, part: String) where Well == SelectionColorWell {
        self.slot = slot
        self.part = part
        self.well = SelectionColorWell(slot: slot, part: part)
        self.paintsSelection = true
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
            draft = editorState.suggestedColorStyleName(slot: slot)
            nameFocused = true
            DispatchQueue.main.async { NSApp.keyWindow?.firstResponder?.trySelectAllText() }
        }
    }

    @ViewBuilder private func readout(_ selection: ColorStyleSelection) -> some View {
        switch selection.reading {
        case .style(let id):
            if let style = editorState.colorStyles.first(where: { $0.id == id }) {
                swatch(style.paint(for: slot))
                    .help("This color comes from the style \(style.name)")
            }
        case .mixed:
            // Over a selection the word IS the well: it says they differ and
            // it is the one thing to click to stop them differing.
            if paintsSelection {
                well
            } else {
                Text(ColorStyleSelection.mixedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("The picked layers do not share one \(part.lowercased()). "
                          + "Choosing a color or a style sets all of them.")
            }
        case .color:
            well
        case .empty:
            if !paintsSelection { well }
        }
    }

    private func swatch(_ paint: Paint) -> some View {
        PaintFill(paint: paint)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .background(CheckerBoard(square: 4).clipShape(RoundedRectangle(cornerRadius: 4)))
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
                .help("Saves this \(ColorStyleNaming.subject(savedPaint)) under that name")
                .playtestControl("Save")
        }
        .padding(.top, 2)
    }

    /// What Save would keep, so the button can say whether it is a colour or a
    /// gradient without guessing.
    private var savedPaint: Paint {
        selection.savablePaint ?? Paint(hex: "#000000")
    }

    private func save() {
        editorState.saveColorStyle(slot: slot, name: draft)
    }
}

/// The color well on a row that speaks for several picked layers: one click,
/// one color, every one of them painted, in a step one undo puts back.
///
/// It is the readout AND the control, because two of them in a 264pt dock is
/// one too many. Layers that agree show the color they share and it opens on
/// that color. Layers that do not still say Mixed, and the word itself is the
/// button: the row keeps saying they differ right up until a color is picked,
/// and the way to stop them differing is the thing the eye is already on.
///
/// It is the app's own picker rather than the system panel, so a color lands on
/// a deliberate action (a swatch, a slider let go of, a hex typed) instead of
/// on every drag tick. Twenty undo steps for one blue is not one move.
struct SelectionColorWell: View {
    @Environment(EditorState.self) private var editorState
    let slot: ColorSlot
    /// What the row beside this paints, in the row's own words, so the hover
    /// tip can say it: "Fill", "Outline", "Text".
    let part: String

    @State private var isHovering = false

    private var selection: ColorStyleSelection { editorState.colorStyleSelection(slot: slot) }

    /// The key this well answers to, so only one picker is ever open and a
    /// walk can open this one without a pointer.
    private var wellKey: String { "selection.\(slot.rawValue)" }

    var body: some View {
        let selection = self.selection
        Button { editorState.openColorWell = wellKey } label: { label(selection) }
            .buttonStyle(.plain)
            // A readout and a control look alike sitting still, so the hairline
            // firms up under the pointer: that is what says this one is worth
            // clicking, and it is the difference between finding the way out of
            // Mixed and giving up on the row.
            .onHover { isHovering = $0 }
            .help(help(selection))
            .accessibilityLabel("\(part) of \(selection.count) selected layers")
            // The same word every color well in the panel answers to, its row
            // saying which color it paints. Pressing it opens the picker.
            .playtestControl("Color", detail: part)
            .popover(isPresented: editorState.colorWellBinding(wellKey), arrowEdge: .top) {
                ColorPickerContent(editorState: editorState,
                                   paint: openingPaint(selection),
                                   name: part,
                                   slot: slot,
                                   supportsOpacity: true,
                                   supportsGradient: slot.acceptsGradient,
                                   onClose: { editorState.openColorWell = nil },
                                   // Live while the pointer is down, so the
                                   // shapes follow the drag; ONE step, and one
                                   // recents entry, when it is let go of.
                                   onPreview: { paint in
                    editorState.previewSelectionPaint(slot: slot, paint: paint)
                }) { paint in
                    editorState.commitSelectionPaint(slot: slot, paint: paint)
                }
            }
    }

    @ViewBuilder private func label(_ selection: ColorStyleSelection) -> some View {
        if case .color(let hex) = selection.reading {
            // The swatch shows the PAINT, so a row holding a gradient looks
            // like the gradient rather than like the one flat colour it stands
            // for. Everything else about the chip is what it always was.
            // The paint in flight while a colour drag is happening, so the
            // chip under the picker keeps up with the canvas rather than
            // sitting on the old colour for a whole pull and jumping.
            PaintFill(paint: editorState.previewedPaint(slot: slot) ?? Paint(hex: hex))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                // Under a color that can be see-through, so a translucent fill
                // reads as translucent rather than as a paler one.
                .background(CheckerBoard(square: 4).clipShape(RoundedRectangle(cornerRadius: 4)))
                .frame(width: 18, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(edge, lineWidth: 1))
        } else {
            // A chip rather than bare text: the same height and the same
            // hairline as the swatch it replaces, so a row that says Mixed
            // still looks like a row with something to press.
            Text(ColorStyleSelection.mixedText)
                .font(.caption)
                .foregroundStyle(isHovering ? .primary : .secondary)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(edge, lineWidth: 1))
        }
    }

    private var edge: Color { .primary.opacity(isHovering ? 0.55 : 0.25) }

    /// The color the picker opens on: the one they share, else the first
    /// picked layer's, so a Mixed row opens somewhere in the neighbourhood
    /// rather than on white.
    private func openingHex(_ selection: ColorStyleSelection) -> String {
        selection.savableColorHex ?? selection.members.first?.colorHex ?? "#FFFFFF"
    }

    /// And the paint it opens on: the gradient they all share when there is
    /// one, so opening a gradient shows you the gradient instead of quietly
    /// flattening it the moment you click.
    private func openingPaint(_ selection: ColorStyleSelection) -> Paint {
        editorState.selectionPaint(slot: slot) ?? Paint(hex: openingHex(selection))
    }

    private func help(_ selection: ColorStyleSelection) -> String {
        // "the text of all 3 of them" would read as the words rather than the
        // ink, so every slot says color out loud: fill color, outline color,
        // text color.
        var lines = ["Sets the \(part.lowercased()) color of all "
                     + "\(selection.count) of them, in one step."]
        if let note = selection.unlinkNote { lines.append(note) }
        return lines.joined(separator: " ")
    }
}

// MARK: - The color rows a whole selection gets

/// The Color section: THE place a color lives, whatever is picked.
///
/// It used to appear only while more than one layer was picked; with one
/// picked, that layer's colors sat inside the Rectangle, Text or Frame section
/// instead. So shift-clicking a second layer moved the color you were editing
/// into a different section, and the only thing that had changed was that you
/// picked one more thing. Now the section is here as soon as anything with a
/// color is picked, and it is the only place a color is, so adding to the
/// selection widens what the row speaks for and moves nothing.
///
/// That is also why the rows are named by SLOT and not by shape: Outline, Fill,
/// Text. A label that read Color over a lone arrow and Outline the moment a box
/// joined it would be the same bug one level down.
///
/// A color that can be absent — a box's inside, a frame's surface — carries the
/// checkbox that turns it on and off, which is the row that used to be a Fill
/// toggle in a shape's settings and a "No background" button in a frame's.
struct SelectionColorInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let slots = editorState.colorRowSlots
        VStack(alignment: .leading, spacing: 10) {
            ForEach(slots, id: \.self) { slot in
                row(slot)
            }
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder private func row(_ slot: ColorSlot) -> some View {
        let selection = editorState.colorStyleSelection(slot: slot)
        let part = slot.selectionTitle
        VStack(alignment: .leading, spacing: 2) {
            if editorState.colorSwitch(slot: slot).isOffered {
                ColorPartRow(part: part, slot: slot, switchControl: switchControl(slot, part))
                    .accessory { styleRevert(slot) }
            } else {
                ColorPartRow(part: part, slot: slot)
                    .accessory { styleRevert(slot) }
            }
            // A Fill row that quietly skips the arrow in the selection says so
            // here, rather than looking as though it did nothing — and so does
            // one where picking a color would let go of a style, which is said
            // before the click rather than discovered after it.
            ForEach([selection.note, selection.unlinkNote].compactMap { $0 }, id: \.self) { note in
                Text(note).font(.caption2).foregroundStyle(.tertiary)
                    .padding(.leading, ColorPartLayout.labelWidth + ColorPartLayout.spacing)
            }
        }
    }

    /// The way back for a copy of a component that has picked its own border
    /// color. Only the border is a part of the LOOK a copy can own; a shape's
    /// ink and a text block's ink are its content, and they follow the
    /// original by other means. It came down here with the color it undoes.
    @ViewBuilder private func styleRevert(_ slot: ColorSlot) -> some View {
        if slot == .border,
           let only = soleLayerID(editorState.colorStyleSelection(slot: slot).layerIDs) {
            InstanceStyleRevert(layerID: only, field: .borderColor)
        }
    }

    /// The checkbox beside a color that can be absent. It answers to the row's
    /// own label rather than carrying a second copy of the word, the way the
    /// Fill toggle in a shape's settings always has.
    private func switchControl(_ slot: ColorSlot, _ part: String) -> some View {
        Toggle(part, isOn: Binding(
            get: { editorState.colorSwitch(slot: slot).isOn },
            set: { editorState.setColorEnabled(slot: slot, on: $0) }))
            .labelsHidden()
            .controlSize(.small)
            .help(switchHelp(slot, part))
            // It wears no word of its own, so it takes the row's: a walk says
            // `press "Switch" in "Background"`.
            .playtestControl("Switch",
                             detail: editorState.colorSwitch(slot: slot).isOn ? "on" : "off")
    }

    private func switchHelp(_ slot: ColorSlot, _ part: String) -> String {
        let count = editorState.colorSwitch(slot: slot).layerIDs.count
        let noun = part.lowercased()
        return count > 1
            ? "Turns the \(noun) on or off for all \(count) of them"
            : "Turns the \(noun) on or off"
    }

    /// Said only when the section is speaking for more than one layer. Over a
    /// single layer every row means what it has always meant, and a sentence
    /// explaining that is a sentence in the way.
    private var caption: String? {
        let count = editorState.colorStyleSelectionCount
        guard count > 1 else { return nil }
        return "\(count) layers. A color or a style picked here paints every one "
            + "of them, in one step."
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
            // The tile IS the style: a saved ramp is drawn as the ramp, aimed
            // the way it was aimed, because a shelf of flat squares is a shelf
            // you cannot pick a gradient off.
            PaintFill(paint: style.paint)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                // Under it, so a ramp that fades to nothing reads as fading
                // rather than as a paler orange.
                .background(CheckerBoard(square: 4).clipShape(RoundedRectangle(cornerRadius: 5)))
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
        .help("\(entry.name) • \(ColorStyleNaming.paintText(style.paint)) • \(entry.detail)")
        // Named for a walk, with no payload: a style tile is not picked up.
        .playtestTarget(entry.name, kind: .tile, detail: "Styles")
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
                    Text(ColorStyleNaming.rowTitle(style.paint))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button { isPickerShown = true } label: { swatch(style) }
                        .buttonStyle(.plain)
                        .help("Changing this repaints every layer using this style")
                        .popover(isPresented: $isPickerShown, arrowEdge: .top) {
                            // The whole paint, so a saved gradient is edited
                            // where it lives: move a stop here and every shape
                            // wearing it follows, in one step.
                            ColorPickerContent(editorState: editorState,
                                               paint: style.paint,
                                               name: style.name,
                                               supportsOpacity: true,
                                               supportsGradient: true,
                                               onClose: { isPickerShown = false }) { paint in
                                editorState.setColorStylePaint(styleID: style.id, paint: paint)
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
                    // Said only about a ramp, and said HERE, because this is
                    // where somebody ticks "Outlines and text" and then goes
                    // looking for it on a Text row.
                    if let note = ColorStyleNaming.gradientReachNote(style.paint) {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
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
        PaintFill(paint: style.paint)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .background(CheckerBoard(square: 4).clipShape(RoundedRectangle(cornerRadius: 4)))
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
