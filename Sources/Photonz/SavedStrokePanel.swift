import AppKit
import PhotonzCore
import SwiftUI

// The Style row at the top of a path's line settings, the stroke tiles on the
// Library's Styles shelf, and the section behind a tile where a saved stroke is
// changed (Next, `next-styles`, `PhotonzCore/SavedStrokes.swift`). The same
// shape as `EffectStylePanel.swift`, with one difference: the mock promises one
// click, and a menu is two, so the strokes this document uses most are buttons
// on the row itself.

// MARK: - The Style row

/// The word Style, then what the picked lines wear or could wear.
///
/// With a stroke saved it sits at the top of the line's settings, because it is
/// the shortest way to set every row under it at once (`atTheFoot`).
///
/// It hangs in two places. Under a path's or a straight line's Line row in
/// Appearance it speaks for their own lines. Under a box's or an oval's Border
/// in Effects (`borderIndex`) it speaks for that edge, and reads Stroke rather
/// than Style, because that Border already has a Style row of its own for
/// saved borders and two rows with one word would be no way to tell them
/// apart. A box is never saved FROM (its corners are its Corner Radius, not a
/// stroke's), so there it only shows once a stroke exists.
struct SavedStrokeRow: View {
    @Environment(EditorState.self) private var editorState
    /// Which part row this hangs under, so a press reaches whatever is picked
    /// at the moment it happens (`PanelReach`).
    let rowID: String
    let selection: SavedStrokeSelection
    /// The place in the Effects list of the Border this row dresses, or nil
    /// for the picked layers' own lines.
    var borderIndex: Int? = nil
    /// Which of its two places this is. With a stroke saved the row is at the
    /// top, as the one click that sets the rows under it. With none saved all
    /// it offers is Save as Style, which comes after the line is tuned, so it
    /// goes under Align and takes no room from Width, Caps and Align, which
    /// have to show without a scroll.
    var atTheFoot = false

    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    /// How many strokes are buttons: past three, a choice is a dropdown, and
    /// the menu beside them has every one.
    private static let buttons = 3

    private var isNaming: Bool { editorState.namingSavedStrokeRow == rowID }
    private var word: String { borderIndex == nil ? "Style" : "Stroke" }

    /// What a press reaches, asked at the moment of the press.
    private var targets: [UUID] {
        guard let borderIndex else { return editorState.layerIDs(reaching: .partSavedStroke(rowID)) }
        let ids = editorState.layerStyleSelection.borders(at: borderIndex).layerIDs
        return editorState.savedStrokeSelection(ids: ids, borderAt: borderIndex).layerIDs
    }

    /// Whether this is the place the row shows: at the top with a stroke
    /// saved, at the foot with none. An edge cannot be saved from, so on a
    /// Border it waits until there is a stroke to give it.
    private var isItsPlace: Bool {
        let none = editorState.namedSavedStrokes.isEmpty
        guard borderIndex == nil else { return !none }
        return atTheFoot == none
    }

