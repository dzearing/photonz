import CoreGraphics

/// How tall the layers list wants to be, worked out rather than measured.
///
/// The list builds only the rows you can see, so it cannot ask the rows how
/// tall they add up to: a stack that has not materialised a row reports no
/// height for it, and feeding that back into the area's frame is a loop that
/// shrinks itself (smaller frame, fewer rows built, smaller reported height).
///
/// Every item in the list is the same shape — a thumbnail with a name beside
/// it — so the number falls out of the row count, one measured row height, and
/// the Canvas row at the bottom, which is always built and so always measured.
public enum LayerListMetrics {
    /// The gap between two rows.
    public static let spacing: CGFloat = 2
    /// The breathing room under the last row.
    public static let bottomPadding: CGFloat = 2

    /// The height the list would take if nothing capped it: every layer row,
    /// the gaps between them, the Canvas row, and the padding under it.
    ///
    /// Heights come from live measurements, so a value that has not landed yet
    /// can be zero or negative; nothing here is allowed to hand back a
    /// negative frame.
    public static func naturalHeight(rowCount: Int,
                                     rowHeight: CGFloat,
                                     canvasRowHeight: CGFloat) -> CGFloat {
        let rows = max(0, rowCount)
        let row = max(0, rowHeight)
        let canvas = max(0, canvasRowHeight)
        return CGFloat(rows) * (row + spacing) + canvas + bottomPadding
    }

    /// How many rows off each edge of the screen still get a picture made for
    /// them, so an ordinary scroll finds one waiting rather than a grey square.
    /// Four rows is roughly one screenful of runway at the panel's resting
    /// height, and it is what keeps a hundred layer document asking for the
    /// same handful of pictures a ten layer one does.
    public static let thumbnailBufferRows = 4

    /// Which row is at the top of the visible area, given how far the list has
    /// been scrolled. Rubber banding past the top reads as the top row, and a
    /// row height that has not been measured yet reads as the top row too
    /// rather than as a division by zero.
    public static func firstVisibleRow(scrollOffset: CGFloat, rowHeight: CGFloat) -> Int {
        guard scrollOffset > 0, rowHeight > 0 else { return 0 }
        return Int((scrollOffset / rowStride(rowHeight: rowHeight)).rounded(.down))
    }

    /// The rows worth making a picture for: the ones on screen, plus
    /// `thumbnailBufferRows` off each edge.
    ///
    /// The list draws a small render of every layer beside its name, and each
    /// one is a real render. Asking for all of them means a document with a
    /// hundred and twenty layers starts a hundred and twenty renders to fill a
    /// list showing five, which is most of the cost of opening it and none of
    /// the benefit. This window is what the list asks for instead, so the cost
    /// is set by the size of the panel and not by the size of the document.
    ///
    /// Everything is clamped: measurements arrive late and can be zero or
    /// negative, and a window that ran off either end of the list would either
    /// crash a slice or quietly ask for everything again.
    public static func thumbnailWindow(rowCount: Int,
                                       rowHeight: CGFloat,
                                       firstVisibleRow: Int,
                                       viewportHeight: CGFloat) -> Range<Int> {
        let count = max(0, rowCount)
        guard count > 0 else { return 0..<0 }
        let stride = rowStride(rowHeight: rowHeight)
        // One extra for the row half off the top edge, which is on screen too.
        let onScreen = max(1, Int((viewportHeight / stride).rounded(.up)) + 1)
        let first = min(max(0, firstVisibleRow), count - 1)
        let start = max(0, first - thumbnailBufferRows)
        let end = min(count, first + onScreen + thumbnailBufferRows)
        return start..<max(start, end)
    }

    /// One row plus the gap under it. Never zero, so dividing by it is safe
    /// before the first measurement lands.
    private static func rowStride(rowHeight: CGFloat) -> CGFloat {
        max(1, rowHeight) + spacing
    }
}
