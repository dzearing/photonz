import Foundation

/// What a capture entry holds. Screenshots are still images; recordings are
/// videos.
public enum CaptureKind: String, Hashable, Codable, Sendable {
    case image
    case video
}

/// One capture — a media file in the capture folder. The folder is the single
/// source of truth (no private index): an entry is just a file URL plus the bits
/// derived from it. Identity is the URL, so history reflects the folder exactly.
public struct CaptureEntry: Hashable, Sendable, Identifiable {
    public let url: URL
    public let createdAt: Date
    public let kind: CaptureKind

    public var id: URL { url }
    public var fileName: String { url.lastPathComponent }

    public init(url: URL, createdAt: Date, kind: CaptureKind) {
        self.url = url
        self.createdAt = createdAt
        self.kind = kind
    }
}

/// Pure, testable policy for reading a capture folder: which file extensions
/// count as captures (and as which kind), and newest-first ordering. The actual
/// filesystem scan + watching is the app's `CaptureStore`.
public enum CaptureLibrary {
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "bmp"]
    public static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    /// Classify a path extension; nil for non-media files (so the scan skips
    /// `index.json`, `.DS_Store`, etc.).
    public static func kind(forPathExtension ext: String) -> CaptureKind? {
        let e = ext.lowercased()
        if imageExtensions.contains(e) { return .image }
        if videoExtensions.contains(e) { return .video }
        return nil
    }

    /// True if a file extension is a capture we should surface.
    public static func isCapture(pathExtension ext: String) -> Bool {
        kind(forPathExtension: ext) != nil
    }

    /// Newest first (the order the history strip shows). Ties broken by file name
    /// so ordering is stable/deterministic.
    public static func sortedNewestFirst(_ entries: [CaptureEntry]) -> [CaptureEntry] {
        entries.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.fileName > $1.fileName
        }
    }
}
