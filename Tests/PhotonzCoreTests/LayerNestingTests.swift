import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The rule that turns a pile of separated pieces into a tree: a label that
/// sits in a button is a child of that button, a row inside a card sits under
/// the card, and a piece that belongs to nothing stays where it is.
///
/// Full design: `docs/design/separate-into-layers.md`, "Which piece sits in
/// which".
@Suite("Nesting separated pieces the way the screen is arranged")
struct LayerNestingTests {

    /// Every index in a forest, so a test can prove a piece is in exactly one
    /// place.
    private func indices(_ nodes: [LayerNesting.Node]) -> [Int] {
        nodes.flatMap { [$0.index] + indices($0.children) }
    }

    private func node(_ nodes: [LayerNesting.Node], _ index: Int) -> LayerNesting.Node? {
        for node in nodes {
            if node.index == index { return node }
            if let found = self.node(node.children, index) { return found }
        }
        return nil
    }

    // MARK: - The case the whole task is named after

    @Test func aLabelInsideAButtonBecomesAChildOfThatButton() {
        // The button, then the words sitting on it.
        let tree = LayerNesting.nest([
            CGRect(x: 233, y: 756, width: 248, height: 60),
            CGRect(x: 272, y: 776, width: 170, height: 25),
        ])
        #expect(tree.count == 1)
        #expect(tree[0].index == 0)
        #expect(tree[0].children.map(\.index) == [1])
    }

    @Test func aPieceThatBelongsToNothingStaysAtTheTop() {
        // A heading on the page, a button, and the button's label. The heading
        // is inside nothing, so it stays a top level piece rather than being
        // forced into a group that does not fit it.
        let tree = LayerNesting.nest([
            CGRect(x: 66, y: 60, width: 200, height: 40),
            CGRect(x: 233, y: 756, width: 248, height: 60),
            CGRect(x: 272, y: 776, width: 170, height: 25),
        ])
        #expect(tree.map(\.index) == [0, 1])
        #expect(tree[0].children.isEmpty)
        #expect(tree[1].children.map(\.index) == [2])
    }

    // MARK: - Depth

    @Test func nestingGoesAsDeepAsTheScreenDoes() {
        // A card, a row on it, and a label on the row: three deep, because the
        // screen is three deep. Nothing in the rule stops at two.
        let card = CGRect(x: 40, y: 40, width: 600, height: 400)
        let row = CGRect(x: 60, y: 80, width: 560, height: 60)
        let label = CGRect(x: 80, y: 96, width: 180, height: 24)
        let tree = LayerNesting.nest([card, row, label])
        #expect(tree.map(\.index) == [0])
        #expect(tree[0].children.map(\.index) == [1])
        #expect(tree[0].children[0].children.map(\.index) == [2])
    }

    @Test func aPieceGoesInTheInnermostThingThatHoldsIt() {
        // The same three rungs handed over in the other order: the label still
        // lands in the row, never in the card as well.
        let tree = LayerNesting.nest([
            CGRect(x: 80, y: 96, width: 180, height: 24),
            CGRect(x: 60, y: 80, width: 560, height: 60),
            CGRect(x: 40, y: 40, width: 600, height: 400),
        ])
        #expect(indices(tree).sorted() == [0, 1, 2])
        #expect(node(tree, 1)?.children.map(\.index) == [0])
        #expect(node(tree, 2)?.children.map(\.index) == [1])
    }

    // MARK: - Exactly one parent, never two

    @Test func aPieceOverlappingTwoBoxesIsPutInNeither() {
        // A run of text that straddles the seam between two cards is inside
        // neither of them: a piece is a child only of something that HOLDS it,
        // and half of it is not held.
        let left = CGRect(x: 0, y: 0, width: 100, height: 100)
        let right = CGRect(x: 100, y: 0, width: 100, height: 100)
        let straddling = CGRect(x: 60, y: 40, width: 80, height: 20)
        let tree = LayerNesting.nest([left, right, straddling])
        #expect(tree.map(\.index) == [0, 1, 2])
        #expect(tree[0].children.isEmpty)
        #expect(tree[1].children.isEmpty)
    }

    @Test func everyPieceAppearsExactlyOnce() {
        let rects = [
            CGRect(x: 0, y: 0, width: 400, height: 400),
            CGRect(x: 20, y: 20, width: 200, height: 100),
            CGRect(x: 30, y: 40, width: 80, height: 20),
            CGRect(x: 500, y: 0, width: 60, height: 60),
            CGRect(x: 380, y: 380, width: 80, height: 40),
        ]
        let tree = LayerNesting.nest(rects)
        #expect(indices(tree).sorted() == [0, 1, 2, 3, 4])
        #expect(indices(tree).count == Set(indices(tree)).count)
    }

    @Test func aPieceThatJustOverhangsItsBoxIsStillInIt() {
        // The cut grows a run of text by a couple of pixels before it is taken,
        // so a label that filled its button edge to edge comes back very
        // slightly proud of it. That is still the button's label.
        let button = CGRect(x: 100, y: 100, width: 200, height: 40)
        let label = CGRect(x: 98, y: 102, width: 204, height: 36)
        let tree = LayerNesting.nest([button, label])
        #expect(tree.count == 1)
        #expect(tree[0].children.map(\.index) == [1])
    }

    @Test func aPieceHalfOutOfItsBoxIsNotInIt() {
        let button = CGRect(x: 100, y: 100, width: 200, height: 40)
        let hanging = CGRect(x: 200, y: 100, width: 200, height: 40)
        #expect(LayerNesting.nest([button, hanging]).count == 2)
    }

    // MARK: - Things that must not swallow each other

    @Test func twoPiecesTheSameSizeDoNotSwallowEachOther() {
        let rect = CGRect(x: 10, y: 10, width: 50, height: 50)
        let tree = LayerNesting.nest([rect, rect])
        #expect(tree.map(\.index) == [0, 1])
        #expect(tree[0].children.isEmpty)
        #expect(tree[1].children.isEmpty)
    }

    @Test func anEmptyPieceIsNobodysChildAndNobodysParent() {
        let box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let nothing = CGRect(x: 20, y: 20, width: 0, height: 0)
        let tree = LayerNesting.nest([box, nothing])
        #expect(tree.map(\.index) == [0, 1])
        #expect(tree[0].children.isEmpty)
    }

    @Test func nothingAtAllNestsIntoNothingAtAll() {
        #expect(LayerNesting.nest([]).isEmpty)
    }

    // MARK: - Order

    @Test func theOrderInsideEachLevelIsTheOrderItCameIn() {
        // The separator hands its pieces over bottom-most first, and that is
        // the stacking order: a label sits ON the button it came off. Nesting
        // must not reshuffle it.
        let card = CGRect(x: 0, y: 0, width: 400, height: 400)
        let tree = LayerNesting.nest([
            card,
            CGRect(x: 10, y: 10, width: 40, height: 20),
            CGRect(x: 10, y: 40, width: 40, height: 20),
            CGRect(x: 10, y: 70, width: 40, height: 20),
        ])
        #expect(tree[0].children.map(\.index) == [1, 2, 3])
    }

    @Test func aDeepTreeReportsItsOwnDepth() {
        let tree = LayerNesting.nest([
            CGRect(x: 0, y: 0, width: 400, height: 400),
            CGRect(x: 10, y: 10, width: 200, height: 200),
            CGRect(x: 20, y: 20, width: 100, height: 100),
            CGRect(x: 30, y: 30, width: 40, height: 40),
        ])
        #expect(LayerNesting.depth(of: tree) == 4)
        #expect(LayerNesting.depth(of: []) == 0)
    }
}
