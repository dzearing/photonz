import CoreGraphics
import Foundation

/// What the Export sheet is allowed to say about a recording before it writes
/// one, and what it must refuse to say.
///
/// The picture sheet answers "how big will this be" by encoding the picture
/// (`ExportSizer`), which costs a few hundred milliseconds and is therefore
/// worth doing while somebody watches. A recording has no equivalent: weighing
/// a GIF is writing the GIF, frame by frame, which for a minute of screen is
/// minutes of work. So this draws the line between the two answers that ARE
/// honest and the one that is not:
///
/// - An untouched recording saved as MP4 is copied verbatim, so its size is
///   already known to the byte.
/// - A trimmed or cropped MP4 is re-encoded, and the only honest estimate comes
///   from what the recording itself already costs per second and per pixel.
///   Both are measured from the file on disk rather than assumed, and the line
///   says "about" so nobody reads it as a promise.
/// - A GIF or a HEIC is re-encoded into a different container entirely, and
///   nothing about the MP4 predicts it. The sheet says what it does know, the
///   pixels, the frame rate and the length, and says plainly that the size
///   comes with the file.
///
/// Everything here is pure: the sheet, the walk and the tests all read the same
/// sentences.
public enum RecordingExport {

    /// What the app knows about the recording being exported, in the order the
    /// sheet needs it.
    public struct Source: Sendable, Hashable {
        /// Length of the file the export reads from, in seconds.
        public var sourceDuration: TimeInterval
        /// How much of it survives the trim and the cuts.
        public var keptDuration: TimeInterval
        /// The recording's own pixel size, oriented.
        public var sourceSize: CGSize
        /// The crop's pixel size, when there is a crop. Nil means the whole
        /// frame.
        public var cropSize: CGSize?
        /// What the file on disk weighs, in bytes. Zero when it could not be
        /// read, which is what takes the estimate away rather than zeroing it.
        public var fileBytes: Int
        /// Whether anything about the recording has been changed, which is what
        /// decides between a file copy and a re-encode.
        public var isEdited: Bool

        public init(sourceDuration: TimeInterval, keptDuration: TimeInterval,
                    sourceSize: CGSize, cropSize: CGSize? = nil,
                    fileBytes: Int, isEdited: Bool) {
            self.sourceDuration = sourceDuration
            self.keptDuration = keptDuration
            self.sourceSize = sourceSize
            self.cropSize = cropSize
            self.fileBytes = fileBytes
            self.isEdited = isEdited
        }
    }

    /// How well the size of the file about to be written is known.
    public enum Weight: Sendable, Hashable {
        /// The file is copied, so this is its size to the byte.
        case exact(Int)
        /// Worked out from what this very recording already costs. Close, and
        /// said as an estimate.
        case about(Int)
        /// Not knowable without writing the whole thing.
        case unknown
    }

    /// The formats a recording can leave the app as, in the order they sit on
    /// the sheet: the one nearly everybody wants first.
    public static let formats: [RecordingFormat] = [.mp4, .gif, .heic]

    /// The name on the segmented row. Short, so three of them and their label
    /// fit the sheet's width without the word beside them breaking.
    public static func shortName(_ format: RecordingFormat) -> String {
        format.rawValue.uppercased()
    }

    /// Whether this format has a size/rate preset worth choosing.
    ///
    /// GIF and HEIC do: the preset is what decides how big the frames are and
    /// how many of them there are. MP4 has no such control today, and a row
    /// that changes nothing is worse than no row, so the sheet leaves it out
    /// exactly as it leaves the quality slider out for PNG.
    public static func offersQuality(_ format: RecordingFormat) -> Bool {
        format.isAnimatedImage
    }

    /// Whether the export is a file copy rather than a re-encode. Only an
    /// untouched recording going out as MP4, which is what keeps that case
    /// instant and byte-identical.
    public static func copiesVerbatim(format: RecordingFormat, source: Source) -> Bool {
        format == .mp4 && !source.isEdited
    }

