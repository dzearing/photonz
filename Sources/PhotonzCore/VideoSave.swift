import CoreGraphics
import Foundation

/// Where a recording's untouched original lives once a save has committed edits
/// into the visible media file.
///
/// The model this supports: **the stored media file is the truth.** Saving a
/// trimmed recording re-encodes the trim into that file, so everything that
/// hands the file out — drag from history, copy to the clipboard, any future
/// consumer — gets the trimmed media without knowing trimming exists. The
/// pre-edit bytes move here first, so the edit stays reversible.
///
/// The original keeps the media extension (AVFoundation reads by type) and
/// hides in a dot-folder beside the recording, which the capture-folder scan
/// skips (`.skipsHiddenFiles` + `.skipsSubdirectoryDescendants`) — so history
/// never lists it.
public enum VideoOriginals {
    /// Hidden sibling folder holding preserved originals.
    public static let folderName = ".photonz-originals"

    /// The preserved-original location for a media file.
    public static func url(for mediaURL: URL) -> URL {
        mediaURL.deletingLastPathComponent()
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(mediaURL.lastPathComponent)
    }

    /// True once a save has preserved this recording's pre-edit bytes.
    public static func exists(for mediaURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: url(for: mediaURL).path)
    }

    /// The file the video editor should edit **from**: the preserved original
    /// when there is one, else the media file itself.
    ///
    /// This mirrors the image editor preferring a capture's layered `.photonz`
    /// sidecar over the flattened PNG. Editing always happens against
    /// full-length source, so repeated saves never stack trims on trims and
    /// clearing the trim can restore the whole clip.
    public static func editSource(for mediaURL: URL) -> URL {
        exists(for: mediaURL) ? url(for: mediaURL) : mediaURL
    }
}

/// What a stored recording already has baked in, and whether the editor's
/// current edits differ from it.
public enum VideoSaveState {
    /// The edits already committed into the media file.
    ///
    /// The `.photonzedits` sidecar records how the visible file was derived
    /// from the preserved original — so it only describes committed state when
    /// an original exists. Without one the file is raw, whatever the sidecar
    /// claims: that is the pre-fix world, where a trim was recorded but never
    /// applied. Reading it as "nothing committed" makes such a recording open
    /// as unsaved, so the user gets a save prompt instead of a silent loss.
    public static func committedEdits(for mediaURL: URL) -> VideoEdits {
        guard VideoOriginals.exists(for: mediaURL) else { return VideoEdits() }
        return VideoEditsSidecar.load(for: mediaURL) ?? VideoEdits()
    }

    /// Seconds of trim drift treated as "the same edit" — far below a video
    /// frame, so re-encoding for it would be busywork.
    public static let timeTolerance: TimeInterval = 1e-4
    /// Pixels of crop drift treated as "the same edit".
    public static let pixelTolerance: CGFloat = 0.5

    /// Whether committing `edits` would change the stored asset.
    public static func needsSave(edits: VideoEdits, committed: VideoEdits) -> Bool {
        !sameTrim(edits.trim, committed.trim) || !sameCrop(edits.crop, committed.crop)
    }

    private static func sameTrim(_ a: VideoTrim?, _ b: VideoTrim?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (lhs?, rhs?):
            return abs(lhs.inPoint - rhs.inPoint) <= timeTolerance
                && abs(lhs.outPoint - rhs.outPoint) <= timeTolerance
        default: return false
        }
    }

    private static func sameCrop(_ a: VideoCrop?, _ b: VideoCrop?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (lhs?, rhs?):
            let l = lhs.rect.standardized, r = rhs.rect.standardized
            return abs(l.minX - r.minX) <= pixelTolerance
                && abs(l.minY - r.minY) <= pixelTolerance
                && abs(l.width - r.width) <= pixelTolerance
                && abs(l.height - r.height) <= pixelTolerance
        default: return false
        }
    }
}

/// What one save has to do to the files on disk. Pure so the ordering rules are
/// testable without AVFoundation; `PhotonzMedia.VideoAssetCommit` executes it.
public struct VideoCommitPlan: Sendable, Hashable {
    /// The asset to derive the new media file from — the preserved original
    /// once there is one, so edits never compose onto already-edited pixels.
    public let source: URL
    /// The media file to overwrite: the recording history hands out.
    public let destination: URL
    /// Where to preserve the pre-edit bytes first, or nil when a previous save
    /// already did (the original is preserved exactly once).
    public let originalToPreserve: URL?
    /// The edits to bake in, measured against `source`.
    public let edits: VideoEdits

    public init(source: URL, destination: URL, originalToPreserve: URL?, edits: VideoEdits) {
        self.source = source
        self.destination = destination
        self.originalToPreserve = originalToPreserve
        self.edits = edits
    }

    /// Empty edits mean the destination is just the source verbatim — a file
    /// copy, no transcode. That is the "revert to the full clip" path.
    public var requiresReencode: Bool { !edits.isEmpty }
}

public enum VideoCommitPlanner {
    /// The plan for committing `edits` into `mediaURL`, or nil when the stored
    /// asset already matches (nothing to save).
    public static func plan(mediaURL: URL, edits: VideoEdits, committed: VideoEdits,
                            hasOriginal: Bool) -> VideoCommitPlan? {
        guard VideoSaveState.needsSave(edits: edits, committed: committed) else { return nil }
        return VideoCommitPlan(
            source: hasOriginal ? VideoOriginals.url(for: mediaURL) : mediaURL,
            destination: mediaURL,
            // Without an original, `committed` is empty, so reaching here means
            // real edits are about to overwrite the only copy of these pixels.
            originalToPreserve: hasOriginal ? nil : VideoOriginals.url(for: mediaURL),
            edits: edits)
    }

    /// Convenience: read the committed state off disk.
    public static func plan(mediaURL: URL, edits: VideoEdits) -> VideoCommitPlan? {
        plan(mediaURL: mediaURL, edits: edits,
             committed: VideoSaveState.committedEdits(for: mediaURL),
             hasOriginal: VideoOriginals.exists(for: mediaURL))
    }
}
