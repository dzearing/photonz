import CoreGraphics
import Foundation
import PhotonzCore

// The marker and the airbrush (`docs/design/brushes.md`, decision 4).
//
// A marker is felt soaked in translucent ink: wherever the nib has been is one
// even colour, however often a stroke goes back over itself, and only a
// SEPARATE stroke darkens it, because the second layer of ink filters the
// light the first already filtered. So a stroke keeps the most any dab laid at
// each pixel (never the sum), and lands multiplied over the paint before it.
//
// An airbrush is a fine spray: each dab is a soft cloud of paint with fine
// droplets in it, and the spray keeps coming while the trigger is held, so
// paint builds up the longer the pointer stays (placement lays those dabs by
// time, `BrushPlacement.dwellInterval`).
//
// Both are shared by the stroke that lands (`PaintRasterizer`) and the stroke
// under the pointer (`PaintRasterizer.LiveMarker`), which hand over the same
// dabs in the same order, so what lands is what was seen.

// MARK: - The marker

struct MarkerStroke {
    /// The nib: round, or a chisel held at a fixed angle.
    let chisel: Bool
    /// How much of the light the ink takes at full coverage, 0...1: the
    /// stroke's Flow and Opacity together.
    let ink: Float
    let toPixels: CGAffineTransform
    let pixelsPerPoint: CGFloat
    private(set) var field: CoverageField

    /// Which way a chisel nib's long edge runs, in the layer's top-left
    /// points: lower left to upper right, the way a right hand holds one. A
    /// stroke along that edge is a thin line, one across it the nib's width.
    static let chiselAxis = CGVector(dx: 1 / 2.0.squareRoot(), dy: -1 / 2.0.squareRoot())
    /// How thick a chisel nib is, as a share of its width (the stroke's Size).
    static let chiselThickness: CGFloat = 0.3
    /// What a lean does to the nib (`BrushDynamics.response(for:)`).
    static let side = BrushDynamics.response(for: .marker).side

    /// Which way the chisel's long edge runs for a pen leaning `lean` (0...1)
    /// toward `toward`: square to the lean, turning there from the upright
    /// hold (`chiselAxis`) as the pen leans further. The edge has no head or
    /// tail, so the turn takes the nearer way round.
    static func nibAxis(lean: Double, toward: CGVector) -> CGVector {
        guard lean > 0 else { return chiselAxis }
        var square = CGVector(dx: toward.dy, dy: -toward.dx)
        if square.dx * chiselAxis.dx + square.dy * chiselAxis.dy < 0 {
            square = CGVector(dx: -square.dx, dy: -square.dy)
        }
        let t = CGFloat(lean)
        let x = chiselAxis.dx + (square.dx - chiselAxis.dx) * t
        let y = chiselAxis.dy + (square.dy - chiselAxis.dy) * t
        let length = hypot(x, y)
        guard length > 1e-6 else { return square }
        return CGVector(dx: x / length, dy: y / length)
    }

    /// How much light a marker's ink takes at a Flow of 0...100: never
    /// nothing, never quite opaque, the way a felt tip always lets the paper
    /// through.
    static func ink(flow: Double) -> Float {
        Float(0.2 + 0.75 * min(1, max(0, flow / 100)))
    }

    init(settings: BrushSettings, colour: RGBA, toPixels: CGAffineTransform, limit: PixelBox) {
        chisel = settings.value("tip") >= 0.5
        ink = Self.ink(flow: settings.value("flow")) * Float(settings.opacity / 100) * Float(colour.a)
        self.toPixels = toPixels
        pixelsPerPoint = hypot(toPixels.a, toPixels.b)
        field = CoverageField(limit: limit)
    }

