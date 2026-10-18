import Foundation

// The Library's Catalog pivot in a video (task
// `in-a-video-the-library-is-a-catalog-of-things-bu`, mock
// `docs/design/mocks/pages/video-library.html`).
//
// The user, 2026-10-17: "It should be a catalog that is easy to find things
// which can apply to videos ... title page, name plates, animated charts".
// So everything made for video is filed under what it IS, each kind a chip
// with its count, and the shelf shows one kind (or all of them, a group each).
// Components are built for mockups: they sit behind the Built for video
// filter, which is on until a person turns it off.
//
// Pure list policy, like `LibrarySearch`: what a tile draws and what a double
// click does are the app's business.

/// A kind of thing in the catalog, in the order the chips are drawn.
public enum VideoCatalogCategory: String, CaseIterable, Hashable, Codable, Sendable {
    case titlePages
    case nameCards
    /// The charts (`AnimatedChart.swift`): bars, a line, a donut, a big
    /// number and a comparison, each building in.
    case animatedCharts
    case callouts
    case backgrounds
    case transitions
    /// The pictures this document holds: a logo, a product shot.
    case logos
    case endCards
    /// The UI components a mockup is built from. Not made for video.
    case components

    /// The chip's name.
    public var title: String {
        switch self {
        case .titlePages: "Title Pages"
        case .nameCards: "Name Cards"
        case .animatedCharts: "Animated Charts"
        case .callouts: "Callouts"
        case .backgrounds: "Backgrounds"
        case .transitions: "Transitions"
        case .logos: "Logos & Brand"
        case .endCards: "End Cards"
        case .components: "Components"
        }
    }

    /// One of them, named in the singular: an item's detail line, and what
    /// search reads as its kind.
    public var singular: String {
        switch self {
        case .titlePages: "Title Page"
        case .nameCards: "Name Card"
        case .animatedCharts: "Chart"
        case .callouts: "Callout"
        case .backgrounds: "Background"
        case .transitions: "Transition"
        case .logos: "Picture"
        case .endCards: "End Card"
        case .components: "Component"
        }
    }

    /// The quiet word after a group's header, for the one kind that is not
    /// made for video.
    public var note: String? {
        self == .components ? "for mockups" : nil
    }

    /// Whether this kind was made and animated for video, which is what the
    /// Built for video filter keeps.
    public var isBuiltForVideo: Bool { self != .components }
}

/// One tile in the catalog: the entry the shelf captions and searches, and
/// the kind it is filed under.
public struct VideoCatalogItem: Identifiable, Hashable, Sendable {
    public let entry: LibraryEntry
    public let category: VideoCatalogCategory

    public init(entry: LibraryEntry, category: VideoCatalogCategory) {
        self.entry = entry
        self.category = category
    }

    public var id: String { entry.id }
    public var builtForVideo: Bool { category.isBuiltForVideo }
}

/// The tiles under one header.
public struct VideoCatalogGroup: Hashable, Sendable {
    public let category: VideoCatalogCategory
    public let items: [VideoCatalogItem]
}

/// Everything the catalog holds for one document.
public struct VideoCatalog: Hashable, Sendable {
    public let items: [VideoCatalogItem]

    public init(items: [VideoCatalogItem]) {
        self.items = items
    }

    // MARK: Ids

    private static let backgroundPrefix = "catalog.background."
    private static let transitionPrefix = "catalog.transition."

    /// A background's tile id. Never a bare UUID, so it can never be read as
    /// a picture's or a component's.
    public static func backgroundID(_ look: LiveLook) -> String { backgroundPrefix + look.rawValue }
    public static func transitionID(_ kind: ClipTransitionKind) -> String { transitionPrefix + kind.rawValue }

    /// The moving look a tile id names, nil for any other tile.
    public static func background(id: String) -> LiveLook? {
        guard id.hasPrefix(backgroundPrefix) else { return nil }
        return LiveLook(rawValue: String(id.dropFirst(backgroundPrefix.count)))
    }

    public static func transition(id: String) -> ClipTransitionKind? {
        guard id.hasPrefix(transitionPrefix) else { return nil }
        return ClipTransitionKind(rawValue: String(id.dropFirst(transitionPrefix.count)))
    }

    // MARK: Filling it

    /// The catalog for a document: its titles split into pages and name
    /// cards (keeping their shelf ids, so a pick or a drag means what it
    /// always meant), the moving backgrounds, the transitions, the pictures
    /// it holds, and the components it could take.
    public static func assemble(titles: [TitlePreset], backgrounds: [LiveLook],
                                transitions: [ClipTransitionKind], pictures: [LibraryEntry],
                                components: [LibraryEntry]) -> VideoCatalog {
        func item(_ id: String, _ name: String, _ detail: String, _ category: VideoCatalogCategory) -> VideoCatalogItem {
            VideoCatalogItem(entry: LibraryEntry(id: id, scope: .catalog, name: name, detail: detail),
                             category: category)
        }
        var items: [VideoCatalogItem] = []
        for preset in titles {
            let category: VideoCatalogCategory = switch preset.kind {
            case .nameCard: .nameCards
            case .chart: .animatedCharts
            case .titlePage: .titlePages
            }
            items.append(item(preset.id, preset.name, preset.entry.detail, category))
        }
        items += backgrounds.map { item(backgroundID($0), $0.title, VideoCatalogCategory.backgrounds.singular,
                                        .backgrounds) }
        items += transitions.map { item(transitionID($0), $0.title, VideoCatalogCategory.transitions.singular,
                                        .transitions) }
        items += pictures.map { item($0.id, $0.name, VideoCatalogCategory.logos.singular, .logos) }
        items += components.map { item($0.id, $0.name, VideoCatalogCategory.components.singular, .components) }
        return VideoCatalog(items: items)
    }

