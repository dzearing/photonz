import PhotonzCore
import SwiftUI

/// **Appearance**: what a shape simply IS (`next-shape-parts`).
///
/// The split the panel turns on, chosen by the user on 2026-09-07 from three
/// drawn panels:
///
/// > Appearance holds the things every shape simply has, in the same order
/// > every time: its opacity, its fill, its outline, and a corner radius only
/// > where there are corners. Effects, under it, is a list you ADD to.
///
/// One sentence tells you which panel a thing is in. Before it, both panels
/// carried an opacity and a blur — the layer's own in one and a shadow's in the
/// other — so a shadow's blur read as a second top level blur and there was no
/// way to tell which was which (reported by the user, 2026-09-07).
///
/// Nothing here is added and nothing here is removed. Every row is simply
/// there, always in this order, so hunting for something you set earlier is
/// always the same four rows. Anything else you set, you added, and added
/// things are in Effects.
///
/// The model itself is `PhotonzCore/LayerParts.swift` and
/// `docs/design/shape-parts.md`.
struct PartsInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let rows = editorState.layerPartRows
        let corners = editorState.corneredRadiusSelection
        // Wider than the gap inside a part (6), so the eye groups a part with
        // the settings under it without either being pushed off the margin.
        VStack(alignment: .leading, spacing: 16) {
            // Opacity leads, always. It is the one thing EVERY layer has,
            // whatever it is made of, so it is the row that never moves.
            //
            // It is a label over a track rather than a tick and a name, so it
            // has no tick to lead with; it steps in by the width of the tick
            // column all the same, so its name starts in the same place Fill's
            // and Outline's do and the list reads as one column.
            opacity
                .padding(.leading, ColorPartLayout.nameLeading)
            ForEach(rows) { row in
                PartRowView(row: row)
            }
            // ...and a corner radius only where there are corners. An ellipse
            // has none, so it shows no row rather than a slider that does
            // nothing to what you have picked.
            if !corners.isEmpty {
                // Another label over a track, stepped in to the same name
                // column as everything above it.
                VStack(alignment: .leading, spacing: 2) {
                    CornerRadiusRow(selection: corners)
                    if let note = corners.note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, ColorPartLayout.nameLeading)
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

    /// How solid the whole layer is, whatever it is made of. It used to sit in
    /// Effects beside the blur, which is why a shadow's own Opacity in the list
    /// above read as a second copy of it.
    private var opacity: some View {
        let selection = editorState.layerStyleSelection
        return LayerStyleSlider(layerIDs: selection.layerIDs, label: "Opacity",
                                reading: selection.reading { $0.opacity }, range: 0...1,
                                format: { "\(Int(($0 * 100).rounded()))%" },
                                field: .opacity) { style, v in
            style.opacity = v
        }
    }

    /// Said only when the list is speaking for more than one layer. Over a
    /// single one every row means what it looks like it means, and a sentence
    /// explaining that is a sentence in the way.
    private var caption: String? {
        let count = editorState.colorStyleSelectionCount
        guard count > 1 else { return nil }
        return "\(count) layers. A tick or a colour picked here reaches every "
            + "one of them, in one step."
    }
}

/// One part: its name, its switch, its colour, and its settings underneath.
///
/// A part that is switched off shows its name and its switch and NOTHING else.
/// That is the whole point of the switch: off has to look off, so the colour
/// and the settings of an outline nobody can see are not sitting there
/// pretending to do something. Switch it on and its settings are simply there.
///
/// Off still TAKES A COLOUR, though. Showing nothing meant a colour carried
/// over from another row was refused by the Outline row of a box with no line
/// round it, so the only way to a coloured edge was to find the switch, flip
/// it, and repaint whatever came back (reported 2026-09-07). The whole row is
/// the landing spot instead, and while a colour is over it the column where
/// the swatch would be shows the colour about to land. Nothing new sits there
/// the rest of the time, so off still looks off.
private struct PartRowView: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerPartRow

    /// What is being held over this row right now, while it is switched off.
    /// Nil the rest of the time, and whenever what is in the air is not a
    /// colour.
    @State private var incoming: ColorDrop.Answer?

    /// Whether this part is showing anything at all. A colour that is a
    /// property rather than a part — a line's ink, a letter's ink — has no
    /// switch and is therefore always on.
    private var isOn: Bool { row.hasSwitch ? row.isOn : true }

    /// Whether this part has settings to show: only while it is on, since the
    /// settings of an absent part are settings for nothing.
    private var showsSettings: Bool { isOn && row.hasSettings }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: ColorPartLayout.spacing) {
                // The tick and then the name, in that order, from the one place
                // the panel's columns live. A part with nothing to switch — a
                // line's ink, a letter's ink — still holds the tick column open,
                // so its name starts on the same line as everybody else's.
                PanelRowHead(title: row.title) {
                    if row.hasSwitch { partSwitch }
                }
                if isOn {
                    colorControl
                } else if let paint = incoming?.landing?.paint {
                    // A colour is over the row: this is where it would land,
                    // wearing it, so letting go is never a guess.
                    LandingSwatch(paint: paint)
                } else if row.isMixed {
                    // The word where the row shows its value, which is where
                    // this row's colour says Mixed too. A part that only some
                    // of them have has no colour on screen to collide with it,
                    // and the line under the row says which of the two the
                    // word is about.
                    MixedWord()
                        .frame(minWidth: ColorPartLayout.readoutWidth,
                               minHeight: ColorPartLayout.rowHeight, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            // The whole row takes the drop while the part is off, because
            // there is no swatch to aim at and a person carrying a colour
            // aims at the row's NAME. Nothing is drawn here at rest.
            .modifier(OffPartColorDrop(row: row, active: !isOn, incoming: $incoming))
            if let note = row.reachNote {
                // Under the NAME it is about, not under the tick. The tick is
                // the row's leading column now, so a note left at the row's
                // own edge would start a whole column left of the word it
                // explains and read as belonging to the list rather than to
                // this row.
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, ColorPartLayout.nameLeading)
            }
            if showsSettings {
                OwnedSettings(owner: row.title) {
                    PartWidthRow(row: row)
                    PartPositionRow(row: row)
                }
            }
        }
        // Every row holds a control called Switch and one called Color, so the
        // row's own word is what tells the outline's from the fill's:
        // `press "Switch" in "Outline"`.
        .playtestField(row.title)
    }

    // MARK: The switch

    @ViewBuilder private var partSwitch: some View {
        // A switch has on and off and nothing else, so while the picked layers
        // disagree it shows neither: it is drawn one step quieter, because off
        // is the true answer that means none of them have this part, and the
        // first press resolves to ON for all of them. It never returns to
        // Mixed, which is a report about the selection rather than a state
        // anyone can set (`UX-PATTERNS.md` section 4).
        Toggle(row.title, isOn: Binding(get: { row.isMixed ? false : row.isOn },
                                        set: { setOn(row.isMixed ? true : $0) }))
            .labelsHidden()
            .controlSize(.small)
            .opacity(row.isMixed ? MixedLook.controlOpacity : 1)
            .help(switchHelp)
            .playtestControl("Switch",
                             detail: row.isMixed ? "mixed" : (row.isOn ? "on" : "off"))
    }

    private func setOn(_ on: Bool) {
        switch row.part {
        case .fill:
            editorState.setColorEnabled(slot: .fill, on: on)
        case .outline:
            editorState.setOutlineEnabled(ids: row.switchIDs, on: on)
        case .shadow, nil:
            // The shadow is not a row in this panel any more; it is an entry in
            // the Effects list under it.
            break
        }
    }

    private var switchHelp: String {
        let noun = row.title.lowercased()
        // While they disagree the switch has no state to turn off, so the tip
        // says what the press it CAN take would do.
        if row.isMixed {
            return "Gives all \(row.switchIDs.count) of them \(row.part?.article ?? "a") \(noun)"
        }
        return row.switchIDs.count > 1
            ? "Turns the \(noun) on or off for all \(row.switchIDs.count) of them"
            : "Turns the \(noun) on or off"
    }

    // MARK: The colour

    @ViewBuilder private var colorControl: some View {
        if let target = ColorTarget(row.colors) {
            // ONE well, however many kinds of line the row speaks for. Over a
            // rectangle and a screenshot it paints the shape its stroke and the
            // picture its ring, in one step one undo puts back.
            ColorStyleRow(target: target, part: row.title)
            // The way back for a copy of a component that has picked its own
            // ring colour. It sits with the colour it undoes, which is here.
            if target.lead == .border, let only = soleLayerID(row.switchIDs) {
                InstanceStyleRevert(layerID: only, field: .borderColor)
            }
        }
    }
}

