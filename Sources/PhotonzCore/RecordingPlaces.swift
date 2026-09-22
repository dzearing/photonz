import Foundation

/// Where you were in each recording you have opened.
///
/// Coming back to a recording you were working on and being put at the very
/// start again is the small tax that makes a tool feel like it is not paying
/// attention. This remembers the moment the playhead was on, per recording, and
/// hands it back when the same recording is opened again.
///
/// It is APP state, not document state, for the same reason `MovieLibrary` is:
/// a recording that travels to another machine does not carry where somebody
/// else was up to in it. It is also deliberately forgetful:
///
/// - A moment in the first second and a half is where a recording opens anyway,
///   so it is not worth remembering and any older memory of that recording is
///   dropped with it. Same for a moment at the very end: you watched it out.
/// - A recording whose file has changed since (a save wrote the trim into it)
///   has its moment forgotten, because the old moment could be past the end of
///   the new file.
/// - Only the last `limit` recordings are kept, newest first.
public struct RecordingPlaces: Codable, Sendable, Equatable {
    public struct Place: Codable, Sendable, Equatable {
        /// The recording's file path.
        public var path: String
        /// Where the playhead was, in milliseconds.
        public var momentMS: Int
        /// What the file looked like when the moment was noted (size and
        /// modification time), so a recording rewritten since is not resumed
        /// into the wrong place.
        public var stamp: String
        public var notedAt: Date

        public init(path: String, momentMS: Int, stamp: String, notedAt: Date) {
            self.path = path
            self.momentMS = momentMS
            self.stamp = stamp
            self.notedAt = notedAt
        }
    }

    /// Newest first.
    public private(set) var places: [Place]

    /// How many recordings are remembered at once.
    public static let limit = 40
    /// A moment this near the start is where the recording opens anyway.
    public static let ignoreFirstMS = 1500
    /// A moment this near the end means it was watched out.
    public static let ignoreLastMS = 1000

    public init(places: [Place] = []) {
        self.places = places
    }

    /// Note where the playhead is in `path`. A moment not worth remembering
    /// forgets the recording instead, so coming back really does start it over.
    public mutating func remember(path: String, momentMS: Int, durationMS: Int,
                                  stamp: String, at now: Date = .now) {
        places.removeAll { $0.path == path }
        guard Self.isWorthRemembering(momentMS: momentMS, durationMS: durationMS) else { return }
        places.insert(Place(path: path, momentMS: momentMS, stamp: stamp, notedAt: now), at: 0)
        if places.count > Self.limit { places.removeLast(places.count - Self.limit) }
    }

    /// Where to put the playhead when `path` opens again, or nil to start at the
    /// beginning. The length is asked for again rather than trusted, so a
    /// moment that no longer lands inside the recording simply starts over.
    public func moment(forPath path: String, stamp: String, durationMS: Int) -> Int? {
        guard let place = places.first(where: { $0.path == path }), place.stamp == stamp,
              Self.isWorthRemembering(momentMS: place.momentMS, durationMS: durationMS)
        else { return nil }
        return place.momentMS
    }

    /// Forget one recording, for a file that has gone.
    public mutating func forget(path: String) {
        places.removeAll { $0.path == path }
    }

    static func isWorthRemembering(momentMS: Int, durationMS: Int) -> Bool {
        guard durationMS > 0 else { return false }
        guard momentMS > ignoreFirstMS else { return false }
        return momentMS < durationMS - ignoreLastMS
    }
}
