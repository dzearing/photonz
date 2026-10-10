import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Where a Pen point lands inside an icon frame (`IconSnap`): on a whole unit,
/// pulled onto a keyline or onto another shape's point when it is near one, so
/// the file that leaves the app says every place in whole numbers.
@Suite("Pen points in an icon frame land on whole units")
struct IconSnapTests {

    /// A 24 unit icon frame sitting at 100, 100 on the canvas. Its keylines
    /// across are at 100 (edge), 102 (live area), 103 (square), 112 (centre),
    /// 121, 122 and 124.
    private static let frame = CGRect(x: 100, y: 100, width: 24, height: 24)

    // MARK: Whole units

    @Test func aPointLandsOnTheNearestWholeUnit() {
        let snap = IconSnap(frame: Self.frame)
        // Close in, the hand is precise and rounding is all that happens.
        #expect(snap.point(nearest: CGPoint(x: 103.3, y: 105.6), zoom: 32)
                == CGPoint(x: 103, y: 106))
        #expect(snap.point(nearest: CGPoint(x: 117.49, y: 109.51), zoom: 32)
                == CGPoint(x: 117, y: 110))
    }

    @Test func wholeUnitsCountFromTheFramesOwnCorner() {
        // A frame left on half a point still has its units counted from its
        // corner, because the file it exports starts there.
        let snap = IconSnap(frame: CGRect(x: 100.5, y: 99.25, width: 24, height: 24))
        #expect(snap.point(nearest: CGPoint(x: 105.9, y: 104.1), zoom: 32)
                == CGPoint(x: 105.5, y: 104.25))
    }

    @Test func aPointPastTheFramesEdgeStillLandsOnAWholeUnit() {
        // A path started in the icon keeps its units when a point strays out.
        let snap = IconSnap(frame: Self.frame)
        #expect(snap.point(nearest: CGPoint(x: 126.4, y: 97.7), zoom: 32)
                == CGPoint(x: 126, y: 98))
    }

    @Test func aPointThatIsNotANumberIsLeftAlone() {
        let snap = IconSnap(frame: Self.frame)
        let odd = CGPoint(x: CGFloat.nan, y: 3)
        #expect(snap.point(nearest: odd, zoom: 4).x.isNaN)
    }

    // MARK: Keylines

    @Test func aKeylinePullsFromFurtherThanHalfAUnit() {
        let snap = IconSnap(frame: Self.frame)
        // Zoomed out, the centre line catches a point most of a unit away...
        #expect(snap.point(nearest: CGPoint(x: 112.8, y: 106.2), zoom: 4).x == 112)
        // ...and close in, where a unit is a big target, it does not.
        #expect(snap.point(nearest: CGPoint(x: 112.8, y: 106.2), zoom: 32).x == 113)
    }

    @Test func aKeylinePullsEachAxisOnItsOwn() {
        let snap = IconSnap(frame: Self.frame)
        // The square's right edge (121) across, the centre (112) down, each
        // from further than rounding alone would carry it.
        #expect(snap.point(nearest: CGPoint(x: 120.3, y: 111.2), zoom: 4)
                == CGPoint(x: 121, y: 112))
    }

    @Test func theNearestKeylineWins() {
        let snap = IconSnap(frame: Self.frame)
        // 102 (live area) and 103 (square) are one unit apart.
        #expect(snap.point(nearest: CGPoint(x: 102.6, y: 110), zoom: 4).x == 103)
        #expect(snap.point(nearest: CGPoint(x: 102.4, y: 110), zoom: 4).x == 102)
    }

    @Test func keylinesSwitchedOffPullNothing() {
        // Only lines the canvas is drawing pull: with the guides off, the
        // point just rounds.
        let snap = IconSnap(frame: Self.frame, keylines: false)
        #expect(snap.point(nearest: CGPoint(x: 112.8, y: 106.2), zoom: 4)
                == CGPoint(x: 113, y: 106))
    }

    @Test func aKeylineOffTheUnitsIsNotATarget() {
        // A 25 unit frame's centre is at 12.5: landing there would put a point
        // off the units, so it is not offered.
        let snap = IconSnap(frame: CGRect(x: 100, y: 100, width: 25, height: 25))
        #expect(snap.xLines.allSatisfy { ($0 - 100).rounded() == $0 - 100 })
        #expect(snap.point(nearest: CGPoint(x: 112.45, y: 110), zoom: 4).x == 112)
    }

    @Test func aFrameThatIsNotAnIconHasNoKeylines() {
        let snap = IconSnap(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        #expect(snap.xLines.isEmpty)
        #expect(snap.yLines.isEmpty)
    }

    // MARK: Other shapes' points

    @Test func anotherShapesPointPullsBothAxes() {
        let snap = IconSnap(frame: Self.frame, keylines: false,
                            anchors: [CGPoint(x: 105, y: 107)])
        #expect(snap.point(nearest: CGPoint(x: 105.7, y: 107.6), zoom: 4)
                == CGPoint(x: 105, y: 107))
        // Without it the same point rounds the other way on both axes.
        #expect(IconSnap(frame: Self.frame, keylines: false)
            .point(nearest: CGPoint(x: 105.7, y: 107.6), zoom: 4) == CGPoint(x: 106, y: 108))
    }

    @Test func aPointBeatsAKeyline() {
        // The shape you are joining onto is what you are aiming at.
        let snap = IconSnap(frame: Self.frame, anchors: [CGPoint(x: 113, y: 107)])
        #expect(snap.point(nearest: CGPoint(x: 112.4, y: 107.3), zoom: 4)
                == CGPoint(x: 113, y: 107))
    }

    @Test func aPointOffTheUnitsIsNotATarget() {
        let snap = IconSnap(frame: Self.frame, keylines: false,
                            anchors: [CGPoint(x: 105.5, y: 107)])
        #expect(snap.anchors.isEmpty)
    }

    // MARK: Handles

    @Test func aHandleEndsOnAWholeUnit() {
        let snap = IconSnap(frame: Self.frame)
        #expect(snap.offset(CGPoint(x: 3.4, y: -2.6)) == CGPoint(x: 3, y: -3))
    }

    @Test func aFortyFiveDegreeHandleStaysAtFortyFive() {
        let snap = IconSnap(frame: Self.frame)
        let diagonal = PenSession.snappedToFortyFive(CGPoint(x: 3.6, y: -3.4))
        let landed = snap.offset(diagonal)
        #expect(abs(landed.x) == abs(landed.y))
        #expect(landed == CGPoint(x: 4, y: -4) || landed == CGPoint(x: 3, y: -3))
    }

    // MARK: Which frame

    private static func iconDocument() -> (PhotonzDocument, UUID) {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1600, height: 1100))
        let icon = document.addFrame(origin: CGPoint(x: 100, y: 100),
                                     size: CGSize(width: 24, height: 24))
        _ = document.addFrame(origin: CGPoint(x: 400, y: 100),
                              size: CGSize(width: 390, height: 844))
        return (document, icon.id)
    }

    @Test func anIconFrameUnderThePointerSnaps() {
        let (document, _) = Self.iconDocument()
        let snap = document.iconSnap(at: CGPoint(x: 110, y: 110), keylines: true)
        #expect(snap?.frame == Self.frame)
    }

    @Test func aScreenOrBareCanvasDoesNot() {
        let (document, _) = Self.iconDocument()
        #expect(document.iconSnap(at: CGPoint(x: 500, y: 300), keylines: true) == nil)
        #expect(document.iconSnap(at: CGPoint(x: 50, y: 50), keylines: true) == nil)
    }

    @Test func theShapesAlreadyOnTheIconOfferTheirPoints() {
        var (document, _) = Self.iconDocument()
        let drawn = PathContent(anchors: [PathAnchor(point: CGPoint(x: 104, y: 104)),
                                          PathAnchor(point: CGPoint(x: 116, y: 104)),
                                          PathAnchor(point: CGPoint(x: 110, y: 115))],
                                isClosed: true)
        document.addLayerDrawnOnFrame(PenSession.layer(from: drawn))
        let snap = document.iconSnap(at: CGPoint(x: 110, y: 110), keylines: true)
        #expect(Set(snap?.anchors.map { "\($0.x),\($0.y)" } ?? [])
                == ["104.0,104.0", "116.0,104.0", "110.0,115.0"])
    }

    // MARK: The Pen

    private func click(_ session: inout PenSession, _ x: CGFloat, _ y: CGFloat,
                       constrained: Bool = false, free: Bool = false,
                       zoom: CGFloat = 32) -> PenSession.Outcome {
        session.press(at: CGPoint(x: x, y: y), constrained: constrained, free: free, zoom: zoom)
        return session.release()
    }

    private func iconPen() -> PenSession {
        var session = PenSession()
        session.iconSnap = IconSnap(frame: Self.frame)
        return session
    }

    @Test func aPenClickInAnIconLandsOnAWholeUnit() {
        var session = iconPen()
        _ = click(&session, 103.3, 105.6)
        #expect(session.anchors.map(\.point) == [CGPoint(x: 103, y: 106)])
    }

    @Test func thePreviewShowsWhereThePointWillLand() {
        var session = iconPen()
        _ = click(&session, 103.3, 105.6)
        session.pointer = CGPoint(x: 110.4, y: 108.8)
        session.zoom = 32
        #expect(session.previewPath?.anchors.last?.point == CGPoint(x: 110, y: 109))
        #expect(session.landing(at: CGPoint(x: 110.4, y: 108.8), constrained: false, zoom: 32)
                == .place(CGPoint(x: 110, y: 109)))
    }

    @Test func theIconBeatsTheCanvasGrid() {
        // A four point canvas grid cannot reach most units; inside an icon the
        // units are the grid.
        var session = iconPen()
        session.grid = NudgeGrid(spacing: 4)
        _ = click(&session, 105.2, 106.9)
        #expect(session.anchors.map(\.point) == [CGPoint(x: 105, y: 107)])
        #expect(session.pressGridLines.x == nil)
    }

    @Test func commandPutsThePointExactlyWhereItWasPut() {
        var session = iconPen()
        _ = click(&session, 103.3, 105.6, free: true)
        #expect(session.anchors.map(\.point) == [CGPoint(x: 103.3, y: 105.6)])
    }

    @Test func shiftKeepsALevelRunOnWholeUnits() {
        var session = iconPen()
        _ = click(&session, 104, 104)
        _ = click(&session, 113.4, 104.6, constrained: true)
        #expect(session.anchors.last?.point == CGPoint(x: 113, y: 104))
    }

    @Test func shiftKeepsADiagonalAtFortyFiveOnWholeUnits() {
        var session = iconPen()
        _ = click(&session, 104, 104)
        _ = click(&session, 110.3, 109.9, constrained: true)
        let last = session.anchors.last?.point ?? .zero
        #expect(last.x.rounded() == last.x && last.y.rounded() == last.y)
        #expect(abs(last.x - 104) == abs(last.y - 104))
    }

    @Test func aDraggedCurveHasWholeHandles() {
        var session = iconPen()
        session.press(at: CGPoint(x: 104.2, y: 104.3), constrained: false, zoom: 32)
        session.drag(to: CGPoint(x: 107.6, y: 102.2), constrained: false, zoom: 32)
        _ = session.release()
        let anchor = session.anchors.first
        #expect(anchor?.point == CGPoint(x: 104, y: 104))
        #expect(anchor?.handleOut == CGPoint(x: 4, y: -2))
        #expect(anchor?.handleIn == CGPoint(x: -4, y: 2))
    }

    @Test func clickingTheFirstPointStillCloses() {
        var session = iconPen()
        _ = click(&session, 104, 104)
        _ = click(&session, 116, 104)
        _ = click(&session, 110, 115)
        guard case .closed = click(&session, 104.2, 103.9) else {
            Issue.record("expected the path to close")
            return
        }
    }

    @Test func aTriangleDrawnInAnIconExportsInWholeUnits() {
        var (document, _) = Self.iconDocument()
        var session = PenSession()
        session.iconSnap = document.iconSnap(at: CGPoint(x: 103.3, y: 103.6), keylines: true)
        _ = click(&session, 103.3, 103.6, zoom: 0.58)
        _ = click(&session, 118.6, 104.4, zoom: 0.58)
        _ = click(&session, 111.4, 116.7, zoom: 0.58)
        guard let content = session.finish() else {
            Issue.record("expected an open path")
            return
        }
        document.addLayerDrawnOnFrame(PenSession.layer(from: content))
        let svg = SVGExport.write(document).text
        #expect(SVGWholeUnits.fractionalCoordinates(in: svg).isEmpty)
    }
}
