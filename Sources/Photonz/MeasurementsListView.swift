// The measurements section of the panel: the list of measurements taken on this document and the controls above it.

import AppKit
import PhotonzCore
import SwiftUI

// MARK: - Measurements section (§6, `next-measure-panel`)

/// The Measurements group's header furniture: the count badge and the panel
/// menu (Show All / Hide All / Copy as Spec List / Clear Measurements). Each
/// menu action is one undo step; Clear has no confirmation — undo is the
/// safety net.
struct MeasurementsSectionAccessory: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        HStack(spacing: 6) {
            Text("\(editorState.measurementCount)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(.quaternary))
            // The same commands as the menu bar's Measure menu, in its order
            // and under its names (§6's mirror rule), so nothing learned here
            // is wrong there. Each is off when it would change nothing.
            let count = editorState.measurementCount
            let visibleCount = editorState.visibleMeasurementCount
            Menu {
                Button("Show All Measurements") { editorState.setAllMeasurementsVisible(true) }
                    .disabled(visibleCount == count)
                Button("Hide All Measurements") { editorState.setAllMeasurementsVisible(false) }
                    .disabled(visibleCount == 0)
                Divider()
                Button("Copy as Spec List") { editorState.copyMeasureSpecList() }
                    .disabled(visibleCount == 0)
                Divider()
                Button("Clear Measurements", role: .destructive) {
                    editorState.clearAllMeasurements()
                }
                .disabled(count == 0)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .panelHelp("Show, hide, copy, or clear every measurement")
        }
    }
}

/// The Measurements rows (§6): a filtered view of the layer stack, top-most
/// first. Selection is the shared layer selection, the eye is the layer's
/// visibility, delete is layer delete — the group holds no state of its own.
struct MeasurementsListView: View {
    @Environment(EditorState.self) private var editorState
    @State private var renamingLayerID: UUID?
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 2) {
            ForEach(editorState.measurePanelLayers, id: \.id) { layer in
                row(layer)
            }
            // How many of the rows are in the selection, once it is more than
            // one: the number Copy Measurements will copy.
            let count = editorState.selectedMeasureLayerIDs.count
            if count >= 2 {
                Text("\(count) measurements selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.leading, 6)
                    .panelEdgeRowPadding()
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelListGutter)
        // The Rename command asks for a row's field; only measurement rows this
        // list shows answer it.
        .onChange(of: editorState.layerAwaitingRename) { _, id in
            guard let id, let layer = editorState.measurePanelLayers.first(where: { $0.id == id })
            else { return }
            editorState.layerAwaitingRename = nil
            beginRename(layer)
        }
    }

    private var pixelScale: CGFloat { editorState.document?.pixelScale ?? 1 }

    private func row(_ layer: Layer) -> some View {
        let isSelected = editorState.isLayerSelected(layer.id)
        let content = layer.measure
        return HStack(spacing: 8) {
            swatch(content)
            if renamingLayerID == layer.id {
                TextField("Measurement name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename(layer) }
                    .nameFieldKeys(commit: { commitRename(layer) }, revert: cancelRename)
                    .onChange(of: renameFieldFocused) { _, focused in
                        if !focused { commitRename(layer) }
                    }
            } else {
                // Rows name themselves (decision D3): axis + role wording until
                // the user renames one, then the custom name sticks.
                Text(MeasureSpecList.displayName(for: layer))
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(layer.isVisible ? .primary : .tertiary)
                    .onTapGesture(count: 2) { beginRename(layer) }
            }
            Spacer(minLength: 4)
            if let content {
                Text(content.label(pixelScale: pixelScale))
                    .font(.callout)
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(layer.isVisible ? .secondary : .tertiary)
            }
            Button {
                editorState.toggleLayerVisibility(id: layer.id)
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(layer.isVisible ? .primary : .tertiary)
            }
            .panelHelp(layer.isVisible ? "Hide Measurement" : "Show Measurement")
            .panelEdgeIcon("eye", of: MeasureSpecList.displayName(for: layer))
        }
        .buttonStyle(.borderless)
        .padding(.leading, 6)
        .panelEdgeRowPadding()
        .padding(.vertical, 4)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.25))
            }
        }
        .contentShape(Rectangle())
        // Shift ranges from the anchor row, command toggles, plain selects:
        // the same reading as the Layers rows, over this list's order.
        .onTapGesture {
            editorState.clickRow(layer.id, RowClick(modifiers: NSEvent.modifierFlags),
                                 in: editorState.measurePanelLayers.map(\.id))
        }
        .contextMenu {
            Button("Copy Measurement") { editorState.copyMeasurement(id: layer.id) }
            Divider()
            Button("Rename") { beginRename(layer) }
            Toggle(MenuToggleNames.layerVisible, isOn: Binding(
                get: { layer.isVisible },
                set: { _ in editorState.toggleLayerVisibility(id: layer.id) }))
            Divider()
            Button("Delete", role: .destructive) { editorState.deleteLayer(id: layer.id) }
        }
        // The name a walk uses for this row, so its menu can be opened and
        // photographed. Without it the measurement rows were the one list in
        // the panel nothing could reach by name.
        .playtestTarget(MeasureSpecList.displayName(for: layer), kind: .row,
                        detail: "measurement, \(layer.isVisible ? "shown" : "hidden")")
    }

    /// The row's role swatch: the measurement's own ink, so it matches the
    /// canvas even after a recolor. Alignment guides ring it dashed, like the
    /// legend.
    @ViewBuilder private func swatch(_ content: MeasureContent?) -> some View {
        let color = Color(hex: content?.strokeColorHex ?? MeasureContent.defaultStrokeColorHex)
        if content?.alignment != nil {
            Circle()
                .strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                .frame(width: 10, height: 10)
        } else {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
        }
    }

    private func beginRename(_ layer: Layer) {
        renameText = MeasureSpecList.displayName(for: layer)
        renamingLayerID = layer.id
        renameFieldFocused = true
    }

    private func commitRename(_ layer: Layer) {
        guard renamingLayerID == layer.id else { return }
        renamingLayerID = nil
        editorState.renameLayer(id: layer.id, to: renameText)
    }

    /// Escape: the row keeps the name it had and nothing reaches history, the
    /// same thing Escape does to a frame's name on the canvas.
    private func cancelRename() {
        renamingLayerID = nil
    }
}
