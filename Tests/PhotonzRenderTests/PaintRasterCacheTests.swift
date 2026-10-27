import CoreGraphics
import Foundation
import os
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A paint layer keeps its last raster (`docs/design/brushes.md`, decision 5).
/// On 2026-10-25 a smudge after a few watercolour strokes froze the app: every
/// press re-simulated every stroke on the layer to read the paint under it, and
/// every render after the release did it again. The cache paints only the
/// strokes added since the raster it kept, and what it hands back is the same
/// bitmap, byte for byte, as replaying the whole list.
@Suite("Paint raster cache")
struct PaintRasterCacheTests {

    private let box = CGSize(width: 240, height: 140)
    private let scale: CGFloat = 2

    private func line(from a: CGPoint, to b: CGPoint, startingAt t0: Double = 0) -> [StrokeSample] {
        let steps = max(2, Int(hypot(b.x - a.x, b.y - a.y) / 10))
        return (0...steps).map { i in
            let f = CGFloat(i) / CGFloat(steps)
            return StrokeSample(point: CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f),
                                ms: t0 + Double(i) * 16)
        }
    }

    private func stroke(_ medium: BrushMedium, _ a: CGPoint, _ b: CGPoint, size: Double = 24,
                        mode: BrushMode = .paint, hex: String = "#2060E0", seed: UInt32,
                        at time: Double) -> BrushStroke {
        var settings = BrushSettings(medium: medium, values: ["size": size])
        settings.mode = mode
        return BrushStroke(samples: line(from: a, to: b), settings: settings, colorHex: hex, seed: seed,
                           startedAt: time)
    }

    /// Washes laid a second apart, so each blooms into the one before it while
    /// it is still wet; oil dragged through them; a smudge across the lot.
    private var strokes: [BrushStroke] {
        [
            stroke(.watercolour, CGPoint(x: 20, y: 40), CGPoint(x: 220, y: 50), size: 40, seed: 1, at: 100),
            stroke(.watercolour, CGPoint(x: 120, y: 10), CGPoint(x: 125, y: 130), size: 30,
                   hex: "#D03030", seed: 2, at: 101),
            stroke(.oil, CGPoint(x: 30, y: 100), CGPoint(x: 210, y: 90), seed: 3, at: 102),
            stroke(.charcoal, CGPoint(x: 40, y: 20), CGPoint(x: 60, y: 120), size: 12, hex: "#202020",
                   seed: 4, at: 103),
            stroke(.watercolour, CGPoint(x: 60, y: 70), CGPoint(x: 200, y: 75), size: 26, hex: "#30A040",
                   seed: 5, at: 103.5),
            stroke(.oil, CGPoint(x: 20, y: 60), CGPoint(x: 220, y: 70), size: 20, mode: .smudge,
                   seed: 6, at: 104),
        ]
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

    /// Every stroke replayed from nothing, the way the layer was drawn before
    /// it kept anything.
    private func replayed(_ strokes: [BrushStroke]) throws -> [UInt8] {
        bytes(try #require(PaintRasterizer.replay(PaintContent(strokes: strokes), size: box, scale: scale)))
    }

    @Test func aStrokeAddedPaintsOnlyThatStrokeAndMatchesAFullReplay() throws {
        let cache = PaintRasterCache(budgetBytes: 64 << 20)
        let all = strokes
        for count in 1...all.count {
            let before = cache.strokesSimulated
            let image = try #require(cache.raster(PaintContent(strokes: Array(all.prefix(count))),
                                                  size: box, scale: scale))
            #expect(cache.strokesSimulated - before == 1, "stroke \(count) simulated only itself")
            #expect(bytes(image) == (try replayed(Array(all.prefix(count)))), "stroke \(count) matches a replay")
        }
    }

    @Test func theSameStrokesAskedAgainSimulateNothing() throws {
        let cache = PaintRasterCache(budgetBytes: 64 << 20)
        let content = PaintContent(strokes: strokes)
        let first = try #require(cache.raster(content, size: box, scale: scale))
        let before = cache.strokesSimulated
        let again = try #require(cache.raster(content, size: box, scale: scale))
        #expect(cache.strokesSimulated == before)
        #expect(again === first)
    }

    @Test func undoingAStrokeFindsTheShorterListStillKept() throws {
        let cache = PaintRasterCache(budgetBytes: 64 << 20)
        let all = strokes
        _ = cache.raster(PaintContent(strokes: Array(all.dropLast())), size: box, scale: scale)
        _ = cache.raster(PaintContent(strokes: all), size: box, scale: scale)
        let before = cache.strokesSimulated
        let undone = try #require(cache.raster(PaintContent(strokes: Array(all.dropLast())),
                                               size: box, scale: scale))
        #expect(cache.strokesSimulated == before)
        #expect(bytes(undone) == (try replayed(Array(all.dropLast()))))
    }

    @Test func aChangedEarlierStrokeReplaysFromThere() throws {
        // Recolouring the first stroke is not an addition: nothing kept is a
        // prefix of the new list, so it is replayed whole, and correctly.
        let cache = PaintRasterCache(budgetBytes: 64 << 20)
        var all = strokes
        _ = cache.raster(PaintContent(strokes: all), size: box, scale: scale)
        all[0].colorHex = "#E0A020"
        let before = cache.strokesSimulated
        let image = try #require(cache.raster(PaintContent(strokes: all), size: box, scale: scale))
        #expect(cache.strokesSimulated - before == all.count)
        #expect(bytes(image) == (try replayed(all)))
    }

    @Test func anotherScaleIsAnotherRaster() throws {
        let cache = PaintRasterCache(budgetBytes: 64 << 20)
        let content = PaintContent(strokes: Array(strokes.prefix(2)))
        _ = cache.raster(content, size: box, scale: 2)
        let before = cache.strokesSimulated
        let half = try #require(cache.raster(content, size: box, scale: 1))
        #expect(cache.strokesSimulated - before == 2)
        #expect(half.width == Int(box.width))
    }

    @Test func itKeepsWithinItsBudgetAndLetsGo() throws {
        // One raster here is 480 x 280 x 4 bytes, about 0.5 MB: a budget of
        // 1.2 MB holds two.
        let one = Int(box.width * scale) * Int(box.height * scale) * 4
        let cache = PaintRasterCache(budgetBytes: one * 2 + one / 2)
        let all = strokes
        for count in 1...4 { _ = cache.raster(PaintContent(strokes: Array(all.prefix(count))), size: box, scale: scale) }
        #expect(cache.keptBytes <= one * 2 + one / 2)
        #expect(cache.keptBytes > 0)
        cache.letGo()
        #expect(cache.keptBytes == 0)
        // Bigger than half the budget is never kept at all.
        let small = PaintRasterCache(budgetBytes: one)
        _ = small.raster(PaintContent(strokes: Array(all.prefix(1))), size: box, scale: scale)
        #expect(small.keptBytes == 0)
    }

    @Test func requestsArrivingTogetherSimulateTheStrokesOnce() throws {
        // Two tiles of one render ask for the same layer at once: the second
        // waits for the first rather than doing it all again.
        let cache = PaintRasterCache(budgetBytes: 64 << 20)
        let content = PaintContent(strokes: strokes)
        let size = box, scale = scale
        DispatchQueue.concurrentPerform(iterations: 4) { _ in
            _ = cache.raster(content, size: size, scale: scale)
        }
        #expect(cache.strokesSimulated == strokes.count)
    }

    @Test func twoLayersOfOneSizeAskedForTogetherEachComeBackAsTheirOwn() throws {
        // Two paint layers the same size, rendered at once: neither waits on
        // the other's strokes, and neither is handed the other's raster.
        let cache = PaintRasterCache(budgetBytes: 64 << 20)
        let first = Array(strokes.prefix(3)), second = Array(strokes.suffix(3))
        let contents = [PaintContent(strokes: first), PaintContent(strokes: second)]
        let size = box, scale = scale
        let images = OSAllocatedUnfairLock(initialState: [Int: [UInt8]]())
        DispatchQueue.concurrentPerform(iterations: 8) { i in
            guard let image = cache.raster(contents[i % 2], size: size, scale: scale) else { return }
            let data = bytes(image)
            images.withLock { $0[i % 2] = data }
        }
        let got = images.withLock { $0 }
        #expect(got[0] == (try replayed(first)))
        #expect(got[1] == (try replayed(second)))
        #expect(cache.strokesSimulated == first.count + second.count)
    }

    @Test func thePlainRoundYardstickIsNeverServedFromTheCache() throws {
        let content = PaintContent(strokes: Array(strokes.prefix(1)))
        let medium = try #require(PaintRasterizer.rasterize(content, size: box, scale: scale))
        let plain = try #require(PaintRasterizer.$plainRound.withValue(true) {
            PaintRasterizer.rasterize(content, size: box, scale: scale)
        })
        #expect(bytes(plain) != bytes(medium))
    }
}

