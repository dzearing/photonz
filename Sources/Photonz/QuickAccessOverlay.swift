import PhotonzCore
import SwiftUI

/// Contents of the post-capture Quick Access Overlay (phase 11.7): the just-taken
/// capture's thumbnail plus quick actions — Copy, Save, Edit, Delete — and
/// drag-the-PNG-out. A CleanShot-style HUD: it appears in a corner, gets out of
/// the way on its own, and never steals focus. The panel chrome / slide-in /
/// auto-close live in `QuickAccessController`; this is just the card.
struct QuickAccessOverlay: View {
    let entry: CaptureEntry
    let coordinator: AppCoordinator
    /// Reported to the controller so it can pause the auto-close while hovered.
    let onHoverChange: (Bool) -> Void

    private var store: CaptureStore { coordinator.capture.store }

    var body: some View {
        VStack(spacing: 8) {
            thumbnail
            HStack(spacing: 8) {
                Button {
                    store.copyToPasteboard(entry)
                    coordinator.hideQuickAccess()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy to Clipboard")
                Button {
                    coordinator.saveCaptureToDisk(entry.id)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Save to a File…")
                Button {
                    coordinator.editCapture(entry.id)
                    coordinator.hideQuickAccess()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("Edit in a new window")
                Button {
                    coordinator.pinCapture(entry.id)
                    coordinator.hideQuickAccess()
                } label: {
                    Image(systemName: "pin")
                }
                .help("Pin to Screen")
                Button(role: .destructive) {
                    store.remove(id: entry.id)
                    coordinator.hideQuickAccess()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete")
            }
            .buttonStyle(IconActionButtonStyle())
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding(8)
        .onHover { onHoverChange($0) }
    }

    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if let image = store.image(for: entry) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.15)))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            }
        }
        // Drag the capture's PNG straight out to Finder / another app.
        .onDrag { NSItemProvider(contentsOf: store.fileURL(for: entry)) ?? NSItemProvider() }
    }
}
