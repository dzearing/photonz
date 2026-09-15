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
// The mark is only ever asked with the grid pulling, and that gate is not
// arithmetic tidiness, it is this file: asking the picture's own borders costs
// milliseconds on a big screenshot however few borders are in it, because
// `EdgeMap.verticalEdges` builds and scans a profile the full width of the
// picture on every call. The two ceilings below are the cases the gate leaves
// on the hover path, and the third measurement is the one it keeps off it.
//
// Read on the thread's own CPU clock, fastest of a run, so a test machine
// sharing cores with a build cannot turn a healthy number into a failure.

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

    private func landing(_ p: CGPoint, edges: EdgeMap) -> CGPoint {
        AnnotationSnapping.snap(p, shape: .rectangle, opposite: nil, edges: edges,
                                zoom: 2, free: false, holding: .none, gridHolding: .none,
                                gridSpacing: 8, gridOrigin: .zero,
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

    @Test func aGridOverALargeScreenshotPaysForTheBorderQuery() {
        // The expensive case, and the reason the mark is gated on the grid:
        // with the grid on OVER a 2560 by 1600 screenshot, every hover move
        // asks the picture's borders too. The ceiling here is deliberately
        // loose, because the number is not this feature's to fix — it belongs
        // to `EdgeMap`, which every annotation drag and every measure hover
        // already pays. It is here so the number is written down, and so a
        // tenfold regression in that shared query is caught by something.
        let points = probes(64)
        var sink = CGPoint.zero
        let dense = fastest("grid over a 2560x1600 screenshot, 104 borders in it",
                            calls: 20, each: points.count) {
            for p in points { sink = self.landing(p, edges: Self.busyEdges) }
        }
        let sparse = fastest("the same screenshot with only four borders in it",
                             calls: 20, each: points.count) {
            for p in points { sink = self.landing(p, edges: Self.sparseEdges) }
        }
        #expect(sink != CGPoint(x: -1, y: -1))
        // Within a whisker of each other: the cost is the picture's WIDTH, not
        // what is drawn on it. That is the fact worth recording.
        #expect(abs(dense - sparse) < dense * 0.5)
        #expect(dense < 25_000)
    }
}
