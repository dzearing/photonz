import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("Lining layers up with each other")
struct LayerArrangementTests {
    /// Three buttons at rough positions, the case the whole feature exists for.
    let a = LayerArrangement.Box(id: UUID(), frame: CGRect(x: 10, y: 20, width: 100, height: 40))
    let b = LayerArrangement.Box(id: UUID(), frame: CGRect(x: 40, y: 90, width: 60, height: 30))
    let c = LayerArrangement.Box(id: UUID(), frame: CGRect(x: 25, y: 160, width: 80, height: 50))

    var boxes: [LayerArrangement.Box] { [a, b, c] }

    // MARK: Align

    @Test func alignsLeftEdgesToTheLeftmostLayer() {
        let moves = LayerArrangement.aligned(boxes, to: .left)
        #expect(moves[a.id] == nil) // already leftmost: it does not move
        #expect(moves[b.id] == CGPoint(x: 10, y: 90))
        #expect(moves[c.id] == CGPoint(x: 10, y: 160))
    }

    @Test func alignsRightEdgesToTheRightmostLayer() {
        let moves = LayerArrangement.aligned(boxes, to: .right)
        #expect(moves[a.id] == nil) // right edge 110 is the rightmost
        #expect(moves[b.id] == CGPoint(x: 50, y: 90))
        #expect(moves[c.id] == CGPoint(x: 30, y: 160))
    }

    @Test func centersHorizontallyOnTheSelectionMiddle() {
        // Selection spans x 10…110, so the middle is 60.
        let moves = LayerArrangement.aligned(boxes, to: .horizontalCenter)
        #expect(moves[a.id] == nil) // 10 + 50 = 60 already
        #expect(moves[b.id] == CGPoint(x: 30, y: 90))
        #expect(moves[c.id] == CGPoint(x: 20, y: 160))
    }

    @Test func alignsTopsBottomsAndMiddles() {
        // Selection spans y 20…210.
        #expect(LayerArrangement.aligned(boxes, to: .top)[c.id] == CGPoint(x: 25, y: 20))
        #expect(LayerArrangement.aligned(boxes, to: .bottom)[a.id] == CGPoint(x: 10, y: 170))
        #expect(LayerArrangement.aligned(boxes, to: .verticalCenter)[a.id] == CGPoint(x: 10, y: 95))
    }

    @Test func onlyLayersThatActuallyMoveComeBack() {
        // Two boxes already sharing a left edge: aligning left changes nothing,
        // so nothing comes back and no undo step gets spent.
        let one = LayerArrangement.Box(id: UUID(), frame: CGRect(x: 5, y: 0, width: 10, height: 10))
        let two = LayerArrangement.Box(id: UUID(), frame: CGRect(x: 5, y: 40, width: 30, height: 10))
        #expect(LayerArrangement.aligned([one, two], to: .left).isEmpty)
    }

    @Test func oneLayerHasNothingToLineUpWith() {
        #expect(LayerArrangement.aligned([a], to: .left).isEmpty)
        #expect(LayerArrangement.aligned([], to: .top).isEmpty)
        #expect(!LayerArrangement.canAlign(count: 1))
        #expect(LayerArrangement.canAlign(count: 2))
    }

    // MARK: Align inside the thing it sits in

    /// A card 200 by 100 with a small label near its top left corner: one
    /// layer inside a frame, which is the only case where a single layer has
    /// something to line up with.
    let card = CGRect(x: 100, y: 100, width: 200, height: 100)
    let label = LayerArrangement.Box(id: UUID(), frame: CGRect(x: 110, y: 110, width: 60, height: 20))

