import CoreGraphics
import Foundation
import PhotonzCore
import Testing

// What it costs to say where a press would land, asked once per mouse move.
//
// The mark under the pointer (`CanvasDrawLanding`) runs on every hover frame,
// so the claim worth guarding is not "it is fast" but "one answer costs a small
// fraction of a frame". A frame is 16ms and a mouse move arrives at most every
// 8ms, so anything into the hundreds of microseconds is already too much.
//
// WHICH BUILD THE NUMBER CAME FROM IS THE WHOLE STORY HERE. This file used to
// say the mark had to be gated on the grid, because asking the picture's own
// borders cost about 2.4ms a mouse move on a 2560 by 1600 screenshot. That
// reading was taken by `swift test`, which builds unoptimized, and every app
// bundle is built by `Scripts/build-app.sh`, which is `swift build -c release`.
// The same measurement in release is about 17 microseconds. So there was never
// a cost to gate on, the gate came off (`CanvasDrawLanding`), and the ceilings
// below are written per configuration so the difference can never be mistaken
// for a finding again: `release` carries the real ceiling, `debug` a loose one
// that only catches a tenfold regression.
//
// Read on the thread's own CPU clock, fastest of a run, so a test machine
// sharing cores with a build cannot turn a healthy number into a failure. The
// one check that compares two costs to each other takes them back to back
// inside every round as well: see `relativeGap` for why a ceiling on one number
// survives a busy machine when a gap between two separately measured ones does
// not.

/// What one hover frame may cost, in microseconds. The release number is the
/// claim: a mouse move arrives at most every 8ms and this is a fraction of a
/// percent of it. The debug number is not a claim about the product, only a
/// tripwire on the unoptimized build the test suite runs in.
#if DEBUG
private let hoverFrameCeiling: Double = 25_000
#else
private let hoverFrameCeiling: Double = 200
#endif

private func threadCPUNow() -> Duration {
    var ts = timespec()
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
    return .seconds(ts.tv_sec) + .nanoseconds(ts.tv_nsec)
}

private func microseconds(_ d: Duration) -> Double { d / .microseconds(1) }

/// The cost of ONE mouse move: the fastest round of `calls`, each round doing
/// `each` of them, after a warm-up.
private func fastest(_ name: String, calls: Int, each: Int, _ body: () -> Void) -> Double {
    body()
    var cpu: [Duration] = []
    for _ in 0..<calls {
        let start = threadCPUNow()
        body()
        cpu.append(threadCPUNow() - start)
    }
    let best = microseconds(cpu.min() ?? .zero) / Double(each)
    print(String(format: "[perf] %@: %.1f us a mouse move (worst round %.1f us each)",
                 name, best, microseconds(cpu.max() ?? .zero) / Double(each)))
    return best
}

/// How far apart two costs are, as a fraction of the first, measured with the
/// two taken BACK TO BACK inside every round and judged round by round.
///
/// Measuring one in full and then the other is what this replaced, and it does
/// not survive the full suite: on 2026-09-16 the same run read 2633 us for the
/// expensive map and 5697 us for the cheap one, because the two blocks ran
/// minutes apart in scheduler terms and landed on different cores with
/// different caches. Half a dozen red runs since 2026-09-15 were all that and
/// nothing else. Inside one round both readings share whatever the round got,
/// so their difference is about the work again; the median of the rounds then
/// keeps one round where the thread was taken away from deciding anything.
private func relativeGap(_ name: String, rounds: Int, each: Int,
                         _ a: () -> Void, _ b: () -> Void) -> (gap: Double, aCost: Double) {
    a()
    b()
    var gaps: [Double] = []
    var aCosts: [Duration] = []
    var bCosts: [Duration] = []
    for _ in 0..<rounds {
        var start = threadCPUNow()
        a()
        let aRound = threadCPUNow() - start
        start = threadCPUNow()
        b()
        let bRound = threadCPUNow() - start
        aCosts.append(aRound)
        bCosts.append(bRound)
        let aUS = microseconds(aRound), bUS = microseconds(bRound)
        gaps.append(aUS > 0 ? abs(aUS - bUS) / aUS : .infinity)
    }
    gaps.sort()
    let typical = gaps[gaps.count / 2]
    let aBest = microseconds(aCosts.min() ?? .zero) / Double(each)
    print(String(format: "[perf] %@: %.0f%% apart in a typical round over %d interleaved rounds "
                 + "(widest %.0f%%); %.1f us and %.1f us a mouse move at their fastest",
                 name, typical * 100, rounds, gaps[gaps.count - 1] * 100,
                 aBest, microseconds(bCosts.min() ?? .zero) / Double(each)))
    return (typical, aBest)
}

@Suite("What the landing mark costs per mouse move")
struct DrawLandingCostTests {

    /// A 2560 by 1600 picture with a border every 40 pixels each way: 104 full
    /// length lines, denser than any real interface.
    private static let busyEdges: EdgeMap = {
        let w = 2560, h = 1600
        var gx = [Double](repeating: 0, count: w * h)
        var gy = [Double](repeating: 0, count: w * h)
        for col in stride(from: 40, to: w, by: 40) {
            for y in 0..<h { gx[y * w + col] = 2 }
        }
        for row in stride(from: 40, to: h, by: 40) {
            for x in 0..<w { gy[row * w + x] = 2 }
        }
        return EdgeMap(width: w, height: h, gxMagnitude: gx, gyMagnitude: gy)
    }()

