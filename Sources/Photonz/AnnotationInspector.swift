// The settings for an annotation: arrows and their captions, shapes, and the corner radius row they share.

import PhotonzCore
import SwiftUI

// MARK: - Annotation inspector

/// The picked shapes' own settings: thickness, an arrow's caption and its
/// head — over the WHOLE selection.
///
/// Colors are not here: they live in the Color section, which is where they
/// live whatever is picked, so shift-clicking a second layer widens what a row
/// speaks for instead of moving it. These rows now work the same way. Pick two
/// arrows and Thickness is still there, speaking for both; pick an arrow and a
/// box and only the setting they share is offered, because a Head Size slider
/// over a rectangle is a control that does nothing.
///
/// Corners are not here either, for the same reason colors are not: rounding
/// is one row under Effects that speaks for everything picked, shapes and
/// screenshots alike.
///
/// Sliders preview live and commit one undo step on release, however many
/// shapes they reached.
struct AnnotationInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let selection = editorState.shapeSelection
        let ids = selection.layerIDs
        let rows = Self.visibleRows(selection)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.self) { row in
                    self.row(row, selection: selection, ids: ids)
                }
                // The label pills a hand has dragged, put back where the app
                // places them. Offered only while there is one to put back.
                if !selection.pinnedCaptionIDs.isEmpty,
                   Experiments.shared.arrowCaptionsEnabled {
                    let pinned = selection.pinnedCaptionIDs
                    Button(pinned.count > 1 ? "Reset label positions" : "Reset label position") {
                        editorState.resetCaptionPlacement(ids: pinned)
                    }
                    .font(.caption)
                    .controlSize(.small)
                    .panelHelp(pinned.count > 1
                          ? "Put all \(pinned.count) labels back where the app places them"
                          : "Put the label back where the app places it")
                }
                SelectionStyleNotes(notes: [selection.note],
                                    caption: selectionCaption(selection.count))
            }
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
            .padding(.vertical, 8)
        }
    }

    /// The rows this section actually shows, which is also what decides whether
    /// the section is there at all: a rectangle whose only setting was its
    /// Thickness brings no section once that width has moved into the Outline
    /// part, rather than an empty heading with its name on it.
    static func visibleRows(_ selection: ShapeSelection) -> [ShapeSettingRow] {
        // There is no arrow section any more where Appearance is on. Every one
        // of these rows moved into Appearance, under the part it belongs to,
        // so one section says how the thing looks (`ShapePartSettings.swift`,
        // asked for by the user on 2026-09-09). The release without the split
        // keeps the section exactly as it was.
        guard !Experiments.shared.shapePartsEnabled else { return [] }
        return selection.rows.filter { row in
            // Captions are a Next feature; without it an arrow is a plain
            // arrow and neither the field nor its size row belongs here.
            guard Experiments.shared.arrowCaptionsEnabled
                    || (row != .caption && row != .labelSize) else { return false }
            // Where the outline is a part that switches off — a box, an
            // ellipse — its width is that part's own setting and is called
            // Width there (`next-shape-parts`). Where the line IS the shape
            // the part has no switch and so no drawer, and the thickness
            // stays right here, in reach the moment the arrow is picked.
            return !(Experiments.shared.shapePartsEnabled && row == .thickness
                     && selection.widthIsAnOutlineSetting)
        }
    }

    @ViewBuilder
    private func row(_ row: ShapeSettingRow, selection: ShapeSelection, ids: [UUID]) -> some View {
        switch row {
        case .thickness:
            // The ONE width of the line round a shape. It reads whichever ring
            // is actually on screen, so a box drawn before the Effects Border
            // slider stopped reaching shapes still shows its width here, and a
            // pull moves that ring onto the stroke where it belongs.
            ShapeSlider(layerIDs: ids, label: "Thickness",
                        reading: selection.outlineWidth,
                        range: AnnotationStyles.strokeWidthRange,
                        format: { DocumentUnit.text($0) },
                        preview: { editorState.previewOutlineWidth(ids: $0, $1) },
                        commit: { editorState.commitOutlineWidth(ids: $0, $1) })
                .panelHelp(Experiments.shared.shapePartsEnabled
                      ? "How thick the line is. Its color is the Color row, in Appearance above"
                      : "How thick the line round the shape is. Its color is Outline, in the Color section above")
        case .caption:
            // ONE arrow only. A single field over three arrows could only give
            // all three the same words, and a caption is what the arrow says,
            // not how it looks.
            if let only = selection.members.first, selection.count == 1 {
                ArrowCaptionField(layerID: only.id)
            }
        case .labelSize:
            ShapeSlider(layerIDs: ids, label: "Label size",
                        reading: selection.number { $0.captionFontSize },
                        range: MeasureContent.labelSizeRangePx,
                        format: { DocumentUnit.text($0) },
                        preview: { editorState.previewCaptionFontSize(ids: $0, $1) },
                        commit: { editorState.commitCaptionFontSize(ids: $0, $1) })
        case .labelCorners:
            ShapeSlider(layerIDs: ids, label: "Label corners",
                        reading: selection.number { $0.captionRoundness },
                        range: AnnotationContent.captionRoundnessRange,
                        format: { roundnessWord($0) },
                        round: { $0 },
                        preview: { editorState.previewCaptionRoundness(ids: $0, $1) },
                        commit: { editorState.commitCaptionRoundness(ids: $0, $1) })
                .panelHelp("How round the label's corners are, from a square box through a badge to a full pill")
        case .headStyle:
            // The one row in this section that is a picture rather than a
            // number, so it carries its own caption instead of a slider's.
            let ending = selection.reading { $0.arrowheadStyle }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Ending").font(.caption).foregroundStyle(.secondary)
                    // A glyph says what the ending IS while you are looking at
                    // the row; the word is what you remember it by afterwards.
                    if ending.isMixed {
                        MixedWord()
                    } else if let word = ArrowheadStylePicker.word(ending.value, isMixed: false) {
                        Text(word).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                ArrowheadStylePicker(selection: ending.value, isMixed: ending.isMixed) {
                    editorState.setArrowheadStyle(ids: ids, $0)
                }
            }
            .playtestField("Ending")
        case .headSize:
            ShapeSlider(layerIDs: ids, label: "Head Size",
                        reading: selection.number { $0.arrowheadScale },
                        range: AnnotationStyles.arrowheadScaleRange,
                        format: { "×\(String(format: "%.1f", $0))" },
                        round: { $0 },
                        preview: { editorState.previewAnnotationRestyle(ids: $0, arrowheadScale: $1) },
                        commit: { editorState.commitAnnotationRestyle(ids: $0, arrowheadScale: $1) })
        }
    }

    /// What the corner row says it is on. The two ends are shapes with names,
    /// because "Square" and "Pill" are what the user is actually after; the
    /// middle is how far it has travelled between them.
    private func roundnessWord(_ value: CGFloat) -> String {
        switch value {
        case ..<0.02: "Square"
        case 0.98...: "Pill"
        default: "\(Int((value * 100).rounded()))%"
        }
    }
}

