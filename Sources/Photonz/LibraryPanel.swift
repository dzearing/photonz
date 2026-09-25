import AppKit
import PhotonzCore
import SwiftUI

// MARK: - The Library shelf (Next, `next-library`)

/// The Library: one shelf with four scopes, living in the right dock as an
/// ordinary panel group (`docs/design/ui-building.md`, step B3). It is not a
/// browser window and not a mode — someone who only captures and redlines
/// never turns it on, and the dock without it is the dock they have today.
///
/// **Media** shows the pictures THIS document holds (`DocumentMedia`), one
/// tile per picture however many layers draw it. It used to list the app's
/// whole capture folder, which is the global shelf's job: History (⇧⌘H) is
/// everything you ever captured, across every document, and the Library is
/// what this file contains and can place again (`docs/design/modes.md` §6).
/// So a brand new document opens on an empty shelf, and the empty shelf says
/// both what will fill it and where the captures went. Components, Styles and
/// Systems arrive with the steps that create them, and until then each says so
/// in plain words.
///
/// Selection is the app's one selection: picking a tile clears the layer and
/// canvas selection and opens the item's section in this same dock, exactly
/// the way picking a layer opens its sections.
struct LibraryPanel: View {
    @Environment(EditorState.self) private var editorState
    /// The scope you were last in, remembered across launches (and read by the
    /// section header, so a collapsed Library still says what it is set to).
    @AppStorage(LibraryPanel.scopeKey) private var scopeRaw = LibraryScope.media.rawValue
    /// The tile area's max height, resizable and persisted, the same way the
    /// layers area is: a long shelf must not shove the rest of the dock off
    /// the bottom.
    @AppStorage(LibraryPanel.heightKey) private var maxHeight = 220.0
    @State private var query = ""
    /// How much room the shelf has across, which is all that has to be
    /// measured: the rest of the height is arithmetic.
    @State private var shelfWidth: CGFloat = 0
    /// Where the shelf is scrolled to, and whether it owes someone a scroll.
    /// A reference on purpose: see the note at the grid's geometry reader.
    @State private var shelfReveal = ShelfRevealScratch()
    /// What the scope picker, search box and grab bar around the tiles come to.
    @State private var chromeHeight: CGFloat = 0

    /// A second ceiling, from the dock rather than from the grab bar: what the
    /// panel can spare once every form section has been paid for. The stored
    /// ceiling is what the reader ASKED the shelf for; this is what the dock
    /// HAS, and the shelf is drawn at the smaller of the two, exactly the way
    /// the layers list is (`LayersListView.dockCeiling`).
    ///
    /// The shelf takes this itself rather than letting the dock wrap the whole
    /// section in a second scroller, which is what it used to do. Two scrollers
    /// over one shelf meant the outer one cut the inner one's window: the tile
    /// the app had just scrolled to could be perfectly placed in the shelf and
    /// still behind the fade, and what the cut took was the CAPTION under a
    /// tile picture, which is the tile's name.
    var dockCeiling: CGFloat?
    /// Told how tall the shelf would be with only the grab bar pressing on it,
    /// and what the picker, search box and grab bar around it cost, so the dock
    /// can budget for both separately: the shelf scrolls and they do not.
    var onMetrics: ((_ shelfNatural: CGFloat, _ extras: CGFloat) -> Void)?

    static let scopeKey = "library.scope"
    /// How tall the shelf may get, remembered across launches.
    static let heightKey = "inspector.libraryHeight"
    static let minHeight: CGFloat = 104
    static let maxAllowedHeight: CGFloat = 560
    /// How many tiles one scope draws at once. Search runs over everything and
    /// only the result is capped, so an older capture is still reachable by
    /// name — this is a cap on how many full-size images the grid loads, not
    /// on what the Library knows about.
    static let maxTiles = 60
    /// The shelf's scrolling area as a coordinate space, so the grid can say
    /// how far it has been scrolled rather than where it is in the window.
    // nonisolated: a plain name, read from the Sendable closure
    // `onGeometryChange` hands its reader. Making the panel Equatable put that
    // closure outside the main actor's isolation, and a constant string has no
    // business being isolated in the first place.
    fileprivate nonisolated static let shelfSpace = "library.shelf"