/// The colour about to land, drawn where a row's swatch would be: the same 18pt
/// square in the same column, ringed the way every swatch in the panel rings
/// while a colour is over it.
struct LandingSwatch: View {
    let paint: Paint

    var body: some View {
        PaintFill(paint: paint)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .background(CheckerBoard(square: 4).clipShape(RoundedRectangle(cornerRadius: 4)))
            .frame(width: 18, height: 18)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.accentColor, lineWidth: 2))
            .frame(minWidth: ColorPartLayout.readoutWidth,
                   minHeight: ColorPartLayout.rowHeight, alignment: .leading)
            .transition(.opacity)
    }
}

/// Settings that belong to the row above them, and say so.
///
/// A shadow carries a Blur, a Size and an Opacity of its own, and the layer
/// carries a Blur and an Opacity too. Drawn flat in one column they read as the
/// same thing twice: the user hit exactly that on 2026-09-07 and could not tell
/// which panel owned which. So a part's settings sit behind a rule of their
/// own, stepped in from the row that owns them — chosen by the user the same
/// day, which is what reversed the "no indent" ask from 2026-09-06: the indent
/// is back because it is now carrying a meaning it did not carry then.
struct OwnedSettings<Content: View>: View {
    /// The row these belong to, so a screen reader and a scripted walk can say
    /// whose Blur they mean.
    let owner: String
    @ViewBuilder var content: Content

