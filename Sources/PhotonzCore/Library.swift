import Foundation

/// The Library's four scopes, in the order the segmented control shows them
/// (`docs/design/ui-building.md`, step B3). A scope is a filter over one flat
/// list of items, not four separate shelves, so search and selection work the
/// same wherever you are standing.
public enum LibraryScope: String, CaseIterable, Hashable, Sendable, Codable {
    case media
    case components
    case styles
    case systems

    /// The scope's full name, used in the panel header and anywhere there is
    /// room for the whole word.
    public var title: String {
        switch self {
        case .media: return "Media"
        case .components: return "Components"
        case .styles: return "Styles"
        case .systems: return "Systems"
        }
    }

    /// The segmented control's label. The dock is narrow, so the two long
    /// names lose their tail rather than squeezing four segments illegibly.
    public var segmentTitle: String {
        switch self {
        case .media: return "Media"
        case .components: return "Comps"
        case .styles: return "Styles"
        case .systems: return "Systems"
        }
    }

    /// One item of this scope, named in the singular. Titles the inspector
    /// section that opens when you pick a tile, so the header says what you
    /// picked rather than "Library item".
    public var itemTitle: String {
        switch self {
        case .media: return "Media"
        case .components: return "Component"
        case .styles: return "Style"
        case .systems: return "System"
        }
    }

    /// The search field's placeholder, so the field says what it will search.
    public var searchPlaceholder: String {
        switch self {
        case .media: return "Search media"
        case .components: return "Search components"
        case .styles: return "Search styles"
        case .systems: return "Search systems"
        }
    }

    /// What an empty scope says for itself. Honest: it says what will fill it,
    /// so nobody wonders whether the panel is broken.
    public var emptyMessage: String {
        switch self {
        case .media: return "Captures you take show up here."
        case .components: return "Components you make will show up here."
        case .styles: return "Colors, text and effects you save will show up here."
        case .systems: return "Design systems you add will show up here."
        }
    }

    /// The empty state, given what is typed in the search field: a scope with
    /// nothing in it explains itself, a search that found nothing says so
    /// instead (otherwise "Components you make will show up here" reads as a
    /// lie the moment you have components and mistyped a word).
    public func emptyMessage(searching query: String) -> String {
        LibrarySearch.normalized(query).isEmpty ? emptyMessage : "Nothing here matches that search."
    }
}

/// One thing on the shelf. Deliberately thin: an id, the scope it lives in, a
/// name, and one line of detail. What a tile draws (a thumbnail, a swatch, a
/// preview) is the app's business; this is what selection, search and the
/// inspector header need.
public struct LibraryEntry: Identifiable, Hashable, Sendable {
    /// Stable across a reload of the list, because the selection is stored as
    /// an id. Media uses the file's path, so a capture stays selected when the
    /// folder is rescanned.
    public let id: String
    public let scope: LibraryScope
    public let name: String
    /// The second line on the tile and in the inspector: when it was taken,
    /// how many uses it has, whatever the scope has to say. May be empty.
    public let detail: String

    public init(id: String, scope: LibraryScope, name: String, detail: String = "") {
        self.id = id
        self.scope = scope
        self.name = name
        self.detail = detail
    }

    /// Identity is the id: two readings of the same file are the same item
    /// even if its detail line (a relative date) has moved on.
    public static func == (lhs: LibraryEntry, rhs: LibraryEntry) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The Library's search: pure list policy, so the field and its filtering are
/// testable away from SwiftUI.
public enum LibrarySearch {
    /// Case- and accent-insensitive, trimmed. Also the form the empty check
    /// runs on, so "   " counts as no search at all.
    public static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// True when every word typed appears somewhere in the name. Words rather
    /// than the whole string, and in any order, so half-remembered names still
    /// land: "9.41 screenshot" finds "Screenshot 2026-09-02 at 9.41".
    public static func matches(name: String, query: String) -> Bool {
        let words = normalized(query).split(separator: " ")
        guard !words.isEmpty else { return true }
        let haystack = normalized(name)
        return words.allSatisfy { haystack.contains($0) }
    }

    /// The items whose name or detail line answer the query, order preserved.
    public static func filter(_ items: [LibraryEntry], query: String) -> [LibraryEntry] {
        guard !normalized(query).isEmpty else { return items }
        return items.filter { matches(name: "\($0.name) \($0.detail)", query: query) }
    }

    /// What one scope shows for a query: its own items, filtered.
    public static func filter(_ items: [LibraryEntry], scope: LibraryScope,
                              query: String) -> [LibraryEntry] {
        filter(items.filter { $0.scope == scope }, query: query)
    }
}

/// What a tile writes under its picture.
///
/// A capture's file name is all prefix and timestamp
/// ("Screenshot 2026-06-21 at 10.30.45"), and a tile is about seventy points
/// wide, so the only part of it that ever fits is the part every one of them
/// shares. For those the caption is when it was taken, which is both what a
/// person is actually scanning for and what the history overlay already writes
/// under the very same files. A file someone named themselves keeps its name.
public enum LibraryNaming {
    /// The prefixes the app (and macOS) give a capture it named itself.
    public static let timestampedPrefixes = ["Screenshot", "Recording"]

    /// True for a name the app made up, false for one a person chose.
    public static func isDefaultCaptureName(_ name: String) -> Bool {
        guard let prefix = timestampedPrefixes.first(where: { name.hasPrefix("\($0) ") })
        else { return false }
        return name.dropFirst(prefix.count + 1).contains(" at ")
    }

    /// The caption for a capture taken at `takenAt`, seen from `now`.
    public static func caption(fileName: String, takenAt: Date, now: Date) -> String {
        isDefaultCaptureName(fileName)
            ? RelativeTime.string(from: takenAt, to: now)
            : fileName
    }
}