    private var scope: LibraryScope { LibraryScope(rawValue: scopeRaw) ?? .media }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            scopePicker
            searchField
            // A colour let go of on the shelf asks for its name HERE, right
            // above the tiles it is about to join, rather than in a dialog
            // over the picture. Same field, same keys, as the one a colour row
            // opens.
            if let dropped = editorState.colorStyleShelfNaming {
                LibraryColorNamingField(paint: dropped.paint)
            }
            tiles
            resizeHandle
        }
        // The panel's one margin, like every other section: the shelf kept a
        // 12 of its own, so its scope bar and search box stood 2pt proud of
        // every row above and below them (`panelMargins`, 2026-09-24).
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.top, 2)
        // What the section costs the dock, split into the part that scrolls and
        // the part that must not. Measured as a whole and the shelf taken back
        // out of it, because the chrome is not one contiguous piece: the picker
        // and the search box sit above the tiles and the grab bar below them.
        //
        // No loop in that: what is left after the shelf comes out does not
        // depend on how tall the shelf was drawn, and the height reported for
        // the shelf itself is the UNPRESSED one, so the dock never budgets from
        // a number it just handed out.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { total in
            let extras = max(0, total - shelfHeight)
            if chromeHeight != extras { chromeHeight = extras }
            onMetrics?(unpressedShelfHeight, extras)
        }
        .onAppear { onMetrics?(unpressedShelfHeight, chromeHeight) }
        // A shelf that gained a row without growing — because the dock was
        // already pressing on it — changes what it is ASKING for and nothing
        // else, so the measurement above never fires and the dock would keep
        // budgeting for the old shelf.
        .onChange(of: unpressedShelfHeight) { onMetrics?(unpressedShelfHeight, chromeHeight) }
        // Switching scope with a search still running would show an empty
        // shelf for a reason that is not on screen anymore.
        .onChange(of: scopeRaw) { query = "" }
        // The one place in the app a dropped colour is KEPT rather than
        // painted with.
        .libraryColorDrop()
        // ...and a recording or a sound: the section's own drop target takes
        // it (`SectionFileDrop`), and the shelf wears the ring a kept colour
        // gets, so it is plain the file is going HERE and not onto the picture.
        .overlay {
            if editorState.isLibraryTakingFiles {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: editorState.isLibraryTakingFiles)
        // Named so a walk can let a file go on the shelf through the section's
        // own drop target.
        .playtestTarget("Library shelf", kind: .row, detail: scope.title)
    }

    // MARK: Scope and search

    private var scopePicker: some View {
        // The kit's bar rather than the system's: a system segmented control
        // cannot shrink below its own words, and in the narrowest dock this one
        // made the panel 30pt wider than the dock, sliding every section over
        // the canvas (`panelMargins`, 2026-09-24). The kit's bar becomes a
        // dropdown when its words will not fit.
        VideoKit.Segmented(options: LibraryScope.allCases.map { ($0, $0.segmentTitle) },
                           selection: scope) { scopeRaw = $0.rawValue }
            .panelHelp("What the shelf is showing")
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(scope.searchPlaceholder, text: $query)
                .textFieldStyle(.plain)
                .font(.caption)
                // Type to narrow, Return to take the top hit, which is the
                // flow every search field on the Mac already has. Escape empties
                // the box, so the shelf shows everything again. Both are the end
                // of searching, so both hand the keyboard to the picture and the
                // next tool letter picks a tool.
                .onSubmit { selectFirstTile() }
                // With nothing matching, Return has no top hit to take, so it
                // leaves the keyboard where the fixing happens.
                .nameFieldKeys(canCommit: !isEmpty,
                               commit: selectFirstTile,
                               revert: { query = "" })
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

    // MARK: Tiles

    /// The tiles Media draws for what is typed: the pictures this document
    /// holds, paired with the entry so the tile can draw and caption one. The
    /// name is the layer that placed it first and the detail is how many
    /// layers draw it, and search reads both.
    private var visibleMedia: [(entry: LibraryEntry, item: DocumentMediaItem)] {
        guard scope == .media else { return [] }
        let items = editorState.documentMediaItems
        let byID = Dictionary(items.map { ($0.id.uuidString, $0) },
                              uniquingKeysWith: { first, _ in first })
        let hits = LibrarySearch.filter(DocumentMedia.entriesOf(items), query: query)
        return hits.prefix(Self.maxTiles).compactMap { entry in
            byID[entry.id].map { (entry, $0) }
        }
    }

    /// The recordings and sounds Media draws for what is typed, ahead of the
    /// pictures and in the order they were brought in (`video.html`, Library
    /// scope Media: intro.mov, demo.mov, b-roll.mov, music.wav).
    private var visibleClips: [(entry: LibraryEntry, item: DocumentClipItem)] {
        guard scope == .media else { return [] }
        let items = editorState.documentClipItems
        guard !items.isEmpty else { return [] }
        let byID = Dictionary(items.map { ($0.id.uuidString, $0) },
                              uniquingKeysWith: { first, _ in first })
        let hits = LibrarySearch.filter(DocumentMedia.clipEntriesOf(items), query: query)
        return hits.prefix(Self.maxTiles).compactMap { entry in
            byID[entry.id].map { (entry, $0) }
        }
    }

    /// The tiles Components draws for what is typed: the mains in the open
    /// document and the starters it has not taken yet, each paired with the
    /// layer it stands for so the tile can draw a picture of it (Next,
    /// `next-components` and `next-starter-components`). A starter's layer is
    /// not in the document — it is what a drop would bring in.
    private var visibleComponents: [(entry: LibraryEntry, layer: Layer,
                                     starter: StarterComponent?, shared: SharedComponent?)] {
        guard scope == .components, let document = editorState.document else { return [] }
        let hits = LibrarySearch.filter(editorState.componentEntries, query: query)
        // One walk of the tree for all the tiles, not one per tile: this runs
        // on every draw of the shelf, and a lookup by id copies the whole
        // layer tree on its way through.
        let mains = Dictionary(document.mainComponents.compactMap { layer in
            layer.componentID.map { ($0, layer) }
        }, uniquingKeysWith: { first, _ in first })
        return hits.prefix(Self.maxTiles).compactMap { entry in
            guard let id = UUID(uuidString: entry.id) else { return nil }
            if let layer = mains[id] { return (entry, layer, nil, nil) }
            if let shared = editorState.sharedComponent(entryID: entry.id),
               let drawing = editorState.sharedPreviewLayer(shared) {
                return (entry, drawing, nil, shared)
            }
            guard editorState.starterComponentsEnabled,
                  let starter = StarterComponent(componentID: id) else { return nil }
            return (entry, editorState.starterPreviewLayer(starter), starter, nil)
        }
    }

    /// The tiles Styles draws for what is typed: the named colors saved in the
    /// open document, each paired with the style so the tile can draw its
    /// color (Next, `next-styles`).
    private var visibleStyles: [(entry: LibraryEntry, style: ColorStyle)] {
        guard scope == .styles, let document = editorState.document else { return [] }
        let hits = LibrarySearch.filter(editorState.colorStyleEntries, query: query)
        return hits.prefix(Self.maxTiles).compactMap { entry in
            guard let id = UUID(uuidString: entry.id),
                  let style = document.colorStyle(id: id) else { return nil }
            return (entry, style)
        }
    }

    /// ...and the named text treatments, on the same shelf and after them
    /// (Next, `next-styles`). One shelf, because to a person a saved colour and
    /// a saved way of setting text are the same kind of thing: a name you put
    /// on things.
    private var visibleTextStyles: [(entry: LibraryEntry, style: TextStyle)] {
        guard scope == .styles, let document = editorState.document else { return [] }
        let hits = LibrarySearch.filter(editorState.textStyleEntries, query: query)
        return hits.prefix(Self.maxTiles).compactMap { entry in
            guard let id = UUID(uuidString: entry.id),
                  let style = document.textStyle(id: id) else { return nil }
            return (entry, style)
        }
    }

    /// ...and the named effects, on the same shelf and after them (Next,
    /// `next-styles`). The third of the three kinds a style comes in, and it
    /// sits with the other two because to a person they are one thing: a name
    /// you put on things.
    private var visibleEffectStyles: [(entry: LibraryEntry, style: EffectStyle)] {
        guard scope == .styles, let document = editorState.document else { return [] }
        let hits = LibrarySearch.filter(editorState.effectStyleEntries, query: query)
        return hits.prefix(Self.maxTiles).compactMap { entry in
            guard let id = UUID(uuidString: entry.id),
                  let style = document.effectStyle(id: id) else { return nil }
            return (entry, style)
        }
    }

    /// Whether this scope has anything to show at all, whatever the search
    /// says. The empty state and the resize grabber both hang off this.
    private var isEmpty: Bool {
        visibleClips.isEmpty && visibleMedia.isEmpty && visibleComponents.isEmpty && visibleStyles.isEmpty
            && visibleTextStyles.isEmpty && visibleEffectStyles.isEmpty
    }

    /// How many tiles the shelf is showing right now, whatever scope they came
    /// from — the shelf only ever draws one scope at a time.
    private var tileCount: Int {
        visibleClips.count + visibleMedia.count + visibleComponents.count + visibleStyles.count
            + visibleTextStyles.count + visibleEffectStyles.count
    }

    /// The height the shelf takes: its tiles, capped at the LOWER of the two
    /// ceilings pressing on it — what the grab bar was dragged to, and what the
    /// dock has room for. A shelf holding one thing is one tile tall, so the
    /// dock under it is not a patch of empty glass.
    private var shelfHeight: CGFloat {
        // An empty shelf is a sentence, not a list: there is no grid to cap and
        // nothing for the dock to take away.
        guard !isEmpty else { return 0 }
        return LibraryShelfLayout.shelfHeight(
            tileCount: tileCount, width: shelfWidth,
            cap: min(maxHeight, dockCeiling ?? .greatestFiniteMagnitude))
    }

    /// ...and what it would be if the dock were NOT pressing on it: its tiles,
    /// capped by the ceiling the reader set with the grab bar. This is what the
    /// dock budgets from, so it reserves room for the shelf that was asked for
    /// rather than for the one it has already shortened.
    private var unpressedShelfHeight: CGFloat {
        guard !isEmpty else { return 0 }
        return LibraryShelfLayout.shelfHeight(tileCount: tileCount, width: shelfWidth,
                                              cap: maxHeight)
    }

    @ViewBuilder
    private var tiles: some View {
        if isEmpty {
            // An empty shelf takes only the room its sentence needs.
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    grid
                        // How far the shelf is scrolled, which is the one thing
                        // the reveal below cannot work out for itself. Kept
                        // OUTSIDE @State on purpose: this fires on every scroll
                        // tick, and re-drawing the shelf to remember a number
                        // nothing draws is jank for nothing.
                        .onGeometryChange(for: CGFloat.self) {
                            $0.frame(in: .named(Self.shelfSpace)).minY
                        } action: { top in
                            shelfReveal.gridTop = top
                            if shelfReveal.isPending { applyTileReveal(proxy) }
                        }
                }
                .frame(height: shelfHeight)
                .coordinateSpace(.named(Self.shelfSpace))
                .scrollBounceBehavior(.basedOnSize)
                // A shelf the dock has squeezed keeps a sliver of the next row
                // on screen, and this is what turns that sliver into a
                // sentence: the cut edge fades, the way every other shortened
                // body in the dock does, so three tiles showing out of five
                // read as three of five rather than as all there is. Without
                // it, an audit read a cut shelf on 2026-09-17 and reported the
                // Nav Bar component missing from an app that had it.
                .scrollEdgeFade(isShortened: isShelfShortened)
                // Only the WIDTH is measured. How tall the shelf wants to be
                // is worked out from the tile count instead, because a lazy
                // grid only builds the rows it can see and so answers a
                // measurement with the height it was given rather than the
                // height it wants.
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    shelfWidth = width
                }
                // The shelf grows and shrinks as a search narrows it, so let it
                // move rather than jump. Keyed on the tile count on purpose:
                // the first pass, where the shelf learns how wide it is, must
                // land silently instead of sliding down from the ceiling.
                .animation(.spring(duration: 0.22), value: tileCount)
                // The app just made something that lives on this shelf: put
                // that tile on screen. On appear too, because making the first
                // component builds this shelf with the request already waiting.
                .onChange(of: editorState.pendingLibraryTileID) { requestTileReveal(proxy) }
                .onAppear { requestTileReveal(proxy) }
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: LibraryShelfLayout.tileMinimumWidth),
                                    spacing: LibraryShelfLayout.tileSpacing)],
                  alignment: .leading, spacing: LibraryShelfLayout.tileSpacing) {
            ForEach(visibleClips, id: \.entry.id) { pair in
                LibraryClipTile(item: pair.entry, clip: pair.item)
            }
            ForEach(visibleMedia, id: \.entry.id) { pair in
                LibraryTile(item: pair.entry, media: pair.item)
            }
            ForEach(visibleComponents, id: \.entry.id) { pair in
                LibraryComponentTile(entry: pair.entry, layer: pair.layer, starter: pair.starter,
                                     shared: pair.shared)
            }
            ForEach(visibleStyles, id: \.entry.id) { pair in
                LibraryStyleTile(entry: pair.entry, style: pair.style)
            }
            ForEach(visibleTextStyles, id: \.entry.id) { pair in
                LibraryTextStyleTile(entry: pair.entry, style: pair.style)
            }
            ForEach(visibleEffectStyles, id: \.entry.id) { pair in
                LibraryEffectStyleTile(entry: pair.entry, style: pair.style)
            }
        }
        .padding(.vertical, LibraryShelfLayout.gridVerticalPadding)
    }

    private var emptyState: some View {
        Text(scope.emptyMessage(searching: query))
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 18)
    }

    // MARK: Bringing the new tile into view

    /// The app has made something the shelf holds (a component, a saved color)
    /// and wants its tile on screen. The shelf shows about two rows, and a new
    /// component is listed after the ones already in the document, so with a
    /// handful saved the tile lands below the shelf's own fold.
    ///
    /// A tile already showing must not move: the shelf twitching every time you
    /// make something is worse than the scroll is worth.
    /// `LibraryShelfLayout.tileReveal` makes that call.
    private func requestTileReveal(_ proxy: ScrollViewProxy) {
        guard let id = editorState.pendingLibraryTileID else { return }
        // A search still running can be hiding the very thing the app just
        // made, and a shelf that hides your work is the same failure one step
        // earlier. So the search goes.
        if !query.isEmpty, shelfIndex(of: id) == nil { query = "" }
        shelfReveal.isPending = true
        // The grid may have moved with this very change, in which case the
        // measurement above lands first and this finds nothing left to do. When
        // the shelf was already scrolled where it needed to be, or grew without
        // moving, this is the only path.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { applyTileReveal(proxy) }
    }

    private func applyTileReveal(_ proxy: ScrollViewProxy) {
        guard shelfReveal.isPending, let id = editorState.pendingLibraryTileID else { return }
        shelfReveal.isPending = false
        editorState.libraryTileRevealHandled()
        // Not on this shelf: a scope was switched under it, or a search still
        // has no room for it. Nothing to scroll to, so let the request go.
        guard let index = shelfIndex(of: id), shelfWidth > 0 else { return }
        let action = LibraryShelfLayout.tileReveal(index: index, width: shelfWidth,
                                                   gridTop: shelfReveal.gridTop,
                                                   viewportHeight: shelfHeight)
        guard action != .none else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            proxy.scrollTo(id, anchor: action == .top ? .top : .bottom)
        }
    }

    /// Where a tile sits in the shelf as it is drawn right now, counting from
    /// zero, or nil when it is not on this shelf at all. One index, not one per
    /// scope: the shelf only ever draws one scope at a time.
    private func shelfIndex(of id: String) -> Int? {
        if let index = visibleClips.firstIndex(where: { $0.entry.id == id }) { return index }
        if let index = visibleMedia.firstIndex(where: { $0.entry.id == id }) {
            return visibleClips.count + index
        }
        if let index = visibleComponents.firstIndex(where: { $0.entry.id == id }) { return index }
        if let index = visibleStyles.firstIndex(where: { $0.entry.id == id }) { return index }
        return nil
    }

    /// Return in the search field picks the first tile showing, so the shelf
    /// can be worked without the pointer.
    private func selectFirstTile() {
        if let first = visibleClips.first {
            editorState.selectLibraryItem(first.entry.id)
        } else if let first = visibleMedia.first {
            editorState.selectLibraryItem(first.entry.id)
        } else if let first = visibleComponents.first {
            editorState.selectLibraryItem(first.entry.id)
        } else if let first = visibleStyles.first {
            editorState.selectLibraryItem(first.entry.id)
        }
    }

    /// Whether the shelf is showing less than it holds, and so owes the reader
    /// a cue saying so. Never before it has been measured: a shelf standing at
    /// its ceiling for one frame is not a shelf that has been cut.
    private var isShelfShortened: Bool {
        shelfWidth > 0 && shelfHeight < shelfContentHeight - PanelAreaResize.tolerance
    }

    /// How tall the shelf would be with nothing capping it. Before anything
    /// has measured the dock there is no honest answer, so it stands at its
    /// ceiling for that one frame, exactly as `shelfHeight` does.
    private var shelfContentHeight: CGFloat {
        guard shelfWidth > 0 else { return maxHeight }
        return LibraryShelfLayout.contentHeight(tileCount: tileCount, width: shelfWidth)
    }

    /// The grab bar decides for itself whether there is anything to resize: an
    /// empty shelf, or one holding a single row of tiles, offers none.
    private var resizeHandle: some View {
        // Never past what the dock can spare, so every point of the bar still
        // moves the shelf: a bar that refused to move would be a control that
        // cannot act. The room is still there to be had — collapsing a section
        // you are not using is what frees it.
        PanelAreaResizeHandle(maxHeight: $maxHeight,
                              area: "Library",
                              contentHeight: min(shelfContentHeight,
                                                 dockCeiling ?? .greatestFiniteMagnitude),
                              minHeight: Self.minHeight,
                              maxAllowedHeight: Self.maxAllowedHeight,
                              help: "Drag to resize the Library")
    }
}