/// Letting go of a stroke on a 12 megapixel picture whose paint layer already
/// holds a few hundred strokes, and undoing it. Measured in the app on
/// 2026-10-27 with 300 strokes on a 4000 by 3000 layer: the landing held the
/// main thread at most 24 ms and the undo 9.6 ms, against 344 to 432 ms a
/// landing when the whole layer was replayed (2026-10-25). The suite runs
/// unoptimised, where one stroke's simulation alone takes several times that,
/// so what it holds is the shape: a landing simulates the new stroke and
/// nothing else, costs no more with 300 strokes under it than with one, and an
/// undo simulates nothing and hands back the raster kept for it.
@Suite("Landing and undo on a big layer")
struct PaintLandingCostTests {
    private let size = CGSize(width: 4000, height: 3000)

    private func dot(_ i: Int) -> BrushStroke {
        let x = CGFloat(40 + (i * 137) % 3900), y = CGFloat(40 + (i * 89) % 2900)
        return BrushStroke(samples: [StrokeSample(point: CGPoint(x: x, y: y), ms: 0),
                                     StrokeSample(point: CGPoint(x: x + 6, y: y + 2), ms: 16)],
                           settings: BrushSettings(medium: .marker, values: ["size": 4]), colorHex: "#203040",
                           seed: UInt32(i + 1), startedAt: Double(i))
    }