    /// The same picture with only four borders found in it, which separates the
    /// cost of the picture's SIZE from the cost of what is in it.
    private static let sparseEdges: EdgeMap = {
        let w = 2560, h = 1600
        var gx = [Double](repeating: 0, count: w * h)
        var gy = [Double](repeating: 0, count: w * h)
        for col in [320, 2240] { for y in 0..<h { gx[y * w + col] = 2 } }
        for row in [200, 1400] { for x in 0..<w { gy[row * w + x] = 2 } }
        return EdgeMap(width: w, height: h, gxMagnitude: gx, gyMagnitude: gy)
    }()

    /// Twenty pinned guides, more than anyone has put on one picture.
    private static let guides: [CanvasGuide] = (0..<10).flatMap { i in
        [CanvasGuide(axis: .vertical, position: CGFloat(i) * 117 + 31),
         CanvasGuide(axis: .horizontal, position: CGFloat(i) * 93 + 17)]
    }

    /// The pointer wandering, so no two calls get the same answer handed back
    /// by a cache that does not exist and must not be assumed.
    private func probes(_ count: Int) -> [CGPoint] {
        (0..<count).map { i in
            CGPoint(x: CGFloat((i * 37) % 2500) + 0.5, y: CGFloat((i * 53) % 1550) + 0.5)
        }
    }

    private func landing(_ p: CGPoint, edges: EdgeMap, gridSpacing: CGFloat? = 8) -> CGPoint {
        AnnotationSnapping.snap(p, shape: .rectangle, opposite: nil, edges: edges,
                                zoom: 2, free: false, holding: .none, gridHolding: .none,
                                gridSpacing: gridSpacing, gridOrigin: .zero,
                                gridAxes: .columnsAndRows, guides: Self.guides).point
    }

    @Test func aShapeToolOnADrawnCanvasCostsAlmostNothing() {
        // The case this feature is for: an icon grid on a canvas the app drew,
        // where there is no photograph to find borders in.
        let points = probes(64)
        var sink = CGPoint.zero
        let each = fastest("a grid and twenty guides, nothing photographed",
                           calls: 200, each: points.count) {
            for p in points { sink = self.landing(p, edges: .empty) }
        }
        #expect(sink != CGPoint(x: -1, y: -1))
        #expect(each < 100)
    }

    @Test func aimingOverAScreenshotWithNoGridCostsAFractionOfAFrame() {
        // The case this task added: a plain 2560 by 1600 capture, no grid
        // pulling, the rectangle tool hovering. Every move asks the picture's
        // borders, which is the query that was once thought too expensive to
        // put on the hover path.
        let points = probes(64)
        var sink = CGPoint.zero
        let each = fastest("no grid, hovering over a 2560x1600 screenshot",
                           calls: 40, each: points.count) {
            for p in points { sink = self.landing(p, edges: Self.busyEdges, gridSpacing: nil) }
        }
        #expect(sink != CGPoint(x: -1, y: -1))
        #expect(each < hoverFrameCeiling)
    }

    @Test func thePenCostsAlmostNothing() {
        var session = PenSession()
        session.grid = NudgeGrid(spacing: 8, origin: .zero, axes: .columnsAndRows)
        // A path with plenty of points already down, because closing and
        // finishing are read against the anchors every time.
        for i in 0..<40 {
            session.press(at: CGPoint(x: CGFloat(i) * 31, y: CGFloat(i) * 17),
                          constrained: false, zoom: 2)
            _ = session.release()
        }
        let points = probes(64)
        var sink = CGPoint.zero
        let each = fastest("the Pen with forty anchors down",
                           calls: 200, each: points.count) {
            for p in points { sink = session.landing(at: p, constrained: false, zoom: 2).point }
        }
        #expect(sink != CGPoint(x: -1, y: -1))
        #expect(each < 100)
    }

    @Test func whatABorderQueryCostsIsThePictureSizeNotItsContents() {
        // A grid ON TOP of a 2560 by 1600 screenshot: the heaviest hover there
        // is, since every move asks the grid and the picture's borders both.
        // The fact recorded here is that the two pictures cost the same, which
        // is what says the price is `EdgeMap` scanning a profile the full width
        // of the picture rather than anything to do with how much was found in
        // it. Worth keeping because a change that made the cost track the
        // number of borders would be a real regression on a busy capture.
        let points = probes(64)
        var sink = CGPoint.zero
        let (gap, dense) = relativeGap(
            "grid over a 2560x1600 screenshot, 104 borders in it against the same with four",
            rounds: 20, each: points.count,
            { for p in points { sink = self.landing(p, edges: Self.busyEdges) } },
            { for p in points { sink = self.landing(p, edges: Self.sparseEdges) } })
        #expect(sink != CGPoint(x: -1, y: -1))
        // Within a whisker of each other: the cost is the picture's WIDTH, not
        // what is drawn on it. That is the fact worth recording.
        #expect(gap < 0.5)
        #expect(dense < hoverFrameCeiling)
    }
}
