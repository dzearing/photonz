import PhotonzCore
import SwiftUI

/// **Transitions**: every transition as a tile, to browse, search and drag
/// onto a cut (`video-transitions.html`, `#gEffects`). Premiere's Effects
/// panel with Video Transitions open, in the panel rather than only in the
/// picker that opens at a cut, so there is somewhere to find a transition
/// before any cut is in hand.
///
/// A tile dragged onto a cut on the timeline puts that transition there
/// (`TransitionDrag.swift`). A click puts it on the cut in hand, when there is
/// one, and either way picks the tile for the header's plus menu. A right
/// click has the same two verbs as the plus menu, for that tile.
struct TransitionsGroup: View {
    @Environment(EditorState.self) private var editorState
    @State private var query = ""

    /// The mock's line under the grid, longer than the panel's budget, so it
    /// sits behind the header's question mark in the mock's words.
    static let sectionHelp = "Drag a tile onto a cut, or pick one to apply it to the selected cut. "
        + "Every transition rides the same keyframe and easing engine as the rest of the timeline."

    /// The mock's `.mt` line under each name: what the transition does, in a
    /// few words.
    static func blurb(_ kind: ClipTransitionKind) -> String {
        switch kind {
        case .dissolve: "opacity fade"
        case .dipToBlack: "fade through black"
        case .dipToWhite: "fade through white"
        case .push: "A pushed out"
        case .wipe: "B wiped over"
        case .blurThrough: "blur and blend"
        }
    }

    private var shown: [ClipTransitionKind] {
        let words = query.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return ClipTransitionKind.allCases }
        return ClipTransitionKind.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(words)
                || Self.blurb($0).localizedCaseInsensitiveContains(words)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
            VideoKit.TileGrid(columns: 2, spacing: 8) {
                ForEach(shown, id: \.self) { kind in tile(kind) }
            }
            .animation(.easeOut(duration: 0.15), value: shown)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// The mock's `.libtools .srch`, the same box the Library shelf has.
    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search transitions", text: $query)
                .textFieldStyle(.plain)
                .font(.caption)
                .onSubmit { if let first = shown.first { pick(first) } }
                .nameFieldKeys(canCommit: !shown.isEmpty,
                               commit: { if let first = shown.first { pick(first) } },
                               revert: { query = "" })
                .accessibilityLabel("Search transitions")
                .playtestControl("Search transitions", detail: "Transitions")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .panelHelp("Clear the search")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
    }

    private func tile(_ kind: ClipTransitionKind) -> some View {
        let isDefault = editorState.defaultTransitionKind == kind
        return VideoKit.Tile(name: kind.title, detail: Self.blurb(kind),
                             isSelected: editorState.transitionsGroupKind == kind,
                             emphasis: .cut, thumbnailHeight: 30) {
            VideoKit.AnimatedTransitionThumbnail(style: TransitionPicker.style(kind))
        }
        .overlay(alignment: .topTrailing) {
            if isDefault { TransitionPicker.defaultKeycap(kind, in: "Transitions") }
        }
        .onTapGesture { pick(kind) }
        .onDrag {
            editorState.transitionsGroupPick = kind
            return TransitionDrag.itemProvider(kind)
        } preview: {
            VideoKit.AnimatedTransitionThumbnail(style: TransitionPicker.style(kind))
                .frame(width: 64, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .contextMenu {
            Button("Apply to Every Cut") { editorState.putTransitionOnEveryCut(kind) }
            Button("Set as Default Transition") { editorState.setDefaultTransition(kind) }
                .disabled(isDefault)
        }
        // One name for a walk: a tile it can press and pick up.
        .playtestTarget(kind.title, kind: .tile, detail: "Transitions",
                        payload: { TransitionDrag.itemProvider(kind) })
        .panelHelp(isDefault ? "\(kind.title), \u{2318}T" : kind.title)
        .accessibilityAddTraits(.isButton)
    }

    /// A click: on the cut in hand when there is one, and the plus menu's
    /// subject either way.
    private func pick(_ kind: ClipTransitionKind) {
        editorState.pickTransitionTile(kind)
    }
}

/// The group header's plus (`#efxMenu`): the picked tile on every cut, or as
/// the one ⌘T puts on.
struct TransitionsGroupMenu: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let kind = editorState.transitionsGroupKind
        Menu {
            Button("Apply to Every Cut") { editorState.putTransitionOnEveryCut(kind) }
            Button("Set as Default Transition") { editorState.setDefaultTransition(kind) }
                .disabled(editorState.defaultTransitionKind == kind)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Add transition")
        .panelHelp("\(kind.title) on every cut, or as the default")
        .playtestControl("Transitions menu", detail: "the plus on the Transitions header")
    }
}

extension EditorState {

    /// Whether the panel carries the Transitions group: a document with time
    /// that has a recording on its timeline, which is where cuts come from.
    var showsTransitionsGroup: Bool {
        guard Experiments.shared.transitionsAtACutEnabled, documentHasTime, let document else { return false }
        return document.timelineClipLayers.contains { $0.movie != nil }
    }

    /// Whether a cut itself is picked, rather than a clip with the playhead
    /// near one of its joins: only then does a click on a tile mean it.
    private var isACutPicked: Bool { selectedEditPoint != nil || selectedClipCutIndex != nil }

    /// The tile the group shows picked and its plus menu acts on: what is on
    /// the picked cut, else the one clicked last, else the default.
    var transitionsGroupKind: ClipTransitionKind {
        if isACutPicked, let kind = cutInHand?.cut.transition?.kind { return kind }
        return transitionsGroupPick ?? defaultTransitionKind
    }

    /// A tile clicked in the Transitions group: picked, and put on the picked
    /// cut when there is one (the mock's "pick one to apply it to the selected
    /// cut"). A cut that cannot pay for it says so on the canvas, the way ⌘T
    /// does, and keeps what it has.
    func pickTransitionTile(_ kind: ClipTransitionKind) {
        transitionsGroupPick = kind
        guard isACutPicked, canWorkWithClipTransitions, let inHand = cutInHand else { return }
        guard inHand.cut.fitted(kind) != nil else {
            raiseCanvasNotice(.defaultTransitionRefused(.noSpare(kind)))
            return
        }
        setTransition(kind, at: inHand.place)
    }
}
