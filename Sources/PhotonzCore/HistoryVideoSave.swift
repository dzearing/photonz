import Foundation

/// Command S on an edited recording that lives in history.
///
/// History is a folder of files somebody copies or drags into a chat, so the
/// tile has to BE the finished video. One tile per recording, as with a
/// screenshot whose layers are kept beside its flattened PNG:
///
/// - the tile's own file is written over with the edit, as the Export sheet's
///   best MP4 (`choice`);
/// - the recording as it was made is kept in the hidden originals folder
///   (`VideoOriginals`), which is what the edit plays from from then on;
/// - the edit itself is kept beside the tile as a `.photonz` project
///   (`projectURL`), which is what opening the tile opens.
///
/// So editing again and saving again replaces the same file, and taking an
/// edit all the way back to the recording puts the recording back.
public enum HistoryVideoSave {

    /// What Command S does for a window holding a recording.
    public enum Plan: Equatable, Sendable {
        /// Not a recording in history: the save box, as before.
        case askWhere
        /// The recording as it was made, and nothing kept: nothing to write.
        case nothingToDo
        /// Edited back to the recording as it was made: the kept original
        /// goes back on the tile and the project beside it goes away.
        case putTheRecordingBack
        /// Write the project and the finished video. `keepOriginal` is the
        /// first save: the recording as made is kept before anything changes.
        case writeTheEdit(keepOriginal: Bool)
    }

    /// What is true of the window and its file when Command S is pressed.
    public struct Situation: Equatable, Sendable {
        /// The recording's file is in the capture folder history lists.
        public var inHistory: Bool
        /// That file has landed on disk.
        public var fileThere: Bool
        /// The document is the recording exactly as it opens, nothing done.
        public var untouched: Bool
        /// A recording as it was made is already kept for this file.
        public var originalKept: Bool
        /// The edit's clips play the tile's file itself, rather than a kept
        /// original.
        public var playsTheHistoryFile: Bool

        public init(inHistory: Bool, fileThere: Bool, untouched: Bool,
                    originalKept: Bool, playsTheHistoryFile: Bool) {
            self.inHistory = inHistory
            self.fileThere = fileThere
            self.untouched = untouched
            self.originalKept = originalKept
            self.playsTheHistoryFile = playsTheHistoryFile
        }
    }

    public static func plan(_ situation: Situation) -> Plan {
        guard situation.inHistory, situation.fileThere else { return .askWhere }
        if situation.untouched {
            return situation.originalKept && !situation.playsTheHistoryFile ? .putTheRecordingBack : .nothingToDo
        }
        // The file is already an edit of a kept original (an older editor
        // saved it) and this window plays that file: writing over it would
        // throw away the only copy of what the edit is made of.
        if situation.originalKept && situation.playsTheHistoryFile { return .askWhere }
        return .writeTheEdit(keepOriginal: !situation.originalKept)
    }

    /// How the finished video is written: the Export sheet's best MP4, the
    /// recording's own size, all of the edit whatever In and Out are set,
    /// with its captions in the picture, since a pasted file carries nothing
    /// beside it.
    public struct Choice: Hashable, Sendable {
        public let quality: VideoExportQuality
        public let size: VideoExportSize
        public let range: VideoExportRange
        public let captions: CaptionExport
    }

    public static let choice = Choice(quality: .high, size: .full, range: .whole, captions: .burnedIn)

    /// The edit, kept beside the tile under the tile's own name.
    public static func projectURL(for video: URL) -> URL {
        video.deletingPathExtension().appendingPathExtension("photonz")
    }

    /// Where the video is written before it replaces the tile's file: inside
    /// the hidden originals folder, so history never lists a half-written file
    /// and a replace is one rename on the same disk.
    public static func writingURL(for video: URL) -> URL {
        VideoOriginals.url(for: video).deletingLastPathComponent()
            .appendingPathComponent(video.deletingPathExtension().lastPathComponent + " (saving).mp4")
    }

    /// Whether the project beside a video is still that video's edit: as new
    /// as the video or newer (it is written first, and the video lands after),
    /// within the couple of seconds a file system's dates can differ by. A
    /// video written later by something else is the truth, and the project
    /// is left alone.
    public static func projectIsCurrent(projectModified: Date?, videoModified: Date?) -> Bool {
        guard let projectModified, let videoModified else { return false }
        return projectModified >= videoModified.addingTimeInterval(-2)
    }

    /// Videos whose save has not finished, by path, so one cut short by
    /// quitting is finished on the next launch.
    public struct Pending: Equatable, Sendable {
        public private(set) var paths: [String]

        public init(paths: [String] = []) {
            self.paths = []
            for path in paths { add(path) }
        }

        public mutating func add(_ path: String) {
            if !paths.contains(path) { paths.append(path) }
        }

        public mutating func remove(_ path: String) {
            paths.removeAll { $0 == path }
        }
    }
}
