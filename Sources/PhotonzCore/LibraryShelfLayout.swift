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
    /// The air around a picture that is drawn whole inside its well. A picture
    /// that has to be cut off gives this up and goes edge to edge.
    public static let picturePadding: CGFloat = 3

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

    // MARK: Putting one tile on screen

    /// Where the tile at `index` starts, measured down from the top of the
    /// grid. Worked out rather than measured, for the same reason the shelf's
    /// height is: a lazy grid has not built the row a tile is on until that row
    /// is on screen, so a tile below the fold cannot be asked where it is —
    /// which is exactly the tile that needs moving.
    public static func tileTop(index: Int, width: CGFloat) -> CGFloat {
        guard index > 0 else { return gridVerticalPadding }
        let row = index / columnCount(width: width)
        return gridVerticalPadding + CGFloat(row) * (tileHeight + tileSpacing)
    }

    /// What the shelf should do to put the tile at `index` on screen: the same
    /// call the dock makes about a whole section, asked about one tile inside
    /// the shelf's own little scroll.
    ///
    /// The app opens the shelf for you when it makes something (a component, a
    /// saved color), and the tile it just made can be sitting below two rows of
    /// older ones. Then the shelf is on screen and your work is not.
    ///
    /// - Parameters:
    ///   - index: the tile's place in the shelf, counting from zero.
    ///   - width: how much room the shelf has across.
    ///   - gridTop: where the top of the grid sits relative to the top of the
    ///     shelf's visible area. Zero when the shelf is scrolled to its start,
    ///     negative once it has been scrolled down.
    ///   - viewportHeight: how tall the shelf's visible area is.
    public static func tileReveal(index: Int, width: CGFloat,
                                  gridTop: CGFloat, viewportHeight: CGFloat) -> DockReveal.Action {
        DockReveal.action(sectionTop: gridTop + tileTop(index: index, width: width),
                          sectionHeight: tileHeight,
                          viewportHeight: viewportHeight)
    }

    // MARK: The picture in a tile

    /// Which edge of a tile's picture the well cuts off.
    public enum TileCrop: Equatable, Sendable {
        /// Nothing is cut: the whole component is in view.
        case none
        /// A wide component, blown up and cut off at its far edge.
        case trailing
        /// A tall component, blown up and cut off at its bottom.
        case bottom
    }

    /// Where a component's picture ends up inside its tile well.
    public struct TilePicture: Equatable, Sendable {
        /// How big to draw the picture, in points. Bigger than the well when
        /// the picture is cropped, which is the whole point of cropping.
        public var size: CGSize
        /// Which edge, if any, the well cuts off.
        public var crop: TileCrop

        public init(size: CGSize, crop: TileCrop) {
            self.size = size
            self.crop = crop
        }
    }

    /// The share of the well a picture has to cover before it counts as
    /// readable. Below this it is a hairline: a nav bar fitted whole into a
    /// 61 point tile is nine points tall, which is the same grey smear as a
    /// text field fitted whole beside it.
    public static let readablePictureFraction: CGFloat = 1.0 / 3.0

    /// How far past a plain fit a picture may be blown up before the cut costs
    /// more than the size buys. Filling the well outright turns a nav bar into
    /// the word "Back" and a text field into the word "Placeho", which says no
    /// more than the hairline did; stopping here keeps roughly the first half
    /// of a long component in view, so it still reads as a strip with a start,
    /// a top and a bottom.
    public static let maxPictureZoom: CGFloat = 2.5

    /// How a component's picture sits in a `well`-sized picture area.
    ///
    /// A shape that reads at its natural fit is drawn whole, which is every
    /// square-ish thing and every button. A shape so long that fitting it
    /// leaves a hairline is blown up until it reads and cut off at its far
    /// edge instead, the way a long file name is cut rather than shrunk to
    /// nothing: the start of a nav bar at a size you can read beats the whole
    /// of it as a grey line.
    public static func picture(_ pictureSize: CGSize, in well: CGSize) -> TilePicture {
        guard pictureSize.width > 0, pictureSize.height > 0,
              well.width > 0, well.height > 0 else {
            return TilePicture(size: .zero, crop: .none)
        }
        let aspect = pictureSize.width / pictureSize.height
        let fitted = fit(aspect: aspect, in: well)
        if fitted.height < well.height * readablePictureFraction {
            let width = min(well.height * aspect, well.width * maxPictureZoom)
            return TilePicture(size: CGSize(width: width, height: width / aspect),
                               crop: .trailing)
        }
        if fitted.width < well.width * readablePictureFraction {
            let height = min(well.width / aspect, well.height * maxPictureZoom)
            return TilePicture(size: CGSize(width: height * aspect, height: height),
                               crop: .bottom)
        }
        return TilePicture(size: fitted, crop: .none)
    }

    /// The biggest `aspect`-shaped box that fits inside `well`.
    private static func fit(aspect: CGFloat, in well: CGSize) -> CGSize {
        let width = min(well.width, well.height * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    // MARK: How sharp the picture behind it has to be

    /// Picture sizes are rounded up to this many pixels before an image is
    /// asked for, so nudging the dock a point wider does not throw away every
    /// picture the shelf has already drawn.
    public static let pictureSourceStep: CGFloat = 128
    /// The most pixels a tile picture is ever worth. A tile is small; past
    /// this the extra pixels are memory nobody can see.
    public static let maxPictureSource: CGFloat = 512

    /// How many pixels the image behind a tile picture needs along its long
    /// side to look sharp at `size` on a Retina screen.
    public static func pictureSourceDimension(for size: CGSize) -> CGFloat {
        let wanted = max(size.width, size.height) * 2
        let stepped = (wanted / pictureSourceStep).rounded(.up) * pictureSourceStep
        return min(max(stepped, pictureSourceStep), maxPictureSource)
    }
}
