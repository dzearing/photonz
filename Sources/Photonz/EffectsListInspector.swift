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
    /// effect, how tall it is and whether it is open. The dock's height budget
    /// keeps room to draw the first OPEN one whole, so a squeezed Effects
    /// section never cuts a slider in half.
    var onPanes: (([DockHeightBudget.Block]) -> Void)?

    /// Each effect's measured extent, by its place in the list.
    @State private var panes: [Int: DockHeightBudget.Block] = [:]

    var body: some View {
        let rows = editorState.layerEffectRows
        VStack(alignment: .leading, spacing: Self.paneSpacing) {
            if rows.isEmpty {
                empty
            } else {
                ForEach(rows) { row in
                    EffectRowView(row: row, onExtent: { panes[row.index] = $0 })
                }
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        // Measured like an effect, and folded like one, so a
                        // cut that lands on it shows its top rather than
                        // ending the list on empty glass.
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            panes[rows.count] = DockHeightBudget.Block(height: $0, isOpen: false)
                        }
                }
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, Self.listInset)
        // Both, because either can move on its own: an effect folding changes
        // a height, and removing one changes how many there are while the
        // measurements of the rest stay exactly as they were.
        .onChange(of: panes, initial: true) { report(rows.count + (caption == nil ? 0 : 1)) }
        .onChange(of: rows.count) { report(rows.count + (caption == nil ? 0 : 1)) }
    }

    /// The panes in list order, dropping any measurement left behind by an
    /// effect that has since been removed.
    private func report(_ count: Int) {
        onPanes?((0..<count).compactMap { panes[$0] })
    }

    /// What an untouched shape shows: one line saying what this list is for and
    /// where the gesture is. An empty section with nothing in it at all reads as
    /// broken, and the plus on the header is small enough to be missed the first
    /// time.
    private var empty: some View {
        Text("Nothing added yet. Use the plus above for a shadow, a glow, a border or a blur.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .playtestField("Effects Empty")
            .panelStartProbe(.row, owner: "Effects empty")
    }

    private var caption: String? {
        let count = editorState.colorStyleSelectionCount
        guard count > 1 else { return nil }
        return "\(count) layers. Adding, removing or reordering here reaches "
            + "every one of them, in one step."
    }
}

