import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The small pill the canvas puts under whatever is being dragged: what it
/// says, and where it sits so it never lands on the thing it is describing.
@Suite("The reading a drag carries with it")
struct DragReadoutTests {

    // MARK: What it says

    @Test func aMoveSaysWhereTheThingIsGoing() {
        #expect(DragReadout.text(.position(CGPoint(x: 240, y: 120))) == "240, 120")
    }

    @Test func aResizeSaysHowBigItIsBecoming() {
        #expect(DragReadout.text(.size(CGSize(width: 580, height: 448))) == "580 × 448")
    }

    /// Whole numbers. A pointer lands on 240.4 constantly and a pill that
    /// counted decimals would be unreadable at the speed a drag moves.
    @Test func everyNumberIsWhole() {
        #expect(DragReadout.text(.position(CGPoint(x: 240.4, y: 119.6))) == "240, 120")
        #expect(DragReadout.text(.size(CGSize(width: 579.5, height: 447.49))) == "580 × 447")
    }

    /// A layer can be dragged off the top or the left of the canvas, and the
    /// number that says so is negative. It is not clamped: the pill tells the
    /// truth about where the thing actually is.
    @Test func aThingDraggedOffTheTopLeftReadsNegative() {
        #expect(DragReadout.text(.position(CGPoint(x: -18, y: -4))) == "-18, -4")
    }

    /// Minus zero exists in floating point and reads as "-0", which looks like
    /// a bug on screen. It is a plain zero.
    @Test func thereIsNoMinusZero() {
        #expect(DragReadout.text(.position(CGPoint(x: -0.2, y: 0))) == "0, 0")
    }

    // MARK: What it says for a drag

    /// The rule: the pill carries the reading the drag is CHANGING. A move
    /// changes where a thing is, everything else changes how big it is.
    @Test func eachKindOfDragAsksForTheReadingItIsChanging() {
        let box = CGRect(x: 40, y: 60, width: 120, height: 80)
        #expect(DragReadout.subject(.move, box: box) == .position(CGPoint(x: 40, y: 60)))
        #expect(DragReadout.subject(.resize, box: box) == .size(CGSize(width: 120, height: 80)))
        #expect(DragReadout.subject(.sweep, box: box) == .size(CGSize(width: 120, height: 80)))
        #expect(DragReadout.subject(.reshape, box: box) == .size(CGSize(width: 120, height: 80)))
    }

    // MARK: Where it sits

    /// Centred under the box, clear of it by the gap. Under rather than over
    /// because the hand and the pointer are usually above whatever is being
    /// pulled downward, and because a name chip already lives above a frame.
    @Test func itSitsCentredUnderTheBox() {
        let box = CGRect(x: 100, y: 100, width: 200, height: 100)
        let plate = DragReadout.plate(for: box, size: CGSize(width: 60, height: 20),
                                      in: CGRect(x: 0, y: 0, width: 800, height: 600), gap: 10)
        #expect(plate.midX == box.midX)
        #expect(plate.minY == box.maxY + 10)
    }

    /// It never overlaps the box it is describing, which is the whole reason
    /// it is outside rather than in a corner of it.
    @Test func itNeverLandsOnTheThingItDescribes() {
        let view = CGRect(x: 0, y: 0, width: 800, height: 600)
        let plate = DragReadout.plate(for: CGRect(x: 100, y: 100, width: 200, height: 100),
                                      size: CGSize(width: 60, height: 20), in: view, gap: 10)
        #expect(!plate.intersects(CGRect(x: 100, y: 100, width: 200, height: 100)))
    }

    /// Dragged to the bottom of the window there is no room underneath, so the
    /// pill goes above instead of being drawn off the edge or on top of the
    /// layer.
    @Test func withNoRoomUnderneathItGoesAbove() {
        let view = CGRect(x: 0, y: 0, width: 800, height: 600)
        let box = CGRect(x: 100, y: 500, width: 200, height: 96)
        let plate = DragReadout.plate(for: box, size: CGSize(width: 60, height: 20),
                                      in: view, gap: 10)
        #expect(plate.maxY == box.minY - 10)
        #expect(!plate.intersects(box))
        #expect(view.contains(plate))
    }

    /// A box pulled against the left or right edge keeps its pill on screen:
    /// it slides along rather than hanging off, so the numbers can always be
    /// read.
    @Test func itStaysInsideTheWindowSideways() {
        let view = CGRect(x: 0, y: 0, width: 800, height: 600)
        let left = DragReadout.plate(for: CGRect(x: -80, y: 100, width: 100, height: 40),
                                     size: CGSize(width: 70, height: 20), in: view, gap: 10)
        #expect(left.minX >= view.minX)
        let right = DragReadout.plate(for: CGRect(x: 760, y: 100, width: 100, height: 40),
                                      size: CGSize(width: 70, height: 20), in: view, gap: 10)
        #expect(right.maxX <= view.maxX)
    }

    /// A box taller than the window has no outside at all. The pill still has
    /// to be readable, so it takes the bottom of the window — the only case
    /// where it sits over what it describes, and the alternative is no reading.
    @Test func aBoxBiggerThanTheWindowStillGetsAReadablePill() {
        let view = CGRect(x: 0, y: 0, width: 800, height: 600)
        let box = CGRect(x: -100, y: -100, width: 1000, height: 800)
        let plate = DragReadout.plate(for: box, size: CGSize(width: 60, height: 20),
                                      in: view, gap: 10)
        #expect(view.contains(plate))
        #expect(plate.midX == box.midX)
    }

    /// A sweep that has barely started is a box a few points across, and its
    /// pill still reads: it is centred on that box wherever the box is.
    @Test func aTinyBoxKeepsItsPillCentredOnIt() {
        let view = CGRect(x: 0, y: 0, width: 800, height: 600)
        let box = CGRect(x: 400, y: 300, width: 3, height: 2)
        let plate = DragReadout.plate(for: box, size: CGSize(width: 46, height: 20),
                                      in: view, gap: 10)
        #expect(plate.midX == box.midX)
        #expect(plate.minY == box.maxY + 10)
    }
}