    /// Lays one dab of the nib and hands back the pixels it touched. A pixel
    /// keeps the most any dab gave it, so the stroke stays flat.
    mutating func mark(_ dab: BrushDab) -> PixelBox {
        let centre = dab.center.applying(toPixels)
        let half = max(dab.diameter / 2 * pixelsPerPoint, 0.5)
        // A pen leaned: a chisel nib turns its long edge square to the lean,
        // the way the hand holds it; a round one lays the side of its felt, a
        // little longer the way it leans.
        let (lean, leanAxis) = BrushDynamics.lean(dab.tilt)
        let side = 1 + CGFloat(Self.side.long * lean)
        let box = PixelBox.around(centre, radius: half * (chisel ? 1 : side) + 2).intersection(field.limit)
        guard !box.isEmpty else { return .empty }
        field.ensure(box)
        // A felt edge: crisp, with a hair of give, never a soft brush.
        let feather = max(1, 0.4 * pixelsPerPoint)
        let thick = max(half * Self.chiselThickness, 0.5)
        let corner = thick * 0.5
        let axis = Self.nibAxis(lean: lean, toward: leanAxis)
        for y in box.minY..<box.maxY {
            for x in box.minX..<box.maxX {
                let dx = CGFloat(x) + 0.5 - centre.x, dy = CGFloat(y) + 0.5 - centre.y
                let distance: CGFloat
                if chisel {
                    // A rounded box: the nib's width along its axis, its
                    // thickness across.
                    let u = abs(dx * axis.dx + dy * axis.dy) - (half - corner)
                    let v = abs(-dx * axis.dy + dy * axis.dx) - (thick - corner)
                    distance = hypot(max(u, 0), max(v, 0)) + min(max(u, v), 0) - corner
                } else if lean > 0 {
                    // An ellipse, long along the lean.
                    let u = (dx * leanAxis.dx + dy * leanAxis.dy) / side
                    let v = -dx * leanAxis.dy + dy * leanAxis.dx
                    distance = hypot(u, v) - half
                } else {
                    distance = hypot(dx, dy) - half
                }
                let cover = Float(min(1, max(0, 0.5 - distance / feather)))
                guard cover > 0 else { continue }
                let i = field.index(x, y)
                if cover > field.values[i] { field.values[i] = cover }
            }
        }
        return box
    }

    /// The ink over one pixel `under` (premultiplied, 0...1), as the pixel to
    /// lay OVER it with plain source-over: the multiply of the ink and what is
    /// there. Laid over `under` it gives exactly the multiply, which is what
    /// lets the live overlay, laid over the canvas, show what lands.
    @inline(__always)
    private func over(_ cover: Float, colour: (Float, Float, Float),
                      under: (Float, Float, Float, Float)) -> (Float, Float, Float, Float) {
        let a = cover * ink
        // Multiply, then source-over: a·C·(1 − Da + D) is what the ink
        // passes of the light the paint below already let through.
        let keep = 1 - under.3
        return (a * colour.0 * (keep + under.0), a * colour.1 * (keep + under.1),
                a * colour.2 * (keep + under.2), a)
    }

    /// Lays the stroke over `plane` in `colour`: a stroke that lands.
    func composite(into plane: PixelPlane, colour: RGBA) {
        let box = field.box.intersection(plane.box)
        guard !box.isEmpty else { return }
        let c = (Float(colour.r), Float(colour.g), Float(colour.b))
        for y in box.minY..<box.maxY {
            for x in box.minX..<box.maxX {
                let cover = field.values[field.index(x, y)]
                guard cover > 0 else { continue }
                let o = plane.offset(x, y)
                let d = (Float(plane.data[o]) / 255, Float(plane.data[o + 1]) / 255,
                         Float(plane.data[o + 2]) / 255, Float(plane.data[o + 3]) / 255)
                let s = over(cover, colour: c, under: d)
                let keep = 1 - s.3
                plane.data[o] = byte((s.0 + d.0 * keep) * 255)
                plane.data[o + 1] = byte((s.1 + d.1 * keep) * 255)
                plane.data[o + 2] = byte((s.2 + d.2 * keep) * 255)
                plane.data[o + 3] = byte((s.3 + d.3 * keep) * 255)
            }
        }
    }

    /// Writes what the stroke lays over `under` (the paint it lands on, in
    /// the overlay's pixels, or nothing) into `box` of `overlay`, in place of
    /// what was there. Shown over the canvas at full strength.
    func replace(_ box: PixelBox, in overlay: PixelPlane, under: PixelPlane?, colour: RGBA) {
        let box = box.intersection(overlay.box)
        guard !box.isEmpty else { return }
        let c = (Float(colour.r), Float(colour.g), Float(colour.b))
        for y in box.minY..<box.maxY {
            for x in box.minX..<box.maxX {
                var d: (Float, Float, Float, Float) = (0, 0, 0, 0)
                if let under, x < under.width, y < under.height {
                    let u = under.offset(x, y)
                    d = (Float(under.data[u]) / 255, Float(under.data[u + 1]) / 255,
                         Float(under.data[u + 2]) / 255, Float(under.data[u + 3]) / 255)
                }
                let s = over(field.value(x, y), colour: c, under: d)
                let o = overlay.offset(x, y)
                overlay.data[o] = byte(s.0 * 255)
                overlay.data[o + 1] = byte(s.1 * 255)
                overlay.data[o + 2] = byte(s.2 * 255)
                overlay.data[o + 3] = byte(s.3 * 255)
            }
        }
    }
}

