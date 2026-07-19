import CoreGraphics

/// Pure, testable policy for sizing an editor window to a freshly opened image,
/// and the zoom to show it at.
///
/// The decision follows a strict priority (see `plan`):
///  1. **Prefer 100%.** Always try to show the image at its on-screen point size.
///  2. **Prefer growing the window.** If the image at 100% fits inside the usable
///     maximum, size the window to exactly `image + side pane + padding on each
///     canvas edge` and stay at 100%.
///  3. **Reduce zoom only as a last resort.** When even a maxed window can't hold
///     the image at 100%, max the binding axis and drop the zoom so the image
///     fits with the same padding on each side of the canvas area.
///
/// Everything is a pure function of sizes in **points** — no AppKit/SwiftUI. The
/// caller (`EditorState`) converts image pixels to points (dividing by the
/// capture's pixel scale), subtracts the window chrome from the screen's visible
/// frame to get `maxContentSize`, and applies the returned content size + scale.
public enum EditorWindowFit {

    /// The gap between the image and the edge of the canvas area, per side. This
    /// is padding *inside* the window; the side pane is separate window width.
    public static let edgePadding: CGFloat = 100

    public struct Plan: Equatable, Sendable {
        /// Target window **content** size, in points.
        public var contentSize: CGSize
        /// Fraction of 100% (the image's on-screen point size) to display at.
        /// `1` = 100%; `< 1` only when even a maxed window can't fit it.
        public var imageScale: CGFloat

        public init(contentSize: CGSize, imageScale: CGFloat) {
            self.contentSize = contentSize
            self.imageScale = imageScale
        }
    }

    /// Compute the window content size + display scale for opening `imagePointSize`.
    ///
    /// - Parameters:
    ///   - imagePointSize: the image's size at 100% zoom, in points (pixels ÷ scale).
    ///   - sidePaneWidth: width the docked side pane occupies in the window (0 collapsed).
    ///   - maxContentSize: the largest usable window content area (visible screen − chrome).
    ///   - minContentSize: the window floor, in content points.
    ///   - padding: gap between the image and the canvas edge, per side.
    public static func plan(imagePointSize: CGSize,
                            sidePaneWidth: CGFloat,
                            maxContentSize: CGSize,
                            minContentSize: CGSize,
                            padding: CGFloat = edgePadding) -> Plan {
        let img = CGSize(width: max(0, imagePointSize.width),
                         height: max(0, imagePointSize.height))
        let pane = max(0, sidePaneWidth)
        let pad = max(0, padding)
        let maxW = max(1, maxContentSize.width)
        let maxH = max(1, maxContentSize.height)

        // What the window would need to show the image at 100% with the padding
        // on each canvas edge, plus the side pane.
        let neededW = img.width + pad * 2 + pane
        let neededH = img.height + pad * 2

        var scale: CGFloat = 1
        if neededW > maxW || neededH > maxH {
            // Step 3: even a maxed window can't hold 100% → reduce the zoom so
            // the image fits the maxed canvas area, keeping the padding.
            let canvasW = max(1, maxW - pane - pad * 2)
            let canvasH = max(1, maxH - pad * 2)
            let sx = img.width > 0 ? canvasW / img.width : 1
            let sy = img.height > 0 ? canvasH / img.height : 1
            scale = min(sx, sy, 1)
        }

        // Hug the (possibly reduced) image on both axes; the binding axis lands
        // exactly on the usable max, the other stays as tight as the image.
        var size = CGSize(width: img.width * scale + pad * 2 + pane,
                          height: img.height * scale + pad * 2)
        size.width = min(size.width, maxW)
        size.height = min(size.height, maxH)
        // The floor is a hard minimum — a usable window wins over exact padding.
        size.width = max(size.width, minContentSize.width)
        size.height = max(size.height, minContentSize.height)

        return Plan(contentSize: size, imageScale: scale)
    }
}
