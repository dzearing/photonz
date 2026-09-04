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
