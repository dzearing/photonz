import AppKit
import PhotonzCore
import SwiftUI

/// **Properties**: the pane beside a clip, a title or a sound in a document
/// with time (`docs/design/mocks/pages/video.html`, `renderProps`).
///
/// One clip line first (its name, where it starts and ends, how long it is and
/// how fast it plays), then **Animating**: only the values that are actually
/// keyed, each with Premiere's row of ‹ ◆ › and its value at the playhead. The
/// rest wait behind Animate a property, a picker rather than a longer list,
/// because the list only grows (`PropertiesPane.swift`).
///
/// The diamond is Premiere's keyframe button: a key here goes, and where there
/// is none one is written. The row's cross, and its right-click, stop the
/// value animating altogether.
struct PropertyKeysInspector: View {
    @Environment(EditorState.self) private var editorState
    /// Animate a property's list is open. Held here, because the list opens
    /// over this whole section (the mock's `.propPick`, under the header),
    /// not beside its button.
    @State private var isPicking = false

    var body: some View {
        #if PHOTONZ_PLAYTEST
        let _ = ViewBuildMeter.shared.built(.keysSection)
        #endif
        VStack(alignment: .leading, spacing: 2) {
            if let line = editorState.keyClipLine {
                ClipLineRow(line: line)
            }
            // A recording's clicks, drawn or not (`ClickEffectRows`): a
            // setting of the clip itself, so it sits with the clip line
            // rather than among what is animating.
            if let clip = editorState.clickEffectClip {
                ClickEffectRows(clipID: clip.id)
            }
            AnimatingHeader()
            // Nothing under the header while nothing is keyed: its own count
            // already reads "nothing yet", and what can be keyed is the
            // section's question mark.
            let rows = editorState.animatingRows
            ForEach(rows, id: \.self) { property in
                PropertyKeyRow(property: property)
            }
            AnimatePropertyButton(isOpen: $isPicking)
                .padding(.top, 4)
            // How it gets from one key to the next, once something has two
            // (`video-move-wt.html`, `#secEase`).
            if editorState.betweenKeysProperty != nil {
                BetweenKeysSection()
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
        .panelPopover(isPresented: $isPicking, height: AnimatePropertyPicker.tallest) {
            AnimatePropertyPicker(isOpen: $isPicking)
        }
        .alert(stopTitle, isPresented: asking) {
            Button("Remove Keys", role: .destructive) { editorState.confirmStopKeying() }
            Button("Cancel", role: .cancel) { editorState.cancelStopKeying() }
        } message: {
            Text(stopAlertMessage)
        }
    }

    /// What the section header's question mark says. It was the mock's line
    /// under an empty list ("Any property can be keyed, including colours and
    /// border width"); the panel holds labels and tools, never sentences.
    static let sectionHelp = "Any property can be keyed, even color and stroke width. "
        + "Pick one from Animate a property to key it at the playhead"

    private var asking: Binding<Bool> {
        Binding(get: { editorState.keyStopQuestion != nil },
                set: { if !$0 { editorState.cancelStopKeying() } })
    }

    private var stopTitle: String {
        "Stop animating \((editorState.keyStopQuestion?.title ?? "").lowercased())?"
    }

    private var stopAlertMessage: String {
        guard let property = editorState.keyStopQuestion else { return "" }
        return "Its \(editorState.keyCount(property)) keys go, and it keeps the value it has now."
    }
}

/// `Between the keys  Ease in out`, then Curve and Path: the mock's `#secEase`
/// (`video-move-wt.html` steps 5 to 7). Curve is how fast the stretch under
/// the playhead travels, from the one list of curve names every page with
/// timing offers; Path is where a move travels. The mock prints a line under
/// them (`#pPathNote`) that changes once the path bends; the user's answer of
/// 2026-09-25 (no sentences in the panel, explain behind a question mark in
/// the header) puts those same words behind the header's question mark.
private struct BetweenKeysSection: View {
    @Environment(EditorState.self) private var editorState
    @State private var isDrawing = false

    static let straightHelp = "Easing is how fast it travels. The path is where it travels. "
        + "They are separate on purpose: a straight move can still ease, "
        + "and an arc can still run at a flat rate."
    static let curvedHelp = "The handle is the curve\u{2019}s control point. Drag it and the graphic arcs; "
        + "double-click it and the path snaps back to straight."

    var body: some View {
        let curve = editorState.betweenKeysCurve
        let name = curve.map(StretchCurve.title) ?? ""
        VStack(alignment: .leading, spacing: 4) {
            Rectangle()
                .fill(VideoKit.Palette.line)
                .frame(height: 1)
                .padding(.top, 8)
                .padding(.bottom, 4)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Between the keys")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                Text(name)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(VideoKit.Palette.faint)
                    .lineLimit(1)
                    .panelReadout(name)
                    .playtestField("Between the keys")
                SectionHelpMark(section: "Between the keys", text: help)
            }
            .padding(.bottom, 2)
            VideoKit.DropdownRow(label: "Curve", value: name, choices: curveChoices(current: curve))
            .frame(minHeight: 24)
            .playtestField("Curve")
            .panelHelp("How fast it travels between these two keys")
            .popover(isPresented: $isDrawing, arrowEdge: .leading) {
                CurveEditor(curve: curve ?? PropertyKeys.curve) { drawn in
                    editorState.curveBetweenKeys(drawn)
                    isDrawing = false
                }
            }
            if let shape = editorState.motionPathShape {
                MotionPathRow(shape: shape)
            }
        }
    }

    /// What the question mark says: the mock's own line for a move, which
    /// turns to the handle once the path bends, and the easing half of it for
    /// anything else.
    private var help: String {
        switch editorState.motionPathShape {
        case .curved?: Self.curvedHelp
        case .straight?: Self.straightHelp
        case nil: Self.easingHelp
        }
    }

    static let easingHelp = "Easing is how fast it changes between these two keys."

    /// The mock's curve menu (`curve.js`): the four standard curves, the four
    /// shaped ones, each with its shape beside its name, then Draw a Curve.
    private func curveChoices(current: EasingCurve?) -> [VideoKit.Choice] {
        [.heading("Standard")] + EasingCurve.named.prefix(4).map { item($0, current: current) }
            + [.heading("Shaped")] + EasingCurve.named.dropFirst(4).map { item($0, current: current) }
            + [.divider] + customChoice(current: current)
            + [.item("Draw a Curve\u{2026}") { isDrawing = true }]
    }

    /// The row reads Custom for a curve of your own, so the menu offers it:
    /// ticked while the stretch is on it, and the one it last left for a named
    /// curve otherwise (`CustomChoice`). Absent until there has been one.
    private func customChoice(current: EasingCurve?) -> [VideoKit.Choice] {
        guard let own = editorState.customBetweenKeysCurve else { return [] }
        return [.item(StretchCurve.title(own), isOn: current == own,
                      image: CurveMenuImage.image(for: own)) {
            editorState.curveBetweenKeys(own)
        }]
    }

    private func item(_ curve: EasingCurve, current: EasingCurve?) -> VideoKit.Choice {
        .item(curve.title, isOn: current == curve, image: CurveMenuImage.image(for: curve)) {
            editorState.curveBetweenKeys(curve)
        }
    }
}

/// A curve's shape as a small template picture, for a menu row: a menu cannot
/// draw a SwiftUI view beside its words, only a picture, and a template one
/// takes the row's own colour when it is highlighted.
@MainActor
enum CurveMenuImage {
    private static var made: [String: NSImage] = [:]

