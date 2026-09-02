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

    /// This color's alpha, for the pickers that offer an opacity slider (the
    /// model stores alpha in its own field — hex strings never carry it).
    var alphaComponent: CGFloat {
        NSColor(self).usingColorSpace(.sRGB)?.alphaComponent ?? 1
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
                        },
                        accessory: sectionAccessory(id)
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
            if layer.measure != nil { set.insert(.measure) }
            if layer.collage != nil { set.insert(.collage) }
        }
        if editorState.isCanvasSelected { set.insert(.canvas) }
        // The Measurements group (§6, `next-measure-panel`): a filtered view of
        // the layer stack, present whenever the document holds a measurement.
        if Experiments.shared.measurePanelEnabled, editorState.measurementCount > 0 {
            set.insert(.measurements)
        }
        // The Measure tool's own properties (D15): Snap and Show are settings,
        // not modes, so they left the tool bar and live here while the tool is
        // in hand. The Mode row is a deliberate echo of the button's flyout —
        // the flyout is the fast path, this is where the live mode is readable
        // as a word rather than a glyph.
        if editorState.activeTool == .measure, MeasureToolInspector.hasAnySetting {
            set.insert(.measureTool)
        }
        // The Magic Wand's own properties (D15): tolerance is a setting, not a
        // mode, so it left the tool bar and lives here while the wand is in
        // hand.
        if editorState.activeTool == .wand, Experiments.shared.toolOptionsEnabled {
            set.insert(.wandTool)
        }
        // Crop's aspect lock, in words. The tool button's flyout is the fast
        // path; D15 asks that the live mode stay readable somewhere as a word,
        // because a glyph says what the next drag does and does not remind you
        // three minutes later.
        if editorState.activeTool == .crop, Experiments.shared.toolOptionsEnabled {
            set.insert(.cropTool)
        }
        return set
    }

    private var orderedAvailableSections: [InspectorSectionID] {
        let available = availableSections
        return order.filter { available.contains($0) }
    }

    /// Header furniture for sections that carry any: the Measurements group's
    /// count badge and panel menu (§6).
    private func sectionAccessory(_ id: InspectorSectionID) -> AnyView? {
        guard id == .measurements else { return nil }
        return AnyView(MeasurementsSectionAccessory())
    }

    @ViewBuilder
    private func sectionContent(_ id: InspectorSectionID) -> some View {
        switch id {
        case .layers:
            LayersListView()
        case .measurements:
            MeasurementsListView()
        case .measureTool:
            MeasureToolInspector()
        case .wandTool:
            WandToolInspector()
        case .cropTool:
            CropToolInspector()
        case .annotation:
            if let layer = selectedLayer, layer.annotation != nil {
                AnnotationInspector(layer: layer)
            }
        case .text:
            if let layer = selectedLayer, case .text = layer.content {
                TextInspector(layer: layer)
            }
        case .measure:
            if let layer = selectedLayer, layer.measure != nil {
                MeasureInspector(layer: layer)
            }
        case .collage:
            if let layer = selectedLayer, layer.collage != nil {
                CollageInspector(layer: layer)
            }
        case .canvas:
            if editorState.isCanvasSelected {
                CanvasInspector()
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
        // Sections added after this panel's order was last saved get spliced in
        // at their canonical position rather than dumped at the bottom, so a new
        // section lands where it was designed to sit for people who have already
        // run the app (which is everyone).
        var merged = ids
        for section in InspectorSectionID.allCases where !merged.contains(section) {
            let canonical = InspectorSectionID.allCases.firstIndex(of: section) ?? 0
            let insertAt = merged.firstIndex {
                (InspectorSectionID.allCases.firstIndex(of: $0) ?? 0) > canonical
            } ?? merged.endIndex
            merged.insert(section, at: insertAt)
        }
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
    case measureTool
    case wandTool
    case cropTool
    case measurements
    case annotation
    case text
    case measure
    case collage
    case canvas
    case effects
    case shadow

    var title: String {
        switch self {
        case .layers: "Layers"
        case .measureTool: "Measure Tool"
        case .wandTool: "Magic Wand"
        case .cropTool: "Crop Tool"
        case .measurements: "Measurements"
        case .annotation: "Annotation"
        case .text: "Text"
        case .measure: "Measure"
        case .collage: "Collage"
        case .canvas: "Canvas"
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

/// Measured natural height of the layer rows, so the bounded scroll area hugs
/// the content until it exceeds the resizable max.
private struct LayersContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Reorders layers when a dragged row is dropped on another. The move is one
/// document mutation (undo step) applied on drop, using the same visual-index
/// convention as the old `List.onMove`.
private struct LayerRowDropDelegate: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let editorState: EditorState

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        defer { dragging = nil }
        let layers = editorState.panelLayers
        guard let dragging, dragging != target,
              let from = layers.firstIndex(where: { $0.id == dragging }),
              let to = layers.firstIndex(where: { $0.id == target }) else { return false }
        editorState.moveLayers(visualSources: IndexSet(integer: from),
                               visualDestination: to > from ? to + 1 : to)
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
    /// Optional header furniture between the title and the drag grip — the
    /// Measurements section puts its count badge and panel menu here.
    var accessory: AnyView?
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
            if let accessory { accessory }
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
                // A wide, invisible strip makes the 1px line easy to grab — a
                // hairline is nearly impossible to hit, so give it a 14pt target
                // (extends 7pt each side of the divider).
                Color.clear
                    .frame(width: 14)
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
            // The 14pt grab strip spills past the 1pt divider; let it receive
            // hits in that overhang instead of being clipped to 1pt.
            .frame(width: 1)
            .zIndex(1)
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
    @State private var draggingLayerID: UUID?
    @FocusState private var renameFieldFocused: Bool

    /// The layer area's max height (user-resizable, persisted). Beyond this the
    /// list scrolls INTERNALLY so a tall stack doesn't shove the Effects/Shadow
    /// sections off the bottom of the inspector — you keep the other palettes in
    /// view and scroll layers on their own.
    @AppStorage("inspector.layersHeight") private var maxHeight = 260.0
    /// Measured natural height of all the rows, so the area hugs the content when
    /// it's short and only caps + scrolls once it exceeds `maxHeight`.
    @State private var contentHeight: CGFloat = 160
    @State private var dragStartHeight: CGFloat?

    static let minHeight: CGFloat = 120
    static let maxAllowedHeight: CGFloat = 600

    /// A plain VStack of rows (NOT a `List`: a List has no natural height and its
    /// fixed-height hack clipped the top rows), inside a bounded ScrollView so it
    /// scrolls independently, plus a drag handle to resize it. Reordering uses the
    /// same drag/drop the inspector sections use.
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                rows
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: LayersContentHeightKey.self,
                                               value: proxy.size.height)
                    })
            }
            .frame(height: min(contentHeight, maxHeight))
            .scrollBounceBehavior(.basedOnSize)
            .onPreferenceChange(LayersContentHeightKey.self) { contentHeight = $0 }

            resizeHandle
        }
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(editorState.panelLayers) { layer in
                row(layer)
                    .onDrag {
                        draggingLayerID = layer.id
                        return NSItemProvider(object: layer.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: LayerRowDropDelegate(
                        target: layer.id, dragging: $draggingLayerID, editorState: editorState))
            }
            // The Canvas pseudo-layer: pinned at the very bottom (beneath the
            // Background it frames). Not a real layer — no eye/lock/delete/
            // reorder; selecting it puts resize handles on the canvas boundary.
            canvasRow
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
        // Rows slide/fade on add, delete, duplicate, and reorder.
        .animation(.spring(duration: 0.25), value: editorState.panelLayers.map(\.id))
    }

    /// A grabber under the list — drag to resize the layer area's max height.
    /// Only meaningful once the list is tall enough to scroll, but always shown
    /// so the affordance is discoverable.
    private var resizeHandle: some View {
        Capsule()
            .fill(.tertiary)
            .frame(width: 32, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: 12)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                // GLOBAL space: the handle moves as the area resizes, so a
                // local-space translation would be measured against the moving
                // handle and jiggle. Base off the ACTUAL frame height (not the
                // stored max, which can exceed content) so it tracks the cursor
                // 1:1 instead of needing a big pull to catch up.
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        let currentFrame = min(contentHeight, maxHeight)
                        let base = dragStartHeight ?? currentFrame
                        if dragStartHeight == nil { dragStartHeight = currentFrame }
                        maxHeight = min(Self.maxAllowedHeight,
                                        max(Self.minHeight, base + value.translation.height))
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
            .help("Drag to resize the layers area")
    }

    private var canvasRow: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .foregroundStyle(.tertiary)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 40, height: 30)
            Text("Canvas")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let size = editorState.document?.canvasSize {
                Text(verbatim: "\(Int(size.width)) × \(Int(size.height))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            if editorState.isCanvasSelected {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.25))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editorState.selectCanvas() }
        .help("Select to resize the canvas by its edges")
    }

    private func row(_ layer: Layer) -> some View {
        let isSelected = editorState.isLayerSelected(layer.id)
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
        // ⌘-click loads the layer's opaque pixels as a selection (Photoshop's
        // load-transparency); a plain click just selects the layer.
        .highPriorityGesture(
            TapGesture().modifiers(.command).onEnded { editorState.selectLayerPixels(id: layer.id) }
        )
        .onTapGesture { editorState.selectLayer(layer.id) }
        .contextMenu {
            Button("Duplicate") { editorState.duplicateLayer(id: layer.id) }
                .keyboardShortcut("d", modifiers: .command)
            Button("Select Pixels") { editorState.selectLayerPixels(id: layer.id) }
            Button("Merge Down") { editorState.mergeDown(id: layer.id) }
                .keyboardShortcut("e", modifiers: .command)
            if layer.isRasterizable {
                Button("Rasterize Layer") { editorState.rasterizeLayer(id: layer.id) }
            }
            Divider()
            Button("Bring to Front") { editorState.bringLayerToFront(id: layer.id) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Bring Forward") { editorState.bringLayerForward(id: layer.id) }
                .keyboardShortcut("]", modifiers: .command)
            Button("Send Backward") { editorState.sendLayerBackward(id: layer.id) }
                .keyboardShortcut("[", modifiers: .command)
            Button("Send to Back") { editorState.sendLayerToBack(id: layer.id) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Divider()
            Button("Rename") { beginRename(layer) }
            Button(layer.isVisible ? "Hide" : "Show") { editorState.toggleLayerVisibility(id: layer.id) }
            Button(layer.isLocked ? "Unlock" : "Lock") { editorState.toggleLayerLock(id: layer.id) }
            Divider()
            Button("Delete", role: .destructive) { editorState.deleteLayer(id: layer.id) }
                .keyboardShortcut(.delete, modifiers: .command)
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

// MARK: - Measure tool properties (D15)

/// The Measure tool's own properties, shown while the tool is in hand.
///
/// These used to ride in the tool bar as a Snap menu and a Show menu next to
/// four mode chips, six controls that grew a fixed strip the moment you picked
/// the tool up. D15 draws the line: a mode changes what a click DOES and can
/// live in the tool button, and everything else is a setting that belongs with
/// the tool's properties. Snap changes where a point lands, Show changes what
/// the canvas draws, and both read better as words in a panel than as menus in
/// a strip.
///
/// Mode is here too, on purpose. The button's flyout is the fast path, but a
/// glyph cannot tell you three minutes later that you are still in Gap, so the
/// live mode stays readable as a word for anyone with the inspector open.
struct MeasureToolInspector: View {
    @Environment(EditorState.self) private var editorState

    /// Whether any of the tool's settings exist in this release, so the panel
    /// can leave the section out entirely rather than show an empty box.
    static var hasAnySetting: Bool {
        Experiments.shared.measureModesEnabled || Experiments.shared.measureCenterSnapEnabled
            || Experiments.shared.measureRolesEnabled
    }

    var body: some View {
        @Bindable var state = editorState
        VStack(alignment: .leading, spacing: 8) {
            if Experiments.shared.measureModesEnabled {
                field("Mode") {
                    Picker("Mode", selection: $state.measureToolMode) {
                        ForEach(MeasureToolMode.available(
                            alignmentEnabled: Experiments.shared.measureAlignEnabled), id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden().controlSize(.small)
                    .help("What a click does. The Measure button holds the same list, "
                          + "and I cycles it.")
                }
            }
            if Experiments.shared.measureCenterSnapEnabled {
                field("Snap") {
                    Picker("Snap", selection: $state.measureSnapsToCenters) {
                        Text("Edges").tag(false)
                        Text("Edges and centers").tag(true)
                    }
                    .labelsHidden().controlSize(.small)
                    .help("What measure points magnetize to. Hold Command to drag free.")
                }
            }
            if Experiments.shared.measureRolesEnabled {
                field("Show") {
                    Picker("Show", selection: Binding(
                        get: { editorState.measureShowFilter },
                        set: { editorState.setMeasureShowFilter($0) })) {
                        ForEach(EditorState.MeasureShowFilter.allCases, id: \.self) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .labelsHidden().controlSize(.small)
                    .help("Which measurements the canvas shows. A view filter only: exports "
                          + "always include every visible measurement.")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder private func field<Content: View>(_ label: String,
                                                   @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}

// MARK: - Magic Wand tool properties (D15)

/// The Magic Wand's own properties, shown while the tool is in hand.
///
/// Tolerance used to ride in the tool bar as a labelled slider, 152pt that
/// appeared the moment you picked the wand up. It is a setting by D15's test —
/// it changes what the result looks like, not what the pointer does — so it
/// belongs with the tool's properties, and it reads better here with room for
/// the number and a line saying what it means.
struct WandToolInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        @Bindable var state = editorState
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tolerance").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(editorState.wandTolerance))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { editorState.wandTolerance },
                                  set: { editorState.wandTolerance = $0.rounded() }),
                   in: 0...128)
                .controlSize(.small)
            Text("How far a color may drift and still join the selection.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Crop tool properties (D15)

/// The Crop tool's own properties, shown while the tool is in hand: the aspect
/// lock as a word.
///
/// The four locks used to be four chips in the tool bar. They are modes, so
/// they moved into the crop button's flyout; this is the same choice spelled
/// out, for anyone with the inspector open. Picking here reshapes the pending
/// crop rect exactly as the flyout does.
struct CropToolInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Aspect").font(.caption).foregroundStyle(.secondary)
            Picker("Aspect", selection: Binding(get: { editorState.cropAspect },
                                                set: { editorState.setCropAspect($0) })) {
                ForEach(CropAspect.allCases, id: \.self) { aspect in
                    Text(aspect.label).tag(aspect)
                }
            }
            .labelsHidden().controlSize(.small)
            .help("What shape the crop keeps. The Crop button holds the same list.")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

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
            Menu {
                Button("Show All") { editorState.setAllMeasurementsVisible(true) }
                Button("Hide All") { editorState.setAllMeasurementsVisible(false) }
                Divider()
                Button("Copy as Spec List") { editorState.copyMeasureSpecList() }
                Divider()
                Button("Clear Measurements", role: .destructive) {
                    editorState.clearAllMeasurements()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Show, hide, copy, or clear every measurement")
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
        }
        .padding(.horizontal, 8)
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
            .help(layer.isVisible ? "Hide Measurement" : "Show Measurement")
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
            Button("Rename") { beginRename(layer) }
            Button(layer.isVisible ? "Hide" : "Show") {
                editorState.toggleLayerVisibility(id: layer.id)
            }
            Divider()
            Button("Delete", role: .destructive) { editorState.deleteLayer(id: layer.id) }
        }
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
                                 range: 0...80,
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
    @State private var captionDraft: String = ""
    @State private var captionSizeDraft: CGFloat?

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
                if a.shape == .rectangle || a.shape == .ellipse {
                    HStack {
                        Toggle("Fill", isOn: Binding(
                            get: { a.fillColorHex != nil },
                            // Toggling on seeds the fill with the stroke color;
                            // the well below refines it. Off = no fill.
                            set: { editorState.setAnnotationFill(layerID: layer.id, $0 ? a.colorHex : nil) }))
                            .font(.caption).controlSize(.small)
                        Spacer()
                        if let fillHex = a.fillColorHex {
                            ColorPicker("Fill Color", selection: Binding(
                                get: { Color(hex: fillHex) },
                                set: { if let hex = $0.hexString { editorState.setAnnotationFill(layerID: layer.id, hex) } }),
                                supportsOpacity: false)
                                .labelsHidden().controlSize(.small)
                        }
                    }
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
                if a.shape == .arrow, Experiments.shared.arrowCaptionsEnabled {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Caption").font(.caption).foregroundStyle(.secondary)
                        TextField("Add a caption", text: $captionDraft)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .onSubmit {
                                editorState.setAnnotationCaption(layerID: layer.id, captionDraft)
                            }
                    }
                    // Track the model (initially, after undo, on layer switch);
                    // typing edits only the draft until Return commits.
                    .onChange(of: a.caption ?? "", initial: true) { _, new in
                        captionDraft = new
                    }
                    if a.hasCaption {
                        sliderRow("Label size", value: captionSizeDraft ?? a.captionFontSize,
                                  display: "\(Int((captionSizeDraft ?? a.captionFontSize).rounded())) px",
                                  range: MeasureContent.labelSizeRangePx,
                                  set: { v in
                                      captionSizeDraft = v
                                      editorState.previewCaptionFontSize(layerID: layer.id, v.rounded())
                                  },
                                  commit: {
                                      editorState.commitCaptionFontSize(
                                          layerID: layer.id, (captionSizeDraft ?? a.captionFontSize).rounded())
                                      captionSizeDraft = nil
                                  })
                    }
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

/// Docked per-layer measure inspector (16.3): unit, label toggle, color, and the
/// document's pixel scale (so the points readout is correct on a Retina capture).
struct MeasureInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer
    @State private var nameDraft = ""
    /// Which layer `nameDraft` was typed for. Selecting another measurement
    /// while the field has focus drops focus AFTER `layer` has changed, and
    /// the draft must not land on the new selection.
    @State private var draftLayerID: UUID?
    @FocusState private var nameFocused: Bool

    private var content: MeasureContent? {
        editorState.document?.layer(id: layer.id)?.measure
    }

    /// The name the Measurements row shows: derived until renamed, then the
    /// custom name. The Name field edits exactly this.
    private var displayName: String {
        MeasureSpecList.displayName(for: editorState.document?.layer(id: layer.id) ?? layer)
    }

    var body: some View {
        if let c = content {
            VStack(alignment: .leading, spacing: 8) {
                // The same rename the Measurements row offers on double-click
                // (decision D3), reachable from Properties too. It commits
                // through the same call, so it is one undo step either way.
                if Experiments.shared.measurePanelEnabled {
                    field("Name") {
                        TextField("Measurement name", text: $nameDraft)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .focused($nameFocused)
                            .onSubmit { commitName() }
                            .onChange(of: nameFocused) { _, focused in
                                if !focused { commitName() }
                            }
                            .help("What this measurement is called in the Measurements "
                                  + "list and the copied spec list")
                    }
                    .id(layer.id)
                    .onAppear {
                        nameDraft = displayName
                        draftLayerID = layer.id
                    }
                    .onChange(of: displayName) { _, name in
                        if !nameFocused { nameDraft = name }
                    }
                }
                // The mock's Role control (§5, `next-measure-roles`): Size vs
                // Spacing, each with its own remembered color set. Alignment
                // guides are their own kind, so they don't offer it.
                if Experiments.shared.measureRolesEnabled, c.alignment == nil {
                    field("Role") {
                        Picker("Role", selection: Binding(
                            get: { c.role },
                            set: { editorState.setMeasureRole($0) })) {
                            Text("Size").tag(MeasureRole.size)
                            Text("Spacing").tag(MeasureRole.spacing)
                        }
                        .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                        .help("What this measurement calls out. Switching applies that "
                              + "role's remembered colors, and new measurements start "
                              + "with the last-used role.")
                    }
                }
                field("Unit") {
                    Picker("Unit", selection: Binding(
                        get: { c.unit },
                        set: { editorState.setMeasureUnit($0) })) {
                        // "Logical" = on-screen/design size (points); "Actual" =
                        // raw bitmap pixels (2× on a Retina screenshot).
                        Text("Logical").tag(MeasureUnit.points)
                        Text("Actual").tag(MeasureUnit.pixels)
                    }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                    .help("Both read out in px. Logical is the on-screen size (like CSS px, the "
                          + "default); Actual is raw device pixels, 2× larger on a Retina screenshot.")
                }
                field("Thickness") {
                    Picker("Thickness", selection: Binding(
                        get: { c.strokeWidth },
                        set: { editorState.setMeasureThickness($0) })) {
                        Text("1 px").tag(CGFloat(1))
                        Text("2 px").tag(CGFloat(2))
                        Text("3 px").tag(CGFloat(3))
                    }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                }
                field("Label size") {
                    // During a drag the committed doc hasn't changed, so read the
                    // live preview value (else the thumb snaps back / resets).
                    let liveScale = editorState.measureLabelPreview?.scale ?? c.labelScale
                    let px = liveScale * MeasureContent.labelFontSize
                    let lo = Double(MeasureContent.labelSizeRangePx.lowerBound)
                    let hi = Double(MeasureContent.labelSizeRangePx.upperBound)
                    HStack(spacing: 8) {
                        Slider(value: Binding(
                            get: { Double(px) },
                            set: { editorState.previewMeasureLabelScale(CGFloat($0) / MeasureContent.labelFontSize) }),
                               in: lo...hi,
                               onEditingChanged: { editing in
                                   if !editing {
                                       editorState.commitMeasureLabelScale(
                                           editorState.measureLabelPreview?.scale ?? c.labelScale)
                                   }
                               })
                            .controlSize(.small)
                        Text("\(Int(px.rounded())) px")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                // Three swatches, no extra sliders: Stroke = caliper ink + the
                // chip's border, Chip = the pill's fill (its picker carries the
                // opacity slider, so "no chip" is just alpha 0), Text = readout.
                // Whole-object transparency lives in Effects, where every layer's
                // does.
                swatchRow("Stroke", color: Color(hex: c.strokeColorHex)) {
                    if let hex = $0.hexString { editorState.setMeasureStrokeColor(hex, commit: true) }
                }
                swatchRow("Chip", color: Color(hex: c.chipColorHex).opacity(c.chipOpacity),
                          supportsOpacity: true) {
                    if let hex = $0.hexString {
                        editorState.setMeasureChipColor(hex, opacity: $0.alphaComponent, commit: true)
                    }
                }
                swatchRow("Text", color: Color(hex: c.textColorHex)) {
                    if let hex = $0.hexString { editorState.setMeasureTextColor(hex, commit: true) }
                }
                if Experiments.shared.measurePanelEnabled {
                    geometryGrid(c)
                    exportSection
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    /// Commits the Name field the way the row's double-click rename does: a
    /// trimmed, non-empty name that differs from what the row already shows.
    /// Clearing the field just puts the current name back.
    private func commitName() {
        guard draftLayerID == layer.id else { return }
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != displayName else {
            nameDraft = displayName
            return
        }
        editorState.renameLayer(id: layer.id, to: trimmed)
    }

    /// The mock's read-only From / To / Distance / Units grid (§6): the feet in
    /// document coordinates and the span, straight from `caliperGeometry()` —
    /// no new model state. A guide (§9) reads Length instead of Distance, and
    /// adds the edge it settled on and how many things it checked.
    @ViewBuilder private func geometryGrid(_ c: MeasureContent) -> some View {
        let frame = editorState.document?.layer(id: layer.id)?.frame ?? layer.frame
        let g = c.caliperGeometry()
        let scale = editorState.document?.pixelScale ?? 1
        Divider().opacity(0.4)
        VStack(alignment: .leading, spacing: 4) {
            readoutRow("From", point(g.footA, in: frame, scale: scale))
            readoutRow("To", point(g.footB, in: frame, scale: scale))
            readoutRow(c.alignment == nil ? "Distance" : "Length",
                       String(format: "%.\(max(0, c.decimals))f %@",
                              c.displayDistance(pixelScale: scale), c.unit.suffix))
            if let check = c.alignment {
                readoutRow("Edge", edgeReadout(c, check, in: frame, scale: scale))
                readoutRow("Items", itemsReadout(check))
            }
            readoutRow("Units", c.unit == .points ? "Logical px" : "Actual px")
        }
    }

    /// Which edge the guide settled on and where it is, in the measure's unit:
    /// "Left, x 312 px", or just "x 312 px" when the scan could not tell the
    /// side. The position is the reference line, which is where the guide
    /// itself sits once committed.
    private func edgeReadout(_ c: MeasureContent, _ check: AlignmentCheck,
                             in frame: CGRect, scale: CGFloat) -> String {
        guard let verdict = check.verdict else { return "no edges" }
        let position: String
        switch c.mode {
        case .vertical:
            let x = c.displayValue(frame.minX + verdict.reference, pixelScale: scale)
            position = "x \(Int(x.rounded())) \(c.unit.suffix)"
        case .horizontal:
            let y = c.displayValue(frame.minY + verdict.reference, pixelScale: scale)
            position = "y \(Int(y.rounded())) \(c.unit.suffix)"
        }
        guard let edge = c.alignedEdge else { return position }
        return "\(edge.word), \(position)"
    }

    /// How many elements the guide checked, and how many are off: "4 items" /
    /// "4 items, 1 off".
    private func itemsReadout(_ check: AlignmentCheck) -> String {
        let count = MeasureSpecList.countPhrase(check.items.count)
        guard let verdict = check.verdict, !verdict.isAligned else { return count }
        return "\(count), 1 off"
    }

    /// A document coordinate in the measure's unit, "x, y".
    private func point(_ p: CGPoint, in frame: CGRect, scale: CGFloat) -> String {
        guard let c = content else { return "" }
        let x = c.displayValue(frame.minX + p.x, pixelScale: scale)
        let y = c.displayValue(frame.minY + p.y, pixelScale: scale)
        return "\(Int(x.rounded())), \(Int(y.rounded()))"
    }

    /// One read-only line of the grid: caption left, value right, selectable so
    /// a number can be copied straight out of the inspector.
    @ViewBuilder private func readoutRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(.caption)
                .monospacedDigit()
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    /// The mock's Export section (§7): the two existing app-wide actions as
    /// convenience buttons. The caliper is baked into every export by
    /// construction, so these need nothing measure-specific.
    @ViewBuilder private var exportSection: some View {
        Divider().opacity(0.4)
        field("Export") {
            HStack(spacing: 8) {
                Button("Copy Image") { editorState.copyCompositeToClipboard() }
                    .help("Copies the flattened image, measurements included")
                Button("Export PNG") { editorState.exportComposite(format: .png, scale: 1) }
                    .help("Saves the flattened image as a PNG, measurements included")
            }
            .controlSize(.small)
        }
    }

    /// A compact labeled control matching the Effects panel: a small secondary
    /// caption above the control, full width.
    @ViewBuilder private func field<Content: View>(_ label: String,
                                                   @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    /// One color row: caption on the left, swatch next to it, so the three
    /// swatches line up in a column.
    @ViewBuilder private func swatchRow(_ label: String, color: Color,
                                        supportsOpacity: Bool = false,
                                        set: @escaping (Color) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            ColorPicker(label, selection: Binding(get: { color }, set: set),
                        supportsOpacity: supportsOpacity)
                .labelsHidden().controlSize(.small)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Canvas inspector (the Canvas pseudo-layer)

struct CanvasInspector: View {
    @Environment(EditorState.self) private var editorState
    @State private var width: Double = 0
    @State private var height: Double = 0

    private var canvasSize: CGSize { editorState.document?.canvasSize ?? .zero }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                dimensionField("W", $width)
                dimensionField("H", $height)
                Spacer()
                Button("Canvas Size…") { editorState.isCanvasSizeDialogPresented = true }
                    .controlSize(.small)
                    .help("Numeric resize with a content-anchor picker")
            }
            Text("Drag the canvas edges to add or trim space; content stays put on the side you didn't move. Fields grow to the right/bottom.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onAppear { syncFields() }
        .onChange(of: canvasSize) { syncFields() }
    }

    private func syncFields() {
        width = Double(canvasSize.width)
        height = Double(canvasSize.height)
    }

    private func dimensionField(_ label: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, value: value,
                      format: .number.precision(.fractionLength(0)).grouping(.never))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
                .onSubmit {
                    let size = CGSize(width: max(1, width.rounded()), height: max(1, height.rounded()))
                    guard size != canvasSize else { return }
                    editorState.setCanvasSize(to: size, anchor: .topLeft)
                }
        }
    }
}

// MARK: - Collage inspector (16.9)

struct CollageInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer

    private var content: CollageContent? {
        editorState.document?.layer(id: layer.id)?.collage
    }

    var body: some View {
        if let c = content {
            VStack(alignment: .leading, spacing: 8) {
                field("Layout") {
                    Picker("Layout", selection: Binding(
                        get: { c.template },
                        set: { value in editorState.updateCollage(layerID: layer.id) { $0.template = value } })) {
                        ForEach(CollageTemplate.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                }
                field("Photos") {
                    Stepper("\(c.slots.count) slots", value: Binding(
                        get: { c.slots.count },
                        set: { value in editorState.updateCollage(layerID: layer.id) { $0.setSlotCount(value) } }),
                        in: 1...12)
                        .font(.caption).controlSize(.small)
                }
                field("Spacing") {
                    Stepper("\(Int(c.gutter)) px", value: Binding(
                        get: { Int(c.gutter) },
                        set: { value in editorState.updateCollage(layerID: layer.id) { $0.gutter = CGFloat(value) } }),
                        in: 0...200, step: 4)
                        .font(.caption).controlSize(.small)
                }
                HStack {
                    Toggle("Backdrop", isOn: Binding(
                        get: { c.backdropColorHex != nil },
                        set: { on in
                            editorState.updateCollage(layerID: layer.id) {
                                $0.backdropColorHex = on ? "#FFFFFF" : nil
                            }
                        }))
                        .font(.caption).controlSize(.small)
                    Spacer()
                    if let hex = c.backdropColorHex {
                        ColorPicker("Backdrop color", selection: Binding(
                            get: { Color(hex: hex) },
                            set: { color in
                                if let newHex = color.hexString {
                                    editorState.updateCollage(layerID: layer.id) { $0.backdropColorHex = newHex }
                                }
                            }),
                            supportsOpacity: false)
                            .labelsHidden().controlSize(.small)
                    }
                }
                Text("Drop photos from the history or Finder into a cell; drag a photo layer onto a cell to absorb it; drag between cells to swap.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder private func field<Content: View>(_ label: String,
                                                   @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}
