// The settings for a picked measurement: its unit, its label, its colour and the document's pixel scale.

import PhotonzCore
import SwiftUI

/// Docked per-layer measure inspector: what a measurement is CALLED and what it
/// reads, which is all that is left here.
///
/// Everything that says how a measurement LOOKS moved into Appearance on
/// 2026-09-09, under the part it belongs to: the Role above the parts, the
/// Thickness under Caliper, the Chip size and the Unit under a Chip block, and
/// the three swatches replaced by the Caliper, Chip Fill, Chip Edge and Chip
/// Text rows, each with the same colour control every other part in the app
/// has (`MeasurePartSettings.swift`). What stays is the Name and the Details
/// fold, neither of which is a setting.
///
/// The release WITHOUT the parts split keeps this section exactly as it was.
struct MeasureInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer
    @State private var nameDraft = ""
    /// Which layer `nameDraft` was typed for. Selecting another measurement
    /// while the field has focus drops focus AFTER `layer` has changed, and
    /// the draft must not land on the new selection.
    @State private var draftLayerID: UUID?
    @FocusState private var nameFocused: Bool
    /// Whether the read-only numbers at the foot of the section are unfolded.
    /// Remembered across selections and across launches, like the parts list's
    /// open row: someone checking coordinates all afternoon should not have to
    /// open the fold again on every measurement they click.
    @AppStorage(MeasureInspector.detailsOpenKey) private var isDetailsOpen = false
    static let detailsOpenKey = "inspector.measureDetailsOpen"

    private var content: MeasureContent? {
        editorState.document?.layer(id: layer.id)?.measure
    }

    /// The name the Measurements row shows: derived until renamed, then the
    /// custom name. The Name field edits exactly this.
    private var displayName: String {
        MeasureSpecList.displayName(for: editorState.document?.layer(id: layer.id) ?? layer)
    }

    /// Whether this section has anything left to show. With the parts split on
    /// and the Measurements panel off there is nothing here at all, and an
    /// empty heading with a name on it is worse than no section.
    static var hasAnyRow: Bool {
        Experiments.shared.measurePanelEnabled || !Experiments.shared.shapePartsEnabled
    }

    /// Whether the controls that moved into Appearance are still drawn here.
    private var showsLookControls: Bool { !Experiments.shared.shapePartsEnabled }

    var body: some View {
        if let c = content {
            VStack(alignment: .leading, spacing: 6) {
                // The same rename the Measurements row offers on double-click
                // (decision D3), reachable from Properties too. It commits
                // through the same call, so it is one undo step either way.
                if Experiments.shared.measurePanelEnabled {
                    row("Name") {
                        TextField("Measurement name", text: $nameDraft)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .focused($nameFocused)
                            .onSubmit { commitName() }
                            .nameFieldKeys(commit: { commitName() },
                                           revert: { nameDraft = displayName })
                            .onChange(of: nameFocused) { _, focused in
                                if !focused { commitName() }
                            }
                            .panelHelp("What this measurement is called in the Measurements "
                                  + "list and the copied spec list")
                    }
                    .id(layer.id)
                    .onAppear {
                        nameDraft = displayName
                        draftLayerID = layer.id
                    }
                    .onChange(of: displayName) { _, name in
                        if !nameFocused { nameDraft = name }
                    }
                }
                // The mock's Role control (§5, `next-measure-roles`): Size vs
                // Spacing, each with its own remembered color set. Alignment
                // guides are their own kind, so they don't offer it.
                if showsLookControls, Experiments.shared.measureRolesEnabled, c.alignment == nil {
                    row("Role") {
                        Picker("Role", selection: Binding(
                            get: { c.role },
                            set: { editorState.setMeasureRole($0) })) {
                            Text("Size").tag(MeasureRole.size)
                            Text("Spacing").tag(MeasureRole.spacing)
                        }
                        .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                        .panelHelp("What this measurement calls out. Switching applies that "
                              + "role's remembered colors, and new measurements start "
                              + "with the last-used role.")
                    }
                }
                if showsLookControls {
                row("Unit") {
                    Picker("Unit", selection: Binding(
                        get: { c.unit },
                        set: { editorState.setMeasureUnit($0) })) {
                        // "Logical" = on-screen/design size (points); "Actual" =
                        // raw bitmap pixels (2× on a Retina screenshot).
                        Text("Logical").tag(MeasureUnit.points)
                        Text("Actual").tag(MeasureUnit.pixels)
                    }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                    .panelHelp("Both read out in px. Logical is the on-screen size (like CSS px, the "
                          + "default); Actual is raw device pixels, 2× larger on a Retina screenshot.")
                }
                row("Thickness") {
                    Picker("Thickness", selection: Binding(
                        get: { c.strokeWidth },
                        set: { editorState.setMeasureThickness($0) })) {
                        Text("1 px").tag(CGFloat(1))
                        Text("2 px").tag(CGFloat(2))
                        Text("3 px").tag(CGFloat(3))
                    }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                }
                row("Label size") {
                    // During a drag the committed doc hasn't changed, so read the
                    // live preview value (else the thumb snaps back / resets).
                    let liveScale = editorState.measureLabelPreview?.scale ?? c.labelScale
                    let px = liveScale * MeasureContent.labelFontSize
                    let lo = Double(MeasureContent.labelSizeRangePx.lowerBound)
                    let hi = Double(MeasureContent.labelSizeRangePx.upperBound)
                    HStack(spacing: 6) {
                        Slider(value: Binding(
                            get: { Double(px) },
                            set: { editorState.previewMeasureLabelScale(CGFloat($0) / MeasureContent.labelFontSize) }),
                               in: lo...hi,
                               onEditingChanged: { editing in
                                   if !editing {
                                       editorState.commitMeasureLabelScale(
                                           editorState.measureLabelPreview?.scale ?? c.labelScale)
                                   }
                               })
                            .controlSize(.small)
                        Text(DocumentUnit.text(px))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                // Three swatches, no extra sliders: Stroke = caliper ink + the
                // chip's border, Chip = the pill's fill (its picker carries the
                // opacity slider, so "no chip" is just alpha 0), Text = readout.
                // Whole-object transparency lives in Effects, where every layer's
                // does.
                swatchRow("Stroke", hex: c.strokeColorHex) {
                    editorState.setMeasureStrokeColor($0, commit: true)
                }
                // The chip's opacity IS its alpha, so the picker's opacity
                // slider writes it: "no chip" is alpha 0 rather than a separate
                // switch.
                swatchRow("Chip", hex: chipHex(c), supportsOpacity: true) { picked in
                    let rgba = RGBA(hex: picked)
                    editorState.setMeasureChipColor(rgba?.hexString ?? picked,
                                                    opacity: rgba?.a ?? 1, commit: true)
                }
                swatchRow("Text", hex: c.textColorHex) {
                    editorState.setMeasureTextColor($0, commit: true)
                }
                }
                if Experiments.shared.measurePanelEnabled {
                    detailsSection(c)
                }
            }
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
            .padding(.vertical, 8)
        }
    }

    /// Commits the Name field the way the row's double-click rename does: a
    /// trimmed, non-empty name that differs from what the row already shows.
    /// Clearing the field just puts the current name back.
    private func commitName() {
        guard draftLayerID == layer.id else { return }
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != displayName else {
            nameDraft = displayName
            return
        }
        editorState.renameLayer(id: layer.id, to: trimmed)
    }

    /// The foot of the section: the one action that belongs beside a picked
    /// measurement, and a fold holding every number it can tell you about
    /// itself.
    ///
    /// The numbers used to sit open, and between them and the spec-line preview
    /// they were half the section's height — which is how the section came to
    /// be 470pt tall against a 344pt slot and could not be made to fit by any
    /// ordering of the dock. None of them is a setting: Distance restates the
    /// number already drawn on the canvas, Units restates the Unit row three
    /// rows above, and the spec line restates both. So they fold, the way a
    /// part's settings fold in the parts list, and the fold is remembered
    /// across launches: open it once and it stays open.
    @ViewBuilder private func detailsSection(_ c: MeasureContent) -> some View {
        Divider().opacity(0.4)
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.14)) { isDetailsOpen.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(isDetailsOpen ? 90 : 0))
                    Text("Details").font(.caption)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .panelHelp("Where this measurement's feet sit, how far apart they are, and the "
                  + "exact line Copy Measurement puts on the clipboard")
            .playtestControl("Details", detail: isDetailsOpen ? "open" : "closed")
            Spacer(minLength: 0)
            Button("Copy Measurement") { editorState.copyMeasurement(id: layer.id) }
                .controlSize(.small)
                .panelHelp("Copies this one measurement's spec line as text, ready to paste into a thread")
        }
        .playtestField("Details")
        if isDetailsOpen {
            VStack(alignment: .leading, spacing: 4) {
                geometryGrid(c)
                // The exact line that lands on the clipboard, so the button
                // needs no explaining. Selectable, like the readouts above it.
                if let line = specLine {
                    Text(line)
                        .font(.caption2).monospaced().foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.tail)
                        .textSelection(.enabled)
                }
            }
            .transition(.opacity)
        }
    }

    /// The mock's read-only From / To / Distance / Units grid (§6): the feet in
    /// document coordinates and the span, straight from `caliperGeometry()` —
    /// no new model state. A guide (§9) reads Length instead of Distance, and
    /// adds the edge it settled on and how many things it checked.
    @ViewBuilder private func geometryGrid(_ c: MeasureContent) -> some View {
        let frame = editorState.document?.layer(id: layer.id)?.frame ?? layer.frame
        let g = c.caliperGeometry()
        let scale = editorState.document?.pixelScale ?? 1
        VStack(alignment: .leading, spacing: 4) {
            readoutRow("From", point(g.footA, in: frame, scale: scale))
            readoutRow("To", point(g.footB, in: frame, scale: scale))
            readoutRow(c.alignment == nil ? "Distance" : "Length",
                       String(format: "%.\(max(0, c.decimals))f %@",
                              c.displayDistance(pixelScale: scale), c.unit.suffix))
            if let check = c.alignment {
                readoutRow("Edge", edgeReadout(c, check, in: frame, scale: scale))
                readoutRow("Items", itemsReadout(check))
            }
            readoutRow("Units", c.unit == .points ? "Logical px" : "Actual px")
        }
    }

    /// Which edge the guide settled on and where it is, in the measure's unit:
    /// "Left, x 312 px", or just "x 312 px" when the scan could not tell the
    /// side. The position is the reference line, which is where the guide
    /// itself sits once committed.
    private func edgeReadout(_ c: MeasureContent, _ check: AlignmentCheck,
                             in frame: CGRect, scale: CGFloat) -> String {
        guard let verdict = check.verdict else { return "no edges" }
        let position: String
        switch c.mode {
        case .vertical:
            let x = c.displayValue(frame.minX + verdict.reference, pixelScale: scale)
            position = "x \(Int(x.rounded())) \(c.unit.suffix)"
        case .horizontal:
            let y = c.displayValue(frame.minY + verdict.reference, pixelScale: scale)
            position = "y \(Int(y.rounded())) \(c.unit.suffix)"
        }
        guard let edge = c.alignedEdge else { return position }
        return "\(edge.word), \(position)"
    }

    /// How many elements the guide checked, and how many are off: "4 items" /
    /// "4 items, 1 off". A check whose items are raw edge runs (no pixels were
    /// read, or an older guide) says "not counted" rather than a wrong number.
    private func itemsReadout(_ check: AlignmentCheck) -> String {
        let count = check.itemsAreElements
            ? MeasureSpecList.countPhrase(check.items.count) : "not counted"
        guard let verdict = check.verdict, !verdict.isAligned else { return count }
        return "\(count), 1 off"
    }

    /// A document coordinate in the measure's unit, "x, y".
    private func point(_ p: CGPoint, in frame: CGRect, scale: CGFloat) -> String {
        guard let c = content else { return "" }
        let x = c.displayValue(frame.minX + p.x, pixelScale: scale)
        let y = c.displayValue(frame.minY + p.y, pixelScale: scale)
        return "\(Int(x.rounded())), \(Int(y.rounded()))"
    }

    /// One read-only line of the grid: caption left, value right, selectable so
    /// a number can be copied straight out of the inspector.
    @ViewBuilder private func readoutRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary)
                .frame(width: Self.labelWidth, alignment: .leading)
            Text(value)
                .font(.caption)
                .monospacedDigit()
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    /// The spec line Copy Measurement puts on the clipboard, live from the
    /// document so a recolor, rename or unit change updates it in place.
    private var specLine: String? {
        guard let document = editorState.document,
              let current = document.layer(id: layer.id) else { return nil }
        return MeasureSpecList.specLine(for: current, in: document)
    }

    /// One setting, on one line: its name on the left, its control on the
    /// right, the way the colour rows below already read.
    ///
    /// These used to stack the caption on its own line ABOVE a full-width
    /// control, which is the Effects panel's shape. It is the wrong shape here:
    /// every control in this section — two segments, three segments, a short
    /// slider — is about half the column wide, so the caption line bought
    /// nothing and cost a line of height each time, and the section ended up
    /// speaking two row languages, stacked at the top and inline at the bottom.
    /// One language, five lines shorter.
    @ViewBuilder private func row<Content: View>(_ label: String,
                                                 @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
                .frame(width: Self.labelWidth, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .playtestField(label)
    }

    /// Wide enough for "Thickness" and "Label size", the two longest names in
    /// the section, so every control in it starts at the same left edge.
    private static let labelWidth: CGFloat = 62

    /// One color row: caption on the left, swatch next to it, so the three
    /// swatches line up in a column.
    /// The chip's color and its opacity as one string, because to the picker
    /// they are one color.
    private func chipHex(_ measure: MeasureContent) -> String {
        var rgba = RGBA(hex: measure.chipColorHex) ?? RGBA(r: 1, g: 1, b: 1)
        rgba.a = measure.chipOpacity
        return rgba.hexStringWithAlpha
    }

    @ViewBuilder private func swatchRow(_ label: String, hex: String,
                                        supportsOpacity: Bool = false,
                                        set: @escaping (String) -> Void) -> some View {
        row(label) {
            ColorWellButton(hex: hex, name: label, supportsOpacity: supportsOpacity, onCommit: set)
        }
    }
}