/// The shelf's live measurements for the tile reveal: how far it is scrolled,
/// and whether a reveal is waiting on layout. Held by reference so writing it
/// during a scroll does not redraw the shelf.
@MainActor private final class ShelfRevealScratch {
    var gridTop: CGFloat = 0
    var isPending = false
}

/// One thing on the shelf: a thumbnail with its name underneath. Click picks
/// it (which is the app's one selection, so the canvas lets go), double click
/// places it again, and it drags onto the canvas as the very same picture.
private struct LibraryTile: View {
    let item: LibraryEntry
    let media: DocumentMediaItem
    @Environment(EditorState.self) private var editorState

    private var isSelected: Bool { editorState.selectedLibraryItemID == item.id }

    var body: some View {
        VStack(spacing: LibraryShelfLayout.captionSpacing) {
            thumbnail
            Text(item.name)
                .font(.system(size: LibraryShelfLayout.captionFontSize))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .frame(maxWidth: .infinity)
        .padding(LibraryShelfLayout.tilePadding)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        // Double click first: SwiftUI hands a tap to the highest count that
        // matches, and a single-click-only gesture would swallow both.
        .onTapGesture(count: 2) { place() }
        .onTapGesture { editorState.selectLibraryItem(item.id) }
        // The preview is the picture itself, so a media tile and a component
        // tile are picked up the same way. Nothing in here touches the app's
        // state: a change made while the drag is being handed over redraws the
        // tile and SwiftUI asks for the item all over again.
        .onDrag(dragItem, preview: {
            thumbnail.frame(width: LibraryShelfLayout.tileMinimumWidth,
                            height: LibraryShelfLayout.thumbnailHeight)
        })
        .panelHelp("\(item.name) • \(item.detail). Double click to place it again.")
        // The same closure a walk picks the tile up with, so an unmanned run
        // can never drag something the pointer would not.
        .playtestTarget(item.name, kind: .tile, detail: item.detail, payload: dragItem)
    }

    /// What dragging this tile hands over: the picture's id, so letting go on
    /// the canvas puts the SAME picture down rather than a second copy of it,
    /// with PNG bytes alongside for anywhere outside the app
    /// (`DocumentImageDrag`). Nothing in here touches the app's state, so a
    /// change made while the drag is being handed over redraws the tile and
    /// SwiftUI asks for the item all over again.
    private func dragItem() -> NSItemProvider {
        let store = editorState.store
        let image = media.image
        return DocumentImageDrag.itemProvider(id: media.id, name: item.name) {
            store.image(for: image).flatMap(DocumentImageDrag.pngData)
        }
    }

    /// The picture, filling a fixed 44pt-tall well and cropped to it. The
    /// image goes in an OVERLAY rather than a stack: an overlay never gets a
    /// say in its host's size, so a wide screenshot fills the well instead of
    /// stretching the tile across its neighbours.
    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(.quaternary)
            .frame(height: LibraryShelfLayout.thumbnailHeight)
            .overlay {
                if let image = editorState.store.image(for: media.image) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.12)))
    }

    private func place() {
        editorState.selectLibraryItem(item.id)
        editorState.placeLibraryPick()
    }
}

