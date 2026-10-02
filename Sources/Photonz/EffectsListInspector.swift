import PhotonzCore
import SwiftUI

/// **Effects**: a list you ADD to (`next-shape-parts`).
///
/// The other half of the split the user chose on 2026-09-07. Appearance above
/// holds what a shape simply has; this holds what somebody put on it. It starts
/// EMPTY on a new shape and gains a row only when you press the plus on its
/// header: a shadow, a glow, a border, a blur, and later a filter.
///
/// Three things follow from it being a list rather than a set of fixed rows:
///
/// - **The same kind can arrive more than once.** Two shadows, one tight and
///   dark for contact and one wide and soft for lift, are two rows with their
///   own settings.
/// - **The order is visible, so it is editable.** The top of the list is
///   nearest the eye. Drag a row and what paints over what changes.
/// - **A row can be taken out.** The cross removes the effect; the eye beside
///   it keeps every number on it and stops it drawing. Compare-with-and-without
///   is the thing you do constantly, so it is the gesture that keeps your work.
struct EffectsListInspector: View {
    @Environment(EditorState.self) private var editorState

    /// The gap between two effects, and the padding this list draws above and
    /// below the whole stack. The dock reads both to work out how much room one
    /// open effect needs (`InspectorPanel.squeezeFloor(for:room:)`).
    static let paneSpacing: CGFloat = 16
    static let listInset: CGFloat = 8

    /// Told what this list is made of whenever it changes: one block per
    /// effect, how tall it is and whether it is open, and which one of them you
    /// just opened. The dock's height budget keeps room to draw THAT one whole,
    /// so a squeezed Effects section never cuts a slider in half, and the
    /// effect it keeps room for is the one you pressed rather than whichever
    /// happens to be first in the list.
    var onPanes: (([DockHeightBudget.Block], Int?) -> Void)?

    /// Where one effect is sitting in the dock's visible area, told to the
    /// panel so an effect you have just opened can be brought on screen. Keyed
    /// by `LayerEffectRow.id`. See `LayersPanel.applyEffectReveal`.
    var onPaneFrame: ((String, CGRect) -> Void)?

    /// Each effect's measured extent, by its place in the list.
    @State private var panes: [Int: DockHeightBudget.Block] = [:]

    var body: some View {
        let rows = editorState.layerEffectRows
        VStack(alignment: .leading, spacing: Self.paneSpacing) {
            if rows.isEmpty {
                empty
            } else {
                ForEach(rows) { row in
                    EffectRowView(row: row,
                                  onExtent: { panes[row.index] = $0 },
                                  onFrame: { onPaneFrame?(row.id, $0) })
                }
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, Self.listInset)
        // All three, because each can move on its own: an effect folding
        // changes a height, removing one changes how many there are while the
        // measurements of the rest stay exactly as they were, and opening one
        // changes which of them the dock is keeping room for.
        .onChange(of: panes, initial: true) { report(rows) }
        .onChange(of: rows.count) { report(rows) }
        .onChange(of: editorState.openedEffectRow) { report(rows) }
    }

    /// The panes in list order, dropping any measurement left behind by an
    /// effect that has since been removed, and where in that order the effect
    /// you just opened sits.
    private func report(_ rows: [LayerEffectRow]) {
        let count = rows.count
        let focus = editorState.openedEffectRow.flatMap { id in
            rows.firstIndex { $0.id == id }
        }
        onPanes?((0..<count).compactMap { panes[$0] }, focus)
    }

    /// What an untouched shape shows: ONE line saying where the gesture is. An
    /// empty section with nothing in it at all reads as broken, and the plus on
    /// the header is small enough to be missed the first time, so this is the
    /// one case the budget keeps a line for (UX-PATTERNS §4, "How much a section
    /// may say").
    ///
    /// It used to name all four kinds as well, which took a second line to say
    /// something the plus's own hover tip already says word for word ("Add an
    /// effect: a shadow, a glow, a border or a blur") and the menu itself lists
    /// the moment you press it.
    ///
    /// A label since 2026-09-27, not a sentence: where the plus is goes in the
    /// line's hover tip (the user: labels and tools, never sentences).
    private static let nothingYet = "No effects"
    private static let nothingYetHelp = "Add a shadow, a glow, a border or a blur with the plus above"

    private var empty: some View {
        Text(Self.nothingYet)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .panelHelp(Self.nothingYetHelp)
            .playtestField("Effects Empty")
            // Said out loud for the same reason the Motion list says its own
            // empty line: `expect field` reads typing boxes and readouts, and a
            // line of prose is neither until it says so.
            .panelReadout(Self.nothingYet)
            .panelStartProbe(.row, owner: "Effects empty")
    }

}

/// One effect on a layer: the list's row (`EffectsListRow`, the same row a
/// sound's Audio Effects list draws) with what a layer's effect brings to it:
/// a grip, since the order is the paint order, a colour landing on it while it
/// is off, and its settings.
private struct EffectRowView: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerEffectRow
    /// How tall this pane is and whether it is open, told to the list so the
    /// dock can keep room for it. See `EffectsListInspector.onPanes`.
    let onExtent: (DockHeightBudget.Block) -> Void
    /// ...and where it is sitting, in the dock's visible area.
    let onFrame: (CGRect) -> Void

