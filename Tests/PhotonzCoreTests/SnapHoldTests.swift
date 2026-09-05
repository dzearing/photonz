import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Synthetic gradient field, same shape the analyzer produces.
private struct Field {
    var w: Int, h: Int
    var gx: [Double]
    var gy: [Double]

    init(w: Int, h: Int) {
        self.w = w
        self.h = h
        gx = [Double](repeating: 0, count: w * h)
        gy = [Double](repeating: 0, count: w * h)
    }

    mutating func addHorizontalEdge(row: Int, x0: Int, x1: Int, magnitude: Double = 2) {
        for x in max(0, x0)...min(w - 1, x1) { gy[row * w + x] = magnitude }
    }

    var map: EdgeMap { EdgeMap(width: w, height: h, gxMagnitude: gx, gyMagnitude: gy) }
}

/// A hand dragging slowly past something: a little travel per event, with the
/// wobble a hand resting on a mouse actually has. This is the walk the user
/// reported the flicker on, written down so it can be counted.
private func slowWalk(from: CGFloat, to: CGFloat, step: CGFloat = 0.4) -> [CGFloat] {
    let wobble: [CGFloat] = [0, 0.7, -0.5, 0.3, -0.2, 0.6, -0.6, 0.1]
    var out: [CGFloat] = []
    var v = from
    var i = 0
    while from > to ? v > to : v < to {
        out.append(v + wobble[i % wobble.count])
        v += from > to ? -step : step
        i += 1
    }
    return out
}

/// How many times a walk changed its mind about being snapped.
private struct FlipCount {
    var catches = 0
    var releases = 0
    private var last: Bool?

    mutating func record(snapped: Bool) {
        if let last, last != snapped {
            if snapped { catches += 1 } else { releases += 1 }
        }
        last = snapped
    }
}

@Suite("A snap that is showing is a snap you get")
struct SnapHoldTests {

    // MARK: The measure foot

