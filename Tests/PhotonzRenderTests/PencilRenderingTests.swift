import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The Pencil (`docs/design/brushes.md`): graphite on the dry media's paper,
/// measured against the plain round tip, which fails every bar here.
@Suite("Pencil rendering")
struct PencilRenderingTests {

    private let line = (CGPoint(x: 30, y: 60), CGPoint(x: 270, y: 60))
    private let box = CGSize(width: 300, height: 120)
    private let scale: CGFloat = 2

    /// A straight stroke: a pen at `pressure` leaning by `tilt`, or a mouse
    /// with neither.
    private func stroke(_ medium: BrushMedium = .pencil, size: Double = 4, set: [String: Double] = [:],
                        pressure: Double? = nil, tilt: CGPoint? = nil, seed: UInt32 = 5,
                        hex: String = "#000000") -> BrushStroke {
        let settings = BrushSettings(medium: medium, values: ["size": size].merging(set) { $1 })
        let samples = (0...24).map { i -> StrokeSample in
            let t = CGFloat(i) / 24
            return StrokeSample(point: CGPoint(x: line.0.x + (line.1.x - line.0.x) * t, y: line.0.y),
                                pressure: pressure, tilt: tilt, ms: Double(i) * 30)
        }
        return BrushStroke(samples: samples, settings: settings, colorHex: hex, seed: seed)
    }

    private func render(_ strokes: [BrushStroke]) throws -> CGImage {
        try #require(PaintRasterizer.rasterize(PaintContent(strokes: strokes), size: box, scale: scale))
    }

    private func profile(_ s: BrushStroke, reach: CGFloat = 30) throws -> (width: Double, darkness: Double) {
        PaintMeasures.lineProfile(try render([s]), from: line.0, to: line.1, reach: reach, scale: scale)
    }

    private func tooth(_ s: BrushStroke) throws -> Double {
        let width = try profile(s).width
        return PaintMeasures.interiorGapFraction(try render([s]), from: line.0, to: line.1,
                                                 diameter: max(width, 1), scale: scale)
    }

    private func grade(_ name: String) -> Double {
        Double(BrushMedium.pencilGrades.firstIndex(of: name) ?? 2)
    }

    // MARK: - Measured bars