    static func image(for curve: EasingCurve) -> NSImage {
        if let image = made[curve.title] { return image }
        let side: CGFloat = 16
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let inset: CGFloat = 2.5
            let width = rect.width - inset * 2
            let height = rect.height - inset * 2
            let path = NSBezierPath()
            let steps = 40
            for step in 0...steps {
                let t = Double(step) / Double(steps)
                let value = min(max(curve.value(at: t), -0.25), 1.25)
                let point = NSPoint(x: inset + width * t, y: inset + height * (value + 0.25) / 1.5)
                if step == 0 { path.move(to: point) } else { path.line(to: point) }
            }
            path.lineWidth = 1.4
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        made[curve.title] = image
        return image
    }
}

/// `Path  [Straight | Curved]`: the mock's Path control. Straight puts every
/// stretch back on its line; Curved arcs a straight path up and over, which is
/// a place to drag the handle on the canvas from.
private struct MotionPathRow: View {
    @Environment(EditorState.self) private var editorState
    let shape: MotionPathShape

    var body: some View {
        // The name over a control the width of the section: the mock gives
        // this row one column (`grid-template-columns:1fr`), unlike Curve.
        VStack(alignment: .leading, spacing: 4) {
            PanelRowLabel(text: "Path")
            SegmentedControl("Path", selection: shape,
                             options: MotionPathShape.allCases.map { .init($0, $0.title) },
                             fallsBackToSystem: false) {
                editorState.setMotionPathShape($0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
        .panelReadout("Path \(shape.title)")
        .playtestField("Path")
        .help("Drag the square on the path in the canvas to bend it. Double-click it to straighten.")
    }
}

/// The kind chip on the Properties header: Clip, Title, Audio.
struct PropertyKeysSectionAccessory: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        if let kind = editorState.keyLayerKind {
            // The mock's `.cnt`: a small pill beside the title.
            Text(kind)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10)))
                .panelReadout(kind)
                .playtestField("Properties Kind")
        }
    }
}

