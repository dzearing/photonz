import CoreGraphics

/// Frame math for sizing a video-editor window to its recording (phase 13):
/// when metadata loads, the window grows/shrinks so the player area shows the
/// video pixel-exact, clamped to the screen. Pure so it's unit-tested; the
/// caller feeds AppKit bottom-left-origin rects and applies the result.
public enum VideoWindowLayout {
    /// The frame the window should adopt so its player area becomes
    /// `targetPlayerArea` points.
    ///
    /// - `current`: the window's frame (screen coords, bottom-left origin).
    /// - `playerArea`: the player region's current size inside that frame; the
    ///   difference to the window size is the chrome (title bar, paddings,
    ///   transport controls) and is preserved verbatim.
    /// - `targetPlayerArea`: what the player region should become.
    /// - Growth keeps the window's top-left corner anchored (windows visually
    ///   grow down/right), then the frame is clamped into `visible`.
    public static func frame(current: CGRect, playerArea: CGSize, targetPlayerArea: CGSize,
                             minSize: CGSize, visible: CGRect) -> CGRect {
        guard visible.width > 0, visible.height > 0,
              targetPlayerArea.width > 0, targetPlayerArea.height > 0 else { return current }

        let chrome = CGSize(width: current.width - playerArea.width,
                            height: current.height - playerArea.height)
        var size = CGSize(width: targetPlayerArea.width + chrome.width,
                          height: targetPlayerArea.height + chrome.height)
        size.width = min(max(size.width, minSize.width), visible.width)
        size.height = min(max(size.height, minSize.height), visible.height)

        // Top-left anchored, then slid back inside the visible frame.
        var origin = CGPoint(x: current.minX, y: current.maxY - size.height)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }
}