    /// The pixel size the written file will really have.
    public static func outputSize(format: RecordingFormat, quality: VideoExportQuality,
                                  source: Source) -> CGSize {
        let base = source.cropSize ?? source.sourceSize
        guard format.isAnimatedImage else { return base }
        guard base.width > 0, base.height > 0 else { return base }
        return Geometry.downscaledToFit(base, maxDimension: quality.maxDimension)
    }

    /// How well the size is known, and the best honest number where one exists.
    public static func weight(format: RecordingFormat, source: Source) -> Weight {
        // A different container, written frame by frame. The MP4's weight says
        // nothing about it.
        guard format == .mp4 else { return .unknown }
        guard source.fileBytes > 0, source.sourceDuration > 0 else { return .unknown }
        if copiesVerbatim(format: format, source: source) { return .exact(source.fileBytes) }

        // Two ratios, both measured off this recording: the share of the
        // seconds that survive, and the share of the pixels. Neither is a
        // constant somebody picked.
        let seconds = min(max(0, source.keptDuration) / source.sourceDuration, 1)
        let pixels = pixelShare(source)
        let estimate = Int((Double(source.fileBytes) * seconds * pixels).rounded())
        guard estimate > 0 else { return .unknown }
        return .about(estimate)
    }

    /// What share of the recording's pixels survive the crop, never more than
    /// all of them.
    private static func pixelShare(_ source: Source) -> Double {
        let whole = source.sourceSize.width * source.sourceSize.height
        guard let crop = source.cropSize, whole > 0 else { return 1 }
        let kept = crop.width * crop.height
        guard kept > 0 else { return 1 }
        return min(Double(kept / whole), 1)
    }

    /// The one line under the format: what the file is, and what it costs.
    ///
    /// The same shape as the picture sheet's line, so the eye looking for the
    /// size finds it in the same place and reads it in the same words.
    public static func sizeLine(format: RecordingFormat, source: Source) -> String {
        let name = format.displayName
        switch weight(format: format, source: source) {
        case .exact(let bytes):
            return "\(name) · \(ExportQuality.fileSize(bytes: bytes))"
        case .about(let bytes):
            return "\(name) · about \(ExportQuality.fileSize(bytes: bytes))"
        case .unknown:
            return "\(name) · size not known until it is written"
        }
    }

    /// The line where the picture sheet writes its pixel size: how big the
    /// file's picture is, how fast it runs where that is chosen, and how much
    /// of the recording is in it.
    public static func shapeLine(format: RecordingFormat, quality: VideoExportQuality,
                                 source: Source) -> String {
        var parts: [String] = []
        let size = outputSize(format: format, quality: quality, source: source)
        if size.width >= 1, size.height >= 1 {
            parts.append("\(Int(size.width.rounded())) × \(Int(size.height.rounded())) px")
        }
        if offersQuality(format) {
            parts.append("\(Int(quality.targetFPS.rounded())) fps")
        }
        parts.append(lengthPhrase(source))
        return parts.joined(separator: " · ")
    }

    /// How long the written file runs, and what it was cut from when those are
    /// different, so the trim is legible on the sheet about to write it.
    private static func lengthPhrase(_ source: Source) -> String {
        let kept = RecordingClock.elapsedString(source.keptDuration)
        let whole = RecordingClock.elapsedString(source.sourceDuration)
        return kept == whole ? kept : "\(kept) of \(whole)"
    }

    /// What the save box opens on: the recording's own name, wearing the
    /// extension of the format that was actually chosen.
    public static func suggestedFileName(recording: String,
                                         format: RecordingFormat) -> String {
        let base = URL(fileURLWithPath: recording).deletingPathExtension().lastPathComponent
        let name = base.isEmpty ? "Recording" : base
        return "\(name).\(format.fileExtension)"
    }
}
