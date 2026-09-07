import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Every gap in a stack is the gap the layout was given, even where a piece
/// changes size on its way into the flow.
///
/// A stack works out where everything goes from the sizes its pieces have
/// GOING IN, and some pieces are not that size once they get there: a label
/// stretched across a column re-wraps and comes out taller, and a stack inside
/// a stack lays itself out again in the width it has just been handed. Place
/// from the size that went in and the gap under that piece comes out short —
/// a point under a card's title, sixteen points under a nested stack, which is
/// one thing written straight through another.
@Suite("Every gap is the gap the layout was given")
struct GroupGapTests {

    // MARK: - Building blocks

    /// A stack puts its pieces in the order they SIT in, so everything here is
    /// drawn where a person would have drawn it: each piece past the one
    /// before it, along the way its stack runs.
    private func at(_ layer: Layer, _ origin: CGPoint) -> Layer {
        var out = layer
        out.frame.origin = origin
        return out
    }

    private func words(_ string: String, size: CGFloat = 10,
                       placement: LayerPlacement? = nil) -> Layer {
        let content = TextContent(string: string, fontSize: size)
        return Layer(name: "Label", content: .text(content),
                     frame: CGRect(origin: .zero, size: TextMeasurement.size(of: content)),
                     placement: placement)
    }

    private func box(_ name: String, _ size: CGSize,
                     placement: LayerPlacement? = nil) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: size)),
              frame: CGRect(origin: .zero, size: size), placement: placement)
    }

    private func group(_ name: String, _ children: [Layer], layout: GroupLayout,
                       placement: LayerPlacement? = nil) -> Layer {
        var content = GroupContent(children: children)
        content.layout = layout
        return Layer(name: name, content: .group(content),
                     frame: CGRect(origin: .zero, size: .zero), placement: placement)
    }

    /// A column of pieces drawn one under the next, 100 apart, so nothing about
    /// the order they end up in is a coin toss.
    private func column(_ pieces: [Layer], gap: CGFloat, width: CGFloat? = nil) -> Layer {
        group("Column", pieces.enumerated().map { at($1, CGPoint(x: 0, y: CGFloat($0) * 100)) },
              layout: stack(.column, gap: gap, width: width))
    }

    private func row(_ pieces: [Layer], gap: CGFloat, height: CGFloat? = nil) -> Layer {
        group("Row", pieces.enumerated().map { at($1, CGPoint(x: CGFloat($0) * 100, y: 0)) },
              layout: stack(.row, gap: gap, height: height))
    }

    private func stack(_ direction: StackDirection, gap: CGFloat,
                       width: CGFloat? = nil, height: CGFloat? = nil) -> GroupLayout {
        GroupLayout(kind: .stack, direction: direction, gap: gap,
                    width: width, height: height)
    }

    /// The space between each piece a person can see and the next one, along
    /// the way the stack runs.
    private func gaps(_ flowed: Layer, horizontal: Bool = false) -> [CGFloat] {
        let boxes = flowed.children.map(\.contentBounds)
        return zip(boxes, boxes.dropFirst()).map {
            horizontal ? $1.minX - $0.maxX : $1.minY - $0.maxY
        }
    }

    // MARK: - A piece that changes size as it is placed

    /// The one that was writing over things: a stack inside a stack, stretched
    /// across it. Placed at the column's width its own words re-wrap, so it
    /// arrives twenty points taller than it went in, and everything under it
    /// was placed for the shorter box.
    @Test("A stack inside a column keeps its gap after it grows to its new width")
    func aNestedStackKeepsTheGapUnderIt() {
        let inner = group("Inner",
                          [words("Some words that will certainly wrap when narrowed")],
                          layout: stack(.column, gap: 0),
                          placement: LayerPlacement(horizontal: .stretch))
        let flowed = GroupFlow.flowing(
            column([box("Top", CGSize(width: 40, height: 20)),
                    inner,
                    box("Bottom", CGSize(width: 40, height: 20))],
                   gap: 8, width: 120))
        #expect(gaps(flowed) == [8, 8])
        // ...and the column closed around the taller piece rather than around
        // the box it used to be.
        let last = flowed.children.map(\.contentBounds).map(\.maxY).max() ?? 0
        #expect(flowed.localBounds.height == last)
    }

    /// The same the other way round: a row whose middle piece is a stack
    /// stretched down it, which re-flows and comes out wider.
    @Test("A stack inside a row keeps its gap after it grows to its new height")
    func aNestedStackKeepsTheGapBesideIt() {
        let inner = group("Inner",
                          [box("A", CGSize(width: 20, height: 20)),
                           box("B", CGSize(width: 20, height: 20))],
                          layout: stack(.row, gap: 4),
                          placement: LayerPlacement(vertical: .stretch))
        let flowed = GroupFlow.flowing(
            row([box("Left", CGSize(width: 30, height: 60)),
                 inner,
                 box("Right", CGSize(width: 30, height: 60))],
                gap: 8, height: 60))
        #expect(gaps(flowed, horizontal: true) == [8, 8])
    }

    /// A label is the piece that grows most often, and it kept its gap before
    /// this: the guard that says so.
    @Test("A label that re-wraps as it is stretched keeps its gap under it")
    func aLabelKeepsTheGapUnderIt() {
        let flowed = GroupFlow.flowing(
            column([box("Top", CGSize(width: 40, height: 20)),
                    words("Some words that will certainly wrap when narrowed",
                          placement: LayerPlacement(horizontal: .stretch)),
                    box("Bottom", CGSize(width: 40, height: 20))],
                   gap: 8, width: 120))
        #expect(gaps(flowed) == [8, 8])
    }

    /// Nothing changed for a stack whose pieces are the size they were drawn:
    /// the plain answer is still the plain answer.
    @Test("A column of plain boxes still sits exactly the gap apart")
    func plainBoxesAreUntouched() {
        let flowed = GroupFlow.flowing(
            column([box("One", CGSize(width: 40, height: 20)),
                    box("Two", CGSize(width: 60, height: 30)),
                    box("Three", CGSize(width: 20, height: 10))],
                   gap: 12))
        #expect(gaps(flowed) == [12, 12])
    }

    // MARK: - The card

    /// The complaint: the space under a card's title read a point smaller than
    /// the space above it, on a card told to keep one gap between everything.
    @Test("The Card starter keeps the same space above and below its title")
    func theCardKeepsOneGap() {
        var history = History(document: PhotonzDocument(canvasSize: CGSize(width: 900, height: 700)))
        var cardID: UUID?
        history.perform { cardID = $0.insertStarterComponent(.card, at: CGPoint(x: 400, y: 300)) }
        guard let cardID, let card = history.current.layer(id: cardID),
              let gap = card.group?.layout?.usedGap
        else { Issue.record("no card"); return }
        let pieces = card.children.filter { $0.name != "Background" }
        let boxes = pieces.map(\.contentBounds)
        let measured = zip(boxes, boxes.dropFirst()).map { $1.minY - $0.maxY }
        #expect(measured == [gap, gap])
    }
}
