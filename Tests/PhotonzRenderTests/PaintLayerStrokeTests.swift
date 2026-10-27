import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The stroke under the hand is painted onto its layer's own kept raster, at
/// the scale the canvas shows that layer, with the code that lands it
/// (`docs/design/brushes.md`, decision 5). The user, 2026-10-25: "when I draw,
/// it seems like all of the previous strokes are recomputed because they
/// change and then swap into this higher resolution". So what the hand sees is
/// what lands, pixel for pixel, and nothing already painted is simulated again
/// to show it.
@Suite("A live stroke on its layer")
struct PaintLayerStrokeTests {

    private let box = CGSize(width: 240, height: 140)
    private let scale: CGFloat = 2

    /// A pen's samples carry their press, so nothing about the stroke's end
    /// is decided only once it lands (`BrushPlacement.taperedOut`).
    private func line(from a: CGPoint, to b: CGPoint, pen: Bool, startingAt t0: Double = 0) -> [StrokeSample] {
        let steps = max(2, Int(hypot(b.x - a.x, b.y - a.y) / 10))
        return (0...steps).map { i in
            let f = CGFloat(i) / CGFloat(steps)
            return StrokeSample(point: CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f),
                                pressure: pen ? 0.8 : nil, ms: t0 + Double(i) * 16)
        }
    }

    private func stroke(_ medium: BrushMedium, _ a: CGPoint, _ b: CGPoint, size: Double = 24,
                        mode: BrushMode = .paint, hex: String = "#2060E0", seed: UInt32,
                        at time: Double, pen: Bool = false) -> BrushStroke {
        var settings = BrushSettings(medium: medium, values: ["size": size])
        settings.mode = mode
        return BrushStroke(samples: line(from: a, to: b, pen: pen), settings: settings, colorHex: hex,
                           seed: seed, startedAt: time)
    }

    /// Washes laid a second apart, so each blooms into the one before it while
    /// it is still wet; oil dragged through them; charcoal over the lot.
    private var earlier: [BrushStroke] {
        [
            stroke(.watercolour, CGPoint(x: 20, y: 40), CGPoint(x: 220, y: 50), size: 40, seed: 1, at: 100),
            stroke(.watercolour, CGPoint(x: 120, y: 10), CGPoint(x: 125, y: 130), size: 30,
                   hex: "#D03030", seed: 2, at: 101),
            stroke(.oil, CGPoint(x: 30, y: 100), CGPoint(x: 210, y: 90), seed: 3, at: 102),
            stroke(.charcoal, CGPoint(x: 40, y: 20), CGPoint(x: 60, y: 120), size: 12, hex: "#202020",
                   seed: 4, at: 103),
        ]
    }

    /// The new stroke in each medium, laid across the earlier ones while the
    /// last wash is still wet.
    private func next(_ medium: BrushMedium, mode: BrushMode = .paint, pen: Bool = true) -> BrushStroke {
        stroke(medium, CGPoint(x: 30, y: 75), CGPoint(x: 205, y: 60), size: 22, mode: mode, hex: "#30A040",
               seed: 9, at: 103.5, pen: pen)
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// The live stroke driven the way the canvas drives it: the walker's dabs
    /// as each sample arrives, then the release.
    private func painted(_ new: BrushStroke, on base: PaintLayerBase?) throws -> PaintLayerStroke {
        let live = try #require(PaintLayerStroke(stroke: new, base: base, size: box, scale: scale))
        var walker = BrushPlacement.Walker(settings: new.settings, seed: new.seed,
                                           jitter: PaintRasterizer.jitter(for: new.settings.medium))
        for sample in new.samples { live.mark(walker.add(sample)) }
        live.mark(walker.finish())
        live.finish()
        return live
    }

    /// What the canvas shows while the button is down: the layer as it stood,
    /// with the live stroke's overlay over it, at full strength or at the
    /// stroke's opacity.
    private func shown(_ live: PaintLayerStroke, over base: PaintLayerBase?) throws -> [UInt8] {
        let width = live.width, height = live.height
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let all = CGRect(x: 0, y: 0, width: width, height: height)
        if let base { context.draw(base.image, in: all) }
        context.setAlpha(live.showsAtFullStrength ? 1 : live.opacity)
        context.draw(try #require(live.picture(of: all)), in: all)
        return bytes(try #require(context.makeImage()))
    }

    private func share(_ a: [UInt8], _ b: [UInt8], over levels: Int) -> Double {
        var differ = 0
        for i in a.indices where abs(Int(a[i]) - Int(b[i])) > levels { differ += 1 }
        return Double(differ) / Double(max(a.count, 1))
    }

    @Test(arguments: [BrushMedium.pencil, .charcoal, .chalk, .crayon, .marker, .airbrush, .watercolour, .oil])
    func whatTheHandSeesIsWhatLands(_ medium: BrushMedium) throws {
        let cache = PaintRasterCache(budgetBytes: 64 << 20)
        let content = PaintContent(strokes: earlier)
        let base = try #require(cache.base(content, size: box, scale: scale))
        let new = next(medium)
        let live = try painted(new, on: base)
        let landed = bytes(try #require(cache.raster(PaintContent(strokes: earlier + [new]), size: box,
                                                     scale: scale)))
        // A level or two where a stroke laid over the paint is rounded once
        // rather than twice; nothing a person can see.
        #expect(share(try shown(live, over: base), landed, over: 3) < 0.0005, "\(medium)")
    }

    @Test func aSmudgeShowsThePaintItDrags() throws {
        let cache = PaintRasterCache(budgetBytes: 64 << 20)
        let content = PaintContent(strokes: earlier)
        let base = try #require(cache.base(content, size: box, scale: scale))
        let new = next(.oil, mode: .smudge)
        let live = try painted(new, on: base)
        #expect(live.showsAtFullStrength)
        let landed = bytes(try #require(cache.raster(PaintContent(strokes: earlier + [new]), size: box,
                                                     scale: scale)))
        // Smudged paint is opaque where it was: laid over the paint it came
        // from, it reads as what lands.
        #expect(share(try shown(live, over: base), landed, over: 6) < 0.01)
    }

    @Test func aFirstStrokeOnFreshPaperLandsAsShown() throws {
        let cache = PaintRasterCache(budgetBytes: 64 << 20)
        for medium in [BrushMedium.watercolour, .oil, .marker] {
            let new = next(medium)
            let live = try painted(new, on: nil)
            let landed = bytes(try #require(cache.raster(PaintContent(strokes: [new]), size: box, scale: scale)))
            #expect(share(try shown(live, over: nil), landed, over: 3) < 0.0005, "\(medium)")
        }
    }

    @Test func paintingOnAKeptLayerSimulatesNoEarlierStroke() throws {
        let cache = PaintRasterCache(budgetBytes: 64 << 20)
        let content = PaintContent(strokes: earlier)
        _ = cache.raster(content, size: box, scale: scale)
        let before = cache.strokesSimulated
        let base = try #require(cache.base(content, size: box, scale: scale))
        #expect(cache.strokesSimulated == before, "the raster the render kept is the one the press reads")
        #expect(base.strokeCount == earlier.count)
        // The wet washes come with it: the live wash blooms into them without
        // replaying a single earlier stroke for its water.
        _ = try painted(next(.watercolour), on: base)
        #expect(cache.strokesSimulated == before)
    }

    @Test func aBaseNotYetDrawnIsDrawnOnceAndKept() throws {
        let cache = PaintRasterCache(budgetBytes: 64 << 20)
        let content = PaintContent(strokes: earlier)
        _ = try #require(cache.base(content, size: box, scale: scale))
        #expect(cache.strokesSimulated == earlier.count)
        let before = cache.strokesSimulated
        let raster = try #require(cache.raster(content, size: box, scale: scale))
        #expect(cache.strokesSimulated == before)
        #expect(raster.width == Int(box.width * scale))
    }

    @Test func theOverlayIsHandedOutAPieceAtATime() throws {
        let live = try painted(next(.marker), on: nil)
        let piece = try #require(live.picture(of: CGRect(x: 40, y: 100, width: 64, height: 32)))
        #expect(piece.width == 64 && piece.height == 32)
        let whole = bytes(try #require(live.picture(of: CGRect(x: 0, y: 0, width: live.width, height: live.height))))
        let part = bytes(piece)
        // Row 0 of the piece is row 100 of the whole, top-left first.
        for x in 0..<64 {
            let a = (100 * live.width + 40 + x) * 4, b = x * 4
            #expect(Array(whole[a..<a + 4]) == Array(part[b..<b + 4]))
        }
        // A piece reaching past the layer is cut to it.
        let edge = try #require(live.picture(of: CGRect(x: live.width - 10, y: 0, width: 64, height: 8)))
        #expect(edge.width == 10)
        // Padded, it is the whole rect, clear past the layer's edge.
        let padded = try #require(live.picture(of: CGRect(x: -2, y: 100, width: 8, height: 4), padded: true))
        #expect(padded.width == 8 && padded.height == 4)
        let pad = bytes(padded)
        #expect(pad[3] == 0 && pad[7] == 0, "the two columns past the left edge are clear")
        #expect(Array(pad[8..<12]) == Array(whole[(100 * live.width) * 4..<(100 * live.width) * 4 + 4]))
    }

    @Test func eachMarkSaysWhichPixelsItChanged() throws {
        let new = next(.watercolour)
        let live = try #require(PaintLayerStroke(stroke: new, base: nil, size: box, scale: scale))
        var walker = BrushPlacement.Walker(settings: new.settings, seed: new.seed)
        var touched = CGRect.null
        for sample in new.samples { touched = touched.union(live.mark(walker.add(sample))) }
        touched = touched.union(live.mark(walker.finish()))
        touched = touched.union(live.finish())
        let all = CGRect(x: 0, y: 0, width: live.width, height: live.height)
        let overlay = bytes(try #require(live.picture(of: all)))
        // Every pixel the overlay holds lies inside what the marks said.
        for y in 0..<live.height {
            for x in 0..<live.width where overlay[(y * live.width + x) * 4 + 3] > 0 {
                #expect(touched.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)))
                if !touched.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) { return }
            }
        }
    }
}

/// A mouse stroke lands thinned out over its last stretch
/// (`BrushPlacement.taperedOut`). Before 2026-10-27 the live stroke could not
/// know where it ended, so the end drew in only as it landed: 0.13% of the
/// canvas changed on the release. Now the last stretch is drawn as if the
/// stroke ended where the pointer is and taken back on the next move.
@Suite("A live mouse stroke thins its end as it goes")
struct LiveTaperTests {
    private let box = CGSize(width: 240, height: 140)
    private let scale: CGFloat = 2

    private func mouseStroke(_ medium: BrushMedium, seed: UInt32 = 9) -> BrushStroke {
        var settings = BrushSettings(medium: medium, values: ["size": 22])
        settings.mode = .paint
        let samples = (0...24).map { i in
            StrokeSample(point: CGPoint(x: 30 + CGFloat(i) * 7, y: 75 - CGFloat(i) * 0.6), ms: Double(i) * 16)
        }
        return BrushStroke(samples: samples, settings: settings, colorHex: "#30A040", seed: seed, startedAt: 103.5)
    }

    private func earlier() -> [BrushStroke] {
        var settings = BrushSettings(medium: .watercolour, values: ["size": 40])
        settings.mode = .paint
        let samples = (0...20).map { i in
            StrokeSample(point: CGPoint(x: 20 + CGFloat(i) * 10, y: 40 + CGFloat(i) * 0.5), ms: Double(i) * 16)
        }
        return [BrushStroke(samples: samples, settings: settings, colorHex: "#2060E0", seed: 1, startedAt: 103)]
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// The overlay laid over the layer, as the canvas shows it.
    private func shown(_ live: PaintLayerStroke, over base: PaintLayerBase?) throws -> [UInt8] {
        let all = CGRect(x: 0, y: 0, width: live.width, height: live.height)
        let context = try #require(CGContext(data: nil, width: live.width, height: live.height,
                                             bitsPerComponent: 8, bytesPerRow: live.width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        if let base { context.draw(base.image, in: all) }
        context.setAlpha(live.showsAtFullStrength ? 1 : live.opacity)
        context.draw(try #require(live.picture(of: all)), in: all)
        return bytes(try #require(context.makeImage()))
    }

    private func share(_ a: [UInt8], _ b: [UInt8], over levels: Int) -> Double {
        var differ = 0
        for i in a.indices where abs(Int(a[i]) - Int(b[i])) > levels { differ += 1 }
        return Double(differ) / Double(max(a.count, 1))
    }

    @Test(arguments: [BrushMedium.pencil, .charcoal, .chalk, .crayon, .marker, .watercolour, .oil])
    func theEndIsThinnedBeforeTheRelease(_ medium: BrushMedium) throws {
        let cache = PaintRasterCache(budgetBytes: 64 << 20)
        let earlier = earlier()
        let base = try #require(cache.base(PaintContent(strokes: earlier), size: box, scale: scale))
        let new = mouseStroke(medium)
        // Live: no samples yet when it begins, as on the canvas.
        var begun = new
        begun.samples = []
        let live = try #require(PaintLayerStroke(stroke: begun, base: base, size: box, scale: scale))
        var walker = BrushPlacement.Walker(settings: new.settings, seed: new.seed,
                                           jitter: PaintRasterizer.jitter(for: new.settings.medium))
        for sample in new.samples { live.mark(walker.add(sample)) }
        live.mark(walker.finish())
        // The picture with the button still down, before `finish`.
        let held = try shown(live, over: base)
        live.finish()
        let released = try shown(live, over: base)
        let landed = bytes(try #require(cache.raster(PaintContent(strokes: earlier + [new]), size: box,
                                                     scale: scale)))
        #expect(share(held, landed, over: 3) < 0.0005, "\(medium): held against landed")
        #expect(held == released, "\(medium): nothing changes as the button comes up")
    }

    @Test func aStrokeThatCarriesOnFillsOutWhereItWasThinned() throws {
        // Half way, the end is thin; at the end, that stretch is full width
        // and only the new end is thin: the tail is taken back, not left.
        let new = mouseStroke(.marker)
        var begun = new
        begun.samples = []
        let live = try #require(PaintLayerStroke(stroke: begun, base: nil, size: box, scale: scale))
        var walker = BrushPlacement.Walker(settings: new.settings, seed: new.seed)
        let half = new.samples.count / 2
        for sample in new.samples[..<half] { live.mark(walker.add(sample)) }
        let all = CGRect(x: 0, y: 0, width: live.width, height: live.height)
        let midway = bytes(try #require(live.picture(of: all)))
        for sample in new.samples[half...] { live.mark(walker.add(sample)) }
        live.mark(walker.finish())
        live.finish()
        let done = bytes(try #require(live.picture(of: all)))
        // Where the half-way end was, the finished stroke is wider: more of
        // the column under it is painted.
        let x = Int((30 + CGFloat(half - 2) * 7) * scale)
        func painted(_ data: [UInt8]) -> Int {
            (0..<live.height).filter { data[($0 * live.width + x) * 4 + 3] > 40 }.count
        }
        #expect(painted(done) > painted(midway))
    }
}
