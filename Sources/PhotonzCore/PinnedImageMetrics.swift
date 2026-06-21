import CoreGraphics

/// Sizing + opacity policy for pin-to-screen floating windows (phase 11.8): a
/// pinned screenshot floats above everything as reference material, at an
/// adjustable size and opacity. Pure math so the AppKit window shell stays thin.
public enum PinnedImageMetrics {
    /// Floor so a pinned reference never fades to illegibility.
    public static let minOpacity: CGFloat = 0.2
    public static let maxOpacity: CGFloat = 1.0

    /// Initial pinned-window content size: aspect-fit the image inside a square
    /// of side `maxDimension`, never upscaling beyond the image's natural size
    /// (a tiny grab stays tiny). Rounds to whole points.
    public static func fittedSize(imageSize: CGSize, maxDimension: CGFloat) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, maxDimension > 0 else { return .zero }
        let scale = min(1, min(maxDimension / imageSize.width, maxDimension / imageSize.height))
        return CGSize(width: (imageSize.width * scale).rounded(),
                      height: (imageSize.height * scale).rounded())
    }

    /// Clamp a requested opacity into the legible range.
    public static func clampOpacity(_ value: CGFloat) -> CGFloat {
        min(maxOpacity, max(minOpacity, value))
    }
}