    @Test func alignsOneLayerToEveryEdgeAndMiddleOfItsContainer() {
        #expect(LayerArrangement.aligned([label], to: .left, within: card)
            == [label.id: CGPoint(x: 100, y: 110)])
        #expect(LayerArrangement.aligned([label], to: .horizontalCenter, within: card)
            == [label.id: CGPoint(x: 170, y: 110)])
        #expect(LayerArrangement.aligned([label], to: .right, within: card)
            == [label.id: CGPoint(x: 240, y: 110)])
        #expect(LayerArrangement.aligned([label], to: .top, within: card)
            == [label.id: CGPoint(x: 110, y: 100)])
        #expect(LayerArrangement.aligned([label], to: .verticalCenter, within: card)
            == [label.id: CGPoint(x: 110, y: 140)])
        #expect(LayerArrangement.aligned([label], to: .bottom, within: card)
            == [label.id: CGPoint(x: 110, y: 180)])
    }

    @Test func aLayerAlreadyInTheMiddleOfItsContainerDoesNotMove() {
        let centred = LayerArrangement.Box(id: UUID(),
                                           frame: CGRect(x: 170, y: 140, width: 60, height: 20))
        #expect(LayerArrangement.aligned([centred], to: .horizontalCenter, within: card).isEmpty)
        #expect(LayerArrangement.aligned([centred], to: .verticalCenter, within: card).isEmpty)
    }

    @Test func centringMeansTheSameHereAsItDoesWhenTheContainerIsResized() {
        // An odd difference lands on the half point rather than rounding to a
        // whole one, which is what the persistent centre rule
        // (`LayerScaling.span`) does. If these two disagreed, centring a label
        // and then dragging the card wider would nudge it a point sideways.
        let odd = CGRect(x: 0, y: 0, width: 101, height: 41)
        let box = LayerArrangement.Box(id: UUID(), frame: CGRect(x: 0, y: 0, width: 20, height: 10))
        #expect(LayerArrangement.aligned([box], to: .horizontalCenter, within: odd)[box.id]
            == CGPoint(x: 40.5, y: 0))
        #expect(LayerArrangement.aligned([box], to: .verticalCenter, within: odd)[box.id]
            == CGPoint(x: 0, y: 15.5))
    }

    @Test func oneLayerCanAlignOnlyWhenSomethingHoldsIt() {
        #expect(!LayerArrangement.canAlign(count: 1))
        #expect(LayerArrangement.canAlign(count: 1, hasContainer: true))
        // Nothing selected is still nothing to line up, container or not.
        #expect(!LayerArrangement.canAlign(count: 0, hasContainer: true))
        #expect(LayerArrangement.aligned([], to: .left, within: card).isEmpty)
    }

    @Test func aContainerWinsOverTheSelectionsOwnBox() {
        // The app lines a multi-selection up with itself and only hands over a
        // container for a single layer, but the maths has to be unambiguous:
        // given a container, every box answers to the container.
        let moves = LayerArrangement.aligned(boxes, to: .left, within: card)
        #expect(moves[a.id] == CGPoint(x: 100, y: 20))
        #expect(moves[b.id] == CGPoint(x: 100, y: 90))
        #expect(moves[c.id] == CGPoint(x: 100, y: 160))
    }

    // MARK: Space evenly

    @Test func spacesEvenlyAcrossWithEqualGaps() {
        // Three boxes 20 wide inside a 200-wide span: the outer two hold still
        // and the middle one lands so both gaps are 70.
        let ids = (0..<3).map { _ in UUID() }
        let row = [
            LayerArrangement.Box(id: ids[0], frame: CGRect(x: 0, y: 0, width: 20, height: 10)),
            LayerArrangement.Box(id: ids[1], frame: CGRect(x: 30, y: 0, width: 20, height: 10)),
            LayerArrangement.Box(id: ids[2], frame: CGRect(x: 180, y: 0, width: 20, height: 10)),
        ]
        let moves = LayerArrangement.distributed(row, along: .horizontal)
        #expect(moves[ids[0]] == nil)
        #expect(moves[ids[2]] == nil)
        #expect(moves[ids[1]] == CGPoint(x: 90, y: 0))
    }

    @Test func spacingEvenlyIgnoresTheOrderTheyWereSelectedIn() {
        let ids = (0..<3).map { _ in UUID() }
        let scrambled = [
            LayerArrangement.Box(id: ids[2], frame: CGRect(x: 180, y: 0, width: 20, height: 10)),
            LayerArrangement.Box(id: ids[0], frame: CGRect(x: 0, y: 0, width: 20, height: 10)),
            LayerArrangement.Box(id: ids[1], frame: CGRect(x: 30, y: 0, width: 20, height: 10)),
        ]
        #expect(LayerArrangement.distributed(scrambled, along: .horizontal)[ids[1]]
            == CGPoint(x: 90, y: 0))
    }

    @Test func spacesEvenlyDownWhenBoxesAreDifferentHeights() {
        let ids = (0..<4).map { _ in UUID() }
        let column = [
            LayerArrangement.Box(id: ids[0], frame: CGRect(x: 0, y: 0, width: 10, height: 10)),
            LayerArrangement.Box(id: ids[1], frame: CGRect(x: 0, y: 15, width: 10, height: 30)),
            LayerArrangement.Box(id: ids[2], frame: CGRect(x: 0, y: 60, width: 10, height: 20)),
            LayerArrangement.Box(id: ids[3], frame: CGRect(x: 0, y: 170, width: 10, height: 10)),
        ]
        let moves = LayerArrangement.distributed(column, along: .vertical)
        var frames = column.map { box -> CGRect in
            guard let origin = moves[box.id] else { return box.frame }
            return CGRect(origin: origin, size: box.frame.size)
        }
        frames.sort { $0.minY < $1.minY }
        // Ends held, and every gap the same to within the rounding to whole points.
        #expect(frames.first?.minY == 0)
        #expect(frames.last?.maxY == 180)
        let gaps = zip(frames, frames.dropFirst()).map { $1.minY - $0.maxY }
        #expect((gaps.max() ?? 0) - (gaps.min() ?? 0) <= 1)
        #expect((gaps.min() ?? 0) > 0)
    }

    @Test func spacingEvenlyLandsOnWholePoints() {
        // A span that does not divide cleanly still lands on whole numbers:
        // half-pixel positions are the thing typed geometry exists to avoid.
        let ids = (0..<3).map { _ in UUID() }
        let row = [
            LayerArrangement.Box(id: ids[0], frame: CGRect(x: 0, y: 0, width: 10, height: 10)),
            LayerArrangement.Box(id: ids[1], frame: CGRect(x: 20, y: 0, width: 10, height: 10)),
            LayerArrangement.Box(id: ids[2], frame: CGRect(x: 41, y: 0, width: 10, height: 10)),
        ]
        for origin in LayerArrangement.distributed(row, along: .horizontal).values {
            #expect(origin.x == origin.x.rounded())
            #expect(origin.y == origin.y.rounded())
        }
    }

    @Test func spacingEvenlyNeedsThreeLayers() {
        #expect(LayerArrangement.distributed(Array(boxes.prefix(2)), along: .horizontal).isEmpty)
        #expect(!LayerArrangement.canDistribute(count: 2))
        #expect(LayerArrangement.canDistribute(count: 3))
    }

    @Test func spacingEvenlyKeepsTheOtherAxisAlone() {
        let ids = (0..<3).map { _ in UUID() }
        let row = [
            LayerArrangement.Box(id: ids[0], frame: CGRect(x: 0, y: 5, width: 20, height: 10)),
            LayerArrangement.Box(id: ids[1], frame: CGRect(x: 30, y: 44, width: 20, height: 10)),
            LayerArrangement.Box(id: ids[2], frame: CGRect(x: 180, y: 7, width: 20, height: 10)),
        ]
        #expect(LayerArrangement.distributed(row, along: .horizontal)[ids[1]]?.y == 44)
    }

    // MARK: Naming

    @Test func everyCommandSaysWhatItDoesInWords() {
        for alignment in LayerAlignment.allCases {
            #expect(!alignment.title.isEmpty)
            #expect(!alignment.title.contains("-"))
        }
        for axis in LayerDistribution.allCases {
            #expect(!axis.title.isEmpty)
        }
        #expect(LayerAlignment.left.title == "Align Left")
        #expect(LayerDistribution.horizontal.title == "Space Evenly Across")
    }
}
