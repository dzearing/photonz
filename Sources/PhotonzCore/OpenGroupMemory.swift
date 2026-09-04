import Foundation

/// Which groups a picture had open in its layers list, remembered per file.
///
/// Opening a group is not an edit. It does not change a single pixel, it never
/// shows up in undo, and two people looking at the same file have no business
/// forcing their own reading order on each other. So this is kept beside the
/// document, in the app's own settings, exactly like the other things the app
/// remembers about how you were looking at something (which panels were
/// showing, how wide the inspector was, which sections were collapsed) — never
/// inside the file.
///
/// Two rules keep the record from turning into litter:
///
/// - A group that is no longer in the document is dropped, on the way in and
///   on the way out. Delete a group and nothing of it is left behind.
/// - A file whose groups are all shut has no record at all, because "all shut"
///   is what a file with no record already opens as. Tidying up shrinks this
///   rather than growing it.
///
/// Files fall off the end oldest first once there are more than `capacity` of
/// them, so a year of opening pictures cannot grow settings without end.
public struct OpenGroupMemory: Codable, Sendable, Equatable {

    /// How many files are remembered at once. Well past the handful anyone has
    /// in flight, small enough that the whole record stays tiny.
    public static let capacity = 60

    /// One file's open groups, and when they were last touched — which is what
    /// decides who falls off the end.
    public struct Entry: Codable, Sendable, Equatable {
        /// Sorted, so the same set of open groups always writes the same bytes
        /// and an unchanged list is an unchanged write.
        public var groupIDs: [UUID]
        public var usedAt: Date

        public init(groupIDs: [UUID], usedAt: Date) {
            self.groupIDs = groupIDs
            self.usedAt = usedAt
        }
    }

    /// Keyed by the file's path.
    public private(set) var files: [String: Entry]

    public init(files: [String: Entry] = [:]) {
        self.files = files
    }

    public var isEmpty: Bool { files.isEmpty }
    public var fileCount: Int { files.count }

    /// The groups to open when this file comes back on screen, narrowed to the
    /// ones the document still has. `groups` is every group the layers list can
    /// actually open right now.
    public func openGroups(for key: String, stillInDocument groups: Set<UUID>) -> Set<UUID> {
        guard let entry = files[key] else { return [] }
        return Set(entry.groupIDs).intersection(groups)
    }

    /// Writes down what is open now. Anything that is not a group of this
    /// document any more is dropped, and a file with nothing open is forgotten
    /// outright rather than stored empty.
    public mutating func remember(_ open: Set<UUID>, for key: String,
                                  stillInDocument groups: Set<UUID>,
                                  at now: Date = Date()) {
        let kept = open.intersection(groups)
        guard !kept.isEmpty else {
            files[key] = nil
            return
        }
        files[key] = Entry(groupIDs: kept.sorted { $0.uuidString < $1.uuidString }, usedAt: now)
        evictOldest()
    }

    /// Drops a file's record entirely.
    public mutating func forget(_ key: String) {
        files[key] = nil
    }

    private mutating func evictOldest() {
        guard files.count > Self.capacity else { return }
        let stale = files
            .sorted { ($0.value.usedAt, $0.key) < ($1.value.usedAt, $1.key) }
            .prefix(files.count - Self.capacity)
        for (key, _) in stale { files[key] = nil }
    }
}