    /// What is being held over this row right now, while it is switched off.
    @State private var incoming: ColorDrop.Answer?

    var body: some View {
        let kindWord = row.kind.title.lowercased()
        EffectsListRow(
            title: row.title,
            kindWord: kindWord,
            steadyNames: row.steadyNames,
            isOn: row.isOn,
            isMixed: row.isMixed,
            isFolded: editorState.isEffectFolded(row),
            toggleFold: { editorState.toggleEffectFolded(row) },
            switchReading: row.switchReading,
            switchHelp: CrowdWords.them(row.switchIDs.count)
                .map { "Stops it drawing on \($0), and keeps its settings" }
                ?? "Stops it drawing, and keeps its settings",
            setOn: { editorState.setEffectEnabled(row: row, on: $0) },
            remove: { editorState.removeEffect(row: row) },
            reorder: row.canReorder
                ? .init(index: row.index,
                        canMove: { editorState.canMoveEffect(row: row, to: $0) },
                        move: { editorState.moveEffect(row: row, to: $0) })
                : nil,
            note: row.reachNote,
            headerDrop: OffEffectColorDrop(row: row, active: !row.isOn, incoming: $incoming),
            onExtent: onExtent,
            onFrame: onFrame,
            accessory: { offAccessory },
            settings: { settings })
    }

    /// While the effect is off: the colour being held over it, or the word
    /// mixed where the picked layers disagree.
    @ViewBuilder private var offAccessory: some View {
        if !row.isOn, let paint = incoming?.landing?.paint {
            LandingSwatch(paint: paint)
        } else if !row.isOn, row.isMixed {
            MixedWord()
                .frame(minWidth: ColorPartLayout.readoutWidth,
                       minHeight: ColorPartLayout.rowHeight, alignment: .leading)
        }
    }

    // MARK: The settings

    @ViewBuilder private var settings: some View {
        // The name this effect came from, at the top, because it sets every row
        // under it and a control that does that placed below them is a control
        // nobody finds (`EffectStylePanel.swift`).
        EffectStyleRow(row: row)
        // Then the colour, whatever the effect is, so the list reads one way:
        // every entry that paints a colour asks for it in the same place, in
        // the same words, with the same saved colours behind it.
        EffectColorRow(row: row)
        switch row.kind {
        case .shadow:
            let index = row.shadowIndex ?? 0
            // Behind the layer or cast into it: one setting, because an inner
            // shadow is the same effect drawn somewhere else rather than a
            // different effect with its own row.
            ShadowKindRow(index: index, ids: row.switchIDs)
            // Everything else about the shadow except the tick, which is up on
            // the row, and the colour, which is the row above this one.
            ShadowInspector(showsSwitch: false, showsColor: false, inset: false, index: index)
        case .border:
            // On a label, WHAT the ring goes round comes before everything
            // else: it changes what the rest of the settings even describe.
            BorderFollowsRow(row: row)
            // Where the ring sits, then how thick it is: which side of the edge
            // you are on changes what a width even means, so it is asked first.
            BorderPositionRow(row: row)
            BorderWidthRow(row: row)
            // ...and then how far off that edge it stands, which only means
            // something once you know which side of the edge you are on.
            BorderOffsetRow(row: row)
        case .glow:
            // Which side of the edge the light is on, then how far it reaches,
            // how gently it stops, and how strong it is. Four things and no
            // Distance or Direction: a glow does not fall anywhere.
            GlowKindRow(row: row)
            GlowSlidersRow(row: row)
        case .blur:
            BlurEffectRow(row: row)
        }
    }
}

