import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Watercolour (`docs/design/brushes.md`, decision 4). A stroke is a
/// see-through wash whose pigment pooled darker at the edge where it dried; it
/// bleeds past where the brush went; it settles into the paper's grain; strokes
/// that cross once dry deepen into a glaze; and a stroke painted into a wash
/// that is still wet blooms out through it. The plain round tip (still the oil
/// paint's until its slice) fails both measured bars.
@Suite("Watercolour rendering")
struct WatercolourRenderingTests {

    // MARK: - Helpers

    private let box = CGSize(width: 300, height: 160)
    private let scale: CGFloat = 2

    private func render(_ strokes: [BrushStroke], over paper: Bool = false) throws -> CGImage {
        let raster = try #require(PaintRasterizer.rasterize(PaintContent(strokes: strokes), size: box,
                                                            scale: scale))
        guard paper else { return raster }
        let context = try #require(CGContext(
            data: nil, width: raster.width, height: raster.height, bitsPerComponent: 8,
            bytesPerRow: raster.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: raster.width, height: raster.height))
        context.draw(raster, in: CGRect(x: 0, y: 0, width: raster.width, height: raster.height))
        return try #require(context.makeImage())
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

    /// The red channel averaged over a few points around `p`, 0...255.
    private func red(_ image: CGImage, _ p: CGPoint) -> Int {
        let data = rgba(image)
        var sum = 0, count = 0
        for dy in -2...2 {
            for dx in -2...2 {
                let x = Int(p.x * scale) + dx, y = Int(p.y * scale) + dy
                sum += Int(data[(y * image.width + x) * 4])
                count += 1
            }
        }
        return sum / count
    }

    private func line(_ points: [CGPoint], every ms: Double = 16) -> [StrokeSample] {
        var out: [StrokeSample] = []
        var t = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            let steps = max(2, Int(hypot(b.x - a.x, b.y - a.y) / 12))
            for i in 0..<steps {
                let f = CGFloat(i) / CGFloat(steps)
                out.append(StrokeSample(point: CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f), ms: t))
                t += ms
            }
        }
        if let last = points.last { out.append(StrokeSample(point: last, ms: t)) }
        return out
    }

    private func stroke(_ medium: BrushMedium, _ samples: [StrokeSample], size: Double,
                        set: [String: Double] = [:], hex: String = "#2060E0", seed: UInt32 = 4,
                        at time: Double? = nil) -> BrushStroke {
        BrushStroke(samples: samples,
                    settings: BrushSettings(medium: medium, values: ["size": size].merging(set) { $1 }),
                    colorHex: hex, seed: seed, startedAt: time)
    }

    private let a = CGPoint(x: 30, y: 80), b = CGPoint(x: 270, y: 80)

    private func straight(_ medium: BrushMedium, size: Double = 40, set: [String: Double] = [:]) -> BrushStroke {
        stroke(medium, line([a, b]), size: size, set: set)
    }

    // MARK: - The measured bars

    @Test("Measured bar: a watercolour stroke is darker at its edge than its middle; the round tip is not")
    func edgeDarkeningBar() throws {
        let wash = PaintMeasures.edgeToCentre(try render([straight(.watercolour)]), from: a, to: b,
                                              diameter: 40, scale: scale)
        #expect(wash >= PaintMeasures.watercolourEdgeBar, "watercolour \(wash)")
        let round = PaintMeasures.edgeToCentre(try render([straight(.oil, set: ["opacity": 50])]), from: a, to: b,
                                               diameter: 40, scale: scale)
        #expect(round < PaintMeasures.watercolourEdgeBar, "round tip \(round)")
    }

    @Test("Measured bar: a wet stroke spreads past the path the brush took; the round tip does not")
    func spreadBar() throws {
        let wash = PaintMeasures.spreadPastPath(try render([straight(.watercolour)]), from: a, to: b,
                                                diameter: 40, scale: scale)
        #expect(wash >= PaintMeasures.watercolourSpreadBar, "watercolour \(wash)")
        let round = PaintMeasures.spreadPastPath(try render([straight(.oil)]), from: a, to: b,
                                                 diameter: 40, scale: scale)
        #expect(round < PaintMeasures.watercolourSpreadBar, "round tip \(round)")
    }

    // MARK: - A wash

    @Test("A single stroke is a see-through wash, never the full colour")
    func transparentWash() throws {
        let image = try render([straight(.watercolour, set: ["granulation": 0])], over: true)
        let middle = red(image, CGPoint(x: 150, y: 80))
        // The paint is #2060E0: red 0x20 at full strength, 255 on bare paper.
        #expect(middle > 0x20 + 60 && middle < 235, "middle of the wash \(middle)")
        let alpha = PaintMeasures.meanAlpha(try render([straight(.watercolour)]), around: CGPoint(x: 150, y: 80),
                                            radius: 4, scale: scale)
        #expect(alpha < 0.75, "coverage at the middle \(alpha)")
    }

    @Test("A stroke that goes back over itself is still one wash, not darker where it doubled")
    func oneWashPerStroke() throws {
        let back = stroke(.watercolour, line([CGPoint(x: 30, y: 80), CGPoint(x: 260, y: 80), CGPoint(x: 265, y: 84),
                                              CGPoint(x: 30, y: 84)]), size: 40, set: ["granulation": 0])
        let image = try render([back], over: true)
        let twice = red(image, CGPoint(x: 150, y: 82)), once = red(image, CGPoint(x: 150, y: 70))
        #expect(abs(twice - once) <= 8, "covered twice \(twice), once \(once)")
    }

    @Test("Two strokes crossing once the first has dried deepen into a glaze")
    func glaze() throws {
        let across = stroke(.watercolour, line([CGPoint(x: 30, y: 80), CGPoint(x: 270, y: 80)]), size: 30,
                            set: ["granulation": 0], at: 0)
        let down = stroke(.watercolour, line([CGPoint(x: 150, y: 10), CGPoint(x: 150, y: 150)]), size: 30,
                          set: ["granulation": 0], seed: 5, at: 120)
        let image = try render([across, down], over: true)
        let overlap = red(image, CGPoint(x: 150, y: 80))
        let one = red(image, CGPoint(x: 80, y: 80)), other = red(image, CGPoint(x: 150, y: 35))
        #expect(overlap < one - 25 && overlap < other - 25, "overlap \(overlap), strokes \(one) and \(other)")
    }

    // MARK: - Wet into wet

    /// How many pixels of `base` a later stroke changed, out beyond where its
    /// own brush and bleed could reach (a Size 12 stroke at the default Bleed
    /// reaches under 9 points from its line): `from`...`to` points either side
    /// of x 150, inside the first stroke's band.
    private func changedBeyond(_ base: CGImage, _ both: CGImage, from: CGFloat, to: CGFloat) -> Int {
        let a = rgba(base), b = rgba(both)
        var changed = 0
        for y in Int(68 * scale)..<Int(92 * scale) {
            for x in Int((150 - to) * scale)..<Int((150 + to) * scale) {
                let dx = abs((CGFloat(x) + 0.5) / scale - 150)
                guard dx >= from else { continue }
                let i = (y * base.width + x) * 4 + 3
                if abs(Int(a[i]) - Int(b[i])) > 10 { changed += 1 }
            }
        }
        return changed
    }

    @Test("Painting into a wash that is still wet blooms out through it; into a dry one it does not")
    func wetIntoWetBlooms() throws {
        let first = stroke(.watercolour, line([CGPoint(x: 30, y: 80), CGPoint(x: 270, y: 80)]), size: 40, at: 0)
        let ends = try #require(first.endedAt)
        func into(after seconds: Double) -> BrushStroke {
            stroke(.watercolour, line([CGPoint(x: 150, y: 30), CGPoint(x: 150, y: 130)]), size: 12,
                   hex: "#C03020", seed: 9, at: ends + seconds)
        }
        let base = try render([first])
        let wet = changedBeyond(base, try render([first, into(after: 0.5)]), from: 11, to: 40)
        let dry = changedBeyond(base, try render([first, into(after: 60)]), from: 11, to: 40)
        #expect(wet > 400 && wet > dry * 4, "wet \(wet) pixels changed past the brush, dry \(dry)")
    }

    // MARK: - The settings

    @Test("Wetness: a dry brush skips on the paper's tooth, a wet one lays an unbroken wash")
    func wetnessDryBrush() throws {
        let dry = PaintMeasures.interiorGapFraction(try render([straight(.watercolour, set: ["wetness": 0])]),
                                                    from: a, to: b, diameter: 40, scale: scale)
        let wet = PaintMeasures.interiorGapFraction(try render([straight(.watercolour, set: ["wetness": 100])]),
                                                    from: a, to: b, diameter: 40, scale: scale)
        #expect(dry > 0.15 && wet < 0.05, "wetness 0 leaves \(dry) bare, wetness 100 \(wet)")
    }

    @Test("Wetness: a wetter brush is still wet a few seconds on, so a later stroke blooms into it")
    func wetnessKeepsItWet() throws {
        func bloom(_ wetness: Double) throws -> Int {
            let first = stroke(.watercolour, line([CGPoint(x: 30, y: 80), CGPoint(x: 270, y: 80)]), size: 40,
                               set: ["wetness": wetness], at: 0)
            let later = stroke(.watercolour, line([CGPoint(x: 150, y: 30), CGPoint(x: 150, y: 130)]), size: 12,
                               hex: "#C03020", seed: 9, at: (first.endedAt ?? 0) + 3)
            let base = try render([first])
            return changedBeyond(base, try render([first, later]), from: 11, to: 40)
        }
        let soaked = try bloom(100), parched = try bloom(10)
        #expect(soaked > parched * 4 && soaked > 200, "wetness 100 \(soaked), wetness 10 \(parched)")
    }

    @Test("Bleed: more bleed spreads the wash further past the brush")
    func bleedSpreads() throws {
        func spread(_ bleed: Double) throws -> Double {
            PaintMeasures.spreadPastPath(try render([straight(.watercolour, set: ["bleed": bleed])]),
                                         from: a, to: b, diameter: 40, scale: scale)
        }
        let none = try spread(0), lots = try spread(100)
        #expect(lots > none + 0.3, "bleed 0 \(none), bleed 100 \(lots)")
        #expect(none < 0.15, "with no bleed the wash keeps close to the brush: \(none)")
    }

    @Test("Granulation: pigment settles into the paper's pits, so the wash is grainier")
    func granulation() throws {
        let inner = CGRect(x: 60, y: 74, width: 180, height: 12)
        let smooth = PaintMeasures.unevenness(try render([straight(.watercolour, set: ["granulation": 0])]),
                                              in: inner, scale: scale)
        let grainy = PaintMeasures.unevenness(try render([straight(.watercolour, set: ["granulation": 100])]),
                                              in: inner, scale: scale)
        #expect(grainy > smooth * 1.8 && grainy > 0.12, "granulation 0 \(smooth), 100 \(grainy)")
    }

    @Test("Replay is the same every time")
    func deterministic() throws {
        let first = stroke(.watercolour, line([a, b]), size: 40, at: 0)
        let second = stroke(.watercolour, line([CGPoint(x: 150, y: 30), CGPoint(x: 150, y: 130)]), size: 14,
                            seed: 3, at: 1)
        #expect(rgba(try render([first, second])) == rgba(try render([first, second])))
    }

    // MARK: - Live and landed

    @Test("A watercolour stroke laid live into a wet wash shows what lands, bloom and glaze included")
    func liveIntoWetWash() throws {
        let first = stroke(.watercolour, line([CGPoint(x: 30, y: 80), CGPoint(x: 270, y: 80)]), size: 40, seed: 1,
                           at: 0)
        let second = stroke(.watercolour, line([CGPoint(x: 150, y: 20), CGPoint(x: 150, y: 140)]), size: 16,
                            hex: "#C03020", seed: 2, at: (first.endedAt ?? 0) + 0.5)
        let landed = rgba(try render([first, second]))
        let width = Int(box.width * scale), height = Int(box.height * scale)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
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
        let shown = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                           bytesPerRow: width * 4, space: space, bitmapInfo: info))
        shown.draw(try #require(working.makeImage()), in: CGRect(x: 0, y: 0, width: width, height: height))
        shown.draw(try #require(overlay.makeImage()), in: CGRect(x: 0, y: 0, width: width, height: height))
        let seen = rgba(try #require(shown.makeImage()))
        var differ = 0
        for i in seen.indices where abs(Int(seen[i]) - Int(landed[i])) > 4 { differ += 1 }
        #expect(Double(differ) / Double(seen.count) < 0.002, "\(differ) channel values differ")
    }
}
