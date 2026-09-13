import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// How much one Separate into Layers is allowed to take out of one picture.
///
/// Measured on real captures: a settings pane offers eleven pieces, a whole
/// app window ninety three, and a dense web page three hundred and ninety. The
/// first two are a layers list; the third is a wall. This is the rule that
/// decides where the wall starts and what happens on the other side of it.
///
/// Full design: `docs/design/separate-into-layers.md`.
@Suite("What one Separate is allowed to take")
struct SeparateBudgetTests {

    private func rects(_ sizes: [Double]) -> [CGRect] {
        sizes.enumerated().map { CGRect(x: 0, y: Double($0.offset) * 100,
                                        width: $0.element, height: $0.element) }
    }

    @Test func aPictureUnderTheLimitComesOutWhole() {
        let choice = SeparateBudget.choose(rects([10, 20, 30]), limit: 5)
        #expect(choice.kept == [0, 1, 2])
        #expect(choice.crowdedOut == 0)
    }

    @Test func pastTheLimitTheBiggestPiecesComeOut() {
        // The small ones on a dense page are the hundredth label, which is
        // exactly the piece nobody was going to reach for. The big ones are
        // the headings, the cards and the buttons.
        let choice = SeparateBudget.choose(rects([10, 90, 20, 80]), limit: 2)
        #expect(choice.kept == [1, 3])
        #expect(choice.crowdedOut == 2)
    }

    @Test func whatIsKeptStaysInReadingOrder() {
        // The kept pieces come back in the order they were handed over, which
        // is reading order — so the names still run down the page rather than
        // down a size chart.
        let choice = SeparateBudget.choose(rects([50, 10, 60, 20, 70]), limit: 3)
        #expect(choice.kept == [0, 2, 4])
    }

    @Test func twoPiecesOfTheSameSizeAreTakenInTheOrderTheyCameIn() {
        let choice = SeparateBudget.choose(rects([40, 40, 40]), limit: 2)
        #expect(choice.kept == [0, 1])
        #expect(choice.crowdedOut == 1)
    }

    @Test func aLimitOfNothingTakesNothingAndSaysSo() {
        let choice = SeparateBudget.choose(rects([10, 20]), limit: 0)
        #expect(choice.kept.isEmpty)
        #expect(choice.crowdedOut == 2)
    }

    @Test func theLimitsAreTheOnesTheDesignDocQuotes() {
        // If these move, the sentence in the design doc and the one in the
        // pill move with them.
        #expect(SeparateBudget.maxTextRuns == 150)
        #expect(SeparateBudget.maxBoxes == 30)
        #expect(SeparateBudget.maxDepth == 4)
    }
}

/// The other half of "the layers list stays usable": how DEEP the tree may go.
@Suite("How deep a separated tree may go")
struct SeparateDepthTests {

    /// `count` rectangles, each one comfortably inside the one before it.
    private func nestedPile(_ count: Int) -> [CGRect] {
        (0..<count).map {
            CGRect(x: Double($0) * 10, y: Double($0) * 10,
                   width: 1000 - Double($0) * 40, height: 1000 - Double($0) * 40)
        }
    }

    @Test func aTreeInsideTheLimitIsLeftAlone() {
        let nodes = LayerNesting.nest(nestedPile(4))
        #expect(LayerNesting.depth(of: nodes) == 4)
        // Still one ladder: each piece holds the next.
        #expect(nodes.count == 1)
    }

    @Test func aDeeperPileStopsAtTheLimit() {
        let nodes = LayerNesting.nest(nestedPile(7))
        #expect(LayerNesting.depth(of: nodes) == SeparateBudget.maxDepth)
    }

    @Test func nothingIsLostWhenATreeIsFlattenedToTheLimit() {
        // A piece past the limit does not disappear: it joins the deepest
        // group it is allowed to be in, so it is still inside the thing a
        // person would drag.
        let nodes = LayerNesting.nest(nestedPile(7))
        func indices(_ nodes: [LayerNesting.Node]) -> [Int] {
            nodes.flatMap { [$0.index] + indices($0.children) }
        }
        #expect(indices(nodes).sorted() == Array(0..<7))
    }

    @Test func thePiecesPastTheLimitLandInTheLastGroupThatHoldsThem() {
        let nodes = LayerNesting.nest(nestedPile(7))
        // Level 1 holds 2 holds 3, and the fourth level is where 3, 4, 5 and 6
        // all end up together rather than each inside the last.
        var node = nodes[0]
        for _ in 0..<2 {
            #expect(node.children.count == 1)
            node = node.children[0]
        }
        #expect(node.children.map(\.index) == [3, 4, 5, 6])
        #expect(LayerNesting.depth(of: node.children) == 1)
    }
}