    @Test func aSlowPassAcrossAnEdgeCatchesOnceAndLetsGoOnce() {
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 200, x0: 100, x1: 300)
        let map = f.map
        var hold = SnapHold()
        var flips = FlipCount()
        for y in slowWalk(from: 216, to: 176) {
            let snap = EdgeSnapping.snap(CGPoint(x: 200, y: y), edges: map, zoom: 1,
                                         xSpan: 100...300, snapToPixelGrid: false,
                                         holding: hold)
            hold = SnapHold(x: snap.guideX, y: snap.guideY)
            flips.record(snapped: snap.guideY != nil)
        }
        #expect(flips.catches == 1)
        #expect(flips.releases == 1)
    }

    @Test func theSameWalkWithNoMemoryIsTheFlickerTheUserSaw() {
        // The old behaviour, kept as the witness: with nothing held between
        // events the answer is taken and dropped several times on one pass.
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 200, x0: 100, x1: 300)
        let map = f.map
        var flips = FlipCount()
        for y in slowWalk(from: 216, to: 176) {
            let snap = EdgeSnapping.snap(CGPoint(x: 200, y: y), edges: map, zoom: 1,
                                         xSpan: 100...300, snapToPixelGrid: false)
            flips.record(snapped: snap.guideY != nil)
        }
        #expect(flips.catches > 1)
    }

    @Test func aCaughtEdgeSurvivesAWobbleWiderThanTheCatch() {
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 200, x0: 100, x1: 300)
        let map = f.map
        // Caught at 200, then the pointer wanders to 12 away — past the 8 it
        // would have taken to catch, so this is exactly the wobble that used
        // to lose the line.
        let kept = EdgeSnapping.snap(CGPoint(x: 200, y: 212), edges: map, zoom: 1,
                                     xSpan: 100...300, snapToPixelGrid: false,
                                     holding: SnapHold(y: 200))
        #expect(kept.point.y == 200)
        #expect(kept.guideY == 200)
    }

    @Test func aCaughtEdgeLetsGoOnceThePointerIsClearlyAway() {
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 200, x0: 100, x1: 300)
        let map = f.map
        let gone = EdgeSnapping.snap(CGPoint(x: 200, y: 217), edges: map, zoom: 1,
                                     xSpan: 100...300, snapToPixelGrid: false,
                                     holding: SnapHold(y: 200))
        #expect(gone.point.y == 217)
        #expect(gone.guideY == nil)
    }

    @Test func lettingGoTakesFartherThanCatchingDid() {
        // The rule the whole thing rests on: you cannot lose a line at a
        // distance that would not have caught it in the first place.
        #expect(SnapHold.releaseFactor > 1)
    }

    @Test func withNoLineShowingThePointerIsObeyedExactly() {
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 200, x0: 100, x1: 300)
        let snap = EdgeSnapping.snap(CGPoint(x: 200, y: 260.4), edges: f.map, zoom: 1,
                                     xSpan: 100...300, snapToPixelGrid: false,
                                     holding: SnapHold(y: 200))
        #expect(snap.point.y == 260.4)
        #expect(snap.guideY == nil)
    }

    // MARK: ⌘ frees the drag, and keeps it free

    @Test func commandDropsEveryLineAtOnce() {
        var hold = SnapHold(x: 100, y: 200)
        hold.free()
        #expect(hold.x == nil)
        #expect(hold.y == nil)
        #expect(hold.isFree)
    }

    @Test func aFreedDragStaysFreeEvenAfterTheKeyComesUp() {
        var hold = SnapHold()
        hold.free()
        // Later events in the same drag do not re-arm the magnets.
        #expect(hold.isFree)
        hold = SnapHold()
        #expect(!hold.isFree)  // ...until the next drag starts.
    }

    // MARK: A layer edge

    @Test func aResizedEdgeCatchesAPeerOnceAcrossASlowPass() {
        let peer = CGRect(x: 300, y: 300, width: 120, height: 40)
        var hold = SnapHold()
        var flips = FlipCount()
        for x in slowWalk(from: 316, to: 276) {
            let r = Snapping.snapResizedFrame(CGRect(x: 100, y: 100, width: x - 100, height: 50),
                                              handle: .right, canvas: CGSize(width: 800, height: 600),
                                              peers: [peer], gridSpacing: 8, zoom: 1,
                                              holding: hold)
            hold = SnapHold(x: r.guideX, y: r.guideY)
            flips.record(snapped: r.guideX != nil)
        }
        #expect(flips.catches == 1)
        #expect(flips.releases == 1)
    }

    @Test func aCaughtResizeEdgeSitsExactlyOnTheLineItIsShowing() {
        let peer = CGRect(x: 300, y: 300, width: 120, height: 40)
        let r = Snapping.snapResizedFrame(CGRect(x: 100, y: 100, width: 211, height: 50),
                                          handle: .right, canvas: CGSize(width: 800, height: 600),
                                          peers: [peer], gridSpacing: 8, zoom: 1,
                                          holding: SnapHold(x: 300))
        #expect(r.guideX == 300)
        #expect(r.frame.maxX == 300)
    }

    // MARK: A layer corner, both axes at once

    @Test func aCornerHoldsEachAxisOnItsOwn() {
        let peer = CGRect(x: 300, y: 400, width: 120, height: 40)
        // The x edge is 11 away from the line it caught (kept), the y edge is
        // 30 away from its own (let go) — one drag, two independent answers.
        let r = Snapping.snapResizedFrame(CGRect(x: 100, y: 100, width: 211, height: 270),
                                          handle: .bottomRight,
                                          canvas: CGSize(width: 800, height: 600),
                                          peers: [peer], gridSpacing: nil, zoom: 1,
                                          holding: SnapHold(x: 300, y: 400))
        #expect(r.guideX == 300)
        #expect(r.frame.maxX == 300)
        #expect(r.guideY == nil)
        #expect(r.frame.maxY == 370)
    }

    // MARK: A whole layer moving

    @Test func aMovedLayerCatchesAPeerOnceAcrossASlowPass() {
        let peer = CGRect(x: 300, y: 300, width: 120, height: 40)
        var hold = SnapHold()
        var flips = FlipCount()
        for x in slowWalk(from: 284, to: 324) {
            let r = Snapping.snapFrameOrigin(CGPoint(x: x, y: 100), size: CGSize(width: 50, height: 50),
                                             canvas: CGSize(width: 800, height: 600),
                                             peers: [peer], gridSpacing: 8, zoom: 1,
                                             holding: hold)
            hold = SnapHold(x: r.guideX, y: r.guideY)
            flips.record(snapped: r.guideX != nil)
        }
        #expect(flips.catches == 1)
        #expect(flips.releases == 1)
    }

    @Test func aMovedLayerStaysFlushWithTheLineItIsShowing() {
        let peer = CGRect(x: 300, y: 300, width: 120, height: 40)
        let r = Snapping.snapFrameOrigin(CGPoint(x: 289, y: 100), size: CGSize(width: 50, height: 50),
                                         canvas: CGSize(width: 800, height: 600),
                                         peers: [peer], gridSpacing: 8, zoom: 1,
                                         holding: SnapHold(x: 300))
        #expect(r.guideX == 300)
        #expect(r.origin.x == 300)
    }

    @Test func aHeldLineThatIsNowFarAwayIsNotResurrected() {
        // Holding a line the drag has long since left must not drag the layer
        // back to it: the hold is a grip, not an anchor.
        let peer = CGRect(x: 300, y: 300, width: 120, height: 40)
        let r = Snapping.snapFrameOrigin(CGPoint(x: 500, y: 100), size: CGSize(width: 50, height: 50),
                                         canvas: CGSize(width: 800, height: 600),
                                         peers: [peer], gridSpacing: nil, zoom: 1,
                                         holding: SnapHold(x: 300))
        #expect(r.guideX == nil)
        #expect(r.origin.x == 500)
    }
}

