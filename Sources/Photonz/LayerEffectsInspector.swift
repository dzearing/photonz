// The effects and shadow sections of the panel: opacity, blur, corner radius, border, and every part of a layer's shadow.

import PhotonzCore
import SwiftUI

// MARK: - Effects & shadow inspectors

/// Non-destructive effects for EVERYTHING picked: opacity, blur, corner
/// radius, border. One pull rounds four buttons, and one undo puts all four
/// back. Where the picked layers differ the readout says Mixed rather than
/// printing one of their numbers as if it spoke for the rest.
struct EffectsInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let selection = editorState.layerStyleSelection
        let ids = selection.layerIDs
        VStack(alignment: .leading, spacing: 8) {
            LayerStyleSlider(layerIDs: ids, label: "Opacity",
                             reading: selection.reading { $0.opacity }, range: 0...1,
                             format: { "\(Int(($0 * 100).rounded()))%" },
                             field: .opacity) { style, v in
                style.opacity = v
            }
            LayerStyleSlider(layerIDs: ids, label: "Blur",
                             reading: selection.number { $0.blurRadius }, range: 0...50,
                             format: points, field: .blur) { style, v in
                style.blurRadius = CGFloat(v)
            }
            // ONE Corner Radius, for every way of rounding. A rectangle curves
            // the outline it draws; a screenshot or a frame has its corners
            // masked off. Both used to have a slider of their own, both called
            // Corner Radius, sitting in different sections of the same panel.
            CornerRadiusRow(selection: editorState.cornerRadiusSelection)
            // The width only. The color a border is painted is a color like any
            // other, so it lives in the Color section with the rest rather than
            // in a swatch of its own down here — and the moment this slider
            // leaves zero, the Border row is up there waiting.
            //
            // Offered only to layers with no line of their own. A shape strokes
            // its own outline, and at the same width the two rings are the same
            // pixels, so a rectangle used to carry two sliders for one ring with
            // the border quietly covering the stroke. A shape's width is the
            // Thickness row in its own section now; see `OutlineWidth.swift`.
            // With `next-shape-parts` on, this ring is the Outline part and its
            // width sits with its own switch and colour up in Appearance.
            let borders = Experiments.shared.shapePartsEnabled
                ? LayerStyleSelection(members: [], selectionCount: selection.selectionCount)
                : selection.borders
            if !borders.isEmpty {
                LayerStyleSlider(layerIDs: borders.layerIDs, label: "Border",
                                 reading: borders.number { $0.borderWidth }, range: 0...20,
                                 format: points, field: .border) { style, v in
                    style.borderWidth = CGFloat(v)
                }
                .panelHelp("The color of the border is in the Color section above")
                // Said under the row it is about, the way the Color rows say
                // it, so it cannot be read as speaking for the whole section:
                // Opacity and Blur still reach every picked layer.
                if let reach = borderReachNote(selection, borders) {
                    Text(reach)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // "A slider here changes every one of them" is a promise Border
            // cannot keep when a shape is picked with something that can take
            // one, so in that case the caption claims only the rest.
            SelectionStyleNotes(notes: [selection.note],
                                caption: selectionCaption(
                                    selection.count,
                                    borders.count == selection.count || borders.isEmpty
                                        ? "A slider here" : "Every other slider here"))
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
    }

    /// What the Border row says out loud when a shape is picked alongside
    /// something that can take one. Nothing when the row is not there at all:
    /// a lone rectangle is not missing a Border, it has its Thickness.
    private func borderReachNote(_ selection: LayerStyleSelection,
                                 _ borders: LayerStyleSelection) -> String? {
        guard !borders.isEmpty, borders.count < selection.count else { return nil }
        let shapes = selection.count - borders.count
        let verb = shapes == 1 ? "draws its own outline" : "draw their own outline"
        return "Border applies to \(borders.count) of the \(selection.count) selected layers. "
            + "The other \(shapes == 1 ? "one" : "\(shapes)") \(verb): use Thickness."
    }
}

/// The picked layers' shadow: a switch plus, when one is on, blur (softness),
/// size (spread), distance (offset), direction (angle), opacity, and color
/// (10.6) — all of them over the whole selection.
struct ShadowInspector: View {
    @Environment(EditorState.self) private var editorState
    /// Whether the section draws its own on/off switch. The parts list
    /// (`next-shape-parts`) puts that switch up on the Shadow row with every
    /// other part's, and borrows only the rows below it.
    var showsSwitch = true
    /// Same for the colour, which sits on the row in the parts list.
    var showsColor = true
    /// Whether this is a section of its own, with a section's padding. Inside
    /// the parts list the list supplies the margins, so the shadow's rows sit
    /// in the same column as every part above them.
    var inset = true
    /// Which of the layer's shadows these rows are for, nearest the eye first.
    /// A layer can throw more than one since the Appearance list became a list
    /// you add to; the Shadow section of the old panel only ever means the
    /// first one.
    var index = 0

    var body: some View {
        // The layers that have a shadow to talk about. A label whose halo its
        // surface draws for it is not one of them: a switch reading "on" there
        // would be describing a shadow nobody can see, so off is the truth and
        // switching it on gives that label a real shadow.
        let selection = editorState.layerStyleSelection
        let shadows = selection.shadows(at: index)
        let ids = shadows.layerIDs
        VStack(alignment: .leading, spacing: 8) {
            let isMixed = selection.shadowIsMixed
            // The way back for a copy that has picked its own shadow, when
            // there is one. Worked out up here because with the switch up on
            // the parts row this line has nothing else on it, and an empty
            // line still takes its spacing: it pushed Blur further from the
            // Shadow row than Width sits from Outline.
            let revert: UUID? = soleLayerID(selection.layerIDs).flatMap {
                editorState.isInstanceStyleOwn(instance: $0, field: .shadow) ? $0 : nil
            }
            if showsSwitch || revert != nil {
                HStack(spacing: 6) {
                    if showsSwitch {
                        // The caption is the switch's own, and it is out here
                        // rather than inside the Toggle so that the one step
                        // quieter below lands on the switch alone: a caption
                        // dimmed with it would fade into the notes around it.
                        Text("Enable Shadow").font(.caption).foregroundStyle(.secondary)
                        Toggle("", isOn: Binding(
                            // A switch has on and off and nothing else, so while
                            // the picked layers disagree it shows neither: the
                            // first press resolves to ON for all of them, the way
                            // a mixed checkbox has always behaved here, and it
                            // never returns to Mixed, because Mixed is a report
                            // about the selection rather than a state anyone sets.
                            get: { isMixed ? false : selection.hasShadowEverywhere },
                            set: { editorState.setSelectionShadowEnabled(isMixed ? true : $0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .accessibilityLabel("Enable Shadow")
                        // Off is a true answer — none of them have one — so a
                        // disagreeing selection may not wear it at full strength.
                        .opacity(isMixed ? MixedLook.controlOpacity : 1)
                        .panelHelp(shadowSwitchHelp(selection, isMixed: isMixed))
                        .playtestControl("Enable Shadow",
                                         detail: isMixed ? "Shadow, mixed"
                                             : (selection.hasShadowEverywhere ? "Shadow, on" : "Shadow, off"))
                        // The word goes beside the switch, since there is no room
                        // for it inside one, and after it rather than between it
                        // and its caption so that nothing moves on a selection
                        // that agrees.
                        if isMixed { MixedWord() }
                    }
                    // A shadow is ONE part of the look: its softness, size,
                    // distance, direction, opacity and colour are six controls for
                    // the one thing a person means by "the shadow", so there is one
                    // way back rather than six identical arrows.
                    if let revert {
                        InstanceStyleRevert(layerID: revert, field: .shadow)
                    }
                    Spacer(minLength: 0)
                }
            }
            // Said BEFORE the rows, not after them, because a switch reading
            // off above six rows full of numbers is a contradiction until you
            // know only some of the picked layers have a shadow. Said first,
            // it is the sentence that makes the rows make sense.
            //
            // Only where the switch it describes is actually here. Borrowed by
            // the Effects list, these rows are settings hanging under a row
            // whose tick lives up on that row and reaches ONLY the layers that
            // hold the effect, so this sentence printed a second count under
            // the row's own and then promised something untrue: "the switch
            // gives the rest one too" (found on the probe, 2026-09-08). The
            // list's row says its reach itself.
            if showsSwitch, let reach = shadowReachNote(selection, shadows) {
                Text(reach)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !shadows.isEmpty {
                let at = index
                HStack(spacing: 8) {
                    // Called Softness in the Effects list, where a row called
                    // Blur can be sitting right above it: two controls with one
                    // word between them is exactly what the user reported on
                    // 2026-09-07. The rule down the side of these settings
                    // already says whose they are; the name says what it does.
                    // Current, where there is no Blur row to collide with, is
                    // untouched.
                    LayerStyleSlider(layerIDs: ids,
                                     label: Experiments.shared.shapePartsEnabled
                                         ? "Softness" : "Blur",
                                     reading: shadows.number { $0.shadow(at: at)?.radius ?? 0 },
                                     range: 0...40, format: points) { style, v in
                        style.updateShadow(at: at) { $0.radius = CGFloat(v) }
                    }
                    if showsColor { ShadowColorWell(index: at) }
                }
                LayerStyleSlider(layerIDs: ids, label: "Size",
                                 reading: shadows.number { $0.shadow(at: at)?.spread ?? 0 },
                                 range: 0...80, format: points) { style, v in
                    style.updateShadow(at: at) { $0.spread = CGFloat(v) }
                }
                LayerStyleSlider(layerIDs: ids, label: "Distance",
                                 reading: shadows.number { $0.shadow(at: at)?.distance ?? 0 },
                                 range: 0...40, format: points) { style, v in
                    // Each layer keeps the way its own shadow points; only how
                    // far it is thrown is set from here.
                    style.updateShadow(at: at) { $0.setDistance(CGFloat(v)) }
                }
                LayerStyleSlider(layerIDs: ids, label: "Direction",
                                 reading: shadows.number { $0.shadow(at: at)?.directionDegrees ?? 90 },
                                 range: 0...360,
                                 format: { "\(Int($0.rounded()))°" }) { style, v in
                    style.updateShadow(at: at) { $0.setDirectionDegrees(CGFloat(v)) }
                }
                LayerStyleSlider(layerIDs: ids, label: "Opacity",
                                 reading: shadows.reading { $0.shadow(at: at)?.opacity ?? 0 },
                                 range: 0...1,
                                 format: { "\(Int(($0 * 100).rounded()))%" }) { style, v in
                    style.updateShadow(at: at) { $0.opacity = v }
                }
                SelectionStyleNotes(notes: [showsColor ? shadowColorNote(shadows, at: at) : nil],
                                    caption: nil)
            }
        }
        .padding(.horizontal, inset ? 14 : 0)
        .padding(.vertical, inset ? 8 : 0)
    }

    /// How many of the picked layers this section is talking to, in words,
    /// and what the switch does with the rest.
    private func shadowReachNote(_ selection: LayerStyleSelection,
                                 _ shadows: LayerStyleSelection) -> String? {
        let picked = selection.count
        let shadowed = shadows.count
        guard picked > 1 else { return nil }
        if shadowed == 0 {
            return "\(picked) layers. Switching this on shadows every one of them, in one step."
        }
        if shadowed == picked {
            return "\(picked) layers. A slider here changes every one of them, in one step."
        }
        let verb = shadowed == 1 ? "has" : "have"
        return "\(shadowed) of the \(picked) selected layers \(verb) a shadow. "
            + "The rows below change those; the switch gives the rest one too."
    }

    private func shadowSwitchHelp(_ selection: LayerStyleSelection,
                                  isMixed: Bool) -> String {
        // While they disagree the switch has no state to turn off, so the tip
        // says what the press it CAN take would do.
        if isMixed { return "Gives all \(selection.count) of them a shadow" }
        return selection.count > 1
            ? "Turns the shadow on or off for all \(selection.count) of them"
            : "Turns the shadow on or off"
    }

    private func shadowColorNote(_ shadows: LayerStyleSelection, at index: Int) -> String? {
        guard shadows.reading({ $0.shadow(at: index)?.colorHex ?? "#000000" }).isMixed else { return nil }
        return "Shadow colors differ. Picking one paints them all."
    }
}

/// What the shadow is painted, over every picked layer that has one.
///
/// Its own view because it sits in two places: beside Blur in the Shadow
/// section, and on the Shadow row of the parts list, where every other part
/// keeps its colour.
struct ShadowColorWell: View {
    @Environment(EditorState.self) private var editorState
    /// Which shadow in the layer's list this well paints.
    var index = 0

    var body: some View {
        let at = index
        let shadows = editorState.layerStyleSelection.shadows(at: at)
        let ids = shadows.layerIDs
        let reading = shadows.reading { $0.shadow(at: at)?.colorHex ?? "#000000" }
        // The same picker every other color row opens. A shadow keeps its own
        // Opacity slider in its settings, so the picker is not offered a second
        // one that would fight with it.
        ColorWellButton(hex: reading.value ?? "#000000",
                        name: "Shadow",
                        supportsOpacity: false,
                        // The same preview-and-commit path the Blur and Size
                        // sliders take, so a shadow recolours under the drag
                        // and lands in one step.
                        onPreview: { hex in
            editorState.previewLayerStyle(ids: ids) { $0.updateShadow(at: at) { $0.colorHex = hex } }
        }) { hex in
            editorState.previewLayerStyle(ids: ids) { $0.updateShadow(at: at) { $0.colorHex = hex } }
            editorState.commitLayerStyle(ids: ids)
            editorState.recordRecentColor(hex: hex)
        }
        .disabled(ids.isEmpty)
    }
}
