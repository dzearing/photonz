import AppKit
import PhotonzCore
import SwiftUI

/// Which color row has its name field open. One field at a time, and the app
/// rather than the row holds it, so moving the selection closes it. The slot is
/// the whole address: the row speaks for whatever is picked, so there is only
/// ever one Fill row on screen.
struct ColorStyleNamingRequest: Hashable {
    let target: ColorTarget

    init(target: ColorTarget) { self.target = target }
    init(slot: ColorSlot) { self.target = ColorTarget(slot) }
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
/// - **Wearing a style.** The well draws its color INSIDE a frame rather than
///   filling its square, and this button says the style's NAME beside a
///   palette mark, so a linked row and a plain one never look alike in the same
///   column. The well still opens the picker, because a person who clicks a
///   color wants to change it: picking one there takes the row off the style,
///   which the picker says before the click and one undo puts back. "Unlink"
///   is in the menu and in the picker and says what it does, so the way back to
///   a one-off color is one click and never a surprise. The row's own label
///   never moves out of the way for the name — losing it was exactly what made
///   a rectangle's settings unreadable.
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
    /// The colours this row paints. Usually one; two on the Outline row over a
    /// shape and a picture, which the menu treats as the one part it is.
    let target: ColorTarget
    /// What the row beside this paints, in the row's own words: "Outline",
    /// "Fill", "Background", "Text". The menu says it out loud, so a shorter
    /// list reads as scoped rather than as colors having gone missing.
    let part: String

    init(target: ColorTarget, part: String) {
        self.target = target
        self.part = part
    }

    init(slot: ColorSlot, part: String) {
        self.init(target: ColorTarget(slot), part: part)
    }

