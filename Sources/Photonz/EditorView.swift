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
    }

    @ViewBuilder
    private var canvas: some View {
        if appState.document != nil {
            CanvasView(image: appState.renderedImage,
                       viewport: appState.viewport,
                       document: appState.document,
                       selection: appState.selection,
                       selectedLayerID: appState.selectedLayerID,
                       selectedLayerFrame: appState.selectedLayerFrame,
                       dragPreview: appState.dragPreview,
                       tool: appState.activeTool,
                       annotationContent: appState.activeAnnotationContent,
                       onViewSizeChange: { appState.canvasViewSizeChanged($0) },
                       onViewportChange: { appState.setViewport($0) },
                       onSelectionChange: { appState.setSelection($0) },
                       onSelectLayer: { appState.selectLayer($0) },
                       onDragBegin: { appState.beginLayerDrag(id: $0) },
                       onFramePreview: { appState.previewLayerFrame(id: $0, frame: $1) },
                       onFrameCommit: { appState.commitLayerFrame(id: $0, frame: $1) },
                       onAnnotationCommit: { appState.addAnnotation(from: $0, to: $1) },
                       onToolChange: { appState.setTool($0) })
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
            if appState.activeTool.createsAnnotationByDrag {
                styleButton
            }
            Divider().frame(height: 20)
            placeholderButton("crop", "Crop (phase 4)")
            placeholderButton("character.cursor.ibeam", "Text (3.4)")
            placeholderButton("plus.magnifyingglass", "Zoom Callout (phase 5)")
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

    /// Swatch showing the active tool's color; opens the style popover.
    private var styleButton: some View {
        Button {
            isStylePopoverPresented.toggle()
        } label: {
            Circle()
                .fill(Color(hex: appState.annotationStyles.colorHex(for: appState.activeTool) ?? "#FF3B30"))
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .frame(width: 28, height: 28)
        }
        .help("Annotation Style (S)")
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
            if appState.activeTool.usesStrokeWidth {
                HStack(spacing: 10) {
                    ForEach(AnnotationStyles.strokeWidths, id: \.self) { width in
                        strokeWidthDot(width)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .buttonStyle(.plain)
        .presentationBackground(.clear)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(8)
    }

    private func swatch(_ hex: String) -> some View {
        let isSelected = appState.annotationStyles.colorHex(for: appState.activeTool) == hex
        return Button {
            appState.setAnnotationColor(hex)
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
        let isSelected = appState.annotationStyles.strokeWidth == width
        return Button {
            appState.setAnnotationStrokeWidth(width)
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