// MARK: - The airbrush

struct AirbrushStroke {
    /// How hard it sprays, 0...1: the stroke's Flow.
    let flow: Float
    /// How wide the mist reaches out from the line, 0...1: the stroke's
    /// Spread. Narrow, the mist hugs the line inside a fine halo of droplets;
    /// wide, it fills the tip and feathers out to its rim.
    let spread: Float
    /// Fine mist to coarse spatter, 0...1: the stroke's Droplet Size.
    let droplet: Float
    let toPixels: CGAffineTransform
    let pixelsPerPoint: CGFloat
    private(set) var field: CoverageField
    private var scatter: Scatter

    /// Paint per dab at full Flow and press: a pass at the default Flow
    /// leaves a light veil, and holding still builds it toward solid in
    /// about a second.
    static let sprayPerDab: Float = 0.55

    init(settings: BrushSettings, seed: UInt32, toPixels: CGAffineTransform, limit: PixelBox) {
        flow = Float(settings.value("flow") / 100)
        spread = Float(settings.value("spread") / 100)
        droplet = Float(settings.value("droplet") / 100)
        self.toPixels = toPixels
        pixelsPerPoint = hypot(toPixels.a, toPixels.b)
        field = CoverageField(limit: limit)
        scatter = Scatter(seed: seed)
    }

    /// One pair of numbers from a bell curve around 0, spread 1.
    private mutating func bell() -> (Float, Float) {
        let u = max(scatter.unit(), 1e-6), v = scatter.unit()
        let r = (-2 * log(u)).squareRoot()
        return (r * cos(2 * .pi * v), r * sin(2 * .pi * v))
    }

    /// How wide the mist's bell is, as a share of the tip's radius.
    var sigma: Float { 0.15 + 0.21 * spread }

    /// Where a dab's droplets land, how big each is in points and how much
    /// paint it carries, rolled from the stroke's seed whatever happens, so
    /// the live stroke and the landed one spray the same ones even when a dab
    /// falls off the bitmap.
    private mutating func droplets(_ dab: BrushDab, radius: CGFloat, amount: Float,
                                   press: Float) -> [(CGPoint, CGFloat, Float)] {
        // Fine mist is many tiny specks, coarse spatter fewer and bigger.
        let count = Int(((dab.diameter * 1.2 + 8) * CGFloat(2.4 - 1.9 * droplet)).rounded())
        let size = CGFloat(0.12 + 0.75 * droplet * droplet)
        let ink = amount * (2.6 + 1.2 * droplet)
        var drops: [(CGPoint, CGFloat, Float)] = []
        drops.reserveCapacity(count + 8)
        for _ in 0..<count {
            let (gx, gy) = bell()
            // Most droplets ride the mist, a little wider than it; some are
            // overspray thrown anywhere over the cone, the fine halo at the
            // edge of a real airbrush line.
            let halo = scatter.unit() < 0.3
            let reach = 0.95 * scatter.unit().squareRoot(), turn = 2 * Float.pi * scatter.unit()
            let width = sigma * 1.25
            let x = halo ? reach * cos(turn) : gx * width
            let y = halo ? reach * sin(turn) : gy * width
            let grow = CGFloat(0.6 + 0.8 * scatter.unit())
            let weight = 0.5 + scatter.unit()
            guard x * x + y * y < 0.94 else { continue }
            drops.append((CGPoint(x: dab.center.x + CGFloat(x) * radius, y: dab.center.y + CGFloat(y) * radius),
                          size * grow, min(1, ink * weight)))
        }
        // A heavy flow pressed hard spatters: a few big drops thrown out past
        // the mist, landing thick.
        let heavy = max(0, flow * press - 0.5) / 0.5
        let thrown = heavy * (1.2 + 3 * droplet) + scatter.unit()
        for _ in 0..<Int(thrown) {
            let reach = 0.3 + 0.62 * scatter.unit().squareRoot(), turn = 2 * Float.pi * scatter.unit()
            let grow = CGFloat(0.6 + 0.8 * scatter.unit())
            drops.append((CGPoint(x: dab.center.x + CGFloat(reach * cos(turn)) * radius,
                                  y: dab.center.y + CGFloat(reach * sin(turn)) * radius),
                          CGFloat(0.45 + 0.8 * droplet) * grow, 0.85))
        }
        return drops
    }