/// The three dots at the end of the Properties header (`video.html`,
/// `#propMenu`): take the picked thing's look, or put one on it. The same two
/// commands as the Layer menu and a layer's right click, under the same names,
/// so nothing learned here is wrong there. Under them, in a document with
/// time, the mock's Reset to defaults: the picked thing back the way it came in.
struct PropertiesPanelMenu: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        Menu {
            // Each with the mock's icon beside it: copy, and the undo arrow.
            Button("Copy Look", systemImage: "doc.on.doc") { editorState.copyLook() }
                .disabled(!editorState.canCopyLook)
            Button("Paste Look", systemImage: "doc.on.clipboard") { editorState.pasteLook() }
                .disabled(!editorState.canPasteLook)
            if editorState.documentHasTime {
                Button("Reset to Defaults", systemImage: "arrow.uturn.backward") {
                    editorState.resetPropertiesToDefaults()
                }
                .disabled(!editorState.canResetProperties)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Properties Menu")
        .panelHelp("Copy the look, or reset")
        .playtestControl("Properties Menu", detail: "the three dots on the Properties header")
    }
}

/// `Sample Talk        2.0s → 14.9s  12.9s · 1.0x`: the mock's `.cliphead`.
/// A readout, not a form: trimming is the clip's edges on the timeline, and
/// speed is the Time section and the clip's right-click.
private struct ClipLineRow: View {
    let line: ClipLine

    var body: some View {
        VStack(spacing: 0) {
            // One line, the mock's way, when the whole name fits beside the
            // times; otherwise the name goes above them and reads whole. It
            // was cut short beside them until 2026-09-27, and "Tutorial
            // Sam..." at the dock's default width was the one clip name every
            // tutorial showed.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    name.fixedSize()
                    Spacer(minLength: 0)
                    times
                }
                VStack(alignment: .leading, spacing: 2) {
                    name
                    times
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 6)
            .padding(.bottom, 4)
            Rectangle()
                .fill(VideoKit.Palette.line)
                .frame(height: 1)
                .padding(.bottom, 6)
        }
        .panelReadout("\(line.name) \(line.reading)")
        .playtestField("Clip line")
        .help("\(line.name): \(line.inText) to \(line.outText), \(line.lengthText) at \(line.speedText)")
    }
}

