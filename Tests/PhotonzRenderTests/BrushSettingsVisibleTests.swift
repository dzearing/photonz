import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Every setting a brush declares visibly changes the stroke (the user,
/// 2026-10-24: each brush has knobs of its own, and each must do something
/// you can see). The same stroke is painted at a setting's low end and its
/// high end, and the share of the stroke that differs between the two has to
/// clear a bar. A setting that only acts in its own situation is painted in
/// it: Tilt Shading with a leaning pen, Smear over paint already there,
/// Build-up with the spray held still half way.
@Suite("Every brush setting changes the stroke")
struct BrushSettingsVisibleTests {

    static let bar = 0.2
    private let size = CGSize(width: 360, height: 120)

    private func samples(tilt: CGPoint? = nil, hold: Bool = false) -> [StrokeSample] {
        var out: [StrokeSample] = []
        var ms = 0.0
        for i in 0...30 {
            let t = CGFloat(i) / 30
            out.append(StrokeSample(point: CGPoint(x: 40 + 280 * t, y: 60 + sin(t * .pi * 2) * 12),
                                    tilt: tilt, ms: ms))
            ms += 12
            if hold, i == 15 {
                // Most of what a Build-up changes is where the spray is held,
                // so the hold is long against the pass.
                for _ in 0..<40 {
                    ms += 30
                    out.append(StrokeSample(point: out[out.count - 1].point, tilt: tilt, ms: ms))
                }
            }
        }
        return out
    }

    private func render(_ medium: BrushMedium, _ id: String, _ value: Double) throws -> CGImage {
        var strokes: [BrushStroke] = []
        if id == "smear" {
            // Red paint already on the layer, under the middle of the stroke.
            strokes.append(BrushStroke(samples: (0...10).map {
                StrokeSample(point: CGPoint(x: 150 + Double($0) * 6, y: 20 + Double($0) * 8), ms: Double($0) * 12)
            }, settings: BrushSettings(medium: .oil), colorHex: "#D0302A", seed: 9))
        }
        let tilt: CGPoint? = id == "tilt" ? CGPoint(x: 0.7, y: 0.3) : nil
        strokes.append(BrushStroke(samples: samples(tilt: tilt, hold: id == "buildup"),
                                   settings: BrushSettings(medium: medium, values: [id: value]),
                                   colorHex: "#24324A", seed: 21))
        return try #require(PaintRasterizer.rasterize(PaintContent(strokes: strokes), size: size, scale: 2))
    }

    @Test("Each brush's own settings change the stroke between their two ends",
          arguments: BrushMedium.allCases)
    func ownSettingsShow(_ medium: BrushMedium) throws {
        for spec in medium.ownSettings {
            let low = try render(medium, spec.id, spec.range.lowerBound)
            let high = try render(medium, spec.id, spec.range.upperBound)
            // Per pixel catches a pale texture appearing (a pencil's side
            // shading); per four-point block catches a change of tone that
            // is not just grain rearranged. Either, past the bar, is seen.
            let share = max(PaintMeasures.changedShare(low, high, block: 1),
                            PaintMeasures.changedShare(low, high))
            print("changedShare \(medium.rawValue).\(spec.id) = \(String(format: "%.3f", share))")
            #expect(share >= Self.bar, "\(medium.title) \(spec.name) changes \(share) of the stroke")
        }
    }

    @Test("The same render reads as unchanged, a different one as changed")
    func measure() throws {
        let a = try render(.charcoal, "grain", 60)
        #expect(PaintMeasures.changedShare(a, a) == 0)
        let b = try render(.marker, "flow", 60)
        #expect(PaintMeasures.changedShare(a, b) > 0.3)
    }
}
