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

    // MARK: How big a tile is

    /// How a release sizes its tiles. Everything that depends on how wide a
    /// tile is takes one of these, so the grid, the height arithmetic and the
    /// tile views all agree on the same tile.
    public struct Sizing: Equatable, Sendable {
        /// The narrowest a tile may be before the grid drops a column.
        public var minimumWidth: CGFloat
        /// The picture's width over its height, so it grows with the tile.
        /// Nil keeps the picture at the fixed `thumbnailHeight` however wide
        /// the tile is.
        public var pictureAspect: CGFloat?

        public init(minimumWidth: CGFloat, pictureAspect: CGFloat?) {
            self.minimumWidth = minimumWidth
            self.pictureAspect = pictureAspect
        }

        /// The shelf Current ships: 68 point tiles with a 44 point picture,
        /// three to a row in a resting dock.
        public static let compact = Sizing(minimumWidth: tileMinimumWidth, pictureAspect: nil)

        /// The shelf the video mock draws (`.libgrid` is
        /// `repeat(auto-fill,minmax(96px,1fr))`, `.libtile .th` is
        /// `aspect-ratio:16/10`): two cards to a row in a resting dock, each
        /// picture keeping its shape as the card grows, so a card reads as a
        /// card and a name like "Tutorial Sample.mp4" reads whole.
        public static let card = Sizing(minimumWidth: 96, pictureAspect: 16.0 / 10.0)
    }

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

    // MARK: The words in the corners of a tile picture

    /// A tile picture wears at most two little words: which drawing it shows,
    /// in the bottom right, and where the component came from, in the bottom
    /// left. Both sit INSIDE the picture well, which is the whole point of
    /// putting them there: the shelf is height-capped, so a word under the
    /// name would cost every row of tiles and the tile is 68 points exactly.
    public static let tileBadgeFontSize: CGFloat = 8
    /// One line of that word, measured the way the caption is.
    public static let tileBadgeLineHeight: CGFloat = 10
    /// The capsule's own breathing room around the word.
    public static let tileBadgeHorizontalPadding: CGFloat = 3
    public static let tileBadgeVerticalPadding: CGFloat = 1
    /// How far in from the corner of the well the capsule sits.
    public static let tileBadgeInset: CGFloat = 2

    /// The capsule itself, word and padding. This is the part that actually
    /// covers picture, so it is what has to stay small against
    /// `thumbnailHeight`.
    public static let tileBadgeCapsuleHeight: CGFloat =
        tileBadgeLineHeight + tileBadgeVerticalPadding * 2

    /// The capsule plus the air it sits in from the corner: how much of the
    /// well's height one corner word claims in all.
    public static let tileBadgeFootprint: CGFloat =
        tileBadgeCapsuleHeight + tileBadgeInset * 2

    /// One tile, top to bottom.
    public static let tileHeight: CGFloat =
        tilePadding * 2 + thumbnailHeight + captionSpacing + captionHeight

    // MARK: The shelf

    /// How many tiles fit across `width`, which is what an adaptive grid works
    /// out for itself. Always at least one, however narrow the dock is pulled.
    public static func columnCount(width: CGFloat, sizing: Sizing = .compact) -> Int {
        guard width > 0 else { return 1 }
        let columns = Int((width + tileSpacing) / (sizing.minimumWidth + tileSpacing))
        return max(1, columns)
    }

    /// How wide each tile is drawn at `width`: an adaptive grid shares out
    /// what is left after the gaps equally. Before the dock is measured there
    /// is no width, and a tile stands at its minimum.
    public static func tileWidth(width: CGFloat, sizing: Sizing = .compact) -> CGFloat {
        guard width > 0 else { return sizing.minimumWidth }
        let columns = CGFloat(columnCount(width: width, sizing: sizing))
        return (width - tileSpacing * (columns - 1)) / columns
    }

    /// How tall the picture well is at `width`. Whole points, so the tile
    /// views and this arithmetic land on the same pixel.
    public static func thumbnailHeight(width: CGFloat, sizing: Sizing = .compact) -> CGFloat {
        guard let aspect = sizing.pictureAspect, aspect > 0 else { return thumbnailHeight }
        let picture = tileWidth(width: width, sizing: sizing) - tilePadding * 2
        return max(1, (picture / aspect).rounded(.down))
    }

    /// One tile, top to bottom, at `width`.
    public static func tileHeight(width: CGFloat, sizing: Sizing = .compact) -> CGFloat {
        tilePadding * 2 + thumbnailHeight(width: width, sizing: sizing) + captionSpacing + captionHeight
    }

    /// How many rows `tileCount` tiles wrap into at `width`.
    public static func rowCount(tileCount: Int, width: CGFloat, sizing: Sizing = .compact) -> Int {
        guard tileCount > 0 else { return 0 }
        let columns = columnCount(width: width, sizing: sizing)
        return (tileCount + columns - 1) / columns
    }

    /// The height the grid would take if nothing capped it.
    public static func contentHeight(tileCount: Int, width: CGFloat, sizing: Sizing = .compact) -> CGFloat {
        let rows = rowCount(tileCount: tileCount, width: width, sizing: sizing)
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * tileHeight(width: width, sizing: sizing)
            + CGFloat(rows - 1) * tileSpacing
            + gridVerticalPadding * 2
    }

    /// The least room the shelf may be squeezed to: one whole row of tiles.
    ///
    /// A tile is a picture with its NAME under it, and the name is the whole of
    /// what a tile says. So a shelf cut across a row does not read as "there is
    /// more below" the way a cut list of rows does — it reads as a row of
    /// anonymous pictures, and the thing the app was pointing at has lost the
    /// only label it had.
    ///
    /// Measured on the probe on 2026-09-16: six tutorial walks rang the Library
    /// with the dock squeezing its body to the generic 112 point list floor
    /// (`DockMetrics.listFloor`), and every one of them photographed the tile
    /// the guide was talking about with its caption cut away. "The Brand tile
    /// that just landed" over a shelf with no word Brand on it.
    ///
    /// Independent of width, because a wider dock puts more tiles ON a row
    /// rather than making the row taller.
    public static let oneRowHeight: CGFloat = contentHeight(tileCount: 1, width: tileMinimumWidth)

    /// The least room the shelf may be squeezed to when there is more of it
    /// under the cut: one whole row, and then a sliver of the row below.
    ///
    /// `oneRowHeight` on its own is honest about the row it shows and silent
    /// about the rows it does not. Squeezed to it, the shelf ends on clean
    /// glass under a full row of named tiles, which reads as the whole list —
    /// on 2026-09-17 a shelf cut to three of the app's five starters was read
    /// that way by an audit, which reported the Nav Bar component missing from
    /// an app that had it all along.
    ///
    /// So the floor buys the same cue every other shortened body in the dock
    /// gets: enough of the next thing showing through the fade to mean "there
    /// is more this way" rather than "that is all". The sliver is TILE and not
    /// the gap above it, because a cut landing in the gap ends the shelf on
    /// background and says nothing.
    ///
    /// A shelf that fits in one row is not padded out to show a sliver of
    /// nothing: `shelfHeight` never draws more than the content, so the extra
    /// is only ever spent when there is a row to spend it on.
    ///
    /// - Parameter peek: how much of the next row to keep on screen. The dock's
    ///   own `bodyPeek`, handed in rather than pinned here, so the shelf uses
    ///   the same number as every other cut body in the panel.
    public static func squeezeFloor(peek: CGFloat) -> CGFloat {
        gridVerticalPadding + tileHeight + tileSpacing + max(0, peek)
    }

    /// The same floor for a shelf whose tiles grow with the dock: one whole
    /// row at `width`, and the sliver. A card shelf pulled wider has taller
    /// cards, so its floor rises with it, or the caption of the row it keeps
    /// would be the part the dock cuts away.
    public static func squeezeFloor(peek: CGFloat, width: CGFloat, sizing: Sizing) -> CGFloat {
        let measured = width > 0 ? width : sizing.minimumWidth
        return gridVerticalPadding + tileHeight(width: measured, sizing: sizing) + tileSpacing + max(0, peek)
    }

    /// The height the shelf actually takes: its content, but never more than
    /// the ceiling the drag handle sets, so the sections under it stay in view
    /// and a long shelf scrolls on its own.
    ///
    /// Before anything has measured the dock, `width` is zero and there is no
    /// honest answer, so the shelf stands at its ceiling for that one frame
    /// rather than guessing a tall column and visibly collapsing.
    public static func shelfHeight(tileCount: Int, width: CGFloat, cap: CGFloat,
                                   sizing: Sizing = .compact) -> CGFloat {
        guard width > 0 else { return cap }
        return min(contentHeight(tileCount: tileCount, width: width, sizing: sizing), cap)
    }

    // MARK: Putting one tile on screen

    /// Where the tile at `index` starts, measured down from the top of the
    /// grid. Worked out rather than measured, for the same reason the shelf's
    /// height is: a lazy grid has not built the row a tile is on until that row
    /// is on screen, so a tile below the fold cannot be asked where it is —
    /// which is exactly the tile that needs moving.
    public static func tileTop(index: Int, width: CGFloat, sizing: Sizing = .compact) -> CGFloat {
        guard index > 0 else { return gridVerticalPadding }
        let row = index / columnCount(width: width, sizing: sizing)
        return gridVerticalPadding + CGFloat(row) * (tileHeight(width: width, sizing: sizing) + tileSpacing)
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
                                  gridTop: CGFloat, viewportHeight: CGFloat,
                                  sizing: Sizing = .compact) -> DockReveal.Action {
        DockReveal.action(sectionTop: gridTop + tileTop(index: index, width: width, sizing: sizing),
                          sectionHeight: tileHeight(width: width, sizing: sizing),
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