/// What ONE effect is painted, as a setting of that effect.
///
/// The whole point is that there is nothing special about it. It is the same
/// well, the same saved-colours menu and the same "Save as Style" field a Fill
/// or an Outline row carries, addressed by the effect's place in the list
/// instead of by one of the layer's own slots (`ColorTarget`). So a border can
/// wear the hairline colour you saved, follow it when you edit it, and let go
/// of it the moment you pick a colour by hand.
///
/// An effect with no colour at all — a blur — brings no row rather than a blank
/// one.
private struct EffectColorRow: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerEffectRow

    var body: some View {
        if let target = ColorTarget(effect: row) {
            HStack(alignment: .top, spacing: ColorPartLayout.spacing) {
                Text("Color")
                    .panelRowName()
                    .frame(width: ColorPartLayout.nameWidth,
                           height: ColorPartLayout.rowHeight, alignment: .leading)
                // The KIND's word rather than the row's, so two borders both
                // offer "Saved border colors" instead of one of them offering
                // "Saved border 2 colors". Which of the two a walk means is
                // already settled by the row it is in.
                ColorStyleRow(target: target, part: row.kind.title,
                              selection: editorState.colorStyleSelection(target),
                              isNaming: editorState.isNamingColorStyle(target),
                              previewPaint: editorState.previewedPaint(target),
                              // An effect that is not drawing keeps this
                              // swatch, so this is where a carried colour
                              // lands rather than on the row's own band. It
                              // has to mean what the band means: switch the
                              // effect back on AND paint it. Painting
                              // something nobody can see, and saying it had
                              // painted it, is the bug this closes.
                              switchedOff: !row.isOn)
                    .equatable()
                Spacer(minLength: 0)
            }
            // Its own row name, INSIDE the effect's, so a walk says
            // `{"menu": "Color", "in": "Border 2"}`: the effect's row holds two
            // menus now, the saved colours and the Position, and the row's name
            // alone could not tell them apart.
            .playtestField("Color")
        }
    }
}

