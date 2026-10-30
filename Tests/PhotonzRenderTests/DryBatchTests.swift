import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A dry stroke lays a move's dabs together, side by side on every core,
/// rather than one at a time (`DryStroke.mark(_:)` with a list). A pencil's or
/// a crayon's tip only ever raises a pixel to the larger of what is there and
/// what it lays, so the order the dabs land in cannot matter; charcoal and
/// chalk drag what they laid along before the next dab, so they still go one
/// at a time. On 2026-10-30 a 20 point pencil's move laid about twenty-five
/// dabs of a few hundred pixels each, every one on the main thread alone.
@Suite("A dry stroke lays a batch of dabs as it lays them one at a time")
struct DryBatchTests {

    private func stroke(_ medium: BrushMedium, size: Double, tilted: Bool) -> BrushStroke {
        var settings = BrushSettings(medium: medium, values: ["size": size])
        settings.mode = .paint
        let tilt = tilted ? CGPoint(x: 0.6, y: -0.3) : CGPoint.zero
        let samples: [StrokeSample] = (0...30).map { (i: Int) -> StrokeSample in
            let n = CGFloat(i)
            let point = CGPoint(x: 20 + n * 9, y: 60 + sin(n * 0.4) * 25)
            let pressure: Double = 0.4 + 0.5 * Double(i % 7) / 7
            return StrokeSample(point: point, pressure: pressure, tilt: tilt, ms: Double(i) * 16)
        }
        return BrushStroke(samples: samples, settings: settings, colorHex: "#203040", seed: 11, startedAt: 0)
    }

    private func field(_ stroke: BrushStroke, scale: CGFloat, batch: Int?) throws -> (CoverageField, PixelBox) {
        let look = try #require(DryLook(stroke.settings))
        var dry = DryStroke(look: look, seed: stroke.seed, toPixels: CGAffineTransform(scaleX: scale, y: scale),
                            limit: PixelBox(minX: 0, minY: 0, maxX: Int(320 * scale), maxY: Int(130 * scale)))
        let dabs = BrushPlacement.dabs(for: stroke)
        var touched = PixelBox.empty
        if let batch {
            var at = 0
            while at < dabs.count {
                let end = min(dabs.count, at + batch)
                touched = touched.union(dry.mark(Array(dabs[at..<end])))
                at = end
            }
        } else {
            for dab in dabs { touched = touched.union(dry.mark(dab)) }
        }
        return (dry.field, touched)
    }

    @Test(arguments: [BrushMedium.pencil, .crayon, .charcoal, .chalk])
    func aBatchLaysWhatOneAtATimeLays(_ medium: BrushMedium) throws {
        for (size, scale, tilted) in [(20.0, 1.0, false), (64.0, 2.0, false), (40.0, 1.0, true)] {
            let new = stroke(medium, size: size, tilted: tilted)
            let (single, singleBox) = try field(new, scale: scale, batch: nil)
            for batch in [1, 5, 40] {
                let (batched, batchedBox) = try field(new, scale: scale, batch: batch)
                #expect(batched.box == single.box, "\(medium) \(size) pt, batches of \(batch): field box")
                #expect(batched.values == single.values, "\(medium) \(size) pt, batches of \(batch): coverage")
                #expect(batchedBox == singleBox, "\(medium) \(size) pt, batches of \(batch): pixels touched")
            }
        }
    }

    @Test func aBatchTakenBackLeavesTheFieldAsItWas() throws {
        // The live tail is laid as a batch and taken back on the next move.
        let new = stroke(.pencil, size: 20, tilted: false)
        let look = try #require(DryLook(new.settings))
        var dry = DryStroke(look: look, seed: new.seed, toPixels: .identity,
                            limit: PixelBox(minX: 0, minY: 0, maxX: 320, maxY: 130))
        let dabs = BrushPlacement.dabs(for: new)
        let half = dabs.count / 2
        _ = dry.mark(Array(dabs[..<half]))
        let before = dry.field
        let checkpoint = dry.beginTail()
        _ = dry.mark(Array(dabs[half...]))
        dry.takeBackTail(to: checkpoint)
        // The field may have grown for the tail; past where it was, it is clear.
        let after = dry.field
        var differ = 0
        for y in after.box.minY..<after.box.maxY {
            for x in after.box.minX..<after.box.maxX where after.value(x, y) != before.value(x, y) { differ += 1 }
        }
        #expect(differ == 0)
    }
}
