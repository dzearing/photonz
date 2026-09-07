import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A label centred inside a container of its own height sits in the middle of
/// it, with the same room above the words as below them.
///
/// The room is measured on the box a person SEES. A measured text box is
/// stored a few points taller than its words so an antialiased glyph edge has
/// somewhere to round into, all of it past the bottom edge; centre the STORED
/// box and every title in the app sits about two points high, centre the words
/// against the stored box and it sits two points low. Either way it is the
/// kind of wrongness nobody can name and everybody can see.
///
/// Where the words go INSIDE that box is the renderer's half of the same
/// question (`TextDownTheBoxTests`).
@Suite("A label centred in a bar")
struct CentredLabelTests {

    /// A text box as the measurement leaves it: as wide and as tall as the
    /// words, plus the slack on the far edges.
    private func label(_ string: String, size: CGFloat) -> Layer {
        let content = TextContent(string: string, fontSize: size)
        return Layer(name: "Title", content: .text(content),
                     frame: CGRect(origin: .zero, size: TextMeasurement.size(of: content)))
    }

    /// A bar of a fixed height that lines its contents up down the middle.
    private func bar(_ children: [Layer], height: CGFloat, width: CGFloat = 320) -> Layer {
        var group = GroupContent(children: children)
        group.layout = GroupLayout(kind: .stack, direction: .row, gap: 12,
                                   padding: GroupPadding(top: 0, right: 14, bottom: 0, left: 14),
                                   width: width, height: height)
        group.contentPlacement = LayerPlacement(horizontal: .left, vertical: .center)
        return Layer(name: "Bar", content: .group(group), frame: .zero)
    }

    @Test(arguments: [(CGFloat(15), CGFloat(48)), (15, 44), (13, 32), (24, 64), (11, 28)])
    func aCentredLabelHasTheSameRoomAboveAndBelowItsWords(size: CGFloat, height: CGFloat) {
        let laid = GroupFlow.flowing(bar([label("Title", size: size)], height: height))
        let title = laid.children[0].contentBounds
        let above = title.minY
        let below = height - title.maxY
        #expect(abs(above - below) <= 1,
                "\(size) point words in a \(height) tall bar have \(above) above, \(below) below")
    }

    /// The same for a column, where the cross axis is the one across the box.
    /// Nothing about a label lined up left, right or at the top moves.
    @Test func labelsLinedUpOnAnEdgeAreUnchanged() {
        for rule in [VerticalPlacement.top, .bottom] {
            var words = label("Title", size: 15)
            words.placement = LayerPlacement(horizontal: .left, vertical: rule)
            let laid = GroupFlow.flowing(bar([words], height: 48))
            let title = laid.children[0].contentBounds
            #expect(rule == .top ? title.minY == 0 : title.maxY == 48,
                    "a \(rule) label sits at \(title)")
        }
    }
}
