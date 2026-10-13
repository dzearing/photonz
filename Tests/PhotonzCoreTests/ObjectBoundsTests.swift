import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A small painter for the tests: shapes with antialiased edges (sixteen
/// samples a pixel), vertical gradients and soft glows, turned into the field
/// the readers walk.
struct ColourCanvas {
    let w: Int, h: Int
    var r: [Double], g: [Double], b: [Double]

    init(_ w: Int, _ h: Int, _ page: UInt32) {
        self.w = w
        self.h = h
        let c = Self.rgb(page)
        r = Array(repeating: c.0, count: w * h)
        g = Array(repeating: c.1, count: w * h)
        b = Array(repeating: c.2, count: w * h)
    }

    static func rgb(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xff), Double((hex >> 8) & 0xff), Double(hex & 0xff))
    }

    /// Whether a point is inside a rounded rect.
    static func inside(_ x: Double, _ y: Double, _ rect: CGRect, _ radius: Double) -> Bool {
        guard x >= rect.minX, x <= rect.maxX, y >= rect.minY, y <= rect.maxY else { return false }
        let cx = min(max(x, rect.minX + radius), rect.maxX - radius)
        let cy = min(max(y, rect.minY + radius), rect.maxY - radius)
        return (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius
    }

    /// How far outside a rounded rect a point is (0 inside).
    static func distance(_ x: Double, _ y: Double, _ rect: CGRect, _ radius: Double) -> Double {
        let cx = min(max(x, rect.minX + radius), rect.maxX - radius)
        let cy = min(max(y, rect.minY + radius), rect.maxY - radius)
        return max(0, ((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot() - radius)
    }

    mutating func blend(_ i: Int, _ c: (Double, Double, Double), _ a: Double) {
        r[i] = r[i] * (1 - a) + c.0 * a
        g[i] = g[i] * (1 - a) + c.1 * a
        b[i] = b[i] * (1 - a) + c.2 * a
    }

    /// A rounded rect filled from `top` to `bottom`, antialiased.
    mutating func fill(_ rect: CGRect, radius: Double = 0, top: UInt32, bottom: UInt32? = nil) {
        let t = Self.rgb(top), bt = Self.rgb(bottom ?? top)
        for y in max(0, Int(rect.minY) - 1)..<min(h, Int(rect.maxY) + 1) {
            for x in max(0, Int(rect.minX) - 1)..<min(w, Int(rect.maxX) + 1) {
                var hits = 0
                for sy in 0..<4 {
                    for sx in 0..<4 where Self.inside(Double(x) + (Double(sx) + 0.5) / 4,
                                                      Double(y) + (Double(sy) + 0.5) / 4, rect, radius) {
                        hits += 1
                    }
                }
                guard hits > 0 else { continue }
                let f = min(1, max(0, (Double(y) + 0.5 - rect.minY) / rect.height))
                let c = (t.0 + (bt.0 - t.0) * f, t.1 + (bt.1 - t.1) * f, t.2 + (bt.2 - t.2) * f)
                blend(y * w + x, c, Double(hits) / 16)
            }
        }
    }

    /// A soft glow or shadow: `alpha` at the shape's edge, gone `spread` px out.
    mutating func glow(_ rect: CGRect, radius: Double = 0, colour: UInt32, alpha: Double, spread: Double,
                       dy: Double = 0) {
        let c = Self.rgb(colour)
        let shifted = rect.offsetBy(dx: 0, dy: dy)
        for y in 0..<h {
            for x in 0..<w {
                let d = Self.distance(Double(x) + 0.5, Double(y) + 0.5, shifted, radius)
                guard d < spread else { continue }
                let t = 1 - d / spread
                blend(y * w + x, c, alpha * t * t)
            }
        }
    }

    var field: LumaField {
        var l = [UInt8](), rg = [UInt8](), yb = [UInt8]()
        l.reserveCapacity(w * h)
        for i in 0..<(w * h) {
            let o = LumaField.opponent(r: Int(r[i].rounded()), g: Int(g[i].rounded()), b: Int(b[i].rounded()))
            l.append(o.luma)
            rg.append(o.redGreen)
            yb.append(o.yellowBlue)
        }
        return LumaField(width: w, height: h, samples: l, redGreen: rg, yellowBlue: yb)
    }
}

@Suite("Object bounds: buttons, pills and cards by colour, past their glow")
struct ObjectBoundsTests {

    private func expectEdges(_ rect: CGRect?, _ expected: CGRect, within: CGFloat = 1,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        guard let rect else {
            Issue.record("expected \(expected), got nothing", sourceLocation: sourceLocation)
            return
        }
        let ok = abs(rect.minX - expected.minX) <= within && abs(rect.minY - expected.minY) <= within
            && abs(rect.maxX - expected.maxX) <= within && abs(rect.maxY - expected.maxY) <= within
        if !ok { Issue.record("expected \(expected), got \(rect)", sourceLocation: sourceLocation) }
    }

    /// The user's case, at 1x: a 274 x 62 gradient pill with a purple glow
    /// under it on a near black page.
    private static let pillRect = CGRect(x: 60, y: 50, width: 274, height: 62)
    private static let pill: LumaField = {
        var c = ColourCanvas(400, 200, 0x0a0a11)
        c.glow(pillRect, radius: 31, colour: 0x7c3aed, alpha: 0.45, spread: 30, dy: 6)
        c.fill(pillRect, radius: 31, top: 0x9d6bff, bottom: 0x7c3aed)
        // A white label in the middle.
        c.fill(CGRect(x: 140, y: 74, width: 110, height: 14), top: 0xffffff)
        return c.field
    }()

    @Test func aGradientPillWiderThan160IsReadToItsFillNotItsGlow() {
        for p in [CGPoint(x: 70, y: 81), CGPoint(x: 197, y: 56), CGPoint(x: 320, y: 105)] {
            expectEdges(ObjectBounds.objects(at: p, in: Self.pill, minElement: 10).first, Self.pillRect)
        }
    }

    @Test func fromItsLabelThePillIsOnTheLadder() {
        let ladder = ObjectBounds.objects(at: CGPoint(x: 160, y: 80), in: Self.pill, minElement: 10)
        #expect(ladder.contains { abs($0.width - 274) <= 1 && abs($0.height - 62) <= 1 }, "\(ladder)")
    }

    @Test func theOpenPageIsNothing() {
        #expect(ObjectBounds.objects(at: CGPoint(x: 380, y: 190), in: Self.pill, minElement: 10).isEmpty)
    }

    @Test func aButtonAsBrightAsItsPageReadsByColour() {
        var c = ColourCanvas(300, 120, 0x7f7f7f)
        let rect = CGRect(x: 40, y: 30, width: 200, height: 40)
        c.fill(rect, radius: 20, top: 0xd0604a)
        expectEdges(ObjectBounds.objects(at: CGPoint(x: 60, y: 50), in: c.field, minElement: 10).first, rect)
    }

    @Test func aWideFlatButtonHasNoSizeCap() {
        var c = ColourCanvas(900, 120, 0xffffff)
        let rect = CGRect(x: 30, y: 30, width: 820, height: 48)
        c.fill(rect, radius: 8, top: 0x1e3a8a)
        expectEdges(ObjectBounds.objects(at: CGPoint(x: 40, y: 54), in: c.field, minElement: 10).first, rect)
    }

    @Test func aWhiteCardUnderASoftShadowReadsTheCard() {
        var c = ColourCanvas(360, 220, 0xf2f2f7)
        let rect = CGRect(x: 60, y: 40, width: 240, height: 120)
        c.glow(rect, radius: 12, colour: 0x000000, alpha: 0.12, spread: 20, dy: 6)
        c.fill(rect, radius: 12, top: 0xffffff)
        c.fill(CGRect(x: 80, y: 60, width: 120, height: 12), top: 0x111111)
        expectEdges(ObjectBounds.objects(at: CGPoint(x: 70, y: 120), in: c.field, minElement: 10).first, rect)
    }

    @Test func aBorderedButtonOnItsPageReadsToTheOuterEdgeOfItsBorder() {
        var c = ColourCanvas(200, 100, 0xffffff)
        let rect = CGRect(x: 40, y: 30, width: 80, height: 28)
        c.fill(rect, radius: 6, top: 0xc7c7cc)
        c.fill(rect.insetBy(dx: 1, dy: 1), radius: 5, top: 0xffffff)
        let ladder = ObjectBounds.objects(at: CGPoint(x: 50, y: 44), in: c.field, minElement: 10)
        expectEdges(ladder.first, rect)
    }

    // MARK: A box

    @Test func aRoughBoxRoundThePillSnapsToItAndLeavesTheSmallPrintItCuts() {
        var c = ColourCanvas(400, 220, 0x0a0a11)
        c.glow(Self.pillRect, radius: 31, colour: 0x7c3aed, alpha: 0.45, spread: 30, dy: 6)
        c.fill(Self.pillRect, radius: 31, top: 0x9d6bff, bottom: 0x7c3aed)
        // A line of small print under the pill, longer than it.
        c.fill(CGRect(x: 20, y: 130, width: 360, height: 8), top: 0x6b6b7b)
        let box = CGRect(x: 45, y: 36, width: 304, height: 106)
        expectEdges(ObjectBounds.content(in: box, field: c.field, slack: 4, minElement: 10), Self.pillRect)
    }

    @Test func aBoxRoundNothingIsNothing() {
        #expect(ObjectBounds.content(in: CGRect(x: 340, y: 150, width: 50, height: 40), field: Self.pill,
                                     slack: 4, minElement: 10) == nil)
    }

    // MARK: What a hover costs

    /// A 3456 x 2234 capture whose page is a soft purple glow, the worst a
    /// hover meets: nothing on it holds still, so every growth runs until the
    /// hover's budget is spent. The budget is what keeps that inside a frame.
    @Test func aHoverOnOpenGlowingPageStaysInsideItsBudget() {
        let w = 3456, h = 2234
        var l = [UInt8](repeating: 0, count: w * h), rg = l, yb = l
        for y in 0..<h {
            for x in 0..<w {
                let dx = Double(x - w / 2) / 500, dy = Double(y - h / 2) / 350
                let glow = 40 * Foundation.exp(-(dx * dx + dy * dy))
                // Crisp hairlines round it, as text and controls would be, so
                // every walk out from the pointer crosses an edge to flat page.
                let mark = abs(x - w / 2) == 1300 || abs(y - h / 2) == 900
                l[y * w + x] = mark ? 90 : UInt8(10 + glow)
                rg[y * w + x] = mark ? 128 : UInt8(128 + glow / 3)
                yb[y * w + x] = mark ? 128 : UInt8(124 - glow / 2)
            }
        }
        let field = LumaField(width: w, height: h, samples: l, redGreen: rg, yellowBlue: yb)
        func cpu() -> Double {
            var t = timespec()
            clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
            return Double(t.tv_sec) * 1000 + Double(t.tv_nsec) / 1_000_000
        }
        var ratios: [Double] = []
        for k in 0..<5 {
            var t = cpu()
            CPUYardstick.round()
            let ruler = cpu() - t
            t = cpu()
            let found = ObjectBounds.objects(at: CGPoint(x: w / 2 + 40 * k, y: h / 2 + 100), in: field,
                                             minElement: 20)
            let hover = cpu() - t
            #expect(found.isEmpty, "\(found)")
            if ruler > 0 { ratios.append(hover / ruler) }
        }
        ratios.sort()
        let ratio = ratios.isEmpty ? .infinity : ratios[ratios.count / 2]
        let perCallMS = ratio * CPUYardstick.baselineMS
        print("[perf] object hover on open glowing page: \(String(format: "%.1f", perCallMS)) ms "
              + "of the calibration machine's time unoptimized, ratio \(String(format: "%.2f", ratio))")
        // Reads about 365 ms here, unoptimized, on 2026-10-13: the hover spends
        // its whole million-pixel budget. The app's optimized build does the
        // same work in under 20 ms (measured on the user's own capture). A
        // growth that ignored the budget would run on over the whole glow.
        if PerfGate.isOn {
            #expect(perCallMS < 800, "an open-page hover cost \(perCallMS) ms, \(ratio) times the ruler")
        }
    }
}
