import PhotonzCore
import SwiftUI

/// The parts a layer is made of, as one list (`next-shape-parts`).
///
/// Every part works the same way: a tick that switches it on or off, the colour
/// it paints, and its own settings on the lines underneath. Learn to take the
/// outline off a box and you already know how to take its fill off, and how to
/// add whatever part arrives next.
///
/// It replaces four ways of asking the same question. A rectangle used to carry
/// a Fill checkbox in Color, an Outline colour beside it with NO switch at all,
/// a Thickness slider in a section named after the shape, and a shadow behind a
/// switch in a section of its own — so there was no way to draw a box with no
/// ring round it, which is what the user hit on 2026-09-06.
///
/// The layout is one list, and a part that is switched on shows its settings
/// on the lines directly below it, in the same column as every other row.
/// Ticking a part is already the person saying they want it, so there is
/// nothing left to press: no chevron, no remembering which row is open, no
/// indent. Parts are told apart by the gap between them rather than by a step
/// to the right, so a switched on part and its settings read as one block
/// (asked for by the user on 2026-09-06, replacing the fold that shipped the
/// day before).
///
/// The model itself — what a part is, which parts a layer has — is
/// `PhotonzCore/LayerParts.swift` and `docs/design/shape-parts.md`.
struct PartsInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let rows = editorState.layerPartRows
        // Wider than the gap inside a part (6), so the eye groups a part with
        // the settings under it without either being pushed off the margin.
        VStack(alignment: .leading, spacing: 16) {
            ForEach(rows) { row in
                PartRowView(row: row)
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
                Text(row.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: ColorPartLayout.labelWidth,
                           height: ColorPartLayout.rowHeight, alignment: .leading)
                // Always this wide, blank or not, so every colour in the list
                // starts at the same left edge whether its part has a switch.
                Group {
                    if row.hasSwitch { partSwitch } else { Color.clear }
                }
                .frame(width: ColorPartLayout.switchWidth,
                       height: ColorPartLayout.rowHeight, alignment: .leading)
                if isOn {
                    colorControl
                } else if let paint = incoming?.landing?.paint {
                    // A colour is over the row: this is where it would land,
                    // wearing it, so letting go is never a guess.
                    landingSwatch(paint)
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
            // Out at the margin with the settings: everything a row has to say
            // below itself shares one left edge, so nothing under a part is a
            // step further in than anything else under it.
            if let note = row.reachNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsSettings { settings }
        }
        // Every row holds a control called Switch and one called Color, so the
        // row's own word is what tells the outline's from the fill's:
        // `press "Switch" in "Outline"`.
        .playtestField(row.title)
    }

    /// The colour about to land, drawn where this row's swatch would be: the
    /// same 18pt square in the same column, ringed the way every swatch in the
    /// panel rings while a colour is over it.
    private func landingSwatch(_ paint: Paint) -> some View {
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
        case .shadow:
            editorState.setSelectionShadowEnabled(on)
        case nil:
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
        } else {
            // The shadow's colour is not one of the layer's slots, so it has no
            // saved-styles menu; the well alone sits where every other colour
            // in the list sits.
            ShadowColorWell()
                .frame(minWidth: ColorPartLayout.readoutWidth,
                       minHeight: ColorPartLayout.rowHeight, alignment: .leading)
        }
    }

    // MARK: The settings

    @ViewBuilder private var settings: some View {
        switch row.part {
        case .shadow:
            // Everything about the shadow except the switch and the colour,
            // which are up on the row with every other part's.
            ShadowInspector(showsSwitch: false, showsColor: false, inset: false)
        default:
            PartWidthRow(row: row)
        }
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
