import AppKit
import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

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

// MARK: - Docked inspector panel

/// The full-height, docked right-side inspector (10.5). Holds collapsible,
/// drag-reorderable sections — Layers, Annotation, Effects, Shadow. Order and
/// collapsed state persist across launches; the panel width is set by the 1px
/// `InspectorResizeHandle` on its left edge.
struct InspectorPanel: View {
    @Environment(EditorState.self) private var editorState
    @AppStorage("inspector.sectionOrder") private var orderRaw = ""
    @AppStorage("inspector.collapsed") private var collapsedRaw = ""
    @State private var order: [InspectorSectionID] = InspectorSectionID.allCases
    @State private var dragging: InspectorSectionID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(orderedAvailableSections, id: \.self) { id in
                    CollapsibleSection(
                        title: id.title,
                        isCollapsed: isCollapsed(id),
                        onToggle: { toggleCollapsed(id) },
                        dragItem: {
                            dragging = id
                            return NSItemProvider(object: id.rawValue as NSString)
                        }
                    ) {
                        sectionContent(id)
                    }
                    .onDrop(of: [.text],
                            delegate: SectionDropDelegate(item: id, order: $order, dragging: $dragging))
                    Divider().opacity(0.4)
                }
            }
            .padding(.vertical, 6)
            // NO implicit animation on the section SET (10.7). Animating
            // section insert/remove forces the whole .regularMaterial panel to
            // re-blur and an NSColorWell to animate in/out every frame for the
            // spring's duration — ~350ms of pegged CPU per selection that
            // crosses between an annotation and a non-annotation layer (the
            // Annotation section toggles). Showing/hiding sections instantly
            // drops that to ~20ms. Collapse (chevron) and drag-reorder keep
            // their own explicit `withAnimation`, so they still animate.
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
        .onAppear(perform: loadOrder)
        .onChange(of: order) { persistOrder() }
    }

    private var selectedLayer: Layer? {
        guard let id = editorState.selectedLayerID else { return nil }
        return editorState.document?.layer(id: id)
    }

    /// Sections currently applicable: Layers always; Effects/Shadow when a layer
    /// is selected; Annotation only for annotation layers.
    private var availableSections: Set<InspectorSectionID> {
        var set: Set<InspectorSectionID> = [.layers]
        if let layer = selectedLayer {
            set.insert(.effects)
            set.insert(.shadow)
            if layer.annotation != nil { set.insert(.annotation) }
            if case .text = layer.content { set.insert(.text) }
        }
        return set
    }

    private var orderedAvailableSections: [InspectorSectionID] {
        let available = availableSections
        return order.filter { available.contains($0) }
    }

    @ViewBuilder
    private func sectionContent(_ id: InspectorSectionID) -> some View {
        switch id {
        case .layers:
            LayersListView()
        case .annotation:
            if let layer = selectedLayer, layer.annotation != nil {
                AnnotationInspector(layer: layer)
            }
        case .text:
            if let layer = selectedLayer, case .text = layer.content {
                TextInspector(layer: layer)
            }
        case .effects:
            if let layer = selectedLayer {
                EffectsInspector(layer: layer)
            }
        case .shadow:
            if let layer = selectedLayer {
                ShadowInspector(layer: layer)
            }
        }
    }

    // MARK: Persistence

    private func loadOrder() {
        let ids = orderRaw.split(separator: ",").compactMap { InspectorSectionID(rawValue: String($0)) }
        // Keep any sections not present in the saved string (e.g. added later).
        let missing = InspectorSectionID.allCases.filter { !ids.contains($0) }
        let merged = ids + missing
        if merged != order { order = merged }
    }

    private func persistOrder() {
        orderRaw = order.map(\.rawValue).joined(separator: ",")
    }

    private func isCollapsed(_ id: InspectorSectionID) -> Bool {
        collapsedRaw.split(separator: ",").contains(Substring(id.rawValue))
    }

    private func toggleCollapsed(_ id: InspectorSectionID) {
        var set = Set(collapsedRaw.split(separator: ",").map(String.init))
        if set.contains(id.rawValue) { set.remove(id.rawValue) } else { set.insert(id.rawValue) }
        withAnimation(.spring(duration: 0.25)) {
            collapsedRaw = set.sorted().joined(separator: ",")
        }
    }
}

/// The sections of the inspector, in their default order. `rawValue` persists.
enum InspectorSectionID: String, CaseIterable {
    case layers
    case annotation
    case text
    case effects
    case shadow