@Suite("The gate that keeps a straight drag straight")
struct DragAxisGateTests {

    private func drag(_ gate: inout DragAxisGate, _ points: [CGPoint]) {
        for p in points { gate.track(p) }
    }

    @Test func aDragStartsWithBothAxesOpen() {
        var gate = DragAxisGate()
        gate.reset(at: .zero)
        #expect(gate.axes == .both)
        #expect(gate.capturesX)
        #expect(gate.capturesY)
    }

    @Test func aDecisiveVerticalDragStopsCatchingVerticalLines() {
        var gate = DragAxisGate()
        gate.reset(at: CGPoint(x: 100, y: 100))
        drag(&gate, (1...10).map { CGPoint(x: 100, y: 100 + CGFloat($0) * 3) })
        #expect(gate.axes == .vertical)
        #expect(!gate.capturesX)
        #expect(gate.capturesY)
    }

    @Test func aWobbleAroundTheThresholdKeepsTheDecisionItAlreadyMade() {
        // Motion that sits near two-to-one, which is where the old gate lived,
        // and jitters either side of it. The answer must not change once.
        var gate = DragAxisGate()
        gate.reset(at: CGPoint(x: 100, y: 100))
        drag(&gate, (1...8).map { CGPoint(x: 100, y: 100 + CGFloat($0) * 3) })
        let locked = gate.axes
        var p = CGPoint(x: 100, y: 124)
        let wobble: [(CGFloat, CGFloat)] = [(0.5, 1.1), (-0.6, 0.9), (0.7, 1.4), (-0.4, 0.8),
                                            (0.9, 1.0), (-0.8, 1.2), (0.6, 0.7), (-0.5, 1.3)]
        for (dx, dy) in wobble {
            p = CGPoint(x: p.x + dx, y: p.y + dy)
            gate.track(p)
            #expect(gate.axes == locked)
        }
    }

    @Test func aDragThatGoesTrulyDiagonalOpensBothAgain() {
        var gate = DragAxisGate()
        gate.reset(at: CGPoint(x: 100, y: 100))
        drag(&gate, (1...8).map { CGPoint(x: 100, y: 100 + CGFloat($0) * 3) })
        #expect(gate.axes == .vertical)
        drag(&gate, (1...10).map { CGPoint(x: 100 + CGFloat($0) * 3, y: 124 + CGFloat($0) * 3) })
        #expect(gate.axes == .both)
    }

    @Test func aStalledDragKeepsItsLastDecisionRatherThanGuessingAgain() {
        var gate = DragAxisGate()
        gate.reset(at: CGPoint(x: 100, y: 100))
        drag(&gate, (1...10).map { CGPoint(x: 100, y: 100 + CGFloat($0) * 3) })
        #expect(gate.axes == .vertical)
        // The hand stops. Nothing new is being said, so nothing changes.
        drag(&gate, Array(repeating: CGPoint(x: 100, y: 130), count: 6))
        #expect(gate.axes == .vertical)
    }

    @Test func aNewDragForgetsTheLastOne() {
        var gate = DragAxisGate()
        gate.reset(at: CGPoint(x: 100, y: 100))
        drag(&gate, (1...10).map { CGPoint(x: 100, y: 100 + CGFloat($0) * 3) })
        #expect(gate.axes == .vertical)
        gate.reset(at: CGPoint(x: 400, y: 400))
        #expect(gate.axes == .both)
        #expect(gate.motion == .zero)
    }
}
