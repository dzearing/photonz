import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The Pencil (`docs/design/brushes.md`): its settings, and the pressure and
/// tilt every dab now carries, read from a pen or, for a mouse, simulated.
@Suite("Brush pencil")
struct BrushPencilTests {

    @Test("Pencil is a brush, named Pencil, first among the sketching media")
    func isABrush() {
        #expect(BrushMedium.allCases.first == .pencil)
        #expect(BrushMedium.pencil.title == "Pencil")
        #expect(BrushMedium(rawValue: "pencil") == .pencil)
    }

    @Test("Hardness is a choice of pencil grades from hard to soft, starting at HB")
    func hardness() throws {
        let spec = try #require(BrushMedium.pencil.settings.first { $0.id == "hardness" })
        #expect(spec.name == "Hardness")
        #expect(spec.options == ["4H", "2H", "HB", "2B", "4B", "6B", "8B"])
        #expect(spec.options?[Int(spec.defaultValue)] == "HB")
        let names = BrushMedium.pencil.settings.map(\.name)
        #expect(names == ["Size", "Opacity", "Hardness", "Grain", "Tilt Shading"])
        // A pencil is thin.
        #expect(BrushSettings(medium: .pencil).size <= 4)
    }

    @Test("A pencil saved with a grade loads with it, and an unknown grade is clamped")
    func codable() throws {
        let settings = BrushSettings(medium: .pencil, values: ["hardness": 6])
        let data = try JSONEncoder().encode(settings)
        let back = try JSONDecoder().decode(BrushSettings.self, from: data)
        #expect(back == settings)
        #expect(BrushSettings(medium: .pencil, values: ["hardness": 40]).value("hardness") == 6)
    }

    private func stroke(_ samples: [StrokeSample], medium: BrushMedium = .pencil, size: Double = 4) -> BrushStroke {
        BrushStroke(samples: samples, settings: BrushSettings(medium: medium, values: ["size": size]),
                    colorHex: "#000000", seed: 3)
    }

    @Test("A pen's pressure reaches every dab, eased between its samples")
    func penPressure() {
        let s = stroke([StrokeSample(point: .zero, pressure: 0.2, ms: 0),
                        StrokeSample(point: CGPoint(x: 40, y: 0), pressure: 0.6, ms: 20),
                        StrokeSample(point: CGPoint(x: 80, y: 0), pressure: 1.0, ms: 40)])
        let dabs = BrushPlacement.dabs(for: s)
        #expect(abs((dabs.first?.pressure ?? 0) - 0.2) < 1e-9)
        #expect(abs((dabs.last?.pressure ?? 0) - 1.0) < 1e-9)
        let middle = dabs.min { abs($0.center.x - 40) < abs($1.center.x - 40) }
        #expect(abs((middle?.pressure ?? 0) - 0.6) < 0.03)
        // Never down where the pen went up.
        for (a, b) in zip(dabs, dabs.dropFirst()) { #expect(b.pressure >= a.pressure - 1e-9) }
    }

    @Test("A pen's tilt reaches every dab; a mouse's dabs stand upright")
    func penTilt() {
        let tilted = stroke([StrokeSample(point: .zero, pressure: 0.5, tilt: CGPoint(x: 0.6, y: 0), ms: 0),
                             StrokeSample(point: CGPoint(x: 30, y: 0), pressure: 0.5,
                                          tilt: CGPoint(x: 0.6, y: 0.2), ms: 20)])
        let dabs = BrushPlacement.dabs(for: tilted)
        #expect(dabs.first?.tilt == CGPoint(x: 0.6, y: 0))
        #expect(abs((dabs.last?.tilt.y ?? 0) - 0.2) < 1e-9)
        let mouse = stroke([StrokeSample(point: .zero, ms: 0), StrokeSample(point: CGPoint(x: 30, y: 0), ms: 20)])
        #expect(BrushPlacement.dabs(for: mouse).allSatisfy { $0.tilt == .zero })
    }

    private func mouseStroke(pointsPerMs speed: Double, length: Double = 200) -> BrushStroke {
        let step = 4.0
        return stroke((0...Int(length / step)).map { i in
            StrokeSample(point: CGPoint(x: Double(i) * step, y: 0), ms: Double(i) * step / speed)
        })
    }

    @Test("A mouse touches down lightly, settles to a steady middle press, and presses lighter moving fast")
    func mousePressure() {
        let slow = BrushPlacement.dabs(for: mouseStroke(pointsPerMs: 0.2))
        let first = slow.first?.pressure ?? 1, settled = slow.last?.pressure ?? 0
        #expect(first < settled - 0.15, "the touch-down is lighter: \(first) against \(settled)")
        #expect(settled > 0.5 && settled < 0.8, "a steady middle press: \(settled)")
        let fast = BrushPlacement.dabs(for: mouseStroke(pointsPerMs: 4)).last?.pressure ?? 1
        #expect(fast < settled - 0.1, "fast is lighter: \(fast) against \(settled)")
        #expect(fast > 0.2)
        #expect(BrushDynamics.mousePressure(speed: 0, travelled: 1000, diameter: 4) <= 1)
    }

    @Test("Pressure worked out sample by sample is exactly the pressure of the finished stroke")
    func liveMatchesLanded() {
        let s = stroke((0..<50).map { i in
            StrokeSample(point: CGPoint(x: Double(i) * 3.1, y: sin(Double(i) / 4) * 20),
                         ms: Double(i * i) * 0.4)
        })
        var walker = BrushPlacement.Walker(settings: s.settings, seed: s.seed)
        var live: [BrushDab] = []
        for sample in s.samples { live += walker.add(sample) }
        live += walker.finish()
        #expect(live == BrushPlacement.dabs(for: s))
    }

    @Test("A pencil's box reaches far enough for the side of the lead when the pen is tilted")
    func bounds() {
        let s = stroke([StrokeSample(point: CGPoint(x: 100, y: 100), ms: 0),
                        StrokeSample(point: CGPoint(x: 200, y: 100), ms: 20)], size: 4)
        #expect(s.bounds.height >= 4 * BrushMedium.pencil.reach)
        #expect(BrushMedium.pencil.reach >= 6)
        #expect(BrushMedium.charcoal.reach == 1)
        let charcoal = stroke(s.samples, medium: .charcoal, size: 4)
        #expect(charcoal.bounds.height == 4)
    }
}
