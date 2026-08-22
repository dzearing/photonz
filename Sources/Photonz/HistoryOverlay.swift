import PhotonzCore
import SwiftUI

/// Contents of the global slide-down history overlay (phase 11.4): a
/// newest-first strip of the capture folder's contents.
///
/// Keyboard-first: on open the first item takes a primary-colored selection
/// outline; ← / → move it, Return opens/edits the focused item, ⌫ trashes it.
/// The focused (or hovered) item shows its bottom action buttons; an idle,
/// unfocused item shows a friendly "last taken" string in their place so the
/// row height never jumps. A segmented All / Screenshots / Videos filter shares
/// the top row with Clear All. Liquid Glass surface; the panel chrome/animation
/// is `HistoryOverlayController`.
struct HistoryOverlay: View {
    let coordinator: AppCoordinator

    /// Coordinate space anchored at the overlay's top-left, so each icon can
    /// report its frame for tooltip placement.
    static let coordSpace = "captureHistoryOverlay"

    @State private var filter: CaptureFilter = .all
    /// Index of the focused item within the *filtered* list (nil = nothing / empty).
    @State private var selection: Int?
    @FocusState private var keyboardFocused: Bool

    private var capture: CaptureCenter { coordinator.capture }
    private var allEntries: [CaptureEntry] { capture.store.entries }
    private var entries: [CaptureEntry] { filter.apply(to: allEntries) }