    @Test("Measured bar: a softer lead draws a wider, darker line; the round tip does not change")
    func gradesBar() throws {
        let grades = ["2H", "HB", "4B", "8B"]
        let read = try grades.map { try profile(stroke(set: ["hardness": grade($0)])) }
        for (a, b) in zip(read, read.dropFirst()) {
            #expect(b.width >= a.width, "width \(read.map(\.width))")
            #expect(b.darkness > a.darkness, "darkness \(read.map(\.darkness))")
        }
        let first = try #require(read.first), last = try #require(read.last)
        #expect(last.width >= first.width * PaintMeasures.pencilGradeWidthBar, "\(first.width) to \(last.width)")
        #expect(last.darkness >= first.darkness * PaintMeasures.pencilGradeDarknessBar,
                "\(first.darkness) to \(last.darkness)")
        // The plain round has no lead to soften: the bar fails it.
        let hard = try profile(stroke(.marker, set: ["hardness": grade("2H")]))
        let soft = try profile(stroke(.marker, set: ["hardness": grade("8B")]))
        #expect(soft.width < hard.width * PaintMeasures.pencilGradeWidthBar)
        #expect(soft.darkness < hard.darkness * PaintMeasures.pencilGradeDarknessBar)
    }

    @Test("Measured bar: pressed lightly the paper's tooth shows through; pressed hard it fills in and darkens")
    func pressureBar() throws {
        let light = stroke(pressure: 0.2), heavy = stroke(pressure: 1)
        let lightTooth = try tooth(light), heavyTooth = try tooth(heavy)
        #expect(lightTooth >= PaintMeasures.pencilLightToothBar, "light \(lightTooth)")
        #expect(lightTooth > heavyTooth + 0.1, "light \(lightTooth) heavy \(heavyTooth)")
        let lightDark = try profile(light).darkness, heavyDark = try profile(heavy).darkness
        #expect(heavyDark >= lightDark * 1.8, "light \(lightDark) heavy \(heavyDark)")
        // A mouse presses somewhere in between.
        let mouse = try profile(stroke()).darkness
        #expect(mouse > lightDark && mouse < heavyDark, "mouse \(mouse)")
        // The round tip leaves no tooth however lightly it is pressed.
        let round = stroke(.marker, pressure: 0.2)
        #expect(PaintMeasures.interiorGapFraction(try render([round]), from: line.0, to: line.1, diameter: 4,
                                                  scale: scale) < PaintMeasures.pencilLightToothBar)
    }

    @Test("Tilted, the side of the lead lays a broad, paler, grainier band")
    func tiltShades() throws {
        let upright = stroke(pressure: 0.6)
        let leaning = stroke(pressure: 0.6, tilt: CGPoint(x: 0, y: 0.7))
        let up = try profile(upright), side = try profile(leaning)
        #expect(side.width >= up.width * 3, "upright \(up.width) leaning \(side.width)")
        #expect(side.darkness < up.darkness, "upright \(up.darkness) leaning \(side.darkness)")
        #expect(try tooth(leaning) > tooth(upright), "the side catches only the high tooth")
        // Tilt Shading at none: the lean changes nothing.
        let ignored = try profile(stroke(set: ["tilt": 0], pressure: 0.6, tilt: CGPoint(x: 0, y: 0.7)))
        #expect(abs(ignored.width - up.width) <= up.width * 0.15, "\(ignored.width) against \(up.width)")
        // A leaning pen with the round tip is the same round line.
        let round = try profile(stroke(.marker, pressure: 0.6, tilt: CGPoint(x: 0, y: 0.7)))
        let roundUp = try profile(stroke(.marker, pressure: 0.6))
        #expect(round.width < roundUp.width * 3)
    }

    @Test("More Tilt Shading lays a wider band from the same lean")
    func tiltSetting() throws {
        let some = try profile(stroke(set: ["tilt": 30], pressure: 0.6, tilt: CGPoint(x: 0, y: 0.7)))
        let full = try profile(stroke(set: ["tilt": 100], pressure: 0.6, tilt: CGPoint(x: 0, y: 0.7)))
        #expect(full.width > some.width * 1.4, "\(some.width) to \(full.width)")
    }

    @Test("Grain says how much of the paper's tooth the graphite skips")
    func grainSetting() throws {
        let none = try tooth(stroke(size: 8, set: ["grain": 0]))
        let full = try tooth(stroke(size: 8, set: ["grain": 100]))
        #expect(none < 0.08, "no grain \(none)")
        #expect(full > none + 0.25, "full grain \(full)")
    }

    @Test("Passes piled up go to a silvery graphite, not to black")
    func sheen() throws {
        func darkest(_ medium: BrushMedium) throws -> (luma: Double, blueOverRed: Double) {
            let passes = (0..<5).map { i in
                stroke(medium, size: 10, set: medium == .pencil ? ["hardness": grade("8B"), "grain": 0] : ["grain": 0],
                       pressure: 1, seed: UInt32(20 + i))
            }
            let image = try render(passes)
            let width = image.width, height = image.height
            var data = [UInt8](repeating: 0, count: width * height * 4)
            let context = try #require(CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                                 bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var best = (luma: 1.0, blueOverRed: 0.0)
            for i in stride(from: 0, to: data.count, by: 4) {
                let r = Double(data[i]) / 255, g = Double(data[i + 1]) / 255, b = Double(data[i + 2]) / 255
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                if luma < best.luma { best = (luma, b - r) }
            }
            return best
        }
        let pencil = try darkest(.pencil), charcoal = try darkest(.charcoal)
        #expect(pencil.luma > 0.08, "the pile reads as graphite: \(pencil.luma)")
        #expect(pencil.blueOverRed > 0.01, "with a cool sheen: \(pencil.blueOverRed)")
        #expect(charcoal.luma < pencil.luma - 0.05, "charcoal goes darker: \(charcoal.luma)")
    }

    @Test("A pencil is a thinner, paler line than charcoal at their own sizes")
    func notCharcoal() throws {
        let pencil = try profile(stroke())
        let charcoal = try profile(stroke(.charcoal, size: BrushSettings(medium: .charcoal).size))
        #expect(pencil.width < charcoal.width / 3)
        #expect(pencil.darkness < charcoal.darkness)
    }
}
