import AppKit
import PhotonzCore
import SwiftUI

// MARK: - The Library shelf (Next, `next-library`)

/// The Library: one shelf with four scopes, living in the right dock as an
/// ordinary panel group (`docs/design/ui-building.md`, step B3). It is not a
/// browser window and not a mode — someone who only captures and redlines
/// never turns it on, and the dock without it is the dock they have today.
///
/// What is here now is the shelf itself and the one scope that has something
/// real to hold: **Media** shows the captures the app already keeps in the
/// capture folder, so the panel is useful the first time it opens rather than
/// four empty boxes. Components, Styles and Systems arrive with the steps that
/// create them, and until then each says so in plain words.
///
/// Selection is the app's one selection: picking a tile clears the layer and
/// canvas selection and opens the item's section in this same dock, exactly
/// the way picking a layer opens its sections.
struct LibraryPanel: View {
    @Environment(EditorState.self) private var editorState
    @Environment(AppCoordinator.self) private var coordinator
    /// The scope you were last in, remembered across launches (and read by the
    /// section header, so a collapsed Library still says what it is set to).
    @AppStorage(LibraryPanel.scopeKey) private var scopeRaw = LibraryScope.media.rawValue
    /// The tile area's max height, resizable and persisted, the same way the
    /// layers area is: a long shelf must not shove the rest of the dock off
    /// the bottom.
    @AppStorage("inspector.libraryHeight") private var maxHeight = 220.0
    @State private var query = ""

    static let scopeKey = "library.scope"
    static let minHeight: CGFloat = 104
    static let maxAllowedHeight: CGFloat = 560
    /// How many tiles one scope draws at once. Search runs over everything and
    /// only the result is capped, so an older capture is still reachable by
    /// name — this is a cap on how many full-size images the grid loads, not
    /// on what the Library knows about.
    static let maxTiles = 60