extension ClipLineRow {
    private var name: some View {
        Text(line.name)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var times: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(line.inText).foregroundStyle(VideoKit.Palette.dim).fontWeight(.semibold)
                + Text(" \u{2192} ").foregroundStyle(VideoKit.Palette.faint)
                + Text(line.outText).foregroundStyle(VideoKit.Palette.dim).fontWeight(.semibold)
            Text("\(line.lengthText) \u{00B7} \(line.speedText)")
                .foregroundStyle(VideoKit.Palette.faint)
        }
        .font(.system(size: 10, design: .monospaced))
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
    }
}

/// `Animating  2 of 15 properties  Graph`: the mock's `.sec-h` over the rows.
private struct AnimatingHeader: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let count = PropertyPicker.countText(keyed: editorState.animatingRows.count,
                                             of: editorState.keyRows.count)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Animating")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
            Text(count)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .panelReadout(count)
                .playtestField("Animating Count")
            Spacer(minLength: 0)
            // The mock's Graph link (`video.html`, `#graphOpen`): the picked
            // layer's first curve, opened on its lane in the timeline.
            if canGraph {
                Button("Graph") { editorState.openGraphForPickedLayer() }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(VideoKit.Palette.accent)
                    .help("Show the curve on the timeline")
                    .playtestControl("Graph", detail: "Animating")
            }
        }
        .padding(.bottom, 2)
    }

    private var canGraph: Bool {
        guard editorState.documentHasTime, let id = editorState.selectedLayerID,
              let document = editorState.document else { return false }
        return editorState.keyLanes(layerID: id).contains {
            document.keyGraph(layerID: id, motionID: $0.motionID) != nil
        }
    }
}

/// `+ Animate a property`. The picker it opens is drawn over the section
/// (`AnimatePropertyPicker`).
private struct AnimatePropertyButton: View {
    @Binding var isOpen: Bool

    var body: some View {
        Button {
            isOpen = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                Text("Animate a property")
                    .font(.system(size: 11))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05)))
        .panelHelp("Pick a value to key at the playhead")
        .playtestControl("Animate a property", detail: "Animating")
    }
}

/// Every value that is not animating yet, in groups, with a box to find one by
/// name. Picking one starts it with a key at the playhead holding the value it
/// has now. Drawn over the panel rather than in a popover window beside it
/// (`PanelPopover`), which is where the mock puts it and what keeps opening
/// and closing it from redrawing the whole panel.
private struct AnimatePropertyPicker: View {
    @Environment(EditorState.self) private var editorState
    @Binding var isOpen: Bool
    @State private var query = ""

    /// The find box and the list under it at its longest (`.frame(maxHeight:)`).
    static let tallest: CGFloat = 8 + 26 + 8 + 1 + 260

