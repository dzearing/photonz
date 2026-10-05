import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The mark a point wears on the canvas, which says what KIND of point it is:
/// square for a hard corner, round for a smooth bend, and a rounded square for
/// a point curved on one side only (`docs/design/vector-paths.md`, "Reshaping
/// one"). The Pen and reshaping both draw from this one answer, so a point
/// looks the same while it is being placed as when it is picked up again.
@Suite("What a point's mark says it is")
struct PathAnchorMarkTests {

    private let at = CGPoint(x: 10, y: 10)

    // MARK: Which mark

    @Test func aPointWithNoHandlesIsASquare() {
        #expect(PathAnchorMark(PathAnchor(point: at)) == .square)
    }

    @Test func aSmoothBendIsRound() {
        let bend = PathAnchor(point: at, handleIn: CGPoint(x: -5, y: 0),
                              handleOut: CGPoint(x: 5, y: 0), kind: .smooth)
        #expect(PathAnchorMark(bend) == .round)
    }

    @Test func aPointCurvedOnOneSideIsARoundedSquareWhicheverSide() {
        let leaving = PathAnchor(point: at, handleOut: CGPoint(x: 5, y: 0))
        let arriving = PathAnchor(point: at, handleIn: CGPoint(x: -5, y: 0))
        #expect(PathAnchorMark(leaving) == .roundedSquare)
        #expect(PathAnchorMark(arriving) == .roundedSquare)
    }

    @Test func aBrokenPointCurvedOnBothSidesIsStillACorner() {
        // Two handles that are not tied together: a corner by kind, so the
        // square, because dragging one lever leaves the other where it is.
        let broken = PathAnchor(point: at, handleIn: CGPoint(x: -5, y: 2),
                                handleOut: CGPoint(x: 5, y: 3), kind: .corner)
        #expect(PathAnchorMark(broken) == .square)
    }

    // MARK: The shape drawn

    @Test func everyMarkFillsTheBoxItIsDrawnIn() {
        for mark in PathAnchorMark.allCases {
            let path = mark.path(centredOn: at, radius: 4)
            let box = path.boundingBoxOfPath
            #expect(abs(box.minX - 6) < 0.001, "\(mark)")
            #expect(abs(box.maxX - 14) < 0.001, "\(mark)")
            #expect(abs(box.minY - 6) < 0.001, "\(mark)")
            #expect(abs(box.maxY - 14) < 0.001, "\(mark)")
            #expect(path.contains(at), "\(mark)")
        }
    }

    @Test func onlyTheSquareReachesItsCorners() {
        // Just inside the corner of the box: the square covers it, the
        // rounded square has cut it off, and the circle never got near it.
        let corner = CGPoint(x: 6.2, y: 6.2)
        #expect(PathAnchorMark.square.path(centredOn: at, radius: 4).contains(corner))
        #expect(!PathAnchorMark.roundedSquare.path(centredOn: at, radius: 4).contains(corner))
        #expect(!PathAnchorMark.round.path(centredOn: at, radius: 4).contains(corner))
    }

    @Test func theRoundedSquareSitsBetweenTheOtherTwo() {
        // Half way along the diagonal from the corner in: inside the rounded
        // square, still outside the circle. That is what makes it read as
        // neither.
        let between = CGPoint(x: 7.0, y: 7.0)
        #expect(PathAnchorMark.roundedSquare.path(centredOn: at, radius: 4).contains(between))
        #expect(!PathAnchorMark.round.path(centredOn: at, radius: 4).contains(between))
    }

    @Test func aWalkNamesEachMarkByItsOwnWord() {
        #expect(PathAnchorMark(rawValue: "square") == .square)
        #expect(PathAnchorMark(rawValue: "round") == .round)
        #expect(PathAnchorMark(rawValue: "roundedSquare") == .roundedSquare)
    }
}

/// The points the Pen marks while you draw: every one placed, and while the
/// button is down the one being placed, AS IT WOULD LAND, so a press turns from
/// a square into a circle the moment it becomes a drag.
@Suite("The points the Pen marks")
struct PenMarkedAnchorsTests {

    private func marks(_ session: PenSession) -> [PathAnchorMark] {
        session.markedAnchors.map(PathAnchorMark.init)
    }

    @Test func nothingIsMarkedBeforeTheFirstPress() {
        #expect(PenSession().markedAnchors.isEmpty)
    }

    @Test func aClickADragAndAnOptionDragEachMarkTheirOwnKind() {
        var session = PenSession()
        session.press(at: CGPoint(x: 0, y: 0), constrained: false, zoom: 1)
        _ = session.release()
        session.press(at: CGPoint(x: 100, y: 0), constrained: false, zoom: 1)
        session.drag(to: CGPoint(x: 140, y: 0), constrained: false, zoom: 1)
        _ = session.release()
        session.press(at: CGPoint(x: 200, y: 100), constrained: false, breaking: true, zoom: 1)
        session.drag(to: CGPoint(x: 200, y: 140), constrained: false, zoom: 1)
        _ = session.release()
        #expect(marks(session) == [.square, .round, .roundedSquare])
    }

    @Test func thePointBeingPlacedIsMarkedWhileTheButtonIsDown() {
        var session = PenSession()
        session.press(at: CGPoint(x: 0, y: 0), constrained: false, zoom: 1)
        _ = session.release()
        session.press(at: CGPoint(x: 100, y: 0), constrained: false, zoom: 1)
        // Still a click: a square under the hand.
        #expect(marks(session) == [.square, .square])
        session.drag(to: CGPoint(x: 140, y: 0), constrained: false, zoom: 1)
        // A drag now: a bend, before the button comes up.
        #expect(marks(session) == [.square, .round])
    }

    @Test func optionOnThePointJustDraggedShowsItGoingHalfSmoothAsYouPress() {
        var session = PenSession()
        session.press(at: CGPoint(x: 0, y: 0), constrained: false, zoom: 1)
        _ = session.release()
        session.press(at: CGPoint(x: 100, y: 0), constrained: false, zoom: 1)
        session.drag(to: CGPoint(x: 140, y: 0), constrained: false, zoom: 1)
        _ = session.release()
        session.press(at: CGPoint(x: 100, y: 0), constrained: false, breaking: true, zoom: 1)
        #expect(marks(session) == [.square, .roundedSquare])
        _ = session.release()
        #expect(marks(session) == [.square, .roundedSquare])
    }

    @Test func theRunToThePointerIsNotAPoint() {
        var session = PenSession()
        session.press(at: CGPoint(x: 0, y: 0), constrained: false, zoom: 1)
        _ = session.release()
        session.pointer = CGPoint(x: 300, y: 300)
        // The preview carries a second anchor out to the pointer; nothing has
        // been put there, so nothing is marked there.
        #expect(session.previewPath?.anchors.count == 2)
        #expect(session.markedAnchors.count == 1)
    }

    @Test func aPressAimedAtClosingMarksNoNewPoint() {
        var session = PenSession()
        for p in [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)] {
            session.press(at: p, constrained: false, zoom: 1)
            _ = session.release()
        }
        #expect(session.anchors.count == 3)
        session.press(at: CGPoint(x: 0, y: 0), constrained: false, zoom: 1)
        #expect(session.markedAnchors.count == 3)
    }
}