    private var scope: LibraryScope { LibraryScope(rawValue: scopeRaw) ?? .media }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            scopePicker
            searchField
            tiles
            resizeHandle
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        // Switching scope with a search still running would show an empty
        // shelf for a reason that is not on screen anymore.
        .onChange(of: scopeRaw) { query = "" }
    }

    // MARK: Scope and search

    private var scopePicker: some View {
        Picker("Scope", selection: $scopeRaw) {
            ForEach(LibraryScope.allCases, id: \.self) { scope in
                Text(scope.segmentTitle).tag(scope.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .help("What the shelf is showing")
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
                // flow every search field on the Mac already has.
                .onSubmit { selectFirstTile() }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
    }

    // MARK: Tiles

    /// Every capture the app knows about, as library items. The name is the
    /// file without its extension and the detail is how long ago it was taken,
    /// and search reads both, so "png yesterday" narrows as well as a name.
    private var mediaEntries: [CaptureEntry] { coordinator.capture.store.entries }

    private func item(for entry: CaptureEntry) -> LibraryEntry {
        let fileName = entry.url.deletingPathExtension().lastPathComponent
        // The caption is what fits and what helps ("4 minutes ago"); the file
        // name rides along as the detail so search still finds it by name and
        // the item's own section can print it in full.
        return LibraryEntry(id: entry.url.path,
                            scope: .media,
                            name: LibraryNaming.caption(fileName: fileName,
                                                        takenAt: entry.createdAt, now: .now),
                            detail: fileName)
    }

    /// The tiles Media draws for what is typed.
    private var visibleEntries: [CaptureEntry] {
        guard scope == .media else { return [] }
        let entries = mediaEntries
        let byID = Dictionary(entries.map { ($0.url.path, $0) }, uniquingKeysWith: { first, _ in first })
        let hits = LibrarySearch.filter(entries.map(item(for:)), query: query)
        return hits.prefix(Self.maxTiles).compactMap { byID[$0.id] }
    }

    /// The tiles Components draws for what is typed: the mains in the open
    /// document, each paired with the layer it stands for so the tile can draw
    /// a picture of it (Next, `next-components`).
    private var visibleComponents: [(entry: LibraryEntry, layer: Layer)] {
        guard scope == .components, let document = editorState.document else { return [] }
        let hits = LibrarySearch.filter(editorState.componentEntries, query: query)
        return hits.prefix(Self.maxTiles).compactMap { entry in
            guard let id = UUID(uuidString: entry.id),
                  let layer = document.mainComponent(componentID: id) else { return nil }
            return (entry, layer)
        }
    }

    /// Whether this scope has anything to show at all, whatever the search
    /// says. The empty state and the resize grabber both hang off this.
    private var isEmpty: Bool {
        visibleEntries.isEmpty && visibleComponents.isEmpty
    }

    @ViewBuilder
    private var tiles: some View {
        if isEmpty {
            // An empty shelf takes only the room its sentence needs. Measuring
            // a full one is not on: a lazy grid materialises the rows you can
            // see, so asking it how tall it is answers with how tall it was
            // told to be.
            emptyState
        } else {
            ScrollView(.vertical) { grid }
                .frame(height: maxHeight)
                .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 8)],
                  alignment: .leading, spacing: 8) {
            ForEach(visibleEntries) { entry in
                LibraryTile(item: item(for: entry), entry: entry,
                            store: coordinator.capture.store)
            }
            ForEach(visibleComponents, id: \.entry.id) { pair in
                LibraryComponentTile(entry: pair.entry, layer: pair.layer)
            }
        }
        .padding(.vertical, 2)
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

    /// Return in the search field picks the first tile showing, so the shelf
    /// can be worked without the pointer.
    private func selectFirstTile() {
        if let first = visibleEntries.first {
            editorState.selectLibraryItem(first.url.path)
        } else if let first = visibleComponents.first {
            editorState.selectLibraryItem(first.entry.id)
        }
    }

    @ViewBuilder
    private var resizeHandle: some View {
        // Nothing to resize while the shelf is empty, so no grab bar either.
        if !isEmpty {
            PanelAreaResizeHandle(maxHeight: $maxHeight,
                              currentHeight: maxHeight,
                              minHeight: Self.minHeight,
                              maxAllowedHeight: Self.maxAllowedHeight,
                              help: "Drag to resize the Library")
        }
    }
}

/// One thing on the shelf: a thumbnail with its name underneath. Click picks
/// it (which is the app's one selection, so the canvas lets go), double click
/// places it, and it drags onto the canvas as the file it is.
private struct LibraryTile: View {
    let item: LibraryEntry
    let entry: CaptureEntry
    let store: CaptureStore
    @Environment(EditorState.self) private var editorState

    private var isSelected: Bool { editorState.selectedLibraryItemID == item.id }

    var body: some View {
        VStack(spacing: 3) {
            thumbnail
            Text(item.name)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .frame(maxWidth: .infinity)
        .padding(4)
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
        // The canvas already accepts a dropped image file (from Finder, from
        // the history overlay), so dragging a tile onto it needs nothing new.
        .onDrag {
            editorState.selectLibraryItem(item.id)
            return NSItemProvider(contentsOf: entry.url) ?? NSItemProvider()
        }
        .help("\(item.name) • \(item.detail). Double click to place it.")
    }

    /// The picture, filling a fixed 44pt-tall well and cropped to it. The
    /// image goes in an OVERLAY rather than a stack: an overlay never gets a
    /// say in its host's size, so a wide screenshot fills the well instead of
    /// stretching the tile across its neighbours.
    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(.quaternary)
            .frame(height: 44)
            .overlay {
                if let image = store.image(for: entry) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay {
                if entry.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
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
/// or Text section plays for a layer. Media is the only scope with items so
/// far, so this describes a capture — its size, when it was taken, and the two
/// things worth doing with it.
struct LibraryItemInspector: View {
    @Environment(EditorState.self) private var editorState
    @Environment(AppCoordinator.self) private var coordinator

    private var entry: CaptureEntry? {
        guard let id = editorState.selectedLibraryItemID else { return nil }
        return coordinator.capture.store.entries.first { $0.url.path == id }
    }

    var body: some View {
        if let entry {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.url.deletingPathExtension().lastPathComponent)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .truncationMode(.middle)
                VStack(alignment: .leading, spacing: 2) {
                    detail(RelativeTime.string(from: entry.createdAt, to: .now))
                    if let size = pixelSize(of: entry) { detail(size) }
                    detail(entry.url.pathExtension.uppercased())
                }
                HStack(spacing: 6) {
                    Button("Place in Picture") {
                        editorState.placeLibraryPick()
                    }
                    .controlSize(.small)
                    .help("Adds this capture to the open picture as a new layer")
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                    }
                    .controlSize(.small)
                    .help("Shows the file in the Finder")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func pixelSize(of entry: CaptureEntry) -> String? {
        guard let image = coordinator.capture.store.image(for: entry) else { return nil }
        return "\(image.width) × \(image.height) px"
    }
}
