import AppKit
import PhotonzCore
import SwiftUI

/// Contents of the global slide-down history overlay (phase 11.4): a
/// newest-first strip of the capture folder's contents.
///
/// Keyboard-first: on open the first item takes a primary-colored selection
/// outline; ← / → move it, Return opens/edits the focused item, ⌫ trashes it.
/// ⌘← / ⌘→ step the filter (Next, `next-history-filter-keys`).
/// The focused (or hovered) item shows its bottom action buttons; an idle,
/// unfocused item shows a friendly "last taken" string in their place so the
/// row height never jumps. A segmented All / Screenshots / Videos filter shares
/// the top row with Clear All. Liquid Glass surface; the panel chrome/animation
/// is `HistoryOverlayController`.
struct HistoryOverlay: View {
    let coordinator: AppCoordinator

    /// Which filter is picked. Held in an object only the filter bar and the
    /// strips read while drawing, so a switch never runs this view's body:
    /// when it did, the overlay's fresh key handlers reached every tile in
    /// all three strips as a new environment, and each one redrew its words
    /// and told accessibility about itself again (2026-10-03).
    @State private var choice = HistoryFilterChoice()
    /// One strip per filter, each with its own keyboard focus.
    @State private var strips = HistoryStrips()
    @FocusState private var keyboardFocused: Bool

    private var capture: CaptureCenter { coordinator.capture }
    private var allEntries: [CaptureEntry] { capture.store.entries }
    /// The strip in sight's captures and focus, which the keys act on.
    private var entries: [CaptureEntry] { choice.showing.apply(to: allEntries) }
    private var focus: HistoryStripFocus { strips.focus(for: choice.showing) }

