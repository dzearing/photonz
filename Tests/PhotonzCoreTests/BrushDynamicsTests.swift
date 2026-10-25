import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Pressure, tilt and speed (`docs/design/brushes.md`, decision 6): each medium
/// answers a pen's press where the real one would, a fast pen thins the line,
/// and a mouse stroke swells in and tapers out instead of starting and ending
/// as a blunt circle. Driven with synthetic pens: the test Mac has no tablet.
@Suite("Brush dynamics")
struct BrushDynamicsTests {

    private func stroke(_ medium: BrushMedium, size: Double = 20, length: Double = 300,
                        pointsPerMs speed: Double = 0.3, pressure: ((Double) -> Double)? = nil,
                        tilt: CGPoint? = nil) -> BrushStroke {
        let step = 4.0
        let count = Int(length / step)
        let samples = (0...count).map { i -> StrokeSample in
            let t = Double(i) / Double(count)
            return StrokeSample(point: CGPoint(x: Double(i) * step, y: 0), pressure: pressure.map { $0(t) },
                                tilt: tilt, ms: Double(i) * step / speed)
        }
        return BrushStroke(samples: samples, settings: BrushSettings(medium: medium, values: ["size": size]),
                           colorHex: "#000000", seed: 3)
    }

    /// The dabs of the middle stretch of a stroke, away from both ends.
    private func middle(_ dabs: [BrushDab]) -> [BrushDab] {
        let end = dabs.last?.along ?? 0
        return dabs.filter { $0.along > end * 0.4 && $0.along < end * 0.6 }
    }

    private func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    // MARK: - The press

    @Test("At the steady press every medium paints exactly its Size and its own weight")
    func steadyPressIsTheSize() {
        for medium in BrushMedium.allCases {
            let response = BrushDynamics.response(for: medium)
            #expect(abs(response.size(pressure: BrushDynamics.steadyPress) - 1) < 1e-9, "\(medium)")
            #expect(abs(response.weight(pressure: BrushDynamics.steadyPress) - 1) < 1e-9, "\(medium)")
        }
    }

    @Test("A harder press never paints narrower or lighter, for any medium")
    func pressIsMonotone() {
        for medium in BrushMedium.allCases {
            let response = BrushDynamics.response(for: medium)
            for p in stride(from: 0.0, to: 1.0, by: 0.1) {
                #expect(response.size(pressure: p + 0.1) >= response.size(pressure: p) - 1e-12, "\(medium)")
                #expect(response.weight(pressure: p + 0.1) >= response.weight(pressure: p) - 1e-12, "\(medium)")
            }
        }
    }

    @Test("The press widens the media the design doc lists, and darkens the dry sticks")
    func pressPerMedium() {
        func widens(_ m: BrushMedium) -> Double {
            let r = BrushDynamics.response(for: m)
            return r.size(pressure: 0.95) / r.size(pressure: 0.2)
        }
        func darkens(_ m: BrushMedium) -> Double {
            let r = BrushDynamics.response(for: m)
            return r.weight(pressure: 0.95) / r.weight(pressure: 0.2)
        }
        // Charcoal: size and opacity. Chalk, crayon the same, less so for wax.
        #expect(widens(.charcoal) >= 1.8)
        #expect(darkens(.charcoal) >= 2)
        #expect(widens(.chalk) >= 1.5)
        #expect(darkens(.chalk) >= 1.7)
        #expect(widens(.crayon) >= 1.15)
        #expect(darkens(.crayon) >= 1.5)
        // A round watercolour brush's belly spreads; an oil brush splays a little.
        #expect(widens(.watercolour) >= 2)
        #expect(widens(.oil) >= 1.15)
        // A felt nib barely spreads and never darkens; the airbrush's press is
        // its flow and the pencil's its own (both read the dab's pressure).
        #expect(widens(.marker) < 1.3)
        #expect(darkens(.marker) == 1)
        #expect(widens(.airbrush) == 1)
        #expect(widens(.pencil) == 1)
    }

