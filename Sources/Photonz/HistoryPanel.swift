import PhotonzCore
import SwiftUI

/// Top-of-window carousel of recent captures (⌘⇧H). Each thumbnail offers
/// copy-to-clipboard and edit-in-Photonz.
struct HistoryPanel: View {
    @Environment(AppState.self) private var appState

    private var capture: CaptureCenter { appState.capture }

    var body: some View {
        VStack(spacing: 8) {
            if capture.needsScreenRecordingPermission {
                permissionHint
            }
            if capture.store.history.entries.isEmpty {
                Text("No captures yet — press ⌘⇧4 to grab a rectangle or ⌘⇧3 for the full screen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            } else {
                carousel
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(capture.store.history.entries) { entry in
                    CaptureCell(entry: entry)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 132)
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
        .padding(8)
    }
}

private struct CaptureCell: View {
    @Environment(AppState.self) private var appState
    let entry: CaptureEntry

    var body: some View {
        VStack(spacing: 6) {
            thumbnail
            HStack(spacing: 16) {
                Button {
                    appState.capture.store.copyToPasteboard(entry)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy to Clipboard")
                Button {
                    if let image = appState.capture.store.image(for: entry) {
                        appState.openCapture(image)
                    }
                } label: {
                    Image(systemName: "pencil")
                }
                .help("Edit in Photonz")
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = appState.capture.store.image(for: entry) {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.15)))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: 128, height: 96)
        }
    }
}
