import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The marker and the airbrush (`docs/design/brushes.md`, decision 4). A
/// marker stroke is one flat translucent colour that darkens only where a
/// separate stroke crosses it, from a round or a chisel nib; the airbrush is a
/// fine soft spray that builds up the longer it is held over one spot. The
/// plain round tip (still the oil paint's until its own slice) fails both
/// measured bars.
@Suite("Marker and airbrush rendering")
struct MarkerAirbrushRenderingTests {

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

    /// The red channel at a point, 0...255, read top-left in points.
    private func red(_ image: CGImage, _ p: CGPoint) -> Int {
        let data = rgba(image)
        let x = Int(p.x * scale), y = Int(p.y * scale)
        return Int(data[(y * image.width + x) * 4])
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
                        set: [String: Double] = [:], hex: String = "#2060E0", seed: UInt32 = 4) -> BrushStroke {
        BrushStroke(samples: samples,
                    settings: BrushSettings(medium: medium, values: ["size": size].merging(set) { $1 }),
                    colorHex: hex, seed: seed)
    }

    /// Goes right, turns, and comes back over itself a third of a tip lower:
    /// the stroke covers much of its own path twice.
    private func doubledBack(_ medium: BrushMedium, size: Double = 20, set: [String: Double] = [:]) -> BrushStroke {
        stroke(medium, line([CGPoint(x: 30, y: 70), CGPoint(x: 260, y: 70), CGPoint(x: 265, y: 77),
                             CGPoint(x: 30, y: 77)]), size: size, set: set)
    }

    // MARK: - Marker: the measured bar

    @Test("Measured bar: a marker stroke that doubles back is one even colour; the round tip is not")
    func flatnessBar() throws {
        let marker = PaintMeasures.flatShare(try render([doubledBack(.marker)]))
        #expect(marker >= PaintMeasures.markerFlatBar, "marker \(marker)")
        let round = PaintMeasures.flatShare(try render([doubledBack(.oil)]))
        #expect(round < PaintMeasures.markerFlatBar, "round tip \(round)")
        // Along its length: where it covers its path twice it is no darker
        // than where it covers it once.
        let image = try render([doubledBack(.marker)], over: true)
        let twice = red(image, CGPoint(x: 150, y: 73)), once = red(image, CGPoint(x: 150, y: 64))
        #expect(abs(twice - once) <= 3, "covered twice \(twice), once \(once)")
    }

    @Test("A second marker stroke crossing the first is darker in the overlap")
    func crossingDarkens() throws {
        let across = stroke(.marker, line([CGPoint(x: 30, y: 80), CGPoint(x: 270, y: 80)]), size: 20)
        let down = stroke(.marker, line([CGPoint(x: 150, y: 20), CGPoint(x: 150, y: 140)]), size: 20, seed: 5)
        let image = try render([across, down], over: true)
        let overlap = red(image, CGPoint(x: 150, y: 80))
        let one = red(image, CGPoint(x: 80, y: 80)), other = red(image, CGPoint(x: 150, y: 40))
        #expect(overlap < one - 25 && overlap < other - 25, "overlap \(overlap), strokes \(one) and \(other)")
        // A marker is translucent: one stroke on white is not the full colour.
        #expect(one > 0x20 + 30, "one stroke \(one)")
    }

    @Test("Flow sets how much ink a marker stroke lays")
    func markerFlow() throws {
        let light = stroke(.marker, line([CGPoint(x: 30, y: 80), CGPoint(x: 270, y: 80)]), size: 20,
                           set: ["flow": 15])
        let heavy = stroke(.marker, line([CGPoint(x: 30, y: 80), CGPoint(x: 270, y: 80)]), size: 20,
                           set: ["flow": 95])
        let a = red(try render([light], over: true), CGPoint(x: 150, y: 80))
        let b = red(try render([heavy], over: true), CGPoint(x: 150, y: 80))
        #expect(a > b + 60, "flow 15 \(a), flow 95 \(b)")
    }

    // MARK: - Marker: the tip

    /// The width of a straight stroke, in points, read across its middle.
    private func width(_ s: BrushStroke, vertical: Bool) throws -> Double {
        let data = rgba(try render([s]))
        let w = Int(box.width * scale)
        var covered = 0
        if vertical {
            let y = Int(80 * scale)
            for x in 0..<w where data[(y * w + x) * 4 + 3] > 127 { covered += 1 }
        } else {
            let x = Int(150 * scale)
            for y in 0..<Int(box.height * scale) where data[(y * w + x) * 4 + 3] > 127 { covered += 1 }
        }
        return Double(covered) / Double(scale)
    }