/// The ONE Corner Radius row, under Effects, speaking for everything picked.
///
/// Rounding means two different things underneath: a rectangle curves the
/// outline it draws, so the curve follows its border, while a screenshot, a
/// frame or a group has its corners masked off. The panel used to carry a
/// slider for each, one in the shape's own section and one here, both labelled
/// Corner Radius, with nothing to say which was which. They also disagreed in
/// the worst way: the mask chopped the corners clean off a rectangle's
/// outline. So there is one row, it reads whichever number is rounding each
/// picked layer, and a pull writes back to whichever one rounds it properly.
///
/// Dragging previews without recording undo; release commits ONE step,
/// however many layers it reached.
struct CornerRadiusRow: View {
    @Environment(EditorState.self) private var editorState
    let selection: CornerRadiusSelection

    /// Where the knob is while the hand is on it, so it moves smoothly even
    /// though what it sends is whole points.
    @State private var draft: Double?

    private var range: ClosedRange<Double> { 0...selection.limit }

    private var knob: Double {
        min(max(draft ?? selection.reading.value ?? 0, range.lowerBound), range.upperBound)
    }

    /// Mixed only until the drag starts: once it has, they all wear the number
    /// under the knob.
    private var showsMixed: Bool { draft == nil && selection.reading.isMixed }

    /// Whether the four corners are showing. Closed until somebody opens them:
    /// one number is the common case, and four always-on rows would be the
    /// panel telling you it has run out of space for the thing you actually
    /// came here for.
    ///
    /// Held by the view rather than by the editor, which is the one place this
    /// row deliberately parts company with an effect. An effect's fold belongs
    /// to that effect, so it is dropped when you pick something else; opening
    /// the corners is a way of WORKING — you are setting corners today — and
    /// closing them again on every selection change would undo that choice
    /// each time you drew the next card.
    @State private var cornersOpen = false

    /// Whether the four corners can be opened at all. This row is shared with
    /// the release that came before Appearance and Effects split, and setting a
    /// corner on its own belongs to the new panel, so only it grows the
    /// chevron. Both releases READ four corners honestly, because a document is
    /// a document: a card drawn with a rounded top opened in either one shows
    /// the four numbers rather than a single one that is not true.
    private var canOpenCorners: Bool { Experiments.shared.shapePartsEnabled }

