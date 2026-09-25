import CoreGraphics
import Foundation

/// What one of the three choices on the Export sheet actually asks the encoder
/// for, and therefore what the file will weigh.
///
/// **Why this exists.** Until now an MP4 was written at
/// `AVAssetExportPresetHighestQuality`, which is an opaque target: nobody,
/// including the app, could say what would come out. That is the whole reason
/// the sheet could only offer a ratio worked out from the source file and hope
/// it held. Once the export ASKS for a number of bits per second, the size of
/// the file is that number times the length, by construction, and the line on
/// the sheet stops being a hope.
///
/// The budget is worked out per pixel and per frame rather than picked, because
/// a 4K recording and a phone-sized one do not want the same number. An encoder
/// never pads: asking for more than the picture costs simply gets a smaller
/// file, which is why the sheet takes the SMALLER of this budget and what the
/// recording already costs per second and per pixel (`RecordingExport.weight`).
public struct VideoExportRecipe: Sendable, Hashable {

    /// The pixel size the written file will have.
    public var size: CGSize
    /// How many frames of it go by in a second.
    public var fps: Double
    /// The picture budget, in bits per second. Zero for an animated picture,
    /// which is frames in a container rather than a stream with a budget.
    public var videoBitsPerSecond: Int
    /// The sound budget, in bits per second, for a recording that carries any.
    public var audioBitsPerSecond: Int

    public init(size: CGSize, fps: Double, videoBitsPerSecond: Int, audioBitsPerSecond: Int) {
        self.size = size
        self.fps = fps
        self.videoBitsPerSecond = videoBitsPerSecond
        self.audioBitsPerSecond = audioBitsPerSecond
    }

    /// What a recording this long will weigh, in bytes, if the encoder spends
    /// its whole budget. Zero when there is no budget to spend, which is what
    /// keeps an animated picture from claiming a size it cannot know.
    public func expectedBytes(seconds: TimeInterval, hasAudio: Bool) -> Int {
        guard videoBitsPerSecond > 0, seconds > 0 else { return 0 }
        let bits = Double(videoBitsPerSecond + (hasAudio ? audioBitsPerSecond : 0)) * seconds
        return Int((bits / 8).rounded())
    }
}

extension VideoExportQuality {

    /// The longest side an MP4 at this choice is allowed to have, or nil for
    /// the choice that keeps the recording as it is.
    ///
    /// **High does not shrink anything.** Somebody who picks the top choice on
    /// a screen recording means "the thing I recorded", and a cap there would
    /// both blur it and take away the verbatim-copy fast path that makes an
    /// untouched recording export instantly. Only the two choices below it are
    /// allowed to make the picture smaller, and the sheet says the pixel size
    /// they land on, live, so the word never has to be trusted on its own.
    var movieMaxDimension: CGFloat? {
        switch self {
        case .high: return nil
        case .standard: return 1440
        case .small: return 960
        }
    }

    /// The most frames a second an MP4 at this choice keeps. The top choice
    /// keeps whatever was recorded; the other two cap at 30, which halves a
    /// 60 fps screen capture on a clean 2:1 boundary.
    var movieMaxFPS: Double {
        self == .high ? 60 : 30
    }

    /// Bits spent on one pixel of one frame. Screen content compresses far
    /// better than camera footage, so these are lower than a camera preset
    /// would use, and they are a ceiling rather than a floor: a still screen
    /// costs a fraction of this and the file comes out smaller.
    private var bitsPerPixelPerFrame: Double {
        switch self {
        case .high: return 0.12
        case .standard: return 0.08
        case .small: return 0.05
        }
    }

    /// What the sound is allowed in the weight, in bits per second.
    ///
    /// The same for all three, because the sound is not where a screen
    /// recording's weight is and squeezing it would only make voices worse for
    /// a percent of the file. It is an allowance rather than an instruction:
    /// the sound is written by the system's own m4a encoder, which picks its
    /// own rate from the material, and on the samples measured here it came in
    /// well under this. Erring high is the right way round for a number
    /// somebody is about to trust.
    private var audioBitsPerSecond: Int { 128_000 }