    @Test("A pen's dabs are as wide and as heavy as its press says")
    func penPressShapesDabs() {
        let light = stroke(.charcoal, pressure: { _ in 0.2 })
        let heavy = stroke(.charcoal, pressure: { _ in 0.95 })
        let lightDabs = middle(BrushPlacement.dabs(for: light))
        let heavyDabs = middle(BrushPlacement.dabs(for: heavy))
        let r = BrushDynamics.response(for: .charcoal)
        for dab in lightDabs {
            #expect(abs(Double(dab.diameter) - 20 * r.size(pressure: 0.2)) < 1e-6)
            #expect(abs(dab.weight - r.weight(pressure: 0.2)) < 1e-9)
        }
        #expect(mean(heavyDabs.map { Double($0.diameter) }) > mean(lightDabs.map { Double($0.diameter) }) * 1.8)
        #expect(mean(heavyDabs.map(\.weight)) > mean(lightDabs.map(\.weight)) * 2)
    }

    @Test("A pen's press ramping up and down widens and narrows the line with it, with no taper of its own")
    func penRamp() {
        let swell = stroke(.watercolour, pressure: { t in sin(t * .pi) })
        let dabs = BrushPlacement.dabs(for: swell)
        let first = Double(dabs.first?.diameter ?? 0), last = Double(dabs.last?.diameter ?? 0)
        let peak = Double(dabs.map(\.diameter).max() ?? 0)
        #expect(first < peak * 0.5)
        #expect(last < peak * 0.5)
        // The pen's stroke lands exactly as it was drawn: nothing thins its end.
        var walker = BrushPlacement.Walker(settings: swell.settings, seed: swell.seed)
        var live: [BrushDab] = []
        for sample in swell.samples { live += walker.add(sample) }
        live += walker.finish()
        #expect(live == dabs)
    }

    // MARK: - Speed

    @Test("A fast pen paints a thinner line than a slow one at the same press")
    func fastPenThins() {
        for medium in [BrushMedium.charcoal, .chalk, .watercolour, .pencil] {
            let slow = middle(BrushPlacement.dabs(for: stroke(medium, pointsPerMs: 0.2, pressure: { _ in 0.6 })))
            let fast = middle(BrushPlacement.dabs(for: stroke(medium, pointsPerMs: 5, pressure: { _ in 0.6 })))
            let ratio = mean(fast.map { Double($0.diameter) }) / mean(slow.map { Double($0.diameter) })
            #expect(ratio < 0.85, "\(medium): \(ratio)")
            #expect(ratio > 0.6, "\(medium): \(ratio)")
            // The press itself is the pen's own reading, untouched.
            #expect(fast.allSatisfy { abs($0.pressure - 0.6) < 1e-9 })
        }
    }

    @Test("A fast mouse stroke paints a thinner line than a slow one")
    func fastMouseThins() {
        let slow = middle(BrushPlacement.dabs(for: stroke(.charcoal, pointsPerMs: 0.2)))
        let fast = middle(BrushPlacement.dabs(for: stroke(.charcoal, pointsPerMs: 4)))
        let ratio = mean(fast.map { Double($0.diameter) }) / mean(slow.map { Double($0.diameter) })
        #expect(ratio < 0.85, "\(ratio)")
        // Slow and settled, a mouse paints exactly the Size.
        #expect(slow.allSatisfy { abs(Double($0.diameter) - 20) < 0.2 })
    }

    // MARK: - The mouse's taper

