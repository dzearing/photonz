import CoreGraphics

/// How tall the Library shelf has to be to hold what is on it.
///
/// The shelf draws its tiles in a lazy grid, and a lazy grid cannot be asked
/// how tall it is: it only builds the rows it has been told to show, so a
/// measurement of it answers with the height it was given rather than the
/// height it wants. So the shelf works it out instead, from the number of
/// tiles and the room it has across. The numbers here were measured against
/// the real grid at five dock widths and are pinned by tests.
///
/// The tile views build themselves out of these same metrics, so the picture
/// and the arithmetic cannot drift apart.
public enum LibraryShelfLayout {

    // MARK: What a tile is made of

    /// The narrowest a tile may be before the grid drops a column.
    public static let tileMinimumWidth: CGFloat = 68
    /// The gap between tiles, across and down.
    public static let tileSpacing: CGFloat = 8
    /// The picture well at the top of every tile.
    public static let thumbnailHeight: CGFloat = 44
    /// The gap between the picture and the name under it.
    public static let captionSpacing: CGFloat = 3
    /// The tile's name, under its picture.
    public static let captionFontSize: CGFloat = 10
    /// One line of that caption. Measured, not guessed: the caption is a
    /// fixed-size system font on one line, so it does not move with settings.
    public static let captionHeight: CGFloat = 13
    /// The breathing room inside a tile, which is also where its selection
    /// ring sits.
    public static let tilePadding: CGFloat = 4
    /// The grid's own top and bottom margin, so the first and last rows are
    /// not flush against the scroll edge.
    public static let gridVerticalPadding: CGFloat = 2

    /// One tile, top to bottom.
    public static let tileHeight: CGFloat =
        tilePadding * 2 + thumbnailHeight + captionSpacing + captionHeight

    // MARK: The shelf

    /// How many tiles fit across `width`, which is what an adaptive grid works
    /// out for itself. Always at least one, however narrow the dock is pulled.
    public static func columnCount(width: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        let columns = Int((width + tileSpacing) / (tileMinimumWidth + tileSpacing))
        return max(1, columns)
    }

    /// How many rows `tileCount` tiles wrap into at `width`.
    public static func rowCount(tileCount: Int, width: CGFloat) -> Int {
        guard tileCount > 0 else { return 0 }
        let columns = columnCount(width: width)
        return (tileCount + columns - 1) / columns
    }

    /// The height the grid would take if nothing capped it.
    public static func contentHeight(tileCount: Int, width: CGFloat) -> CGFloat {
        let rows = rowCount(tileCount: tileCount, width: width)
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * tileHeight
            + CGFloat(rows - 1) * tileSpacing
            + gridVerticalPadding * 2
    }

    /// The height the shelf actually takes: its content, but never more than
    /// the ceiling the drag handle sets, so the sections under it stay in view
    /// and a long shelf scrolls on its own.
    ///
    /// Before anything has measured the dock, `width` is zero and there is no
    /// honest answer, so the shelf stands at its ceiling for that one frame
    /// rather than guessing a tall column and visibly collapsing.
    public static func shelfHeight(tileCount: Int, width: CGFloat, cap: CGFloat) -> CGFloat {
        guard width > 0 else { return cap }
        return min(contentHeight(tileCount: tileCount, width: width), cap)
    }
}