    @Test("A chisel stroke changes width with direction; a round one does not")
    func chiselWidth() throws {
        let level = line([CGPoint(x: 30, y: 80), CGPoint(x: 270, y: 80)])
        let upright = line([CGPoint(x: 150, y: 10), CGPoint(x: 150, y: 150)])
        let diagonal = line([CGPoint(x: 90, y: 140), CGPoint(x: 210, y: 20)])
        let roundLevel = try width(stroke(.marker, level, size: 24), vertical: false)
        let roundUpright = try width(stroke(.marker, upright, size: 24), vertical: true)
        #expect(abs(roundLevel - roundUpright) < 1.5, "\(roundLevel) vs \(roundUpright)")
        #expect(abs(roundLevel - 24) < 2, "\(roundLevel)")
        // The nib is held at an angle, so a stroke along it is a thin line and
        // a stroke across it the nib's full width.
        let chisel: [String: Double] = ["tip": 1]
        let alongNib = try width(stroke(.marker, diagonal, size: 24, set: chisel), vertical: true)
        let acrossNib = try width(stroke(.marker, line([CGPoint(x: 90, y: 20), CGPoint(x: 210, y: 140)]),
                                         size: 24, set: chisel), vertical: true)
        #expect(acrossNib > alongNib * 2, "across the nib \(acrossNib), along it \(alongNib)")
        let chiselLevel = try width(stroke(.marker, level, size: 24, set: chisel), vertical: false)
        #expect(chiselLevel < roundLevel, "a level chisel stroke \(chiselLevel), round \(roundLevel)")
    }

    // MARK: - Airbrush: the measured bar

    /// A pass along the middle that stops for a second half way.
    private func passWithPause(_ medium: BrushMedium, set: [String: Double] = [:]) -> BrushStroke {
        var samples = line([CGPoint(x: 30, y: 80), CGPoint(x: 150, y: 80)])
        let at = samples.last?.ms ?? 0
        samples += (1...30).map { StrokeSample(point: CGPoint(x: 150, y: 80), ms: at + Double($0) * 33) }
        let resume = samples.last?.ms ?? 0
        samples += line([CGPoint(x: 150, y: 80), CGPoint(x: 270, y: 80)]).dropFirst()
            .map { StrokeSample(point: $0.point, ms: resume + $0.ms) }
        return stroke(medium, samples, size: 40, set: set, hex: "#000000")
    }

    @Test("Measured bar: an airbrush held still builds up; the round tip does not")
    func buildUpBar() throws {
        func ratio(_ medium: BrushMedium) throws -> Double {
            let image = try render([passWithPause(medium)])
            let held = PaintMeasures.meanAlpha(image, around: CGPoint(x: 150, y: 80), radius: 6, scale: scale)
            let passed = PaintMeasures.meanAlpha(image, around: CGPoint(x: 80, y: 80), radius: 6, scale: scale)
            return held / max(passed, 0.001)
        }
        let air = try ratio(.airbrush), round = try ratio(.oil)
        #expect(air >= PaintMeasures.airbrushBuildUpBar, "airbrush \(air)")
        #expect(round < PaintMeasures.airbrushBuildUpBar, "round tip \(round)")
    }

    @Test("The spray is fine grain, not a smooth blur, and the round tip is smooth")
    func fineSpray() throws {
        let a = CGPoint(x: 30, y: 80), b = CGPoint(x: 270, y: 80)
        let air = PaintMeasures.fringeGrain(try render([stroke(.airbrush, line([a, b]), size: 40, hex: "#000000")]),
                                            from: a, to: b, diameter: 40, scale: scale)
        let round = PaintMeasures.fringeGrain(try render([stroke(.oil, line([a, b]), size: 40, set: ["opacity": 40],
                                                                 hex: "#000000")]),
                                              from: a, to: b, diameter: 40, scale: scale)
        #expect(air > round * 3 && air > 0.01, "airbrush \(air), round \(round)")
    }

    // MARK: - Live and landed

    @Test("A marker stroke laid live over earlier paint shows what lands, overlap included")
    func markerLiveOverEarlierPaint() throws {
        let first = stroke(.marker, line([CGPoint(x: 150, y: 20), CGPoint(x: 150, y: 140)]), size: 20, seed: 1)
        let second = stroke(.marker, line([CGPoint(x: 30, y: 80), CGPoint(x: 270, y: 80)]), size: 20, seed: 2)
        let landed = rgba(try render([first, second]))
        // The canvas: the earlier paint as it stands, and the live overlay over it.
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
            clip: CGRect(x: 0, y: 0, width: width, height: height), working: working))
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
