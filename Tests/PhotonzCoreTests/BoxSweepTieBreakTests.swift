import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The box sweep settles a tie the same way every time it is run.
///
/// Three places in `BoxSweep` pick a winner out of a `[Int32: Int]` of votes.
/// A dictionary is walked in hash order and Swift reseeds its hashing every
/// process, so when two paints tie on votes the winner used to be whichever the
/// walk happened to reach first — a different answer in a different run of the
/// same app on the same picture.
///
/// That is not a theoretical wobble. Separating `dense-page-1x.png` handed back
/// 355, 357 and 359 as the count of pieces still left in the picture across
/// three runs of the same test on the same bytes, which is a number the app
/// prints to the person in the notice pill. Ties now go to the LOWEST region
/// number, which is the one found first as the picture is read across and down
/// — the same "ties go to whichever came first" rule `SeparateBudget.choose`
/// already follows.
@Suite("Boxes: a tie is settled the same way every run")
struct BoxSweepTieBreakTests {

    /// Two paints covering exactly half the border each. Both clear the share
    /// a background has to hold, so both come back, and the ORDER they come
    /// back in has to be the same every run because the first is the page.
    @Test func twoPaintsTiedOnTheBorderComeBackLowestFirst() {
        let w = 8, h = 8
        var regions = [Int32](repeating: 3, count: w * h)
        // The top half is region 1, the bottom half region 2: each owns exactly
        // half of the border ring.
        for y in 0..<(h / 2) { for x in 0..<w { regions[y * w + x] = 1 } }
        for y in (h / 2)..<h { for x in 0..<w { regions[y * w + x] = 2 } }
        let ranked = BoxSweep.backgroundRegions(regions, w, h)
        #expect(ranked == [1, 2])
    }

    /// The same picture with the two paints numbered the other way round still
    /// ranks the lower number first, so the answer is about the picture and not
    /// about which label the walk handed out.
    @Test func swappingTheNumbersSwapsTheOrderAndNothingElse() {
        let w = 8, h = 8
        var regions = [Int32](repeating: 3, count: w * h)
        for y in 0..<(h / 2) { for x in 0..<w { regions[y * w + x] = 2 } }
        for y in (h / 2)..<h { for x in 0..<w { regions[y * w + x] = 1 } }
        #expect(BoxSweep.backgroundRegions(regions, w, h) == [1, 2])
    }

    /// An island painted half in one colour and half in another has no majority
    /// paint, and the one it is given is the lower number rather than the one
    /// the hash seed reached first.
    @Test func anIslandTiedBetweenTwoPaintsTakesTheLowerNumber() {
        let w = 10, h = 10
        var regions = [Int32](repeating: 0, count: w * h)
        var islands = [Int32](repeating: 0, count: w * h)
        // A 4x4 island at (2,2), its left half paint 7 and its right half
        // paint 4 — a dead tie at eight pixels each.
        for y in 2..<6 {
            for x in 2..<6 {
                islands[y * w + x] = 9
                regions[y * w + x] = x < 4 ? 7 : 4
            }
        }
        var island = BoxSweep.Island(id: 9)
        island.x0 = 2; island.y0 = 2; island.x1 = 5; island.y1 = 5
        island.area = 16
        // Eight votes each, and both clear the share a paint has to hold, so
        // the answer is a tie and the tie goes to the lower number.
        #expect(BoxSweep.dominantRegion(of: island, in: regions,
                                        islands: islands, width: w) == 4)

        // Give paint 7 one more pixel and it wins on votes, tie-break unused.
        regions[2 * w + 4] = 7
        #expect(BoxSweep.dominantRegion(of: island, in: regions,
                                        islands: islands, width: w) == 7)
    }
}
