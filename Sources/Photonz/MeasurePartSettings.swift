// The settings that hang under a measurement's parts in Appearance: the caliper's thickness, the chip's size, what it reads in, and the width of its ring.

import PhotonzCore
import SwiftUI

/// What a measurement used to keep in a section of its own.
///
/// There was a Measurement section carrying a Role, a Unit, a Thickness, a
/// Label size and three swatches of its own — swatches that could not take a
/// saved colour, while every other colour in the app could. Beside it,
/// Appearance carried the measurement's opacity and nothing else. Two places
/// for one question: what does this thing look like. The user asked on
/// 2026-09-09 for one, right after asking the same for arrows, so every one of
/// those controls moved here, under the PART it belongs to:
///
/// | Was in the Measurement section | Is now under |
/// | --- | --- |
/// | Role | the top of Appearance, above the parts it repaints |
/// | Thickness | Caliper |
/// | Label size | Chip, as Chip size |
/// | Unit | Chip |
/// | Stroke swatch | the Caliper row's own colour |
/// | Chip swatch | the Chip Fill row's own colour |
/// | Text swatch | the Chip Text row's own colour |
/// | — (there was none) | Chip Edge, which is new |
///
/// What did NOT move: the Name field and the Details fold with Copy
/// Measurement. Neither says how a measurement looks — one is what it is
/// called and the other is a grid of read-only numbers — and Appearance is the
/// section for what a thing is MADE OF. They stay in the Measurement section,
/// which now holds no setting at all.
///
/// Each drawer sits behind the same bracket a shadow's settings sit behind
/// (`OwnedSettings`), so what a control belongs to is said by where it is.
struct MeasurePartSettings: View {
    @Environment(EditorState.self) private var editorState
    /// The row these belong to, which is also what decides what they ARE.
    let row: LayerPartRow

    var body: some View {
        let ids = row.colors.first?.layerIDs ?? []
        // `showsSettings` and not just "there are layers": a row whose switch is
        // OFF shows its name and its switch and nothing else, so the width of a
        // ring nobody can see does not sit there pretending to do something.
        // The first build missed this and left a Width slider reading 1 px
        // under a Chip Edge that had just been switched off.
        if !ids.isEmpty, row.showsSettings, let slot = row.slot {
            switch slot {
            case .caliper:
                OwnedSettings(owner: row.title) { thickness(ids) }
            case .chipBorder:
                OwnedSettings(owner: row.title) { edgeWidth(ids) }
            case .chipText:
                // The chip used to guarantee its own legibility: the number was
                // white on a dark pill and nobody could change either. Both are
                // choosable now, and taking the fill away leaves the number on
                // the picture, so the guarantee becomes a sentence rather than
                // a number that quietly disappears.
                if let note = legibilityNote(ids) {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            default:
                EmptyView()
            }
        }
    }

    /// Said under the Chip Text row when the number would be hard to find.
    /// Over several measurements it is said once, because it is a warning
    /// rather than a reading.
    private func legibilityNote(_ ids: [UUID]) -> String? {
        ids.compactMap { editorState.document?.layer(id: $0)?.measure?.chipLegibilityNote }.first
    }

    /// How thick the caliper is drawn. Three whole pixels rather than a slider,
    /// because a redliner measuring a one-pixel hairline wants to say ONE
    /// pixel, and the segments say which are on offer.
    private func thickness(_ ids: [UUID]) -> some View {
        let reading = editorState.measureReading(ids) { $0.strokeWidth }
        return HStack(spacing: 8) {
            Text("Thickness").font(.caption).foregroundStyle(.secondary)
            Picker("Thickness", selection: Binding(
                get: { reading ?? 1 },
                set: { editorState.setMeasureThickness(ids: ids, $0) })) {
                Text("1 px").tag(CGFloat(1))
                Text("2 px").tag(CGFloat(2))
                Text("3 px").tag(CGFloat(3))
            }
            .labelsHidden().pickerStyle(.segmented).controlSize(.small)
            .panelHelp("How thick the caliper is drawn. Its colour is the row above.")
            Spacer(minLength: 0)
        }
        .playtestField("Thickness")
    }

    /// How thick the ring round the chip is. It never reaches zero: taking the
    /// ring off is the switch on the row above, and a slider that could also do
    /// it would be two answers to one question.
    private func edgeWidth(_ ids: [UUID]) -> some View {
        ShapeSlider(layerIDs: ids, label: "Width",
                    reading: StyleReading(value: editorState.measureReading(ids) { $0.chipBorderWidth },
                                          isMixed: editorState.measureIsMixed(ids) { $0.chipBorderWidth }),
                    range: MeasureContent.chipBorderWidthRange,
                    format: { DocumentUnit.text($0) },
                    preview: { editorState.previewMeasureChipBorderWidth(ids: $0, $1) },
                    commit: { editorState.commitMeasureChipBorderWidth(ids: $0, $1) })
            .panelHelp("How thick the ring round the readout chip is. Take it off with the switch.")
    }
}

/// A measurement's chip: how big it is and what it reads in.
///
/// Its own block rather than a drawer under one of the chip's colour rows, for
/// the same reason an arrow's Caption block is: those rows are only there once
/// there IS a chip, and this is what the chip SAYS and how big it says it. It
/// sits directly above them, so the order reads as "what the chip reads, then
/// what it is painted".
struct MeasureChipSettings: View {
    @Environment(EditorState.self) private var editorState
    /// Whether any row in the list has a tick, so this block's name starts in
    /// the same column as the names beside the ticks.
    let leadsWithColumn: Bool