    /// What the readout says when there is no single number to say.
    ///
    /// With the corners CLOSED, the four numbers themselves — `16/16/0/0` —
    /// because the readout is then the only place on screen a corner set on its
    /// own can be read. Two layers rounded differently have no four numbers in
    /// common either, so that case is the house word. This is exactly what
    /// Padding's single field does, on purpose (`ArrangementInspector.swift`).
    private var readout: String {
        if showsMixed { return LayerStyleSelection.mixedText }
        guard selection.hasUnevenCorners else { return points(knob) }
        // OPEN, the four numbers are on the rows underneath, so saying them
        // again up here would be noise — and saying one of them would be a
        // claim that is not true. CLOSED, this is the only place left on screen
        // where a corner set on its own can be read, so it holds the four.
        guard !(cornersOpen && canOpenCorners), let shorthand = selection.shorthand else {
            return LayerStyleSelection.mixedText
        }
        return shorthand
    }

    /// True while the readout is standing in for something rather than saying a
    /// number, so it is drawn the one strength every other Mixed is drawn at.
    private var readoutIsMixed: Bool { readout == LayerStyleSelection.mixedText }

    var body: some View {
        let ids = selection.layerIDs
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                heading
                if let only = selection.soleStyleRoundedID {
                    InstanceStyleRevert(layerID: only, field: .cornerRadius)
                }
                Spacer(minLength: 8)
                Text(readout)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(MixedLook.style(readoutIsMixed, otherwise: .secondary))
                    .panelReadout(readout)
            }
            Slider(value: Binding(
                get: { knob },
                set: { v in
                    draft = v
                    editorState.previewCornerRadius(ids: ids, CGFloat(v.rounded()))
                }), in: range) { editing in
                if !editing {
                    editorState.commitCornerRadius(ids: ids, CGFloat((draft ?? knob).rounded()))
                    draft = nil
                }
            }
            .controlSize(.small)
            .disabled(ids.isEmpty)
            .playtestControl("Slider", detail: "Corner Radius")
            .help(selection.hasUnevenCorners
                ? "These corners are set apart. Pulling this gives all four the same."
                : "How round every corner of the picked layers is.")
            if cornersOpen, canOpenCorners {
                // Behind the same rule an effect's settings sit behind, hung on
                // the chevron that opened them. Before this the four corners
                // were a plain 16pt pad, which said "these are further in" and
                // nothing else: which row they belonged to was left for you to
                // work out from the order.
                OwnedSettings(owner: "Corner Radius") {
                    ForEach(CornerRadii.Corner.allCases, id: \.self) { corner in
                        cornerRow(corner, ids: ids)
                    }
                }
                // The outer stack is tight so the slider hugs its label; an
                // effect keeps a full gap between its heading and its rule, so
                // this makes up the difference rather than moving everything.
                .padding(.top, 4)
            }
        }
        .playtestField("Corner Radius")
    }

    /// The name, and the chevron that opens the four corners in front of it.
    ///
    /// Drawn as an effect's heading is drawn — the shared `PanelFoldChevron` in
    /// the panel's leading column, then the name lit and semibold — because
    /// that is what this row now is: a small pane with settings folded under
    /// it. Chevron and name are ONE press, the way a section header and an
    /// effect both are, since a 9pt glyph on its own is a mean target.
    ///
    /// Only the new panel opens at all (`canOpenCorners`), and where it cannot
    /// the row keeps the plain label it has always had: a heading that opens
    /// nothing would be a promise the old panel does not keep.
    @ViewBuilder
    private var heading: some View {
        if canOpenCorners {
            Button {
                withAnimation(.spring(duration: 0.2)) { cornersOpen.toggle() }
            } label: {
                HStack(spacing: ColorPartLayout.spacing) {
                    PanelFoldChevron(isFolded: !cornersOpen)
                    Text("Corner Radius")
                        .font(PanelSectionLook.EffectRow.titleFont)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        // Shrinks before it truncates, the same way an effect's
                        // name does, because this is the longest name in the
                        // panel and the dock can be dragged narrow.
                        .minimumScaleFactor(0.85)
                        .frame(height: ColorPartLayout.rowHeight, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .panelHelp(cornersOpen
                ? "Hide the four corners and keep the rounding they were given."
                : "Round each of the four corners on its own.")
            .accessibilityLabel("Corner Radius")
            .accessibilityValue(cornersOpen ? "corners showing" : "corners hidden")
            // The same word an effect's twist and a layer group's twist answer
            // to, so the one gesture has one name across the app.
            .playtestControl("Twist", detail: cornersOpen ? "open" : "shut")
        } else {
            Text("Corner Radius").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// One corner's own number, typed rather than dragged: you come here to say
    /// "the top two, sixteen, the bottom two, nothing", and four more knobs
    /// would be four more things to nudge by accident.
    @ViewBuilder
    private func cornerRow(_ corner: CornerRadii.Corner, ids: [UUID]) -> some View {
        let reading = selection.corner(corner)
        HStack(spacing: 6) {
            Text(corner.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            LayoutNumberField(
                title: corner.title,
                value: reading.value.map { CGFloat($0) },
                placeholder: reading.isMixed ? MixedValue.text : "",
                help: "How round the \(corner.spoken) corner is."
            ) { value in
                editorState.commitCornerRadius(ids: ids, corner: corner, value)
            }
        }
        .playtestField(corner.title)
    }
}

/// One arrow's caption. Its own view because it holds a draft and the keyboard:
/// typing edits the draft, and Return, Escape or clicking away all land or drop
/// it exactly once.
struct ArrowCaptionField: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    /// Whether the field says its own name above itself. In Appearance the row
    /// it hangs under is already called Caption, and a label repeating the
    /// heading two lines above it is a word in the way.
    var showsLabel = true
    @State private var captionDraft: String = ""
    @FocusState private var captionFocused: Bool
    /// True from the moment the field takes focus until its draft has been
    /// committed or dropped, so a field that disappears mid-edit (the arrow was
    /// deselected by a canvas click) still lands what was typed.
    @State private var captionEditing = false

    private var annotation: AnnotationContent? {
        editorState.document?.layer(id: layerID)?.annotation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsLabel {
                Text("Caption").font(.caption).foregroundStyle(.secondary)
            }
            // As many lines as the caption has: a single line field showed a
            // two line label as its first line alone and landed that back on
            // the arrow the moment the field lost focus, quietly throwing the
            // second line away.
            TextField("Add a caption", text: $captionDraft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .focused($captionFocused)
                // The canvas field's keys, so the two fields for one label
                // agree: Return drops a line, Command and Return lands the
                // caption, Esc drops the draft and shows the arrow's caption
                // again. Both closing keys hand the keyboard to the picture.
                // Clearing `captionEditing` first is what stops the focus loss
                // that follows from landing the same words a second time.
                .onKeyPress(phases: .down) { press in
                    let key: ArrowCaptionEntry.Key
                    switch press.key {
                    case .return, KeyEquivalent("\u{3}"):
                        key = .return(command: press.modifiers.contains(.command))
                    case .escape: key = .escape
                    default: return .ignored
                    }
                    switch ArrowCaptionEntry.action(for: key) {
                    case .type: return .ignored
                    case .commit:
                        captionEditing = false
                        editorState.setAnnotationCaption(layerID: layerID, captionDraft)
                    case .cancel:
                        captionDraft = annotation?.caption ?? ""
                        captionEditing = false
                    }
                    KeyboardHandback.toCanvas()
                    return .handled
                }
                // Like every Mac text field, clicking away commits what you
                // typed (one undo step; none if unchanged). Not when the canvas
                // has just opened its own editor on this arrow: that editor
                // owns the draft now.
                .onChange(of: captionFocused) { _, focused in
                    if focused {
                        captionEditing = true
                    } else if captionEditing {
                        captionEditing = false
                        commitInspectorCaption()
                    }
                }
                .onDisappear {
                    if captionEditing {
                        captionEditing = false
                        commitInspectorCaption()
                    }
                }
        }
        // Track the model (initially, after undo, on layer switch); typing
        // edits only the draft until Return commits.
        .onChange(of: annotation?.caption ?? "", initial: true) { _, new in
            captionDraft = new
        }
        // The canvas opening its own editor on this arrow closes the
        // inspector's draft (one draft at a time): the field falls back to the
        // caption the canvas editor starts from. In practice the click that
        // opens the canvas editor takes focus first, so a pending draft has
        // already landed by then (verified on the probe app); this is the
        // fallback.
        .onChange(of: editorState.editingCaptionLayerID) { _, editing in
            if editing == layerID {
                captionEditing = false
                captionDraft = annotation?.caption ?? ""
            }
        }
    }

    /// The field landing its draft (Return or focus loss). Skipped while the
    /// canvas editor is open on the same arrow: the two fields share one draft
    /// and the canvas holds it.
    private func commitInspectorCaption() {
        guard editorState.editingCaptionLayerID != layerID else { return }
        editorState.setAnnotationCaption(layerID: layerID, captionDraft)
    }
}
