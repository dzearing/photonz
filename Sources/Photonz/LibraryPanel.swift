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
    @StoredSetting(LibraryPanel.scopeKey) private var scopeRaw = LibraryScope.media.rawValue
    /// ...and a video's, which is its own: a video offers Media and its
    /// catalog, and nothing a picture left behind (`LibraryScope.scopes`).
    @StoredSetting(EditorState.videoLibraryScopeKey) private var videoScopeRaw = LibraryScope.media.rawValue
    /// The kind the catalog was last showing, "" for All.
    @StoredSetting(EditorState.catalogCategoryKey) private var catalogCategoryRaw = ""
    /// Whether the catalog keeps only what was made for video. On until a
    /// person turns it off: components are built for mockups.
    @StoredSetting(EditorState.catalogBuiltForVideoKey) private var builtForVideoOnly = true
    /// The tile area's max height, resizable and persisted, the same way the
    /// layers area is: a long shelf must not shove the rest of the dock off
    /// the bottom. Its first value is the release's own: two whole rows of
    /// cards in Next (`LibraryShelfLayout.defaultCap`).
    @StoredSetting(LibraryPanel.heightKey) private var maxHeight = 220.0
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
    /// Drawn in the pane of lists under the pick (Next, `next-lists-pane`),
    /// whose grip sets the room: the shelf takes as much of it as its tiles
    /// need and has no grab bar of its own, the way the Layers list does.
    var inListsPane = false
    /// Told how tall the shelf would be with only the grab bar pressing on it,
    /// and what the picker, search box and grab bar around it cost, so the dock
    /// can budget for both separately: the shelf scrolls and they do not.
    var onMetrics: ((_ shelfNatural: CGFloat, _ extras: CGFloat, _ floor: CGFloat) -> Void)?

    init(dockCeiling: CGFloat? = nil, inListsPane: Bool = false,
         onMetrics: ((_ shelfNatural: CGFloat, _ extras: CGFloat, _ floor: CGFloat) -> Void)? = nil) {
        self.dockCeiling = dockCeiling
        self.inListsPane = inListsPane
        self.onMetrics = onMetrics
        let firstCap = LibraryShelfLayout.defaultCap(sizing: Experiments.shared.libraryTileSizing)
        _maxHeight = StoredSetting(wrappedValue: Double(firstCap), Self.heightKey)
    }

    /// How this release sizes its tiles: the mock's cards in Next, the older
    /// 68 point tiles in Current.
    private var sizing: LibraryShelfLayout.Sizing { Experiments.shared.libraryTileSizing }

    /// The least the dock may squeeze the shelf to: one whole row of tiles at
    /// the width the shelf has, and a sliver of the next. A card shelf's row
    /// grows with the dock, so this is the shelf's to say, not the dock's.
    private var squeezeFloor: CGFloat {
        // A shelf drawn in groups opens with a header, which the row it keeps
        // sits under.
        LibraryShelfLayout.squeezeFloor(peek: DockMetrics.bodyPeek, width: shelfWidth, sizing: sizing)
            + (shelfGroups == nil ? 0 : LibraryShelfLayout.groupHeaderHeight)
    }

    /// What each tile is drawn at, handed down to the tile views so the
    /// picture and the arithmetic above are the same numbers.
    private var tileMetrics: LibraryTileMetrics {
        LibraryTileMetrics(width: shelfWidth, sizing: sizing)
    }

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

    private var hasTime: Bool { editorState.documentHasTime }

    /// The pivot showing: the open document's kind's own, fallen to the
    /// nearest one that kind offers, so the pivots follow the window in front.
    private var scope: LibraryScope {
        LibraryScope.resolved(LibraryScope(rawValue: hasTime ? videoScopeRaw : scopeRaw) ?? .media,
                              hasTime: hasTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            scopePicker
            searchField
            if scope == .catalog { catalogFilters }
            // A colour let go of on the shelf asks for its name HERE, right
            // above the tiles it is about to join, rather than in a dialog
            // over the picture. Same field, same keys, as the one a colour row
            // opens.
            if let dropped = editorState.colorStyleShelfNaming {
                LibraryColorNamingField(paint: dropped.paint)
            }
            tiles
            // Not in the pane: its grip is the one control for how much room
            // the lists get, and a second bar under the tiles would only cap
            // the shelf short of room the pane already holds.
            if !inListsPane { resizeHandle }
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
            onMetrics?(unpressedShelfHeight, extras, squeezeFloor)
        }
        .onAppear { onMetrics?(unpressedShelfHeight, chromeHeight, squeezeFloor) }
        // A shelf that gained a row without growing — because the dock was
        // already pressing on it — changes what it is ASKING for and nothing
        // else, so the measurement above never fires and the dock would keep
        // budgeting for the old shelf.
        .onChange(of: unpressedShelfHeight) { onMetrics?(unpressedShelfHeight, chromeHeight, squeezeFloor) }
        // A wider dock makes a card shelf's row taller without changing what
        // the shelf holds, so its floor moves on its own.
        .onChange(of: squeezeFloor) { onMetrics?(unpressedShelfHeight, chromeHeight, squeezeFloor) }
        // Switching scope with a search still running would show an empty
        // shelf for a reason that is not on screen anymore.
        .onChange(of: scopeRaw) { query = "" }
        .onChange(of: videoScopeRaw) { query = "" }
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
        // The drawn control in both releases: a system segmented control
        // cannot shrink below its own words, and in the narrowest dock this one
        // made the panel 30pt wider than the dock, sliding every section over
        // the canvas (`panelMargins`, 2026-09-24). The drawn one becomes a
        // dropdown when its words will not fit.
        SegmentedControl("Shelf", selection: scope,
                         options: LibraryScope.scopes(hasTime: hasTime).map { .init($0, $0.segmentTitle) },
                         fallsBackToSystem: false) {
            if hasTime { videoScopeRaw = $0.rawValue } else { scopeRaw = $0.rawValue }
        }
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
                .playtestControl("Search library", detail: "Library")
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

    /// The catalog's kinds as chips, each with its count, and the Built for
    /// video filter under them (`video-library.html`, `.vl-chips`).
    @ViewBuilder
    private var catalogFilters: some View {
        let catalog = editorState.videoCatalog
        let counts = catalog.categories(builtForVideoOnly: builtForVideoOnly, query: query)
        let picked = catalogCategory(catalog)
        if !counts.isEmpty {
            LibraryChipWrap {
                LibraryCatalogChip(title: "All", count: counts.reduce(0) { $0 + $1.count },
                                   isOn: picked == nil) { pickCategory(nil) }
                ForEach(counts, id: \.category) { kind in
                    LibraryCatalogChip(title: kind.category.title, count: kind.count,
                                       isOn: picked == kind.category) { pickCategory(kind.category) }
                }
            }
            .animation(.easeOut(duration: 0.15), value: counts.map(\.category))
        }
        Toggle("Built for video", isOn: $builtForVideoOnly)
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .font(.caption)
            .fixedSize()
            .panelHelp("Off shows components too, which are built for mockups")
            .playtestControl("Built for video", detail: "Catalog")
    }

    /// A chip pressed: that kind, remembered for the next video. A search
    /// still running is let go, since it runs across every kind and would
    /// hide the pick.
    private func pickCategory(_ category: VideoCatalogCategory?) {
        query = ""
        catalogCategoryRaw = category?.rawValue ?? ""
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
        let mains = Self.mains(of: document)
        return hits.prefix(Self.maxTiles).compactMap { componentTile($0, mains: mains) }
    }

    /// Every main in the document by its component id, in one walk of the tree.
    private static func mains(of document: PhotonzDocument) -> [UUID: Layer] {
        Dictionary(document.mainComponents.compactMap { layer in
            layer.componentID.map { ($0, layer) }
        }, uniquingKeysWith: { first, _ in first })
    }

    /// The component tile for an entry: a main in the open document, one off
    /// the shared shelf, or a starter it has not taken yet, each with the
    /// layer it stands for so the tile can draw a picture of it. A starter's
    /// layer is not in the document: it is what a drop would bring in.
    private func componentTile(_ entry: LibraryEntry, mains: [UUID: Layer])
        -> (entry: LibraryEntry, layer: Layer, starter: StarterComponent?, shared: SharedComponent?)? {
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

    // MARK: The catalog

    /// The kind the catalog is showing, nil for All: the one remembered while
    /// it still has a chip. A search runs over every kind whatever is picked,
    /// so while one is typed the chip that reads as picked is All.
    private func catalogCategory(_ catalog: VideoCatalog) -> VideoCatalogCategory? {
        guard LibrarySearch.normalized(query).isEmpty else { return nil }
        let shown = catalog.categories(builtForVideoOnly: builtForVideoOnly).map(\.category)
        return VideoCatalog.resolvedCategory(catalogCategoryRaw, shown: shown)
    }

    /// The groups the catalog draws for what is typed and picked.
    private var catalogGroups: [VideoCatalogGroup] {
        guard scope == .catalog else { return [] }
        let catalog = editorState.videoCatalog
        return catalog.groups(category: catalogCategory(catalog), query: query,
                              builtForVideoOnly: builtForVideoOnly)
    }

    /// Whether the catalog heads each group with its kind: on All and while
    /// searching, where more than one kind can show. One kind picked is
    /// already named by its chip.
    private var catalogShowsHeaders: Bool {
        !LibrarySearch.normalized(query).isEmpty || VideoCatalog.resolvedCategory(
            catalogCategoryRaw,
            shown: editorState.videoCatalog.categories(builtForVideoOnly: builtForVideoOnly).map(\.category)) == nil
    }

    private var catalogItemCount: Int { catalogGroups.reduce(0) { $0 + $1.items.count } }

    /// The shelf's groups, when it is drawn in groups: the catalog's kinds,
    /// each under its header. Nil for a shelf drawn as one grid.
    private var shelfGroups: [Int]? {
        guard scope == .catalog, catalogShowsHeaders else { return nil }
        let groups = catalogGroups
        return groups.isEmpty ? nil : groups.map(\.items.count)
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
            && visibleTextStyles.isEmpty && visibleEffectStyles.isEmpty && catalogGroups.isEmpty
    }

    /// How many tiles the shelf is showing right now, whatever scope they came
    /// from — the shelf only ever draws one scope at a time.
    private var tileCount: Int {
        visibleClips.count + visibleMedia.count + visibleComponents.count + visibleStyles.count
            + visibleTextStyles.count + visibleEffectStyles.count + catalogItemCount
    }

    /// The height the shelf takes: its tiles, capped at the LOWER of the two
    /// ceilings pressing on it — what the grab bar was dragged to, and what the
    /// dock has room for. A shelf holding one thing is one tile tall, so the
    /// dock under it is not a patch of empty glass. In the pane of lists the
    /// grab bar is not one of them: the pane's grip already set the room, and
    /// keeping the bar's ceiling there left a shelf scrolling over a band of
    /// blank glass in its own pane (2026-10-15, `PanelListsPane.listCeiling`).
    private var shelfHeight: CGFloat {
        // An empty shelf is a sentence, not a list: there is no grid to cap and
        // nothing for the dock to take away.
        guard !isEmpty else { return 0 }
        let cap = PanelListsPane.listCeiling(grabBar: maxHeight, dock: dockCeiling,
                                             inPane: inListsPane)
        // Before the shelf knows its width it has no honest height, so for
        // that one frame it stands at the grab bar's ceiling, never at an
        // unbounded pane's.
        guard shelfWidth > 0 else { return min(maxHeight, cap) }
        return min(shelfContentHeight, cap)
    }

    /// ...and what it would be if the dock were NOT pressing on it: all of its
    /// tiles in the pane of lists, or its tiles capped by the ceiling the
    /// reader set with the grab bar outside it. This is what the dock budgets
    /// from, so it reserves room for the shelf that was asked for rather than
    /// for the one it has already shortened.
    private var unpressedShelfHeight: CGFloat {
        guard !isEmpty else { return 0 }
        guard shelfWidth > 0 else { return maxHeight }
        return PanelListsPane.listAsks(content: shelfContentHeight, grabBar: maxHeight,
                                       inPane: inListsPane)
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

    @ViewBuilder
    private var grid: some View {
        if scope == .catalog {
            catalogGrid
        } else {
            tileGrid { allTiles }
        }
    }

    /// The catalog: each kind under its header, starting a row of its own, so
    /// a name card never sits beside a transition as if they were one kind of
    /// thing; or the one kind picked, as one grid.
    @ViewBuilder
    private var catalogGrid: some View {
        let groups = catalogGroups
        let mains = editorState.document.map(Self.mains(of:)) ?? [:]
        if catalogShowsHeaders {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(groups, id: \.category) { group in
                    groupHeader(group.category.title, note: group.category.note)
                    tileGrid {
                        ForEach(group.items) { item in catalogTile(item, mains: mains) }
                    }
                }
            }
        } else {
            tileGrid {
                ForEach(groups.flatMap(\.items)) { item in catalogTile(item, mains: mains) }
            }
        }
    }

    /// One catalog item as the tile its kind draws: a title's playing tile,
    /// a moving background, a transition, a picture or a component.
    @ViewBuilder
    private func catalogTile(_ item: VideoCatalogItem, mains: [UUID: Layer]) -> some View {
        switch item.category {
        case .titlePages, .nameCards, .animatedCharts:
            if let preset = editorState.titlePreset(entryID: item.id) { LibraryTitleTile(preset: preset) }
        case .backgrounds:
            if let look = VideoCatalog.background(id: item.id) { LibraryBackgroundTile(look: look) }
        case .transitions:
            if let kind = VideoCatalog.transition(id: item.id) { LibraryTransitionTile(kind: kind) }
        case .logos:
            if let media = editorState.documentMediaItems.first(where: { $0.id.uuidString == item.id }),
               let entry = DocumentMedia.entriesOf([media]).first {
                LibraryTile(item: entry, media: media) { editorState.placePictureAtPlayhead(media) }
            }
        case .components:
            if let entry = editorState.componentEntries.first(where: { $0.id == item.id }),
               let tile = componentTile(entry, mains: mains) {
                LibraryComponentTile(entry: tile.entry, layer: tile.layer, starter: tile.starter,
                                     shared: tile.shared)
            }
        case .callouts, .endCards:
            EmptyView()
        }
    }

    /// The label over a group of tiles, exactly as tall as the shelf's
    /// arithmetic says (`LibraryShelfLayout.groupHeaderHeight`).
    private func groupHeader(_ title: String, note: String? = nil) -> some View {
        (Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            + Text(note.map { "  \($0)" } ?? "").font(.caption).foregroundStyle(.tertiary))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: LibraryShelfLayout.groupHeaderHeight, alignment: .bottomLeading)
            .accessibilityAddTraits(.isHeader)
    }

    private var componentTiles: some View {
        ForEach(visibleComponents, id: \.entry.id) { pair in
            LibraryComponentTile(entry: pair.entry, layer: pair.layer, starter: pair.starter,
                                 shared: pair.shared)
        }
    }

    private func tileGrid<Tiles: View>(@ViewBuilder _ tiles: () -> Tiles) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: sizing.minimumWidth),
                                    spacing: LibraryShelfLayout.tileSpacing)],
                  alignment: .leading, spacing: LibraryShelfLayout.tileSpacing) {
            tiles()
        }
        .padding(.vertical, LibraryShelfLayout.gridVerticalPadding)
        .environment(\.libraryTile, tileMetrics)
    }

    @ViewBuilder
    private var allTiles: some View {
        ForEach(visibleClips, id: \.entry.id) { pair in
            LibraryClipTile(item: pair.entry, clip: pair.item)
        }
        ForEach(visibleMedia, id: \.entry.id) { pair in
            LibraryTile(item: pair.entry, media: pair.item)
        }
        componentTiles
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

    @ViewBuilder
    private var emptyState: some View {
        // A video's empty Media shelf is where it gets its first recording
        // (`video.html`, New video step 2, Fill the Library), so it offers
        // Import rather than a paragraph about pictures.
        if scope == .media, LibrarySearch.normalized(query).isEmpty,
           editorState.document?.hasTime == true, editorState.canImportMedia {
            Button("Import Media…") { editorState.importMediaFromPanel() }
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .playtestControl("Import Media…", detail: "the empty Media shelf")
        } else {
            emptyMessageText
        }
    }

    private var emptyMessageText: some View {
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
        let action: DockReveal.Action
        if let groups = shelfGroups {
            // The index counts across every group; the tile sits in the
            // group its count lands in.
            var group = 0, inGroup = index
            while group < groups.count - 1, inGroup >= groups[group] {
                inGroup -= groups[group]
                group += 1
            }
            let top = LibraryShelfLayout.tileTop(group: group, index: inGroup,
                                                 groups: groups, width: shelfWidth, sizing: sizing)
            action = LibraryShelfLayout.tileReveal(top: top, width: shelfWidth, gridTop: shelfReveal.gridTop,
                                                   viewportHeight: shelfHeight, sizing: sizing)
        } else {
            action = LibraryShelfLayout.tileReveal(index: index, width: shelfWidth,
                                                   gridTop: shelfReveal.gridTop,
                                                   viewportHeight: shelfHeight,
                                                   sizing: sizing)
        }
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
        if let index = catalogGroups.flatMap(\.items).firstIndex(where: { $0.id == id }) { return index }
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
        } else if let first = catalogGroups.first?.items.first {
            // A transition's click is the Transitions group's, so the cut in
            // hand is not let go of.
            if let kind = VideoCatalog.transition(id: first.id) {
                editorState.pickTransitionTile(kind)
            } else {
                editorState.selectLibraryItem(first.id)
            }
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
        if let groups = shelfGroups {
            return LibraryShelfLayout.contentHeight(groups: groups, width: shelfWidth, sizing: sizing)
        }
        return LibraryShelfLayout.contentHeight(tileCount: tileCount, width: shelfWidth, sizing: sizing)
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

/// How big the shelf is drawing its tiles, handed from the shelf to every tile
/// view in it through the environment. A tile cannot work this out for itself
/// without measuring, and a tile that measured would draw its first frame at
/// the wrong height and jump; the shelf already knows its width.
struct LibraryTileMetrics: Equatable {
    /// The tile, padding and all.
    var tileWidth: CGFloat
    /// The picture well at the top of the tile.
    var pictureHeight: CGFloat
    /// How wide the picture is drawn when it is picked up and dragged.
    var pictureWidth: CGFloat
    /// How wide the picture well is drawn on the shelf.
    var wellWidth: CGFloat
    /// Whether the tile is the mock's bordered card (`LibraryShelfTile`).
    var isCard: Bool

    init(width: CGFloat, sizing: LibraryShelfLayout.Sizing) {
        tileWidth = LibraryShelfLayout.tileWidth(width: width, sizing: sizing)
        pictureHeight = LibraryShelfLayout.thumbnailHeight(width: width, sizing: sizing)
        wellWidth = LibraryShelfLayout.pictureWidth(width: width, sizing: sizing)
        isCard = sizing.isCard
        // Current's shelf picked its pictures up at the narrowest a tile gets,
        // and keeps doing so; a card is picked up at the size it is drawn.
        pictureWidth = sizing.pictureAspect == nil
            ? LibraryShelfLayout.tileMinimumWidth
            : wellWidth
    }

    /// What a tile draws at anywhere the shelf has not said: Current's tile.
    static let compact = LibraryTileMetrics(width: 0, sizing: .compact)
}

private struct LibraryTileMetricsKey: EnvironmentKey {
    static let defaultValue = LibraryTileMetrics.compact
}

extension EnvironmentValues {
    var libraryTile: LibraryTileMetrics {
        get { self[LibraryTileMetricsKey.self] }
        set { self[LibraryTileMetricsKey.self] = newValue }
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
    /// How big the shelf is drawing its tiles right now (`LibraryTileMetrics`).
    @Environment(\.libraryTile) private var tileMetrics
    let item: LibraryEntry
    let media: DocumentMediaItem
    /// What a double click does instead of placing the picture again: in the
    /// catalog it lands on the timeline at the playhead.
    var open: (() -> Void)?
    @Environment(EditorState.self) private var editorState

    private var isSelected: Bool { editorState.selectedLibraryItemID == item.id }

    var body: some View {
        LibraryShelfTile(name: item.name,
                         meta: LibraryTileCaption.meta(of: media),
                         isSelected: isSelected) { thumbnail }
        .libraryTileClicks(pick: { editorState.selectLibraryItem(item.id) }, open: place)
        // The preview is the picture itself, so a media tile and a component
        // tile are picked up the same way. Nothing in here touches the app's
        // state: a change made while the drag is being handed over redraws the
        // tile and SwiftUI asks for the item all over again.
        .onDrag(dragItem, preview: {
            thumbnail.frame(width: tileMetrics.pictureWidth,
                            height: tileMetrics.pictureHeight)
                .clipShape(RoundedRectangle(cornerRadius: 5))
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

    /// The picture, filling the well the shelf sizes and cropped to it. The
    /// image goes in an OVERLAY rather than a stack: an overlay never gets a
    /// say in its host's size, so a wide screenshot fills the well instead of
    /// stretching the tile across its neighbours.
    private var thumbnail: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(height: tileMetrics.pictureHeight)
            .overlay {
                if let image = editorState.store.image(for: media.image) {
                    // Art (an SVG) sits whole in the middle of its well, the
                    // way the mock's art tiles draw it; a picture fills it.
                    if media.kind == "svg" {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                    } else {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                    }
                }
            }
            .clipped()
    }

    private func place() {
        editorState.selectLibraryItem(item.id)
        if let open { open() } else { editorState.placeLibraryPick() }
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
                Text(item.caption)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .truncationMode(.middle)
                VStack(alignment: .leading, spacing: 2) {
                    detail(item.detail)
                    // A drawing has no pixels of its own to count: it says
                    // what it is instead.
                    if item.kind == "svg" {
                        detail("svg")
                    } else {
                        detail("\(Int(item.image.pixelSize.width)) × "
                            + "\(Int(item.image.pixelSize.height)) px")
                    }
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