    /// What this choice asks for, given the recording it is being asked about.
    ///
    /// - format: MP4 is a stream with a budget; GIF and HEIC are frames, and
    ///   keep exactly the meaning they have had since the preset shipped.
    /// - sourceSize: the recording's own pixel size, after any crop.
    /// - sourceFPS: how fast the recording itself runs. Nothing is ever sped
    ///   up: a cap only ever takes frames away.
    /// - size: the Size row, where the sheet has one. It owns the pixels, and
    ///   this choice keeps only the frame rate and the budget per pixel. Nil is
    ///   the sheet without a Size row, where this choice shrinks the picture
    ///   as it always did.
    public func recipe(format: RecordingFormat, sourceSize: CGSize,
                       sourceFPS: Double, size: VideoExportSize? = nil) -> VideoExportRecipe {
        guard format == .mp4 else {
            return VideoExportRecipe(
                size: size.map { $0.outputSize(for: sourceSize) }
                    ?? Geometry.downscaledToFit(sourceSize, maxDimension: maxDimension),
                fps: targetFPS, videoBitsPerSecond: 0,
                audioBitsPerSecond: audioBitsPerSecond)
        }
        let capped: CGSize
        if let size {
            capped = size.outputSize(for: sourceSize)
        } else {
            capped = movieMaxDimension.map {
                Geometry.downscaledToFit(sourceSize, maxDimension: $0)
            } ?? sourceSize
        }
        let size = DocumentVideoExport.evenSize(capped)
        let recorded = sourceFPS > 0 ? sourceFPS : 30
        let fps = min(recorded, movieMaxFPS)
        let pixels = Double(size.width * size.height)
        let budget = pixels * fps * bitsPerPixelPerFrame
        // A floor, because a postage-stamp picture still needs enough bits to
        // be watchable rather than a mosaic.
        return VideoExportRecipe(size: size, fps: fps,
                                 videoBitsPerSecond: max(400_000, Int(budget.rounded())),
                                 audioBitsPerSecond: audioBitsPerSecond)
    }

    /// One sentence saying who this choice is for, in terms of where the file
    /// is going rather than what the encoder is doing.
    ///
    /// The three words on the segmented row say which is bigger and which is
    /// smaller and nothing else. This is the part that answers "which one do I
    /// want", and it changes with the format because the same word means a
    /// different trade in a video and in an animated picture.
    public func purpose(for format: RecordingFormat) -> String {
        guard format == .mp4 else {
            switch self {
            case .high: return "Smoothest and sharpest, and much the biggest file."
            case .standard: return "A fair trade for a chat, an issue or a pull request."
            case .small: return "The smallest, for somewhere with a strict limit."
            }
        }
        switch self {
        case .high: return "Every pixel and every frame, for keeping or editing later."
        case .standard: return "For sending: fits chat and email, still sharp on a screen."
        case .small: return "For a tight limit: the smallest file that still reads."
        }
    }
}

extension VideoExportQuality {

    /// Who this choice is for on a sheet that also has a Size row, where the
    /// size says how big the picture is and this says only how smooth it runs
    /// and how much is spent on it. "Every pixel" would be a claim about the
    /// other row.
    public func purposeBesideASize(for format: RecordingFormat) -> String {
        guard format == .mp4 else {
            switch self {
            case .high: return "Smoothest, and much the biggest file."
            case .standard: return "A fair trade for a chat, an issue or a pull request."
            case .small: return "The fewest frames, for somewhere with a strict limit."
            }
        }
        switch self {
        case .high: return "Every frame, sharp enough to keep or edit later."
        case .standard: return "For sending: still sharp, at a fraction of the weight."
        case .small: return "For a tight limit: the smallest file that still reads."
        }
    }
}
