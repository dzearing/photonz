import CoreGraphics
import PhotonzCore
import Testing

/// The shelf's height math. Every expected number here was measured against a
/// real `LazyVGrid(columns: [.adaptive(minimum: 68, spacing: 8)], spacing: 8)`
/// laid out at the same width, so these tests are the contract that keeps the
/// arithmetic and SwiftUI's own layout in step.
@Suite("LibraryShelfLayout")
struct LibraryShelfLayoutTests {

    // MARK: Columns

    @Test func fitsAsManyTilesAcrossAsTheWidthAllows() {
        #expect(LibraryShelfLayout.columnCount(width: 140) == 1)
        #expect(LibraryShelfLayout.columnCount(width: 190) == 2)
        #expect(LibraryShelfLayout.columnCount(width: 236) == 3)
        #expect(LibraryShelfLayout.columnCount(width: 300) == 4)
        #expect(LibraryShelfLayout.columnCount(width: 380) == 5)
    }

    @Test func neverDropsBelowOneColumnHoweverNarrowTheDockGets() {
        #expect(LibraryShelfLayout.columnCount(width: 0) == 1)
        #expect(LibraryShelfLayout.columnCount(width: -50) == 1)
        #expect(LibraryShelfLayout.columnCount(width: 12) == 1)
    }

    // MARK: Rows

    @Test func wrapsTilesIntoRows() {
        #expect(LibraryShelfLayout.rowCount(tileCount: 0, width: 236) == 0)
        #expect(LibraryShelfLayout.rowCount(tileCount: 1, width: 236) == 1)
        #expect(LibraryShelfLayout.rowCount(tileCount: 3, width: 236) == 1)
        #expect(LibraryShelfLayout.rowCount(tileCount: 4, width: 236) == 2)
        #expect(LibraryShelfLayout.rowCount(tileCount: 13, width: 236) == 5)
    }

    // MARK: Height

    @Test func oneTileIsOneRowTall() {
        #expect(LibraryShelfLayout.contentHeight(tileCount: 1, width: 236) == 72)
    }

    @Test func aFullRowIsNoTallerThanOneTile() {
        #expect(LibraryShelfLayout.contentHeight(tileCount: 2, width: 236) == 72)
        #expect(LibraryShelfLayout.contentHeight(tileCount: 3, width: 236) == 72)
    }

    @Test func everyExtraRowAddsATileAndAGap() {
        #expect(LibraryShelfLayout.contentHeight(tileCount: 4, width: 236) == 148)
        #expect(LibraryShelfLayout.contentHeight(tileCount: 9, width: 236) == 224)
        #expect(LibraryShelfLayout.contentHeight(tileCount: 13, width: 236) == 376)
    }

