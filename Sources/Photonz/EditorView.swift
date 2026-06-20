import AppKit
import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @Environment(EditorState.self) private var editorState
    /// Capture/history live on the resident agent now; the in-editor history
    /// panel (phase-9 carousel) reads it until phase 11.4 replaces it with the
    /// global slide-down overlay.
    @Environment(AppCoordinator.self) private var coordinator
    @State private var isStylePopoverPresented = false
    /// Slider drafts so a drag doesn't snap back to the committed value mid-drag.
    @State private var strokeWidthDraft: CGFloat?
    @State private var arrowheadScaleDraft: CGFloat?
    /// Docked inspector width, set by the 1px left resize handle; persisted.
    @AppStorage("inspector.width") private var panelWidth = 264.0
    /// Anchors the active-tool accent circle so it slides between buttons.
    @Namespace private var toolbarNamespace

    var body: some View {
        @Bindable var editorState = editorState
        HStack(spacing: 0) {
            ZStack {
                canvas
                VStack {
                    Spacer()
                    GlassEffectContainer {
                        toolbar
                    }
                    .padding(.bottom, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Canvas surround adapts to the system appearance (Preview-style):
            // near-black in dark mode, light gray in light mode.
            .background(Color(nsColor: .underPageBackgroundColor))
            // The docked, full-height inspector with its 1px left resize handle.
            if editorState.document != nil, editorState.isLayersPanelVisible {
                InspectorResizeHandle(width: $panelWidth)
                InspectorPanel()
                    .frame(width: panelWidth)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.spring(duration: 0.3), value: editorState.isLayersPanelVisible)
        // Fill the window even in the empty state — the HStack otherwise hugs
        // the toolbar's width and the background paints as a visible column
        // against the window's own background.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(isPresented: $editorState.isImporterPresented,
                      allowedContentTypes: [.image, EditorState.photonzType]) { result in
            if case .success(let url) = result {
                let scoped = url.startAccessingSecurityScopedResource()
                editorState.openImage(at: url)
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
        }
        // Drop an image (history overlay thumbnail, Finder file, …): into an
        // open document it becomes a new layer; otherwise it opens as a document.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            editorState.addImageLayerOrOpen(at: url)
            return true
        }
        // Finder double-click / `open` with a document (image or .photonz).
        .onOpenURL { editorState.openImage(at: $0) }
        .sheet(isPresented: $editorState.isResizeDialogPresented) {
            if let document = editorState.document {
                ResizeDialog(originalSize: document.canvasSize)
            }
        }
        .sheet(isPresented: $editorState.isCanvasSizeDialogPresented) {
            if let document = editorState.document {
                CanvasSizeDialog(originalSize: document.canvasSize)
            }
        }
        .sheet(isPresented: $editorState.isExportDialogPresented) {
            ExportDialog()
        }
    }

    @ViewBuilder
    private var canvas: some View {
        if editorState.document != nil {
            CanvasView(image: editorState.renderedImage,
                       viewport: editorState.viewport,
                       document: editorState.document,
                       selection: editorState.selection,
                       cropRect: editorState.cropRect,
                       cropAspect: editorState.cropAspect,
                       cropBounds: editorState.cropBounds,
                       selectedLayerID: editorState.selectedLayerID,
                       selectedLayerFrame: editorState.selectedLayerFrame,
                       dragPreview: editorState.dragPreview,
                       tool: editorState.activeTool,
                       annotationContent: editorState.activeAnnotationContent,
                       textContent: editorState.activeTextContent,
                       onViewSizeChange: { editorState.canvasViewSizeChanged($0) },
                       onViewportChange: { editorState.setViewport($0) },
                       onSelectionChange: { editorState.setSelection($0) },
                       onCropRectChange: { editorState.setCropRect($0) },
                       onCropCommit: { editorState.commitCrop() },
                       onSelectLayer: { editorState.selectLayer($0) },
                       onDragBegin: { editorState.beginLayerDrag(id: $0) },
                       onFramePreview: { editorState.previewLayerFrame(id: $0, frame: $1) },
                       onFrameCommit: { editorState.commitLayerFrame(id: $0, frame: $1) },
                       onTransformPreview: { editorState.previewLayerTransform(id: $0, transform: $1) },
                       onTransformCommit: { editorState.commitLayerTransform(id: $0, transform: $1) },
                       onAnnotationCommit: { editorState.addAnnotation(from: $0, to: $1) },
                       onAnnotationEndpointsCommit: { editorState.commitAnnotationEndpoints(id: $0, start: $1, end: $2) },
                       onZoomCalloutCommit: { editorState.addZoomCallout(from: $0, to: $1) },
                       onToolChange: { editorState.setTool($0) },
                       onTextEditBegin: { editorState.beginTextEdit(layerID: $0) },
                       onTextCommit: { editorState.commitTextEdit(layerID: $0, origin: $1, string: $2, maxWidth: $3) },
                       onTextCancel: { editorState.cancelTextEdit() },
                       onDeleteLayer: { editorState.deleteLayer(id: $0) },
                       onDropImageURL: { editorState.addImageLayerOrOpen(at: $0) })
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Drop a photo or screenshot here")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            GlassEffectContainer {
                VStack(alignment: .leading, spacing: 2) {
                    onboardingRow("folder", "Open a file", "⌘O") {
                        editorState.isImporterPresented = true
                    }
                    onboardingRow("rectangle.dashed", "Capture a rectangle", "⇧⌘4") {
                        coordinator.capture.beginRectCapture()
                    }
                    onboardingRow("doc.on.clipboard", "Paste an image", "⌘V") {
                        editorState.paste()
                    }
                }
                .padding(8)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
        }
    }

    /// One actionable hint in the onboarding card: icon, label, shortcut.
    private func onboardingRow(_ symbol: String, _ title: String, _ shortcut: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                Text(title)
                    .font(.callout)
                Spacer(minLength: 24)
                Text(shortcut)
                    .font(.callout.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 260)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderless)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            toolButton(.select, "cursorarrow", "Select", "v")
            toolButton(.arrow, "arrow.up.right", "Arrow", "a")
            toolButton(.line, "line.diagonal", "Line", "l")
            toolButton(.rectangle, "rectangle", "Rectangle", "r")
            toolButton(.ellipse, "circle", "Ellipse", "o")
            toolButton(.highlight, "highlighter", "Highlight", "h")
            toolButton(.text, "character.cursor.ibeam", "Text", "t")
            if editorState.activeTool.createsAnnotationByDrag || editorState.activeTool == .text
                || editorState.selectedAnnotationLayer != nil
                || editorState.selectedZoomCalloutLayer != nil {
                styleButton
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
            Divider().frame(height: 20)
            toolButton(.crop, "crop", "Crop", "c")
            if editorState.activeTool == .crop {
                cropOptions
                    .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
            }
            Button {
                editorState.isResizeDialogPresented = true
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left.rectangle")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .disabled(editorState.document == nil)
            .help("Resize Image (⌥⌘I)")
            toolButton(.zoomCallout, "plus.magnifyingglass", "Zoom Callout", "z")
            Divider().frame(height: 20)
            Button {
                editorState.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom Out")
            Text(Double(editorState.zoom).formatted(.percent.precision(.fractionLength(0))))
                .font(.callout.monospacedDigit())
                .frame(width: 48)
            Button {
                editorState.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom In")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        // One spring drives every toolbar transition: the accent circle
        // sliding between tools, conditional segments, and the capsule resize.
        .animation(.spring(duration: 0.3), value: editorState.activeTool)
        // NO toolbar animation on selectedLayerID (10.7). Selecting an
        // annotation/callout shows the style swatch, which resizes this glass
        // capsule; animating that reflow re-renders the glass every frame for
        // the spring's duration — ~350ms of pegged CPU per selection that
        // crosses an annotation boundary, on top of the inspector's own cost.
        // Making the swatch appear instantly on selection drops it to ~25ms.
        // (The accent circle still slides on TOOL change via `value: activeTool`
        // above, and the swatch still animates in when you pick the arrow tool.)
    }

    /// Aspect locks plus commit/cancel, shown while the crop tool is active.
    private var cropOptions: some View {
        HStack(spacing: 6) {
            ForEach(CropAspect.allCases, id: \.self) { aspect in
                let isActive = editorState.cropAspect == aspect
                Button {
                    editorState.setCropAspect(aspect)
                } label: {
                    Text(aspect.label)
                        .font(.caption.weight(.medium))
                        .fixedSize()
                        .foregroundStyle(isActive ? Color.white : Color.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            if isActive {
                                Capsule().fill(Color.accentColor)
                            }
                        }
                }
                .help("Lock aspect to \(aspect.label)")
            }
            Button {
                editorState.commitCrop()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .keyboardShortcut(.return, modifiers: [])
            .help("Apply Crop (⏎)")
            Button {
                editorState.cancelCrop()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .help("Cancel Crop (⎋)")
        }
    }

    /// The annotation the popover is editing when one is selected (select
    /// tool); otherwise the popover sets defaults for the active tool.
    private var selectedAnnotation: AnnotationContent? {
        editorState.selectedAnnotationLayer?.annotation
    }

    /// The color the popover currently represents: the selected annotation's
    /// or callout's, or what the active tool will draw with.
    private var activeToolColorHex: String {
        if let callout = editorState.selectedZoomCalloutLayer {
            return callout.style.borderColorHex
        }
        if let selected = selectedAnnotation {
            return selected.colorHex
        }
        if editorState.activeTool == .text {
            return editorState.textStyles.colorHex
        }
        return editorState.annotationStyles.colorHex(for: editorState.activeTool) ?? "#FF3B30" // non-annotation fallback
    }

    /// Stroke width applies to stroke shapes only — highlight is a fill.
    private var showsStrokeWidthRow: Bool {
        if editorState.selectedZoomCalloutLayer != nil {
            return true
        }
        if let selected = selectedAnnotation {
            return selected.shape != .highlight
        }
        return editorState.activeTool.usesStrokeWidth
    }

    private var editedStrokeWidth: CGFloat {
        editorState.selectedZoomCalloutLayer?.style.borderWidth
            ?? selectedAnnotation?.strokeWidth
            ?? editorState.annotationStyles.strokeWidth(for: editorState.activeTool)
    }

    /// The arrowhead-size row applies to arrows only.
    private var showsArrowheadRow: Bool {
        if editorState.selectedZoomCalloutLayer != nil { return false }
        if let selected = selectedAnnotation { return selected.shape == .arrow }
        return editorState.activeTool == .arrow
    }

    private var editedArrowheadScale: CGFloat {
        selectedAnnotation?.arrowheadScale ?? editorState.annotationStyles.arrowheadScale(for: editorState.activeTool)
    }

    /// Swatch showing the active tool's color; opens the style popover.
    private var styleButton: some View {
        Button {
            isStylePopoverPresented.toggle()
        } label: {
            Circle()
                .fill(Color(hex: activeToolColorHex))
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                .frame(width: 28, height: 28)
        }
        .help(editorState.activeTool == .text ? "Text Style (S)" : "Annotation Style (S)")
        .keyboardShortcut("s", modifiers: [])
        .popover(isPresented: $isStylePopoverPresented, arrowEdge: .top) {
            stylePopover
        }
    }

    private var stylePopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ForEach(AnnotationStyles.swatches, id: \.self) { hex in
                    swatch(hex)
                }
            }
            if editorState.activeTool == .text {
                fontPicker
            } else if showsStrokeWidthRow {
                strokeWidthSlider
            }
            if showsArrowheadRow {
                arrowheadSizeSlider
            }
            if editorState.selectedZoomCalloutLayer != nil {
                calloutInspector
            }
        }
        .padding(16)
        .buttonStyle(.plain)
        // The system popover chrome is already glass on macOS 26. Drawing our
        // own glass rect inside a cleared presentation background left a light
        // halo (the popover bezel) around the inner rect — let the system
        // material carry the surface instead.
    }

    /// Magnification + shape controls for the selected zoom callout. Color and
    /// width reuse the shared swatch/dot rows above.
    private var calloutInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(editorState.selectedCalloutMagnification ?? 2) },
                    set: { editorState.previewCalloutMagnification(CGFloat($0)) }),
                       in: 1.25...6) { editing in
                    if !editing { editorState.commitCalloutMagnification() }
                }
                Text(Double(editorState.selectedCalloutMagnification ?? 2)
                    .formatted(.number.precision(.fractionLength(1))) + "×")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            HStack(spacing: 6) {
                calloutShapeButton(.rectangle, "rectangle", "Rectangular callout")
                calloutShapeButton(.circle, "circle", "Circular callout")
            }
        }
        .frame(width: 220)
    }

    private func calloutShapeButton(_ shape: ZoomCalloutShape, _ symbol: String,
                                    _ help: String) -> some View {
        let isActive = editorState.selectedZoomCalloutLayer?.zoomCallout?.shape == shape
        return Button {
            editorState.setCalloutShape(shape)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .frame(width: 28, height: 24)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 6).fill(Color.accentColor)
                    }
                }
        }
        .help(help)
    }

    /// Font family / size / weight menus for the text tool.
    private var fontPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Font", selection: Binding(
                get: { editorState.textStyles.fontName },
                set: { editorState.setTextFont($0) })) {
                ForEach(TextStyles.fonts, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            HStack(spacing: 10) {
                Picker("Size", selection: Binding(
                    get: { editorState.textStyles.fontSize },
                    set: { editorState.setTextFontSize($0) })) {
                    ForEach(TextStyles.fontSizes, id: \.self) { size in
                        Text("\(Int(size)) pt").tag(size)
                    }
                }
                Picker("Weight", selection: Binding(
                    get: { editorState.textStyles.weight },
                    set: { editorState.setTextWeight($0) })) {
                    ForEach(TextWeight.allCases, id: \.self) { weight in
                        Text(weight.rawValue.capitalized).tag(weight)
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 220)
    }

    private func swatch(_ hex: String) -> some View {
        let isSelected = activeToolColorHex == hex
        return Button {
            if editorState.selectedZoomCalloutLayer != nil {
                editorState.setCalloutBorderColor(hex)
            } else if editorState.activeTool == .text {
                editorState.setTextColor(hex)
            } else {
                editorState.setAnnotationColor(hex)
            }
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                            .padding(-4)
                    }
                }
        }
        .help(hex)
    }

    /// Stroke width slider with a live numeric readout. Drag previews without
    /// recording undo; release commits one step.
    private var strokeWidthSlider: some View {
        let value = strokeWidthDraft ?? editedStrokeWidth
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label("Width", systemImage: "lineweight").labelStyle(.titleOnly)
                Spacer()
                Text("\(Int(value.rounded())) pt").monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            Slider(value: Binding(
                get: { strokeWidthDraft ?? editedStrokeWidth },
                set: { v in
                    strokeWidthDraft = v
                    // Annotations preview live; callouts commit on release only
                    // (no preview path, so live updates would spam undo).
                    if editorState.selectedZoomCalloutLayer == nil {
                        editorState.previewAnnotationRestyle(strokeWidth: v.rounded())
                    }
                }
            ), in: AnnotationStyles.strokeWidthRange, onEditingChanged: { editing in
                if !editing {
                    let final = (strokeWidthDraft ?? editedStrokeWidth).rounded()
                    if editorState.selectedZoomCalloutLayer != nil {
                        editorState.setCalloutBorderWidth(final)
                    } else {
                        editorState.setAnnotationStrokeWidth(final)
                    }
                    strokeWidthDraft = nil
                }
            })
        }
        .frame(width: 220)
    }

    /// Arrowhead size slider (multiplier) with a small/large triangle on each end.
    private var arrowheadSizeSlider: some View {
        let value = arrowheadScaleDraft ?? editedArrowheadScale
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label("Arrowhead", systemImage: "arrowshape.right.fill").labelStyle(.titleOnly)
                Spacer()
                Text("×\(String(format: "%.1f", value))").monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            HStack(spacing: 8) {
                Image(systemName: "arrowtriangle.right.fill").font(.system(size: 8)).foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { arrowheadScaleDraft ?? editedArrowheadScale },
                    set: { v in
                        arrowheadScaleDraft = v
                        editorState.previewAnnotationRestyle(arrowheadScale: v)
                    }
                ), in: AnnotationStyles.arrowheadScaleRange, onEditingChanged: { editing in
                    if !editing {
                        editorState.setAnnotationArrowheadScale(arrowheadScaleDraft ?? editedArrowheadScale)
                        arrowheadScaleDraft = nil
                    }
                })
                Image(systemName: "arrowtriangle.right.fill").font(.system(size: 15)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 220)
    }

    private func toolButton(_ tool: Tool, _ symbol: String, _ help: String,
                            _ key: KeyEquivalent) -> some View {
        let isActive = editorState.activeTool == tool
        let isLocked = isActive && editorState.toolLocked
        return Button {
            editorState.setTool(tool)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background {
                    if isActive {
                        Circle().fill(Color.accentColor)
                            .matchedGeometryEffect(id: "activeTool", in: toolbarNamespace)
                    }
                }
                // Locked (double-clicked) tools get an inner ring so it's clear
                // they'll stay active instead of reverting to select.
                .overlay {
                    if isLocked {
                        Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                            .padding(3)
                    }
                }
        }
        // Double-click keeps the tool active for repeated drawing.
        .simultaneousGesture(TapGesture(count: 2).onEnded { editorState.lockTool(tool) })
        .help("\(help) (\(String(describing: key.character).uppercased())) — double-click to keep active")
        .keyboardShortcut(key, modifiers: [])
    }

    /// Inert buttons for tools that land in later tasks/phases.
    private func placeholderButton(_ symbol: String, _ help: String) -> some View {
        Button {} label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 28, height: 28)
        }
        .disabled(true)
        .help(help)
    }
}

extension Color {
    /// Color from the document model's hex strings, via the tested RGBA parser.
    init(hex: String) {
        let rgba = RGBA(hex: hex) ?? RGBA(r: 1, g: 0, b: 0)
        self.init(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }
}
