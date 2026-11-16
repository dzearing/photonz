import CoreGraphics

/// How a screen recording stores its pictures when Photonz writes the file
/// itself (`RecordingFileWriter`), rather than leaving it to macOS.
///
/// Measured on 2026-11-15 against a panel of known swatches and slow dark
/// ramps, recorded and screenshotted at the same moment
/// (docs/progress/2026-11-15-recording-colour.md):
///
/// - macOS's own writer hands the stream's pixels (the display's colours, on
///   the sRGB curve) to a file that says Rec.709 colours on the 709 curve, so
///   every player lifts the darks (sRGB 76 plays as 86) and pushes greens
///   (pure green as 127, 251, 87): up to Delta E 6.8 from the screenshot.
/// - Eight bits of 4:2:0 then leave 36 bands with steps of 3 code values
///   across a ramp the screenshot shows in 74 bands of under one.
///
/// What the stream is asked for instead: 10-bit 4:2:0 in Display P3. On the
/// sRGB curve (both sRGB and Display P3 use it) and, for 10-bit frames,
/// with the BT.601 matrix whatever the stream's `colorMatrix` says (measured:
/// tagged 709 the greens play 21, 232, 11; tagged 601 every swatch lands
/// within Delta E 0.5). The file says exactly that, so nothing converts on
/// the way in and every player reads it right. HEVC Main 10 at the rate
/// at its top quality (`RecordingQuality`): within Delta E 0.5 of the
/// screenshot, every ramp in as many bands as the screenshot shows, at the
/// same load on the Mac and the same start.
public enum RecordingPictures {

    /// `kCVImageBufferColorPrimaries_P3_D65`.
    public static let colourPrimaries = "P3_D65"
    /// `kCVImageBufferTransferFunction_sRGB`.
    public static let transferFunction = "IEC_sRGB"
    /// `kCVImageBufferYCbCrMatrix_ITU_R_601_4`.
    public static let yCbCrMatrix = "ITU_R_601_4"

    /// Smaller files: bits for each pixel of each frame. A full Retina screen
    /// at 60 frames a second comes to about 20 megabits a second: the same
    /// colour and bands as 40, measured, with room for a screen in motion.
    static let bitsPerPixelFrame = 0.045
    public static let fewestBitsPerSecond = 4_000_000
    public static let mostBitsPerSecond = 60_000_000

    /// The average rate the encoder is held to for `pixelSize` at `fps`.
    public static func bitsPerSecond(pixelSize: CGSize, fps: Int) -> Int {
        let pixels = max(0, Double(pixelSize.width)) * max(0, Double(pixelSize.height))
        let wanted = pixels * Double(max(1, fps)) * bitsPerPixelFrame
        return min(mostBitsPerSecond, max(fewestBitsPerSecond, Int(wanted.rounded())))
    }

    /// How the encoder is held: to an average rate, or to its top quality
    /// whatever that costs.
    public enum Compression: Sendable, Hashable {
        case averageBitsPerSecond(Int)
        case quality(Double)
    }

    public static func compression(_ quality: RecordingQuality, pixelSize: CGSize, fps: Int) -> Compression {
        switch quality {
        case .smaller: return .averageBitsPerSecond(bitsPerSecond(pixelSize: pixelSize, fps: fps))
        case .best: return .quality(1)
        }
    }

    public static let soundSampleRate = 48_000
    public static let soundChannels = 2
    public static let soundBitsPerSecond = 160_000
}

/// The one recording choice in Settings. Best (the default) asks the encoder
/// for its top quality: every dark gradient as smooth as a screenshot (a dark
/// purple ramp in 93 bands of 0.8 code values, the screenshot's own count),
/// smaller than macOS's own files on a still screen (37 against 46 MB a
/// minute) but four times them while the whole screen moves (925 against 237).
/// Smaller files holds the encoder to `RecordingPictures.bitsPerSecond`: the
/// screen's colours just as true, about half macOS's size, but the screen's
/// fine dither is flattened into faint one-code-value bands (steps of 1.3 on
/// that ramp). Neither costs more of the Mac or starts later (measured
/// 2026-11-15, docs/progress/2026-11-15-recording-colour.md).
public enum RecordingQuality: String, CaseIterable, Sendable, Codable {
    case best
    case smaller

    public static let settingKey = "next.recording.quality"

    public var label: String {
        switch self {
        case .best: return "Best"
        case .smaller: return "Smaller files"
        }
    }

    /// What a stored setting says, Best for anything it does not know.
    public init(stored: String?) {
        self = stored.flatMap(RecordingQuality.init(rawValue:)) ?? .best
    }
}
