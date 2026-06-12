import PhotonzCore
import SwiftUI

/// Right-side glass panel listing layers top-down: thumbnails, visibility,
/// lock, rename (double-click), drag-reorder, and an opacity slider plus
/// effects inspector for the selected layer.
struct LayersPanel: View {
    @Environment(AppState.self) private var appState
    @State private var renamingLayerID: UUID?
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Layers")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)
            List {
                ForEach(appState.panelLayers) { layer in
                    row(layer)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .listRowBackground(Color.clear)
                }
                .onMove { source, destination in
                    appState.moveLayers(visualSources: source, visualDestination: destination)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            if let layer = selectedLayer {
                Divider().padding(.horizontal, 10)
                LayerInspector(layer: layer)
            }
        }
        .frame(width: 248)
        .frame(maxHeight: 480)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var selectedLayer: Layer? {
        guard let id = appState.selectedLayerID else { return nil }
        return appState.document?.layer(id: id)
    }

    private func row(_ layer: Layer) -> some View {
        let isSelected = appState.selectedLayerID == layer.id
        return HStack(spacing: 8) {
            thumbnail(layer)
            if renamingLayerID == layer.id {
                TextField("Layer name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename(layer) }
                    .onChange(of: renameFieldFocused) { _, focused in
                        if !focused { commitRename(layer) }
                    }
            } else {
                Text(layer.name)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(layer.isVisible ? .primary : .tertiary)
                    .onTapGesture(count: 2) { beginRename(layer) }
            }
            Spacer(minLength: 4)
            Button {
                appState.toggleLayerLock(id: layer.id)
            } label: {
                Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 11))
                    .foregroundStyle(layer.isLocked ? .primary : .tertiary)
            }
            .help(layer.isLocked ? "Unlock Layer" : "Lock Layer")
            Button {
                appState.toggleLayerVisibility(id: layer.id)
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(layer.isVisible ? .primary : .tertiary)
            }
            .help(layer.isVisible ? "Hide Layer" : "Show Layer")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.25))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { appState.selectLayer(layer.id) }
        .contextMenu {
            Button("Duplicate") { appState.duplicateLayer(id: layer.id) }
            Button("Delete", role: .destructive) { appState.deleteLayer(id: layer.id) }
        }
    }

    private func thumbnail(_ layer: Layer) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
            if let cg = appState.thumbnail(for: layer) {
                Image(decorative: cg, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(1)
            }
        }
        .frame(width: 40, height: 30)
    }

    private func beginRename(_ layer: Layer) {
        renameText = layer.name
        renamingLayerID = layer.id
        renameFieldFocused = true
    }

    private func commitRename(_ layer: Layer) {
        guard renamingLayerID == layer.id else { return }
        renamingLayerID = nil
        appState.renameLayer(id: layer.id, to: renameText)
    }
}

/// Non-destructive effects for the selected layer: opacity, blur, corner
/// radius, border, shadow. Sliders preview live and commit one undo step per
/// gesture on release.
struct LayerInspector: View {
    @Environment(AppState.self) private var appState
    let layer: Layer

    private var style: LayerStyle {
        appState.previewedStyle(of: layer.id) ?? layer.style
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            styleSlider("Opacity", value: style.opacity, in: 0...1,
                        display: "\(Int((style.opacity * 100).rounded()))%") { style, v in
                style.opacity = v
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// A labeled slider wired to the preview/commit gesture pattern.
    @ViewBuilder
    func styleSlider(_ label: String, value: Double, in range: ClosedRange<Double>,
                     display: String, apply: @escaping (inout LayerStyle, Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(display).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { value },
                set: { v in appState.previewLayerStyle(id: layer.id) { apply(&$0, v) } }),
                   in: range) { editing in
                if !editing { appState.commitLayerStyle(id: layer.id) }
            }
            .controlSize(.small)
        }
    }
}
