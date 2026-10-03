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

    @State private var filter: CaptureFilter = .all
    /// Which item the arrows have focused. Kept out of this view's own state
    /// on purpose: only the tiles and the strip's scroller read it, so an
    /// arrow step redraws the two tiles it moves between and nothing else.
    /// When it lived here, every step rebuilt the whole overlay, filter bar
    /// and all, for about 30ms of main thread work (2026-10-02).
    @State private var focus = HistoryStripFocus()
    @FocusState private var keyboardFocused: Bool
    /// True for the one update a filter switch makes, while the focus lands on
    /// the first item and the strip has already jumped there.
    @State private var jumpingToStart = false

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
        .onChange(of: filter) {
            // The strip jumps to the start itself; the focus landing on the
            // first item must not animate a scroll there on top of that.
            jumpingToStart = true
            resetSelection()
            keyboardFocused = true
            DispatchQueue.main.async { jumpingToStart = false }
        }
        // Folder changes (a deletion, a new capture): keep the index valid.
        .onChange(of: entries.count) {
            focus.byKeys = false
            focus.selection = HistorySelection.clamp(focus.selection, count: entries.count)
        }
    }

    @ViewBuilder
    private var content: some View {
        if allEntries.isEmpty {
            firstCaptureKeys
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

    /// A count, never a sentence: the filter above already says what kind.
    private var filterEmptyMessage: String {
        switch filter {
        case .all: return "0 captures"
        case .screenshots: return "0 screenshots"
        case .videos: return "0 videos"
        }
    }

    /// Nothing captured yet: the three keys that make one, as a menu shows
    /// them, rather than a sentence about it.
    private var firstCaptureKeys: some View {
        HStack(spacing: 20) {
            captureKey("⇧⌘4", "Rectangle")
            captureKey("⇧⌘3", "Full Screen")
            captureKey("⇧⌘5", "Record")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func captureKey(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(keys).foregroundStyle(.tertiary)
            Text(label)
        }
    }

    private var topBar: some View {
        // The segmented filter is CENTERED in the bar; "Clear All" floats at the
        // trailing edge (a ZStack, so the button's width never shifts the picker
        // off-center the way an HStack + Spacer would).
        ZStack {
            // The one segmented control, tinted glass chip and all: the user
            // asked for every segmented control to look and move the same
            // (2026-09-29), and for the picked chip to be tinted glass
            // (2026-09-30).
            SegmentedControl("Filter captures", selection: $filter,
                             options: CaptureFilter.allCases.map { .init($0, $0.title) },
                             form: .natural)
            .fixedSize()
            .toolTip("Filter the history by capture type", below: true)

            HStack {
                Spacer()
                Button(role: .destructive) {
                    coordinator.clearHistory()
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .buttonStyle(PillActionButtonStyle())
                .toolTip("Move all captures to the Trash", below: true)
            }
        }
    }

    private var strip: some View {
        let shown = entries
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    // Keyed by the capture alone, so a capture in both the old
                    // and the new filter keeps its cell (and its picture) across
                    // a switch rather than being built again.
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                        HistoryOverlayFocusedCell(
                            index: index,
                            focus: focus,
                            entry: entry,
                            coordinator: coordinator,
                            highlighted: entry.url == coordinator.highlightedCaptureURL)
                        .id(entry.id)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                // A filter switch swaps the whole set in one frame: no tile
                // fades or slides, whatever transaction the pick came in.
                .transaction(value: filter) { $0.animation = nil }
            }
            // A new filter starts at its newest capture, at once. Scrolling
            // there would sweep past, and build, every tile in between.
            .onChange(of: filter) {
                guard let first = entries.first else { return }
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { proxy.scrollTo(first.id, anchor: .leading) }
            }
            // Keep the focused item on screen as ← / → walk off the visible edge.
            .background {
                HistoryStripScroller(focus: focus, ids: shown.map(\.id),
                                     jumpingToStart: jumpingToStart, proxy: proxy)
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
            Text("Screen Recording is off")
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
        focus.byKeys = false
        focus.selection = entries.isEmpty ? nil : 0
    }

    @discardableResult
    private func moveSelection(by delta: Int) -> KeyPress.Result {
        let shown = entries
        guard !shown.isEmpty else { return .ignored }
        focus.byKeys = true
        focus.selection = HistorySelection.move(focus.selection, by: delta, count: shown.count)
        return .handled
    }

    private func activateSelection() -> KeyPress.Result {
        let entries = entries
        guard let selection = focus.selection, entries.indices.contains(selection) else { return .ignored }
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
        let entries = entries
        guard let selection = focus.selection, entries.indices.contains(selection) else { return .ignored }
        // Trash is recoverable; the folder watcher re-lists and `onChange` clamps
        // the index so the same slot stays focused on the next item.
        capture.store.remove(entries[selection])
        return .handled
    }
}

/// The strip's keyboard focus, as an object the overlay holds but never reads
/// while drawing, so moving it redraws only what reads it.
@MainActor @Observable
private final class HistoryStripFocus {
    /// Index of the focused item within the *filtered* list (nil = nothing / empty).
    var selection: Int?
    /// Whether the arrows put it there, rather than the strip opening, a
    /// filter switch or a deletion. Only read when the focus has moved, never
    /// while drawing.
    @ObservationIgnored var byKeys = false
}

/// One tile and the question "is it the focused one", asked here rather than
/// in the strip: an arrow step re-asks it in every visible tile, which is
/// cheap, and the tile itself is rebuilt only when the answer changes.
private struct HistoryOverlayFocusedCell: View {
    let index: Int
    let focus: HistoryStripFocus
    let entry: CaptureEntry
    let coordinator: AppCoordinator
    let highlighted: Bool

    var body: some View {
        HistoryOverlayCell(entry: entry, coordinator: coordinator, focus: focus,
                           focused: focus.selection == index, highlighted: highlighted)
    }
}

/// Scrolls the strip to keep the focused item in view. A view of its own, with
/// nothing to draw, so the focus moving re-runs this and not the strip.
///
/// The scroll starts the frame after the ring moves rather than in the same
/// one: starting it lays out, and builds, the tile coming into view, and that
/// on top of the ring cost the key's own frame up to 18ms (2026-10-02).
private struct HistoryStripScroller: View {
    let focus: HistoryStripFocus
    let ids: [URL]
    /// True for the one update a filter switch makes: the strip has already
    /// jumped to the start, and must not animate a scroll there on top of that.
    let jumpingToStart: Bool
    let proxy: ScrollViewProxy

    /// The scroll waiting for its frame, dropped when the focus moves again
    /// first. Never read while drawing, so setting it redraws nothing.
    @State private var pending: Task<Void, Never>?

    var body: some View {
        Color.clear
            .onChange(of: focus.selection) {
                pending?.cancel()
                guard !jumpingToStart, let selection = focus.selection, ids.indices.contains(selection) else {
                    return
                }
                let target = ids[selection]
                pending = Task { @MainActor in
                    await NextRunLoopPass.start()
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
    }
}

private struct HistoryOverlayCell: View {
    let entry: CaptureEntry
    let coordinator: AppCoordinator
    let focus: HistoryStripFocus
    /// Keyboard-focused (selected) tile: accent outline + action buttons shown.
    /// Selection is a KEYBOARD concept (← / → / Return / ⌫) and is deliberately
    /// independent of hover — hovering a tile reveals its actions but does NOT
    /// move the selection outline.
    let focused: Bool
    /// The just-captured entry, accented so the newest capture stands out.
    let highlighted: Bool

    @State private var hovered = false
    /// Whether the action buttons exist at all. They are built the first time
    /// the tile shows them, and late when the arrows bring the focus, so the
    /// frame an arrow key lands in only moves the ring: building four buttons
    /// and their tooltip anchors in that same frame cost about 8ms of it, and
    /// keeping a hidden set in every tile cost more than that whenever a new
    /// tile scrolled in (2026-10-02).
    @State private var actionsBuilt = false
    /// Putting the buttons up, while it waits its turn. Started only when the
    /// tile comes to show them: a `.task` on every tile cost the first switch
    /// to Videos, which builds fifteen tiles at once, 10ms. Never read while
    /// drawing, so setting it redraws nothing, and nil to start with, so a
    /// tile made again from the same values is the same tile.
    @State private var pendingActions: Task<Void, Never>?

    private var store: CaptureStore { coordinator.capture.store }

    /// Buttons appear when the tile is focused or hovered; otherwise the idle
    /// "last taken" caption fills the same slot.
    private var showsActions: Bool { focused || hovered }

    var body: some View {
        #if PHOTONZ_PLAYTEST
        let _ = ViewBuildMeter.shared.built(.historyTile)
        #endif
        VStack(spacing: 6) {
            CaptureThumbnailView(entry: entry, store: store, fixedHeight: 100, minWidth: 96,
                                 ringed: focused || highlighted,
                                 onActivate: entry.kind == .video ? {
                                     coordinator.openRecording(entry.url)
                                     coordinator.hideHistory()
                                 } : nil,
                                 // Double-click a screenshot to edit it (videos
                                 // already open their editor on a single click).
                                 onDoubleClick: entry.kind == .video ? nil : {
                                     coordinator.editCapture(entry.url)
                                 })
                // The ring itself is drawn on the picture inside the tile (see
                // `ringed`); the glow here follows whatever the tile drew, so a
                // small capture gets a glow its own size rather than a box.
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
        .playtestHover("capture tile") { hovered = $0 }
    }

    @ViewBuilder
    private var bottomSlot: some View {
        ZStack {
            actionsFootprint
            // Actions reveal on focus/hover; their labels float on the app's
            // own tooltip window so they escape the overlay without reserving
            // space here.
            if actionsBuilt {
                actions
                    .opacity(showsActions ? 1 : 0)
                    .allowsHitTesting(showsActions)
                    .transition(.opacity)
            }

            Text(RelativeTime.string(from: entry.createdAt, to: .now))
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(showsActions ? 0 : 1)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.12), value: showsActions)
        // A tile that comes into being focused (the first one as the strip
        // opens) gets its buttons the way any other does.
        .onAppear { if showsActions { matchActions() } }
        .onChange(of: showsActions) { matchActions() }
    }

    /// Builds the buttons the first time this tile shows them. Once built
    /// they stay, hidden when the tile is neither focused nor hovered, for as
    /// long as the strip keeps the tile: taking them down was a frame of work
    /// of its own, and it landed on the next arrow's.
    private func matchActions() {
        pendingActions?.cancel()
        guard showsActions, !actionsBuilt else { return }
        // Focus that jumps here (the strip opening, a filter switch, a
        // deletion) brings the buttons with it in the same update, which is
        // already building the tiles it shows.
        if !hovered, !focus.byKeys {
            actionsBuilt = true
            return
        }
        pendingActions = Task { await buildActions() }
    }

    private func buildActions() async {
        // Under the pointer: the next frame, fading in as they always did.
        // Under the arrows: once the focus has rested, so a run of arrows
        // moves only the ring and the buttons come up on the tile it stops at.
        // Either way in a frame of its own rather than whichever one the timer
        // lands in, which while an arrow is held is the next arrow's.
        if !hovered {
            try? await Task.sleep(for: .milliseconds(250))
        }
        await NextRunLoopPass.start()
        guard !Task.isCancelled, showsActions else { return }
        withAnimation(.easeOut(duration: 0.12)) { actionsBuilt = true }
    }

    /// The room the buttons take, held whether they are built or not, so a
    /// narrow capture's tile is as wide unfocused as focused and the strip
    /// never shifts as the buttons come and go. Mirrors `actions`: the copy
    /// menu's 22pt on a recording, then round buttons of the style's size.
    private var actionsFootprint: some View {
        let round = IconActionButtonStyle().diameter
        return HStack(spacing: 6) {
            if entry.kind == .video { Color.clear.frame(width: 22) }
            ForEach(0..<(entry.kind == .video ? 3 : 4), id: \.self) { _ in
                Color.clear.frame(width: round)
            }
        }
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
                .toolTip("Copy", below: true)
                iconButton("Play", "play.fill") {
                    coordinator.openRecording(entry.url)
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
            }
            // Every capture is a real file in a normal folder, so every tile can
            // point at it. Recordings had an Export menu here instead (Export
            // GIF…/HEIC…, a save panel writing a converted copy elsewhere) —
            // a FORMAT choice, which belongs in the editor's Export menu with
            // the other format choices, not on a tile.
            iconButton("Show in Finder", "folder") {
                coordinator.revealInFinder(entry.url)
                coordinator.hideHistory()
            }
            iconButton("Delete", "trash", role: .destructive) {
                store.remove(entry)
            }
        }
        .buttonStyle(IconActionButtonStyle())
    }

    /// One glyph, and the word for it under the pointer. `below` because this
    /// strip is pinned to the top of the screen and the row of buttons sits
    /// UNDER the capture it acts on: a label above one would cover the very
    /// picture you are pointing at.
    ///
    /// These used to run on a tooltip of the overlay's own, which read the
    /// button's rectangle out of a SwiftUI preference. The preference stopped
    /// arriving, the rectangle stayed empty, and every label was placed in the
    /// corner of the screen instead of under its button, which is what a
    /// person saw as no tooltip at all. There is now ONE tooltip in the app.
    private func iconButton(_ title: String, _ systemImage: String,
                            role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
        }
        .toolTip(title, below: true)
    }
}
