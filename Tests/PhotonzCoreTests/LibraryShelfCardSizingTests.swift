import CoreGraphics
import PhotonzCore
import Testing

/// The Library shelf the video mock draws (`docs/design/mocks/pages/video.html`,
/// the Library group): tiles at least 96 points wide, as many as fit, and a
/// picture that keeps a 16 by 10 shape as the tile grows, so a card reads as a
/// card rather than a list row. `.libgrid` is `repeat(auto-fill,minmax(96px,1fr))`
/// and `.libtile .th` is `aspect-ratio:16/10`.
///
/// Before this the shelf drew 68 point tiles with a fixed 44 point picture,
/// three to a row in a resting dock, and "Tutorial Sample.mp4" read "Tutor....mp4".
@Suite("LibraryShelfLayout card sizing")
struct LibraryShelfCardSizingTests {
    private let card = LibraryShelfLayout.Sizing.card

    /// The shelf in a dock at its resting 264 points: the dock's two 14 point
    /// margins come off, so the grid has 236 across.
    private let resting: CGFloat = 236

    // MARK: What the mock asks for

    @Test func aCardIsAtLeastNinetySixPointsWideWithASixteenByTenPicture() {
        #expect(card.minimumWidth == 96)
        #expect(abs((card.pictureAspect ?? 0) - 1.6) < 0.0001)
    }

