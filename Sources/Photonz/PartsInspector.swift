import PhotonzCore
import SwiftUI

/// The parts a layer is made of, as one list (`next-shape-parts`).
///
/// Every part works the same way: a tick that switches it on or off, the colour
/// it paints, and its own settings folding open underneath. Learn to take the
/// outline off a box and you already know how to take its fill off, and how to
/// add whatever part arrives next.
///
/// It replaces four ways of asking the same question. A rectangle used to carry
/// a Fill checkbox in Color, an Outline colour beside it with NO switch at all,
/// a Thickness slider in a section named after the shape, and a shadow behind a
/// switch in a section of its own — so there was no way to draw a box with no
/// ring round it, which is what the user hit on 2026-09-06.
///
/// The layout is the one the user picked on the decision card: one list, with
/// the settings folding open under the row you click and folding away when you
/// click another. It keeps the panel the same height whatever is switched on,
/// which is what stops a shadow's five sliders pushing the sections below it
/// off the bottom of the dock.
///
/// The model itself — what a part is, which parts a layer has — is
/// `PhotonzCore/LayerParts.swift` and `docs/design/shape-parts.md`.
struct PartsInspector: View {
    @Environment(EditorState.self) private var editorState

    /// Which part is unfolded. Remembered across selections and across
    /// launches: someone who works in shadows all afternoon should not have to
    /// open the shadow again on every box they click.
    @AppStorage("inspector.openPart") private var openPart = ""

    var body: some View {
        let rows = editorState.layerPartRows
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { row in
                PartRowView(row: row, isOpen: openPart == row.id) {
                    // Clicking the open part closes it, so the panel can be put
                    // back the way it was without hunting for another row.
                    openPart = openPart == row.id ? "" : row.id
                }
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

/// One part: its name, its switch, its colour, and the chevron that opens its
/// settings.
///
/// A part that is switched off shows its name and its switch and NOTHING else.
/// That is the whole point of the switch: off has to look off, so the colour
/// and the settings of an outline nobody can see are not sitting there
/// pretending to do something.
private struct PartRowView: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerPartRow
    let isOpen: Bool
    let toggleOpen: () -> Void

    /// Whether this part is showing anything at all. A colour that is a
    /// property rather than a part — a line's ink, a letter's ink — has no
    /// switch and is therefore always on.
    private var isOn: Bool { row.hasSwitch ? row.isOn : true }

    /// Whether there is anything to unfold: only while the part is on, since
    /// the settings of an absent part are settings for nothing.
    private var opens: Bool { isOn && row.hasSettings }

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
                    // The name is part of the chevron's target: a 16pt arrow at
                    // the far end of the row is a small thing to hit for the
                    // most common move in the section.
                    .contentShape(Rectangle())
                    .onTapGesture { if opens { toggleOpen() } }
                // Always this wide, blank or not, so every colour in the list
                // starts at the same left edge whether its part has a switch.
                Group {
                    if row.hasSwitch { partSwitch } else { Color.clear }
                }
                .frame(width: ColorPartLayout.switchWidth,
                       height: ColorPartLayout.rowHeight, alignment: .leading)
                if isOn { colorControl }
                Spacer(minLength: 0)
                if opens { chevron }
            }
            if let note = row.reachNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, ColorPartLayout.labelWidth + ColorPartLayout.spacing)
            }
            if opens, isOpen {
                settings
                    .padding(.leading, ColorPartLayout.labelWidth + ColorPartLayout.spacing)
                    .transition(.opacity)
            }
        }
        // Every row holds a control called Switch and one called Color, so the
        // row's own word is what tells the outline's from the fill's:
        // `press "Switch" in "Outline"`.
        .playtestField(row.title)
    }

    // MARK: The switch

    @ViewBuilder private var partSwitch: some View {
        Toggle(row.title, isOn: Binding(get: { row.isOn }, set: { setOn($0) }))
            .labelsHidden()
            .controlSize(.small)
            .help(switchHelp)
            .playtestControl("Switch", detail: row.isOn ? "on" : "off")
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
        return row.switchIDs.count > 1
            ? "Turns the \(noun) on or off for all \(row.switchIDs.count) of them"
            : "Turns the \(noun) on or off"
    }

    // MARK: The colour

    @ViewBuilder private var colorControl: some View {
        if let slot = row.slot {
            ColorStyleRow(slot: slot, part: row.title)
            // The way back for a copy of a component that has picked its own
            // ring colour. It sits with the colour it undoes, which is here.
            if slot == .border, let only = soleLayerID(row.switchIDs) {
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

    @ViewBuilder private var chevron: some View {
        Button(action: toggleOpen) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .frame(width: 16, height: ColorPartLayout.rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOpen ? "Hide the \(row.title.lowercased()) settings"
                     : "Show the \(row.title.lowercased()) settings")
        .playtestControl("Settings", detail: isOpen ? "open" : "closed")
    }

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
        if row.slot == .border {
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
