import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A piece stretched across a hugging stack follows the stack back down
/// (task `seven-more-built-in-titles-look-as-refined-as-th`).
///
/// Found on Minimal Underline: pick a font pair whose name sets wider, turn it
/// back, and the line under the name stayed as long as the wider name, past
/// the end of the words and the card. The stack measured how wide its column
/// was from every piece in it, the stretched line included, so a line that had
/// grown held the column open at its own width. The size of the group already
/// left stretched pieces out (`GroupFlow.size`); the column now does too.
@Suite("A stretched piece shrinks back with its stack")
struct StretchedPieceShrinksBackTests {

    private func box(_ name: String, _ width: CGFloat, _ height: CGFloat,
                     _ placement: LayerPlacement? = nil) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: CGSize(width: width, height: height))),
              frame: CGRect(x: 0, y: 0, width: width, height: height), placement: placement)
    }

    private func column(_ children: [Layer]) -> Layer {
        var content = GroupContent(children: children, contentPlacement: LayerPlacement(horizontal: .left))
        content.layout = GroupLayout(kind: .stack, direction: .column, gap: 10,
                                     padding: GroupPadding(top: 8, right: 8, bottom: 8, left: 8))
        return Layer(name: "Card", content: .group(content), frame: .zero)
    }

    @Test("A line stretched across a column comes back to the width of the words when they narrow")
    func lineFollowsTheWordsBackDown() {
        let rule = box("Rule", 120, 4, LayerPlacement(horizontal: .stretch))
        let wide = GroupFlow.flowing(column([box("Name", 300, 40), rule]))
        #expect(wide.children[1].frame.width == 300)
        // The words narrow, as they do when a wider face is turned back.
        var narrowed = wide
        narrowed.children[0] = narrowed.children[0].resized(to: CGRect(origin: narrowed.children[0].frame.origin,
                                                                      size: CGSize(width: 200, height: 40)))
        let settled = GroupFlow.flowing(narrowed)
        #expect(settled.children[1].frame.width == 200)
        #expect(abs(settled.localBounds.width - 216) < 0.5, "\(settled.localBounds)")
    }

    @Test("A column of nothing but stretched pieces keeps the width it had")
    func allStretchedKeepsItsWidth() {
        let one = box("One", 150, 4, LayerPlacement(horizontal: .stretch))
        let two = box("Two", 90, 4, LayerPlacement(horizontal: .stretch))
        let settled = GroupFlow.flowing(column([one, two]))
        #expect(settled.children.map(\.frame.width) == [150, 150])
    }
}
