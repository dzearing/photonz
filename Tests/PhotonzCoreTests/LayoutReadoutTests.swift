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

    // MARK: - A copy that has been given a size of its own

    /// A copy of a component: a bar that runs as a row, shares its leftover
    /// room between its pieces, and is as wide as whatever is inside it. The
    /// original has nothing left over, so there is nothing to share.
    private func spreadingBar() -> (doc: PhotonzDocument, main: UUID, copy: UUID) {
        var doc = PhotonzDocument(
            canvasSize: CGSize(width: 1600, height: 900),
            layers: [rectangle("Back", CGRect(x: 0, y: 0, width: 40, height: 16)),
                     rectangle("Title", CGRect(x: 52, y: 0, width: 60, height: 16))])
        let group = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Nav Bar")!
        doc.setGroupLayout(id: group.id, kind: .stack)
        doc.updateGroupLayout(id: group.id) {
            $0.direction = .row
            $0.gap = 12
            $0.spreadsGap = true
            $0.padding = GroupPadding(top: 0, right: 14, bottom: 0, left: 14)
        }
        let componentID = doc.makeComponent(id: group.id)!
        let copy = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 800, y: 400))!
        return (doc, group.id, copy)
    }

    private func rectangle(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle,
                                                     start: .zero,
                                                     end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    /// Widens a copy, then puts every copy back in step the way any edit does.
    private func widen(_ doc: inout PhotonzDocument, _ copy: UUID, to width: CGFloat) {
        let box = doc.layer(id: copy)!.frame.standardized
        doc.updateLayer(id: copy) {
            $0 = $0.resized(to: CGRect(x: box.minX, y: box.minY, width: width, height: box.height))
        }
        doc.syncComponentInstances()
    }

    /// The half of the old paragraph that was actually wrong.
    ///
    /// "Everything in this copy stays where the original put it" was written
    /// when a copy could not be resized, and it survived the day one could
    /// (2026-09-04). The paragraph became these rows on 2026-09-06, which
    /// answered it: a row reads off the box the COPY is wearing. This holds
    /// that where the words are decided, so nothing can quietly start
    /// answering for the original again.
    @Test("A copy widened past its original reads its gap off its own box")
    func aWidenedCopyReadsItsOwnBox() {
        var (doc, main, copy) = spreadingBar()
        widen(&doc, copy, to: 600)
        let original = doc.layer(id: main)!.workingLayout.followedReadout(clipsContents: false)
        let widened = doc.layer(id: copy)!.workingLayout.followedReadout(clipsContents: false)
        // The original is as wide as its two pieces, so there is nothing to
        // share and the number is the truth.
        #expect(original.contains(LayoutReadout(title: "Gap", value: "12")))
        // The copy has 600 to fill and two pieces to fill it with.
        #expect(widened.contains(LayoutReadout(title: "Gap", value: "Spread")))
    }

    @Test("A copy nobody has resized still reads exactly what its original reads")
    func anUntouchedCopyReadsTheOriginal() {
        let (doc, main, copy) = spreadingBar()
        #expect(doc.layer(id: copy)!.workingLayout.followedReadout(clipsContents: false)
                == doc.layer(id: main)!.workingLayout.followedReadout(clipsContents: false))
    }

    /// Only the rows that depend on the box move. The room at the edges is the
    /// original's answer and stays the original's, so a widened copy does not
    /// start claiming room nobody gave it.
    @Test("Widening a copy moves only the rows that are about its box")
    func widenBecomesOnlyWhatItShould() {
        var (doc, _, copy) = spreadingBar()
        let before = doc.layer(id: copy)!.workingLayout.followedReadout(clipsContents: false)
        widen(&doc, copy, to: 600)
        let after = doc.layer(id: copy)!.workingLayout.followedReadout(clipsContents: false)
        #expect(before.map(\.title) == after.map(\.title))
        #expect(after.contains(LayoutReadout(title: "Padding", value: "0/14/0/14")))
        #expect(after.contains(LayoutReadout(title: "Direction", value: "Row")))
    }
}
