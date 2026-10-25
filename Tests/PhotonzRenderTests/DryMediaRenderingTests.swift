import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Charcoal, chalk and crayon (`docs/design/brushes.md`, decision 4): each
/// catches on one paper grain fixed to the layer, each reads as its own
/// medium, and a smudge drags what is already painted (decision 7).
@Suite("Dry media rendering")
struct DryMediaRenderingTests {

    // MARK: - Helpers

    private func alphas(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 3, to: data.count, by: 4).map { data[$0] }
    }

    private func stroke(_ medium: BrushMedium, from a: CGPoint, to b: CGPoint, size: Double = 24,
                        seed: UInt32 = 3, set: [String: Double] = [:],
                        mode: BrushMode = .paint) -> BrushStroke {
        var settings = BrushSettings(medium: medium, values: ["size": size].merging(set) { $1 })
        settings.mode = mode
        // A few samples so the curve has somewhere to go.
        let samples = (0...8).map { i -> StrokeSample in
            let t = CGFloat(i) / 8
            return StrokeSample(point: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t),
                                ms: Double(i) * 16)
        }
        return BrushStroke(samples: samples, settings: settings, colorHex: "#202020", seed: seed)
    }

    private let box = CGSize(width: 300, height: 120)

    private func render(_ strokes: [BrushStroke], scale: CGFloat = 1) throws -> CGImage {
        try #require(PaintRasterizer.rasterize(PaintContent(strokes: strokes), size: box, scale: scale))
    }

    private func gaps(_ medium: BrushMedium, set: [String: Double] = [:]) throws -> Double {
        let line = (CGPoint(x: 40, y: 60), CGPoint(x: 260, y: 60))
        let image = try render([stroke(medium, from: line.0, to: line.1, set: set)])
        return PaintMeasures.interiorGapFraction(image, from: line.0, to: line.1, diameter: 24, scale: 1)
    }

    // MARK: - The paper

    @Test("The paper grain is the same every time, spans light to dark, and repeats seamlessly")
    func grainIsStableAndTiles() {
        var values: [Float] = []
        for y in stride(from: 0.0, to: 64, by: 0.7) {
            for x in stride(from: 0.0, to: 64, by: 0.7) {
                let h = PaperGrain.height(x: x, y: y)
                #expect(h >= 0 && h <= 1)
                #expect(h == PaperGrain.height(x: x, y: y))
                #expect(abs(h - PaperGrain.height(x: x + PaperGrain.period, y: y + PaperGrain.period)) < 1e-5)
                values.append(h)
            }
        }
        let mean = values.reduce(0, +) / Float(values.count)
        let spread = (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(values.count)).squareRoot()
        #expect(abs(mean - 0.5) < 0.08, "evened out: as much high tooth as low")
        #expect(spread > 0.2)
    }

    @Test("Chalk's grain is coarser than charcoal's: neighbouring points agree more")
    func coarseGrain() {
        func agreement(_ coarseness: Double) -> Double {
            var total = 0.0
            var count = 0
            for y in stride(from: 0.0, to: 60, by: 1.3) {
                for x in stride(from: 0.0, to: 60, by: 1.3) {
                    total += Double(abs(PaperGrain.height(x: x, y: y, coarseness: coarseness)
                                        - PaperGrain.height(x: x + 1, y: y, coarseness: coarseness)))
                    count += 1
                }
            }
            return total / Double(count)
        }
        #expect(agreement(2) < agreement(1) * 0.8)
    }

    @Test("Two strokes over the same spot catch the same tooth")
    func sameTooth() throws {
        // Different seeds and slightly different paths, the same paper.
        let one = try render([stroke(.charcoal, from: CGPoint(x: 40, y: 60), to: CGPoint(x: 260, y: 60), seed: 1)])
        let two = try render([stroke(.charcoal, from: CGPoint(x: 30, y: 61), to: CGPoint(x: 270, y: 59), seed: 99)])
        let a = alphas(one), b = alphas(two)
        // Compare the stroke's core, where both cover.
        var xs: [Double] = [], ys: [Double] = []
        for y in 55...65 { for x in 80...220 { xs.append(Double(a[y * 300 + x])); ys.append(Double(b[y * 300 + x])) } }
        #expect(correlation(xs, ys) > 0.6)
    }

    @Test("The grain is laid in points, so a sharper render shows the same tooth", arguments: [
        (BrushMedium.charcoal, 1), (.crayon, 1), (.chalk, 2),
    ] as [(BrushMedium, Int)])
    func grainInPoints(_ medium: BrushMedium, _ low: Int) throws {
        // Chalk's grit is finer than a point, so a 1x render can only alias
        // it: chalk is read at 2x against 4x.
        let s = stroke(medium, from: CGPoint(x: 40, y: 60), to: CGPoint(x: 260, y: 60))
        let one = alphas(try render([s], scale: CGFloat(low)))
        let two = alphas(try render([s], scale: CGFloat(low * 2)))
        let w = 300 * low
        var xs: [Double] = [], ys: [Double] = []
        for y in (52 * low)...(68 * low) {
            for x in (80 * low)...(220 * low) {
                xs.append(Double(one[y * w + x]))
                // The four sharper pixels that make up the same point.
                let o = (y * 2) * (w * 2) + x * 2
                ys.append((Double(two[o]) + Double(two[o + 1]) + Double(two[o + w * 2])
                           + Double(two[o + w * 2 + 1])) / 4)
            }
        }
        #expect(correlation(xs, ys) > 0.6, "\(medium)")
    }

    // MARK: - The measured bar

    @Test("Measured bar: grain leaves gaps inside each dry stroke where the round tip leaves none")
    func interiorGapsBar() throws {
        // The round soft tip from the foundation slice (still the marker's).
        let round = try gaps(.marker)
        #expect(round < 0.02, "round tip: \(round)")
        for medium in [BrushMedium.charcoal, .chalk, .crayon] {
            let g = try gaps(medium)
            #expect(g >= PaintMeasures.dryMediaGapBar, "\(medium): \(g)")
        }
    }

    @Test("Grain changes how broken the stroke is")
    func grainSetting() throws {
        for medium in [BrushMedium.charcoal, .chalk, .crayon] {
            let none = try gaps(medium, set: ["grain": 0])
            let full = try gaps(medium, set: ["grain": 100])
            #expect(none < 0.03, "\(medium) at no grain: \(none)")
            #expect(full > none + 0.15, "\(medium): \(none) -> \(full)")
        }
    }

    // MARK: - Three media

    @Test("Charcoal fades out softly, crayon stops hard, chalk is an even film where it lands")
    func threeMedia() throws {
        let line = (CGPoint(x: 40, y: 60), CGPoint(x: 260, y: 60))
        func image(_ m: BrushMedium) throws -> CGImage { try render([stroke(m, from: line.0, to: line.1)]) }
        let charcoal = try image(.charcoal), chalk = try image(.chalk)
        // The tip's own fall-off, read with the paper out of the way: grain and
        // the stick's streaks would band the averaged profile.
        func tip(_ m: BrushMedium) throws -> CGImage {
            try render([stroke(m, from: line.0, to: line.1, set: ["grain": 0])])
        }
        let softCharcoal = PaintMeasures.edgeSoftness(try tip(.charcoal), from: line.0, to: line.1,
                                                      diameter: 24, scale: 1)
        let softCrayon = PaintMeasures.edgeSoftness(try tip(.crayon), from: line.0, to: line.1,
                                                    diameter: 24, scale: 1)
        #expect(softCharcoal > softCrayon * 1.6, "charcoal \(softCharcoal) vs crayon \(softCrayon)")
        // Where each lands in the core, how even it is: chalk's powder is a
        // film that is there or not, charcoal shades.
        func uneven(_ image: CGImage) -> Double {
            let a = alphas(image)
            var touched: [Double] = []
            for y in 56...64 { for x in 80...220 where a[y * 300 + x] > 12 { touched.append(Double(a[y * 300 + x])) } }
            let mean = touched.reduce(0, +) / Double(max(touched.count, 1))
            let variance = touched.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(touched.count, 1))
            return variance.squareRoot() / max(mean, 1)
        }
        let unevenCharcoal = uneven(charcoal), unevenChalk = uneven(chalk)
        #expect(unevenChalk < unevenCharcoal * 0.6, "chalk \(unevenChalk) vs charcoal \(unevenCharcoal)")
        // Charcoal leaves dust beyond its edge.
        let dust = alphas(charcoal)
        var beyond = 0
        for x in 80...220 {
            for y in [42, 43, 44, 45, 46, 74, 75, 76, 77, 78] where dust[y * 300 + x] > 8 { beyond += 1 }
        }
        #expect(beyond > 4, "dust specks beyond the edge: \(beyond)")
    }

    @Test("Chalk and crayon land crisp, where charcoal shades")
    func crispOrShaded() throws {
        let line = (CGPoint(x: 40, y: 60), CGPoint(x: 260, y: 60))
        func half(_ m: BrushMedium) throws -> Double {
            PaintMeasures.halfToneShare(try render([stroke(m, from: line.0, to: line.1)]), from: line.0,
                                        to: line.1, diameter: 24, scale: 1)
        }
        let charcoal = try half(.charcoal), chalk = try half(.chalk), crayon = try half(.crayon)
        // Powder and wax are there or not; the foundation slice's chalk left a
        // grey wash between its blotches (0.26).
        #expect(chalk < 0.12, "chalk \(chalk)")
        #expect(crayon < 0.12, "crayon \(crayon)")
        #expect(charcoal > chalk * 1.8, "charcoal \(charcoal) vs chalk \(chalk)")
    }

    @Test("Chalk's streaks run along the drag rather than sitting in round blotches")
    func chalkStreaks() throws {
        let line = (CGPoint(x: 40, y: 60), CGPoint(x: 260, y: 60))
        let chalk = try render([stroke(.chalk, from: line.0, to: line.1)])
        let agree = PaintMeasures.streakAgreement(chalk, from: line.0, to: line.1, diameter: 24, scale: 1,
                                                  offset: 2)
        // Blotches agree with themselves two points away either way (0.18
        // across in the foundation slice); streaks only along.
        #expect(agree.across < 0.08, "across \(agree.across)")
        #expect(agree.along > agree.across + 0.3, "along \(agree.along) across \(agree.across)")
    }

    @Test("A crayon's edge wavers with the hand, where a marker's runs ruler straight")
    func crayonWavers() throws {
        let line = (CGPoint(x: 40, y: 60), CGPoint(x: 260, y: 60))
        // Read with the paper out of the way, so the tooth does not count as
        // waver.
        func waver(_ m: BrushMedium) throws -> Double {
            PaintMeasures.widthWaver(try render([stroke(m, from: line.0, to: line.1, set: ["grain": 0])]),
                                     from: line.0, to: line.1, diameter: 24, scale: 1)
        }
        let crayon = try waver(.crayon), marker = try waver(.marker)
        #expect(crayon > 0.03, "crayon \(crayon)")
        #expect(marker < 0.01, "marker \(marker)")
    }

    @Test("A second crayon pass over the same spot leaves the paper's pits bare")
    func crayonBuildsLittle() throws {
        let a = CGPoint(x: 40, y: 60), b = CGPoint(x: 260, y: 60)
        let one = stroke(.crayon, from: a, to: b, seed: 1)
        let two = stroke(.crayon, from: a, to: b, seed: 2)
        let once = PaintMeasures.interiorGapFraction(try render([one]), from: a, to: b, diameter: 24, scale: 1)
        let twice = PaintMeasures.interiorGapFraction(try render([one, two]), from: a, to: b, diameter: 24,
                                                      scale: 1)
        // Wax settles on the same high tooth again: most of the bare pits
        // after one pass are still bare after two.
        #expect(twice > once * 0.5, "\(once) -> \(twice)")
        let round = stroke(.marker, from: a, to: b, seed: 1)
        #expect(PaintMeasures.interiorGapFraction(try render([round, round]), from: a, to: b, diameter: 24,
                                                  scale: 1) == 0)
    }

    // MARK: - Smudge

    @Test("Smudge drags charcoal along into bare paper, and smudging bare paper paints nothing")
    func smudgeMode() throws {
        let mark = stroke(.charcoal, from: CGPoint(x: 40, y: 60), to: CGPoint(x: 120, y: 60))
        let drag = stroke(.charcoal, from: CGPoint(x: 100, y: 60), to: CGPoint(x: 200, y: 60), seed: 5,
                          mode: .smudge)
        let before = alphas(try render([mark]))
        let after = alphas(try render([mark, drag]))
        // Past the end of the charcoal, along the smudge, there is now some.
        let past = (140...170).map { Int(after[60 * 300 + $0]) }
        #expect(past.allSatisfy { $0 > 0 }, "\(past)")
        #expect((140...170).allSatisfy { before[60 * 300 + $0] == 0 })
        // Off the smudge's path nothing changed.
        #expect(after[20 * 300 + 160] == 0)
        // On bare paper a smudge has nothing to drag.
        let lone = alphas(try render([drag]))
        #expect(lone.allSatisfy { $0 == 0 })
    }

    @Test("A smudge keeps the paper's tooth rather than smearing a smooth comet")
    func smudgeKeepsTooth() throws {
        let mark = stroke(.charcoal, from: CGPoint(x: 40, y: 60), to: CGPoint(x: 120, y: 60))
        let drag = stroke(.charcoal, from: CGPoint(x: 100, y: 60), to: CGPoint(x: 200, y: 60), seed: 5,
                          mode: .smudge)
        let smeared = try render([mark, drag], scale: 2)
        // Past the charcoal, where only the finger has been: 0.58 for the
        // foundation slice's blurred smear.
        let uneven = PaintMeasures.unevenness(smeared, in: CGRect(x: 140, y: 52, width: 40, height: 16), scale: 2)
        #expect(uneven > 0.7, "\(uneven)")
    }

    @Test("Charcoal's Smudge setting fills the tooth along the stroke")
    func smudgeSetting() throws {
        let none = try gaps(.charcoal, set: ["smudge": 0])
        let full = try gaps(.charcoal, set: ["smudge": 100])
        #expect(full < none * 0.8, "\(none) -> \(full)")
    }

    // MARK: - Live and landed

    @Test("The live stroke, marked a few dabs at a time, is the stroke that lands", arguments: [
        BrushMedium.pencil, .charcoal, .chalk, .crayon, .marker,
    ])
    func liveMatchesLanded(_ medium: BrushMedium) throws {
        let s = stroke(medium, from: CGPoint(x: 40, y: 50), to: CGPoint(x: 260, y: 70))
        let landed = alphas(try render([s], scale: 2))
        // The live overlay: the same stroke on a bitmap of its own, dab batches
        // as the pointer would hand them over, shown at the stroke's opacity.
        let width = 600, height = 240
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let marker = try #require(PaintRasterizer.LiveMarker(
            stroke: s, bitmap: context, pointsToPixels: CGAffineTransform(scaleX: 2, y: 2),
            clip: CGRect(x: 0, y: 0, width: width, height: height)))
        var walker = BrushPlacement.Walker(settings: s.settings, seed: s.seed,
                                           jitter: PaintRasterizer.jitter(for: medium))
        for sample in s.samples { marker.mark(walker.add(sample)) }
        marker.mark(walker.finish())
        let live = alphas(try #require(context.makeImage()))
        var differ = 0
        for i in live.indices where abs(Int(live[i]) - Int(landed[i])) > 12 { differ += 1 }
        #expect(Double(differ) / Double(live.count) < 0.002, "\(medium): \(differ) pixels differ")
    }

    private func correlation(_ a: [Double], _ b: [Double]) -> Double {
        let ma = a.reduce(0, +) / Double(a.count), mb = b.reduce(0, +) / Double(b.count)
        var num = 0.0, da = 0.0, db = 0.0
        for i in a.indices {
            num += (a[i] - ma) * (b[i] - mb)
            da += (a[i] - ma) * (a[i] - ma)
            db += (b[i] - mb) * (b[i] - mb)
        }
        return num / max((da * db).squareRoot(), 1e-9)
    }
}