/// One effect, drawn as a SMALL PANE: a chevron, a lit name, a grip, an eye, a
/// cross, and its own settings under it behind a rule that says they are its.
///
/// The rule is the fix for the thing the user reported on 2026-09-07: a
/// shadow's Blur, Size and Opacity drawn flat under its row read as a second
/// copy of the layer's own Blur and Opacity. Now they are visibly the shadow's.
///
/// The heading is the fix for what they reported on 2026-09-08, looking at a
/// Border: the row wore a tick where every other heading in the dock wears a
/// chevron, and its title weighed exactly what the settings under it weighed,
/// so the row and its contents ran together into one grey list. An effect is
/// not a row with some numbers after it — it is a section of its own, four or
/// five settings deep, which is why it is drawn like one:
///
/// - **A chevron leads it** and folds its settings away, the same glyph the
///   layers list uses for a group and the dock uses for a section, one step
///   smaller (`PanelSectionLook.EffectRow`).
/// - **The name is lit**, semibold in the primary ink, so it reads as the
///   header of what sits under it rather than as another label.
/// - **The switch is an eye** at the end of the row, drawn and behaving like
///   the eye on a layer row, because "this one is not showing" is a thing this
///   app already has one picture for.
private struct EffectRowView: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerEffectRow
    /// How tall this pane is and whether it is open, told to the list so the
    /// dock can keep room for it. See `EffectsListInspector.onPanes`.
    let onExtent: (DockHeightBudget.Block) -> Void

    /// What is being held over this row right now, while it is switched off.
    @State private var incoming: ColorDrop.Answer?
    /// How far the row has been dragged, while it is being dragged. The list
    /// order IS the paint order, so this is not decoration: it is how you say
    /// which shadow goes over which.
    @State private var carry: CGFloat = 0
    /// The height of one block, measured off this row, so a drag can be turned
    /// into a number of places moved.
    @State private var blockHeight: CGFloat = 0

    /// Whether this effect's settings are folded away right now. Held by the
    /// editor rather than by this view, which is rebuilt whenever anything
    /// about the selection moves.
    private var isFolded: Bool { editorState.isEffectFolded(row) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: ColorPartLayout.spacing) {
                // The chevron and the lit name, as one press: a section header
                // opens on its title as well as on its arrow, and a 9pt glyph
                // on its own is a mean target for a control you use as often
                // as this one.
                foldControl
                // The colour is NOT here. It is a setting of the effect, so it
                // sits with the width and the position under the rule below,
                // and the header carries only the name, the eye and the two
                // controls that act on the whole entry (reported by the user on
                // 2026-09-07: the colour was the one setting in the wrong
                // place, and the only colour in the app that could not take a
                // saved name).
                if !row.isOn, let paint = incoming?.landing?.paint {
                    LandingSwatch(paint: paint)
                } else if !row.isOn, row.isMixed {
                    MixedWord()
                        .frame(minWidth: ColorPartLayout.readoutWidth,
                               minHeight: ColorPartLayout.rowHeight, alignment: .leading)
                }
                Spacer(minLength: 0)
                // The three things at the end of the row: a grip to put the
                // entry somewhere else in the order, the eye that stops it
                // drawing, and the cross that takes it out. The eye sits
                // BETWEEN them so the cross keeps the panel edge it has always
                // had, and so the two presses that mean opposite things — stop
                // it drawing, throw it away — are never the same target twice
                // running.
                if row.canReorder { grip }
                effectEye
                removeButton
            }
            .modifier(OffEffectColorDrop(row: row, active: !row.isOn, incoming: $incoming))
            if let note = row.reachNote {
                // On the panel's margin, the same as the Appearance list above
                // it: a note padded in under the row's NAME made a second left
                // edge inside the section, which is what the user reported on
                // 2026-09-08. It sits directly under the row it is about, one
                // gap below it and a pane gap above the next effect, so what it
                // belongs to is said by where it sits.
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isFolded {
                // Shown whether or not the effect is drawing. An effect that is
                // off keeps every number on it, and the reason you switched it
                // off is usually that you are about to change one of them, so
                // the settings stay open and stay live and only say quietly, by
                // being a shade fainter, that nothing they describe is on the
                // canvas right now.
                OwnedSettings(owner: row.title) { settings }
                    // Flattened BEFORE it is faded. Without the group SwiftUI
                    // fades each child on its own, and the colour well is a
                    // solid swatch drawn over a checkerboard that says "this
                    // paint has alpha": fade them separately and the checker
                    // comes up through the swatch, so a switched-off border
                    // claimed its colour was half transparent (seen in a probe
                    // capture, 2026-09-08).
                    .compositingGroup()
                    .opacity(row.isOn || row.isMixed
                             ? 1 : PanelSectionLook.EffectRow.offSettingsOpacity)
            }
        }
        .playtestField(row.title)
        .panelStartProbe(.row, owner: row.title)
        // The same three moves the grip and the cross make, for a hand that is
        // not going to drag a 20pt strip: a pointer that right clicks, and a
        // screen reader. It is also the only way a scripted walk can reorder,
        // since a synthesized press cannot start a SwiftUI drag.
        .contextMenu { rowMenu }
        .offset(y: carry)
        .zIndex(carry == 0 ? 0 : 1)
        .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { new in
                    blockHeight = new
                    report(new)
                }
        }
        // A fold always changes the height, so this is belt and braces — but
        // the dock's floor turns on `isOpen`, and a floor that lagged a fold by
        // a frame is the same cut slider one frame later.
        .onChange(of: isFolded) { report(blockHeight) }
    }

    private func report(_ height: CGFloat) {
        onExtent(DockHeightBudget.Block(height: height, isOpen: !isFolded))
    }

    // MARK: The three things a list row can do

    @ViewBuilder private var rowMenu: some View {
        if row.canReorder {
            Button("Move Up") { move(to: row.index - 1) }
                .disabled(!editorState.canMoveEffect(row: row, to: row.index - 1))
            Button("Move Down") { move(to: row.index + 1) }
                .disabled(!editorState.canMoveEffect(row: row, to: row.index + 1))
            Divider()
        }
        Button("Remove") { editorState.removeEffect(row: row) }
    }

    private func move(to target: Int) {
        editorState.moveEffect(row: row, to: target)
    }

    private var grip: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10))
            .foregroundStyle(carry == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            .frame(height: ColorPartLayout.rowHeight)
            .panelEdgeIcon("reorder", of: row.title)
            .contentShape(Rectangle())
            .panelHelp("Drag to change what paints over what")
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { carry = $0.translation.height }
                    .onEnded { value in
                        defer { carry = 0 }
                        guard blockHeight > 1 else { return }
                        let steps = Int((value.translation.height / blockHeight).rounded())
                        move(to: row.index + steps)
                    }
            )
            .playtestControl("Reorder", detail: "drag to change the paint order")
    }

    private var removeButton: some View {
        Button {
            editorState.removeEffect(row: row)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .frame(height: ColorPartLayout.rowHeight)
                .panelEdgeIcon("remove", of: row.title)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
        .panelHelp("Remove this \(row.kind.title.lowercased())")
        .playtestControl("Remove", detail: "takes the effect out of the list")
    }

    // MARK: The heading

    /// The chevron and the name, as one control.
    ///
    /// The chevron sits in the column the tick used to hold, centred on
    /// `ColorPartLayout.tickCenter`, because that is where `OwnedSettings`
    /// hangs the rule that marks this effect's settings: the rule now hangs
    /// from the chevron that folds them, which is a better sentence than the
    /// one it replaced.
    private var foldControl: some View {
        Button {
            withAnimation(.spring(duration: 0.2)) {
                editorState.toggleEffectFolded(row)
            }
        } label: {
            HStack(alignment: .top, spacing: ColorPartLayout.spacing) {
                PanelFoldChevron(isFolded: isFolded)
                Text(row.title)
                    .font(PanelSectionLook.EffectRow.titleFont)
                    // Lit when it is drawing, quiet when it is not, so a
                    // switched-off effect reads as off from the name as well as
                    // from the eye at the other end of the row.
                    .foregroundStyle(row.isOn || row.isMixed
                                     ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: ColorPartLayout.labelWidth,
                           height: ColorPartLayout.rowHeight, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .panelHelp(isFolded ? "Show this \(row.kind.title.lowercased())'s settings"
              : "Hide this \(row.kind.title.lowercased())'s settings")
        .accessibilityLabel(row.title)
        .accessibilityValue(isFolded ? "settings hidden" : "settings showing")
        // The same word the layers list uses for the chevron on a group, so a
        // scripted walk folds an effect the way it opens a group, and so the
        // one gesture has one name across the app.
        .playtestControl("Twist", detail: isFolded ? "shut" : "open")
    }

    // MARK: The eye

    /// Whether this effect is drawing. Mixed reads as off, because a Mac has no
    /// third eye and the row says "mixed" in words beneath itself.
    private var isShowing: Bool { row.isMixed ? false : row.isOn }

    /// The switch, drawn as the eye a layer row wears: the same glyph pair, the
    /// same 11pt, the same tertiary tint when off, in the same shared slot down
    /// the panel's edge. Asked for by the user on 2026-09-08 — the app has one
    /// picture for "this is not showing" and an effect had a second one.
    private var effectEye: some View {
        Button {
            editorState.setEffectEnabled(row: row, on: row.isMixed ? true : !isShowing)
        } label: {
            Image(systemName: isShowing ? "eye" : "eye.slash")
                .font(.system(size: 11))
                .foregroundStyle(isShowing ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(height: ColorPartLayout.rowHeight)
                .panelEdgeIcon("eye", of: row.title)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(row.isMixed ? MixedLook.controlOpacity : 1)
        .panelHelp(row.switchIDs.count > 1
              ? "Stops it drawing on all \(row.switchIDs.count) of them, and keeps its settings"
              : "Stops it drawing, and keeps its settings")
        .accessibilityLabel(isShowing ? "Hide \(row.title)" : "Show \(row.title)")
        // The row's own reading, not a bare on/off: over two shapes where only
        // one holds the effect the switch used to announce a flat "on" while
        // the line under it said "Applies to 1 of the 2 selected layers". A
        // screen reader hears the control, not the caption.
        .accessibilityValue(row.switchReading)
        // Still "Switch": it is the row's switch whatever it is drawn as, and
        // every scripted walk that compares a shape with and without an effect
        // reaches it by that word.
        .playtestControl("Switch", detail: row.switchReading)
    }

    // MARK: The settings

    @ViewBuilder private var settings: some View {
        // The colour first, whatever the effect is, so the list reads one way:
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
    let row: LayerEffectRow

    var body: some View {
        if let target = ColorTarget(effect: row) {
            HStack(alignment: .top, spacing: ColorPartLayout.spacing) {
                Text("Color")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: ColorPartLayout.labelWidth,
                           height: ColorPartLayout.rowHeight, alignment: .leading)
                // The KIND's word rather than the row's, so two borders both
                // offer "Saved border colors" instead of one of them offering
                // "Saved border 2 colors". Which of the two a walk means is
                // already settled by the row it is in.
                ColorStyleRow(target: target, part: row.kind.title)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: ColorPartLayout.labelWidth, alignment: .leading)
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

    var body: some View {
        if isAboutAnEdge { picker }
    }

    @ViewBuilder private var picker: some View {
        let borders = editorState.layerStyleSelection.borders(at: row.index)
        let ids = borders.layerIDs
        let reading = borders.reading { $0.borderEffect(at: row.index)?.position ?? .outside }
        HStack(alignment: .firstTextBaseline, spacing: ColorPartLayout.spacing) {
            Text("Position")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: ColorPartLayout.labelWidth, alignment: .leading)
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
                         range: range,
                         format: points) { style, v in
            style.updateBorderEffect(at: index) { $0.width = CGFloat(v) }
        }
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
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: ColorPartLayout.labelWidth, alignment: .leading)
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
                         range: sizes,
                         format: points) { style, v in
            style.updateGlowEffect(at: index) { $0.size = CGFloat(v) }
        }
        LayerStyleSlider(layerIDs: ids, label: "Softness",
                         reading: glows.number { $0.glowEffect(at: index)?.radius ?? 0 },
                         range: softness,
                         format: points) { style, v in
            style.updateGlowEffect(at: index) { $0.radius = CGFloat(v) }
        }
        LayerStyleSlider(layerIDs: ids, label: "Opacity",
                         reading: glows.reading { $0.glowEffect(at: index)?.opacity ?? 0 },
                         range: 0...1,
                         format: { "\(Int(($0 * 100).rounded()))%" }) { style, v in
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
                         format: points, field: .blur) { style, v in
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
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: ColorPartLayout.labelWidth, alignment: .leading)
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