    var title: String {
        switch self {
        case .layers: "Layers"
        case .annotation: "Annotation"
        case .text: "Text"
        case .effects: "Effects"
        case .shadow: "Shadow"
        }
    }
}

/// Reorders sections live as a dragged header passes over another section.
private struct SectionDropDelegate: DropDelegate {
    let item: InspectorSectionID
    @Binding var order: [InspectorSectionID]
    @Binding var dragging: InspectorSectionID?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != item,
              let from = order.firstIndex(of: dragging),
              let to = order.firstIndex(of: item) else { return }
        withAnimation(.spring(duration: 0.25)) {
            order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// A titled section with a chevron (tap to collapse) and a drag affordance on
/// its header (drag to reorder). Elegant/modern: clean header, smooth collapse.
private struct CollapsibleSection<Content: View>: View {
    let title: String
    let isCollapsed: Bool
    let onToggle: () -> Void
    let dragItem: () -> NSItemProvider
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !isCollapsed {
                content()
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(duration: 0.25)) { onToggle() } }
        .onDrag(dragItem)
        .help("Drag to reorder • click to collapse")
    }
}

/// The 1px resize handle on the panel's left edge. Drag to set the panel width;
/// the value persists via the caller's `@AppStorage` binding.
struct InspectorResizeHandle: View {
    @Binding var width: Double
    @State private var dragStartWidth: Double?

    static let minWidth: Double = 220
    static let maxWidth: Double = 480

    var body: some View {
        Divider()
            .frame(width: 1)
            .overlay {
                // A wider, invisible strip makes the 1px line easy to grab.
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                let base = dragStartWidth ?? width
                                if dragStartWidth == nil { dragStartWidth = width }
                                // Dragging left (negative dx) widens the right panel.
                                width = min(Self.maxWidth, max(Self.minWidth, base - value.translation.width))
                            }
                            .onEnded { _ in dragStartWidth = nil }
                    )
            }
    }
}

// MARK: - Layers section

/// The layer list: thumbnails, visibility, lock, rename (double-click),
/// drag-reorder, and selection. Lives inside the docked inspector's Layers
/// section.
struct LayersListView: View {
    @Environment(EditorState.self) private var editorState
    @State private var renamingLayerID: UUID?
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        List {
            ForEach(editorState.panelLayers) { layer in
                row(layer)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .listRowBackground(Color.clear)
            }
            .onMove { source, destination in
                editorState.moveLayers(visualSources: source, visualDestination: destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .frame(height: listHeight)
        // Rows slide/fade on add, delete, duplicate, and reorder.
        .animation(.spring(duration: 0.25), value: editorState.panelLayers.map(\.id))
    }

    /// Size the list to its rows so the whole panel scrolls as one column; cap
    /// so a tall stack doesn't crowd out the inspectors below (it scrolls then).
    private var listHeight: CGFloat {
        let rows = max(1, editorState.panelLayers.count)
        return min(CGFloat(rows) * 38 + 6, 320)
    }

    private func row(_ layer: Layer) -> some View {
        let isSelected = editorState.selectedLayerID == layer.id
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
                editorState.toggleLayerLock(id: layer.id)
            } label: {
                Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 11))
                    .foregroundStyle(layer.isLocked ? .primary : .tertiary)
            }
            .help(layer.isLocked ? "Unlock Layer" : "Lock Layer")
            Button {
                editorState.toggleLayerVisibility(id: layer.id)
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
        .onTapGesture { editorState.selectLayer(layer.id) }
        .contextMenu {
            Button("Duplicate") { editorState.duplicateLayer(id: layer.id) }
            Button("Delete", role: .destructive) { editorState.deleteLayer(id: layer.id) }
        }
    }

    private func thumbnail(_ layer: Layer) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
            if let cg = editorState.thumbnail(for: layer) {
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
        editorState.renameLayer(id: layer.id, to: renameText)
    }
}

// MARK: - Effects & shadow inspectors

