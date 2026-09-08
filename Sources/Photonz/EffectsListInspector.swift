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
/// - **A row can be taken out.** The cross removes the effect; the tick beside
///   it keeps every number on it and stops it drawing. Compare-with-and-without
///   is the thing you do constantly, so it is the gesture that keeps your work.
struct EffectsListInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let rows = editorState.layerEffectRows
        VStack(alignment: .leading, spacing: 16) {
            if rows.isEmpty {
                empty
            } else {
                ForEach(rows) { row in
                    EffectRowView(row: row)
                }
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
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
    }

    private var caption: String? {
        let count = editorState.colorStyleSelectionCount
        guard count > 1 else { return nil }
        return "\(count) layers. Adding, removing or reordering here reaches "
            + "every one of them, in one step."
    }
}

/// One effect: its name, its tick, the colour it paints, a grip, a cross, and
/// its own settings behind a rule that says they are its.
///
/// The rule is the fix for the thing the user actually reported on 2026-09-07:
/// a shadow's Blur, Size and Opacity drawn flat under its row read as a second
/// copy of the layer's own Blur and Opacity. Now they are visibly the shadow's.
private struct EffectRowView: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerEffectRow

    /// What is being held over this row right now, while it is switched off.
    @State private var incoming: ColorDrop.Answer?
    /// How far the row has been dragged, while it is being dragged. The list
    /// order IS the paint order, so this is not decoration: it is how you say
    /// which shadow goes over which.
    @State private var carry: CGFloat = 0
    /// The height of one block, measured off this row, so a drag can be turned
    /// into a number of places moved.
    @State private var blockHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: ColorPartLayout.spacing) {
                // The tick and then the name, in that order, from the one place
                // the panel's columns live. Every effect row here and every part
                // row in Appearance reads the same way because neither of them
                // arranges the two itself.
                PanelRowHead(title: row.title) { effectSwitch }
                // The colour is NOT here. It is a setting of the effect, so it
                // sits with the width and the position under the rule below,
                // and the header carries only the name, the tick and the two
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
                // The two things every entry in a list you added to has: a grip
                // to put it somewhere else in the order, and a cross to take it
                // out. They sit at the end of the row so the name, the tick and
                // the colour stay in the columns Appearance uses.
                if row.canReorder { grip }
                removeButton
            }
            .modifier(OffEffectColorDrop(row: row, active: !row.isOn, incoming: $incoming))
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
            if row.isOn {
                OwnedSettings(owner: row.title) { settings }
            }
        }
        .playtestField(row.title)
        // The same three moves the grip and the cross make, for a hand that is
        // not going to drag a 20pt strip: a pointer that right clicks, and a
        // screen reader. It is also the only way a scripted walk can reorder,
        // since a synthesized press cannot start a SwiftUI drag.
        .contextMenu { rowMenu }
        .offset(y: carry)
        .zIndex(carry == 0 ? 0 : 1)
        .background {
            GeometryReader { proxy in
                Color.clear.onAppear { blockHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, new in blockHeight = new }
            }
        }
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
            .help("Drag to change what paints over what")
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
        .help("Remove this \(row.kind.title.lowercased())")
        .playtestControl("Remove", detail: "takes the effect out of the list")
    }

    // MARK: The tick

    private var effectSwitch: some View {
        Toggle(row.title, isOn: Binding(get: { row.isMixed ? false : row.isOn },
                                        set: { on in
            editorState.setEffectEnabled(row: row, on: row.isMixed ? true : on)
        }))
            .labelsHidden()
            .controlSize(.small)
            .opacity(row.isMixed ? MixedLook.controlOpacity : 1)
            .help(row.switchIDs.count > 1
                  ? "Stops it drawing on all \(row.switchIDs.count) of them, and keeps its settings"
                  : "Stops it drawing, and keeps its settings")
            // The row's own reading, not a bare on/off: over two shapes where
            // only one holds the effect the tick used to announce a flat "on"
            // while the line under it said "Applies to 1 of the 2 selected
            // layers". A screen reader hears the control, not the caption.
            .accessibilityValue(row.switchReading)
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

/// Which side of the layer's edge one added ring sits on.
///
/// The same three words the Outline row in Appearance uses, because it is the
/// same question: a line is inside the edge, straddling it, or outside it. An
/// inner border and an outer border are two entries in the list that differ by
/// nothing but this.
private struct BorderPositionRow: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerEffectRow

    var body: some View {
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
                .help("Inside keeps the ring within the layer. Outside grows it past the edge.")
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
                .help("Outer throws the halo past the layer's edge. "
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
                .help("Drop throws it behind the layer. Inner casts it into the layer.")
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
                    .help(kind.summary)
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
        .help("Add an effect: a shadow, a glow, a border or a blur")
        .playtestControl("Add Effect", detail: "the plus on the Effects header")
    }
}
