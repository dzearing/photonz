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
/// - Any other MP4 is re-encoded, and the estimate is the smaller of two
///   numbers: the budget the export ASKS the encoder for, which is a number we
///   choose and so a ceiling we can trust (`VideoExportRecipe`), and what this
///   very recording already costs per second and per pixel, measured off the
///   file on disk. The line says "about", because an encoder spends less than
///   its budget on an easy picture and nobody should read it as a promise.
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
        /// How fast the recording itself runs. What a preset caps rather than
        /// what it sets: nothing is ever sped up.
        public var sourceFPS: Double
        /// Whether the recording carries any sound, which is the difference
        /// between a budget for pictures and a budget for both.
        public var hasAudio: Bool
        /// Where the playhead is, in seconds. Only one answer uses it — the
        /// picture, which is a frame of a particular moment and says which.
        public var playheadTime: TimeInterval

        public init(sourceDuration: TimeInterval, keptDuration: TimeInterval,
                    sourceSize: CGSize, cropSize: CGSize? = nil,
                    fileBytes: Int, isEdited: Bool,
                    sourceFPS: Double = 30, hasAudio: Bool = false,
                    playheadTime: TimeInterval = 0) {
            self.sourceDuration = sourceDuration
            self.keptDuration = keptDuration
            self.sourceSize = sourceSize
            self.cropSize = cropSize
            self.fileBytes = fileBytes
            self.isEdited = isEdited
            self.sourceFPS = sourceFPS
            self.hasAudio = hasAudio
            self.playheadTime = playheadTime
        }
    }

    /// What Export is being asked for on a document that has time.
    ///
    /// Three of the four answers are the whole thing, playing. The fourth is
    /// one frame of it, standing still, which is what somebody wants for a bug
    /// report, a slide or a thumbnail — and which the video sheet took away
    /// when it replaced the picture sheet for a recording. It is a fourth
    /// button on the same row rather than a second sheet, because the whole
    /// point of this sheet is that everything leaves through one.
    public enum Choice: Sendable, Hashable {
        /// The document as a file that plays.
        case video(RecordingFormat)
        /// The frame the playhead is on, as a picture.
        case still

        /// What the file is called at the end.
        public var fileExtension: String {
            switch self {
            case .video(let format): return format.fileExtension
            case .still: return "png"
            }
        }

        /// The video format this answer writes, where it is a video at all.
        public var format: RecordingFormat? {
            switch self {
            case .video(let format): return format
            case .still: return nil
            }
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
    /// All three do. GIF and HEIC always did: the preset decides how big the
    /// frames are and how many of them there are. MP4 joined them the day the
    /// export stopped asking AVFoundation for "highest quality" and started
    /// asking for a number of bits per second, because from then on the choice
    /// changes both the picture and, predictably, the weight
    /// (`VideoExportRecipe`).
    public static func offersQuality(_ format: RecordingFormat) -> Bool { true }

    /// What this format at this choice asks the encoder for.
    public static func recipe(format: RecordingFormat, quality: VideoExportQuality,
                              source: Source) -> VideoExportRecipe {
        quality.recipe(format: format,
                       sourceSize: source.cropSize ?? source.sourceSize,
                       sourceFPS: source.sourceFPS)
    }

    /// Whether the export is a file copy rather than a re-encode.
    ///
    /// An untouched recording going out as MP4 at the top choice, which is what
    /// keeps that case instant and byte-identical. The two choices below it are
    /// asking for a SMALLER file than the recording, and there is no way to
    /// make one without encoding it, so they are always a re-encode even when
    /// nothing has been edited. That is the point of them: the commonest reason
    /// to export a recording nobody has touched is that the one on disk is too
    /// big to send.
    public static func copiesVerbatim(format: RecordingFormat, quality: VideoExportQuality,
                                      source: Source) -> Bool {
        format == .mp4 && quality == .high && !source.isEdited
    }

    /// The pixel size the written file will really have.
    public static func outputSize(format: RecordingFormat, quality: VideoExportQuality,
                                  source: Source) -> CGSize {
        let base = source.cropSize ?? source.sourceSize
        guard base.width > 0, base.height > 0 else { return base }
        // An untouched recording going out as MP4 is copied, so its picture is
        // whatever it already was, whichever choice the row is showing.
        if copiesVerbatim(format: format, quality: quality, source: source) { return base }
        return recipe(format: format, quality: quality, source: source).size
    }

    /// How well the size is known, and the best honest number where one exists.
    ///
    /// Two numbers meet here and the SMALLER of them wins, because an encoder
    /// writes the smaller of what the picture costs and what it is allowed:
    ///
    /// - **What we allow.** The export asks for a number of bits per second
    ///   (`VideoExportRecipe`), so that number times the length is the most the
    ///   file can weigh. This is the number that exists even for a document
    ///   assembled out of nothing, where there is no source file to measure.
    /// - **What the picture costs.** Measured off this very recording: the
    ///   share of its seconds that survive and the share of its pixels. A still
    ///   screen costs a fraction of any budget, and asking for more never pads
    ///   the file, so this is what an easy recording really comes out at.
    public static func weight(format: RecordingFormat, quality: VideoExportQuality,
                              source: Source) -> Weight {
        // A different container, written frame by frame. The MP4's weight says
        // nothing about it.
        guard format == .mp4 else { return .unknown }
        if copiesVerbatim(format: format, quality: quality, source: source) {
            return source.fileBytes > 0 ? .exact(source.fileBytes) : .unknown
        }
        let budget = recipe(format: format, quality: quality, source: source)
            .expectedBytes(seconds: source.keptDuration, hasAudio: source.hasAudio)
        let estimate: Int
        if let measured = measuredCost(format: format, quality: quality, source: source) {
            estimate = budget > 0 ? min(budget, measured) : measured
        } else {
            estimate = budget
        }
        guard estimate > 0 else { return .unknown }
        return .about(estimate)
    }

    /// What this recording already costs for the seconds and the pixels that
    /// survive, or nil when the file on disk could not be measured.
    private static func measuredCost(format: RecordingFormat, quality: VideoExportQuality,
                                     source: Source) -> Int? {
        guard source.fileBytes > 0, source.sourceDuration > 0 else { return nil }
        let seconds = min(max(0, source.keptDuration) / source.sourceDuration, 1)
        let pixels = pixelShare(format: format, quality: quality, source: source)
        return Int((Double(source.fileBytes) * seconds * pixels).rounded())
    }

    /// What share of the recording's COST the written file's pixels carry,
    /// never more than all of it. The crop takes some out, and a preset that
    /// shrinks the picture takes more.
    ///
    /// **Not the share of the pixels, a power of it.** Halving every side
    /// quarters the pixels and does not quarter the file: a smaller picture is
    /// harder to compress per pixel, because the detail that is left is
    /// sharper relative to it. Three quarters is the exponent the measurements
    /// bear out. On the eight second sample at Small, straight pixel counting
    /// promised 83 KB against 108 KB landing, a third light; with the power it
    /// promises 95 KB, and the line says "about" for the rest.
    private static func pixelShare(format: RecordingFormat, quality: VideoExportQuality,
                                   source: Source) -> Double {
        let whole = source.sourceSize.width * source.sourceSize.height
        guard whole > 0 else { return 1 }
        let out = outputSize(format: format, quality: quality, source: source)
        let kept = out.width * out.height
        guard kept > 0 else { return 1 }
        return min(pow(Double(kept / whole), 0.75), 1)
    }

    /// The one line under the format: what the file is, and what it costs.
    ///
    /// The same shape as the picture sheet's line, so the eye looking for the
    /// size finds it in the same place and reads it in the same words.
    public static func sizeLine(format: RecordingFormat, quality: VideoExportQuality,
                                source: Source) -> String {
        let name = format.displayName
        switch weight(format: format, quality: quality, source: source) {
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
        // The frame rate, wherever the choice is about to change it. An
        // untouched recording copied as it is has nothing to say here: its
        // frame rate is whatever it was recorded at and no choice touched it.
        if format.isAnimatedImage {
            parts.append("\(Int(quality.targetFPS.rounded())) fps")
        } else if !copiesVerbatim(format: format, quality: quality, source: source),
                  size.width >= 1, size.height >= 1 {
            let fps = recipe(format: format, quality: quality, source: source).fps
            parts.append("\(Int(fps.rounded())) fps")
        }
        parts.append(lengthPhrase(source))
        return parts.joined(separator: " · ")
    }

    /// The one sentence under the Quality row saying who the chosen preset is
    /// for. Three words on a segmented row say which is bigger and which is
    /// smaller; this says which one you want.
    public static func purposeLine(format: RecordingFormat,
                                   quality: VideoExportQuality) -> String {
        quality.purpose(for: format)
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
        suggestedFileName(recording: recording, choice: .video(format))
    }

    // MARK: - The picture on the same sheet

    /// Everything Export can write from a document that has time, in the order
    /// the buttons sit: the video's three formats as they were, then the one
    /// frame. The recording comes first because that is what the sheet is
    /// mostly for.
    public static let choices: [Choice] = formats.map(Choice.video) + [.still]

    /// What the file is called in the one line under the row. A picture says
    /// what it is beside "MP4 Video" and "Animated GIF", in the same shape.
    public static func displayName(_ choice: Choice) -> String {
        switch choice {
        case .video(let format): return format.displayName
        case .still: return "PNG picture"
        }
    }

    /// The name on the segmented row.
    public static func shortName(_ choice: Choice) -> String {
        switch choice {
        case .video(let format): return shortName(format)
        case .still: return "PNG"
        }
    }

    /// Whether this answer has a size preset worth choosing.
    ///
    /// Every video does: the preset decides how big the picture is and how
    /// many frames a second there are. One frame has neither question in it —
    /// it leaves at the size the document is — so the row goes away rather
    /// than standing there meaning nothing, exactly as the scale row does for
    /// an SVG on the picture sheet.
    public static func offersQuality(_ choice: Choice) -> Bool {
        switch choice {
        case .video(let format): return offersQuality(format)
        case .still: return false
        }
    }

    /// The pixel size the written file will really have.
    public static func outputSize(choice: Choice, quality: VideoExportQuality,
                                  source: Source) -> CGSize {
        switch choice {
        case .video(let format):
            return outputSize(format: format, quality: quality, source: source)
        case .still:
            // Nothing is scaled: the frame is the document, at the size the
            // document is, which is what a still is wanted for.
            return source.cropSize ?? source.sourceSize
        }
    }

    /// How big the file's picture is, and how much of the recording is in it.
    /// For one frame, that last part is the moment it was taken at.
    public static func shapeLine(choice: Choice, quality: VideoExportQuality,
                                 source: Source) -> String {
        guard case .still = choice else {
            return shapeLine(format: choice.format ?? .mp4, quality: quality, source: source)
        }
        var parts: [String] = []
        let size = outputSize(choice: choice, quality: quality, source: source)
        if size.width >= 1, size.height >= 1 {
            parts.append("\(Int(size.width.rounded())) × \(Int(size.height.rounded())) px")
        }
        parts.append("the frame at \(RecordingClock.elapsedString(source.playheadTime))")
        return parts.joined(separator: " · ")
    }

    /// What the file is, and what it costs.
    ///
    /// `stillBytes` is the picture already weighed — one frame is a render and
    /// an encode, so unlike a GIF it really can be weighed while somebody
    /// watches, and the bytes that were weighed are the bytes that get saved.
    /// Nil is the moment before that lands, and says what everything else that
    /// cannot be weighed says.
    public static func sizeLine(choice: Choice, quality: VideoExportQuality,
                                source: Source, stillBytes: Int? = nil) -> String {
        guard case .still = choice else {
            return sizeLine(format: choice.format ?? .mp4, quality: quality, source: source)
        }
        let name = displayName(choice)
        guard let stillBytes, stillBytes > 0 else {
            return "\(name) · size not known until it is written"
        }
        return "\(name) · \(ExportQuality.fileSize(bytes: stillBytes))"
    }

    /// The one sentence saying who this answer is for.
    ///
    /// A video says which preset you want. A picture says what a picture even
    /// means here, because PNG sitting beside three video formats otherwise
    /// reads as though it might turn the whole recording into pictures.
    public static func purposeLine(choice: Choice, quality: VideoExportQuality) -> String {
        switch choice {
        case .video(let format): return purposeLine(format: format, quality: quality)
        case .still: return "The one frame the playhead is on, with everything drawn over it."
        }
    }

    /// What the save box opens on: the document's own name, wearing the
    /// extension of the answer that was actually chosen.
    public static func suggestedFileName(recording: String, choice: Choice) -> String {
        let base = URL(fileURLWithPath: recording).deletingPathExtension().lastPathComponent
        let name = base.isEmpty ? "Recording" : base
        return "\(name).\(choice.fileExtension)"
    }
}
