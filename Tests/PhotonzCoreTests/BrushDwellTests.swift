import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The airbrush keeps spraying while the pointer holds still
/// (`docs/design/brushes.md`, decision 4: "flow accumulates while the pointer
/// dwells"). Placement lays dabs by TIME as well as by distance for it, so a
/// stroke that pauses over one spot leaves more paint there; every other
/// medium lays dabs only as it moves.
@Suite("Brush dwell")
struct BrushDwellTests {

    private func samples(holding point: CGPoint, for ms: Double, every step: Double = 33,
                         wobble: CGFloat = 0) -> [StrokeSample] {
        stride(from: 0, through: ms, by: step).enumerated().map { i, t in
            // A hand on a tablet is never perfectly still.
            let shake = wobble * (i % 2 == 0 ? 1 : -1)
            return StrokeSample(point: CGPoint(x: point.x + shake, y: point.y - shake), ms: t)
        }
    }

    private func stroke(_ medium: BrushMedium, _ samples: [StrokeSample], size: Double = 40) -> BrushStroke {
        BrushStroke(samples: samples, settings: BrushSettings(medium: medium, values: ["size": size]),
                    colorHex: "#000000", seed: 9)
    }

    @Test("Holding the airbrush still keeps laying dabs, at a steady rate in time")
    func holdingStillSprays() {
        let short = BrushPlacement.dabs(for: stroke(.airbrush, samples(holding: CGPoint(x: 50, y: 50), for: 200)))
        let long = BrushPlacement.dabs(for: stroke(.airbrush, samples(holding: CGPoint(x: 50, y: 50), for: 1000)))
        let rate = 1000 / BrushPlacement.dwellInterval
        #expect(Double(long.count) >= rate * 0.9, "\(long.count) dabs in a second")
        #expect(long.count > short.count * 3, "\(short.count) -> \(long.count)")
        #expect(long.allSatisfy { hypot($0.center.x - 50, $0.center.y - 50) < 1 })
    }

    @Test("A hand that trembles a little while it holds is still holding")
    func tremblingStillSprays() {
        let held = BrushPlacement.dabs(for: stroke(.airbrush, samples(holding: CGPoint(x: 50, y: 50), for: 1000,
                                                                      wobble: 0.6)))
        #expect(Double(held.count) >= 1000 / BrushPlacement.dwellInterval * 0.8, "\(held.count)")
    }

    @Test("Only the airbrush sprays in place: other media lay nothing more while held")
    func otherMediaDoNotDwell() {
        for medium in BrushMedium.allCases where medium != .airbrush {
            let held = BrushPlacement.dabs(for: stroke(medium, samples(holding: CGPoint(x: 50, y: 50), for: 1000)))
            #expect(held.count <= 2, "\(medium): \(held.count)")
        }
    }

    @Test("A pause in the middle of a pass leaves more dabs there than anywhere along the pass")
    func pauseMidPass() {
        var points: [StrokeSample] = (0...10).map {
            StrokeSample(point: CGPoint(x: 20 + Double($0) * 10, y: 50), ms: Double($0) * 16)
        }
        let pauseAt = points.last?.ms ?? 0
        points += (1...30).map { StrokeSample(point: CGPoint(x: 120, y: 50), ms: pauseAt + Double($0) * 33) }
        let resume = points.last?.ms ?? 0
        points += (1...10).map {
            StrokeSample(point: CGPoint(x: 120 + Double($0) * 10, y: 50), ms: resume + Double($0) * 16)
        }
        let dabs = BrushPlacement.dabs(for: stroke(.airbrush, points))
        let atPause = dabs.filter { abs($0.center.x - 120) < 2 }.count
        let alongPass = dabs.filter { abs($0.center.x - 60) < 2 }.count
        #expect(atPause > alongPass * 5, "\(alongPass) along the pass, \(atPause) at the pause")
    }

    @Test("Dwell dabs worked out sample by sample are exactly the finished stroke's")
    func liveMatchesLanded() {
        var points = samples(holding: CGPoint(x: 50, y: 50), for: 600, wobble: 0.4)
        points += (1...12).map { StrokeSample(point: CGPoint(x: 50 + Double($0) * 7, y: 50 + Double($0) * 2),
                                              ms: 600 + Double($0) * 16) }
        let s = stroke(.airbrush, points)
        var walker = BrushPlacement.Walker(settings: s.settings, seed: s.seed)
        var live: [BrushDab] = []
        for sample in s.samples { live += walker.add(sample) }
        live += walker.finish()
        #expect(live == BrushPlacement.dabs(for: s))
    }
}
