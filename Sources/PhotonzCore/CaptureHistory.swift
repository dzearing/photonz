import Foundation

/// One taken screenshot. The pixels live on disk (see `fileName`); the model
/// stays value-typed and tiny, mirroring how documents reference ImageStore.
public struct CaptureEntry: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let createdAt: Date

    public init(id: UUID = UUID(), createdAt: Date) {
        self.id = id
        self.createdAt = createdAt
    }

    /// On-disk name inside the captures directory.
    public var fileName: String { "capture-\(id.uuidString).png" }
}

/// Newest-first list of captures with a size cap. Pure policy — persistence
/// (PNG files, the captures directory) is the app's job, so pruning/removal
/// hand back the affected entries for the caller to delete from disk.
public struct CaptureHistory: Hashable, Codable, Sendable {
    public private(set) var entries: [CaptureEntry]
    public var limit: Int

    public init(entries: [CaptureEntry] = [], limit: Int = 50) {
        self.entries = entries.sorted { $0.createdAt > $1.createdAt }
        self.limit = limit
    }

    /// Inserts a capture and returns any entries pruned to stay within `limit`.
    @discardableResult
    public mutating func add(_ entry: CaptureEntry) -> [CaptureEntry] {
        let index = entries.firstIndex { $0.createdAt <= entry.createdAt } ?? entries.count
        entries.insert(entry, at: index)
        guard entries.count > limit else { return [] }
        let pruned = Array(entries.suffix(from: limit))
        entries.removeSubrange(limit...)
        return pruned
    }

    /// Removes a capture, returning it so the caller can delete its file.
    @discardableResult
    public mutating func remove(id: UUID) -> CaptureEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.remove(at: index)
    }
}