    /// How thick the bracket is. Named because the offsets below have to take
    /// half of it back to centre the rule on the tick, and the whole of it back
    /// to land the settings in the panel's one column of names.
    static var ruleWidth: CGFloat { 2 }

    /// How far in the rule itself sits: hung on the tick of the row above it.
    /// The tick is that row's leading column now, so its middle is
    /// `ColorPartLayout.tickCenter` in and the rule only has to give back half
    /// its own width to sit exactly under it. One number, read by both lists,
    /// so neither can drift from the other.
    static var ruleLeading: CGFloat { ColorPartLayout.tickCenter - ruleWidth / 2 }

    /// How far the settings sit from the rule. Not a taste: it is whatever
    /// lands them in the SAME column the row names are in, so Softness starts
    /// where Shadow starts and Width starts where Outline starts. The panel
    /// then has exactly two left edges — the ticks, and everything else — and
    /// the rule reads as a bracket in the gap between them. Before this the
    /// settings sat nine points LEFT of the names above them, which read as a
    /// child less indented than its parent.
    static var settingsGap: CGFloat { ColorPartLayout.nameLeading - ruleLeading - ruleWidth }

    var body: some View {
        HStack(alignment: .top, spacing: Self.settingsGap) {
            // The bracket. It runs the full height of what it owns, so two
            // shadows one under the other never blur into one block.
            RoundedRectangle(cornerRadius: 1)
                .fill(.quaternary)
                .frame(width: Self.ruleWidth)
            VStack(alignment: .leading, spacing: 6) { content }
        }
        .padding(.leading, Self.ruleLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(owner) settings")
    }
}

/// The one setting the outline has: how thick it is.
///
/// Two rings underneath — a shape strokes its own path, everything else takes a
/// ring round its box — and one row, because nothing a person does differs. It
/// is no longer called Thickness: the word said nothing about which of a
/// rectangle's two edges it moved, and inside the Outline part its meaning
/// comes from the part it sits in.
private struct PartWidthRow: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerPartRow

