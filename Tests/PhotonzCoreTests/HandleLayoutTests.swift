import CoreGraphics
import PhotonzCore
import Testing

/// Handles have to fit the thing they are round. On a two letter label the
/// eight of them cover the label completely, so there is nothing left to pick
/// it up by. These are the rules that get them out of the way.
@Suite("Handles fit the thing they are round")
struct HandleLayoutTests {
    /// The OK label that found this: a text layer hugging two letters.
    let tiny = CGRect(x: 40, y: 40, width: 19, height: 16)
    /// An ordinary layer, comfortably bigger than the handles on it.
    let roomy = CGRect(x: 100, y: 100, width: 200, height: 100)

    /// Where a handle's drawn square reaches, in document units.
    private func square(_ layout: HandleLayout, _ handle: ResizeHandle,
                        side: CGFloat = 8, zoom: CGFloat = 1) -> CGRect {
        let p = layout.point(for: handle)
        let half = side / zoom / 2
        return CGRect(x: p.x - half, y: p.y - half, width: half * 2, height: half * 2)
    }

    // MARK: A roomy layer is untouched

    @Test func aRoomyLayerKeepsAllEightHandlesWhereTheyAlwaysWere() {
        let layout = Handles.layout(in: roomy, zoom: 1)
        #expect(layout.handles == ResizeHandle.allCases)
        for handle in ResizeHandle.allCases {
            #expect(layout.point(for: handle) == Handles.point(for: handle, in: roomy), "\(handle)")
        }
    }

    @Test func aRoomyLayerStillAnswersEveryHandleToAPress() {
        for handle in ResizeHandle.allCases {
            let p = Handles.point(for: handle, in: roomy)
            #expect(Handles.hit(at: p, frame: roomy, zoom: 1) == handle, "\(handle)")
        }
    }

    // MARK: A cramped layer drops its edge handles and steps outside

    @Test func aTinyLayerOffersItsCornersOnly() {
        let layout = Handles.layout(in: tiny, zoom: 1)
        #expect(layout.handles == [.topLeft, .topRight, .bottomLeft, .bottomRight])
        #expect(layout.offers(.top) == false)
        #expect(layout.offers(.left) == false)
    }

    @Test func aTinyLayersCornersSitOutsideItsOutline() {
        let layout = Handles.layout(in: tiny, zoom: 1)
        #expect(layout.point(for: .topLeft).x < tiny.minX)
        #expect(layout.point(for: .topLeft).y < tiny.minY)
        #expect(layout.point(for: .bottomRight).x > tiny.maxX)
        #expect(layout.point(for: .bottomRight).y > tiny.maxY)
        // Far enough out that the drawn square clears the outline entirely.
        for handle in layout.handles {
            #expect(!square(layout, handle).intersects(tiny), "\(handle)")
        }
    }

    /// The whole point: the middle of a two letter label is grabbable again.
    @Test func theMiddleOfATinyLayerIsNotAHandle() {
        #expect(Handles.hit(at: CGPoint(x: tiny.midX, y: tiny.midY), frame: tiny, zoom: 1) == nil)
    }

    @Test func noPartOfATinyLayersDrawnSquaresOverlapsAnother() {
        let layout = Handles.layout(in: tiny, zoom: 1)
        for a in layout.handles {
            for b in layout.handles where a != b {
                #expect(!square(layout, a).intersects(square(layout, b)), "\(a) vs \(b)")
            }
        }
    }

    @Test func evenAOnePointLayerKeepsItsHandlesApart() {
        let speck = CGRect(x: 10, y: 10, width: 1, height: 1)
        let layout = Handles.layout(in: speck, zoom: 1)
        for a in layout.handles {
            for b in layout.handles where a != b {
                #expect(!square(layout, a).intersects(square(layout, b)), "\(a) vs \(b)")
            }
        }
        #expect(Handles.hit(at: CGPoint(x: speck.midX, y: speck.midY), frame: speck, zoom: 1) == nil)
    }

    @Test func aTinyLayersCornersStillAnswerToAPressWhereTheyDraw() {
        let layout = Handles.layout(in: tiny, zoom: 1)
        for handle in layout.handles {
            let p = layout.point(for: handle)
            #expect(Handles.hit(at: p, frame: tiny, zoom: 1) == handle, "\(handle)")
        }
    }

    @Test func aDroppedEdgeHandleIsNeverReturnedByAPress() {
        // Dead centre of the top edge, which is where `top` used to live.
        let onTheOldTopHandle = CGPoint(x: tiny.midX, y: tiny.minY)
        let hit = Handles.hit(at: onTheOldTopHandle, frame: tiny, zoom: 1)
        #expect(hit == nil || hit?.isCorner == true)
    }

    // MARK: Cramped on one axis only