// MARK: - The picked item's section

/// What the dock says about the tile you picked: the same role the Annotation
/// or Text section plays for a layer. Media is the only scope with items of
/// its own so far, so this describes one of the document's pictures — how big
/// it is, how much of it is in here already, and the one thing worth doing
/// with it.
struct LibraryItemInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        if let clip = editorState.selectedClipItem {
            VStack(alignment: .leading, spacing: 8) {
                Text(clip.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .truncationMode(.middle)
                VStack(alignment: .leading, spacing: 2) {
                    detail(clip.detail)
                    if let movie = clip.movie {
                        detail("\(Int(movie.pixelSize.width)) × \(Int(movie.pixelSize.height)) px")
                    }
                }
                Button("Add at Playhead") {
                    editorState.placeLibraryPick()
                }
                .controlSize(.small)
                .disabled(editorState.document?.hasTime != true)
                .panelHelp("Puts this on the timeline at the playhead")
                .playtestControl("Add at Playhead", detail: "the picked Library tile")
            }
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
            .padding(.vertical, 4)
        } else if let item = editorState.selectedMediaItem {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .truncationMode(.middle)
                VStack(alignment: .leading, spacing: 2) {
                    detail(item.detail)
                    detail("\(Int(item.image.pixelSize.width)) × "
                        + "\(Int(item.image.pixelSize.height)) px")
                }
                Button("Place in Picture") {
                    editorState.placeLibraryPick()
                }
                .controlSize(.small)
                .panelHelp("Puts this picture into the document again, as a new layer")
            }
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
            .padding(.vertical, 4)
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: - The plus on the Library header

/// The ways something gets onto the shelf, on the Library header's plus
/// (`video.html`, `#libMenu`): Import Media, From Capture History, Add
/// Selection to Library.
struct LibraryAddMenu: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        Menu {
            // The key the File row answers to, on the same terms: it is
            // Invert Selection while a marquee is up.
            Button("Import Media…") { editorState.importMediaFromPanel() }
                .keyboardShortcut(editorState.selection == nil
                                  ? KeyboardShortcut("i", modifiers: [.command, .shift]) : nil)
            Button("From Capture History") { editorState.showCaptureHistory?() }
            Button("Add Selection to Library") { editorState.makeComponent() }
                .disabled(!editorState.canMakeComponent)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Add to Library")
        .panelHelp("Add to Library")
        .playtestControl("Add to Library", detail: "the plus on the Library header")
    }
}
