import CoreGraphics

/// Placement geometry for the global slide-down history overlay (phase 11.4).
///
/// The overlay is a borderless panel pinned to the **top edge of a display**.
/// Showing it slides the panel DOWN from just above the top edge into view;
/// dismissing slides it back UP. This type is the pure, testable core of that:
/// given a screen rect (in macOS bottom-left screen coordinates — pass the
/// screen's `visibleFrame` so it clears the menu bar), it yields the panel's
/// on-screen (`presentedFrame`) and off-screen (`hiddenFrame`) rects. The
/// AppKit shell just animates the panel between the two while fading alpha.
public struct HistoryOverlayLayout: Equatable, Sendable {
    /// The panel rect when fully shown (slid down, pinned under the top edge).
    public let presentedFrame: CGRect
    /// The panel rect when hidden (slid up, fully above the top edge).
    public let hiddenFrame: CGRect

    /// - Parameters:
    ///   - screen: the target display's frame (use `visibleFrame`), bottom-left
    ///     origin. Non-zero origins (secondary displays) are honored.
    ///   - height: the panel's height.
    ///   - maxWidth: cap so the strip doesn't stretch edge-to-edge on wide
    ///     displays.
    ///   - horizontalInset: minimum gap to each screen edge before the cap
    ///     applies (drives the width on narrow displays).
    ///   - topInset: gap between the screen's top edge and the panel's top.
    public init(screen: CGRect,
                height: CGFloat,
                maxWidth: CGFloat = 1100,
                horizontalInset: CGFloat = 24,
                topInset: CGFloat = 8) {
        let width = min(screen.width - horizontalInset * 2, maxWidth)
        let x = screen.midX - width / 2
        let presentedY = screen.maxY - height - topInset
        // Hidden: origin at the screen top so the whole panel sits above it.
        let hiddenY = screen.maxY
        presentedFrame = CGRect(x: x, y: presentedY, width: width, height: height)
        hiddenFrame = CGRect(x: x, y: hiddenY, width: width, height: height)
    }
}