    @Test func aWideThinLayerKeepsItsWidthAndStepsOutVertically() {
        let divider = CGRect(x: 0, y: 200, width: 400, height: 8)
        let layout = Handles.layout(in: divider, zoom: 1)
        // Only the corners: the edge handles crowd them on the short axis.
        #expect(layout.handles == [.topLeft, .topRight, .bottomLeft, .bottomRight])
        // Roomy across, so the corners hold their x and only move in y.
        #expect(layout.point(for: .topLeft).x == divider.minX)
        #expect(layout.point(for: .topRight).x == divider.maxX)
        #expect(layout.point(for: .topLeft).y < divider.minY)
        #expect(layout.point(for: .bottomLeft).y > divider.maxY)
        // Its middle is grabbable.
        #expect(Handles.hit(at: CGPoint(x: divider.midX, y: divider.midY),
                            frame: divider, zoom: 1) == nil)
    }

    // MARK: Where the line between cramped and roomy falls

    /// The rule the threshold encodes: an edge midpoint appears only once
    /// there is real air either side of it, not the moment it technically
    /// fits. A box a few points over the old bar wore all eight as one solid
    /// lattice laid over the object.
    @Test func edgeHandlesComeBackOnlyOnceThereIsRoomBetweenThem() {
        let justUnder = CGRect(x: 0, y: 0, width: Handles.crampedSpan - 1,
                               height: Handles.crampedSpan - 1)
        let justOver = CGRect(x: 0, y: 0, width: Handles.crampedSpan,
                              height: Handles.crampedSpan)
        #expect(Handles.layout(in: justUnder, zoom: 1).handles
            == [.topLeft, .topRight, .bottomLeft, .bottomRight])
        #expect(Handles.layout(in: justOver, zoom: 1).handles == ResizeHandle.allCases)
    }

    /// ...and at the smallest box that gets all eight, every drawn square
    /// still has a whole handle's width of air round it.
    @Test func theSmallestBoxWithAllEightStillHasAirBetweenEverySquare() {
        let smallest = CGRect(x: 0, y: 0, width: Handles.crampedSpan,
                              height: Handles.crampedSpan)
        let layout = Handles.layout(in: smallest, zoom: 1)
        #expect(layout.handles == ResizeHandle.allCases)
        for a in layout.handles {
            for b in layout.handles where a != b {
                #expect(!square(layout, a).insetBy(dx: -4, dy: -4).intersects(square(layout, b)),
                        "\(a) vs \(b)")
            }
        }
    }

    // MARK: Cramped is a SCREEN measure, so zoom decides it

    @Test func zoomingOutMakesARoomyLayerCramped() {
        // 200x100 doc units at 0.1x is 20x10 on screen: too small for handles inside.
        let layout = Handles.layout(in: roomy, zoom: 0.1)
        #expect(layout.handles == [.topLeft, .topRight, .bottomLeft, .bottomRight])
        #expect(Handles.hit(at: CGPoint(x: roomy.midX, y: roomy.midY),
                            frame: roomy, zoom: 0.1) == nil)
    }

    @Test func zoomingInMakesATinyLayerRoomy() {
        // 19x16 doc units at 4x is 76x64 on screen: plenty of room.
        let layout = Handles.layout(in: tiny, zoom: 4)
        #expect(layout.handles == ResizeHandle.allCases)
        for handle in ResizeHandle.allCases {
            #expect(layout.point(for: handle) == Handles.point(for: handle, in: tiny), "\(handle)")
        }
    }

    @Test func theOutwardStepIsAScreenDistanceSoItLooksTheSameAtEveryZoom() {
        let atOne = Handles.layout(in: tiny, zoom: 1)
        let atTwo = Handles.layout(in: CGRect(x: 40, y: 40, width: 9.5, height: 8), zoom: 2)
        let stepOne = tiny.minX - atOne.point(for: .topLeft).x
        let stepTwo = (40 - atTwo.point(for: .topLeft).x) * 2
        #expect(abs(stepOne - stepTwo) < 1e-9)
    }
}

/// A one line label is the box most UI work is made of, and it is short: 21 to
/// 30 points tall. Its two corner squares claim that whole side edge between
/// them, so the width the words wrap at — the one thing a label is resized for
/// — had no handle you could take hold of, and pulling the side of a label
/// slid it across the canvas instead.
///
/// The answer is the one every drawing tool uses: the OUTLINE is the handle.
/// The whole run of an edge answers to a press, not just a square in the
/// middle of it, so a short box has a side to pull even where there is no room
/// to draw a square on it.
@Suite("The edge of a picked box is a handle down its whole run")
struct EdgeGrabTests {
    /// The label from the bug: a text box pinned to 360 wide, one line tall.
    let label = CGRect(x: 140, y: 140, width: 360, height: 29)
    /// The label the width floor walk places: 132 wide, one line at 21.
    let shortLabel = CGRect(x: 140, y: 140, width: 132, height: 21)
    let roomy = CGRect(x: 100, y: 100, width: 200, height: 100)
    let tiny = CGRect(x: 40, y: 40, width: 19, height: 16)