    var body: some View {
        let groups = PropertyPicker.groups(all: editorState.keyRows,
                                           keyed: Set(editorState.animatingRows),
                                           query: query, title: editorState.keyTitle)
        VStack(alignment: .leading, spacing: 0) {
            FindBox(query: query)
                .padding(8)
                .background(PanelPopoverKeys(onKey: { key in
                    if key == .submit {
                        if let first = groups.first?.properties.first { pick(first) }
                    } else {
                        PanelDropdown.apply(key, to: &query)
                    }
                }, close: { isOpen = false }))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if groups.isEmpty {
                        let empty = PropertyPicker.emptyText(query: query)
                        Text(empty)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .panelReadout(empty)
                    }
                    ForEach(groups, id: \.self) { group in
                        Text(group.title.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        ForEach(group.properties, id: \.self) { property in
                            PickerRow(property: property, title: editorState.keyTitle(property),
                                      swatch: swatch(property)) {
                                pick(property)
                            }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 260)
        }
    }

    /// The colour a colour value has now, which its row shows in place of the
    /// diamond (the mock's `.pick-i .sw`); nil for every other kind of value.
    private func swatch(_ property: KeyedProperty) -> String? {
        guard PickerRow.isColour(property),
              case let .color(hex)? = editorState.keyedValue(property) else { return nil }
        return hex
    }

    /// The list goes first and the value arrives on the next run-loop pass.
    /// Each is a redraw of its own (the list leaving, then the new row, its
    /// lane and the key), and done in one pass they held the main thread far
    /// longer than either does alone (`perf/animate-pick-cost-walk.json`,
    /// 2026-10-06).
    private func pick(_ property: KeyedProperty) {
        isOpen = false
        let state = editorState
        Task { @MainActor in
            await NextRunLoopPass.start()
            state.startAnimating(property)
        }
    }
}

/// The mock's `.pick-q`, ready for typing the moment the list opens: what has
/// been typed, or Find a property, and the caret after it. It reads its keys
/// through the list (`PanelPopoverKeys`) rather than as a text box holding the
/// window's keyboard, which is what lets the list open and close without the
/// whole window noticing.
private struct FindBox: View {
    let query: String

    var body: some View {
        HStack(spacing: 1) {
            if !query.isEmpty {
                Text(query).foregroundStyle(.primary)
            }
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 1, height: 13)
            if query.isEmpty {
                Text("Find a property").foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(VideoKit.Palette.panel2, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Find a property")
        .accessibilityValue(query)
        .accessibilityAddTraits(.isSearchField)
        .panelReadout(query.isEmpty ? "Find a property" : query)
        .playtestField("Find a property")
    }
}

/// One value in the picker: its mark, its name, and what kind of number it is.
private struct PickerRow: View {
    let property: KeyedProperty
    /// Its name on the picked layer, which says which shadow on a title with
    /// several (`KeyedProperty.title(on:)`).
    let title: String
    /// A colour value's colour now, drawn where a number has its diamond.
    let swatch: String?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                mark
                    .frame(width: 12)
                Text(title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(unit)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .background(isHovering ? AnyShapeStyle(VideoKit.Palette.accent.opacity(0.14)) : AnyShapeStyle(.clear))
        .playtestHover { isHovering = $0 }
        .playtestControl(title, detail: "Animate a property")
    }

    /// The mock's `.sw` for a colour, 12 points with its low edge round it so
    /// a white or a black still reads on the list, and the diamond otherwise.
    @ViewBuilder private var mark: some View {
        if let swatch {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: swatch))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(VideoKit.Palette.edgeLo))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
                .playtestControl("Swatch", detail: "Animate a property, \(title)")
        } else {
            Image(systemName: "diamond")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    /// The mock's `.mt`: px, %, °, dB, or colour.
    private var unit: String {
        switch property {
        case .volume: "dB"
        case let .motion(motion, _):
            Self.isColour(property) ? "color" : (MotionEntry.suffix(motion) ?? DocumentUnit.word)
        }
    }

    static func isColour(_ property: KeyedProperty) -> Bool {
        guard case let .motion(motion, _) = property else { return false }
        return [.color, .shadowColor, .glowColor, .borderColor].contains(motion)
    }
}

/// One value: ‹ ◆ › then its name, then what it is at the playhead.
private struct PropertyKeyRow: View {
    @Environment(EditorState.self) private var editorState
    let property: KeyedProperty
    private var title: String { editorState.keyTitle(property) }

    @State private var isHovering = false

    private var diamond: KeyDiamond { editorState.keyDiamond(property) }
    private var isKeyed: Bool { diamond != .dormant }
    private var isActive: Bool { editorState.activeKeyProperty == property }

    var body: some View {
        // One line, or the value under the name when the dock is too narrow
        // for both: in the narrowest dock Position's two boxes left its name
        // four points, and it read "P" (2026-09-24). One copy of each piece,
        // moved: the two candidates of a `ViewThatFits` built the value's
        // boxes twice over, on the pass a picked value arrives in.
        KeyRowLayout {
            head
            PropertyKeyValue(property: property)
            stopButton
        }
        .frame(minHeight: 24)
        .contentShape(Rectangle())
        .playtestHover("Row \(title)") { isHovering = $0 }
        .playtestField(title)
        .panelStartProbe(.row, owner: title)
        // The verbs for one key live where you click, the way Premiere puts
        // them on a keyframe's own menu: the diamond is the stopwatch, and
        // this is the key under the playhead.
        .contextMenu {
            Button("Add Key Here") { editorState.addKeyHere(property) }
                .disabled(diamond == .onKey)
            Button("Remove Key Here") { editorState.removeKeyHere(property) }
                .disabled(diamond != .onKey)
            Divider()
            Button("Stop Animating") { editorState.toggleKeying(property) }
        }
    }

    /// The mock's `.prow-x`: stop animating this value, keeping the value it
    /// has now. Shown while the pointer is on the row, and its room is kept
    /// either way so the values stay in a column.
    private var stopButton: some View {
        Button {
            editorState.toggleKeying(property)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .semibold))
                .frame(width: 16, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        // Not 0: SwiftUI stops hit testing a view at no opacity at all, and a
        // click that lands a beat before the hover does must still count.
        .opacity(isHovering ? 1 : 0.001)
        .panelHelp("Stop animating \(title.lowercased())")
        .accessibilityLabel("Stop animating \(title.lowercased())")
        .playtestControl("Stop Animating", detail: "Animating, \(title)")
    }

    /// ‹ ◆ › and the name.
    private var head: some View {
        HStack(spacing: 2) {
            stepButton(forward: false)
            KeyDiamondButton(property: property, state: diamond)
            stepButton(forward: true)
            // The value last touched reads in the key colour, the mock's
            // `.prow.sel`: it is the one the Graph link and the lanes follow.
            Text(title)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? AnyShapeStyle(VideoKit.Palette.comp)
                                          : isKeyed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .padding(.leading, 4)
        }
    }

    /// An arrow to the key before or after the playhead. Only there once the
    /// value is keyed, and its room is kept either way so the names stay in a
    /// column however many rows are keyed.
    private func stepButton(forward: Bool) -> some View {
        let can = isKeyed && editorState.canStepToKey(property, forward: forward)
        return Button {
            editorState.stepToKey(property, forward: forward)
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 8, weight: .semibold))
                .frame(width: 12, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(can ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
        .disabled(!can)
        .opacity(isKeyed ? 1 : 0)
        .panelHelp(forward ? "Next key" : "Previous key")
        .accessibilityLabel(forward ? "Next \(title) key" : "Previous \(title) key")
        .playtestControl(forward ? "Next Key" : "Previous Key", detail: "Animating, \(title)")
    }
}

/// `‹ ◆ › name`, the value and the cross on one line, or the value under them
/// when they do not fit (`KeyRowLine`), decided from the width in one pass.
private struct KeyRowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let head = subviews[0].sizeThatFits(.unspecified)
        let value = subviews[1].sizeThatFits(.unspecified)
        let stop = subviews[2].sizeThatFits(.unspecified)
        let oneLine = KeyRowLine.oneLineWidth(head: head.width, value: value.width, stop: stop.width)
        guard let width = proposal.width else {
            return CGSize(width: oneLine, height: max(head.height, value.height, stop.height))
        }
        if oneLine <= width {
            return CGSize(width: width, height: max(head.height, value.height, stop.height))
        }
        return CGSize(width: width,
                      height: max(head.height, stop.height) + KeyRowLine.gap + value.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        guard subviews.count == 3 else { return }
        let head = subviews[0].sizeThatFits(.unspecified)
        let value = subviews[1].sizeThatFits(.unspecified)
        let stop = subviews[2].sizeThatFits(.unspecified)
        let gap = KeyRowLine.gap
        if KeyRowLine.fitsOnOneLine(head: head.width, value: value.width, stop: stop.width,
                                    width: bounds.width) {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                              proposal: .unspecified)
            subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing,
                              proposal: .unspecified)
            subviews[1].place(at: CGPoint(x: bounds.maxX - stop.width - gap, y: bounds.midY),
                              anchor: .trailing, proposal: .unspecified)
            return
        }
        let line = max(head.height, stop.height)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY + line / 2), anchor: .leading,
                          proposal: ProposedViewSize(width: max(0, bounds.width - stop.width - gap),
                                                     height: nil))
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.minY + line / 2), anchor: .trailing,
                          proposal: .unspecified)
        subviews[1].place(at: CGPoint(x: bounds.maxX, y: bounds.minY + line + gap),
                          anchor: .topTrailing, proposal: .unspecified)
    }
}

