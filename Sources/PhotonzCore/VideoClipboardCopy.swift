import CoreGraphics
import Foundation

/// What Edit ▸ Copy Video and Copy as GIF write, before a frame is drawn.
///
/// Current's recording window copied a trimmed recording to paste into a chat;
/// Next opens a recording in the editor, where the edit is a whole timeline and
/// the only way out was a file. The copy is that file, written into a scratch
/// folder instead of a place somebody picks: the Export sheet's own writer, at
/// the choice the sheet last made for the format, so what is pasted is what the
/// sheet would have saved. There is no second set of settings to learn.
public enum VideoClipboardCopy {

    /// Everything the copy asks the writer for.
    public struct Choice: Hashable, Sendable {
        public var quality: VideoExportQuality
        public var size: VideoExportSize
        /// Captions go into the picture: a pasted file has nowhere to carry a
        /// subtitle file beside it.
        public var captions: CaptionExport
        /// The In to the Out where they are set, all of it otherwise: the
        /// stretch the Export sheet opens on.
        public var range: VideoExportRange
    }

    /// The sheet's remembered quality and size for this format, the size taken
    /// down to Full where this picture is too small for it, exactly as the
    /// sheet itself shows it (`VideoExportSize.offeredOrFull`).
    public static func choice(rememberedQuality: VideoExportQuality,
                              rememberedSize: VideoExportSize,
                              canvasSize: CGSize, format: RecordingFormat) -> Choice {
        Choice(quality: rememberedQuality,
               size: rememberedSize.offeredOrFull(for: canvasSize, format: format),
               captions: .burnedIn, range: .marked)
    }

    /// Whether a file this long is the edit: within one of its own frames of
    /// the edit's length, which is as close as a file cut on a frame grid can
    /// land. How a walk tells the edit from the raw recording it came from.
    public static func runsAsLong(fileMS: Int, asEditMS editMS: Int, fps: Double) -> Bool {
        guard fileMS > 0, editMS > 0 else { return false }
        let frame = 1000 / max(1, fps)
        return Double(abs(fileMS - editMS)) <= frame + 1
    }

    /// Whether a GIF read back runs as long as the edit: its delays, which the
    /// format keeps in hundredths, add up to the edit's length within one
    /// hundredth plus the edit's own rounding to a hundredth
    /// (`GIFFrameTiming`).
    public static func gifRunsAsLong(fileMS: Int, asEditMS editMS: Int) -> Bool {
        guard fileMS > 0, editMS > 0 else { return false }
        let editHundredths = Int((Double(editMS) / 10).rounded()) * 10
        return abs(fileMS - editHundredths) <= 10
    }

    /// The same question for an animated picture, asked of its frames: one
    /// picture for every 1/fps of the edit, within one.
    public static func holdsTheEdit(frames: Int, editMS: Int, fps: Double) -> Bool {
        guard frames > 0, editMS > 0 else { return false }
        let wanted = Int((Double(editMS) / 1000 * max(1, fps)).rounded())
        return abs(frames - max(1, wanted)) <= 1
    }
}

extension RecordingFormat {

    /// The heading on the toast while a copy is being written, naming what is
    /// being made the way `writingTitle` does for an export.
    public var copyingTitle: String {
        switch self {
        case .mp4: return "Copying the video"
        case .gif: return "Copying the GIF"
        case .heic: return "Copying the HEIC"
        }
    }
}
