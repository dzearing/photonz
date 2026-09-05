import CoreGraphics
import PhotonzCore
import Testing

/// Picking a panel section up and putting it somewhere else in the column.
///
/// The rule the whole thing rests on: a section moves aside when the pointer
/// passes ITS MIDDLE, not when the dragged section first touches it. Touching
/// is where a drag starts, so swapping on touch means the column rearranges
/// before you have decided anything.
@Suite("SectionReorderDrag")
struct SectionReorderDragTests {

    /// Four sections, 100pt each, stacked from the top. Middles at 50, 150,
    /// 250 and 350.
    private let even: [SectionReorderDrag.Span] = (0..<4).map {
        .init(top: CGFloat($0) * 100, height: 100)
    }

    // MARK: Where the dragged section lands

    @Test func staysPutWhileThePointerIsStillOnItsOwnSection() {
        #expect(SectionReorderDrag.target(dragging: 1, pointerY: 150, spans: even) == 1)
        #expect(SectionReorderDrag.target(dragging: 1, pointerY: 101, spans: even) == 1)
        #expect(SectionReorderDrag.target(dragging: 1, pointerY: 199, spans: even) == 1)
    }

    @Test func doesNotSwapWhenThePointerOnlyTouchesTheSectionBelow() {
        // 201 is inside section 2, but nowhere near its middle at 250.
        #expect(SectionReorderDrag.target(dragging: 1, pointerY: 201, spans: even) == 1)
        #expect(SectionReorderDrag.target(dragging: 1, pointerY: 249, spans: even) == 1)
    }

    @Test func swapsOnceThePointerPassesTheMiddleOfTheSectionBelow() {
        #expect(SectionReorderDrag.target(dragging: 1, pointerY: 251, spans: even) == 2)
    }

    @Test func doesNotSwapWhenThePointerOnlyTouchesTheSectionAbove() {
        #expect(SectionReorderDrag.target(dragging: 2, pointerY: 199, spans: even) == 2)
        #expect(SectionReorderDrag.target(dragging: 2, pointerY: 151, spans: even) == 2)
    }

    @Test func swapsOnceThePointerPassesTheMiddleOfTheSectionAbove() {
        #expect(SectionReorderDrag.target(dragging: 2, pointerY: 149, spans: even) == 1)
    }

    @Test func passesTwoSectionsWhenThePointerPassesBothMiddles() {
        #expect(SectionReorderDrag.target(dragging: 0, pointerY: 360, spans: even) == 3)
        #expect(SectionReorderDrag.target(dragging: 3, pointerY: 40, spans: even) == 0)
    }

    @Test func comesBackWhenYouRetreat() {
        // Down past the middle of 2, then back above it again.
        #expect(SectionReorderDrag.target(dragging: 1, pointerY: 260, spans: even) == 2)
        #expect(SectionReorderDrag.target(dragging: 1, pointerY: 240, spans: even) == 1)
    }

    @Test func stopsAtTheEndsHoweverFarYouPull() {
        #expect(SectionReorderDrag.target(dragging: 1, pointerY: -5000, spans: even) == 0)
        #expect(SectionReorderDrag.target(dragging: 1, pointerY: 5000, spans: even) == 3)
    }

    @Test func readsUnevenSectionsByTheirOwnMiddles() {
        // A tall Layers section over two short ones: 300, 40, 40.
        let spans: [SectionReorderDrag.Span] = [
            .init(top: 0, height: 300), .init(top: 300, height: 40), .init(top: 340, height: 40),
        ]
        #expect(SectionReorderDrag.target(dragging: 0, pointerY: 319, spans: spans) == 0)
        #expect(SectionReorderDrag.target(dragging: 0, pointerY: 321, spans: spans) == 1)
        #expect(SectionReorderDrag.target(dragging: 0, pointerY: 361, spans: spans) == 2)
    }

    @Test func answersWithTheSameIndexWhenThereIsNothingToRead() {
        #expect(SectionReorderDrag.target(dragging: 0, pointerY: 100, spans: []) == 0)
        #expect(SectionReorderDrag.target(dragging: 7, pointerY: 100, spans: even) == 7)
        #expect(SectionReorderDrag.target(dragging: 0, pointerY: 100, spans: [.init(top: 0, height: 50)]) == 0)
    }

    // MARK: How far the sections that move aside slide

    @Test func nothingMovesWhileTheDraggedSectionIsStillInItsOwnPlace() {
        for i in 0..<4 {
            #expect(SectionReorderDrag.offset(of: i, dragging: 1, target: 1, spans: even) == 0)
        }
    }

    @Test func sectionsPassedGoingDownSlideUpByTheDraggedHeight() {
        #expect(SectionReorderDrag.offset(of: 2, dragging: 1, target: 3, spans: even) == -100)
        #expect(SectionReorderDrag.offset(of: 3, dragging: 1, target: 3, spans: even) == -100)
        #expect(SectionReorderDrag.offset(of: 0, dragging: 1, target: 3, spans: even) == 0)
    }

    @Test func sectionsPassedGoingUpSlideDownByTheDraggedHeight() {
        #expect(SectionReorderDrag.offset(of: 0, dragging: 2, target: 0, spans: even) == 100)
        #expect(SectionReorderDrag.offset(of: 1, dragging: 2, target: 0, spans: even) == 100)
        #expect(SectionReorderDrag.offset(of: 3, dragging: 2, target: 0, spans: even) == 0)
    }

    @Test func theDraggedSectionIsNeverOffsetByThisRuleItFollowsThePointer() {
        #expect(SectionReorderDrag.offset(of: 1, dragging: 1, target: 3, spans: even) == 0)
        #expect(SectionReorderDrag.offset(of: 2, dragging: 2, target: 0, spans: even) == 0)
    }

    @Test func slidesByTheDraggedSectionsOwnHeightNotAFixedStep() {
        let spans: [SectionReorderDrag.Span] = [
            .init(top: 0, height: 300), .init(top: 300, height: 40), .init(top: 340, height: 40),
        ]
        #expect(SectionReorderDrag.offset(of: 1, dragging: 0, target: 2, spans: spans) == -300)
        #expect(SectionReorderDrag.offset(of: 0, dragging: 2, target: 0, spans: spans) == 40)
    }

    // MARK: The order you are left with

    @Test func dropsTheSectionIntoTheSlotItWasShowing() {
        #expect(SectionReorderDrag.reordered(["a", "b", "c", "d"], moving: 1, to: 3) == ["a", "c", "d", "b"])
        #expect(SectionReorderDrag.reordered(["a", "b", "c", "d"], moving: 3, to: 0) == ["d", "a", "b", "c"])
        #expect(SectionReorderDrag.reordered(["a", "b", "c"], moving: 0, to: 1) == ["b", "a", "c"])
    }

    @Test func leavesTheOrderAloneWhenTheSectionCameBackToWhereItStarted() {
        #expect(SectionReorderDrag.reordered(["a", "b", "c"], moving: 1, to: 1) == ["a", "b", "c"])
    }

    @Test func leavesTheOrderAloneWhenAskedForASlotThatIsNotThere() {
        #expect(SectionReorderDrag.reordered(["a", "b", "c"], moving: 5, to: 1) == ["a", "b", "c"])
        #expect(SectionReorderDrag.reordered(["a", "b", "c"], moving: 1, to: 9) == ["a", "b", "c"])
    }
}