/// The diamond: Premiere's keyframe button and the key readout in one mark, drawn by the
/// video kit (`VideoKit.KeyDiamond`, the mock's `.kfkey`). Three states, told
/// apart by weight: a dim outline, a coloured outline, a filled diamond.
private struct KeyDiamondButton: View {
    @Environment(EditorState.self) private var editorState
    let property: KeyedProperty
    private var title: String { editorState.keyTitle(property) }
    let state: KeyDiamond

    @State private var isHovering = false

    var body: some View {
        Button {
            editorState.toggleKeyHere(property)
        } label: {
            VideoKit.KeyDiamond(state: kitState, isHovering: isHovering)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .playtestHover("Key \(title)") { isHovering = $0 }
        .panelHelp(help)
        .accessibilityLabel(help)
        .panelReadout(word)
        .playtestControl("Key", detail: word)
    }

    private var kitState: VideoKit.KeyState {
        switch state {
        case .dormant: .dormant
        case .betweenKeys: .armed
        case .onKey: .onKey
        }
    }

    private var help: String {
        switch state {
        case .dormant: "Animate \(title.lowercased()) from here"
        case .betweenKeys: "Add a \(title.lowercased()) key here"
        case .onKey: "Remove this \(title.lowercased()) key"
        }
    }

    /// What a walk reads back, and what the state is called in the log.
    private var word: String {
        switch state {
        case .dormant: "not keyed"
        case .betweenKeys: "between keys"
        case .onKey: "on a key"
        }
    }
}

/// The value at the playhead, in the editor its kind wants: a number box, two
/// for a place, a well for a colour.
private struct PropertyKeyValue: View {
    @Environment(EditorState.self) private var editorState
    let property: KeyedProperty
    private var title: String { editorState.keyTitle(property) }