/// What one added ring round a LABEL goes round: its letters, or the box the
/// words sit in.
///
/// Only a label is asked. Everything else has a box and nothing else, so the
/// row is not there at all rather than being there greyed out: a question with
/// one possible answer is a question in the way.
///
/// It sits at the top of the border's settings because it changes what the two
/// rows under it mean — a line round each letter has no inside and no outside,
/// so the Position popup goes away with it (`BorderFollows.swift`).
private struct BorderFollowsRow: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerEffectRow

    var body: some View {
        let borders = editorState.layerStyleSelection.borders(at: row.index)
        if borders.hasLettersEverywhere {
            let ids = borders.layerIDs
            let reading = borders.reading { $0.borderEffect(at: row.index)?.follows ?? .letters }
            HStack(alignment: .firstTextBaseline, spacing: ColorPartLayout.spacing) {
                Text("Follows")
                    .panelRowName()
                    .frame(width: ColorPartLayout.nameWidth, alignment: .leading)
                Picker("Follows", selection: Binding(
                    get: { reading.isMixed ? nil : reading.value },
                    set: { new in
                        guard let new else { return }
                        editorState.setBorderEffectFollows(at: row.index, ids: ids, to: new)
                    })) {
                        if reading.isMixed {
                            Text(LayerStyleSelection.mixedText).tag(BorderFollows?.none)
                        }
                        ForEach(BorderFollows.allCases, id: \.self) { follows in
                            Text(follows.title).tag(BorderFollows?.some(follows))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    // The width the Position popup beside it carries, for the
                    // same reason: an ideal-width menu inside the dock's column
                    // pushed the whole pane wider than the window.
                    .frame(width: 92, alignment: .leading)
                    .disabled(ids.isEmpty)
                    .panelHelp("Letters draws round each letter, so words stay readable over "
                          + "anything. Box draws round the label's frame.")
                    .playtestControl("Follows", detail: reading.isMixed ? "mixed"
                                        : (reading.value ?? .letters).title)
                Spacer(minLength: 0)
            }
            // Its own row name, the way the Color row above it carries one:
            // with this row on screen the border holds THREE menus, and a walk
            // that said `{"menu": "Border"}` could not say which of them it
            // meant. So this one is `{"menu": "Follows", "in": "Border"}` and
            // the Position keeps the row's own name.
            .playtestField("Follows")
        }
    }
}

/// Which side of the layer's edge one added ring sits on.
///
/// The same three words the Outline row in Appearance uses, because it is the
/// same question: a line is inside the edge, straddling it, or outside it. An
/// inner border and an outer border are two entries in the list that differ by
/// nothing but this.
///
/// Not asked of a ring that is following a label's LETTERS: an outline grown
/// out of the glyphs has no inside or outside to choose between, so the popup
/// would be three words that do nothing (`BorderFollows.swift`).
///
/// Nor of a ring round an OPEN PATH, for the same reason: a line has two sides
/// and no inside, so all three words draw the one band down the middle of it
/// (`Layer.ringsAnOpenLine`). One line of small print goes in the popup's place
/// rather than nothing at all, so nobody is left looking for a control that has
/// quietly gone.
private struct BorderPositionRow: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerEffectRow

    /// Whether this ring has a side of an edge to sit on at all.
    private var isAboutAnEdge: Bool {
        let borders = editorState.layerStyleSelection.borders(at: row.index)
        guard borders.hasLettersEverywhere else { return true }
        let reading = borders.reading { $0.borderEffect(at: row.index)?.follows ?? .letters }
        return !reading.isMixed && reading.value == .box
    }

    /// Whether every layer this row speaks for is an open line. One closed
    /// shape in the selection and the popup comes back: the answer still moves
    /// that one's ring.
    private var ringsALine: Bool {
        editorState.layerStyleSelection.borders(at: row.index).isOpenLineEverywhere
    }

    var body: some View {
        if ringsALine {
            lineNote
        } else if isAboutAnEdge {
            picker
        }
    }

    /// Why the Position popup is not here, in the place it would have been.
    @ViewBuilder private var lineNote: some View {
        let words = "Centered on the line"
        Text(words)
            .panelHelp("An open path is a line, so the border runs down the middle of it")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelReadout(words)
            // Named like the popup it replaces, so a walk asking for Position
            // inside this border finds the answer rather than nothing.
            .playtestField("Position")
    }

    @ViewBuilder private var picker: some View {
        let borders = editorState.layerStyleSelection.borders(at: row.index)
        let ids = borders.layerIDs
        let reading = borders.reading { $0.borderEffect(at: row.index)?.position ?? .outside }
        HStack(alignment: .firstTextBaseline, spacing: ColorPartLayout.spacing) {
            Text("Position")
                .panelRowName()
                .frame(width: ColorPartLayout.nameWidth, alignment: .leading)
            Picker("Position", selection: Binding(
                get: { reading.isMixed ? nil : reading.value },
                set: { new in
                    guard let new else { return }
                    editorState.setBorderEffectPosition(at: row.index, ids: ids, to: new)
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
                // A width rather than `fixedSize`, for the reason the Kind
                // popup carries one: an ideal-width menu inside the dock's
                // column pushed the whole pane wider than the window.
                .frame(width: 92, alignment: .leading)
                .disabled(ids.isEmpty)
                .panelHelp("Inside keeps the ring within the layer. Outside grows it past the edge.")
                .playtestControl("Position", detail: reading.isMixed ? "mixed"
                                    : (reading.value ?? .outside).title)
            Spacer(minLength: 0)
        }
        // No field name of its own: it belongs to the border row above it, so
        // a walk names it `{"control": "Position", "in": "Border 2"}` and two
        // borders never answer to the same words.
    }
}

/// How thick one added ring is.
private struct BorderWidthRow: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerEffectRow

    var body: some View {
        let borders = editorState.layerStyleSelection.borders(at: row.index)
        let index = row.index
        let range = Double(BorderEffect.widthRange.lowerBound)...Double(BorderEffect.widthRange.upperBound)
        LayerStyleSlider(layerIDs: borders.layerIDs, label: "Width",
                         reading: borders.number { $0.borderEffect(at: index)?.width ?? 0 },
                         range: range) { style, v in
            style.updateBorderEffect(at: index) { $0.width = CGFloat(v) }
        }
    }
}

/// How far one added ring stands AWAY from the edge it sits against.
///
/// Nought puts it right on that edge, which is where every ring the app has
/// ever drawn sits. Ten moves an inside ring ten points further in and an
/// outside one ten points further out, and that gap is what makes two rings on
/// one shape worth having: a tight line on the edge and a second standing off
/// it (`BorderPosition.swift`).
///
/// Centred straddles the edge with half the line on either side, so there is no
/// side to measure from. Rather than a slider that does nothing, the row goes
/// and one line of small print says why — and, when a number is being held from
/// an earlier Inside or Outside, that it is being kept rather than thrown away.
private struct BorderOffsetRow: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerEffectRow

    /// What the picked rings say about where they sit. Nil when they disagree.
    private var position: BorderPosition? {
        let borders = editorState.layerStyleSelection.borders(at: row.index)
        let reading = borders.reading { $0.borderEffect(at: row.index)?.position ?? .outside }
        return reading.isMixed ? nil : reading.value
    }

    /// Whether this ring has a side of an edge to stand off from at all. A ring
    /// following a label's LETTERS has no inside and no outside, exactly as the
    /// Position popup above it has none to offer (`BorderFollows.swift`), and
    /// neither has a ring round an OPEN PATH (`Layer.ringsAnOpenLine`).
    private var isAboutAnEdge: Bool {
        let borders = editorState.layerStyleSelection.borders(at: row.index)
        if borders.isOpenLineEverywhere { return false }
        guard borders.hasLettersEverywhere else { return true }
        let reading = borders.reading { $0.borderEffect(at: row.index)?.follows ?? .letters }
        return !reading.isMixed && reading.value == .box
    }

    var body: some View {
        if isAboutAnEdge {
            // Rings that disagree about where they sit still get the slider: it
            // means something on every one of them that is not centred.
            if position == .center { centerNote } else { slider }
        }
    }

    @ViewBuilder private var slider: some View {
        let borders = editorState.layerStyleSelection.borders(at: row.index)
        let index = row.index
        let low = Double(BorderEffect.offsetRange.lowerBound)
        let high = Double(BorderEffect.offsetRange.upperBound)
        let range = low...high
        LayerStyleSlider(layerIDs: borders.layerIDs, label: "Offset",
                         reading: borders.number { $0.borderEffect(at: index)?.offset ?? 0 },
                         range: range) { style, v in
            style.updateBorderEffect(at: index) { $0.offset = CGFloat(v) }
        }
    }

    private func centerHelp(kept: CGFloat) -> String {
        kept > 0
            ? "Center straddles the edge. The \(points(Double(kept))) offset comes back on Inside or Outside"
            : "Center straddles the edge, so it has no offset"
    }

    /// Why the Offset row is not here, in the place it would have been.
    @ViewBuilder private var centerNote: some View {
        let borders = editorState.layerStyleSelection.borders(at: row.index)
        let index = row.index
        let held = borders.number { $0.borderEffect(at: index)?.offset ?? 0 }
        let kept = (held.isMixed ? nil : held.value).map { CGFloat($0) } ?? 0
        // Short, because it sits under the Width for as long as the ring is
        // centred: two lines of small print explaining a missing row is a row
        // of its own. It says the number is kept, so nobody has to guess
        // whether switching to Center threw it away.
        let words = kept > 0 ? "Offset \(points(Double(kept))) kept" : "No offset on Center"
        Text(words)
            .panelHelp(centerHelp(kept: kept))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelReadout(words)
            // Its own name, so a walk can ask for it the way it asks for any
            // other row inside a border: `{"field": "Offset", "in": "Border"}`.
            .playtestField("Offset")
    }
}

/// Which side of the layer's edge one glow lights: outside it, or inside it.
///
/// The same shape of control the shadow's Kind is, because it is the same kind
/// of question. An outer glow and an inner glow are two entries in the list
/// that differ by nothing but this, so the plus offers Glow once and this is
/// what turns one into the other in place.
private struct GlowKindRow: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerEffectRow

    var body: some View {
        let glows = editorState.layerStyleSelection.glows(at: row.index)
        let ids = glows.layerIDs
        let reading = glows.reading { $0.glowEffect(at: row.index)?.kind ?? .outer }
        HStack(alignment: .firstTextBaseline, spacing: ColorPartLayout.spacing) {
            Text("Kind")
                .panelRowName()
                .frame(width: ColorPartLayout.nameWidth, alignment: .leading)
            Picker("Kind", selection: Binding(
                get: { reading.isMixed ? nil : reading.value },
                set: { new in
                    guard let new else { return }
                    editorState.setGlowKind(at: row.index, ids: ids, to: new)
                })) {
                    if reading.isMixed {
                        Text(LayerStyleSelection.mixedText).tag(GlowKind?.none)
                    }
                    ForEach(GlowKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(GlowKind?.some(kind))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                // A width rather than `fixedSize`, for the reason the shadow's
                // Kind popup carries one: an ideal-width menu inside the dock's
                // column pushed the whole pane wider than the window.
                .frame(width: 92, alignment: .leading)
                .disabled(ids.isEmpty)
                .panelHelp("Outer throws the halo past the layer's edge. "
                      + "Inner lights the edge from inside.")
                .playtestControl("Kind", detail: reading.isMixed ? "mixed"
                                    : (reading.value ?? .outer).title)
            Spacer(minLength: 0)
        }
        // No field name of its own: it belongs to the glow row above it, so a
        // walk names it `{"control": "Kind", "in": "Glow 2"}` and two glows
        // never answer to the same words.
    }
}

/// How far one glow reaches, how gently it stops, and how strong it is.
///
/// Size and Softness are not two names for one thing: size decides how far the
/// light gets, softness decides how abruptly it ends. A tight bright ring is a
/// big size with little softness; a bloom is the other way round.
private struct GlowSlidersRow: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerEffectRow

    var body: some View {
        let glows = editorState.layerStyleSelection.glows(at: row.index)
        let ids = glows.layerIDs
        let index = row.index
        let sizes = Double(GlowEffect.sizeRange.lowerBound)...Double(GlowEffect.sizeRange.upperBound)
        let softness = Double(GlowEffect.softnessRange.lowerBound)
            ... Double(GlowEffect.softnessRange.upperBound)
        LayerStyleSlider(layerIDs: ids, label: "Size",
                         reading: glows.number { $0.glowEffect(at: index)?.size ?? 0 },
                         range: sizes) { style, v in
            style.updateGlowEffect(at: index) { $0.size = CGFloat(v) }
        }
        LayerStyleSlider(layerIDs: ids, label: "Softness",
                         reading: glows.number { $0.glowEffect(at: index)?.radius ?? 0 },
                         range: softness) { style, v in
            style.updateGlowEffect(at: index) { $0.radius = CGFloat(v) }
        }
        LayerStyleSlider(layerIDs: ids, label: "Opacity",
                         reading: glows.reading { $0.glowEffect(at: index)?.opacity ?? 0 },
                         range: 0...1, typing: .percent) { style, v in
            style.updateGlowEffect(at: index) { $0.opacity = v }
        }
    }
}

/// How soft the layer is. One number, because a layer has one softness: adding
/// a second blur would be two answers to one question, so the plus offers it
/// once and then stops.
private struct BlurEffectRow: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerEffectRow

    var body: some View {
        let selection = editorState.layerStyleSelection
        LayerStyleSlider(layerIDs: row.switchIDs, label: "Amount",
                         reading: selection.number { $0.blurRadius }, range: 0...50,
                         field: .blur) { style, v in
            style.blurRadius = CGFloat(v)
        }
    }
}