    @Test func matchesTheMeasuredGridAtEveryDockWidth() {
        // width: tile count: measured height, from a real LazyVGrid.
        let measured: [CGFloat: [Int: CGFloat]] = [
            140: [1: 72, 2: 148, 3: 224, 4: 300, 6: 452, 9: 680, 13: 984],
            190: [1: 72, 2: 72, 3: 148, 4: 148, 6: 224, 9: 376, 13: 528],
            236: [1: 72, 2: 72, 3: 72, 4: 148, 6: 148, 9: 224, 13: 376],
            300: [1: 72, 2: 72, 3: 72, 4: 72, 6: 148, 9: 224, 13: 300],
            380: [1: 72, 2: 72, 3: 72, 4: 72, 6: 148, 9: 148, 13: 224],
        ]
        for (width, byCount) in measured {
            for (count, height) in byCount {
                #expect(LibraryShelfLayout.contentHeight(tileCount: count, width: width) == height,
                        "width \(width), \(count) tiles")
            }
        }
    }

    @Test func anEmptyShelfAsksForNoHeightAtAll() {
        #expect(LibraryShelfLayout.contentHeight(tileCount: 0, width: 236) == 0)
    }

    @Test func aShortShelfHugsItsTilesAndALongOneStopsAtTheCap() {
        // What the panel actually asks for: hug the content, cap at the
        // user's ceiling so the sections below stay in view.
        #expect(LibraryShelfLayout.shelfHeight(tileCount: 1, width: 236, cap: 220) == 72)
        #expect(LibraryShelfLayout.shelfHeight(tileCount: 4, width: 236, cap: 220) == 148)
        #expect(LibraryShelfLayout.shelfHeight(tileCount: 13, width: 236, cap: 220) == 220)
    }

    @Test func aShelfWhoseWidthIsNotKnownYetKeepsTheCap() {
        // First layout pass: nothing has measured the dock yet. Better to
        // stand at the ceiling for one frame than to guess tall and shrink.
        #expect(LibraryShelfLayout.shelfHeight(tileCount: 1, width: 0, cap: 220) == 220)
    }

    @Test func theTileMetricsAddUpToTheRowHeightTheGridDraws() {
        // The tile views build themselves from these, so the arithmetic and
        // the drawing cannot drift apart.
        let tile = LibraryShelfLayout.tilePadding * 2
            + LibraryShelfLayout.thumbnailHeight
            + LibraryShelfLayout.captionSpacing
            + LibraryShelfLayout.captionHeight
        #expect(tile == LibraryShelfLayout.tileHeight)
        #expect(LibraryShelfLayout.tileHeight == 68)
    }

    // MARK: What the picture in a tile well does

    /// The starter set's real sizes, which are what this math was tuned
    /// against. The well is the picture area of one tile in a dock at its
    /// usual width: three tiles across, so 61 points of picture inside the
    /// 44 point well.
    private let well = CGSize(width: 61, height: LibraryShelfLayout.thumbnailHeight - 6)
    private let button = CGSize(width: 128, height: 36)
    private let textField = CGSize(width: 220, height: 32)
    private let card = CGSize(width: 260, height: 180)
    private let navBar = CGSize(width: 320, height: 48)
    private let badge = CGSize(width: 26, height: 20)

    @Test func aShapeThatFitsTheWellIsDrawnWhole() {
        for size in [button, card, badge] {
            let picture = LibraryShelfLayout.picture(size, in: well)
            #expect(picture.crop == .none, "\(size)")
            #expect(picture.size.width <= well.width + 0.01, "\(size)")
            #expect(picture.size.height <= well.height + 0.01, "\(size)")
        }
    }

    @Test func aWholePictureKeepsItsShape() {
        let picture = LibraryShelfLayout.picture(card, in: well)
        #expect(abs(picture.size.width / picture.size.height - card.width / card.height) < 0.001)
    }

    @Test func aShapeTooWideToReadIsBlownUpAndCutOffAtItsTrailingEdge() {
        for size in [textField, navBar] {
            let picture = LibraryShelfLayout.picture(size, in: well)
            #expect(picture.crop == .trailing, "\(size)")
            #expect(picture.size.width > well.width, "\(size)")
            // The point of the exercise: what used to be a 9 point hairline is
            // now most of the well.
            #expect(picture.size.height > well.height / 2, "\(size)")
        }
    }

    @Test func aShapeTooTallToReadIsBlownUpAndCutOffAtItsBottom() {
        let rail = CGSize(width: 64, height: 900)
        let picture = LibraryShelfLayout.picture(rail, in: well)
        #expect(picture.crop == .bottom)
        #expect(picture.size.height > well.height)
        #expect(picture.size.width > 0)
    }

    @Test func aBlownUpPictureKeepsItsShape() {
        // It is magnified, never squashed: the crop is what makes it fit.
        let picture = LibraryShelfLayout.picture(navBar, in: well)
        #expect(abs(picture.size.width / picture.size.height - navBar.width / navBar.height) < 0.001)
        #expect(picture.size.width > well.width)
    }

    @Test func aBlownUpPictureStopsShortOfSwallowingTheWholeWell() {
        // Filling the well outright leaves a quarter of a nav bar in view,
        // which reads as the word "Back" rather than as a bar. Roughly the
        // first half is the trade this makes instead.
        for size in [textField, navBar] {
            let picture = LibraryShelfLayout.picture(size, in: well)
            #expect(picture.size.width <= well.width * LibraryShelfLayout.maxPictureZoom + 0.01, "\(size)")
            #expect(picture.size.height < well.height, "\(size)")
            #expect(well.width / picture.size.width >= 0.39, "\(size)")
        }
    }

    @Test func aWiderTileStopsCroppingBecauseTheWholeThingIsReadableAgain() {
        // Pull the dock wide and a nav bar fits honestly, so nothing is cut.
        let wide = CGSize(width: 200, height: well.height)
        #expect(LibraryShelfLayout.picture(navBar, in: wide).crop == .none)
    }

    @Test func aPictureWithNoSizeAsksForNothing() {
        #expect(LibraryShelfLayout.picture(.zero, in: well).size == .zero)
        #expect(LibraryShelfLayout.picture(navBar, in: .zero).size == .zero)
    }

    // MARK: How sharp the picture behind it has to be

    @Test func asksForEnoughPixelsToDrawThePictureOnARetinaScreen() {
        let picture = LibraryShelfLayout.picture(navBar, in: well)
        let pixels = LibraryShelfLayout.pictureSourceDimension(for: picture.size)
        #expect(pixels >= picture.size.width * 2)
    }

    @Test func asksInStepsSoNudgingTheDockDoesNotRebuildEveryPicture() {
        let a = LibraryShelfLayout.pictureSourceDimension(for: CGSize(width: 60, height: 38))
        let b = LibraryShelfLayout.pictureSourceDimension(for: CGSize(width: 61, height: 38))
        #expect(a == b)
        #expect(a.truncatingRemainder(dividingBy: LibraryShelfLayout.pictureSourceStep) == 0)
    }

    @Test func neverAsksForMorePixelsThanATileCouldUse() {
        let huge = LibraryShelfLayout.pictureSourceDimension(for: CGSize(width: 5000, height: 40))
        #expect(huge == LibraryShelfLayout.maxPictureSource)
    }


    // MARK: Putting a tile on screen

    /// A shelf three tiles across, with the ceiling it ships with: two full
    /// rows show and everything after them is behind the shelf's own scroll.
    private let shelfWidth: CGFloat = 236
    private let shelfHeight: CGFloat = 220

    @Test func putsTheFirstRowRightUnderTheGridMargin() {
        #expect(LibraryShelfLayout.tileTop(index: 0, width: shelfWidth)
                == LibraryShelfLayout.gridVerticalPadding)
        #expect(LibraryShelfLayout.tileTop(index: 2, width: shelfWidth)
                == LibraryShelfLayout.gridVerticalPadding)
    }

    @Test func dropsAFullTileAndAGapForEveryRowBelowTheFirst() {
        let row = LibraryShelfLayout.tileHeight + LibraryShelfLayout.tileSpacing
        #expect(LibraryShelfLayout.tileTop(index: 3, width: shelfWidth)
                == LibraryShelfLayout.gridVerticalPadding + row)
        #expect(LibraryShelfLayout.tileTop(index: 6, width: shelfWidth)
                == LibraryShelfLayout.gridVerticalPadding + row * 2)
    }

    @Test func doesNotMoveAShelfWhoseNewTileIsAlreadyShowing() {
        // The second component someone makes: still on the first row.
        #expect(LibraryShelfLayout.tileReveal(index: 1, width: shelfWidth,
                                              gridTop: 0, viewportHeight: shelfHeight) == .none)
        // The last tile of the second row, which is the last one that fits.
        #expect(LibraryShelfLayout.tileReveal(index: 5, width: shelfWidth,
                                              gridTop: 0, viewportHeight: shelfHeight) == .none)
    }

    @Test func liftsATileThatHasFallenPastTheBottomOfTheShelf() {
        // The seventh component: row three, below the shelf's own fold.
        #expect(LibraryShelfLayout.tileReveal(index: 6, width: shelfWidth,
                                              gridTop: 0, viewportHeight: shelfHeight) == .bottom)
        // Far below it.
        #expect(LibraryShelfLayout.tileReveal(index: 15, width: shelfWidth,
                                              gridTop: 0, viewportHeight: shelfHeight) == .bottom)
    }

    @Test func scrollsBackUpToATileAboveTheShelfsFold() {
        // Someone has scrolled the shelf down two rows and the new tile is on
        // the first one.
        #expect(LibraryShelfLayout.tileReveal(index: 0, width: shelfWidth,
                                              gridTop: -152, viewportHeight: shelfHeight) == .top)
    }

    @Test func doesNothingBeforeTheShelfHasBeenMeasured() {
        #expect(LibraryShelfLayout.tileReveal(index: 6, width: 0,
                                              gridTop: 0, viewportHeight: 0) == .none)
    }
}
