import AppKit
import PhotonzCore
import SwiftUI

extension Color {
    /// The document model's hex form of this color (alpha dropped); nil for
    /// colors outside sRGB.
    var hexString: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}

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
            // Rows slide/fade on add, delete, duplicate, and reorder.
            .animation(.spring(duration: 0.25), value: appState.panelLayers.map(\.id))
            if let layer = selectedLayer {
                Divider().padding(.horizontal, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if layer.annotation != nil {
                            AnnotationInspector(layer: layer)
                            Divider().padding(.horizontal, 10)
                        }
                        LayerInspector(layer: layer)
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 248)
        .frame(maxHeight: 560)
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
            styleSlider("Blur", value: Double(style.blurRadius), in: 0...50,
                        display: "\(Int(style.blurRadius.rounded())) pt") { style, v in
                style.blurRadius = CGFloat(v)
            }
            styleSlider("Corner Radius", value: Double(style.cornerRadius), in: 0...maxCornerRadius,
                        display: "\(Int(style.cornerRadius.rounded())) pt") { style, v in
                style.cornerRadius = CGFloat(v)
            }
            HStack(spacing: 8) {
                styleSlider("Border", value: Double(style.borderWidth), in: 0...20,
                            display: "\(Int(style.borderWidth.rounded())) pt") { style, v in
                    style.borderWidth = CGFloat(v)
                }
                borderColorPicker
            }
            shadowControls
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Corner rounding past half the short edge has no visible effect.
    private var maxCornerRadius: Double {
        max(1, Double(min(layer.frame.width, layer.frame.height) / 2))
    }

    private var borderColorPicker: some View {
        ColorPicker("Border color", selection: Binding(
            get: { Color(hex: style.borderColorHex) },
            set: { color in
                if let hex = color.hexString {
                    appState.setLayerStyle(id: layer.id) { $0.borderColorHex = hex }
                }
            }), supportsOpacity: false)
            .labelsHidden()
            .controlSize(.small)
    }

    @ViewBuilder
    private var shadowControls: some View {
        Toggle(isOn: Binding(
            get: { style.shadow != nil },
            set: { on in
                appState.setLayerStyle(id: layer.id) { $0.shadow = on ? ShadowStyle() : nil }
            })) {
            Text("Shadow").font(.caption).foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        if let shadow = style.shadow {
            HStack(spacing: 8) {
                styleSlider("Shadow Blur", value: Double(shadow.radius), in: 0...40,
                            display: "\(Int(shadow.radius.rounded())) pt") { style, v in
                    style.shadow?.radius = CGFloat(v)
                }
                shadowColorPicker
            }
            styleSlider("Shadow Distance", value: Double(shadowDistance(shadow)), in: 0...40,
                        display: "\(Int(shadowDistance(shadow).rounded())) pt") { style, v in
                let angle = shadowAngle(style.shadow ?? shadow)
                style.shadow?.offset = CGSize(width: CGFloat(v) * cos(angle),
                                              height: CGFloat(v) * sin(angle))
            }
            styleSlider("Shadow Direction", value: Double(shadowDegrees(shadow)), in: 0...360,
                        display: "\(Int(shadowDegrees(shadow).rounded()))°") { style, v in
                let dist = max(shadowDistance(style.shadow ?? shadow), 1) // so direction is meaningful
                let rad = CGFloat(v) * .pi / 180
                style.shadow?.offset = CGSize(width: dist * cos(rad), height: dist * sin(rad))
            }
            styleSlider("Shadow Opacity", value: shadow.opacity, in: 0...1,
                        display: "\(Int((shadow.opacity * 100).rounded()))%") { style, v in
                style.shadow?.opacity = v
            }
        }
    }

    private var shadowColorPicker: some View {
        ColorPicker("Shadow color", selection: Binding(
            get: { Color(hex: style.shadow?.colorHex ?? "#000000") },
            set: { color in
                if let hex = color.hexString {
                    appState.setLayerStyle(id: layer.id) { $0.shadow?.colorHex = hex }
                }
            }), supportsOpacity: false)
            .labelsHidden()
            .controlSize(.small)
    }

    private func shadowDistance(_ s: PhotonzCore.ShadowStyle) -> CGFloat { hypot(s.offset.width, s.offset.height) }
    /// Offset angle in radians; defaults to 90° (straight down) when there's no
    /// offset so the direction control still reads sensibly.
    private func shadowAngle(_ s: PhotonzCore.ShadowStyle) -> CGFloat {
        (s.offset.width == 0 && s.offset.height == 0) ? .pi / 2 : atan2(s.offset.height, s.offset.width)
    }
    private func shadowDegrees(_ s: PhotonzCore.ShadowStyle) -> CGFloat {
        let deg = shadowAngle(s) * 180 / .pi
        return deg < 0 ? deg + 360 : deg
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

/// Per-object annotation properties for the selected arrow/line/shape: color,
/// thickness, and (arrows only) arrowhead size. Sliders preview live and commit
/// one undo step on release, mirroring the toolbar style popover.
struct AnnotationInspector: View {
    @Environment(AppState.self) private var appState
    let layer: Layer
    @State private var widthDraft: CGFloat?
    @State private var headDraft: CGFloat?

    private var annotation: AnnotationContent? {
        appState.document?.layer(id: layer.id)?.annotation
    }

    var body: some View {
        if let a = annotation {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(label(for: a.shape)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("Color", selection: Binding(
                        get: { Color(hex: a.colorHex) },
                        set: { if let hex = $0.hexString { appState.setAnnotationColor(hex) } }),
                        supportsOpacity: false)
                        .labelsHidden().controlSize(.small)
                }
                if a.shape != .highlight {
                    sliderRow("Thickness", value: widthDraft ?? a.strokeWidth,
                              display: "\(Int((widthDraft ?? a.strokeWidth).rounded())) pt",
                              range: AnnotationStyles.strokeWidthRange,
                              set: { v in widthDraft = v; appState.previewAnnotationRestyle(strokeWidth: v.rounded()) },
                              commit: {
                                  appState.setAnnotationStrokeWidth((widthDraft ?? a.strokeWidth).rounded())
                                  widthDraft = nil
                              })
                }
                if a.shape == .arrow {
                    sliderRow("Head Size", value: headDraft ?? a.arrowheadScale,
                              display: "×\(String(format: "%.1f", headDraft ?? a.arrowheadScale))",
                              range: AnnotationStyles.arrowheadScaleRange,
                              set: { v in headDraft = v; appState.previewAnnotationRestyle(arrowheadScale: v) },
                              commit: {
                                  appState.setAnnotationArrowheadScale(headDraft ?? a.arrowheadScale)
                                  headDraft = nil
                              })
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func label(for shape: AnnotationShape) -> String {
        switch shape {
        case .arrow: "Arrow"
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .highlight: "Highlight"
        }
    }

    @ViewBuilder
    private func sliderRow(_ label: String, value: CGFloat, display: String,
                           range: ClosedRange<CGFloat>,
                           set: @escaping (CGFloat) -> Void,
                           commit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(display).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { value }, set: { set($0) }), in: range) { editing in
                if !editing { commit() }
            }
            .controlSize(.small)
        }
    }
}
