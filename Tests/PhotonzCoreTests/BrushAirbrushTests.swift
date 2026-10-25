import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The airbrush's own settings and what placement does with them
/// (`docs/design/brushes.md`, "What the airbrush settled"): Flow, Spread,
/// Droplet Size and Build-up, read from the one list; Build-up sets how fast
/// a held spray lays paint; and a dab sprays by time, so a fast pass hands
/// each dab less paint than a slow one.
@Suite("Brush airbrush")
struct BrushAirbrushTests {

    private func stroke(_ samples: [StrokeSample], _ values: [String: Double] = [:],
                        medium: BrushMedium = .airbrush) -> BrushStroke {
        BrushStroke(samples: samples,
                    settings: BrushSettings(medium: medium, values: ["size": 40].merging(values) { $1 }),
                    colorHex: "#000000", seed: 9)
    }

    private func held(for ms: Double) -> [StrokeSample] {
        stride(from: 0, through: ms, by: 33).map { StrokeSample(point: CGPoint(x: 50, y: 50), ms: $0) }
    }

    /// A straight pass at `speed` points a millisecond, a sample every 8 ms.
    private func pass(speed: Double, pressure: Double? = 0.6) -> [StrokeSample] {
        let length = 240.0
        let count = Int(length / (speed * 8))
        return (0...count).map { i in
            StrokeSample(point: CGPoint(x: 20 + length * Double(i) / Double(count), y: 50),
                         pressure: pressure, ms: Double(i) * 8)
        }
    }

    @Test("The airbrush's own settings have plain names, in the order they are shown")
    func names() {
        let own = BrushMedium.airbrush.settings.dropFirst(2)
        #expect(own.map(\.name) == ["Flow", "Spread", "Droplet Size", "Build-up"])
        #expect(own.allSatisfy { $0.range == 0...100 && $0.options == nil })
    }

    @Test("A stroke saved with the old Softness opens with that value as its Spread")
    func softnessBecomesSpread() throws {
        let old = #"{"medium":"airbrush","values":{"size":40,"opacity":100,"flow":30,"softness":15}}"#
        let settings = try JSONDecoder().decode(BrushSettings.self, from: Data(old.utf8))
        #expect(settings.value("spread") == 15)
        #expect(settings.values["softness"] == nil)
        var set = BrushSettings(medium: .airbrush)
        set.set("softness", to: 70)
        #expect(set.value("spread") == 70)
        // A value under the new name wins over one under the old.
        let both = BrushSettings(medium: .airbrush, values: ["softness": 10, "spread": 90])
        #expect(both.value("spread") == 90)
    }

    @Test("Build-up sets how fast a held spray lays dabs, and none at all at 0")
    func buildUpRate() {
        func count(_ buildUp: Double) -> Int {
            BrushPlacement.dabs(for: stroke(held(for: 1000), ["buildup": buildUp])).count
        }
        let none = count(0), half = count(50), full = count(100)
        #expect(none <= 2, "Build-up 0 laid \(none)")
        #expect(Double(half) >= 1000 / BrushPlacement.dwellInterval * 0.9, "\(half)")
        #expect(Double(full) > Double(half) * 1.7, "50: \(half), 100: \(full)")
        #expect(BrushPlacement.dwellInterval(buildUp: 50) == BrushPlacement.dwellInterval)
        #expect(BrushPlacement.dwellInterval(buildUp: 0) == nil)
    }

    @Test("A fast pass hands each dab less spray than a slow one; a held dab sprays it all")
    func speedThinsTheSpray() {
        func mean(_ dabs: [BrushDab]) -> Double {
            let middle = dabs.filter { $0.center.x > 80 && $0.center.x < 200 }
            return middle.map(\.spray).reduce(0, +) / Double(max(1, middle.count))
        }
        let slow = mean(BrushPlacement.dabs(for: stroke(pass(speed: 0.2))))
        let fast = mean(BrushPlacement.dabs(for: stroke(pass(speed: 3))))
        #expect(slow > 0.85, "slow \(slow)")
        #expect(fast < slow * 0.6, "slow \(slow), fast \(fast)")
        let still = BrushPlacement.dabs(for: stroke(held(for: 600)))
        #expect(still.allSatisfy { $0.spray == 1 })
    }

    @Test("Only the airbrush sprays by time: every other medium's dabs carry all their paint")
    func othersUnaffected() {
        for medium in BrushMedium.allCases where medium != .airbrush {
            let dabs = BrushPlacement.dabs(for: stroke(pass(speed: 3), medium: medium))
            #expect(dabs.allSatisfy { $0.spray == 1 }, "\(medium)")
        }
    }

    @Test("Placed sample by sample, the spray is exactly the finished stroke's")
    func liveMatchesLanded() {
        var samples = pass(speed: 1.5)
        let end = samples.last?.ms ?? 0
        samples += (1...20).map { StrokeSample(point: CGPoint(x: 260, y: 50), pressure: 0.9,
                                               ms: end + Double($0) * 33) }
        let s = stroke(samples, ["buildup": 80])
        var walker = BrushPlacement.Walker(settings: s.settings, seed: s.seed)
        var live: [BrushDab] = []
        for sample in s.samples { live += walker.add(sample) }
        live += walker.finish()
        #expect(live == BrushPlacement.dabs(for: s))
    }
}
