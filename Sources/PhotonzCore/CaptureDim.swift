import CoreGraphics

/// The dim a capture overlay lays over the screen while you pick a region: the
/// whole display, with a hole where the selection is.
///
/// The overlay reads the selection in top-left points, the way a screen reads,
/// and the dim is drawn in a layer that counts up from the bottom. This is the
/// one place that turn happens, so it can be checked without a live screen.
public enum CaptureDim {

    /// Where the hole goes, in the dim's own bottom-left origin space, for a
    /// `selection` in the overlay's top-left points over a display of `bounds`.
    /// Nil when the selection has no area on this display at all, which is a
    /// press that has not moved yet, or a drag that has run onto another screen.
    public static func hole(for selection: CGRect, in bounds: CGRect) -> CGRect? {
        let onDisplay = selection.standardized.intersection(bounds)
        guard !onDisplay.isNull, onDisplay.width > 0, onDisplay.height > 0 else { return nil }
        return CGRect(x: onDisplay.minX,
                      y: bounds.height - onDisplay.maxY,
                      width: onDisplay.width,
                      height: onDisplay.height)
    }
}
