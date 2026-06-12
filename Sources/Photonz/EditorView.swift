import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @Environment(AppState.self) private var appState

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
                       onViewSizeChange: { appState.canvasViewSizeChanged($0) },
                       onViewportChange: { appState.setViewport($0) })
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
            toolButton("crop", "Crop")
            toolButton("arrow.up.right", "Arrow")
            toolButton("rectangle", "Rectangle")
            toolButton("character.cursor.ibeam", "Text")
            toolButton("plus.magnifyingglass", "Zoom Callout")
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

    private func toolButton(_ symbol: String, _ help: String) -> some View {
        Button {
            // Tools land in Phases 2–5; the shell ships first.
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
        }
        .help(help)
    }
}