/// Where the shadow is thrown: behind the layer, or into it.
///
/// It reads Mixed when the picked layers disagree, and picking either answer
/// gives it to all of them, which is what every other control in this panel
/// does with a selection that does not agree.
private struct ShadowKindRow: View {
    @Environment(EditorState.self) private var editorState
    let index: Int
    let ids: [UUID]

    var body: some View {
        let reading = editorState.layerStyleSelection.shadows(at: index)
            .reading { $0.shadow(at: index)?.kind ?? .drop }
        HStack(alignment: .firstTextBaseline, spacing: ColorPartLayout.spacing) {
            Text("Kind")
                .panelRowName()
                .frame(width: ColorPartLayout.nameWidth, alignment: .leading)
            Picker("Kind", selection: Binding(
                get: { reading.isMixed ? nil : reading.value },
                set: { new in
                    guard let new else { return }
                    editorState.setShadowKind(index: index, ids: ids, to: new)
                })) {
                    if reading.isMixed {
                        Text(LayerStyleSelection.mixedText).tag(ShadowKind?.none)
                    }
                    ForEach(ShadowKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(ShadowKind?.some(kind))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                // A width, not `fixedSize`: a menu picker asked for its ideal
                // width inside the dock's column pushed the whole pane wider
                // than the window, and the shell answered by auto-collapsing
                // the dock the moment a SECOND one appeared (2026-09-07).
                .frame(width: 92, alignment: .leading)
                .panelHelp("Drop throws it behind the layer. Inner casts it into the layer.")
                .playtestControl("Kind", detail: reading.isMixed ? "mixed"
                                    : (reading.value ?? .drop).title)
            Spacer(minLength: 0)
        }
        // No field name of its own: it belongs to the shadow row above it, so
        // a walk names it `{"control": "Kind", "in": "Shadow 2"}` and two
        // shadows never answer to the same words.
    }
}

/// The plus on the Effects header: one press, a short menu, a new row.
///
/// No dialog and no blank state to fill in. The effect arrives with settings
/// that already look like something, so the next thing you do is tune it rather
/// than build it.
///
/// The menu is ONE ITEM PER KIND — Shadow, Glow, Border, Blur. It used to split
/// the shadow in two, a Shadow and an Inner Shadow, which read as if they were
/// unrelated ideas when they are one effect with a Kind on it; the row you get
/// carries that Kind, and switching it turns the shadow inner in place. A glow
/// is offered once for the same reason, and a border works the same way: its
/// Position is what makes an inner one and an outer one two entries in the
/// list.
///
/// It rides the HEADER rather than the foot of the list: the dock caps a
/// section's height and scrolls the rest inside it, and one shadow is already
/// enough to push a foot button out of sight (2026-09-07).
struct AddEffectButton: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        Menu {
            ForEach(AddableEffect.allCases) { kind in
                Button(kind.title) { editorState.addEffect(kind) }
                    .disabled(!editorState.canAddEffect(kind))
                    .panelHelp(kind.summary)
            }
            // ...and the effects somebody has already tuned and named. This is
            // the route by which a saved effect reaches a layer that has
            // nothing like it yet, and it lives here because adding a saved
            // effect IS adding an effect: a Style menu on a row can only reach
            // layers that already hold that effect at that place
            // (`EffectStylePanel.swift`).
            let saved = editorState.namedEffectStyles
            if !saved.isEmpty {
                Section("Saved effects") {
                    ForEach(saved) { style in
                        Button(style.name) { editorState.addEffectStyle(styleID: style.id) }
                            .panelHelp(EffectStyleNaming.effectText(style.effect))
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!editorState.hasRestylableSelection)
        // The plus says nothing out loud, so this is both what a screen reader
        // announces and the name a scripted walk opens it by.
        .accessibilityLabel("Add Effect")
        .panelHelp("Add an effect: a shadow, a glow, a border or a blur")
        .playtestControl("Add Effect", detail: "the plus on the Effects header")
    }
}
