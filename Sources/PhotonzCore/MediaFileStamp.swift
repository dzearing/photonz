import Foundation

// Telling a file from another that took its name.
//
// A recording is known by where it is, and a path on its own is not enough: an
// export or a re-record puts a different file at the same path, and everything
// kept for the old one (decoded frames, timeline pictures, the waveform, its
// length and size) is wrong for the new one. So a file is its path AND what it
// was when it was read, and one that has changed since is a different file.

/// What a file was when it was read.
public struct MediaFileStamp: Hashable, Codable, Sendable {
    public let bytes: Int64
    /// When it was last written, in nanoseconds: a whole second is long enough
    /// to write a file over another.
    public let modifiedNS: Int64
    /// Which file on its disk it is, so one swapped in with the same size and
    /// date is still seen.
    public let fileID: UInt64

    public init(bytes: Int64, modifiedNS: Int64, fileID: UInt64) {
        self.bytes = bytes
        self.modifiedNS = modifiedNS
        self.fileID = fileID
    }

    /// The stamp of the file at `url` now, nil where there is none. One system
    /// call: nothing in the file is read.
    public static func of(_ url: URL) -> MediaFileStamp? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return MediaFileStamp(
            bytes: Int64(info.st_size),
            modifiedNS: Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec),
            fileID: UInt64(info.st_ino))
    }

    /// Whether two files hold the same thing as far as can be told without
    /// reading them, wherever each is: what a project moved to another disk
    /// with its footage can be asked.
    public func sameContents(as other: MediaFileStamp) -> Bool {
        bytes == other.bytes && modifiedNS == other.modifiedNS
    }
}

/// Which reference each file goes by, for as long as it is that file.
public struct MediaIdentities<Ref> {
    private var entries: [URL: (ref: Ref, stamp: MediaFileStamp?)] = [:]

    public init() {}

    /// The reference for the file at `url`, if it is still the file that
    /// reference was given to.
    public func known(at url: URL, stamp: MediaFileStamp?) -> Ref? {
        guard let stamp, let entry = entries[url], entry.stamp == stamp else { return nil }
        return entry.ref
    }

    /// The reference last filed at `url`, whatever has happened to it since.
    public func filed(at url: URL) -> Ref? { entries[url]?.ref }

    public mutating func file(_ ref: Ref, at url: URL, stamp: MediaFileStamp?) {
        entries[url] = (ref, stamp)
    }

    /// The same file, played from somewhere else from now on.
    public mutating func relocate(from old: URL, to new: URL, stamp: MediaFileStamp?) {
        guard let entry = entries.removeValue(forKey: old) else { return }
        entries[new] = (entry.ref, stamp)
    }
}
