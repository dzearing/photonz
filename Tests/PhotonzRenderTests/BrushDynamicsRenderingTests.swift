import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Pressure, tilt and speed as they land in pixels (`docs/design/brushes.md`,
/// decision 6), read off real strokes with synthetic pens through the same
/// placement and rasterizer a tablet's strokes go through. Before this slice
/// every medium but the pencil painted one width and one weight end to end,
/// which every check here fails.
@Suite("Brush dynamics rendering")
struct BrushDynamicsRenderingTests {

    private let line = (CGPoint(x: 30, y: 60), CGPoint(x: 330, y: 60))
    private let box = CGSize(width: 360, height: 120)
    private let scale: CGFloat = 2

    /// A straight stroke along `line`: a pen at `pressure` leaning by `tilt`,
    /// or a mouse with neither, moving `speed` points a millisecond.
    private func stroke(_ medium: BrushMedium, size: Double = 16, set: [String: Double] = [:],
                        pressure: Double? = nil, tilt: CGPoint? = nil, speed: Double = 0.3,
                        seed: UInt32 = 9) -> BrushStroke {
        let settings = BrushSettings(medium: medium, values: ["size": size].merging(set) { $1 })
        let count = 75
        let length = Double(line.1.x - line.0.x)
        let samples = (0...count).map { i -> StrokeSample in
            let t = Double(i) / Double(count)
            return StrokeSample(point: CGPoint(x: Double(line.0.x) + length * t, y: Double(line.0.y)),
                                pressure: pressure, tilt: tilt, ms: length * t / speed)
        }
        return BrushStroke(samples: samples, settings: settings, colorHex: "#1E1E1E", seed: seed)
    }

    private func render(_ s: BrushStroke) throws -> CGImage {
        try #require(PaintRasterizer.rasterize(PaintContent(strokes: [s]), size: box, scale: scale))
    }

    /// Width and darkness over the middle of the stroke.
    private func middle(_ s: BrushStroke, reach: CGFloat = 40) throws -> (width: Double, darkness: Double) {
        PaintMeasures.lineProfile(try render(s), from: CGPoint(x: 140, y: 60), to: CGPoint(x: 220, y: 60),
                                  reach: reach, scale: scale)
    }

    /// The mean coverage over the middle of the stroke's core: how much paint
    /// a person sees there from a step back.
    private func paint(_ s: BrushStroke, diameter: CGFloat) throws -> Double {
        PaintMeasures.meanCoreAlpha(try render(s), from: CGPoint(x: 140, y: 60), to: CGPoint(x: 220, y: 60),
                                    diameter: diameter, scale: scale)
    }

    // MARK: - Pressure

    @Test("Pressed harder, charcoal and chalk lay a wider and darker line", arguments: [
        BrushMedium.charcoal, .chalk,
    ])
    func dryPress(_ medium: BrushMedium) throws {
        let light = try middle(stroke(medium, pressure: 0.2))
        let heavy = try middle(stroke(medium, pressure: 0.95))
        #expect(heavy.width >= light.width * 1.4, "\(medium) width \(light.width) to \(heavy.width)")
        let lightPaint = try paint(stroke(medium, pressure: 0.2), diameter: 6)
        let heavyPaint = try paint(stroke(medium, pressure: 0.95), diameter: 6)
        #expect(heavyPaint >= lightPaint * 1.6, "\(medium) paint \(lightPaint) to \(heavyPaint)")
    }

    @Test("Pressed harder, crayon's wax reaches deeper into the paper")
    func crayonPress() throws {
        let light = try paint(stroke(.crayon, size: 12, pressure: 0.2), diameter: 6)
        let heavy = try paint(stroke(.crayon, size: 12, pressure: 0.95), diameter: 6)
        #expect(heavy >= light * 1.5, "\(light) to \(heavy)")
    }

    @Test("Pressed harder, a round watercolour brush's belly spreads and oil's bristles splay", arguments: [
        BrushMedium.watercolour, .oil,
    ])
    func wetPress(_ medium: BrushMedium) throws {
        let light = try middle(stroke(medium, size: 20, pressure: 0.2), reach: 60)
        let heavy = try middle(stroke(medium, size: 20, pressure: 0.95), reach: 60)
        #expect(heavy.width >= light.width * 1.15, "\(medium) width \(light.width) to \(heavy.width)")
    }

    @Test("Pressed harder, the airbrush sprays more paint")
    func airbrushPress() throws {
        let light = try paint(stroke(.airbrush, size: 30, pressure: 0.2), diameter: 10)
        let heavy = try paint(stroke(.airbrush, size: 30, pressure: 0.95), diameter: 10)
        #expect(heavy >= light * 1.8, "\(light) to \(heavy)")
    }

    @Test("The plain round, the yardstick, paints one line however hard it is pressed")
    func roundIgnoresPress() throws {
        try PaintRasterizer.$plainRound.withValue(true) {
            // The plain round has no medium of its own; the yardstick is the
            // stamp alone, so the airbrush's flat response stands in for it.
            let light = try middle(stroke(.airbrush, pressure: 0.2))
            let heavy = try middle(stroke(.airbrush, pressure: 0.95))
            #expect(abs(heavy.width - light.width) < 0.6)
        }
    }

    // MARK: - Tilt

    @Test("Leaned, charcoal and chalk lay the side of the stick: a broad, paler band", arguments: [
        BrushMedium.charcoal, .chalk,
    ])
    func dryLean(_ medium: BrushMedium) throws {
        let upright = try middle(stroke(medium, pressure: 0.6))
        // Leaning across the stroke, so the side lies across it.
        let leaned = try middle(stroke(medium, pressure: 0.6, tilt: CGPoint(x: 0, y: 0.85)), reach: 60)
        // Chalk's side catches only the high tooth, so its band reads broken
        // and its half-strength width grows less than charcoal's shading.
        let bar = medium == .chalk ? 1.3 : 1.6
        #expect(leaned.width >= upright.width * bar, "\(medium) width \(upright.width) to \(leaned.width)")
        #expect(leaned.darkness < upright.darkness, "\(medium) darkness \(upright.darkness) to \(leaned.darkness)")
    }

    @Test("A chisel marker's nib turns to the lean: across the stroke it is broad, along it thin")
    func chiselTurns() throws {
        let chisel: [String: Double] = ["tip": 1]
        // The nib's long edge lies square to the lean.
        let broad = try middle(stroke(.marker, size: 20, set: chisel, pressure: 0.6, tilt: CGPoint(x: 0.85, y: 0)))
        let thin = try middle(stroke(.marker, size: 20, set: chisel, pressure: 0.6, tilt: CGPoint(x: 0, y: 0.85)))
        let upright = try middle(stroke(.marker, size: 20, set: chisel, pressure: 0.6))
        #expect(broad.width >= thin.width * 2.5, "broad \(broad.width), thin \(thin.width)")
        #expect(broad.width > upright.width && thin.width < upright.width,
                "upright at 45 degrees sits between: \(upright.width)")
    }

    @Test("A round marker leaned lays the side of its felt, wider across the lean")
    func roundMarkerLean() throws {
        let upright = try middle(stroke(.marker, size: 14, pressure: 0.6))
        let leaned = try middle(stroke(.marker, size: 14, pressure: 0.6, tilt: CGPoint(x: 0, y: 0.85)))
        #expect(leaned.width >= upright.width * 1.35, "\(upright.width) to \(leaned.width)")
        // Still one flat ink.
        let image = try render(stroke(.marker, size: 14, pressure: 0.6, tilt: CGPoint(x: 0, y: 0.85)))
        #expect(PaintMeasures.flatShare(image) >= PaintMeasures.markerFlatBar)
    }

    // MARK: - Speed

    @Test("A fast pen thins the line", arguments: [BrushMedium.charcoal, .watercolour, .pencil])
    func fastPen(_ medium: BrushMedium) throws {
        let size: Double = medium == .pencil ? 6 : 16
        let slow = try middle(stroke(medium, size: size, pressure: 0.6, speed: 0.2), reach: 50)
        let fast = try middle(stroke(medium, size: size, pressure: 0.6, speed: 6), reach: 50)
        #expect(fast.width <= slow.width * 0.88, "\(medium) \(slow.width) to \(fast.width)")
    }

    @Test("A fast mouse stroke is thinner than a slow one")
    func fastMouse() throws {
        let slow = try middle(stroke(.charcoal, speed: 0.2))
        let fast = try middle(stroke(.charcoal, speed: 5))
        #expect(fast.width <= slow.width * 0.88, "\(slow.width) to \(fast.width)")
    }

    // MARK: - The mouse's taper

    /// The stroke's width over a short stretch `at` points from its start.
    private func width(_ image: CGImage, at x: CGFloat, reach: CGFloat = 30) -> Double {
        PaintMeasures.lineProfile(image, from: CGPoint(x: x - 4, y: 60), to: CGPoint(x: x + 4, y: 60),
                                  reach: reach, scale: scale).width
    }

    @Test("A mouse stroke swells in from a point and tapers out to one, for the media that end in a point",
          arguments: [BrushMedium.charcoal, .chalk, .crayon, .watercolour])
    func mouseTaper(_ medium: BrushMedium) throws {
        let image = try render(stroke(medium, set: ["grain": 0]))
        let full = width(image, at: 180)
        let start = width(image, at: line.0.x + 5), end = width(image, at: line.1.x - 5)
        #expect(start < full * 0.7, "\(medium) starts \(start) of \(full)")
        #expect(end < full * 0.7, "\(medium) ends \(end) of \(full)")
        // A pen pressed steadily keeps its width to the very end: the taper is
        // the mouse's, a pen's own press lifts off.
        let pen = try render(stroke(medium, set: ["grain": 0], pressure: BrushDynamics.steadyPress))
        #expect(width(pen, at: line.1.x - 5) > width(pen, at: 180) * 0.75, "\(medium)")
    }
}