/// Non-destructive effects for the selected layer: opacity, blur, corner
/// radius, border. Sliders preview live and commit one undo step per gesture.
struct EffectsInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer

    private var style: LayerStyle {
        editorState.previewedStyle(of: layer.id) ?? layer.style
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LayerStyleSlider(layerID: layer.id, label: "Opacity", value: style.opacity, range: 0...1,
                             display: "\(Int((style.opacity * 100).rounded()))%") { style, v in
                style.opacity = v
            }
            LayerStyleSlider(layerID: layer.id, label: "Blur", value: Double(style.blurRadius), range: 0...50,
                             display: "\(Int(style.blurRadius.rounded())) pt") { style, v in
                style.blurRadius = CGFloat(v)
            }
            LayerStyleSlider(layerID: layer.id, label: "Corner Radius", value: Double(style.cornerRadius),
                             range: 0...maxCornerRadius,
                             display: "\(Int(style.cornerRadius.rounded())) pt") { style, v in
                style.cornerRadius = CGFloat(v)
            }
            HStack(spacing: 8) {
                LayerStyleSlider(layerID: layer.id, label: "Border", value: Double(style.borderWidth),
                                 range: 0...20,
                                 display: "\(Int(style.borderWidth.rounded())) pt") { style, v in
                    style.borderWidth = CGFloat(v)
                }
                borderColorPicker
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
                    editorState.setLayerStyle(id: layer.id) { $0.borderColorHex = hex }
                    editorState.recordRecentColor(hex: hex)
                }
            }), supportsOpacity: false)
            .labelsHidden()
            .controlSize(.small)
    }
}

