import CoreGraphics
import PhotonzCore
import Testing

/// The column count and tile width of the video tile grids (transition
/// picker, caption styles, arrow styles). On 2026-10-01 the probe died in
/// this arithmetic: SwiftUI offered the grid an unbounded width while
/// measuring it, the width became a column count, and turning an infinite
/// count into an `Int` traps.
@Suite("Tile grid plan")
struct TileGridPlanTests {
    @Test func anUnboundedOfferIsAnsweredWithTheNarrowestGridNotATrap() {
        let plan = TileGridPlan(offeredWidth: .infinity, minimumWidth: 96, spacing: 8, columns: nil)
        #expect(plan.width == 200)
        #expect(plan.columns == 2)
        #expect(plan.tileWidth == 96)
    }

    @Test func anUnboundedOfferToAPinnedGridKeepsItsColumnsAndAFiniteWidth() {
        // Every grid in the app pins its columns, and the trap fired anyway:
        // the fitted count was worked out before the pinned one replaced it.
        let plan = TileGridPlan(offeredWidth: .infinity, minimumWidth: 60, spacing: 6, columns: 3)
        #expect(plan.columns == 3)
        #expect(plan.width.isFinite)
        #expect(plan.tileWidth.isFinite)
        #expect(plan.tileWidth > 0)
    }

    @Test func noOfferAndANonsenseOfferBothGetTheNarrowestGrid() {
        for offer in [nil, CGFloat.nan, -CGFloat.infinity] as [CGFloat?] {
            let plan = TileGridPlan(offeredWidth: offer, minimumWidth: 96, spacing: 8, columns: nil)
            #expect(plan.width == 200, "\(String(describing: offer))")
            #expect(plan.columns == 2, "\(String(describing: offer))")
        }
    }

    @Test func aHugeFiniteOfferIsCappedRatherThanOverflowing() {
        let plan = TileGridPlan(offeredWidth: CGFloat.greatestFiniteMagnitude, minimumWidth: 96, spacing: 8, columns: nil)
        #expect(plan.columns <= 1000)
        #expect(plan.tileWidth.isFinite)
    }

    @Test func asManyColumnsAsFitAtTheMinimumWidth() {
        // The dock at rest holds two cards; widened, four.
        #expect(TileGridPlan(offeredWidth: 220, minimumWidth: 96, spacing: 8, columns: nil).columns == 2)
        #expect(TileGridPlan(offeredWidth: 408, minimumWidth: 96, spacing: 8, columns: nil).columns == 4)
        let plan = TileGridPlan(offeredWidth: 220, minimumWidth: 96, spacing: 8, columns: nil)
        #expect(plan.tileWidth == 106)
    }

    @Test func aGridNarrowerThanOneTileStillHasOneColumn() {
        let plan = TileGridPlan(offeredWidth: 40, minimumWidth: 96, spacing: 8, columns: nil)
        #expect(plan.columns == 1)
        #expect(plan.tileWidth == 40)
    }

    @Test func aPinnedCountWinsAndTilesShareTheWidth() {
        let plan = TileGridPlan(offeredWidth: 232, minimumWidth: 96, spacing: 8, columns: 2)
        #expect(plan.columns == 2)
        #expect(plan.tileWidth == 112)
        #expect(TileGridPlan(offeredWidth: 232, minimumWidth: 96, spacing: 8, columns: 0).columns == 1)
    }

    @Test func aWidthTooSmallForTheGapsNeverGivesANegativeTile() {
        let plan = TileGridPlan(offeredWidth: 4, minimumWidth: 60, spacing: 6, columns: 3)
        #expect(plan.tileWidth == 0)
    }
}