    /// Sprays one dab and hands back the pixels it touched. Paint adds up the
    /// way spray does: each layer covers a share of what is still bare.
    mutating func mark(_ dab: BrushDab) -> PixelBox {
        let radiusPoints = max(dab.diameter / 2, 0.25)
        // Pressing harder opens the needle: more paint. The dab's share of
        // the spray is how long the nozzle was over it (a fast pass is light).
        let press = Float(min(1, max(0, dab.pressure)))
        let amount = Self.sprayPerDab * flow * (0.2 + 0.8 * press) * Float(min(1, max(0, dab.spray)))
        let drops = droplets(dab, radius: radiusPoints, amount: amount, press: press)
        let centre = dab.center.applying(toPixels)
        let radius = radiusPoints * pixelsPerPoint
        let box = PixelBox.around(centre, radius: radius + 2).intersection(field.limit)
        guard !box.isEmpty, amount > 0 else { return .empty }
        field.ensure(box)
        // The mist: a bell of paint around the line, densest in the middle,
        // gone before the rim. Coarse spatter carries more of the paint in
        // its drops and less as mist.
        let mist = amount * (0.8 - 0.45 * droplet)
        let spreadOut = 1 / (2 * sigma * sigma)
        let inverse = 1 / Float(radius)
        for y in box.minY..<box.maxY {
            let dy = (Float(y) + 0.5 - Float(centre.y)) * inverse
            for x in box.minX..<box.maxX {
                let dx = (Float(x) + 0.5 - Float(centre.x)) * inverse
                let r2 = dx * dx + dy * dy
                guard r2 < 1 else { continue }
                let laid = mist * exp(-r2 * spreadOut) * (1 - smoothstep(0.45, 1, r2.squareRoot()))
                guard laid > 0.0004 else { continue }
                let i = field.index(x, y)
                field.values[i] = 1 - (1 - field.values[i]) * (1 - laid)
            }
        }
        // The droplets: specks of the same paint, the grain of a spray.
        for (point, size, ink) in drops {
            let at = point.applying(toPixels)
            let r = max(size * pixelsPerPoint, 0.35)
            let speck = PixelBox.around(at, radius: r + 1).intersection(field.box)
            guard !speck.isEmpty else { continue }
            for y in speck.minY..<speck.maxY {
                for x in speck.minX..<speck.maxX {
                    let d = hypot(CGFloat(x) + 0.5 - at.x, CGFloat(y) + 0.5 - at.y)
                    let cover = Float(min(1, max(0, r + 0.5 - d)))
                    guard cover > 0 else { continue }
                    let laid = min(1, ink * cover)
                    let i = field.index(x, y)
                    field.values[i] = 1 - (1 - field.values[i]) * (1 - laid)
                }
            }
        }
        return box
    }

    /// Lays the spray over `plane` in `colour`, at `opacity`: a stroke that
    /// lands.
    func composite(into plane: PixelPlane, colour: RGBA, opacity: Float) {
        let box = field.box.intersection(plane.box)
        guard !box.isEmpty else { return }
        let alpha = Float(colour.a) * opacity
        let r = Float(colour.r), g = Float(colour.g), b = Float(colour.b)
        for y in box.minY..<box.maxY {
            for x in box.minX..<box.maxX {
                let a = field.values[field.index(x, y)] * alpha
                guard a > 0 else { continue }
                let o = plane.offset(x, y)
                let keep = 1 - a
                plane.data[o] = byte(r * a * 255 + Float(plane.data[o]) * keep)
                plane.data[o + 1] = byte(g * a * 255 + Float(plane.data[o + 1]) * keep)
                plane.data[o + 2] = byte(b * a * 255 + Float(plane.data[o + 2]) * keep)
                plane.data[o + 3] = byte(a * 255 + Float(plane.data[o + 3]) * keep)
            }
        }
    }

    /// Writes the spray in `colour` over `box` of `plane`, in place of what
    /// was there: the live overlay holds only this stroke, shown at its
    /// opacity.
    func replace(_ box: PixelBox, in plane: PixelPlane, colour: RGBA) {
        let box = box.intersection(plane.box)
        guard !box.isEmpty else { return }
        let alpha = Float(colour.a)
        let r = Float(colour.r), g = Float(colour.g), b = Float(colour.b)
        for y in box.minY..<box.maxY {
            for x in box.minX..<box.maxX {
                let a = field.value(x, y) * alpha
                let o = plane.offset(x, y)
                plane.data[o] = byte(r * a * 255)
                plane.data[o + 1] = byte(g * a * 255)
                plane.data[o + 2] = byte(b * a * 255)
                plane.data[o + 3] = byte(a * 255)
            }
        }
    }
}