/// The selected layer's shadow: a toggle plus, when on, blur (softness), size
/// (spread), distance (offset), direction (angle), opacity, and color (10.6).
struct ShadowInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer

    private var style: LayerStyle {
        editorState.previewedStyle(of: layer.id) ?? layer.style
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { style.shadow != nil },
                set: { on in
                    editorState.setLayerStyle(id: layer.id) { $0.shadow = on ? ShadowStyle() : nil }
                })) {
                Text("Enable Shadow").font(.caption).foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            if let shadow = style.shadow {
                HStack(spacing: 8) {
                    LayerStyleSlider(layerID: layer.id, label: "Blur", value: Double(shadow.radius),
                                     range: 0...40,
                                     display: "\(Int(shadow.radius.rounded())) pt") { style, v in
                        style.shadow?.radius = CGFloat(v)
                    }
                    shadowColorPicker
                }
                LayerStyleSlider(layerID: layer.id, label: "Size", value: Double(shadow.spread),
                                 range: -10...20,
                                 display: "\(Int(shadow.spread.rounded())) pt") { style, v in
                    style.shadow?.spread = CGFloat(v)
                }
                LayerStyleSlider(layerID: layer.id, label: "Distance", value: Double(shadowDistance(shadow)),
                                 range: 0...40,
                                 display: "\(Int(shadowDistance(shadow).rounded())) pt") { style, v in
                    let angle = shadowAngle(style.shadow ?? shadow)
                    style.shadow?.offset = CGSize(width: CGFloat(v) * cos(angle),
                                                  height: CGFloat(v) * sin(angle))
                }
                LayerStyleSlider(layerID: layer.id, label: "Direction", value: Double(shadowDegrees(shadow)),
                                 range: 0...360,
                                 display: "\(Int(shadowDegrees(shadow).rounded()))°") { style, v in
                    let dist = max(shadowDistance(style.shadow ?? shadow), 1) // so direction is meaningful
                    let rad = CGFloat(v) * .pi / 180
                    style.shadow?.offset = CGSize(width: dist * cos(rad), height: dist * sin(rad))
                }
                LayerStyleSlider(layerID: layer.id, label: "Opacity", value: shadow.opacity, range: 0...1,
                                 display: "\(Int((shadow.opacity * 100).rounded()))%") { style, v in
                    style.shadow?.opacity = v
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var shadowColorPicker: some View {
        ColorPicker("Shadow color", selection: Binding(
            get: { Color(hex: style.shadow?.colorHex ?? "#000000") },
            set: { color in
                if let hex = color.hexString {
                    editorState.setLayerStyle(id: layer.id) { $0.shadow?.colorHex = hex }
                    editorState.recordRecentColor(hex: hex)
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
}

/// A labeled style slider wired to EditorState's preview/commit gesture pattern:
/// dragging previews without recording undo; release commits one step.
struct LayerStyleSlider: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let display: String
    let apply: (inout LayerStyle, Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(display).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { value },
                set: { v in editorState.previewLayerStyle(id: layerID) { apply(&$0, v) } }),
                   in: range) { editing in
                if !editing { editorState.commitLayerStyle(id: layerID) }
            }
            .controlSize(.small)
        }
    }
}

// MARK: - Annotation inspector

/// Per-object annotation properties for the selected arrow/line/shape: color,
/// thickness, and (arrows only) arrowhead size. Sliders preview live and commit
/// one undo step on release, mirroring the toolbar style popover.
struct AnnotationInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer
    @State private var widthDraft: CGFloat?
    @State private var headDraft: CGFloat?
    @State private var radiusDraft: CGFloat?

    private var annotation: AnnotationContent? {
        editorState.document?.layer(id: layer.id)?.annotation
    }

    var body: some View {
        if let a = annotation {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(label(for: a.shape)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("Color", selection: Binding(
                        get: { Color(hex: a.colorHex) },
                        set: { if let hex = $0.hexString { editorState.setAnnotationColor(layerID: layer.id, hex) } }),
                        supportsOpacity: false)
                        .labelsHidden().controlSize(.small)
                }
                if a.shape != .highlight {
                    sliderRow("Thickness", value: widthDraft ?? a.strokeWidth,
                              display: "\(Int((widthDraft ?? a.strokeWidth).rounded())) pt",
                              range: AnnotationStyles.strokeWidthRange,
                              set: { v in
                                  widthDraft = v
                                  editorState.previewAnnotationRestyle(layerID: layer.id, strokeWidth: v.rounded())
                              },
                              commit: {
                                  editorState.commitAnnotationRestyle(layerID: layer.id,
                                                                   strokeWidth: (widthDraft ?? a.strokeWidth).rounded())
                                  widthDraft = nil
                              })
                }
                if a.shape == .arrow {
                    sliderRow("Head Size", value: headDraft ?? a.arrowheadScale,
                              display: "×\(String(format: "%.1f", headDraft ?? a.arrowheadScale))",
                              range: AnnotationStyles.arrowheadScaleRange,
                              set: { v in
                                  headDraft = v
                                  editorState.previewAnnotationRestyle(layerID: layer.id, arrowheadScale: v)
                              },
                              commit: {
                                  editorState.commitAnnotationRestyle(layerID: layer.id,
                                                                   arrowheadScale: headDraft ?? a.arrowheadScale)
                                  headDraft = nil
                              })
                }
                if a.shape == .rectangle {
                    sliderRow("Corner Radius", value: radiusDraft ?? a.cornerRadius,
                              display: "\(Int((radiusDraft ?? a.cornerRadius).rounded())) pt",
                              range: 0...120,
                              set: { v in
                                  radiusDraft = v
                                  editorState.previewAnnotationRestyle(layerID: layer.id, cornerRadius: v.rounded())
                              },
                              commit: {
                                  editorState.commitAnnotationRestyle(layerID: layer.id,
                                                                   cornerRadius: (radiusDraft ?? a.cornerRadius).rounded())
                                  radiusDraft = nil
                              })
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
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

/// Docked per-layer text inspector (13.1): change a placed text element's font
/// face, size, weight, and color. Mirrors `AnnotationInspector` — each change
/// is one undo step and re-measures the layer frame via the core builder.
struct TextInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer

    private var content: TextContent? {
        if case .text(let c)? = editorState.document?.layer(id: layer.id)?.content { return c }
        return nil
    }

    var body: some View {
        if let c = content {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Text").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("Color", selection: Binding(
                        get: { Color(hex: c.colorHex) },
                        set: { if let hex = $0.hexString {
                            editorState.setTextStyle(layerID: layer.id, colorHex: hex)
                        } }),
                        supportsOpacity: false)
                        .labelsHidden().controlSize(.small)
                }
                Picker("Font", selection: Binding(
                    get: { c.fontName },
                    set: { editorState.setTextStyle(layerID: layer.id, fontName: $0) })) {
                    ForEach(fontFamilies(current: c.fontName), id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().controlSize(.small)
                HStack(spacing: 8) {
                    Picker("Size", selection: Binding(
                        get: { c.fontSize },
                        set: { editorState.setTextStyle(layerID: layer.id, fontSize: $0) })) {
                        ForEach(sizes(current: c.fontSize), id: \.self) { Text("\(Int($0)) pt").tag($0) }
                    }
                    .pickerStyle(.menu).labelsHidden().controlSize(.small)
                    Picker("Weight", selection: Binding(
                        get: { c.weight },
                        set: { editorState.setTextStyle(layerID: layer.id, weight: $0) })) {
                        ForEach(TextWeight.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                    .pickerStyle(.menu).labelsHidden().controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    /// Curated families plus the current one if it's off-list (keeps it valid).
    private func fontFamilies(current: String) -> [String] {
        TextStyles.fonts.contains(current) ? TextStyles.fonts : TextStyles.fonts + [current]
    }

    /// Preset sizes plus the current one if it's off-list (e.g. a custom size).
    private func sizes(current: CGFloat) -> [CGFloat] {
        TextStyles.fontSizes.contains(current) ? TextStyles.fontSizes
            : (TextStyles.fontSizes + [current]).sorted()
    }
}