    private func hit(_ p: CGPoint, _ frame: CGRect, zoom: CGFloat = 1) -> ResizeHandle? {
        Handles.hit(at: p, frame: frame, zoom: zoom, edgeGrab: true)
    }

    // MARK: The bug

    @Test func theSideOfAOneLineLabelResizesItRatherThanMovingIt() {
        // The three presses from the bug report, all on the right edge.
        #expect(hit(CGPoint(x: 500, y: 150), label) == .right)
        #expect(hit(CGPoint(x: 499, y: 154), label) == .right)
        #expect(hit(CGPoint(x: 500, y: 160), label) == .right)
        #expect(hit(CGPoint(x: 140, y: 154), label) == .left)
    }

    @Test func theMiddleOfAOneLineLabelStillPicksItUp() {
        for x in stride(from: label.minX + 20, to: label.maxX - 20, by: 40) {
            #expect(hit(CGPoint(x: x, y: label.midY), label) == nil, "x \(x)")
        }
    }

    /// The label is short enough that top and bottom bands would eat the words:
    /// twelve of its twenty nine points, leaving a sliver to pick it up by. So
    /// only the sides — the ones a label is actually resized by — take a band.
    @Test func aOneLineLabelKeepsItsWholeBodyToBePickedUpBy() {
        for y in stride(from: label.minY, through: label.maxY, by: 2) {
            #expect(hit(CGPoint(x: label.midX, y: y), label) == nil, "y \(y)")
        }
    }

    @Test func theCornersStillWinWhereTheyAreDrawn() {
        let layout = Handles.layout(in: label, zoom: 1)
        for corner in layout.handles {
            #expect(hit(layout.point(for: corner), label) == corner, "\(corner)")
        }
    }

    /// The walk that is meant to prove the 80 point width floor drags from the
    /// middle of this label's right edge.
    @Test func theWidthFloorWalksGrabPointIsTheRightEdge() {
        #expect(hit(CGPoint(x: 272, y: 150), shortLabel) == .right)
    }

    // MARK: A roomy box gains a whole edge instead of a square in the middle

    @Test func aRoomyBoxAnswersAnywhereAlongEachEdge() {
        #expect(hit(CGPoint(x: 100, y: 120), roomy) == .left)
        #expect(hit(CGPoint(x: 300, y: 180), roomy) == .right)
        #expect(hit(CGPoint(x: 130, y: 100), roomy) == .top)
        #expect(hit(CGPoint(x: 270, y: 200), roomy) == .bottom)
        // ...and its middle is still where you pick it up.
        #expect(hit(CGPoint(x: roomy.midX, y: roomy.midY), roomy) == nil)
    }

    @Test func aPressJustOutsideAnEdgeCountsAsThatEdge() {
        #expect(hit(CGPoint(x: 305, y: 150), roomy) == .right)
        #expect(hit(CGPoint(x: 307, y: 150), roomy) == nil)
    }

    // MARK: A cramped box keeps every guarantee it had

    @Test func aTinyLabelIsStillGrabbableEverywhereInside() {
        for x in stride(from: tiny.minX, through: tiny.maxX, by: 1) {
            for y in stride(from: tiny.minY, through: tiny.maxY, by: 1) {
                #expect(hit(CGPoint(x: x, y: y), tiny) == nil, "\(x),\(y)")
            }
        }
    }

    @Test func aHairlineDividerIsStillGrabbable() {
        let divider = CGRect(x: 0, y: 200, width: 400, height: 8)
        for y in stride(from: divider.minY, through: divider.maxY, by: 1) {
            #expect(hit(CGPoint(x: divider.midX, y: y), divider) == nil, "y \(y)")
        }
    }

    @Test func aSpeckIsStillGrabbable() {
        let speck = CGRect(x: 10, y: 10, width: 1, height: 1)
        #expect(hit(CGPoint(x: speck.midX, y: speck.midY), speck) == nil)
    }

    // MARK: Zoom decides it, like every other handle measure

    @Test func zoomingOutTakesTheEdgeBandsAwayWithTheHandles() {
        // 360x29 at 0.25x is 90x7 on screen: nothing left to aim at.
        #expect(hit(CGPoint(x: 500, y: 154), label, zoom: 0.25) == nil)
    }

    @Test func zoomingInGivesATinyLabelItsEdgesBack() {
        // Off the midpoint square, up the left edge: nothing but the band can
        // answer here, and at 4x the label is 76x64 on screen with room for it.
        #expect(hit(CGPoint(x: tiny.minX, y: tiny.minY + 2), tiny, zoom: 4) == .left)
    }

    // MARK: Off by default, so only the release that opted in changes

    @Test func withoutTheFlagTheEdgeIsNotAHandle() {
        #expect(Handles.hit(at: CGPoint(x: 500, y: 154), frame: label, zoom: 1) == nil)
        #expect(Handles.hit(at: CGPoint(x: 100, y: 120), frame: roomy, zoom: 1) == nil)
    }
}
