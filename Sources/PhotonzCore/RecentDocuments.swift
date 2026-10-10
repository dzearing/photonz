import Foundation

/// One document you opened or saved: where it is and when you last used it.
public struct RecentDocument: Codable, Hashable, Sendable, Identifiable {
    public let url: URL
    public let usedAt: Date

    public var id: URL { url }
    /// The name a person knows it by: the file's, without its extension.
    public var name: String { url.deletingPathExtension().lastPathComponent }

    public init(url: URL, usedAt: Date) {
        self.url = url
        self.usedAt = usedAt
    }
}

/// The documents you opened and saved, newest first (Next,
/// `next-recent-documents`). What File > Open Recent lists, and what the
/// front door's Recent puts among your captures.
///
/// The app is a menu bar agent with no Dock icon and no `NSDocument`, so the
/// Mac's own recent list has nowhere to show and no dates to say "2 hours
/// ago" with; this is the one list both places read.
public struct RecentDocuments: Codable, Hashable, Sendable {
    /// The Mac's usual length for Open Recent.
    public static let limit = 10

    public private(set) var items: [RecentDocument]

    public init(items: [RecentDocument] = []) {
        self.items = items
    }

    /// `url` was opened or saved at `date`: it goes to the top, once.
    public mutating func note(_ url: URL, at date: Date) {
        let file = url.standardizedFileURL
        items.removeAll { $0.url.standardizedFileURL == file }
        items.insert(RecentDocument(url: file, usedAt: date), at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
    }

    public mutating func remove(_ url: URL) {
        let file = url.standardizedFileURL
        items.removeAll { $0.url.standardizedFileURL == file }
    }

    /// Clear Menu.
    public mutating func clear() {
        items.removeAll()
    }

    /// What File > Open Recent calls each of `documents`: the file's name,
    /// and where two share a name, the folder each is in after it, the way
    /// the Mac's own Open Recent tells them apart.
    public static func menuTitles(_ documents: [RecentDocument]) -> [String] {
        let names = documents.map(\.url.lastPathComponent)
        return documents.map { document in
            let name = document.url.lastPathComponent
            guard names.filter({ $0 == name }).count > 1 else { return name }
            return "\(name) (\(document.url.deletingLastPathComponent().lastPathComponent))"
        }
    }

    /// The ones still there to open: a file moved or deleted since is not
    /// offered, the way the Mac's own Open Recent leaves it out.
    public func existing(where exists: (URL) -> Bool) -> [RecentDocument] {
        items.filter { exists($0.url) }
    }
}