    @Test("A mouse stroke swells in and tapers out instead of starting and ending blunt")
    func mouseTapers() {
        for medium in [BrushMedium.charcoal, .chalk, .crayon, .pencil, .watercolour, .marker, .oil] {
            let dabs = BrushPlacement.dabs(for: stroke(medium))
            let full = mean(middle(dabs).map { Double($0.diameter) })
            let depth = BrushDynamics.response(for: medium).taperDepth
            let first = Double(dabs.first?.diameter ?? 0), last = Double(dabs.last?.diameter ?? 0)
            #expect(first < full * (1 - depth * 0.8), "\(medium) starts at \(first) of \(full)")
            #expect(last < full * (1 - depth * 0.8), "\(medium) ends at \(last) of \(full)")
            #expect((dabs.last?.weight ?? 1) < (middle(dabs).first?.weight ?? 0), "\(medium) lifts off lighter")
            // It narrows steadily into the end, never bulging.
            let tail = dabs.filter { $0.along > (dabs.last?.along ?? 0) - 40 }
            for (a, b) in zip(tail, tail.dropFirst()) { #expect(b.diameter <= a.diameter + 1e-6, "\(medium)") }
        }
    }

    @Test("Charcoal, the medium the judges asked for, ends at under a third of its width")
    func charcoalTaperDepth() {
        let dabs = BrushPlacement.dabs(for: stroke(.charcoal))
        #expect(Double(dabs.first?.diameter ?? 99) < 20 * 0.35)
        #expect(Double(dabs.last?.diameter ?? 99) < 20 * 0.35)
    }

    @Test("A short mouse stroke tapers at both ends without ever disappearing")
    func shortStrokeTapers() {
        let dabs = BrushPlacement.dabs(for: stroke(.charcoal, length: 24))
        #expect(!dabs.isEmpty)
        #expect(dabs.allSatisfy { $0.diameter > 0 && $0.weight > 0 })
        let widest = dabs.map(\.diameter).max() ?? 0
        #expect(widest < 20, "too short to reach its full width: \(widest)")
    }

    @Test("The airbrush has no blunt end to taper: its spray already feathers")
    func airbrushDoesNotTaper() {
        let dabs = BrushPlacement.dabs(for: stroke(.airbrush, size: 40))
        #expect(dabs.allSatisfy { $0.diameter == 40 && $0.weight == 1 })
    }

    @Test("The live stroke is the landed one up to its end, which thins only once the pointer lifts")
    func liveThenTaperOut() {
        let s = stroke(.charcoal)
        var walker = BrushPlacement.Walker(settings: s.settings, seed: s.seed)
        var live: [BrushDab] = []
        for sample in s.samples { live += walker.add(sample) }
        live += walker.finish()
        let landed = BrushPlacement.dabs(for: s)
        #expect(BrushPlacement.taperedOut(live, for: s) == landed)
        #expect(live.count == landed.count)
        // Only the last stretch changed.
        let reach = BrushDynamics.taperLength(diameter: 20)
        let end = landed.last?.along ?? 0
        for (a, b) in zip(live, landed) where a != b { #expect(a.along > end - reach - 1e-6) }
        #expect(zip(live, landed).contains { $0 != $1 })
    }

    @Test("Dabs know how far along the path they are, a spacing apart")
    func alongIsPathLength() {
        let dabs = BrushPlacement.dabs(for: stroke(.charcoal, length: 200))
        let gap = Double(BrushPlacement.spacing(forDiameter: 20))
        for (a, b) in zip(dabs.dropLast(), dabs.dropLast().dropFirst()) {
            #expect(abs(b.along - a.along - gap) < 1e-6)
        }
        #expect(abs((dabs.last?.along ?? 0) - 200) < 1e-6)
    }

    // MARK: - Tilt

    @Test("A lean is read the same for every medium: none upright, all of it well over")
    func leanReading() {
        #expect(BrushDynamics.lean(.zero).amount == 0)
        #expect(BrushDynamics.lean(CGPoint(x: 0.1, y: 0)).amount == 0)
        #expect(BrushDynamics.lean(CGPoint(x: 0, y: 0.9)).amount == 1)
        let half = BrushDynamics.lean(CGPoint(x: 0.3, y: 0.3))
        #expect(half.amount > 0.2 && half.amount < 0.9)
        #expect(abs(half.axis.dx - half.axis.dy) < 1e-9)
    }

    @Test("Tilt broadens charcoal, chalk and the marker's side, and nothing else lays a side")
    func sides() {
        for medium in BrushMedium.allCases {
            let side = BrushDynamics.response(for: medium).side
            switch medium {
            case .charcoal, .chalk, .marker: #expect(side.long > 0, "\(medium)")
            default: #expect(side == .none, "\(medium)")
            }
        }
        #expect(BrushDynamics.response(for: .marker).side.turnsNib)
    }

    @Test("A stroke's box reaches as far as a hard press and a full lean can mark")
    func boundsCoverThePress() {
        for medium in BrushMedium.allCases where medium != .pencil {
            let r = BrushDynamics.response(for: medium)
            let widest = r.size(pressure: 1) * (1 + r.side.long)
            #expect(medium.reach >= widest, "\(medium): reach \(medium.reach) under \(widest)")
        }
    }
}
