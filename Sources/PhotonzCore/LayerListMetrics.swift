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
}
