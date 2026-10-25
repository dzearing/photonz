import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Watercolour stays wet for a while after a stroke ends, and a stroke painted
/// into one that is still wet blooms (`docs/design/brushes.md`, decision 4).
/// So a stroke records when it was painted, as data, and how wet an earlier
/// stroke still is when a later one begins is worked out from those times and
/// the earlier stroke's Wetness: the same answer on every replay.
@Suite("Watercolour drying")
struct WatercolourDryingTests {

    private func stroke(_ medium: BrushMedium = .watercolour, at time: Double?, lasting ms: Double = 500,
                        wetness: Double? = nil, mode: BrushMode = .paint) -> BrushStroke {
        var values: [String: Double] = [:]
        if let wetness { values["wetness"] = wetness }
        return BrushStroke(samples: [StrokeSample(point: CGPoint(x: 10, y: 10), ms: 0),
                                     StrokeSample(point: CGPoint(x: 90, y: 10), ms: ms)],
                           settings: BrushSettings(medium: medium, values: values, mode: mode),
                           colorHex: "#3366CC", seed: 1, startedAt: time)
    }

    @Test("Watercolour's own settings are Wetness, Bleed and Granulation")
    func settings() {
        #expect(BrushMedium.watercolour.settings.map(\.id).dropFirst(2) == ["wetness", "bleed", "granulation"])
    }

    @Test("A stroke keeps when it was painted, and a stroke from before that was recorded reads none")
    func timeIsData() throws {
        let timed = stroke(at: 1_000, lasting: 750)
        #expect(timed.startedAt == 1_000)
        #expect(timed.endedAt == 1_000.75)
        let decoded = try JSONDecoder().decode(BrushStroke.self, from: JSONEncoder().encode(timed))
        #expect(decoded == timed)
        // A stroke saved before strokes had a time still opens.
        let json = try #require(String(data: JSONEncoder().encode(stroke(at: nil)), encoding: .utf8))
        #expect(!json.contains("startedAt"))
        let old = try JSONDecoder().decode(BrushStroke.self, from: Data(json.utf8))
        #expect(old.startedAt == nil && old.endedAt == nil)
    }

    @Test("A wetter brush stays wet longer, a few seconds either way")
    func dryingTime() {
        let dry = WatercolourDrying.seconds(wetness: 0)
        let normal = WatercolourDrying.seconds(wetness: 60)
        let soaked = WatercolourDrying.seconds(wetness: 100)
        #expect(dry >= 1 && dry < normal && normal < soaked && soaked <= 10, "\(dry) \(normal) \(soaked)")
    }

    @Test("An earlier stroke is fully wet just after it ends, drying to nothing by its drying time")
    func wetnessFalls() {
        let first = stroke(at: 100, lasting: 1_000, wetness: 60)
        let drying = WatercolourDrying.seconds(wetness: 60)
        #expect(first.wetness(when: stroke(at: 100.5)) == 1, "painted while it was still going on")
        #expect(first.wetness(when: stroke(at: 101)) == 1)
        let half = first.wetness(when: stroke(at: 101 + drying / 2))
        #expect(abs(half - 0.5) < 0.01, "\(half)")
        #expect(first.wetness(when: stroke(at: 101 + drying + 0.1)) == 0)
        // A wetter earlier stroke is still wet when a drier one would not be.
        let soaked = stroke(at: 100, lasting: 1_000, wetness: 100)
        let parched = stroke(at: 100, lasting: 1_000, wetness: 5)
        let later = stroke(at: 104)
        #expect(soaked.wetness(when: later) > 0.2)
        #expect(parched.wetness(when: later) == 0)
    }

    @Test("Only watercolour paint is wet, and a stroke with no time is dry")
    func onlyWatercolourIsWet() {
        let later = stroke(at: 101)
        #expect(stroke(.marker, at: 100).wetness(when: later) == 0)
        #expect(stroke(at: 100, mode: .smudge).wetness(when: later) == 0)
        #expect(stroke(at: nil).wetness(when: later) == 0)
        #expect(stroke(at: 100).wetness(when: stroke(at: nil)) == 0)
    }

    @Test("A watercolour stroke's box reaches past its tip far enough to hold its bleed")
    func boxHoldsTheBleed() {
        #expect(BrushMedium.watercolour.reach > 2)
        let s = stroke(at: 1)
        let size = s.settings.size
        #expect(s.bounds.minY <= 10 - size / 2 * 2)
    }
}
