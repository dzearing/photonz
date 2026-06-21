import PhotonzCore
import SwiftUI

/// Contents of the global slide-down history overlay (phase 11.4): a
/// newest-first strip of recent captures, each with Copy / Edit / Delete and
/// drag-to-export. Replaces the phase-9 in-editor `HistoryPanel` carousel.
/// Liquid Glass surface; the panel chrome/animation is `HistoryOverlayController`.
struct HistoryOverlay: View {
    let coordinator: AppCoordinator

    private var capture: CaptureCenter { coordinator.capture }

    var body: some View {
        VStack(spacing: 8) {
            if capture.needsScreenRecordingPermission {
                permissionHint
            }
            if capture.store.history.entries.isEmpty {
                Text("No captures yet — press ⌘⇧4 to grab a rectangle or ⌘⇧3 for the full screen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            } else {
                strip
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(8)
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(capture.store.history.entries) { entry in
                    HistoryOverlayCell(entry: entry, coordinator: coordinator)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var permissionHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield")
            Text("Photonz needs Screen Recording access to take screenshots.")
            Button("Open Privacy Settings") {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
                if let url { NSWorkspace.shared.open(url) }
            }
        }
        .font(.callout)
        .padding(6)
    }
}

private struct HistoryOverlayCell: View {
    let entry: CaptureEntry
    let coordinator: AppCoordinator

    private var store: CaptureStore { coordinator.capture.store }

    var body: some View {
        VStack(spacing: 6) {
            thumbnail
            HStack(spacing: 6) {
                Button {
                    store.copyToPasteboard(entry)
                    coordinator.hideHistory()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy to Clipboard")
                Button {
                    coordinator.editCapture(entry.id)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("Edit in a new window")
                Button {
                    coordinator.pinCapture(entry.id)
                    coordinator.hideHistory()
                } label: {
                    Image(systemName: "pin")
                }
                .help("Pin to Screen")
                Button(role: .destructive) {
                    store.remove(id: entry.id)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete")
            }
            .buttonStyle(IconActionButtonStyle())
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if let image = store.image(for: entry) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.15)))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 140, height: 104)
            }
        }
        // Drag the capture's PNG straight out to Finder / another app.
        .onDrag { NSItemProvider(contentsOf: store.fileURL(for: entry)) ?? NSItemProvider() }
    }
}