    var body: some View {
        VStack(spacing: 8) {
            if !allEntries.isEmpty {
                topBar
            }
            if capture.needsScreenRecordingPermission {
                permissionHint
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(8)
        .coordinateSpace(.named(Self.coordSpace))
        // The whole overlay is the keyboard target so ← / → / Return / ⌫ reach
        // the focused item no matter where the pointer is.
        .focusable()
        .focusEffectDisabled()
        .focused($keyboardFocused)
        .onKeyPress(.leftArrow) { moveSelection(by: -1) }
        .onKeyPress(.rightArrow) { moveSelection(by: 1) }
        .onKeyPress(.return) { activateSelection() }
        .onKeyPress(.delete) { deleteSelection() }
        .onAppear { resetSelection(); keyboardFocused = true }
        // Filtering changes which items exist: land the focus on the first one
        // and keep the keyboard target.
        .onChange(of: filter) { resetSelection(); keyboardFocused = true }
        // Folder changes (a deletion, a new capture): keep the index valid.
        .onChange(of: entries.count) { selection = HistorySelection.clamp(selection, count: entries.count) }
    }

    @ViewBuilder
    private var content: some View {
        if allEntries.isEmpty {
            emptyMessage("No captures yet. ⌘⇧4 grabs a rectangle, ⌘⇧3 the full screen, ⌘⇧5 records.")
        } else if entries.isEmpty {
            emptyMessage(filterEmptyMessage)
        } else {
            strip
        }
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filterEmptyMessage: String {
        switch filter {
        case .all: return "No captures yet."
        case .screenshots: return "No screenshots yet."
        case .videos: return "No videos yet."
        }
    }

    private var topBar: some View {
        // The segmented filter is CENTERED in the bar; "Clear All" floats at the
        // trailing edge (a ZStack, so the button's width never shifts the picker
        // off-center the way an HStack + Spacer would).
        ZStack {
            Picker("Filter captures", selection: $filter) {
                ForEach(CaptureFilter.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Filter the history by capture type")

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
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        HistoryOverlayCell(
                            entry: entry,
                            coordinator: coordinator,
                            focused: index == selection,
                            highlighted: entry.url == coordinator.highlightedCaptureURL)
                        .id(entry.id)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            // Keep the focused item on screen as ← / → walk off the visible edge.
            .onChange(of: selection) {
                guard let selection, entries.indices.contains(selection) else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(entries[selection].id, anchor: .center)
                }
            }
        }
    }

    /// Fixed banner height — the controller reserves EXACTLY this much extra panel
    /// height when the hint is shown (`HistoryOverlayController.permissionHintHeight`),
    /// so the banner never eats into the capture strip and clips the thumbnails.
    static let permissionHintHeight: CGFloat = 32

    private var permissionHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield")
            Text("Photonz needs Screen Recording access to take screenshots.")
            Button("Open Setup…") {
                coordinator.hideHistory()
                coordinator.showWelcome()
            }
        }
        .font(.callout)
        .padding(.horizontal, 6)
        .frame(height: Self.permissionHintHeight)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Keyboard selection

    private func resetSelection() {
        selection = entries.isEmpty ? nil : 0
    }

    @discardableResult
    private func moveSelection(by delta: Int) -> KeyPress.Result {
        guard !entries.isEmpty else { return .ignored }
        selection = HistorySelection.move(selection, by: delta, count: entries.count)
        return .handled
    }

    private func activateSelection() -> KeyPress.Result {
        guard let selection, entries.indices.contains(selection) else { return .ignored }
        let entry = entries[selection]
        if entry.kind == .video {
            coordinator.openRecording(entry.url)
            coordinator.hideHistory()
        } else {
            coordinator.editCapture(entry.url)
        }
        return .handled
    }

    private func deleteSelection() -> KeyPress.Result {
        guard let selection, entries.indices.contains(selection) else { return .ignored }
        // Trash is recoverable; the folder watcher re-lists and `onChange` clamps
        // the index so the same slot stays focused on the next item.
        capture.store.remove(entries[selection])
        return .handled
    }
}

private struct HistoryOverlayCell: View {
    let entry: CaptureEntry
    let coordinator: AppCoordinator
    /// Keyboard-focused (selected) tile: accent outline + action buttons shown.
    /// Selection is a KEYBOARD concept (← / → / Return / ⌫) and is deliberately
    /// independent of hover — hovering a tile reveals its actions but does NOT
    /// move the selection outline.
    let focused: Bool
    /// The just-captured entry, accented so the newest capture stands out.
    let highlighted: Bool

    @State private var hovered = false

    private var store: CaptureStore { coordinator.capture.store }

    /// Buttons appear when the tile is focused or hovered; otherwise the idle
    /// "last taken" caption fills the same slot.
    private var showsActions: Bool { focused || hovered }

    var body: some View {
        VStack(spacing: 6) {
            CaptureThumbnailView(entry: entry, store: store, fixedHeight: 100, minWidth: 96,
                                 onActivate: entry.kind == .video ? {
                                     coordinator.openRecording(entry.url)
                                     coordinator.hideHistory()
                                 } : nil,
                                 // Double-click a screenshot to edit it (videos
                                 // already open their editor on a single click).
                                 onDoubleClick: entry.kind == .video ? nil : {
                                     coordinator.editCapture(entry.url)
                                 })
                .overlay {
                    if focused || highlighted {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                    }
                }
                .shadow(color: (focused || highlighted) ? Color.accentColor.opacity(0.55) : .clear,
                        radius: (focused || highlighted) ? 8 : 0)
                .animation(.easeOut(duration: 0.2), value: focused)
                .animation(.easeOut(duration: 0.25), value: highlighted)

            // Focused/hovered → actions; idle → the friendly "last taken" caption.
            // Both live in a fixed-height slot so the row never reflows.
            bottomSlot
                .frame(height: 28)
                .frame(maxWidth: .infinity)
        }
        // The whole tile rectangle is the hover target — important for very
        // skinny images whose thumbnail is only a few px wide.
        .contentShape(Rectangle())
        // Hover only reveals this tile's actions (via `hovered`) — it must NOT
        // move the keyboard selection outline (that's ← / → only).
        .onHover { hovering in
            hovered = hovering
            if !hovering { coordinator.hideCaptureTooltip() }
        }
    }

    @ViewBuilder
    private var bottomSlot: some View {
        ZStack {
            // Actions reveal on focus/hover; their tooltips float on a separate
            // window (TooltipController) so they escape the overlay without
            // reserving space.
            actions
                .opacity(showsActions ? 1 : 0)
                .allowsHitTesting(showsActions)

            Text(RelativeTime.string(from: entry.createdAt, to: .now))
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(showsActions ? 0 : 1)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.12), value: showsActions)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            if entry.kind == .video {
                // Recordings copy as the video file (the stored one, trim and
                // all) or as an animated GIF.
                Menu {
                    Button("Copy Video") {
                        coordinator.copyRecording(entry, as: .mp4)
                        coordinator.hideHistory()
                    }
                    Button("Copy GIF") {
                        coordinator.copyRecording(entry, as: .gif)
                        coordinator.hideHistory()
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .menuIndicator(.hidden)
                .frame(width: 22)
                .historyTooltip("Copy", coordinator: coordinator)
                iconButton("Play", "play.fill") {
                    coordinator.openRecording(entry.url)
                    coordinator.hideHistory()
                }
                // "Show in Finder", not "Export": a recording in history IS a
                // file in a normal folder, so pointing at it is the useful
                // answer. Converting to another format lives in the editor's
                // Export menu, where a format choice belongs.
                iconButton("Show in Finder", "folder") {
                    coordinator.revealInFinder(entry.url)
                    coordinator.hideHistory()
                }
            } else {
                iconButton("Copy", "doc.on.doc") {
                    store.copyToPasteboard(entry)
                    coordinator.hideHistory()
                }
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