    // MARK: Reading it

    /// The items a search and the filter keep, across every category. Search
    /// reads the name, the detail line and the kind's own names, so "name
    /// card" finds every name card and "transition" every transition.
    private func kept(query: String, builtForVideoOnly: Bool) -> [VideoCatalogItem] {
        items.filter { item in
            guard !builtForVideoOnly || item.builtForVideo else { return false }
            return LibrarySearch.matches(
                name: "\(item.entry.name) \(item.entry.detail) \(item.category.title) \(item.category.singular)",
                query: query)
        }
    }

    /// The chips: every kind with something in it, and how many, in order.
    /// While a search is typed the counts are what it found.
    public func categories(builtForVideoOnly: Bool, query: String = "")
        -> [(category: VideoCatalogCategory, count: Int)] {
        let kept = kept(query: query, builtForVideoOnly: builtForVideoOnly)
        return VideoCatalogCategory.allCases.compactMap { category in
            let count = kept.count { $0.category == category }
            return count > 0 ? (category, count) : nil
        }
    }

    /// What the shelf draws: one group per kind with something to show. A
    /// picked category narrows it to that kind; a search runs across every
    /// kind whatever is picked, because a person typing a name does not know
    /// (or care) which chip it lives under.
    public func groups(category: VideoCatalogCategory?, query: String,
                       builtForVideoOnly: Bool) -> [VideoCatalogGroup] {
        let searching = !LibrarySearch.normalized(query).isEmpty
        let kept = kept(query: query, builtForVideoOnly: builtForVideoOnly)
        return VideoCatalogCategory.allCases.compactMap { kind in
            if !searching, let category, category != kind { return nil }
            let inKind = kept.filter { $0.category == kind }
            return inKind.isEmpty ? nil : VideoCatalogGroup(category: kind, items: inKind)
        }
    }

    /// The category to open on, from the one remembered: it stands while it
    /// still has a chip, otherwise the shelf opens on All (nil).
    public static func resolvedCategory(_ stored: String?,
                                        shown: [VideoCatalogCategory]) -> VideoCatalogCategory? {
        guard let stored, let category = VideoCatalogCategory(rawValue: stored),
              shown.contains(category) else { return nil }
        return category
    }
}

// MARK: - A moving background off the catalog

extension VideoCatalog {
    /// How long a background runs when it lands: a still's five seconds,
    /// Premiere's default for a generator as for a picture.
    public static let backgroundLengthMS = PictureClip.lengthMS

    /// The colours each look is offered in: the curated title themes taken in
    /// turn, so ten tiles never read as one tile ten times.
    public static func backgroundTheme(_ look: LiveLook) -> TitleTheme {
        let themes = TitleTheme.curated
        let index = LiveLook.allCases.firstIndex(of: look) ?? 0
        return themes[index % max(1, themes.count)]
    }

    /// The paint a background tile plays and a landed background wears.
    public static func backgroundPaint(_ look: LiveLook) -> Paint {
        let theme = backgroundTheme(look)
        return Paint(hex: theme.ground, kind: .live, stops: theme.liveStops, live: LiveBackdrop(look: look))
    }
}

extension PhotonzDocument {

    /// Where a background lands: as a picture does, laid over what is there
    /// on a free track or a new one called Gfx, never cutting a clip.
    public func backgroundLanding(atMS ms: Int, over pointed: TrackDrop?) -> ClipLanding {
        titleLanding(lengthMS: VideoCatalog.backgroundLengthMS, atMS: ms, over: pointed,
                     newTrackNamed: DocumentTrack.graphicsTrackName)
    }

    /// A moving background, the whole frame, where `landing` says: one
    /// ordinary filled rectangle wearing the look, so everything a shape takes
    /// (a fade, keys, a title over it) it takes. Nil, and nothing changed,
    /// where the landing is refused.
    @discardableResult
    public mutating func landBackground(_ look: LiveLook, at landing: ClipLanding) -> UUID? {
        let start = max(0, landing.startMS)
        var layer = TitlePen(canvas: canvasSize).fullFrame(VideoCatalog.backgroundPaint(look))
        layer.name = look.title
        layer.time = LayerTime(inMS: start, outMS: start + max(LayerTime.shortestMS, landing.lengthMS))
        return land(layer, at: landing)
    }
}
