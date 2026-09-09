import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A group says when its contents run past its own edge.
///
/// The complaint this answers, from the row-wrapping audit: give a row a width
/// too small for what is in it and the pieces simply hang out over the edge,
/// with nothing anywhere saying so. If the group also clips, they vanish
/// altogether. Either way the fix lives in the Layout section, and until now
/// nothing in that section admitted there was anything to fix.
///
/// The rules that keep it small and honest:
///
/// - **Measured, never guessed.** The group is flowed exactly the way the
///   canvas flows it and the pieces are held against the box that came out, so
///   the line and the picture can never disagree.
/// - **Only a group that ARRANGES.** On a Free group everything is where you
///   put it, so a piece hanging off a corner is a drawing, not a fault.
/// - **The fix is a number, not a field name.** "Make it 384 wide" is true
///   whether the box is held by a Width, by a Largest, or by both.
/// - **Wrapping is offered only when wrapping actually fixes it**, on both
///   axes: a row that wraps inside a fixed height pushes lines out of the
///   bottom instead.
@Suite("A group says when its contents run past its edge")
struct GroupOverflowTests {

    // MARK: - Building blocks

    private func box(_ name: String, _ frame: CGRect,
                     placement: LayerPlacement? = nil) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)),
              frame: frame, placement: placement)
    }

    private func group(_ children: [Layer], layout: GroupLayout? = nil,
                       frame: CGRect = .zero, isFrame: Bool = false) -> Layer {
        var content = GroupContent(children: children)
        content.layout = layout
        content.isFrame = isFrame
        return Layer(name: "Group", content: .group(content), frame: frame)
    }

    /// Three chips of 100, laid end to end. A row of them wants 320 with a gap
    /// of 10, so any width under that runs out.
    private func chips(_ widths: [CGFloat] = [100, 100, 100],
                       height: CGFloat = 40) -> [Layer] {
        var x: CGFloat = 0
        return widths.enumerated().map { index, width in
            defer { x += width + 500 }
            return box("Chip \(index)", CGRect(x: x, y: 0, width: width, height: height))
        }
    }

    private func row(width: CGFloat? = nil, height: CGFloat? = nil,
                     maxWidth: CGFloat? = nil, gap: CGFloat = 10,
                     rowGap: CGFloat = 10, wraps: Bool = false) -> GroupLayout {
        var layout = GroupLayout(kind: .stack, direction: .row, gap: gap,
                                 rowGap: rowGap, width: width, height: height)
        layout.maxWidth = maxWidth
        layout.wraps = wraps
        return layout
    }

    // MARK: - It only speaks when there is something to say

    @Test("A row wide enough for its pieces says nothing")
    func aRowThatFitsSaysNothing() {
        #expect(group(chips(), layout: row(width: 320)).contentsOverflow == nil)
    }

    @Test("A row the size of its contents says nothing, because it cannot run out")
    func aHuggingRowSaysNothing() {
        #expect(group(chips(), layout: row()).contentsOverflow == nil)
    }

    @Test("An empty group says nothing")
    func anEmptyGroupSaysNothing() {
        #expect(group([], layout: row(width: 40)).contentsOverflow == nil)
    }

    @Test("Something that is not a group says nothing")
    func aLeafSaysNothing() {
        #expect(box("A", CGRect(x: 0, y: 0, width: 10, height: 10)).contentsOverflow == nil)
    }

    // MARK: - The cuts, argued in the suite comment

    @Test("A Free group is left alone, because a piece hanging off a corner is a drawing")
    func aFreeGroupIsLeftAlone() {
        let overhanging = group([box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
                                 box("Badge", CGRect(x: 280, y: 0, width: 40, height: 20))],
                                layout: .free(width: 200, height: 40))
        #expect(overhanging.contentsOverflow == nil)
    }

    @Test("A screen is left alone, because its size is a box somebody drew")
    func aScreenIsLeftAlone() {
        let screen = group(chips(), layout: row(),
                           frame: CGRect(x: 0, y: 0, width: 200, height: 40), isFrame: true)
        #expect(screen.contentsOverflow == nil)
    }

    // MARK: - What it says when the pieces run out the side

    @Test("A row too narrow for its pieces says so, and names the width that would hold them")
    func aNarrowRowNamesTheWidth() {
        let overflowing = group(chips(), layout: row(width: 200))
        let said = try! #require(overflowing.contentsOverflow)
        #expect(said.across > 0)
        #expect(said.down == 0)
        #expect(said.width == 320)
        #expect(said.height == nil)
    }

    @Test("The number it names is the number that actually makes it fit")
    func theNumberItNamesActuallyFits() {
        let overflowing = group(chips(), layout: row(width: 200))
        let fit = try! #require(overflowing.contentsOverflow?.width)
        #expect(group(chips(), layout: row(width: fit)).contentsOverflow == nil)
    }

    @Test("A largest width holding the box in is what the number moves")
    func aLargestWidthIsRaised() {
        let held = group(chips(), layout: row(maxWidth: 200))
        let said = try! #require(held.contentsOverflow)
        #expect(said.width == 320)
        var wide = row(maxWidth: said.width)
        wide.wraps = false
        #expect(group(chips(), layout: wide).contentsOverflow == nil)
    }

    @Test("A short row says the pieces run past the bottom, and names the height")
    func aShortRowNamesTheHeight() {
        let short = group(chips(), layout: row(width: 320, height: 20))
        let said = try! #require(short.contentsOverflow)
        #expect(said.across == 0)
        #expect(said.down > 0)
        #expect(said.width == nil)
        #expect(said.height == 40)
    }

    @Test("A box too small both ways names both numbers")
    func bothSidesAreNamed() {
        let small = group(chips(), layout: row(width: 200, height: 20))
        let said = try! #require(small.contentsOverflow)
        #expect(said.width == 320)
        #expect(said.height == 40)
    }

    // MARK: - Wrapping, offered only when it works

    @Test("A row that could wrap is told so, when wrapping makes everything fit")
    func wrappingIsOfferedWhenItFits() {
        let narrow = group(chips(), layout: row(width: 200))
        let said = try! #require(narrow.contentsOverflow)
        #expect(said.wrapWouldFit)
        #expect(said.sentence.contains("Wrap"))
    }

    @Test("A row that already wraps and still does not fit is not told to wrap again")
    func wrappingIsNotOfferedTwice() {
        // One chip wider than the whole row: no amount of wrapping helps.
        let stuck = group([box("Wide", CGRect(x: 0, y: 0, width: 260, height: 40))],
                          layout: row(width: 200, wraps: true))
        let said = try! #require(stuck.contentsOverflow)
        #expect(!said.wrapWouldFit)
        #expect(!said.sentence.contains("Wrap"))
    }

    @Test("Wrapping is not offered when the wrapped lines would run out of the bottom instead")
    func wrappingIsNotOfferedWhenItOnlyMovesTheProblem() {
        let boxed = group(chips(), layout: row(width: 200, height: 40))
        let said = try! #require(boxed.contentsOverflow)
        #expect(!said.wrapWouldFit)
        #expect(!said.sentence.contains("Wrap"))
    }

    @Test("A row stops saying it the moment the wrapping makes everything fit")
    func wrappingSilencesIt() {
        #expect(group(chips(), layout: row(width: 200)).contentsOverflow != nil)
        #expect(group(chips(), layout: row(width: 200, wraps: true)).contentsOverflow == nil)
    }

    // MARK: - A column, and a grid

    @Test("A column too short for its pieces says so down the page")
    func aShortColumnSaysSo() {
        var layout = GroupLayout(kind: .stack, direction: .column, gap: 10, height: 60)
        layout.wraps = false
        let column = group(chips(), layout: layout)
        let said = try! #require(column.contentsOverflow)
        #expect(said.down > 0)
        #expect(said.height == 140)
        // Only a row wraps, so a column is never told to.
        #expect(!said.wrapWouldFit)
    }

    @Test("A grid too short for its rows says so as well")
    func aShortGridSaysSo() {
        let grid = GroupLayout(kind: .grid, columns: 2, gap: 10, rowGap: 10, height: 40)
        let short = group(chips([100, 100, 100, 100]), layout: grid)
        let said = try! #require(short.contentsOverflow)
        #expect(said.down > 0)
    }

    // MARK: - The case it matters most in

    @Test("A group that cuts off what does not fit says it too, and says the same thing")
    func aClippingGroupSaysItToo() {
        var content = GroupContent(children: chips(), clipsContents: true)
        content.layout = row(width: 200)
        let clipping = Layer(name: "Card", content: .group(content), frame: .zero)
        // The pieces are gone from the canvas entirely here, so this line is
        // the only thing in the app that knows they exist.
        #expect(clipping.contentsOverflow?.sentence
                == group(chips(), layout: row(width: 200)).contentsOverflow?.sentence)
        #expect(clipping.contentsOverflow != nil)
    }

    @Test("It speaks for its OWN edge, not for a broken group inside it")
    func itSpeaksForItsOwnEdge() {
        // A card wide enough for the row it holds, holding a row too narrow for
        // its chips. The card is fine; the row is the one with a problem, and
        // it is the row's own line that says so.
        let inner = group(chips(), layout: row(width: 200))
        var card = GroupContent(children: [inner])
        card.layout = GroupLayout(kind: .stack, direction: .column, gap: 0, width: 400)
        let outer = Layer(name: "Card", content: .group(card), frame: .zero)
        #expect(outer.contentsOverflow == nil)
        #expect(inner.contentsOverflow != nil)
    }

    // MARK: - The words

    @Test("It names the right edge and the number, in one line")
    func theWordsForOneSide() {
        let said = try! #require(group(chips(), layout: row(width: 200)).contentsOverflow)
        #expect(said.sentence
                == "The pieces run past the right edge. Wrap them onto more lines, or make it 320 wide.")
    }

    @Test("With no wrapping to offer it names the number on its own")
    func theWordsWithNoWrap() {
        let said = try! #require(group(chips(), layout: row(width: 320, height: 20)).contentsOverflow)
        #expect(said.sentence == "The pieces run past the bottom edge. Make it 40 tall.")
    }

    @Test("Past both edges it says both, and gives one size")
    func theWordsForBothSides() {
        let said = try! #require(group(chips(), layout: row(width: 200, height: 20)).contentsOverflow)
        #expect(said.sentence
                == "The pieces run past the right and bottom edges. Make it 320 × 40.")
    }

    @Test("Nothing it can name is nothing it says")
    func noFixIsNoLine() {
        // A row held by a floor only ever gets bigger, so nothing is ever
        // hanging out because of one and there is no number to move.
        var floored = GroupLayout(kind: .stack, direction: .row, gap: 10)
        floored.minWidth = 100
        #expect(group(chips(), layout: floored).contentsOverflow == nil)
    }
}
