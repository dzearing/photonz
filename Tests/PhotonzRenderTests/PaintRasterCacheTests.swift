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

    @Test func aLandingAtOneScaleNeverCostsTheOtherScaleItsRaster() throws {
        // Zoomed in, a layer is shown at two scales: the composite's and the
        // sharp copy's, several times bigger. A landing paints the new stroke
        // at both. On 2026-10-27 the sharp copy's raster came in first, the
        // budget let the oldest go, and that was the composite's raster for
        // the strokes before: the composite then replayed all nine strokes
        // while the sharp copy's raster from one stroke back, wanted only for
        // an undo there, stayed (painting-holds-still-walk, at 200%).
        let small = Int(box.width) * Int(box.height) * 4
        let big = Int(box.width * 4) * Int(box.height * 4) * 4
        // Room for two sharp rasters and not much else, as a 200% view of a
        // screenshot has in the shared budget.
        let cache = PaintRasterCache(budgetBytes: 2 * big + small / 2)
        let all = strokes
        func at(_ count: Int, _ scale: CGFloat) -> CGImage? {
            cache.raster(PaintContent(strokes: Array(all.prefix(count))), size: box, scale: scale)
        }
        _ = at(2, 1)
        _ = at(3, 1)
        _ = at(3, 4)
        // The landing of stroke 4: the sharp copy's first, then the composite's.
        _ = at(4, 4)
        let before = cache.strokesSimulated
        let composite = try #require(at(4, 1))
        #expect(cache.strokesSimulated - before == 1, "the composite painted only the new stroke")
        #expect(bytes(composite) == bytes(try #require(PaintRasterizer.replay(
            PaintContent(strokes: Array(all.prefix(4))), size: box, scale: 1))))
        #expect(cache.keptBytes <= cache.budgetBytes)
    }

    @Test func undoneTheShorterListIsNotTheFirstToGo() throws {
        // After an undo the shorter list is what is on screen: a list it is
        // the start of, used longer ago, goes before it does.
        let one = Int(box.width * scale) * Int(box.height * scale) * 4
        let cache = PaintRasterCache(budgetBytes: one * 2 + one / 2)
        let all = strokes
        func at(_ count: Int) -> CGImage? {
            cache.raster(PaintContent(strokes: Array(all.prefix(count))), size: box, scale: scale)
        }
        _ = at(3)
        _ = at(4)
        _ = at(3)            // undo
        _ = cache.raster(PaintContent(strokes: Array(all.suffix(1))), size: box, scale: scale)  // another layer
        let before = cache.strokesSimulated
        _ = at(3)
        #expect(cache.strokesSimulated == before, "the undone state was still kept")
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
@Suite("Landing and undo on a big layer", .serialized)
struct PaintLandingPerfTests {
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

    /// A stroke landing in round `round`: the same marker, a different seed
    /// and a later start, so every round lands something new.
    private func landing(_ round: Int) -> BrushStroke {
        var stroke = landing
        stroke.seed = UInt32(99 + round)
        stroke.startedAt = 10_000 + Double(round)
        return stroke
    }

    /// Timed on this thread's CPU clock, the landing on one stroke and the
    /// landing on 300 back to back in every round, and judged as the middle
    /// round's ratio of the two: whatever else the machine is doing slows both
    /// halves of a round alike. A stopwatch on one landing each failed CI at
    /// 1275 ms against 1066 (2026-10-30), and a stopwatch on one undo read 54.7
    /// ms against a flat 50 in a full run here, for a lookup that reads under
    /// a millisecond in every other run.
    @Test func landingOnThreeHundredStrokesCostsWhatLandingOnOneDoes() throws {
        let many = (0..<300).map(dot)
        // Room for every raster the rounds below make, 48 MB each, so the 300
        // on their own are still kept for the undo after them.
        let crowded = PaintRasterCache(budgetBytes: 512 << 20)
        let kept = try #require(crowded.raster(PaintContent(strokes: many), size: size, scale: 1))
        let lone = PaintRasterCache(budgetBytes: 512 << 20)
        _ = try #require(lone.raster(PaintContent(strokes: [dot(0)]), size: size, scale: 1))

        // Land on the layer with one stroke and on the one with 300, each
        // round the other way round, so neither always goes second.
        var alone: [Double] = [], crowd: [Double] = []
        for round in 0..<5 {
            let new = landing(round)
            func landAlone() {
                let before = lone.strokesSimulated
                let start = PerfClock.nowMS()
                _ = lone.raster(PaintContent(strokes: [dot(0), new]), size: size, scale: 1)
                alone.append(PerfClock.nowMS() - start)
                #expect(lone.strokesSimulated - before == 1)
            }
            func landCrowded() {
                let before = crowded.strokesSimulated
                let start = PerfClock.nowMS()
                _ = crowded.raster(PaintContent(strokes: many + [new]), size: size, scale: 1)
                crowd.append(PerfClock.nowMS() - start)
                #expect(crowded.strokesSimulated - before == 1, "landing simulated only the new stroke")
            }
            if round.isMultiple(of: 2) { landAlone(); landCrowded() } else { landCrowded(); landAlone() }
        }
        let ratio = MachineSpeed.median(of: zip(crowd, alone).map { $0 / max($1, 0.001) }) ?? .infinity
        let aloneMS = MachineSpeed.median(of: alone) ?? 0
        print(String(format: "landing on a 12 MP layer, ms of CPU: %.1f with 1 stroke under it, %.1f with 300 "
                     + "(%.2f times, the middle of %d rounds)",
                     aloneMS, MachineSpeed.median(of: crowd) ?? 0, ratio, alone.count))
        // Alone the two read 0.94 to 1.01 times each other (2026-10-30): the 300
        // strokes are already in the kept raster, so landing paints one. A
        // landing that grew with the strokes under it reads twice or more.
        if MachineSpeed.isGating {
            #expect(ratio < 1.6, "landing grew with the strokes already on the layer: \(ratio) times a landing on one")
        }

        // Undo: the raster kept for the 300 comes straight back, simulating
        // nothing. The fastest of five, against the landing it is undoing: a
        // lookup is a sliver of a landing, a lookup that paints is a landing.
        let before = crowded.strokesSimulated
        var undone: CGImage?
        var undo = Double.infinity
        for _ in 0..<5 {
            let start = PerfClock.nowMS()
            undone = crowded.raster(PaintContent(strokes: many), size: size, scale: 1)
            undo = min(undo, PerfClock.nowMS() - start)
        }
        print(String(format: "undo on a 12 MP layer of 300 strokes: %.2f ms of CPU", undo))
        #expect(crowded.strokesSimulated == before, "undo simulated nothing")
        #expect(undone === kept)
        if MachineSpeed.isGating {
            #expect(undo < aloneMS / 10, "undo took \(undo) ms of CPU, against \(aloneMS) for a landing")
        }
    }
}