    var body: some View {
        VStack(spacing: 8) {
            if !allEntries.isEmpty {
                HistoryFilterBar(choice: choice, coordinator: coordinator)
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
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            let delta = press.key == .leftArrow ? -1 : 1
            // ⌘← / ⌘→ step the filter, the way ⌘ with an arrow goes to the
            // next page of a segmented view in Finder and Safari.
            if press.modifiers.contains(.command), Experiments.shared.historyFilterKeysEnabled {
                return stepFilter(by: delta)
            }
            return moveSelection(by: delta)
        }
        .onKeyPress(.return) { activateSelection() }
        .onKeyPress(.delete) { deleteSelection() }
        .onAppear {
            focus.land(count: entries.count)
            keyboardFocused = true
            #if PHOTONZ_PLAYTEST
            HistoryOverlayProbe.shared.read = { [choice, strips, capture] in
                let entries = choice.showing.apply(to: capture.store.entries)
                let selection = strips.focus(for: choice.showing).selection
                return .init(filter: choice.filter, showing: choice.showing,
                             focused: selection.flatMap { entries.indices.contains($0) ? entries[$0] : nil },
                             count: entries.count)
            }
            #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        if allEntries.isEmpty {
            firstCaptureKeys
        } else {
            // A new filter keeps the keyboard target.
            HistoryStripsArea(choice: choice, strips: strips, coordinator: coordinator,
                              switched: { keyboardFocused = true })
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

    /// One step along the filter, through the same path a click takes, so the
    /// bar shows it within a frame. The last end stays put: no wrap.
    private func stepFilter(by delta: Int) -> KeyPress.Result {
        guard !allEntries.isEmpty else { return .ignored }
        let next = choice.wanted.stepped(by: delta)
        if next != choice.wanted { choice.pick(next) }
        // Held at either end too, so the key never falls through to a menu
        // shortcut of the window behind.
        return .handled
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
        // Trash is recoverable; the folder watcher re-lists and the strip
        // clamps the index so the same slot stays focused on the next item.
        capture.store.remove(entries[selection])
        return .handled
    }
}

/// The filter picked in the history bar, and the one whose strip is in sight.
///
/// A click on the filter is answered over three frames, each well inside one
/// at 60Hz: the click itself, then the filter showing the new pick, then the
/// chip setting off and the new strip in sight. All of it in the click's own
/// frame came to 20 to 35ms (2026-10-03). Only the bar reads `filter` and
/// only the strips read `showing`, so each frame redraws only its own part.
@MainActor @Observable
private final class HistoryFilterChoice {
    private(set) var filter: CaptureFilter = .all
    private(set) var showing: CaptureFilter = .all
    /// The last pick, before its frames have shown it: a second ⌘→ pressed
    /// before the first has landed steps on from here, not from `filter`.
    @ObservationIgnored private(set) var wanted: CaptureFilter = .all
    /// The next step, waiting for its frame. A pick that overtakes it takes
    /// its place.
    @ObservationIgnored private var pending: Task<Void, Never>?

    func pick(_ picked: CaptureFilter) {
        wanted = picked
        pending?.cancel()
        pending = Task { [weak self] in
            await NextRunLoopPass.start()
            guard let self, !Task.isCancelled else { return }
            self.filter = picked
            await NextRunLoopPass.start()
            guard !Task.isCancelled, self.showing != picked else { return }
            self.showing = picked
        }
    }
}

/// The top row: the filter, centred, and Clear All at the trailing edge.
private struct HistoryFilterBar: View {
    let choice: HistoryFilterChoice
    let coordinator: AppCoordinator

    var body: some View {
        // The segmented filter is CENTERED in the bar; "Clear All" floats at the
        // trailing edge (a ZStack, so the button's width never shifts the picker
        // off-center the way an HStack + Spacer would).
        ZStack {
            // The one segmented control, tinted glass chip and all: the user
            // asked for every segmented control to look and move the same
            // (2026-09-29), and for the picked chip to be tinted glass
            // (2026-09-30).
            SegmentedControl("Filter captures", selection: choice.filter,
                             options: CaptureFilter.allCases.map { .init($0, $0.title) },
                             form: .natural) { choice.pick($0) }
            .fixedSize()
            .toolTip("Filter the history by capture type",
                     key: Experiments.shared.historyFilterKeysEnabled ? "⌘← ⌘→" : nil, below: true)

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
}

/// The three strips, one over another, with only the picked filter's in
/// sight. A switch changes which one is visible and nothing else: handing ONE
/// strip a different list re-sorted and re-laid out the whole 500 item stack
/// and built a new row of tiles, 40 to 110ms on every click (2026-10-03).
private struct HistoryStripsArea: View {
    let choice: HistoryFilterChoice
    let strips: HistoryStrips
    let coordinator: AppCoordinator
    let switched: () -> Void

    /// The filters whose strip exists. The one in sight always does; the
    /// others are built one at a time once the bar has come down
    /// (`buildTheOthers`), so the first switch to each is as quick as the
    /// tenth.
    @State private var built: Set<CaptureFilter> = [.all]

    var body: some View {
        let showing = choice.showing
        ZStack {
            ForEach(CaptureFilter.allCases, id: \.self) { kind in
                if built.contains(kind) || kind == showing {
                    HistoryStripHost(strip: HistoryStrip(filter: kind, focus: strips.focus(for: kind),
                                                         coordinator: coordinator),
                                     shown: kind == showing)
                }
            }
        }
        .task { await buildTheOthers() }
        // A new filter comes into sight focused on the capture the old one
        // had, when it shows that capture, and otherwise on its newest.
        .onChange(of: showing) { left, picked in
            built.insert(picked)
            switched()
            let entries = coordinator.capture.store.entries
            let shown = picked.apply(to: entries)
            if Experiments.shared.historyFilterKeysEnabled {
                let at = HistorySelection.carry(strips.focus(for: left).selection,
                                                from: left.apply(to: entries), to: shown)
                strips.focus(for: picked).land(count: shown.count, at: at ?? 0)
            } else {
                strips.focus(for: picked).land(count: shown.count)
            }
            strips.switched(from: left, to: picked)
        }
    }

    /// Builds the strips the bar is not showing yet, one per pass, after the
    /// bar has finished coming down, so neither the slide nor the first click
    /// on Screenshots or Videos pays for building a row of tiles.
    private func buildTheOthers() async {
        for other in CaptureFilter.allCases {
            // Apart, so each strip's row of tiles is a frame of its own: the
            // two together were one 65ms frame (2026-10-03).
            try? await Task.sleep(for: .milliseconds(300))
            await NextRunLoopPass.start()
            guard !Task.isCancelled else { return }
            if !built.contains(other) { built.insert(other) }
        }
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
    /// Bumped to put the strip back at its start at once, with no scroll
    /// through what lies between. Read only by the strip's scroller.
    var rewinds = 0
    /// Bumped to bring the focused capture into view at once, with no scroll
    /// through what lies between. Read only by the strip's scroller.
    var jumps = 0
    /// The strip was put out of sight and has not been taken back to its
    /// start yet.
    @ObservationIgnored var awayFromStart = false

    /// The strip comes into sight: focus on its newest capture, and back at
    /// its start if it was not put there while out of sight.
    func land(count: Int) {
        byKeys = false
        let first: Int? = count == 0 ? nil : 0
        if selection != first { selection = first }
        if awayFromStart { rewind() }
    }

    /// The strip comes into sight focused on `index` (the capture the last
    /// filter had focused), jumped straight into view. At its first capture
    /// this is `land(count:)`.
    func land(count: Int, at index: Int) {
        guard count > 0, index > 0, index < count else { return land(count: count) }
        byKeys = false
        awayFromStart = false
        if selection != index { selection = index }
        jumps += 1
    }

    /// Back to the start: the newest capture focused and in view.
    func rewind() {
        awayFromStart = false
        byKeys = false
        if selection != nil, selection != 0 { selection = 0 }
        rewinds += 1
    }
}

/// The three strips' focuses, and the strip just put out of sight going back
/// to its start while nobody is looking, so coming back to it later is only a
/// matter of showing it.
@MainActor
private final class HistoryStrips {
    private let all = HistoryStripFocus()
    private let screenshots = HistoryStripFocus()
    private let videos = HistoryStripFocus()
    private var picked: CaptureFilter = .all
    private var rewinding: [CaptureFilter: Task<Void, Never>] = [:]

    func focus(for filter: CaptureFilter) -> HistoryStripFocus {
        switch filter {
        case .all: all
        case .screenshots: screenshots
        case .videos: videos
        }
    }

    /// `left` goes out of sight as `picked` comes in. Its trip back to the
    /// start waits for the switch, and the chip's slide across the filter,
    /// to be over: it lays out the tiles at the start again, and that is
    /// work for a moment when nothing is moving.
    func switched(from left: CaptureFilter, to picked: CaptureFilter) {
        self.picked = picked
        rewinding[picked]?.cancel()
        rewinding[picked] = nil
        let away = focus(for: left)
        away.awayFromStart = true
        rewinding[left]?.cancel()
        rewinding[left] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            await NextRunLoopPass.start()
            guard let self, !Task.isCancelled, self.picked != left, away.awayFromStart else { return }
            away.rewind()
            self.rewinding[left] = nil
        }
    }
}

/// A strip in an AppKit view of its own, so that putting it out of sight is
/// one flag on that view: drawing, clicks and accessibility all stop at a
/// hidden view without anything inside it being told. Hiding it with SwiftUI
/// modifiers instead (opacity, hit testing, accessibility) handed every tile
/// in the strip a new environment and a new accessibility state on every
/// switch, about 40% of a switch's 20 to 60ms (2026-10-03).
private struct HistoryStripHost: NSViewRepresentable {
    let strip: HistoryStrip
    let shown: Bool

    func makeNSView(context: Context) -> NSHostingView<HistoryStrip> {
        let view = NSHostingView(rootView: strip)
        // It fills whatever room the bar gives it; its content never sizes
        // the bar.
        view.sizingOptions = []
        view.isHidden = !shown
        return view
    }

    /// The strip it was made with reads everything it shows for itself, and
    /// the same three things are handed in every time, so it is never given
    /// again: only shown or not.
    func updateNSView(_ view: NSHostingView<HistoryStrip>, context: Context) {
        if view.isHidden == shown { view.isHidden = !shown }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSHostingView<HistoryStrip>,
                      context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

/// One filter's strip: its captures newest first, laid out lazily. It reads
/// the folder and nothing about which filter is picked, so a switch never
/// rebuilds it.
private struct HistoryStrip: View {
    let filter: CaptureFilter
    let focus: HistoryStripFocus
    let coordinator: AppCoordinator

    var body: some View {
        let shown = filter.apply(to: coordinator.capture.store.entries)
        Group {
            if shown.isEmpty {
                Text(emptyLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                strip(shown)
            }
        }
        // Folder changes (a deletion, a new capture): keep the index valid.
        .onChange(of: shown.count) {
            focus.byKeys = false
            focus.selection = HistorySelection.clamp(focus.selection, count: shown.count)
        }
    }

    /// A count, never a sentence: the filter above already says what kind.
    private var emptyLabel: String {
        switch filter {
        case .all: return "0 captures"
        case .screenshots: return "0 screenshots"
        case .videos: return "0 videos"
        }
    }

    private func strip(_ shown: [CaptureEntry]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    // Keyed by the capture alone, so a capture keeps its cell
                    // (and its picture) when the folder changes around it.
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
            }
            // Keep the focused item on screen as ← / → walk off the visible
            // edge, and go back to the start when told.
            .background {
                HistoryStripScroller(focus: focus, ids: shown.map(\.id), proxy: proxy)
            }
        }
    }
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

/// Scrolls the strip to keep the focused item in view as the arrows move it,
/// and puts it back at its start when the strip is rewound. A view of its own,
/// with nothing to draw, so the focus moving re-runs this and not the strip.
///
/// The scroll starts the frame after the ring moves rather than in the same
/// one: starting it lays out, and builds, the tile coming into view, and that
/// on top of the ring cost the key's own frame up to 18ms (2026-10-02).
private struct HistoryStripScroller: View {
    let focus: HistoryStripFocus
    let ids: [URL]
    let proxy: ScrollViewProxy

    /// The scroll waiting for its frame, dropped when the focus moves again
    /// first. Never read while drawing, so setting it redraws nothing.
    @State private var pending: Task<Void, Never>?

    var body: some View {
        Color.clear
            .onChange(of: focus.selection) {
                pending?.cancel()
                // Only the arrows scroll: a focus that jumped (the strip
                // opening, a switch, a deletion) is already in view.
                guard focus.byKeys, let selection = focus.selection, ids.indices.contains(selection) else {
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
            // At once and without a sweep: scrolling there would pass over,
            // and build, every tile in between.
            .onChange(of: focus.rewinds) {
                pending?.cancel()
                guard let first = ids.first else { return }
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { proxy.scrollTo(first, anchor: .leading) }
            }
            // The same for a switch that keeps a capture further along, and
            // only as far as it takes: a capture already in view stays put.
            .onChange(of: focus.jumps) {
                pending?.cancel()
                guard let selection = focus.selection, ids.indices.contains(selection) else { return }
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { proxy.scrollTo(ids[selection]) }
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

