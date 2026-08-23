import Foundation
import PhotonzCore
import Testing

/// A brightness canvas: the same one-byte-per-pixel picture the analyzer hands
/// element detection.
private struct Canvas {
    var w: Int, h: Int
    var pixels: [UInt8]

    init(w: Int, h: Int, background: UInt8 = 255) {
        self.w = w
        self.h = h
        pixels = [UInt8](repeating: background, count: w * h)
    }

    mutating func fill(x: Int, y: Int, width: Int, height: Int, _ tone: UInt8) {
        for row in y..<(y + height) where row >= 0 && row < h {
            for col in x..<(x + width) where col >= 0 && col < w {
                pixels[row * w + col] = tone
            }
        }
    }

    var field: LumaField { LumaField(width: w, height: h, samples: pixels) }
}

@Suite("LumaField")
struct LumaFieldTests {

    @Test func amisSizedFieldIsEmptyRatherThanFatal() {
        #expect(LumaField(width: 10, height: 10, samples: [1, 2, 3]).isEmpty)
        #expect(LumaField.empty.isEmpty)
        #expect(LumaField.empty.luma(0, 0) == 0)
    }

    @Test func readsClampToTheImage() {
        var c = Canvas(w: 4, h: 4, background: 0)
        c.fill(x: 0, y: 0, width: 1, height: 1, 255)
        let field = c.field
        #expect(field.luma(0, 0) == 1)
        #expect(field.luma(-5, -5) == 1)   // clamped back onto the corner
        #expect(field.luma(99, 99) == 0)
    }

    @Test func aRuleOnWhiteReadsAsAHorizontalBoundary() {
        // The difference is taken ACROSS the rule, so a 1 px line reads even
        // though the rows either side of it are identical.
        var c = Canvas(w: 20, h: 20)
        c.fill(x: 0, y: 10, width: 20, height: 1, 100)
        let field = c.field
        #expect(field.horizontalResponse(x: 5, y: 10) > 0.5)
        #expect(field.horizontalResponse(x: 5, y: 3) == 0)
    }

    @Test func aColumnEdgeReadsAsAVerticalBoundary() {
        var c = Canvas(w: 20, h: 20)
        c.fill(x: 10, y: 0, width: 10, height: 20, 0)
        let field = c.field
        #expect(field.verticalResponse(x: 10, y: 5) > 0.5)
        #expect(field.horizontalResponse(x: 5, y: 5) == 0)
    }
}

@Suite("EdgeRun")
struct EdgeRunTests {

    @Test func followsARuleToItsEnds() {
        var c = Canvas(w: 200, h: 100)
        c.fill(x: 40, y: 50, width: 120, height: 2, 100)
        let run = EdgeRun.horizontal(row: 50, seedX: 100, in: c.field)
        #expect(run?.lowerBound == 40)
        #expect(run?.upperBound == 159)
    }

    @Test func aShortRuleAndALongOneAreToldApart() {
        // The whole reason this exists: an edge map cannot tell a divider that
        // spans a row from the card border that spans 20 px more.
        var c = Canvas(w: 300, h: 200)
        c.fill(x: 20, y: 40, width: 260, height: 2, 180)   // card top
        c.fill(x: 40, y: 100, width: 220, height: 2, 220)  // row divider
        let card = EdgeRun.horizontal(row: 40, seedX: 150, in: c.field)
        let divider = EdgeRun.horizontal(row: 100, seedX: 150, in: c.field)
        #expect(card?.lowerBound == 20)
        #expect(divider?.lowerBound == 40)
        #expect(divider?.upperBound == 259)
    }

    @Test func followsABoundaryAroundACornerRadius() {
        // A rounded top edge drifts a row per column near its ends. The walk has
        // to follow it, or every rounded control reads short.
        var c = Canvas(w: 200, h: 100)
        c.fill(x: 50, y: 40, width: 100, height: 30, 60)
        for step in 0..<6 {                       // chamfer both top corners
            c.fill(x: 50 + step, y: 40, width: 1, height: 6 - step, 255)
            c.fill(x: 149 - step, y: 40, width: 1, height: 6 - step, 255)
        }
        let run = EdgeRun.horizontal(row: 40, seedX: 100, in: c.field)
        #expect((run?.lowerBound ?? 999) <= 52)
        #expect((run?.upperBound ?? 0) >= 147)
    }

    @Test func columnsWalkTheOtherWay() {
        var c = Canvas(w: 200, h: 200)
        c.fill(x: 80, y: 30, width: 2, height: 90, 60)
        let run = EdgeRun.vertical(column: 80, seedY: 70, in: c.field)
        #expect(run?.lowerBound == 30)
        #expect(run?.upperBound == 119)
    }

    @Test func flatPixelsHaveNoRun() {
        let c = Canvas(w: 100, h: 100)
        #expect(EdgeRun.horizontal(row: 50, seedX: 50, in: c.field) == nil)
        #expect(EdgeRun.horizontal(row: 50, seedX: 50, in: .empty) == nil)
    }

    @Test func aSeedOnADeadPixelStillFindsTheBoundary() {
        // The pointer's own column often lands in a gap between glyphs or just
        // inside a corner; the seed search is what keeps that from reading as
        // "no boundary here", and short breaks are bridged rather than ending
        // the run.
        var c = Canvas(w: 200, h: 100)
        c.fill(x: 40, y: 50, width: 120, height: 2, 100)
        c.fill(x: 99, y: 50, width: 3, height: 2, 255)   // a 3 px break in the rule
        let run = EdgeRun.horizontal(row: 50, seedX: 100, in: c.field)
        #expect(run?.lowerBound == 40)
        #expect(run?.upperBound == 159)
    }

    @Test func theWalkStopsAtItsReach() {
        var c = Canvas(w: 600, h: 100)
        c.fill(x: 0, y: 50, width: 600, height: 2, 100)
        let run = EdgeRun.horizontal(row: 50, seedX: 300, in: c.field, reach: 50)
        #expect(run?.lowerBound == 250)
        #expect(run?.upperBound == 350)
    }
}