    @Test func theOldShelfIsStillThereForTheReleaseThatHasIt() {
        let compact = LibraryShelfLayout.Sizing.compact
        #expect(compact.minimumWidth == LibraryShelfLayout.tileMinimumWidth)
        #expect(compact.pictureAspect == nil)
        #expect(LibraryShelfLayout.thumbnailHeight(width: resting, sizing: compact)
            == LibraryShelfLayout.thumbnailHeight)
        #expect(LibraryShelfLayout.tileHeight(width: resting, sizing: compact)
            == LibraryShelfLayout.tileHeight)
    }

    // MARK: Columns

    @Test func aRestingDockHoldsTwoTilesToARow() {
        #expect(LibraryShelfLayout.columnCount(width: resting, sizing: card) == 2)
        #expect(LibraryShelfLayout.tileWidth(width: resting, sizing: card) == 114)
    }

    @Test func fitsAsManyCardsAcrossAsTheWidthAllows() {
        #expect(LibraryShelfLayout.columnCount(width: 192, sizing: card) == 1)
        #expect(LibraryShelfLayout.columnCount(width: 200, sizing: card) == 2)
        #expect(LibraryShelfLayout.columnCount(width: 300, sizing: card) == 2)
        #expect(LibraryShelfLayout.columnCount(width: 304, sizing: card) == 3)
        #expect(LibraryShelfLayout.columnCount(width: 420, sizing: card) == 4)
    }

    @Test func noCardIsEverNarrowerThanTheMockAllowsOnceThereAreTwo() {
        for width in stride(from: 200.0, through: 600.0, by: 1.0) {
            let tile = LibraryShelfLayout.tileWidth(width: CGFloat(width), sizing: card)
            #expect(tile >= 96, "width \(width)")
        }
    }

    @Test func aDockTooNarrowForTwoGivesItsOneTileTheWholeWidth() {
        #expect(LibraryShelfLayout.tileWidth(width: 192, sizing: card) == 192)
        #expect(LibraryShelfLayout.columnCount(width: 0, sizing: card) == 1)
    }

    // MARK: The picture grows with the tile

    @Test func thePictureRunsEdgeToEdgeInsideTheCardsBorder() {
        // 114 across, a 1 point border each side: a 112 point picture, 70 tall.
        #expect(LibraryShelfLayout.cardBorder == 1)
        #expect(LibraryShelfLayout.pictureWidth(width: resting, sizing: card) == 112)
        #expect(LibraryShelfLayout.thumbnailHeight(width: resting, sizing: card) == 70)
        for width in [192.0, 236.0, 300.0, 320.0, 420.0] as [CGFloat] {
            let tile = LibraryShelfLayout.tileWidth(width: width, sizing: card)
            let picture = LibraryShelfLayout.pictureWidth(width: width, sizing: card)
            #expect(picture == tile - LibraryShelfLayout.cardBorder * 2, "width \(width)")
            let height = LibraryShelfLayout.thumbnailHeight(width: width, sizing: card)
            // Whole points, so the drawing and the arithmetic land on the same
            // pixel, and never more than a point off the true shape.
            #expect(height == height.rounded(.down), "width \(width)")
            #expect(abs(picture / 1.6 - height) < 1, "width \(width)")
        }
    }

    @Test func aCompactTileKeepsItsPaddedPicture() {
        let compact = LibraryShelfLayout.Sizing.compact
        #expect(!compact.isCard)
        #expect(card.isCard)
        #expect(LibraryShelfLayout.pictureWidth(width: resting, sizing: compact)
            == LibraryShelfLayout.tileWidth(width: resting, sizing: compact)
                - LibraryShelfLayout.tilePadding * 2)
    }

    @Test func aWiderTileIsATallerTile() {
        let two = LibraryShelfLayout.tileHeight(width: 236, sizing: card)
        let twoWider = LibraryShelfLayout.tileHeight(width: 300, sizing: card)
        #expect(twoWider > two)
    }

    // MARK: The caption under the picture

    /// The mock's `.cap` is `padding:5px 7px 6px; gap:1px`, a 10.5 point name
    /// in `--ink` at weight 560 and a 9 point mono line in `--faint` under it.
    @Test func theCaptionIsTheMocksTwoLinesInItsPadding() {
        #expect(LibraryShelfLayout.cardCaptionTop == 5)
        #expect(LibraryShelfLayout.cardCaptionBottom == 6)
        #expect(LibraryShelfLayout.cardCaptionHorizontal == 7)
        #expect(LibraryShelfLayout.cardCaptionGap == 1)
        #expect(LibraryShelfLayout.cardNameFontSize == 10.5)
        #expect(LibraryShelfLayout.cardMetaFontSize == 9)
        // Measured with ImageRenderer on 2026-09-27: the name 13, the meta 11.
        #expect(LibraryShelfLayout.cardNameHeight == 13)
        #expect(LibraryShelfLayout.cardMetaHeight == 11)
        // 5 + 13 + 1 + 11 + 6
        #expect(LibraryShelfLayout.cardCaptionHeight == 36)
    }

    @Test func theCardAddsUpToTheRowHeightTheGridDraws() {
        for width in [192.0, 236.0, 300.0, 420.0] as [CGFloat] {
            let tile = LibraryShelfLayout.cardBorder * 2
                + LibraryShelfLayout.thumbnailHeight(width: width, sizing: card)
                + LibraryShelfLayout.cardCaptionHeight
            #expect(tile == LibraryShelfLayout.tileHeight(width: width, sizing: card))
        }
        // The mock measures 112 by 105 at a 256 point dock; this card is two
        // points wider, so its picture is a point taller, and the app's lines
        // are a little taller than the browser's.
        #expect(LibraryShelfLayout.tileHeight(width: resting, sizing: card) == 108)
    }

    // MARK: Height

    @Test func theShelfIsAsTallAsItsRowsOfCards() {
        // Two to a row at rest, each row 108 with an 8 point gap between.
        #expect(LibraryShelfLayout.contentHeight(tileCount: 0, width: resting, sizing: card) == 0)
        #expect(LibraryShelfLayout.contentHeight(tileCount: 1, width: resting, sizing: card) == 112)
        #expect(LibraryShelfLayout.contentHeight(tileCount: 2, width: resting, sizing: card) == 112)
        #expect(LibraryShelfLayout.contentHeight(tileCount: 3, width: resting, sizing: card) == 228)
        #expect(LibraryShelfLayout.contentHeight(tileCount: 5, width: resting, sizing: card) == 344)
    }

    @Test func aLongShelfStopsAtTheCap() {
        #expect(LibraryShelfLayout.shelfHeight(tileCount: 2, width: resting, cap: 220, sizing: card) == 112)
        #expect(LibraryShelfLayout.shelfHeight(tileCount: 3, width: resting, cap: 240, sizing: card) == 228)
        #expect(LibraryShelfLayout.shelfHeight(tileCount: 9, width: resting, cap: 220, sizing: card) == 220)
        #expect(LibraryShelfLayout.shelfHeight(tileCount: 1, width: 0, cap: 220, sizing: card) == 220)
    }

    // MARK: Putting one tile on screen

    @Test func everyRowBelowTheFirstDropsACardAndAGap() {
        let row = LibraryShelfLayout.tileHeight(width: resting, sizing: card) + LibraryShelfLayout.tileSpacing
        #expect(LibraryShelfLayout.tileTop(index: 1, width: resting, sizing: card)
            == LibraryShelfLayout.gridVerticalPadding)
        #expect(LibraryShelfLayout.tileTop(index: 2, width: resting, sizing: card)
            == LibraryShelfLayout.gridVerticalPadding + row)
        #expect(LibraryShelfLayout.tileTop(index: 5, width: resting, sizing: card)
            == LibraryShelfLayout.gridVerticalPadding + row * 2)
    }

    @Test func liftsACardThatHasFallenPastTheShelfsFold() {
        // A 240 point shelf shows two rows of cards (2 + 108 + 8 + 108 = 226):
        // the fifth card starts the third row, below the fold.
        #expect(LibraryShelfLayout.tileReveal(index: 3, width: resting, gridTop: 0,
                                              viewportHeight: 240, sizing: card) == .none)
        #expect(LibraryShelfLayout.tileReveal(index: 4, width: resting, gridTop: 0,
                                              viewportHeight: 240, sizing: card) == .bottom)
    }

    // MARK: How tall the shelf starts

    @Test func aFreshCardShelfShowsTwoWholeRowsAndASliver() {
        // Left at 220 a resting card shelf cut its second row through the
        // line under the names. Its first ceiling is two whole rows, the gap
        // under them and the dock's 22 point peek of the third.
        let cap = LibraryShelfLayout.defaultCap(sizing: card)
        #expect(cap == LibraryShelfLayout.gridVerticalPadding
            + LibraryShelfLayout.tileHeight(width: resting, sizing: card) * 2
            + LibraryShelfLayout.tileSpacing * 2 + 22)
        #expect(cap == 256)
        #expect(LibraryShelfLayout.tileReveal(index: 3, width: resting, gridTop: 0,
                                              viewportHeight: cap, sizing: card) == .none)
    }

    @Test func theCompactShelfKeepsItsFirstCeiling() {
        #expect(LibraryShelfLayout.defaultCap(sizing: .compact) == 220)
    }

    // MARK: The least room a shelf may be squeezed to

    @Test func theSmallestShelfStillHoldsAWholeRowOfCardsAndASliver() {
        let floor = LibraryShelfLayout.squeezeFloor(peek: 22, width: resting, sizing: card)
        #expect(floor == LibraryShelfLayout.gridVerticalPadding
            + LibraryShelfLayout.tileHeight(width: resting, sizing: card)
            + LibraryShelfLayout.tileSpacing + 22)
        #expect(floor == 140)
        // A whole card, caption and all, is inside it.
        #expect(LibraryShelfLayout.tileTop(index: 0, width: resting, sizing: card)
            + LibraryShelfLayout.tileHeight(width: resting, sizing: card) <= floor)
    }

    @Test func aWiderDockRaisesTheFloorBecauseItsCardsAreTaller() {
        let resting = LibraryShelfLayout.squeezeFloor(peek: 22, width: 236, sizing: card)
        let wider = LibraryShelfLayout.squeezeFloor(peek: 22, width: 300, sizing: card)
        #expect(wider > resting)
    }

    @Test func aShelfNotYetMeasuredFloorsAtTheNarrowestCard() {
        // Before the dock is measured there is no width, and the floor stands
        // on a card at its minimum width rather than on nothing.
        #expect(LibraryShelfLayout.squeezeFloor(peek: 22, width: 0, sizing: card)
            == LibraryShelfLayout.squeezeFloor(peek: 22, width: 96, sizing: card))
    }

    @Test func theCompactFloorIsUnchanged() {
        #expect(LibraryShelfLayout.squeezeFloor(peek: 22, width: resting, sizing: .compact)
            == LibraryShelfLayout.squeezeFloor(peek: 22))
    }

    // MARK: Names read whole

    @Test func aCardLeavesRoomForTheNamesTheMockShows() {
        // "Tutorial Sample.mp4" at the name's 10.5 point medium weight is about
        // 98 points; a resting card gives its name the tile less its border
        // and the caption's side padding.
        let caption = LibraryShelfLayout.tileWidth(width: resting, sizing: card)
            - LibraryShelfLayout.cardBorder * 2 - LibraryShelfLayout.cardCaptionHorizontal * 2
        #expect(caption == 98)
    }

    // MARK: Where it ships

    @Test func itShipsOnByDefaultInNextOnly() {
        #expect(FeatureCatalog.defaultSettings(for: .next)
            .isEnabled(FeatureCatalog.libraryTilesAsCardsFlag))
        #expect(!FeatureCatalog.flags(for: .current)
            .contains { $0.name == FeatureCatalog.libraryTilesAsCardsFlag })
    }
}