    var body: some View {
        // ONE measurement only, the way the section it came from always was:
        // the label-size slider previews on a single layer, and a unit is
        // something a person sets on the measurement they are looking at.
        if let layer = editorState.selectedMeasureLayer, let c = layer.measure {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: ColorPartLayout.spacing) {
                    PanelRowHead(title: "Chip", leadsWithColumn: leadsWithColumn) {
                        EmptyView()
                    }
                    Spacer(minLength: 0)
                }
                OwnedSettings(owner: "Chip") {
                    chipSize(c)
                    unit(c)
                }
            }
            .playtestField("Chip")
            .panelStartProbe(.row, owner: "Chip")
        }
    }

    /// The readout's size, in the pixels the slider shows rather than the scale
    /// the model keeps, so the number means what it says.
    private func chipSize(_ c: MeasureContent) -> some View {
        // During a drag the committed document has not changed, so read the
        // live preview value or the thumb snaps back.
        let liveScale = editorState.measureLabelPreview?.scale ?? c.labelScale
        let px = liveScale * MeasureContent.labelFontSize
        let lo = Double(MeasureContent.labelSizeRangePx.lowerBound)
        let hi = Double(MeasureContent.labelSizeRangePx.upperBound)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Chip size").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(DocumentUnit.text(px))
                    .font(.caption.monospacedDigit())
                    .panelReadout(DocumentUnit.text(px))
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { Double(px) },
                set: {
                    editorState.previewMeasureLabelScale(CGFloat($0) / MeasureContent.labelFontSize)
                }),
                   in: lo...hi,
                   onEditingChanged: { editing in
                       if !editing {
                           editorState.commitMeasureLabelScale(
                               editorState.measureLabelPreview?.scale ?? c.labelScale)
                       }
                   })
                .controlSize(.small)
                .playtestControl("Slider", detail: "Chip size")
        }
        .playtestField("Chip size")
    }

    /// What the number is read in. Both are pixels; the choice is whether they
    /// are the ones on screen or the ones in the bitmap.
    private func unit(_ c: MeasureContent) -> some View {
        HStack(spacing: 8) {
            Text("Unit").font(.caption).foregroundStyle(.secondary)
            Picker("Unit", selection: Binding(
                get: { c.unit },
                set: { editorState.setMeasureUnit($0) })) {
                Text("Logical").tag(MeasureUnit.points)
                Text("Actual").tag(MeasureUnit.pixels)
            }
            .labelsHidden().pickerStyle(.segmented).controlSize(.small)
            .panelHelp("Both read out in px. Logical is the on-screen size (like CSS px, the "
                  + "default); Actual is raw device pixels, 2× larger on a Retina screenshot.")
            Spacer(minLength: 0)
        }
        .playtestField("Unit")
    }
}

/// What a measurement calls out: a size, or a spacing.
///
/// It sits at the TOP of Appearance, above the parts, because switching it
/// repaints every one of them from that role's remembered set. An alignment
/// guide is its own kind of measurement and offers no role at all.
struct MeasureRoleRow: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        if Experiments.shared.measureRolesEnabled,
           let c = editorState.selectedMeasureLayer?.measure, c.alignment == nil {
            HStack(spacing: 8) {
                Text("Role").font(.caption).foregroundStyle(.secondary)
                Picker("Role", selection: Binding(
                    get: { c.role },
                    set: { editorState.setMeasureRole($0) })) {
                    Text("Size").tag(MeasureRole.size)
                    Text("Spacing").tag(MeasureRole.spacing)
                }
                .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                .panelHelp("What this measurement calls out. Switching applies that role's "
                      + "remembered colors, and new measurements start with the last-used role.")
                Spacer(minLength: 0)
            }
            .playtestField("Role")
            .panelStartProbe(.row, owner: "Role")
        }
    }
}

extension EditorState {
    /// What a set of measurements agree on for one of their numbers, or nil
    /// while they disagree, so a control over two calipers reads honestly.
    func measureReading(_ ids: [UUID], _ value: (MeasureContent) -> CGFloat) -> CGFloat? {
        let numbers = ids.compactMap { document?.layer(id: $0)?.measure }.map(value)
        guard let first = numbers.first else { return nil }
        return numbers.allSatisfy { $0 == first } ? first : nil
    }

    /// Whether they disagree about it.
    func measureIsMixed(_ ids: [UUID], _ value: (MeasureContent) -> CGFloat) -> Bool {
        let numbers = ids.compactMap { document?.layer(id: $0)?.measure }.map(value)
        guard let first = numbers.first else { return false }
        return !numbers.allSatisfy { $0 == first }
    }
}
