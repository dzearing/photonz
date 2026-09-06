import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What the Layout section reads back when it cannot be typed.
///
/// A copy of a component is SHOWN how its original arranges its contents and
/// refused the typing of it. Until now that was a paragraph — "Everything in
/// this copy stays where the original put it. It keeps 10 top, 16 right, 10
/// bottom, 16 left clear inside its edges. It is 36 tall." — which took three
/// lines to say what three rows say in one word each, and said the size a
/// third time after Position & Size had already said it twice.
///
/// So the facts become titled values, in the same order and under the same
/// words the rows of an ordinary group carry, and anything with a home
/// elsewhere on the panel is not repeated here at all.
@Suite("A layout that cannot be typed reads back as rows, not a paragraph")
struct LayoutReadoutTests {

    // MARK: - Only what has no other home

    @Test("A group that arranges nothing and keeps no room reads back nothing")
    func freeAndBare() {
        #expect(GroupLayout.free().followedReadout(clipsContents: false).isEmpty)
    }

    @Test("The size is left to Position & Size, which is two rows above it")
    func sizeIsNotRepeated() {
        let layout = GroupLayout.free(width: 320, height: 36)
        #expect(layout.followedReadout(clipsContents: false).isEmpty)
    }

    @Test("Room inside the edges reads as one number when every side agrees")
    func evenRoom() {
        let layout = GroupLayout.free(padding: GroupPadding(16))
        #expect(layout.followedReadout(clipsContents: false)
                == [LayoutReadout(title: "Padding", value: "16")])
    }

    @Test("Room that differs reads as the four numbers, clockwise from the top")
    func unevenRoom() {
        let room = GroupPadding(top: 10, right: 16, bottom: 10, left: 16)
        let layout = GroupLayout.free(padding: room)
        #expect(layout.followedReadout(clipsContents: false)
                == [LayoutReadout(title: "Padding", value: "10/16/10/16")])
    }

    // MARK: - A stack

    @Test("A stack reads back which way it runs and how far apart")
    func stack() {
        let layout = GroupLayout(kind: .stack, direction: .row, gap: 12)
        #expect(layout.followedReadout(clipsContents: false)
                == [LayoutReadout(title: "Direction", value: "Row"),
                    LayoutReadout(title: "Gap", value: "12")])
    }

    @Test("A stack sharing its leftover room says so where the number would be")
    func spreadingStack() {
        let layout = GroupLayout(kind: .stack, direction: .row, gap: 12,
                                 spreadsGap: true, width: 640)
        let readout = layout.followedReadout(clipsContents: false)
        #expect(readout.contains(LayoutReadout(title: "Gap", value: "Spread")))
    }

    @Test("A stack with no room to spare reads its gap, whatever the switch says")
    func spreadingWithNothingToSpare() {
        let layout = GroupLayout(kind: .stack, direction: .row, gap: 12, spreadsGap: true)
        let readout = layout.followedReadout(clipsContents: false)
        #expect(readout.contains(LayoutReadout(title: "Gap", value: "12")))
    }

    // MARK: - A grid

    @Test("A grid reads back its columns and one gap while both gaps agree")
    func gridWithOneGap() {
        let layout = GroupLayout(kind: .grid, columns: 4, gap: 8, rowGap: 8)
        #expect(layout.followedReadout(clipsContents: false)
                == [LayoutReadout(title: "Columns", value: "4"),
                    LayoutReadout(title: "Gap", value: "8")])
    }

    @Test("A grid whose two gaps differ reads both, named")
    func gridWithTwoGaps() {
        let layout = GroupLayout(kind: .grid, columns: 4, gap: 8, rowGap: 20)
        #expect(layout.followedReadout(clipsContents: false)
                == [LayoutReadout(title: "Columns", value: "4"),
                    LayoutReadout(title: "Column gap", value: "8"),
                    LayoutReadout(title: "Row gap", value: "20")])
    }

    // MARK: - The rare ones

    @Test("A limit that is holding a group open reads back under its own axis")
    func limits() {
        let layout = GroupLayout(kind: nil, minWidth: 96, maxHeight: 200)
        #expect(layout.followedReadout(clipsContents: false)
                == [LayoutReadout(title: "Smallest width", value: "96"),
                    LayoutReadout(title: "Largest height", value: "200")])
    }

    @Test("Cutting off what does not fit reads back, and staying open does not")
    func clipping() {
        let layout = GroupLayout.free(width: 320)
        #expect(layout.followedReadout(clipsContents: true)
                == [LayoutReadout(title: "Clip contents", value: "On")])
        #expect(layout.followedReadout(clipsContents: false).isEmpty)
    }

    // MARK: - Order

    @Test("The rows come in the order an ordinary group's own rows do")
    func order() {
        let layout = GroupLayout(kind: .stack, direction: .row, gap: 12,
                                 padding: GroupPadding(16), width: 640, minWidth: 96)
        #expect(layout.followedReadout(clipsContents: true).map(\.title)
                == ["Direction", "Smallest width", "Clip contents", "Gap", "Padding"])
    }

    @Test("Numbers are whole, the way every field in the section shows them")
    func roundsLikeTheFields() {
        let layout = GroupLayout(kind: .stack, gap: 11.6, padding: GroupPadding(15.4))
        #expect(layout.followedReadout(clipsContents: false)
                == [LayoutReadout(title: "Direction", value: "Column"),
                    LayoutReadout(title: "Gap", value: "12"),
                    LayoutReadout(title: "Padding", value: "15")])
    }
}
