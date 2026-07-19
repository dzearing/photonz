import CoreGraphics

/// Maps an image's DPI to a display backing scale, so a Retina screenshot opens
/// at its on-screen POINT size (Preview-style). macOS saves Retina screenshots
/// at 144 DPI (2×) or 216 DPI (3×); those are the only values treated as a scale.
/// Every other DPI — 72, 96, the 300 of a print scan — stays 1× so ordinary
/// photos aren't silently shrunk to half size.
public enum DisplayScale {
    /// The pixel scale implied by `dpi`. Returns 2 or 3 only for a clean 2×/3×
    /// multiple of 72 (small tolerance for rounding); otherwise 1. Non-finite or
    /// non-positive input is 1.
    public static func pixelScale(forDPI dpi: Double) -> CGFloat {
        guard dpi.isFinite, dpi > 0 else { return 1 }
        let raw = dpi / 72
        for scale in [2.0, 3.0] where abs(raw - scale) < 0.02 {
            return CGFloat(scale)
        }
        return 1
    }
}