    private var landing: BrushStroke {
        // A marker: cheap to simulate unoptimised, so what is timed is what the
        // layer adds around it, not the stroke.
        let samples = (0...12).map { StrokeSample(point: CGPoint(x: 800 + CGFloat($0) * 50, y: 1500), ms: Double($0) * 16) }
        return BrushStroke(samples: samples, settings: BrushSettings(medium: .marker, values: ["size": 60]),
                           colorHex: "#2060E0", seed: 99, startedAt: 10_000)
    }

    private func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    @Test func landingOnThreeHundredStrokesCostsWhatLandingOnOneDoes() throws {
        let clock = ContinuousClock()
        let many = (0..<300).map(dot)
        let crowded = PaintRasterCache(budgetBytes: 256 << 20)
        let kept = try #require(crowded.raster(PaintContent(strokes: many), size: size, scale: 1))
        let lone = PaintRasterCache(budgetBytes: 256 << 20)
        _ = try #require(lone.raster(PaintContent(strokes: [dot(0)]), size: size, scale: 1))
        let new = landing

        // Land on the layer with one stroke, then on the one with 300.
        var before = lone.strokesSimulated
        let alone = ms(clock.measure { _ = lone.raster(PaintContent(strokes: [dot(0), new]), size: size, scale: 1) })
        #expect(lone.strokesSimulated - before == 1)
        before = crowded.strokesSimulated
        let crowd = ms(clock.measure { _ = crowded.raster(PaintContent(strokes: many + [new]), size: size, scale: 1) })
        #expect(crowded.strokesSimulated - before == 1, "landing simulated only the new stroke")
        print(String(format: "landing on a 12 MP layer: %.1f ms with 1 stroke under it, %.1f ms with 300", alone, crowd))
        #expect(crowd < alone * MachineSpeed.tolerance + 60,
                "landing grew with the strokes already on the layer: \(Int(crowd)) ms against \(Int(alone))")

        // Undo: the raster kept for the 300 comes straight back.
        before = crowded.strokesSimulated
        var undone: CGImage?
        let undo = ms(clock.measure { undone = crowded.raster(PaintContent(strokes: many), size: size, scale: 1) })
        print(String(format: "undo on a 12 MP layer of 300 strokes: %.1f ms", undo))
        #expect(crowded.strokesSimulated == before, "undo simulated nothing")
        #expect(undone === kept)
        #expect(undo < 50, "undo took \(Int(undo)) ms")
    }
}
