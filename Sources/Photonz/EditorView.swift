import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @Environment(AppState.self) private var appState
    @State private var isStylePopoverPresented = false

    var body: some View {
        @Bindable var appState = appState
        ZStack {
            canvas
            VStack {
                if appState.capture.isHistoryVisible {
                    HistoryPanel()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                toolbar
                    .padding(.bottom, 16)
            }
            .animation(.spring(duration: 0.3), value: appState.capture.isHistoryVisible)
        }
        .background(.black.opacity(0.85))
        .fileImporter(isPresented: $appState.isImporterPresented,
                      allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                let scoped = url.startAccessingSecurityScopedResource()
                appState.openImage(at: url)
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            appState.openImage(at: url)
            return true
        }
        .sheet(isPresented: $appState.isResizeDialogPresented) {
            if let document = appState.document {
                ResizeDialog(originalSize: document.canvasSize)
            }
        }
        .sheet(isPresented: $appState.isCanvasSizeDialogPresented) {
            if let document = appState.document {
                CanvasSizeDialog(originalSize: document.canvasSize)
            }
        }
    }

    @ViewBuilder
    private var canvas: some View {
        if appState.document != nil {
            CanvasView(image: appState.renderedImage,
                       viewport: appState.viewport,
                       document: appState.document,
                       selection: appState.selection,
                       cropRect: appState.cropRect,
                       cropAspect: appState.cropAspect,
                       cropBounds: appState.cropBounds,
                       selectedLayerID: appState.selectedLayerID,
                       selectedLayerFrame: appState.selectedLayerFrame,
                       dragPreview: appState.dragPreview,
                       tool: appState.activeTool,
                       annotationContent: appState.activeAnnotationContent,
                       textContent: appState.activeTextContent,
                       onViewSizeChange: { appState.canvasViewSizeChanged($0) },
                       onViewportChange: { appState.setViewport($0) },
                       onSelectionChange: { appState.setSelection($0) },
                       onCropRectChange: { appState.setCropRect($0) },
                       onCropCommit: { appState.commitCrop() },
                       onSelectLayer: { appState.selectLayer($0) },
                       onDragBegin: { appState.beginLayerDrag(id: $0) },
                       onFramePreview: { appState.previewLayerFrame(id: $0, frame: $1) },
                       onFrameCommit: { appState.commitLayerFrame(id: $0, frame: $1) },
                       onTransformPreview: { appState.previewLayerTransform(id: $0, transform: $1) },
                       onTransformCommit: { appState.commitLayerTransform(id: $0, transform: $1) },
                       onAnnotationCommit: { appState.addAnnotation(from: $0, to: $1) },
                       onAnnotationEndpointsCommit: { appState.commitAnnotationEndpoints(id: $0, start: $1, end: $2) },
                       onZoomCalloutCommit: { appState.addZoomCallout(from: $0, to: $1) },
                       onToolChange: { appState.setTool($0) },
                       onTextEditBegin: { appState.beginTextEdit(layerID: $0) },
                       onTextCommit: { appState.commitTextEdit(layerID: $0, origin: $1, string: $2, maxWidth: $3) },
                       onTextCancel: { appState.cancelTextEdit() })
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop a photo or screenshot here")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("or press ⌘O to open a file")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
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
            if appState.activeTool.createsAnnotationByDrag || appState.activeTool == .text
                || appState.selectedAnnotationLayer != nil
                || appState.selectedZoomCalloutLayer != nil {
                styleButton
            }
            Divider().frame(height: 20)
            toolButton(.crop, "crop", "Crop", "c")
            if appState.activeTool == .crop {
                cropOptions
            }
            Button {
                appState.isResizeDialogPresented = true
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left.rectangle")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .disabled(appState.document == nil)
            .help("Resize Image (⌥⌘I)")
            toolButton(.zoomCallout, "plus.magnifyingglass", "Zoom Callout", "z")
            Divider().frame(height: 20)
            Button {
                appState.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom Out")
            Text(Double(appState.zoom).formatted(.percent.precision(.fractionLength(0))))
                .font(.callout.monospacedDigit())
                .frame(width: 48)
            Button {
                appState.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom In")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }

    /// Aspect locks plus commit/cancel, shown while the crop tool is active.
    private var cropOptions: some View {
        HStack(spacing: 6) {
            ForEach(CropAspect.allCases, id: \.self) { aspect in
                let isActive = appState.cropAspect == aspect
                Button {
                    appState.setCropAspect(aspect)
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
                appState.commitCrop()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .keyboardShortcut(.return, modifiers: [])
            .help("Apply Crop (⏎)")
            Button {
                appState.cancelCrop()
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
        appState.selectedAnnotationLayer?.annotation
    }

    /// The color the popover currently represents: the selected annotation's
    /// or callout's, or what the active tool will draw with.
    private var activeToolColorHex: String {
        if let callout = appState.selectedZoomCalloutLayer {
            return callout.style.borderColorHex
        }
        if let selected = selectedAnnotation {
            return selected.colorHex
        }
        if appState.activeTool == .text {
            return appState.textStyles.colorHex
        }
        return appState.annotationStyles.colorHex(for: appState.activeTool) ?? "#FF3B30"
    }

    /// Stroke width applies to stroke shapes only — highlight is a fill.
    private var showsStrokeWidthRow: Bool {
        if appState.selectedZoomCalloutLayer != nil {
            return true
        }
        if let selected = selectedAnnotation {
            return selected.shape != .highlight
        }
        return appState.activeTool.usesStrokeWidth
    }

    private var editedStrokeWidth: CGFloat {
        appState.selectedZoomCalloutLayer?.style.borderWidth
            ?? selectedAnnotation?.strokeWidth
            ?? appState.annotationStyles.strokeWidth
    }

    /// Swatch showing the active tool's color; opens the style popover.
    private var styleButton: some View {
        Button {
            isStylePopoverPresented.toggle()
        } label: {
            Circle()
                .fill(Color(hex: activeToolColorHex))
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .frame(width: 28, height: 28)
        }
        .help(appState.activeTool == .text ? "Text Style (S)" : "Annotation Style (S)")
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
            if appState.activeTool == .text {
                fontPicker
            } else if showsStrokeWidthRow {
                HStack(spacing: 10) {
                    ForEach(AnnotationStyles.strokeWidths, id: \.self) { width in
                        strokeWidthDot(width)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            if appState.selectedZoomCalloutLayer != nil {
                calloutInspector
            }
        }
        .padding(16)
        .buttonStyle(.plain)
        .presentationBackground(.clear)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(8)
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
                    get: { Double(appState.selectedCalloutMagnification ?? 2) },
                    set: { appState.previewCalloutMagnification(CGFloat($0)) }),
                       in: 1.25...6) { editing in
                    if !editing { appState.commitCalloutMagnification() }
                }
                Text(Double(appState.selectedCalloutMagnification ?? 2)
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
        let isActive = appState.selectedZoomCalloutLayer?.zoomCallout?.shape == shape
        return Button {
            appState.setCalloutShape(shape)
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
                get: { appState.textStyles.fontName },
                set: { appState.setTextFont($0) })) {
                ForEach(TextStyles.fonts, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            HStack(spacing: 10) {
                Picker("Size", selection: Binding(
                    get: { appState.textStyles.fontSize },
                    set: { appState.setTextFontSize($0) })) {
                    ForEach(TextStyles.fontSizes, id: \.self) { size in
                        Text("\(Int(size)) pt").tag(size)
                    }
                }
                Picker("Weight", selection: Binding(
                    get: { appState.textStyles.weight },
                    set: { appState.setTextWeight($0) })) {
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
            if appState.selectedZoomCalloutLayer != nil {
                appState.setCalloutBorderColor(hex)
            } else if appState.activeTool == .text {
                appState.setTextColor(hex)
            } else {
                appState.setAnnotationColor(hex)
            }
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                            .padding(-4)
                    }
                }
        }
        .help(hex)
    }

    /// Dot whose diameter tracks the stroke width it selects.
    private func strokeWidthDot(_ width: CGFloat) -> some View {
        let isSelected = editedStrokeWidth == width
        return Button {
            if appState.selectedZoomCalloutLayer != nil {
                appState.setCalloutBorderWidth(width)
            } else {
                appState.setAnnotationStrokeWidth(width)
            }
        } label: {
            Circle()
                .fill(.primary)
                .frame(width: width + 4, height: width + 4)
                .frame(width: 24, height: 24)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
        }
        .help("\(Int(width)) pt")
    }

    private func toolButton(_ tool: Tool, _ symbol: String, _ help: String,
                            _ key: KeyEquivalent) -> some View {
        let isActive = appState.activeTool == tool
        return Button {
            appState.setTool(tool)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background {
                    if isActive {
                        Circle().fill(Color.accentColor)
                    }
                }
        }
        .help("\(help) (\(String(describing: key.character).uppercased()))")
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
