import AppKit
import PhotonzCore
import SwiftUI

// The Style row inside one effect, the effect tiles on the Library's Styles
// shelf, and the section behind a tile where a saved effect is edited (Next,
// `next-styles`).
//
// The colour half of the same idea is `ColorStylePanel.swift` and the text half
// is `TextStylePanel.swift`, and everything here is deliberately the same shape
// as both: one menu that saves a name or wears one, one tile on one shelf, one
// section behind the tile where the style is edited.

// MARK: - The Style row inside one effect

/// The whole Style row for one effect: the word Style, the menu, and the name
/// field the menu raises when you save.
///
/// It sits at the TOP of the effect's settings, above the colour, for the same
/// reason the text one sits at the top of the Text section: it is the shortest
/// way to set every row under it at once, and a control that sets five rows
/// placed below those five rows is a control nobody finds.
///
/// It is not on the row's HEADER. That header already carries a chevron, a
/// name, a grip, an eye and a cross, and a sixth control on it would be
/// crowding for the sake of symmetry with a colour well that is not there
/// either — the colour moved down into the settings on 2026-09-07 for exactly
/// this reason.
struct EffectStyleRow: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerEffectRow

    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    private var isNaming: Bool { editorState.isNamingEffectStyle(row: row) }

    var body: some View {
        if editorState.effectStylesEnabled, !editorState.effectStyleSelection(row: row).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: ColorPartLayout.spacing) {
                    Text("Style")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: ColorPartLayout.labelWidth, alignment: .leading)
                    EffectStyleControl(row: row)
                    Spacer(minLength: 0)
                }
                if isNaming { namingField }
                if let note = editorState.effectStyleSelection(row: row).unlinkNote {
                    // Said BEFORE the settings under it are touched, because a
                    // name that quietly stopped being worn is one nobody
                    // notices until an edit to it fails to reach a layer.
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Named for the effect it belongs to rather than for the word on
            // screen. The label beside it says Style, and so does the Text
            // section's own Style row, so a text layer — which has a shadow in
            // its Effects list — showed a walk two rows called Style and could
            // open neither. The row it is in is what tells them apart, exactly
            // as two shadows are told apart.
            .playtestField("\(row.title) Style")
            // Saving asks for the name first, IN the dock, rather than making a
            // style called something and hoping you find where to rename it. It
            // opens on a name nobody is using, with the text selected, so
            // naming it is typing and Return is enough.
            .onChange(of: isNaming, initial: true) { _, naming in
                guard naming else { return }
                draft = editorState.suggestedEffectStyleName(kind: row.kind)
                nameFocused = true
                DispatchQueue.main.async { NSApp.keyWindow?.firstResponder?.trySelectAllText() }
            }
        }
    }

    private var namingField: some View {
        HStack(spacing: 6) {
            TextField("Style name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .controlSize(.small)
                .focused($nameFocused)
                .onSubmit(save)
                // Escape drops it: nothing was made, so there is nothing to
                // undo either. Both keys hand the keyboard back to the picture.
                .nameFieldKeys(commit: save,
                               revert: { editorState.endNamingEffectStyle() })
            Button("Save", action: save)
                .controlSize(.small)
                .panelHelp("Saves this \(row.kind.title.lowercased()) under that name")
                .playtestControl("Save")
        }
        .padding(.top, 2)
    }

    private func save() {
        editorState.saveEffectStyle(row: row, name: draft)
    }
}

