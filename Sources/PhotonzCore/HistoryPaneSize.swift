import CoreGraphics

/// **How tall the History pane is** (user 2026-10-28: "i'd like the pane to
/// be resizable on the outer edge").
///
/// The pane hangs from the top of the screen, so its outer edge is the bottom
/// one: dragging it down makes the pane, and the tiles in it, taller. The
/// height a person leaves it at is kept and used the next time it opens.
public enum HistoryPaneSize {
    /// What it opens at until somebody drags it: the strip it always had,
    /// now that the pane no longer stands 8 points in from every edge.
    public static let standard: CGFloat = 192
    /// No shorter than this, so a tile is still a picture you can recognise.
    public static let shortest: CGFloat = 150
    /// A tile no shorter than this, however short the pane.
    public static let smallestTile: CGFloat = 60
    /// A tile's height at the standard pane height, which it always had.
    public static let standardTile: CGFloat = 100

    /// No taller than most of the screen, so whatever is under it can still
    /// be seen and clicked.
    public static func tallest(screenHeight: CGFloat) -> CGFloat {
        max(standard, screenHeight * 0.6)
    }

    /// The height to open at: the one kept, inside its limits, or the standard.
    public static func height(kept: CGFloat?, screenHeight: CGFloat) -> CGFloat {
        guard let kept else { return standard }
        return min(max(shortest, kept), tallest(screenHeight: screenHeight))
    }

    /// The height while the bottom edge is dragged. `top` and `pointerY` are
    /// screen points, bottom-left origin; `grabbedBelowBottom` is how far
    /// under the pane's bottom edge the pointer took hold of it.
    public static func dragged(top: CGFloat, pointerY: CGFloat, grabbedBelowBottom: CGFloat,
                               screenHeight: CGFloat) -> CGFloat {
        height(kept: top - pointerY - grabbedBelowBottom, screenHeight: screenHeight)
    }

    /// How tall a tile is in a pane this tall: every point the pane is
    /// dragged taller goes to the tiles. Worked out from the pane rather than
    /// measured in each strip, so switching filters lays nothing out again.
    public static func tileHeight(paneHeight: CGFloat) -> CGFloat {
        max(smallestTile, paneHeight - (standard - standardTile))
    }
}
