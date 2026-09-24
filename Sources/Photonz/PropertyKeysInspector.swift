import AppKit
import PhotonzCore
import SwiftUI

/// **Animating**: every value the picked layer has that can change over time,
/// each with a key diamond (`every-value-in-the-panel-has-a-key-diamond`,
/// `docs/design/mocks/pages/video.html`, the clip detail pane).
///
/// Premiere's Effect Controls, said in one row per value: the arrows and the
/// diamond, the value's name, and the value at the playhead. The diamond is the
/// stopwatch: dim until the value is keyed, coloured once it is, filled while a
/// key sits under the playhead. Changing a keyed value at another moment, here
/// or on the canvas, puts a key there, so there is no Add Key button to find.
///
/// Every value is listed, keyed or not, so "how do I animate this?" has a
/// visible answer on a layer nobody has touched: the dim diamond on its row.
struct PropertyKeysInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(editorState.keyRows, id: \.self) { property in
                PropertyKeyRow(property: property)
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
        .alert(stopTitle, isPresented: asking) {
            Button("Remove Keys", role: .destructive) { editorState.confirmStopKeying() }
            Button("Cancel", role: .cancel) { editorState.cancelStopKeying() }
        } message: {
            Text(stopMessage)
        }
    }

    private var asking: Binding<Bool> {
        Binding(get: { editorState.keyStopQuestion != nil },
                set: { if !$0 { editorState.cancelStopKeying() } })
    }

    private var stopTitle: String {
        "Stop animating \((editorState.keyStopQuestion?.title ?? "").lowercased())?"
    }

    private var stopMessage: String {
        guard let property = editorState.keyStopQuestion else { return "" }
        return "Its \(editorState.keyCount(property)) keys go, and it keeps the value it has now."
    }
}

/// How many values on the picked layer are keyed, on the section's header:
/// the mock's "2 of 9 properties", said shorter.
struct PropertyKeysSectionAccessory: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let keyed = editorState.keyedRowCount
        HStack(spacing: 8) {
            Text(keyed == 0 ? "None keyed" : "\(keyed) keyed")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .panelReadout(keyed == 0 ? "None keyed" : "\(keyed) keyed")
                .playtestField("Animating Count")
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
    }

    private var canGraph: Bool {
        guard editorState.documentHasTime, let id = editorState.selectedLayerID,
              let document = editorState.document else { return false }
        return editorState.keyLanes(layerID: id).contains {
            document.keyGraph(layerID: id, motionID: $0.motionID) != nil
        }
    }
}

/// One value: ‹ ◆ › then its name, then what it is at the playhead.
private struct PropertyKeyRow: View {
    @Environment(EditorState.self) private var editorState
    let property: KeyedProperty

    private var diamond: KeyDiamond { editorState.keyDiamond(property) }
    private var isKeyed: Bool { diamond != .dormant }

    var body: some View {
        // One line, or the value under the name when the dock is too narrow
        // for both: in the narrowest dock Position's two boxes left its name
        // four points, and it read "P" (2026-09-24).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) {
                head
                Spacer(minLength: 6)
                PropertyKeyValue(property: property)
            }
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 2) {
                    head
                    Spacer(minLength: 0)
                }
                PropertyKeyValue(property: property)
            }
        }
        .frame(minHeight: 24)
        .contentShape(Rectangle())
        .playtestField(property.title)
        .panelStartProbe(.row, owner: property.title)
        // The verbs for one key live where you click, the way Premiere puts
        // them on a keyframe's own menu: the diamond is the stopwatch, and
        // this is the key under the playhead.
        .contextMenu {
            Button("Add Key Here") { editorState.addKeyHere(property) }
                .disabled(diamond == .onKey)
            Button("Remove Key Here") { editorState.removeKeyHere(property) }
                .disabled(diamond != .onKey)
            Divider()
            Button(isKeyed ? "Stop Animating" : "Animate") { editorState.toggleKeying(property) }
        }
    }

    /// ‹ ◆ › and the name.
    private var head: some View {
        HStack(spacing: 2) {
            stepButton(forward: false)
            KeyDiamondButton(property: property, state: diamond)
            stepButton(forward: true)
            Text(property.title)
                .font(.system(size: 11))
                .foregroundStyle(isKeyed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
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
        .accessibilityLabel(forward ? "Next \(property.title) key" : "Previous \(property.title) key")
        .playtestControl(forward ? "Next Key" : "Previous Key", detail: "Animating, \(property.title)")
    }
}

/// The diamond: the stopwatch and the key readout in one mark, drawn by the
/// video kit (`VideoKit.KeyDiamond`, the mock's `.kfkey`). Three states, told
/// apart by weight: a dim outline, a coloured outline, a filled diamond.
private struct KeyDiamondButton: View {
    @Environment(EditorState.self) private var editorState
    let property: KeyedProperty
    let state: KeyDiamond

    @State private var isHovering = false

    var body: some View {
        Button {
            editorState.toggleKeying(property)
        } label: {
            VideoKit.KeyDiamond(state: kitState, isHovering: isHovering)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .playtestHover("Key \(property.title)") { isHovering = $0 }
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
        state == .dormant ? "Animate \(property.title.lowercased()) from here"
                          : "Stop animating \(property.title.lowercased())"
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

    var body: some View {
        switch editorState.keyedValue(property) {
        case let .number(number)?:
            numberBox(number, label: property.title, suffix: suffix) {
                editorState.setKeyedValue(.number($0), for: property)
            }
        case let .point(point)?:
            HStack(spacing: 4) {
                numberBox(Double(point.x), label: "\(property.title) X", leading: "X", suffix: nil) {
                    editorState.setKeyedValue(.point(CGPoint(x: $0, y: point.y)), for: property)
                }
                numberBox(Double(point.y), label: "\(property.title) Y", leading: "Y", suffix: nil) {
                    editorState.setKeyedValue(.point(CGPoint(x: point.x, y: $0)), for: property)
                }
            }
        case let .color(hex)?:
            ColorWellButton(hex: hex, name: property.title,
                            wellKey: "key-\(property.title)",
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
        case let .motion(motion): MotionEntry.suffix(motion)
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
                         width: .fixed(leading == nil ? 52 : 44),
                         playtest: ("\(label) Value", "Animating"),
                         spell: { Self.text(Double($0)) },
                         land: { typed in
                             land(Double(typed))
                             return nil
                         })
    }
}