    var body: some View {
        switch editorState.keyedValue(property) {
        case let .number(number)?:
            numberBox(number, label: title, suffix: suffix) {
                editorState.setKeyedValue(.number($0), for: property)
            }
        case let .point(point)?:
            HStack(spacing: 4) {
                numberBox(Double(point.x), label: "\(title) X", leading: "X", suffix: nil) {
                    editorState.setKeyedValue(.point(CGPoint(x: $0, y: point.y)), for: property)
                }
                numberBox(Double(point.y), label: "\(title) Y", leading: "Y", suffix: nil) {
                    editorState.setKeyedValue(.point(CGPoint(x: point.x, y: $0)), for: property)
                }
            }
        case let .color(hex)?:
            ColorWellButton(hex: hex, name: title,
                            wellKey: "key-\(title)",
                            onCommit: { picked in
                editorState.setKeyedValue(.color(picked), for: property)
                editorState.recordRecentColor(hex: picked)
            })
            .panelReadout(hex)
        case nil:
            EmptyView()
        }
    }

    /// One decimal at most, the way Premiere reads a value between keys:
    /// "146.5", never "146.53", and a whole number stays whole.
    static func text(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }

    private var suffix: String? {
        switch property {
        case let .motion(motion, _): MotionEntry.suffix(motion)
        case .volume: "dB"
        }
    }

    private func numberBox(_ value: Double, label: String, leading: String? = nil,
                           suffix: String?, land: @escaping (Double) -> Void) -> some View {
        PanelNumberField(showing: .number(Self.text(value)),
                         label: label,
                         identity: "key-\(editorState.keyLayer?.id.uuidString ?? "")-\(label)",
                         leading: leading,
                         suffix: suffix,
                         width: .fixed(leading == nil ? 84 : 52),
                         playtest: ("\(label) Value", "Animating"),
                         spell: { Self.text(Double($0)) },
                         land: { typed in
                             land(Double(typed))
                             return nil
                         })
    }
}