    var body: some View {
        if editorState.savedStrokesEnabled, !selection.isEmpty, selection.hasALine,
           !selection.isAllBrushed, isItsPlace {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: ColorPartLayout.spacing) {
                    HStack(spacing: 4) {
                        Text(word).panelRowName()
                        // Beside the word, in the room the name column has
                        // spare: beside the buttons it wrapped onto a second
                        // line, which put it below the fold with the shelf open.
                        if offersButtons { menu(wearing: nil) }
                    }
                    .frame(width: ColorPartLayout.nameWidth, alignment: .leading)
                    controls
                    Spacer(minLength: 0)
                }
                if isNaming { namingField }
            }
            .playtestField(borderIndex == nil ? "Line Style" : "Border Stroke")
            .onChange(of: isNaming, initial: true) { _, naming in
                guard naming else { return }
                draft = editorState.suggestedSavedStrokeName(ids: selection.layerIDs)
                // One pass later: the field is being installed by the very
                // change being reacted to (`EffectStyleRow`).
                DispatchQueue.main.async {
                    nameFocused = true
                    DispatchQueue.main.async { NSApp.keyWindow?.firstResponder?.trySelectAllText() }
                }
            }
        }
    }

    /// Whether the row shows saved strokes as buttons: there are some, and
    /// the picked paths do not all wear one already.
    private var offersButtons: Bool {
        selection.boundSavedStrokeID == nil && !editorState.namedSavedStrokes.isEmpty
    }

    @ViewBuilder private var controls: some View {
        let state = editorState
        let wearing = selection.boundSavedStrokeID.flatMap { id in
            state.namedSavedStrokes.first { $0.id == id }
        }
        if let wearing {
            menu(wearing: wearing)
        } else if state.namedSavedStrokes.isEmpty {
            saveButton
        } else {
            LibraryChipWrap(spacing: 4, rowSpacing: 4) {
                ForEach(state.document?.savedStrokeChoices(limit: Self.buttons) ?? []) { stroke in
                    Button { use(stroke) } label: {
                        Text(stroke.name).lineLimit(1).truncationMode(.middle)
                    }
                    .controlSize(.small)
                    .panelHelp("Gives this line \(stroke.name)")
                    .playtestControl(stroke.name, detail: "saved stroke")
                }
            }
        }
    }

    private var saveButton: some View {
        Button("Save as Style") { editorState.beginNamingSavedStroke(rowID: rowID) }
            .controlSize(.small)
            .disabled(selection.savableStrokeLook == nil)
            .panelHelp("Keeps this line under a name, so another path takes it in one click")
            .playtestControl("Save as Style")
    }

    private func menu(wearing: SavedStroke?) -> some View {
        let state = editorState
        return Menu {
            if let wearing {
                Section("Using \(wearing.name)") {
                    Button("Edit \(wearing.name) in the Library") {
                        // The shelf first, then the tile: picking a tile in a
                        // Library nobody has opened selects something there is
                        // nowhere to see.
                        state.showStylesShelf()
                        state.selectLibraryItem(wearing.id.uuidString)
                    }
                    Button("Unlink") { unlink() }
                }
            } else if selection.wearsAnySavedStroke {
                Section("Using more than one style") {
                    Button("Unlink") { unlink() }
                }
            } else if selection.savableStrokeLook != nil {
                Button("Save as Style") { state.beginNamingSavedStroke(rowID: rowID) }
            }
            let strokes = state.namedSavedStrokes.filter { $0.id != wearing?.id }
            if !strokes.isEmpty {
                Section("Saved lines") {
                    ForEach(strokes) { stroke in
                        Button(stroke.name) { use(stroke) }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "square.on.square.dashed")
                if let wearing {
                    Text(wearing.name).font(.caption).lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .panelHelp(wearing.map { "This line uses the style \($0.name)" }
                   ?? "Save this line as a named style, or use one you already saved")
        .playtestControl(word, detail: wearing?.name ?? "none")
    }

    private func use(_ stroke: SavedStroke) {
        editorState.useSavedStroke(ids: targets, styleID: stroke.id, borderAt: borderIndex)
    }

    private func unlink() {
        editorState.unlinkSavedStroke(ids: targets, borderAt: borderIndex)
    }

    private var namingField: some View {
        HStack(spacing: 6) {
            TextField("Style name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .controlSize(.small)
                .focused($nameFocused)
                .onSubmit(save)
                .nameFieldKeys(commit: save, revert: { editorState.endNamingSavedStroke() })
            Button("Save", action: save)
                .controlSize(.small)
                .panelHelp("Saves this line under that name")
                .playtestControl("Save")
        }
        .padding(.top, 2)
    }

    private func save() {
        editorState.saveStroke(ids: targets, name: draft)
    }
}

// MARK: - One stroke on the Styles shelf

/// A saved stroke on the shelf: a piece of the line itself, its name, and a
/// click that opens the section where it is changed.
struct LibrarySavedStrokeTile: View {
    @Environment(\.libraryTile) private var tileMetrics
    @Environment(\.lengthUnit) private var lengths
    @Environment(EditorState.self) private var editorState
    let entry: LibraryEntry
    let stroke: SavedStroke

    private var isSelected: Bool { editorState.selectedLibraryItemID == entry.id }

    var body: some View {
        Button { editorState.selectLibraryItem(entry.id) } label: {
            // How many use it, which is what the mock's Styles scope prints.
            LibraryShelfTile(name: entry.name, meta: entry.detail,
                             isSelected: isSelected) {
                SavedStrokeSample(look: stroke.look, height: tileMetrics.pictureHeight)
            }
        }
        .buttonStyle(.plain)
        .panelHelp("\(entry.name) • \(stroke.look.summary(in: lengths)) • \(entry.detail)")
        .playtestTarget(entry.name, kind: .tile, detail: "Styles")
    }
}

/// A corner of the line, drawn with its own caps and corners and its weight
/// scaled the way a 24 unit icon is scaled to the sample, so a heavier stroke
/// reads heavier on the shelf.
struct SavedStrokeSample: View {
    @Environment(\.lengthUnit) private var lengths
    let look: StrokeLook
    var height: CGFloat = 46

    var body: some View {
        Canvas { context, size in
            let weight = min(max(lengths.reading(look.width) / 24 * size.height, 1),
                             size.height / 3)
            var line = Path()
            line.move(to: CGPoint(x: size.width * 0.3, y: size.height * 0.72))
            line.addLine(to: CGPoint(x: size.width * 0.3, y: size.height * 0.3))
            line.addLine(to: CGPoint(x: size.width * 0.7, y: size.height * 0.3))
            context.stroke(line, with: .color(.primary),
                           style: SwiftUI.StrokeStyle(lineWidth: weight,
                                                      lineCap: look.lineEnd.lineCap,
                                                      lineJoin: look.lineCorner.lineJoin,
                                                      miterLimit: pathMiterLimit))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

// MARK: - The section behind a tile

/// The section that opens when you pick a saved stroke off the shelf. It is
/// where a stroke is changed, because changing it here changes every path
/// wearing it, and doing that from one of those paths would look like editing
/// that path. The rows are the ones a path's line has, in the same words.
struct LibrarySavedStrokeInspector: View {
    @Environment(EditorState.self) private var editorState
    @Environment(\.lengthUnit) private var lengths

    @State private var draft = ""
    @State private var heldWidth: CGFloat?
    @FocusState private var nameFocused: Bool

    private var stroke: SavedStroke? { editorState.selectedSavedStroke }

    var body: some View {
        if let stroke {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Name").font(.callout).foregroundStyle(.secondary)
                    TextField("Style name", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                        .focused($nameFocused)
                        .onSubmit { commit(stroke) }
                        .nameFieldKeys(commit: { commit(stroke) }, revert: { draft = stroke.name })
                        .onChange(of: nameFocused) { _, focused in if !focused { commit(stroke) } }
                }
                SavedStrokeSample(look: stroke.look, height: 30)
                width(stroke)
                LineCapsRow(reading: StyleReading(value: stroke.look.lineEnd, isMixed: false),
                            pick: { end in change(stroke) { $0.lineEnd = end } })
                PathLineStyleRow(label: "Corners",
                                 reading: StyleReading(value: stroke.look.lineCorner, isMixed: false),
                                 title: \.title,
                                 glyph: { PathLineStyleGlyph.corner($0, named: $0.title) },
                                 help: { _ in "Changing this re-sets every line using this style" },
                                 pick: { corner in change(stroke) { $0.lineCorner = corner } })
                align(stroke)
                Text(EffectStyleNaming.detail(
                    usageCount: editorState.savedStrokeUsageCount(styleID: stroke.id)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Button("Select What Uses This") {
                        editorState.selectLayersUsingSavedStroke(styleID: stroke.id)
                    }
                    .controlSize(.small)
                    .disabled(editorState.savedStrokeUsageCount(styleID: stroke.id) == 0)
                    .panelHelp("Selects the paths this line is on")
                    Button("Remove") { editorState.deleteSavedStroke(styleID: stroke.id) }
                        .controlSize(.small)
                        .panelHelp("Takes the style off the shelf. Every path keeps its line")
                }
            }
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
            .padding(.vertical, 4)
            .onAppear { draft = stroke.name }
            .onChange(of: stroke.id) { _, _ in draft = stroke.name }
            .onChange(of: stroke.name) { _, name in if !nameFocused { draft = name } }
        }
    }

    /// Width: a pull moves every path live and lands as one step when it is let
    /// go of, and a typed number keeps its fraction, as the path's own row does.
    private func width(_ stroke: SavedStroke) -> some View {
        let range = lengths.strokeWidthRange
        let value = heldWidth ?? stroke.look.width
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Width").font(.caption).foregroundStyle(.secondary)
                Spacer()
                SliderReadout(typing: lengths.lineWidth, label: "Width", value: value,
                              isMixed: false, range: range, identity: stroke.id,
                              land: { typed in
                                  change(stroke) { $0.width = lengths.typedLength(typed) }
                              })
            }
            Slider(value: Binding(
                get: { Double(value) },
                set: { new in
                    let pulled = lengths.pulled(CGFloat(new))
                    heldWidth = pulled
                    var look = stroke.look
                    look.width = pulled
                    editorState.previewSavedStroke(styleID: stroke.id, look: look)
                }),
                   in: Double(range.lowerBound)...Double(range.upperBound),
                   onEditingChanged: { editing in
                       guard !editing, let held = heldWidth else { return }
                       heldWidth = nil
                       change(stroke) { $0.width = held }
                   })
                .controlSize(.small)
                .panelHelp("Changing this re-sets every line using this style")
                .playtestControl("Slider", detail: "Width")
        }
        .playtestField("Width")
    }

    private func align(_ stroke: SavedStroke) -> some View {
        let help = "Changing this re-sets every line using this style"
        return HStack(alignment: .center, spacing: ColorPartLayout.spacing) {
            Text("Align")
                .panelRowName()
                .frame(width: ColorPartLayout.nameWidth, alignment: .leading)
            VideoKit.Dropdown(label: "Align", value: stroke.look.strokePosition.title,
                              valueStyle: nil, help: help,
                              choices: .picking(BorderPosition.allCases,
                                                current: stroke.look.strokePosition,
                                                title: \.title,
                                                isEnabled: { _ in true },
                                                pick: { side in
                                                    change(stroke) { $0.strokePosition = side }
                                                }))
                .frame(maxWidth: .infinity)
                .panelHelp(help)
                .playtestControl("Align", detail: stroke.look.strokePosition.title)
        }
    }

    private func change(_ stroke: SavedStroke, _ edit: (inout StrokeLook) -> Void) {
        var look = stroke.look
        edit(&look)
        editorState.setSavedStroke(styleID: stroke.id, look: look)
    }

    private func commit(_ stroke: SavedStroke) {
        guard let name = ComponentNaming.normalized(draft) else {
            draft = stroke.name   // ...a blank name is refused, so put it back
            return
        }
        guard name != stroke.name else { return }
        editorState.renameSavedStroke(styleID: stroke.id, to: name)
    }
}
