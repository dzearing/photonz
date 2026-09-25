import CoreGraphics
import Foundation

/// How big the picture of an exported video is: the Size row on the Export
/// sheet.
///
/// A Retina screen recording is 2880 by 1800 or larger, and what people post
/// is 1080p or 720p, which is what Premiere and every share tool offer. So the
/// size is its own choice, named the way those tools name it, and it owns the
/// pixels; the Quality row beside it keeps the frame rate and the budget.
///
/// **An animated picture steps down one.** A GIF is frames rather than a
/// stream and grows with every pixel, so a 1080p one is a file nobody can
/// send; 480p is where GIFs in an issue or a chat live. GIF and HEIC offer
/// Full, 720p and 480p, a video Full, 1080p and 720p: three either way.
///
/// **The names are the short side.** 1080p is a picture 1080 pixels tall when
/// it lies on its side, whatever its shape: a 16:10 recording at 1080p is 1728
/// by 1080, a portrait one 1080 by 1728. Nothing is ever made bigger, so a
/// size that would not shrink this recording is not offered for it.
public enum VideoExportSize: String, CaseIterable, Sendable, Codable {
    /// The recording's own pixels.
    case full
    case p1080
    case p720
    case p480

    /// The longest the short side may be, or nil for the whole picture.
    public var shortSide: CGFloat? {
        switch self {
        case .full: return nil
        case .p1080: return 1080
        case .p720: return 720
        case .p480: return 480
        }
    }

    /// The pixel size a picture of this shape comes out at, shape kept.
    public func outputSize(for source: CGSize) -> CGSize {
        guard let cap = shortSide, source.width > 0, source.height > 0 else { return source }
        let short = min(source.width, source.height)
        guard short > cap else { return source }
        let scale = cap / short
        return CGSize(width: (source.width * scale).rounded(),
                      height: (source.height * scale).rounded())
    }

    /// Whether this size makes this picture smaller. Full is always on offer.
    public func shrinks(_ source: CGSize) -> Bool {
        guard let cap = shortSide else { return false }
        return min(source.width, source.height) > cap
    }

    /// The sizes a format has on its row, whatever the picture.
    public static func choices(for format: RecordingFormat) -> [VideoExportSize] {
        format.isAnimatedImage ? [.full, .p720, .p480] : [.full, .p1080, .p720]
    }

    /// The sizes worth offering for a picture this big, in the order they sit
    /// on the row: the whole picture first, then smaller.
    public static func offered(for source: CGSize,
                               format: RecordingFormat = .mp4) -> [VideoExportSize] {
        choices(for: format).filter { $0 == .full || $0.shrinks(source) }
    }

    /// This size where it is on offer for this picture in this format, else
    /// the whole of it. A size remembered from a bigger recording does nothing
    /// on a smaller one.
    public func offeredOrFull(for source: CGSize,
                              format: RecordingFormat = .mp4) -> VideoExportSize {
        Self.offered(for: source, format: format).contains(self) ? self : .full
    }

    /// The name on the segmented row. Full says the pixels it keeps, because
    /// "Full" alone does not say whether that is big.
    public func label(for source: CGSize) -> String {
        switch self {
        case .full:
            guard source.width >= 1, source.height >= 1 else { return "Full" }
            return "Full · \(Int(source.width.rounded())) × \(Int(source.height.rounded()))"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        }
    }

    /// What the sheet opens on for a format the first time: the whole picture
    /// for a video, so an untouched recording still leaves as a straight copy,
    /// and 480p for an animated picture, about the size the sheet's Standard
    /// preset made one before there was a Size row.
    public static func firstChoice(for format: RecordingFormat) -> VideoExportSize {
        format.isAnimatedImage ? .p480 : .full
    }
}
