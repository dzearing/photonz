import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Oil paint (`docs/design/brushes.md`, decision 4). A stroke is laid by a row
/// of bristles: it streaks along its direction with lit ridges, it picks up
/// the paint it crosses and carries that colour on past it, mixing, by Smear,
/// and it runs dry over a distance Load sets. The plain round tip fails both
/// measured bars.
@Suite("Oil paint rendering")
struct OilRenderingTests {

    // MARK: - Helpers

    private let box = CGSize(width: 320, height: 200)
    private let scale: CGFloat = 2
    private let blue = "#2050C8", red = "#D02818"

    private func render(_ strokes: [BrushStroke], size: CGSize? = nil) throws -> CGImage {
        try #require(PaintRasterizer.rasterize(PaintContent(strokes: strokes), size: size ?? box, scale: scale))
    }

    /// The same strokes, every one stamped with the plain round.
    private func round(_ strokes: [BrushStroke]) throws -> CGImage {
        try PaintRasterizer.$plainRound.withValue(true) { try render(strokes) }
    }

    private func line(_ points: [CGPoint], every ms: Double = 16) -> [StrokeSample] {
        var out: [StrokeSample] = []
        var t = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            let steps = max(2, Int(hypot(b.x - a.x, b.y - a.y) / 10))
            for i in 0..<steps {
                let f = CGFloat(i) / CGFloat(steps)
                out.append(StrokeSample(point: CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f), ms: t))
                t += ms
            }
        }
        if let last = points.last { out.append(StrokeSample(point: last, ms: t)) }
        return out
    }

    private func oil(_ from: CGPoint, _ to: CGPoint, size: Double = 24, set: [String: Double] = [:],
                     hex: String? = nil, seed: UInt32 = 5) -> BrushStroke {
        BrushStroke(samples: line([from, to]),
                    settings: BrushSettings(medium: .oil, values: ["size": size].merging(set) { $1 }),
                    colorHex: hex ?? blue, seed: seed)
    }

    private let a = CGPoint(x: 30, y: 100), b = CGPoint(x: 290, y: 100)

    /// A red stroke down the middle, then a blue one across it, left to right.
    private func crossing(set: [String: Double] = [:]) -> [BrushStroke] {
        [oil(CGPoint(x: 110, y: 20), CGPoint(x: 110, y: 180), size: 30, hex: red, seed: 1),
         oil(a, b, set: set, hex: blue, seed: 2)]
    }

    /// How much red the blue stroke carries over the two brush widths after
    /// it leaves the red one.
    private func carried(_ image: CGImage) -> Double {
        let leaves: CGFloat = 110 + 15 - 30
        return PaintMeasures.carriedShare(image, from: a, to: b, diameter: 24, scale: scale,
                                          own: RGBA(hex: blue)!, foreign: RGBA(hex: red)!,
                                          start: leaves + 2, end: leaves + 48)
    }

    // MARK: - The measured bars

    @Test("Measured bar: inside a stroke the bristles leave lit ridges; the round tip is flat")
    func ridgeBar() throws {
        let stroke = oil(a, b)
        let ridges = PaintMeasures.ridgeContrast(try render([stroke]), from: a, to: b, diameter: 24, scale: scale)
        #expect(ridges >= PaintMeasures.oilRidgeBar, "oil \(ridges)")
        let flat = PaintMeasures.ridgeContrast(try round([stroke]), from: a, to: b, diameter: 24, scale: scale)
        #expect(flat < PaintMeasures.oilRidgeBar, "round tip \(flat)")
    }

    @Test("The streaks run along the stroke: averaged over four widths they are still there")
    func streaksRunAlong() throws {
        let image = try render([oil(a, b)])
        let short = PaintMeasures.ridgeContrast(image, from: a, to: b, diameter: 24, scale: scale)
        let long = PaintMeasures.ridgeContrast(image, from: a, to: b, diameter: 24, scale: scale, stretch: 48)
        #expect(long >= short * 0.6, "short \(short), long \(long)")
        // Down a vertical stroke the streaks turn with it.
        let top = CGPoint(x: 160, y: 20), bottom = CGPoint(x: 160, y: 180)
        let down = try render([oil(top, bottom)])
        let along = PaintMeasures.ridgeContrast(down, from: top, to: bottom, diameter: 24, scale: scale, stretch: 48)
        #expect(along >= PaintMeasures.oilRidgeBar, "vertical \(along)")
    }

    @Test("Measured bar: a stroke across another carries its colour on past it; the round tip does not")
    func carryBar() throws {
        let share = carried(try render(crossing()))
        #expect(share >= PaintMeasures.oilCarryBar, "oil \(share)")
        let flat = carried(try round(crossing()))
        #expect(flat < 0.02, "round tip \(flat)")
    }

    @Test("Where it crosses, the two colours mix rather than one covering the other")
    func mixesAtTheCrossing() throws {
        let image = try render(crossing())
        let mix = PaintMeasures.carriedShare(image, from: a, to: b, diameter: 24, scale: scale,
                                             own: RGBA(hex: blue)!, foreign: RGBA(hex: red)!,
                                             start: 100, end: 120)
        #expect(mix > 0.15 && mix < 0.85, "mix \(mix)")
    }

    @Test("Smear sets how much it drags: none at 0, more at 100 than at the default")
    func smearSetsHowMuch() throws {
        let none = carried(try render(crossing(set: ["smear": 0])))
        let some = carried(try render(crossing()))
        let lots = carried(try render(crossing(set: ["smear": 100])))
        #expect(none < 0.02, "smear 0: \(none)")
        #expect(some > none + 0.05, "default \(some) vs 0 \(none)")
        #expect(lots > some + 0.05, "smear 100 \(lots) vs default \(some)")
    }

    @Test("Load sets how far a stroke goes before the brush runs dry")
    func loadSetsTheReach() throws {
        let wide = CGSize(width: 900, height: 80)
        let from = CGPoint(x: 20, y: 40), to = CGPoint(x: 880, y: 40)
        func reach(_ load: Double) throws -> Double {
            let image = try render([oil(from, to, size: 16, set: ["load": load])], size: wide)
            return PaintMeasures.reachBeforeDry(image, from: from, to: to, diameter: 16, scale: scale)
        }
        let light = try reach(20), heavy = try reach(80)
        #expect(light < 860, "load 20 never ran dry: \(light)")
        #expect(heavy > light * 1.6, "load 80 \(heavy) vs load 20 \(light)")
        let flat = PaintMeasures.reachBeforeDry(
            try PaintRasterizer.$plainRound.withValue(true) {
                try render([oil(from, to, size: 16, set: ["load": 20])], size: wide)
            }, from: from, to: to, diameter: 16, scale: scale)
        #expect(flat >= 859, "the round tip never runs dry: \(flat)")
    }

    @Test("A fresh layer gives nothing to pick up: the first stroke is its own colour")
    func firstStrokeIsItsOwnColour() throws {
        let image = try render([oil(a, b, hex: blue)])
        let share = PaintMeasures.carriedShare(image, from: a, to: b, diameter: 24, scale: scale,
                                               own: RGBA(hex: blue)!, foreign: RGBA(hex: red)!,
                                               start: 40, end: 220)
        #expect(share < 0.02, "\(share)")
    }

    @Test("A click with the brush lays one dab")
    func aClickPaints() throws {
        let click = BrushStroke(samples: [StrokeSample(point: CGPoint(x: 100, y: 100), ms: 0)],
                                settings: BrushSettings(medium: .oil, values: ["size": 24]),
                                colorHex: blue, seed: 3)
        let covered = PaintMeasures.meanAlpha(try render([click]), around: CGPoint(x: 100, y: 100), radius: 4,
                                              scale: scale)
        #expect(covered > 0.5, "\(covered)")
    }

    @Test("The same stroke renders the same pixels every time")
    func deterministic() throws {
        let one = try render(crossing()), two = try render(crossing())
        #expect(one.dataProvider?.data as Data? == two.dataProvider?.data as Data?)
    }

    // MARK: - Live and landed

    @Test("The live stroke over the paint it lands on shows what lands")
    func liveMatchesLanded() throws {
        let strokes = crossing()
        let first = strokes[0], second = strokes[1]
        let landed = rgba(try render(strokes))
        let width = Int(box.width * scale), height = Int(box.height * scale)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let working = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: space, bitmapInfo: info))
        working.draw(try render([first]), in: CGRect(x: 0, y: 0, width: width, height: height))
        let overlay = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: space, bitmapInfo: info))
        let live = try #require(PaintRasterizer.LiveMarker(
            stroke: second, bitmap: overlay, pointsToPixels: CGAffineTransform(scaleX: scale, y: scale),
            clip: CGRect(x: 0, y: 0, width: width, height: height), working: working, earlier: [first]))
        #expect(live.showsAtFullStrength)
        var walker = BrushPlacement.Walker(settings: second.settings, seed: second.seed)
        for sample in second.samples { live.mark(walker.add(sample)) }
        live.mark(walker.finish())
        live.finish()
        let shown = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                           bytesPerRow: width * 4, space: space, bitmapInfo: info))
        shown.draw(try #require(working.makeImage()), in: CGRect(x: 0, y: 0, width: width, height: height))
        shown.draw(try #require(overlay.makeImage()), in: CGRect(x: 0, y: 0, width: width, height: height))
        let seen = rgba(try #require(shown.makeImage()))
        var differ = 0
        for i in seen.indices where abs(Int(seen[i]) - Int(landed[i])) > 4 { differ += 1 }
        #expect(Double(differ) / Double(seen.count) < 0.002, "\(differ) channel values differ")
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }
}