    var body: some View {
        if row.mixesLineKinds {
            // A shape and a picture picked together. Two rings underneath, one
            // number: the slider reads whichever line each layer actually has
            // and writes back the same way, so 6 pt means 6 pt on both.
            ShapeSlider(layerIDs: row.widthIDs, label: "Width",
                        reading: editorState.outlineWidthReading(ids: row.widthIDs),
                        range: AnnotationStyles.strokeWidthRange,
                        format: { "\(Int($0.rounded())) pt" },
                        preview: { editorState.previewRingWidth(ids: $0, $1) },
                        commit: { editorState.commitRingWidth(ids: $0, $1) })
        } else if row.slot == .border {
            let borders = editorState.layerStyleSelection.borders
            LayerStyleSlider(layerIDs: row.widthIDs, label: "Width",
                             reading: borders.number { $0.borderWidth },
                             range: 1...20,
                             format: { "\(Int($0.rounded())) pt" },
                             field: .border) { style, v in
                style.borderWidth = CGFloat(v)
            }
        } else {
            ShapeSlider(layerIDs: row.widthIDs, label: "Width",
                        reading: editorState.shapeSelection.outlineWidth,
                        range: AnnotationStyles.strokeWidthRange,
                        format: { "\(Int($0.rounded())) pt" },
                        preview: { editorState.previewOutlineWidth(ids: $0, $1) },
                        commit: { editorState.commitOutlineWidth(ids: $0, $1) })
        }
    }
}


/// The outline's other setting: WHERE it sits on the layer's edge.
///
/// A line is one line drawn in a different place rather than three different
/// effects, so it is one popup under the Width and not three rows
/// (`docs/design/shape-parts.md`, "How the list grows"). It is drawn exactly
/// like the shadow's Kind, because it is exactly the same idea: one thing, a
/// choice of where it goes.
///
/// It is simply absent where the choice would mean nothing. A line and an arrow
/// ARE their stroke, and a letter's outline follows the letters, so those show
/// a Width and stop there rather than a popup that does nothing.
private struct PartPositionRow: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerPartRow

    var body: some View {
        let ids = editorState.outlinePositionIDs(ids: row.widthIDs)
        if !ids.isEmpty {
            let reading = editorState.outlinePositionReading(ids: ids)
            HStack(alignment: .firstTextBaseline, spacing: ColorPartLayout.spacing) {
                Text("Position")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: ColorPartLayout.labelWidth, alignment: .leading)
                Picker("Position", selection: Binding(
                    get: { reading.isMixed ? nil : reading.value },
                    set: { new in
                        guard let new else { return }
                        editorState.setOutlinePosition(ids: ids, to: new)
                    })) {
                        if reading.isMixed {
                            Text(LayerStyleSelection.mixedText).tag(BorderPosition?.none)
                        }
                        ForEach(BorderPosition.allCases, id: \.self) { position in
                            Text(position.title).tag(BorderPosition?.some(position))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    // A fixed width for the same reason the shadow's Kind has
                    // one: a menu picker asked for its ideal width inside the
                    // dock's column pushes the whole pane wider than the window.
                    .frame(width: 92, alignment: .leading)
                    .help("Whether the outline sits inside the layer edge, on it, or outside it")
                    .playtestControl("Position",
                                     detail: reading.isMixed ? "mixed"
                                         : (reading.value?.title ?? ""))
                Spacer(minLength: 0)
            }
            // Its own name in a walk, so `panelMenu "Position"` reaches it
            // rather than a second menu called after the part it sits in.
            .playtestField("Position")
        }
    }
}
