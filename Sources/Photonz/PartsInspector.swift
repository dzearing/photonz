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
            // has no tick to lead with and it does not pretend to: it starts on
            // the panel's own margin like every other row, and its track runs
            // the full width. It used to step in by the width of the tick
            // column to line its label up with the names beside the ticks,
            // which put the section's content 24pt further in than its own
            // heading (reported by the user, 2026-09-08).
            opacity
                .panelStartProbe(.row, owner: "Opacity")
            // A measurement's Role, right under it: it is a preset for every
            // colour below it, so it reads as "what this calls out, then what
            // that is painted" (`MeasurePartSettings`).
            if Experiments.shared.shapePartsEnabled { MeasureRoleRow() }
            let column = rows.contains(where: \.hasSwitch)
            ForEach(rows) { row in
                // The tick column is held open across the whole list, or not at
                // all: over a box the Fill row has a tick and everything lines
                // up beside it, while over an arrow nothing here can be
                // switched, so there is no column and the Colour row starts on
                // the panel's own margin like the slider above it.
                //
                // The arrow's label block goes in front of the first of the
                // label's colour rows, so the words come before what they are
                // painted. See `ArrowLabelSettings`.
                if row.id == firstLabelRowID(rows) { ArrowLabelSettings(leadsWithColumn: column) }
                // ...and a measurement's chip block goes in front of the first
                // of ITS colour rows, for the same reason.
                if row.id == firstChipRowID(rows) { MeasureChipSettings(leadsWithColumn: column) }
                VStack(alignment: .leading, spacing: 6) {
                    PartRowView(row: row, leadsWithColumn: column)
                    // What used to be the arrow's own section, folded under the
                    // part each control belongs to (`ShapePartSettings`), and
                    // the same for a measurement's (`MeasurePartSettings`).
                    if Experiments.shared.shapePartsEnabled {
                        ShapePartSettings(row: row)
                        MeasurePartSettings(row: row)
                    }
                }
            }
            // ...and when there is no label yet there are no label rows to go
            // in front of, so the block lands after everything the arrow does
            // have. This is the state where the Caption field is the whole
            // point: it is the only way to give an arrow a label from here.
            if firstLabelRowID(rows) == nil {
                ArrowLabelSettings(leadsWithColumn: column)
            }
            // ...and a corner radius only where there are corners. An ellipse
            // has none, so it shows no row rather than a slider that does
            // nothing to what you have picked.
            if !corners.isEmpty {
                // Another label over a track, and like Opacity it begins on the
                // panel's margin rather than under the name column.
                VStack(alignment: .leading, spacing: 2) {
                    CornerRadiusRow(selection: corners)
                    if let note = corners.note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .panelStartProbe(.row, owner: "Corner Radius")
            }
            // Where the row would have been, when a copy handed its roundness
            // to a knob. A row that simply vanishes is a hole in the panel, so
            // the section names the control that owns the number and where it
            // is, the way the Layout section names Edit Original.
            if let rounding = editorState.instanceRoundingNote {
                Text(rounding)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .panelStartProbe(.row, owner: "Rounding note")
            }
            ArrowLabelPlacementReset()
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .panelStartProbe(.row, owner: "Appearance note")
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
    }

    /// The first of the label's three colour rows, which is where the arrow's
    /// label block goes in front of. Nil when the picked arrows have no words,
    /// so those rows are not there at all.
    private func firstLabelRowID(_ rows: [LayerPartRow]) -> String? {
        rows.first { row in
            guard let slot = row.slot else { return false }
            return slot == .captionFill || slot == .captionBorder || slot == .captionText
        }?.id
    }

    /// The first of the chip's three colour rows, which is where a
    /// measurement's chip block goes in front of. Nil when the picked
    /// measurement has no readout, so those rows are not there at all.
    private func firstChipRowID(_ rows: [LayerPartRow]) -> String? {
        rows.first { row in
            guard let slot = row.slot else { return false }
            return slot == .chipFill || slot == .chipBorder || slot == .chipText
        }?.id
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
    ///
    /// It used to promise that everything here reached every picked layer,
    /// full stop. That stopped being true the day a row only some of them have
    /// started showing its colour: the Fill row over five boxes where three
    /// are filled paints those three, and says so in its own line two lines
    /// above this one. So the promise names its own exception rather than
    /// being contradicted by the row above it.
    private var caption: String? {
        let count = editorState.colorStyleSelectionCount
        guard count > 1 else { return nil }
        return "\(count) layers. What you set here reaches every one of them, "
            + "in one step, unless a row says underneath how many it reaches."
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
///
/// "Off" means NONE of the picked layers has the part. A row where three of
/// five boxes are filled is not off, it is a row speaking for three, so it
/// shows their colour and painting it paints those three — the shared rule for
/// a control that reaches some of what is picked (`UX-PATTERNS.md`, "What a
/// control DOES for several picked things"). It used to show the word Mixed
/// and nothing else, which left the switch as the only move on offer and the
/// switch fills all five (found by the audit of 2026-09-06,
/// `switch-says-mixed`).
private struct PartRowView: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerPartRow
    /// Whether ANY row in this list has a tick, which is what decides whether
    /// the list has a leading column at all. See `PanelRowHead`.
    let leadsWithColumn: Bool

    /// What is being held over this row right now, while it is switched off.
    /// Nil the rest of the time, and whenever what is in the air is not a
    /// colour.
    @State private var incoming: ColorDrop.Answer?

    /// Whether this row has a colour to show: one of the picked layers has the
    /// part, or the colour is a property rather than a part — a line's ink, a
    /// letter's ink — which can never be absent. Read off the row itself, so
    /// what the panel draws and what a colour picked here reaches are the one
    /// answer (`LayerPartRow.showsSettings`).
    private var showsColor: Bool { row.showsSettings }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: ColorPartLayout.spacing) {
                // The tick and then the name, in that order, from the one place
                // the panel's columns live. A part with nothing to switch — a
                // line's ink, a letter's ink — still holds the tick column open,
                // so its name starts on the same line as everybody else's.
                PanelRowHead(title: row.title, leadsWithColumn: leadsWithColumn) {
                    if row.hasSwitch { partSwitch }
                }
                if showsColor {
                    // The colour of the layers that HAVE the part, whether that
                    // is all of them or three of five. The well itself says
                    // Mixed when those three disagree about the colour, and the
                    // line under the row says how many of the picked layers the
                    // row is speaking for, so the two questions keep their own
                    // words.
                    colorControl
                } else if let paint = incoming?.landing?.paint {
                    // A colour is over the row: this is where it would land,
                    // wearing it, so letting go is never a guess.
                    LandingSwatch(paint: paint)
                }
                Spacer(minLength: 0)
            }
            // The whole row takes the drop only while NOBODY has the part,
            // because then there is no swatch to aim at and a person carrying a
            // colour aims at the row's NAME. The moment one of them has it the
            // swatch is back and takes the colour itself: two drop targets
            // stacked on one row would fight over the same pointer, and they
            // would promise two different things — the row gives the part to
            // every picked layer, the swatch paints the ones that have it.
            // Nothing is drawn here at rest.
            .modifier(OffPartColorDrop(row: row, active: !showsColor, incoming: $incoming))
            if let note = row.reachNote {
                // On the panel's margin, like everything else in the section.
                // It used to be padded in under the row's NAME so it read as
                // belonging to the row rather than to the list; that put a
                // second left edge inside the section, which is the thing the
                // user reported on 2026-09-08. It is a line of small grey type
                // directly under the row it is about, one gap below and a gap
                // and a half above the next, so what it belongs to is already
                // said by where it sits.
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Every row holds a control called Switch and one called Color, so the
        // row's own word is what tells the outline's from the fill's:
        // `press "Switch" in "Outline"`.
        .playtestField(row.title)
        .panelStartProbe(.row, owner: row.title)
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
            .panelHelp(switchHelp)
            .playtestControl("Switch",
                             detail: row.isMixed ? "mixed" : (row.isOn ? "on" : "off"))
    }

    private func setOn(_ on: Bool) {
        switch row.part {
        case .fill:
            editorState.setColorEnabled(slot: .fill, on: on)
        case .captionFill:
            editorState.setColorEnabled(slot: .captionFill, on: on)
        case .captionBorder:
            editorState.setColorEnabled(slot: .captionBorder, on: on)
        case .chipFill:
            editorState.setColorEnabled(slot: .chipFill, on: on)
        case .chipBorder:
            editorState.setColorEnabled(slot: .chipBorder, on: on)
        case .arrowHead, .shadow, nil:
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
                // The one thing in a panel allowed to step in past the margin,
                // so a walk can say in numbers that it steps in ONCE and lands
                // under the name it belongs to.
                .panelStartProbe(.subsection, owner: owner)
        }
        .padding(.leading, Self.ruleLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(owner) settings")
    }
}
