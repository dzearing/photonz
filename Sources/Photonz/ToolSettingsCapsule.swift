import PhotonzCore
import SwiftUI

/// The settings for the tool in your hand, riding in their own small capsule
/// just above the floating tool bar (`next-tool-settings`).
///
/// Why it exists: a tool's settings used to live only in the right hand panel,
/// so hiding the panel — a normal thing to do while you work on a picture, and
/// something the shell also does for you on a narrow window — took the Zoom
/// Callout's shape, the wand's tolerance and Measure's Snap and Show away with
/// it. A mode was fine, because a mode lives inside its own tool button and
/// press-and-hold always reaches it. Only the settings half was stranded.
///
/// Why it is a capsule of its own rather than part of the bar: tool settings
/// used to sit INSIDE the tool bar and grew it by 150 to 200 points the moment
/// you picked up Measure or Crop, pushing tools into the overflow menu. That
/// was removed on purpose. On its own row the bar never changes width whatever
/// you pick up, and the capsule wraps rather than pushing anything off the
/// picture.
///
/// The panel keeps every one of these settings too. They are not copies: both
/// places read and write the same `EditorState` property, so changing either
/// moves both at once.
struct ToolSettingsCapsule: View {
    @Environment(EditorState.self) private var editorState

    /// What the tool in hand puts here. Empty means no capsule at all: the
    /// caller draws nothing, so the arrow leaves the picture clear.
    static func settings(for tool: Tool) -> [ToolSetting] {
        guard Experiments.shared.toolSettingsEnabled else { return [] }
        return ToolSettingsBar.settings(for: tool,
                                        availability: Experiments.shared.toolSettingsAvailability)
    }

    var body: some View {
        let settings = Self.settings(for: editorState.activeTool)
        if !settings.isEmpty {
            ToolSettingsWrap(spacing: 18, rowSpacing: 8) {
                ForEach(settings, id: \.self) { setting in
                    field(setting)
                }
            }
            // No width frame on purpose: the capsule HUGS its settings, and
            // the wrap below takes the room it is offered as the line it wraps
            // at. A `maxWidth` here made the glass span the whole picture.
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 21))
            .contentShape(.rect(cornerRadius: 21))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    /// One setting: its word, then its control, on one line. The word is the
    /// same one the right hand panel uses, so a person who learned it in one
    /// place recognises it in the other.
    @ViewBuilder private func field(_ setting: ToolSetting) -> some View {
        HStack(spacing: 8) {
            Text(setting.title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            control(setting)
        }
        // Named apart from the panel's own row of the same name, so a scripted
        // walk can say which of the two it means.
        .playtestField("Tool \(setting.title)")
    }

    @ViewBuilder private func control(_ setting: ToolSetting) -> some View {
        @Bindable var state = editorState
        switch setting {
        case .calloutShape:
            // Two choices, so both stay on screen: picking a circle is one
            // click, not a menu and then a click.
            Picker("Shape", selection: $state.calloutToolShape) {
                ForEach(ZoomCalloutShape.allCases, id: \.self) { shape in
                    Text(shape.title).tag(shape)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("What the next callout is drawn in. A callout already on the "
                  + "canvas is switched in its own section of the panel.")
        case .calloutMagnification:
            // The same short track and readout the wand's tolerance uses, and
            // the same number the picked callout's slider shows, so the one
            // idea looks the same in all three places.
            HStack(spacing: 6) {
                Slider(value: Binding(get: { editorState.calloutToolMagnification },
                                      set: { editorState.calloutToolMagnification = $0 }),
                       in: ZoomCalloutBuilder.magnificationRange)
                    .controlSize(.small)
                    .frame(width: 96)
                Text(ZoomCalloutBuilder.magnificationLabel(editorState.calloutToolMagnification))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
            .help("How much bigger the next callout draws the region it points at. "
                  + "A callout already on the canvas is resized in its own section "
                  + "of the panel.")
        case .wandTolerance:
            // Short track plus the number: the panel has the long track and the
            // sentence explaining it, this is the one you nudge mid-selection.
            HStack(spacing: 6) {
                Slider(value: Binding(get: { editorState.wandTolerance },
                                      set: { editorState.wandTolerance = $0.rounded() }),
                       in: 0...128)
                    .controlSize(.small)
                    .frame(width: 116)
                Text("\(Int(editorState.wandTolerance))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
            }
            .help("How far a color may drift and still join the selection.")
        case .measureSnap:
            Picker("Snap", selection: $state.measureSnapsToCenters) {
                Text("Edges").tag(false)
                Text("Edges and centers").tag(true)
            }
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("What measure points magnetize to. Hold Command to drag free.")
        case .measureShow:
            Picker("Show", selection: Binding(
                get: { editorState.measureShowFilter },
                set: { editorState.setMeasureShowFilter($0) })) {
                ForEach(EditorState.MeasureShowFilter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("Which measurements the canvas shows. A view filter only: exports "
                  + "always include every visible measurement.")
        }
    }
}

/// A row of controls that starts a new row rather than running off the end.
///
/// The capsule floats over the picture, so it can never be wider than the
/// picture: on a narrow window its settings stack instead. SwiftUI has no
/// wrapping stack of its own, and the alternative — hiding settings a narrow
/// window cannot fit — is exactly the disappearance this whole feature exists
/// to end.
struct ToolSettingsWrap: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let rows = self.rows(within: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +)
            + rowSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        let rows = self.rows(within: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            // Rows centre on each other, so a wrapped capsule reads as one
            // block rather than a ragged left column.
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private struct Row {
        var indices: [Int]
        var width: CGFloat
        var height: CGFloat
    }

    /// The packing itself is `ToolSettingsBar.rows`, in PhotonzCore, where it
    /// is unit-tested; this only measures the subviews and turns the answer
    /// into rows with sizes.
    private func rows(within width: CGFloat, subviews: Subviews) -> [Row] {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return ToolSettingsBar.rows(ofWidths: sizes.map(\.width), spacing: spacing,
                                    within: width)
            .map { indices in
                Row(indices: indices,
                    width: indices.map { sizes[$0].width }.reduce(0, +)
                        + spacing * CGFloat(max(0, indices.count - 1)),
                    height: indices.map { sizes[$0].height }.max() ?? 0)
            }
    }
}