/// The menu on an effect's Style row: it saves this effect under a name, or
/// points it at a name you already have.
///
/// It speaks for every layer the row reaches. One card picked or twenty,
/// choosing Card lift here re-sets all of their shadows, in one step that one
/// undo puts back.
///
/// Three states, exactly the way a colour row and a text row read:
///
/// - **An effect of its own.** The button is a quiet glyph: "Save as Style"
///   makes one, and any saved effect OF THIS KIND can be picked straight from
///   the menu.
/// - **Wearing a style.** The button says the style's NAME, so a linked effect
///   and a hand-tuned one never look alike. Every setting under it still
///   answers, and changing one takes the effect off the style, which the row
///   says in words before the click and one undo puts back.
/// - **Disagreeing.** Layers wearing different styles, or tuned differently,
///   say Mixed rather than naming one of them. Picking a name still lands on
///   all of them, which is the way out.
private struct EffectStyleControl: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerEffectRow

    var body: some View {
        let selection = editorState.effectStyleSelection(row: row)
        let style = editorState.boundEffectStyle(row: row)
        // Only this kind. A menu on a Shadow row that could turn it into a
        // border would be a row whose title lies; the plus on the header is
        // where an effect of another kind comes from.
        let styles = editorState.effectStyles(for: row.kind)
        Menu {
            if let style {
                Section("Using \(style.name)") {
                    Button("Edit \(style.name) in the Library") {
                        // The shelf first, then the tile: picking a tile in a
                        // Library nobody has opened selects something there is
                        // nowhere to see.
                        editorState.showStylesShelf()
                        editorState.selectLibraryItem(style.id.uuidString)
                    }
                    Button(unlinkTitle(selection)) { editorState.unlinkEffectStyle(row: row) }
                }
            } else if selection.wearsAnyStyle {
                // Several styles under one row: there is no name to print, but
                // letting go of all of them is still one honest move.
                Section("Using more than one style") {
                    Button(unlinkTitle(selection)) { editorState.unlinkEffectStyle(row: row) }
                }
            } else if selection.savableEffect != nil {
                Button(saveTitle(selection)) { editorState.beginNamingEffectStyle(row: row) }
            }
            if !styles.isEmpty {
                Section(selection.count > 1
                        ? "Saved \(row.kind.title.lowercased())s, for all \(selection.count)"
                        : "Saved \(row.kind.title.lowercased())s") {
                    ForEach(styles) { option in
                        Button {
                            editorState.useEffectStyle(row: row, styleID: option.id)
                        } label: {
                            Label {
                                Text(option.name)
                            } icon: {
                                Image(systemName: option.id == style?.id
                                      ? "checkmark.circle.fill" : "circle.fill")
                            }
                        }
                    }
                }
            }
        } label: {
            label(style, selection)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .panelHelp(help(selection, style))
        // Named, so a walk reaches this menu by the word beside it rather than
        // by the glyph on it. It belongs to the effect above it, so a walk
        // names it `{"control": "Style", "in": "Shadow 2"}` and two shadows
        // never answer to the same words.
        .playtestControl("Style", detail: style?.name ?? "none")
    }

    /// Wearing a style: a mark and the style's NAME, with the menu's own
    /// chevron beside them so it reads as something to open rather than a stray
    /// word. Effects that disagree say Mixed in the same place, because that is
    /// the answer to the same question. Otherwise the quiet glyph on its own.
    @ViewBuilder private func label(_ style: EffectStyle?,
                                    _ selection: EffectStyleSelection) -> some View {
        if let style {
            HStack(spacing: 3) {
                Image(systemName: "square.on.square.dashed")
                Text(style.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else if selection.wearsAnyStyle {
            HStack(spacing: 3) {
                Image(systemName: "square.on.square.dashed")
                Text(EffectStyleSelection.mixedText)
                    .font(.caption)
                    .foregroundStyle(MixedLook.style)
            }
        } else {
            Image(systemName: "square.on.square.dashed")
        }
    }

    private func unlinkTitle(_ selection: EffectStyleSelection) -> String {
        selection.count > 1 ? "Unlink All \(selection.count)" : "Unlink"
    }

    private func saveTitle(_ selection: EffectStyleSelection) -> String {
        selection.count > 1 ? "Save as Style for All \(selection.count)" : "Save as Style"
    }

    /// The hover tip. With one layer picked it is about that effect; with
    /// several it has to say how many a pick here reaches.
    private func help(_ selection: EffectStyleSelection, _ style: EffectStyle?) -> String {
        let subject = row.kind.title.lowercased()
        let many = selection.count > 1
        switch (style, many) {
        case (.some(let style), false):
            return "This \(subject) uses the style \(style.name)"
        case (.some(let style), true):
            return "All \(selection.count) of these use the style \(style.name)"
        case (nil, false):
            return "Save this \(subject) as a named style, or use one you already saved"
        case (nil, true):
            return "Save what these \(selection.count) share as a named style, "
                + "or set them all to one you already saved"
        }
    }
}

// MARK: - One effect tile on the Styles shelf

/// A saved effect on the shelf: a small plate wearing the effect, its name, and
/// how much of the document leans on it. Click picks it, which opens the section
/// where it is renamed, re-tuned or removed.
///
/// It draws the effect rather than a swatch for the same reason a text style
/// draws its letters: a shelf of identical grey squares is a shelf you cannot
/// pick a style off. A shadow shows as a lifted plate, a glow as a lit one, a
/// border as a ringed one and a blur as a soft one, so the four kinds are told
/// apart at a glance without reading a word.
struct LibraryEffectStyleTile: View {
    @Environment(EditorState.self) private var editorState
    let entry: LibraryEntry
    let style: EffectStyle

    private var isSelected: Bool { editorState.selectedLibraryItemID == entry.id }

    var body: some View {
        // A real button rather than a tap gesture on a plain view, for the
        // reason the text tile carries one: a click on a gesture-only tile went
        // nowhere, and a button also gives the tile a keyboard route.
        Button { editorState.selectLibraryItem(entry.id) } label: { tile }
            .buttonStyle(.plain)
            .panelHelp("\(entry.name) • \(EffectStyleNaming.effectText(style.effect))"
                       + " • \(entry.detail)")
            .playtestTarget(entry.name, kind: .tile, detail: "Styles")
    }

    private var tile: some View {
        VStack(spacing: LibraryShelfLayout.captionSpacing) {
            EffectSample(effect: style.effect,
                         side: LibraryShelfLayout.thumbnailHeight)
                .frame(maxWidth: .infinity)
                .frame(height: LibraryShelfLayout.thumbnailHeight)
            Text(entry.name)
                .font(.system(size: LibraryShelfLayout.captionFontSize))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .frame(maxWidth: .infinity)
        .padding(LibraryShelfLayout.tilePadding)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }
}

/// A small plate wearing one effect, for a tile and for the top of the style's
/// own section.
///
/// It is a PICTURE of the effect rather than the renderer's own answer: the
/// shelf draws dozens of these on every pass and the real compositor works in
/// document points on a Core Image graph. The settings are scaled down to the
/// plate, so a 40pt shadow reads as a big soft one rather than as a grey
/// square.
///
/// It draws its own piece of PAPER under the plate, in both themes, because
/// every one of these effects only exists against something: a 40% black shadow
/// on the dark dock is invisible, which is exactly what the first build of this
/// tile looked like — four saved effects, four identical grey squares. Paper is
/// what the canvas is, and it is what a person is picturing when they name a
/// shadow.
struct EffectSample: View {
    let effect: LayerEffect
    /// How wide the whole sample is drawn, so the section can show a bigger one
    /// than a tile does.
    var side: CGFloat = 46

    /// How much of the sample the plate takes, leaving the rest as the room a
    /// shadow or a halo needs to be seen at all.
    private var plateSide: CGFloat { side * 0.5 }

    /// Document points to sample points. The plate stands for a shape about
    /// four times its size, which is what makes a tuned shadow legible on
    /// something this small.
    private var scale: CGFloat { plateSide / 100 }

    private let paper = Color(white: 0.95)
    private let ink = Color(white: 0.66)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(paper)
            plate.frame(width: plateSide, height: plateSide)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.15)))
    }

    @ViewBuilder private var plate: some View {
        switch effect {
        case .shadow(let shadow):
            let colour = Color(hex: shadow.colorHex).opacity(shadow.opacity)
            let inner = shadow.kind == .inner
            base
                // An inner shadow has nowhere to fall outside the plate, so it
                // is drawn as a dark band inside it rather than as a lift.
                .overlay(inner ? AnyView(rim(colour, width: max(shadow.radius * scale, 1.5)))
                         : AnyView(Color.clear))
                .shadow(color: inner ? .clear : colour,
                        radius: shadow.radius * scale,
                        x: shadow.offset.width * scale, y: shadow.offset.height * scale)
        case .glow(let glow):
            let colour = Color(hex: glow.colorHex).opacity(glow.opacity)
            base
                .overlay(glow.kind == .inner
                         ? AnyView(rim(colour, width: max(glow.radius * scale, 1.5)))
                         : AnyView(Color.clear))
                .shadow(color: glow.kind == .inner ? .clear : colour,
                        radius: max(glow.radius, glow.size) * scale)
        case .border(let border):
            base.overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color(hex: border.colorHex),
                                  lineWidth: max(border.width * scale, 1)))
        case .blur(let blur):
            base.blur(radius: blur.radius * scale)
        }
    }

    /// The plate the effect is worn on: a plain rounded square, so what changes
    /// from one sample to the next is the effect and nothing else.
    private var base: some View {
        RoundedRectangle(cornerRadius: 4).fill(ink)
    }

    /// A band of colour inside the plate's edge, which is what an inner shadow
    /// and an inner glow both look like.
    private func rim(_ colour: Color, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(colour, lineWidth: width)
            .blur(radius: width / 2)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - The picked effect style's section

/// The section that opens when you pick a saved effect off the shelf. It is
/// where a style is changed, because changing it here changes every layer
/// wearing it, and doing that from one of those layers would look like editing
/// that layer.
///
/// The controls are one-value ones written here rather than the Effects list's
/// own rows: a style holds exactly one effect, so all the reading-over-a-
/// selection machinery those rows carry would be dead weight. That is the same
/// call `LibraryTextStyleInspector` makes for a saved text style.
struct LibraryEffectStyleInspector: View {
    @Environment(EditorState.self) private var editorState

    @State private var draft = ""
    @State private var isPickerShown = false
    @FocusState private var nameFocused: Bool

    private var style: EffectStyle? { editorState.selectedEffectStyle }

    var body: some View {
        if let style {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Name")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField("Style name", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                        .focused($nameFocused)
                        .onSubmit { commit(style) }
                        .nameFieldKeys(commit: { commit(style) },
                                       revert: { draft = style.name })
                        .onChange(of: nameFocused) { _, focused in if !focused { commit(style) } }
                }
                settings(style)
                Text(EffectStyleNaming.standing(
                    usageCount: editorState.effectStyleUsageCount(styleID: style.id)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Button("Select What Uses This") {
                        editorState.selectLayersUsingEffectStyle(styleID: style.id)
                    }
                    .controlSize(.small)
                    .disabled(editorState.effectStyleUsageCount(styleID: style.id) == 0)
                    .panelHelp("Selects the layers this effect is on")
                    Button("Remove") {
                        editorState.deleteEffectStyle(styleID: style.id)
                    }
                    .controlSize(.small)
                    .panelHelp("Takes the style off the shelf. "
                               + "Every layer keeps the effect it is wearing")
                }
            }
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
            .padding(.vertical, 4)
            .onAppear { draft = style.name }
            .onChange(of: style.id) { _, _ in draft = style.name }
            .onChange(of: style.name) { _, name in if !nameFocused { draft = name } }
        }
    }

    /// The settings of the kind this style is, in the same order and the same
    /// words the Effects list asks for them, so a style's controls and the ones
    /// that tune an effect by hand read as the same controls.
    @ViewBuilder private func settings(_ style: EffectStyle) -> some View {
        // The effect as it is, at the top, because the numbers below it are
        // hard to picture and this is not.
        HStack(spacing: 10) {
            EffectSample(effect: style.effect, side: 56)
            Text(EffectStyleNaming.effectText(style.effect))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        switch style.effect {
        case .shadow(let shadow):
            colorRow(style, hex: shadow.colorHex) { $0.shadow?.colorHex = $1 }
            picker(style, "Kind", ShadowKind.allCases, current: shadow.kind, title: \.title) {
                $0.shadow?.kind = $1
            }
            // The same five, in the same order, with the same words and the
            // same ranges the Effects list asks for them in, so a style's
            // controls and the ones that tune a shadow by hand are the same
            // controls. Distance and Direction rather than an x and a y,
            // because that is how a shadow is described everywhere else in the
            // app.
            slider(style, "Softness", shadow.radius, 0...40, points) { $0.shadow?.radius = $1 }
            slider(style, "Size", shadow.spread, 0...80, points) { $0.shadow?.spread = $1 }
            slider(style, "Distance", shadow.distance, 0...40, points) {
                $0.shadow?.setDistance($1)
            }
            slider(style, "Direction", shadow.directionDegrees, 0...360,
                   { "\(Int($0.rounded()))°" }) { $0.shadow?.setDirectionDegrees($1) }
            opacityRow(style, shadow.opacity) { $0.shadow?.opacity = $1 }
        case .glow(let glow):
            colorRow(style, hex: glow.colorHex) { $0.glow?.colorHex = $1 }
            picker(style, "Kind", GlowKind.allCases, current: glow.kind, title: \.title) {
                $0.glow?.kind = $1
            }
            slider(style, "Size", glow.size, GlowEffect.sizeRange, points) { $0.glow?.size = $1 }
            slider(style, "Softness", glow.radius, GlowEffect.softnessRange, points) {
                $0.glow?.radius = $1
            }
            opacityRow(style, glow.opacity) { $0.glow?.opacity = $1 }
        case .border(let border):
            colorRow(style, hex: border.colorHex) { $0.border?.colorHex = $1 }
            picker(style, "Position", BorderPosition.allCases, current: border.position,
                   title: \.title) { $0.border?.position = $1 }
            slider(style, "Width", border.width, BorderEffect.widthRange, points) {
                $0.border?.width = $1
            }
        case .blur(let blur):
            slider(style, "Amount", blur.radius, 0...50, points) { $0.blur?.radius = $1 }
        }
    }

    // MARK: The controls

    private func points(_ value: CGFloat) -> String { "\(Int(value.rounded())) pt" }

    private func slider(_ style: EffectStyle, _ label: String, _ value: CGFloat,
                        _ range: ClosedRange<CGFloat>, _ format: @escaping (CGFloat) -> String,
                        _ apply: @escaping (inout LayerEffect, CGFloat) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(format(value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .panelReadout(format(value))
            }
            Slider(value: Binding(
                get: { Double(value) },
                set: { new in
                    var effect = style.effect
                    apply(&effect, CGFloat(new))
                    editorState.setEffectStyle(styleID: style.id, effect: effect)
                }),
                   in: Double(range.lowerBound)...Double(range.upperBound))
                .controlSize(.small)
                .panelHelp("Changing this re-sets every effect using this style")
                .playtestControl("Slider", detail: label)
        }
        .playtestField(label)
    }

    private func opacityRow(_ style: EffectStyle, _ value: Double,
                            _ apply: @escaping (inout LayerEffect, Double) -> Void) -> some View {
        slider(style, "Opacity", CGFloat(value), 0...1,
               { "\(Int(($0 * 100).rounded()))%" }) { effect, new in apply(&effect, Double(new)) }
    }

    private func picker<Option: Hashable>(
        _ style: EffectStyle, _ label: String, _ options: [Option], current: Option,
        title: KeyPath<Option, String>,
        _ apply: @escaping (inout LayerEffect, Option) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Picker(label, selection: Binding(
                get: { current },
                set: { new in
                    var effect = style.effect
                    apply(&effect, new)
                    editorState.setEffectStyle(styleID: style.id, effect: effect)
                })) {
                    ForEach(options, id: \.self) { option in
                        Text(option[keyPath: title]).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                // A width rather than `fixedSize`, for the reason every other
                // menu picker in the dock carries one: an ideal-width menu
                // inside the dock's column pushed the whole pane wider than the
                // window (2026-09-07).
                .frame(width: 120, alignment: .leading)
                .panelHelp("Changing this re-sets every effect using this style")
                .playtestControl(label, detail: current[keyPath: title])
        }
        .playtestField(label)
    }

    private func colorRow(_ style: EffectStyle, hex: String,
                          _ apply: @escaping (inout LayerEffect, String) -> Void) -> some View {
        HStack(spacing: 8) {
            Text("Color")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button { isPickerShown = true } label: { swatch(hex) }
                .buttonStyle(.plain)
                .panelHelp("Changing this re-sets every effect using this style")
                .popover(isPresented: $isPickerShown, arrowEdge: .top) {
                    ColorPickerContent(editorState: editorState,
                                       paint: Paint(hex: hex),
                                       name: style.name,
                                       supportsOpacity: true,
                                       supportsGradient: false,
                                       onClose: { isPickerShown = false }) { paint in
                        var effect = style.effect
                        apply(&effect, paint.hex)
                        editorState.setEffectStyle(styleID: style.id, effect: effect)
                    }
                }
                .playtestControl("Color", detail: hex)
        }
        .playtestField("Color")
    }

    private func swatch(_ hex: String) -> some View {
        PaintFill(paint: Paint(hex: hex))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .background(CheckerBoard(square: 4).clipShape(RoundedRectangle(cornerRadius: 4)))
            .frame(width: 18, height: 18)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.primary.opacity(0.25), lineWidth: 1))
    }

    private func commit(_ style: EffectStyle) {
        guard let name = ComponentNaming.normalized(draft) else {
            draft = style.name   // ...a blank name is refused, so put it back
            return
        }
        guard name != style.name else { return }
        editorState.renameEffectStyle(styleID: style.id, to: name)
    }
}
