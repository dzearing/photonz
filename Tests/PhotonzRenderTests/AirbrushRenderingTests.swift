import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The airbrush as a spray (`docs/design/brushes.md`, "What the airbrush
/// settled"): a mist of fine droplets densest along the line that feathers
/// out with no edge, building up by time, harder with more pressure and
/// lighter on a fast pass, with Flow, Spread, Droplet Size and Build-up each
/// visibly changing it. The plain round tip (still the oil paint's until its
/// own slice) fails the measured bars.
@Suite("Airbrush rendering")
struct AirbrushRenderingTests {

    private let box = CGSize(width: 300, height: 160)
    private let scale: CGFloat = 2
    private let a = CGPoint(x: 30, y: 80), b = CGPoint(x: 270, y: 80)

    private func render(_ strokes: [BrushStroke]) throws -> CGImage {
        try #require(PaintRasterizer.rasterize(PaintContent(strokes: strokes), size: box, scale: scale))
    }

    /// A straight pass from `a` to `b` at `speed` points a millisecond.
    private func pass(speed: Double = 0.6, pressure: Double? = nil, from: CGPoint? = nil,
                      to: CGPoint? = nil) -> [StrokeSample] {
        let start = from ?? a, end = to ?? b
        let length = Double(hypot(end.x - start.x, end.y - start.y))
        let count = max(2, Int(length / max(speed * 8, 2)))
        let every = length / Double(count) / speed
        return (0...count).map { i in
            let f = CGFloat(i) / CGFloat(count)
            return StrokeSample(point: CGPoint(x: start.x + (end.x - start.x) * f, y: start.y + (end.y - start.y) * f),
                                pressure: pressure, ms: Double(i) * every)
        }
    }

    private func stroke(_ samples: [StrokeSample], medium: BrushMedium = .airbrush, size: Double = 40,
                        set: [String: Double] = [:], seed: UInt32 = 4) -> BrushStroke {
        BrushStroke(samples: samples,
                    settings: BrushSettings(medium: medium, values: ["size": size].merging(set) { $1 }),
                    colorHex: "#000000", seed: seed)
    }

    private func core(_ image: CGImage, at x: CGFloat = 150) -> Double {
        PaintMeasures.meanAlpha(image, around: CGPoint(x: x, y: 80), radius: 5, scale: scale)
    }

    // MARK: - The measured bars

    @Test("Measured bar: the spray feathers out from a dense middle; the round tip has a body and an edge")
    func featherBar() throws {
        let air = PaintMeasures.featherShare(try render([stroke(pass())]), from: a, to: b, diameter: 40, scale: scale)
        let round = PaintMeasures.featherShare(try render([stroke(pass(), medium: .oil)]), from: a, to: b, diameter: 40,
                                               scale: scale)
        #expect(air >= PaintMeasures.airbrushFeatherBar, "airbrush \(air)")
        #expect(round < PaintMeasures.airbrushFeatherBar, "round tip \(round)")
    }

    @Test("Measured bar: the spray's fringe is specked with droplets; the round tip's edge has none")
    func edgeDropletBar() throws {
        let air = PaintMeasures.edgeDroplets(try render([stroke(pass())]), from: a, to: b, diameter: 40, scale: scale)
        let round = PaintMeasures.edgeDroplets(try render([stroke(pass(), medium: .oil)]), from: a, to: b, diameter: 40,
                                               scale: scale)
        #expect(air >= PaintMeasures.airbrushEdgeDropletBar, "airbrush \(air)")
        #expect(round < PaintMeasures.airbrushEdgeDropletBar, "round tip \(round)")
    }

    /// A pass that stops for `ms` at its middle.
    private func pause(_ ms: Double, medium: BrushMedium = .airbrush, set: [String: Double] = [:]) -> BrushStroke {
        var samples = pass(to: CGPoint(x: 150, y: 80))
        let at = samples.last?.ms ?? 0
        if ms > 0 {
            samples += stride(from: 33.0, through: ms, by: 33).map {
                StrokeSample(point: CGPoint(x: 150, y: 80), ms: at + $0)
            }
        }
        let resume = samples.last?.ms ?? 0
        samples += pass(from: CGPoint(x: 150, y: 80)).dropFirst().map {
            StrokeSample(point: $0.point, ms: resume + $0.ms)
        }
        return stroke(samples, medium: medium, set: set)
    }

    @Test("Measured bar: the longer the spray is held, the darker the spot; the round tip does not change")
    func dwellCurve() throws {
        let holds = [0.0, 250, 500, 1000, 2000]
        let air = try holds.map { core(try render([pause($0)])) }
        for (earlier, later) in zip(air, air.dropFirst()) {
            #expect(later > earlier, "airbrush \(air)")
        }
        #expect(air[3] >= air[0] * PaintMeasures.airbrushBuildUpBar, "airbrush \(air)")
        let round = try holds.map { core(try render([pause($0, medium: .oil)])) }
        #expect((round.max() ?? 0) < (round.min() ?? 0) * 1.05, "round tip \(round)")
    }

    @Test("Measured bar: a slow pass is darker than a fast one; the round tip lays the same")
    func speedBar() throws {
        func ratio(_ medium: BrushMedium) throws -> Double {
            core(try render([stroke(pass(speed: 0.25, pressure: 0.6), medium: medium)]))
                / max(0.001, core(try render([stroke(pass(speed: 3, pressure: 0.6), medium: medium)])))
        }
        let air = try ratio(.airbrush), round = try ratio(.oil)
        #expect(air >= PaintMeasures.airbrushSlowOverFastBar, "airbrush \(air)")
        #expect(round < 1.1, "round tip \(round)")
    }

    // MARK: - Pressure and the settings

    @Test("Pressing harder sprays more")
    func pressureSpraysMore() throws {
        let light = core(try render([stroke(pass(pressure: 0.2))]))
        let hard = core(try render([stroke(pass(pressure: 1))]))
        #expect(hard > light * 2, "light \(light), hard \(hard)")
    }

    @Test("Flow sets how hard it sprays")
    func flow() throws {
        let low = core(try render([stroke(pass(), set: ["flow": 10])]))
        let high = core(try render([stroke(pass(), set: ["flow": 90])]))
        #expect(high > low * 2.5, "flow 10 \(low), flow 90 \(high)")
        #expect(high < 0.98, "a single pass at high flow still has room to build: \(high)")
    }

    @Test("Spread sets how wide the mist reaches, feathered either way")
    func spread() throws {
        func read(_ spread: Double) throws -> (width: Double, feather: Double) {
            let image = try render([stroke(pass(), set: ["spread": spread, "flow": 60])])
            return (PaintMeasures.lineProfile(image, from: a, to: b, reach: 30, scale: scale).width,
                    PaintMeasures.featherShare(image, from: a, to: b, diameter: 40, scale: scale))
        }
        let narrow = try read(0), wide = try read(100)
        #expect(wide.width > narrow.width * 1.6, "spread 0 \(narrow), spread 100 \(wide)")
        #expect(narrow.feather >= PaintMeasures.airbrushFeatherBar && wide.feather >= PaintMeasures.airbrushFeatherBar,
                "spread 0 \(narrow), spread 100 \(wide)")
    }

    @Test("Droplet Size goes from many fine specks to fewer, coarser ones")
    func dropletSize() throws {
        func read(_ droplet: Double) throws -> (count: Double, size: Double) {
            let image = try render([stroke(pass(), set: ["droplet": droplet])])
            return (PaintMeasures.edgeDroplets(image, from: a, to: b, diameter: 40, scale: scale),
                    PaintMeasures.speckSize(image, from: a, to: b, diameter: 40, scale: scale))
        }
        let mist = try read(0), spatter = try read(100)
        #expect(mist.count > spatter.count * 1.5, "droplet 0 \(mist), droplet 100 \(spatter)")
        #expect(spatter.size > mist.size * 1.6, "droplet 0 \(mist), droplet 100 \(spatter)")
    }

    @Test("Build-up sets how fast a held spot darkens")
    func buildUp() throws {
        func held(_ buildUp: Double) throws -> Double {
            core(try render([pause(500, set: ["buildup": buildUp])]))
        }
        let none = try held(0), half = try held(50), full = try held(100)
        let passed = core(try render([pause(0)]))
        #expect(none < passed * 1.15, "build-up 0 held \(none), a pass \(passed)")
        #expect(half > none * 1.3 && full > half * 1.1, "0 \(none), 50 \(half), 100 \(full)")
    }

    @Test("At a heavy flow and a hard press it spatters past the mist; at a light flow it does not")
    func spatter() throws {
        func strong(_ flow: Double) throws -> Double {
            PaintMeasures.edgeDroplets(try render([stroke(pass(pressure: 1), set: ["flow": flow])]),
                                       from: a, to: b, diameter: 40, scale: scale, lift: 0.3)
        }
        let light = try strong(25), heavy = try strong(100)
        #expect(heavy > light * 3 && heavy > 0.02, "flow 25 \(light), flow 100 \(heavy)")
    }

    // MARK: - Live and landed

    @Test("The spray shown under the pointer is exactly the spray that lands")
    func liveMatchesLanded() throws {
        var samples = pass(speed: 1.2, pressure: 0.8)
        let end = samples.last?.ms ?? 0
        samples += (1...20).map { StrokeSample(point: b, pressure: 0.8, ms: end + Double($0) * 33) }
        let s = stroke(samples, set: ["flow": 90, "droplet": 70, "buildup": 80])
        let landed = try render([s])
        let width = Int(box.width * scale), height = Int(box.height * scale)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let overlay = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let live = try #require(PaintRasterizer.LiveMarker(
            stroke: s, bitmap: overlay, pointsToPixels: CGAffineTransform(scaleX: scale, y: scale),
            clip: CGRect(x: 0, y: 0, width: width, height: height)))
        var walker = BrushPlacement.Walker(settings: s.settings, seed: s.seed)
        for sample in s.samples { live.mark(walker.add(sample)) }
        live.mark(walker.finish())
        let seen = try #require(overlay.makeImage())
        func alphas(_ image: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: width * height * 4)
            let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return stride(from: 3, to: data.count, by: 4).map { data[$0] }
        }
        let shown = alphas(seen), lands = alphas(landed)
        var differ = 0
        for i in shown.indices where abs(Int(shown[i]) - Int(lands[i])) > 2 { differ += 1 }
        #expect(differ == 0, "\(differ) pixels differ")
    }
}