    private var selection: ColorStyleSelection { editorState.colorStyleSelection(target) }
    /// Only the saved colors meant for this part. A color kept for hairlines
    /// is not something to fill a box with, and offering it was how the menu
    /// stopped meaning anything.
    private var styles: [ColorStyle] { editorState.colorStyles(for: target) }

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
                        Button(unlinkTitle(selection)) { editorState.unlinkColorStyle(target) }
                    }
                } else if selection.wearsAnyStyle {
                    // Several styles under one row: there is no name to print,
                    // but letting go of all of them is still one honest move.
                    Section("Using more than one style") {
                        Button(unlinkTitle(selection)) { editorState.unlinkColorStyle(target) }
                    }
                } else if selection.savableColorHex != nil {
                    Button(saveTitle(selection)) { editorState.beginNamingColorStyle(target) }
                }
                if !styles.isEmpty {
                    Section(selection.count > 1
                            ? "\(offerTitle), for all \(selection.count)"
                            : offerTitle) {
                        ForEach(styles) { option in
                            Button {
                                editorState.useColorStyle(target, styleID: option.id)
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
                            editorState.showStylesShelf()
                        }
                    }
                }
            } label: {
                label(style)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .panelHelp(help(selection, style))
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
/// the switch that turns the row on and off, the label, the color, the menu.
/// Every one of them is a fixed width, so the swatches line up down the
/// section whatever any row happens to be wearing.
///
/// The ORDER lives here too, in `PanelRowHead`, and not in the lists. Reported
/// by the user on 2026-09-07: the tick is what the row is for, so it belongs
/// first. Both lists ask for a head rather than laying two views out
/// themselves, so a list added later cannot come out the other way round.
enum ColorPartLayout {
    /// Wide enough for the longest part name the inspector uses.
    static let labelWidth: CGFloat = 68
    /// The switch column, FIRST in the row and left blank in rows with nothing
    /// to switch, so a row that has a checkbox and a row that does not still
    /// agree on where the name and the color go.
    ///
    /// It is the panel's shared leading column, INSIDE the row: holding it
    /// open lines the names up without pushing the row itself off the panel's
    /// margin (`EditorChromeLayout.panelRowLeadingColumn`).
    static let switchWidth: CGFloat = EditorChromeLayout.panelRowLeadingColumn
    /// The colour chip itself: every swatch in the panel, the one the drag
    /// lands on, and the height of the Mixed chip that stands in for them.
    static let swatchSize: CGFloat = 18
    /// The column the colour keeps, so a row showing a chip and a row showing
    /// nothing still put the styles button beside them in the same place.
    ///
    /// It is the CHIP and nothing else. It used to be 52 — wide enough for the
    /// word Mixed as well — which left 34pt of empty reserved column between
    /// the chip and the styles button beside it: measured off a probe capture
    /// on 2026-09-12, the chip's ink ended at x 1148 and the palette mark began
    /// at 1192.5, a gap of 44.5pt. The user reported it on 2026-09-09 with a
    /// picture of the Fill row: "it feels far away right now which makes it
    /// feel disconnected". A row wearing the word Mixed carries its own styles
    /// button along to the right of it, which is the price: the button belongs
    /// to the readout beside it, not to a column ruled down the section.
    static let readoutWidth: CGFloat = swatchSize
    /// The band the label, the switch and the color all centre on, so nothing
    /// sits half a line above its neighbour.
    static let rowHeight: CGFloat = 20
    static let spacing: CGFloat = EditorChromeLayout.panelRowGap

    /// How far inside the space the layout gives it the styles button starts
    /// DRAWING.
    ///
    /// It is a borderless menu, so AppKit gives it a bezel of its own and the
    /// palette mark begins this far in. Measured off a probe capture on
    /// 2026-09-12 rather than guessed: with the layout putting the button hard
    /// against the chip, the chip's last lit pixel was at x 1148 and the
    /// palette's first at 1152.5.
    static let styleButtonInkInset: CGFloat = 4.5

    /// The gap to leave in the LAYOUT between the colour and the styles button,
    /// so that what a PERSON sees between the chip and the palette mark is one
    /// standard row gap. The button's own bezel pays for part of it.
    static var styleGap: CGFloat { max(0, spacing - styleButtonInkInset) }

    /// The ink a small checkbox actually draws, which is narrower than the
    /// column it sits in and leading aligned inside it. Measured off a probe
    /// capture on 2026-09-07 rather than guessed: 14 wide in a 16 wide column.
    static let tickWidth: CGFloat = 14

    /// How far in the middle of the tick sits, from the row's leading edge.
    /// The switch column is first, so this is half the ink and nothing else.
    /// `OwnedSettings` hangs its rule on it, which is the whole reason the
    /// number is shared instead of typed twice.
    static var tickCenter: CGFloat { tickWidth / 2 }

    /// How far in the NAME column starts, INSIDE a row that leads with a tick
    /// or a chevron. The row itself still begins on the panel's margin.
    ///
    /// It is the panel's one subsection indent, which is not a coincidence: a
    /// part's settings fold under its name, so they step in by exactly this
    /// much and land under the word they belong to
    /// (`EditorChromeLayout.panelSubsectionIndent`).
    ///
    /// It is NOT a margin for rows that have no leading control. A slider that
    /// wears its label over a full width track — Opacity, Corner Radius — used
    /// to be padded in by this much to line its label up with the names, which
    /// pushed it 24pt off the panel's own margin and left the section's content
    /// lining up with neither its heading nor the sections around it (reported
    /// by the user, 2026-09-08). Those rows start on the margin now and their
    /// tracks run the full width.
    static var nameLeading: CGFloat { EditorChromeLayout.panelSubsectionIndent }

}

/// The head of every row in the panel's two lists: the tick, then the name.
///
/// The tick is what the row is FOR — it is the thing you reach for over and
/// over, to see the shape with the effect and without it — so it leads, and the
/// name reads after it the way a checkbox and its label read everywhere else on
/// the Mac. Before this the name came first and the tick sat 68 points in,
/// which put it nowhere near the rule that marks the row's settings and made
/// you hunt down the list for the one control you use most.
///
/// Both columns are fixed and their widths add up the same either way round,
/// so the color, the grip and the cross after it do not move.
struct PanelRowHead<Switch: View>: View {
    /// The row's own word: Outline, Fill, Blur, Shadow 2.
    let title: String
    /// Whether the LIST this row is in has any ticks in it at all.
    ///
    /// True and the column is held open on every row, blank or not, so a row
    /// with a tick and a row without still put their names on one line. False
    /// and there is no column: a list where NOTHING can be switched has nothing
    /// to line up with, and holding the space anyway indents every name by the
    /// width of a control that is not there. That is what a lone arrow's Color
    /// row looked like — one word floating 24pt in from the panel's margin with
    /// empty space to its left (measured 2026-09-08).
    var leadsWithColumn: Bool = true
    /// The tick, where the row has one. Rows with nothing to switch pass an
    /// `EmptyView` and still keep the column while any row in the list has one.
    @ViewBuilder var switchControl: Switch

    var body: some View {
        HStack(alignment: .top, spacing: ColorPartLayout.spacing) {
            // ALWAYS this wide, blank or not, once the list has a tick in it
            // anywhere. The empty rectangle is what holds the column open: a
            // frame put straight on a view that draws nothing reserves nothing,
            // and a row with no tick then starts its name a whole column to the
            // left of every other row. That is exactly what an arrow's ink row
            // did the first time this was built, on 2026-09-08, and again the
            // day the columns arrived.
            if leadsWithColumn {
                Color.clear
                    .frame(width: ColorPartLayout.switchWidth,
                           height: ColorPartLayout.rowHeight)
                    .overlay(alignment: .leading) { switchControl }
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: ColorPartLayout.labelWidth,
                       height: ColorPartLayout.rowHeight, alignment: .leading)
        }
    }
}

extension PanelRowHead where Switch == EmptyView {
    /// A row with nothing to switch. It still holds the tick column open while
    /// any other row in the same list has one.
    init(title: String, leadsWithColumn: Bool = true) {
        self.init(title: title, leadsWithColumn: leadsWithColumn) { EmptyView() }
    }
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
/// layer at once. A color that comes from a style gets the same well drawing
/// the same color, framed rather than filled and named beside it, and picking
/// a color in it takes the row off the style. Several layers that disagree
/// say Mixed, because showing one of their colors is how three layers end up
/// somewhere nobody asked for — and over a selection that word is itself the
/// well, so the way out of Mixed is the thing you were already looking at.
struct ColorStyleRow<Well: View>: View {
    @Environment(EditorState.self) private var editorState
    /// The colours this row paints. One on nearly every row; two on the Outline
    /// row over a shape and a picture, which is one line to a person and
    /// therefore one row here.
    let target: ColorTarget
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
        self.target = ColorTarget(slot)
        self.part = part
        self.well = well()
        self.paintsSelection = false
    }

    /// The row over a selection: one well for all of them, and the menu.
    init(slot: ColorSlot, part: String) where Well == SelectionColorWell {
        self.init(target: ColorTarget(slot), part: part)
    }

    /// The same, for a row the parts list built, which already knows which of
    /// the picked layers wears which colour.
    init(target: ColorTarget, part: String) where Well == SelectionColorWell {
        self.target = target
        self.part = part
        self.well = SelectionColorWell(target: target, part: part)
        self.paintsSelection = true
    }

    private var selection: ColorStyleSelection { editorState.colorStyleSelection(target) }
    private var isNaming: Bool {
        editorState.colorStyleNaming == ColorStyleNamingRequest(target: target)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The color keeps a column the width of its CHIP, so a row showing
            // a chip and a row showing nothing put the menu beside them in the
            // same place, and the menu sits one standard gap from the chip
            // rather than across the width of the word Mixed.
            HStack(alignment: .center, spacing: ColorPartLayout.styleGap) {
                readout(selection)
                    .frame(minWidth: ColorPartLayout.readoutWidth, alignment: .leading)
                ColorStyleControl(target: target, part: part)
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
            draft = editorState.suggestedColorStyleName(target)
            nameFocused = true
            DispatchQueue.main.async { NSApp.keyWindow?.firstResponder?.trySelectAllText() }
        }
    }

    @ViewBuilder private func readout(_ selection: ColorStyleSelection) -> some View {
        // The well is in ONE place in the view tree whatever the row is
        // reading, and it matters: two branches of a switch are two views, so
        // a picker open over a styled row used to be torn down the moment
        // picking a color took the row off its style. The popover shut under
        // the pointer after one swatch, where every other row lets you keep
        // trying. Same for the row that says Mixed and then agrees.
        if showsWell(selection) {
            well
        } else if case .mixed = selection.reading {
            // A row over ONE layer cannot be mixed with itself, so this is the
            // row inside a shape's own section: it has no well of its own to
            // offer and says the word on its own.
            Text(ColorStyleSelection.mixedText)
                .font(.caption)
                .foregroundStyle(MixedLook.style)
                .panelHelp("The picked layers do not share one \(part.lowercased()). "
                      + "Choosing a color or a style sets all of them.")
        }
    }

    /// Whether the color column is the well.
    ///
    /// A color of its own is one, and so is a color that comes from a style:
    /// the well draws that one FRAMED rather than filled edge to edge, and
    /// picking a color in it takes the row off the style, which is what
    /// painting by hand has always meant everywhere else in the app. It used to
    /// be a plain chip with a tooltip, the same size and shape and in the same
    /// column as the live wells beside it, so two rows looked identical and
    /// only one of them answered — which is the one thing a person tries first.
    ///
    /// Over a selection the word Mixed IS the well: it says they differ and it
    /// is the one thing to click to stop them differing.
    private func showsWell(_ selection: ColorStyleSelection) -> Bool {
        switch selection.reading {
        case .style, .color: return true
        case .mixed: return paintsSelection
        case .empty: return !paintsSelection
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
                // undo either. Both keys hand the keyboard back to the picture,
                // so the next tool letter picks a tool rather than vanishing
                // into a field that has just closed.
                .nameFieldKeys(commit: save,
                               revert: { editorState.endNamingColorStyle() })
            Button("Save", action: save)
                .controlSize(.small)
                .panelHelp("Saves this \(ColorStyleNaming.subject(savedPaint)) under that name")
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
        editorState.saveColorStyle(target, name: draft)
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
    /// The colours this one well paints. Two on the Outline row over a shape
    /// and a picture: one click paints the shape its stroke and the picture its
    /// ring, in one step one undo puts back.
    let target: ColorTarget
    /// What the row beside this paints, in the row's own words, so the hover
    /// tip can say it: "Fill", "Outline", "Text".
    let part: String

    @State private var isHovering = false

    init(target: ColorTarget, part: String) {
        self.target = target
        self.part = part
    }

    init(slot: ColorSlot, part: String) {
        self.init(target: ColorTarget(slot), part: part)
    }

    private var selection: ColorStyleSelection { editorState.colorStyleSelection(target) }

    /// The key this well answers to, so only one picker is ever open and a
    /// walk can open this one without a pointer.
    private var wellKey: String { target.key }

    var body: some View {
        let selection = self.selection
        Button { editorState.openColorWell = wellKey } label: { label(selection) }
            .buttonStyle(.plain)
            // A readout and a control look alike sitting still, so the hairline
            // firms up under the pointer: that is what says this one is worth
            // clicking, and it is the difference between finding the way out of
            // Mixed and giving up on the row.
            .onHover { isHovering = $0 }
            .panelHelp(help(selection))
            .accessibilityLabel(boundStyle.map { "\(part) color, using the style \($0.name)" }
                                ?? "\(part) color of \(selection.count) selected layers")
            // The same word every color well in the panel answers to, its row
            // saying which color it paints. Pressing it opens the picker.
            .playtestControl("Color", detail: part, payload: {
                // The very item the swatch's own drag hands over, so a walk
                // can never carry a colour the pointer could not.
                guard let paint = editorState.selectionPaint(target) else {
                    return NSItemProvider()
                }
                return ColorDrag.itemProvider(paint: paint, source: wellKey,
                                              style: boundStyle.map {
                                                  ColorDrop.SavedColor(id: $0.id, name: $0.name)
                                              })
            })
            // Picked up and dropped on like any colour well on a Mac. Letting
            // go here goes down the very path a colour picked in the picker
            // takes — one undo step over every layer the row speaks for, and
            // the same "stopped following Accent" pill when it lets go of a
            // saved colour — so a dragged colour and a picked one are the
            // same move made two ways.
            .colorSwatchDrag(key: wellKey, part: part,
                             // Nil while the row says Mixed: there is no one
                             // colour to pick up, and a swatch handed nothing
                             // is refused everywhere rather than guessing.
                             paint: { editorState.selectionPaint(target) },
                             style: { boundStyle.map {
                                 ColorDrop.SavedColor(id: $0.id, name: $0.name)
                             } },
                             welcomes: { editorState.styleWelcome(target, styleID: $0.id) },
                             reaches: { selection.count },
                             acceptsGradient: target.acceptsGradient,
                             onDrop: { landing in
                // A colour that arrived under a NAME goes down the very path
                // the row's own menu takes when that name is picked: the row
                // wears the name afterwards and follows it the day the colour
                // behind it is edited. Anything else would make the drag a
                // quieter, lossier way to do a move the menu does properly.
                if let brings = landing.brings {
                    editorState.useColorStyle(target, styleID: brings.id)
                } else {
                    editorState.commitSelectionPaint(target, paint: landing.paint)
                }
            })
            .popover(isPresented: editorState.colorWellBinding(wellKey), arrowEdge: .top) {
                // Always two children, whether or not there is a banner to
                // draw: the picker keeps its place in the stack, so letting go
                // of a style with the picker open does not rebuild it under
                // the pointer.
                VStack(alignment: .leading, spacing: 0) {
                    styleBanner
                    ColorPickerContent(editorState: editorState,
                                       paint: openingPaint(selection),
                                       name: part,
                                       slot: target.lead,
                                       supportsOpacity: target.supportsOpacity,
                                       supportsGradient: target.acceptsGradient,
                                       onClose: { editorState.openColorWell = nil },
                                       // Live while the pointer is down, so the
                                       // shapes follow the drag; ONE step, and one
                                       // recents entry, when it is let go of.
                                       onPreview: { paint in
                        editorState.previewSelectionPaint(target, paint: paint)
                    }) { paint in
                        editorState.commitSelectionPaint(target, paint: paint)
                    }
                }
            }
    }

    /// The style painting this row, when one style paints all of it.
    private var boundStyle: ColorStyle? {
        guard Experiments.shared.colorStylesEnabled else { return nil }
        return selection.boundStyleID
            .flatMap { id in editorState.colorStyles.first { $0.id == id } }
    }

    /// What the picker says over a color that comes from a style: which style
    /// it is, that picking here lets go of it, and the way to let go without
    /// picking anything.
    ///
    /// It is said HERE rather than under the row, because here is where the
    /// click that would do it is. The same palette mark and the same word
    /// Unlink the row's own menu and the toolbar swatch use, so the three
    /// places read as one idea rather than three.
    @ViewBuilder private var styleBanner: some View {
        if let style = boundStyle {
            let selection = self.selection
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "swatchpalette")
                        .foregroundStyle(.secondary)
                    Text("Using \(style.name)")
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("Unlink") { editorState.unlinkColorStyle(target) }
                        .buttonStyle(.link)
                        .font(.callout)
                        .panelHelp("Keeps this color exactly as it is and stops following "
                              + "\(style.name)")
                        .playtestControl("Unlink", detail: part)
                }
                if let note = selection.styleReplacementNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
            .padding(.top, 12)
            .padding(.bottom, 10)
            Divider()
        }
    }

    @ViewBuilder private func label(_ selection: ColorStyleSelection) -> some View {
        if case .style(let id) = selection.reading {
            // A style the document has never heard of is no style at all: the
            // row falls back to the plain chip over the color it is actually
            // wearing rather than drawing a frame around nothing.
            if let style = editorState.colorStyles.first(where: { $0.id == id }) {
                styledSwatch(style)
            } else {
                filledSwatch(Paint(hex: selection.members.first?.colorHex ?? "#FFFFFF"))
            }
        } else if case .color(let hex) = selection.reading {
            // The swatch shows the PAINT, so a row holding a gradient looks
            // like the gradient rather than like the one flat colour it stands
            // for. Everything else about the chip is what it always was.
            // The paint in flight while a colour drag is happening, so the
            // chip under the picker keeps up with the canvas rather than
            // sitting on the old colour for a whole pull and jumping.
            filledSwatch(Paint(hex: hex))
        } else {
            // A chip rather than bare text: the same height and the same
            // hairline as the swatch it replaces, so a row that says Mixed
            // still looks like a row with something to press.
            Text(ColorStyleSelection.mixedText)
                .font(.caption)
                // At rest the one strength every Mixed in the dock wears; under
                // the pointer it firms up, which is this chip saying it is a
                // button as well as a readout.
                .foregroundStyle(isHovering ? AnyShapeStyle(.primary) : MixedLook.style)
                .padding(.horizontal, 6)
                .frame(height: ColorPartLayout.swatchSize)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(edge, lineWidth: 1))
        }
    }

    /// A color the row owns: it fills its chip edge to edge.
    private func filledSwatch(_ paint: Paint) -> some View {
        // The chip shows the PAINT, so a row holding a gradient looks like the
        // gradient rather than like the one flat color it stands for, and it
        // shows the paint in flight while a color drag is happening, so it
        // keeps up with the canvas instead of sitting on the old color for a
        // whole pull and jumping.
        PaintFill(paint: editorState.previewedPaint(target) ?? paint)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            // Under a color that can be see-through, so a translucent fill
            // reads as translucent rather than as a paler one.
            .background(CheckerBoard(square: 4).clipShape(RoundedRectangle(cornerRadius: 4)))
            .frame(width: ColorPartLayout.swatchSize, height: ColorPartLayout.swatchSize)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(edge, lineWidth: 1))
    }

    /// A color that comes from a style: the same 18pt square in the same
    /// column, but the paint sits INSIDE a frame instead of filling the square.
    ///
    /// That gap is the whole point. Two rows of the Color section used to show
    /// the same chip in the same place whether the color was the layer's own or
    /// a style's, so the only way to tell them apart was to read the name in
    /// the next column — and the one you could not click looked exactly like
    /// the one you could. Held versus filled reads straight down the column
    /// without reading a word.
    ///
    /// No palette mark on the chip: the menu button 6pt to the right already
    /// wears one beside the style's name, and the same mark twice in one row
    /// says nothing the first one did not.
    private func styledSwatch(_ style: ColorStyle) -> some View {
        PaintFill(paint: editorState.previewedPaint(target) ?? style.paint(for: target.lead))
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .background(CheckerBoard(square: 3).clipShape(RoundedRectangle(cornerRadius: 2)))
            .frame(width: 12, height: 12)
            .frame(width: ColorPartLayout.swatchSize, height: ColorPartLayout.swatchSize)
            // The holder is filled, not just outlined, the way the Mixed chip
            // in this same column is: an outline alone came out faint in the
            // light appearance, and a chip sitting in something reads as held
            // from across the panel where a hairline does not.
            .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .strokeBorder(.primary.opacity(isHovering ? 0.6 : 0.35), lineWidth: 1))
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
        editorState.selectionPaint(target) ?? Paint(hex: openingHex(selection))
    }

    private func help(_ selection: ColorStyleSelection) -> String {
        // "the text of all 3 of them" would read as the words rather than the
        // ink, so every slot says color out loud: fill color, outline color,
        // text color.
        let noun = part.lowercased()
        var lines: [String] = []
        if let style = boundStyle {
            // A color from a style says where it comes from FIRST, then what
            // clicking would do to that, because "sets the fill color" over a
            // color somebody deliberately linked is the wrong half of the
            // story to lead with.
            lines.append(selection.count > 1
                         ? "All \(selection.count) of these \(noun) colors come from "
                            + "the style \(style.name)."
                         : "This \(noun) color comes from the style \(style.name).")
        } else {
            lines.append(selection.count > 1
                         ? "Sets the \(noun) color of all \(selection.count) of them, "
                            + "in one step."
                         : "Sets the \(noun) color.")
        }
        // What a pick would let go of: for a row that disagrees, the layers it
        // would take off their styles; for a row wearing one, the style itself.
        if let note = selection.unlinkNote ?? selection.styleReplacementNote {
            lines.append(note)
        }
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
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
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
            .panelHelp(switchHelp(slot, part))
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
///
/// It is also the HANDLE for the colour it stands for. Saving a colour under a
/// name and then having to open a picker and find it again to use it made the
/// shelf a place colours went rather than a place they came from, so a tile is
/// picked up and let go of on any swatch, the same way every other colour in
/// the app is carried.
///
/// What travels is the saved colour ITSELF, not a copy of what it looks like:
/// a swatch that can wear a name takes the name and follows it afterwards,
/// exactly as it would if the name had been picked out of that row's own menu.
/// Somewhere that cannot wear one — a shadow's colour, another app — still
/// takes the colour, and the swatch says so before you let go.
struct LibraryStyleTile: View {
    @Environment(EditorState.self) private var editorState
    let entry: LibraryEntry
    let style: ColorStyle

    private var isSelected: Bool { editorState.selectedLibraryItemID == entry.id }

    /// Where a colour dragged off this tile came from. No swatch answers to
    /// it, which is right: a saved colour is at home on every swatch, and the
    /// only place it is refused is the shelf it came off.
    private var dragKey: String { "library.style.\(style.id.uuidString)" }

    private var saved: ColorDrop.SavedColor {
        ColorDrop.SavedColor(id: style.id, name: style.name)
    }

    private func item() -> NSItemProvider {
        ColorDrag.itemProvider(paint: style.paint, source: dragKey, style: saved)
    }

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
        // Pulling the tile carries the colour; a plain click still picks the
        // tile, which is what SwiftUI does with the two on one view.
        .modifier(LibraryStyleTileDrag(paint: style.paint, item: item))
        .panelHelp("\(entry.name) • \(ColorStyleNaming.paintText(style.paint)) • \(entry.detail)")
        // Named for a walk, carrying the very item the tile's own drag hands
        // over, so a walk can never carry a colour the pointer could not.
        .playtestTarget(entry.name, kind: .tile, detail: "Styles",
                        payload: Experiments.shared.colorDragEnabled ? item : nil)
    }
}

/// Picking a tile up, only where colour drag is turned on. It is its own
/// modifier so the tile itself stays one plain view, the way the swatches keep
/// theirs in `ColorSwatchDrag`.
private struct LibraryStyleTileDrag: ViewModifier {
    let paint: Paint
    let item: () -> NSItemProvider

    @ViewBuilder func body(content: Content) -> some View {
        if Experiments.shared.colorDragEnabled {
            // The 22pt chip every colour drag travels as, not the tile: a tile
            // under the pointer would say a tile was moving, and what is
            // moving is a colour.
            content.onDrag(item, preview: { DraggedColorChip(paint: paint) })
        } else {
            content
        }
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
                        .panelHelp("Changing this repaints every layer using this style")
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
                    .panelHelp("Selects the layers this style paints")
                    .playtestControl("Select What Uses This",
                                     detail: "Style, \(editorState.colorStyleUsageCount(styleID: style.id)) colors")
                    Button("Remove") {
                        editorState.deleteColorStyle(styleID: style.id)
                    }
                    .controlSize(.small)
                    .panelHelp("Takes the style off the shelf. Every layer keeps the color it is wearing")
                }
            }
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
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
            .frame(width: ColorPartLayout.swatchSize, height: ColorPartLayout.swatchSize)
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
