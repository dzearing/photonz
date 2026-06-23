import PhotonzCore
import SwiftUI

/// Contents of the global slide-down history overlay (phase 11.4): a
/// newest-first strip of the capture folder's contents. Per-item actions stay
/// hidden until the item is hovered (they're noisy otherwise) and each shows a
/// small tooltip *below* the row so it never covers the thumbnail. Liquid Glass
/// surface; the panel chrome/animation is `HistoryOverlayController`.
struct HistoryOverlay: View {
    let coordinator: AppCoordinator

    /// Coordinate space anchored at the overlay's top-left, so each icon can
    /// report its frame for tooltip placement.
    static let coordSpace = "captureHistoryOverlay"

    private var capture: CaptureCenter { coordinator.capture }

    var body: some View {
        VStack(spacing: 6) {
            if !capture.store.entries.isEmpty {
                topBar
            }
            if capture.needsScreenRecordingPermission {
                permissionHint
            }
            if capture.store.entries.isEmpty {
                Text("No captures yet — ⌘⇧4 grabs a rectangle, ⌘⇧3 the full screen, ⌘⇧5 records.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                strip
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(8)
        .coordinateSpace(.named(Self.coordSpace))
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button(role: .destructive) {
                coordinator.clearHistory()
            } label: {
                Label("Clear All", systemImage: "trash")
            }
            .buttonStyle(PillActionButtonStyle())
            .help("Move all captures to the Trash")
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(capture.store.entries) { entry in
                    HistoryOverlayCell(entry: entry, coordinator: coordinator,
                                       highlighted: entry.url == coordinator.highlightedCaptureURL)
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
    /// The just-captured entry, accented so the newest capture stands out.
    let highlighted: Bool

    @State private var hovered = false

    private var store: CaptureStore { coordinator.capture.store }

    var body: some View {
        VStack(spacing: 6) {
            CaptureThumbnailView(entry: entry, store: store, fixedHeight: 100, minWidth: 96,
                                 onActivate: entry.kind == .video ? {
                                     coordinator.openRecording(entry.url)
                                     coordinator.hideHistory()
                                 } : nil)
                .overlay {
                    if highlighted {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                    }
                }
                .shadow(color: highlighted ? Color.accentColor.opacity(0.55) : .clear,
                        radius: highlighted ? 8 : 0)
                .animation(.easeOut(duration: 0.25), value: highlighted)

            // Actions reveal on hover; their tooltips float on a separate window
            // (TooltipController) so they escape the overlay without reserving space.
            actions
                .opacity(hovered ? 1 : 0)
                .allowsHitTesting(hovered)
                .animation(.easeOut(duration: 0.12), value: hovered)
        }
        // The whole tile rectangle is the hover target — important for very
        // skinny images whose thumbnail is only a few px wide.
        .contentShape(Rectangle())
        .onHover { hovering in
            hovered = hovering
            if !hovering { coordinator.hideCaptureTooltip() }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            iconButton("Copy", "doc.on.doc") {
                store.copyToPasteboard(entry)
                coordinator.hideHistory()
            }
            if entry.kind == .video {
                iconButton("Play", "play.fill") {
                    coordinator.openRecording(entry.url)
                    coordinator.hideHistory()
                }
                Menu {
                    Button("Export GIF…") { coordinator.saveRecording(entry.url, as: .gif) }
                    Button("Export HEIC…") { coordinator.saveRecording(entry.url, as: .heic) }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .menuIndicator(.hidden)
                .frame(width: 22)
                .historyTooltip("Export", coordinator: coordinator)
            } else {
                iconButton("Edit", "square.and.pencil") {
                    coordinator.editCapture(entry.url)
                }
                iconButton("Pin", "pin") {
                    coordinator.pinCapture(entry.url)
                    coordinator.hideHistory()
                }
            }
            iconButton("Delete", "trash", role: .destructive) {
                store.remove(entry)
            }
        }
        .buttonStyle(IconActionButtonStyle())
    }

    private func iconButton(_ title: String, _ systemImage: String,
                            role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
        }
        .historyTooltip(title, coordinator: coordinator)
    }
}

/// Captures a control's frame in the overlay's coordinate space and shows the
/// floating tooltip anchored just below it on hover.
private struct HistoryTooltipModifier: ViewModifier {
    let title: String
    let coordinator: AppCoordinator
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: HistoryIconFrameKey.self,
                                           value: proxy.frame(in: .named(HistoryOverlay.coordSpace)))
                }
            )
            .onPreferenceChange(HistoryIconFrameKey.self) { frame = $0 }
            .onHover { hovering in
                if hovering { coordinator.showCaptureTooltip(title, iconFrameInOverlay: frame) }
                else { coordinator.hideCaptureTooltip() }
            }
    }
}

private struct HistoryIconFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private extension View {
    func historyTooltip(_ title: String, coordinator: AppCoordinator) -> some View {
        modifier(HistoryTooltipModifier(title: title, coordinator: coordinator))
    }
}
