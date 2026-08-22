import AVFoundation
import Foundation
import PhotonzCore

/// Executes a `VideoCommitPlan`: bakes a recording's edits into the stored
/// media file so the file itself is the truth.
///
/// This is the video sibling of the image editor writing its flattened
/// composite back into the capture file (and leaving a layered `.photonz`
/// sidecar so the edit stays reversible). Here the "rich original" is the
/// untouched media, preserved in a hidden sibling folder, and the sidecar
/// records how the visible file was derived from it.
///
/// Ordering matters: the new media is built into scratch **first**, the
/// pre-edit bytes are preserved **second**, and only then is the stored file
/// swapped. A failure at any step leaves the recording exactly as it was.
public enum VideoAssetCommit {

    public enum CommitError: Error {
        /// The plan's source is gone (deleted or renamed under us).
        case missingSource
    }

    /// Apply `plan`. Throws rather than half-applying.
    public static func commit(_ plan: VideoCommitPlan) async throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: plan.source.path) else { throw CommitError.missingSource }

        // Scratch lives in the (hidden) originals folder beside the recording:
        // same volume, so the final swap is atomic, and dot-hidden so the
        // capture-folder scan never lists a half-written file as history.
        let scratchDir = VideoOriginals.url(for: plan.destination).deletingLastPathComponent()
        try fm.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        let ext = plan.destination.pathExtension.isEmpty ? "mp4" : plan.destination.pathExtension
        let scratch = scratchDir.appendingPathComponent(".commit-\(UUID().uuidString).\(ext)")
        defer { try? fm.removeItem(at: scratch) }

        if plan.requiresReencode {
            let seconds = await VideoExporter.duration(of: plan.source)
            try await VideoExporter.exportMP4(from: plan.source, to: scratch,
                                              trim: plan.edits.trim ?? VideoTrim(duration: seconds),
                                              crop: plan.edits.crop)
        } else {
            // No edits left: the stored file goes back to being the original.
            try fm.copyItem(at: plan.source, to: scratch)
        }

        // Preserve the pre-edit bytes before anything overwrites them. Only the
        // FIRST save does this, so the original is always the true original.
        if let original = plan.originalToPreserve {
            try fm.createDirectory(at: original.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try? fm.removeItem(at: original)
            try fm.copyItem(at: plan.destination, to: original)
        }

        // Swap in the new media, keeping the destination's name and metadata —
        // history sorts by creation date, and a save must not reshuffle it.
        if fm.fileExists(atPath: plan.destination.path) {
            _ = try fm.replaceItemAt(plan.destination, withItemAt: scratch)
        } else {
            try fm.moveItem(at: scratch, to: plan.destination)
        }

        // Record how the stored file was derived, so a later session edits from
        // the original and can undo back to it.
        VideoEditsSidecar.save(plan.edits, for: plan.destination)
    }
}
