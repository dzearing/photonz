import CoreGraphics
import Foundation
import PhotonzCore

// Oil paint (`docs/design/brushes.md`, decision 4), in the spirit of Baxter et
// al., "IMPaSTo" (2004): a loaded bristle brush that carries colour.
//
// - The brush is a row of BRISTLES across its width, each with its own
//   reservoir: a colour, and how much paint it still holds. A stroke starts
//   with every bristle loaded by Load; each lays its paint down as it goes and
//   runs dry over a distance Load sets, the weaker bristles first, so the end
//   of a long stroke breaks into a dry brush's streaks.
// - Each bristle PICKS UP the paint already on the layer under it, by Smear:
//   its colour moves toward what it passed over, and it lays that colour on
//   past the place it found it, so a stroke across an earlier one drags the
//   earlier colour along and mixes it, then clears back to its own over a few
//   brush widths. Where it lands on paint, the two also mix in place.
// - Every pixel keeps a HEIGHT: the paint is thickest along each bristle and
//   thinner between them, piled into a rim at the stroke's sides where the
//   brush pushed it. The height is lit from the upper left when the stroke is
//   laid down, so ridges catch the light and grooves fall into shade.
//
// Paint is only ever laid over what is there, never scraped off, so the live
// overlay (which lies over the canvas) shows exactly what lands. Shared by the
// stroke that lands (`PaintRasterizer`) and the stroke under the pointer
// (`PaintRasterizer.LiveMarker`), which hand over the same dabs in the same
// order and read the same paint under them.

struct OilStroke {
    let toPixels: CGAffineTransform
    let pixelsPerPoint: CGFloat
    /// The stroke's own colour, unpremultiplied, 0...1.
    let own: (Float, Float, Float)
    /// Opacity and the colour's own alpha.
    let strength: Float
    /// The settings, 0...1.
    let load: Float
    let smear: Float
    /// How far a fully loaded bristle paints before it runs dry, in points.
    let reach: CGFloat
    /// How far a colour picked up is carried before the brush clears back to
    /// its own, in points.
    let carry: CGFloat
    /// How thick the paint stands, in points: a fuller brush lays it thicker.
    let thickness: Float
    private var bristles: [Bristle]
    /// Where each bristle's band ends across the brush, 0...1, left to right:
    /// bristles are not all as thick, so the streaks are uneven.
    private let bands: [Float]
    /// Which way the brush is moving, in pixels, eased.
    private var heading: CGVector?
    private var last: CGPoint?
    /// The stroke's first dab, held until the brush has moved and its heading
    /// is known, so the stroke starts square to the way it goes.
    private var first: BrushDab?
    private(set) var red: CoverageField
    private(set) var green: CoverageField
    private(set) var blue: CoverageField
    private(set) var cover: CoverageField
    private(set) var height: CoverageField

    struct Bristle {
        var r: Float, g: Float, b: Float
        /// How much paint it still holds, 0...1.
        var paint: Float
        /// How hard it presses, so how much it lays: some bristles always
        /// carry more than their neighbours, which is what streaks a stroke.
        let press: Float
        /// How far it lasts against the others before running dry.
        let endurance: Float
        /// How proud its ridge stands.
        let lift: Float
        /// A touch lighter or darker than the rest: the paint on a brush is
        /// never quite one even colour.
        let tint: Float
    }

    /// How a flat brush's footprint is shaped: it reaches along the stroke,
    /// either side of the dab, this share of half its width, pressing hardest
    /// in its middle (a smooth bell, so however the dabs fall every pixel gets
    /// the same paint and no seams cross the stroke). Every bristle sweeps the
    /// same length, so a stroke is evenly covered edge to edge and squared off
    /// where it starts and ends, as a flat brush is.
    static let footprint: CGFloat = 0.6

    /// How far a brush loaded at 0...100 paints before it runs dry, in brush
    /// widths: three at an empty brush, about twenty at the default 70.
    static func reach(load: Double) -> Double {
        3 + 0.25 * min(100, max(0, load))
    }

    init(settings: BrushSettings, colour: RGBA, seed: UInt32, toPixels: CGAffineTransform, limit: PixelBox) {
        self.toPixels = toPixels
        pixelsPerPoint = hypot(toPixels.a, toPixels.b)
        own = (Float(colour.r), Float(colour.g), Float(colour.b))
        strength = Float(settings.opacity / 100) * Float(colour.a)
        load = Float(settings.value("load") / 100)
        smear = Float(settings.value("smear") / 100)
        let size = CGFloat(max(1, settings.size))
        reach = size * CGFloat(Self.reach(load: settings.value("load")))
        carry = size * (0.6 + 3.4 * CGFloat(smear))
        thickness = 0.35 + 0.65 * load
        // A bristle about every point across, never fewer than five.
        let count = min(160, max(5, Int((size / 1.1).rounded())))
        var scatter = Scatter(seed: seed ^ 0x0115)
        // Bristles clump: neighbours share part of their lift and press, so
        // the ridges come in bands of a few bristles, not a regular comb.
        var clump: Float = scatter.unit()
        bristles = (0..<count).map { k in
            if k % 3 == 0 { clump = 0.5 * clump + 0.5 * scatter.unit() }
            let edge = Float(min(k, count - 1 - k))
            // The outermost bristles splay and carry less.
            let outer: Float = edge < 1 ? 0.7 : edge < 2 ? 0.88 : 1
            return Bristle(r: Float(colour.r), g: Float(colour.g), b: Float(colour.b), paint: 1,
                           press: (0.7 + 0.15 * clump + 0.15 * scatter.unit()) * outer,
                           endurance: 0.55 + 0.9 * scatter.unit(),
                           lift: 0.2 + 0.8 * (0.6 * clump + 0.4 * scatter.unit()),
                           tint: 0.95 + 0.1 * scatter.unit())
        }
        let widths = (0..<count).map { _ in 0.35 + 1.3 * scatter.unit() }
        let total = widths.reduce(0, +)
        var edge: Float = 0
        bands = widths.map { width in
            edge += width / total
            return edge
        }
        red = CoverageField(limit: limit)
        green = CoverageField(limit: limit)
        blue = CoverageField(limit: limit)
        cover = CoverageField(limit: limit)
        height = CoverageField(limit: limit)
    }

    /// Lays one dab of the brush, picking up from `under` (the layer's paint
    /// before this stroke, in the same pixels, or nothing), and hands back
    /// the pixels it touched.
    mutating func mark(_ dab: BrushDab, under: PixelPlane?) -> PixelBox {
        let centre = dab.center.applying(toPixels)
        guard let last else {
            first = dab
            self.last = centre
            return .empty
        }
        // The brush's heading and how far it has come since the last dab.
        let dx = centre.x - last.x, dy = centre.y - last.y
        let step = hypot(dx, dy)
        guard step > 1e-4 else { return heading == nil ? .empty : lay(dab, under: under) }
        let way = CGVector(dx: dx / step, dy: dy / step)
        if let heading {
            let x = heading.dx * 0.85 + way.dx * 0.15, y = heading.dy * 0.85 + way.dy * 0.15
            let norm = max(hypot(x, y), 1e-6)
            self.heading = CGVector(dx: x / norm, dy: y / norm)
        } else {
            heading = way
        }
        self.last = centre
        var touched = PixelBox.empty
        if let held = first {
            first = nil
            touched = lay(held, under: under)
        }
        spend(step / pixelsPerPoint)
        return touched.union(lay(dab, under: under))
    }

    /// The first dab, if the brush never moved from it (a click): laid
    /// heading along, as a dab would be.
    mutating func finish(under: PixelPlane?) -> PixelBox {
        guard let held = first else { return .empty }
        first = nil
        // Pressed down, a brush leaves its whole print, not one pass of it.
        var touched = PixelBox.empty
        for _ in 0..<4 { touched = touched.union(lay(held, under: under)) }
        return touched
    }

    /// Lays one dab along the heading.
    private mutating func lay(_ dab: BrushDab, under: PixelPlane?) -> PixelBox {
        let centre = dab.center.applying(toPixels)
        let along = heading ?? CGVector(dx: 1, dy: 0)
        let across = CGVector(dx: -along.dy, dy: along.dx)
        let radius = max(dab.diameter / 2 * pixelsPerPoint, 0.75)
        let length = max(radius * Self.footprint, 0.75)
        let box = PixelBox.around(centre, radius: radius + 2).intersection(red.limit)
        guard !box.isEmpty else { return .empty }
        for field in [\OilStroke.red, \.green, \.blue, \.cover, \.height] { self[keyPath: field].ensure(box) }
        let count = bristles.count
        let press = Float(min(1, 0.55 + dab.pressure))
        let rim = Float(0.25)
        // Every pixel's paint depends only on that pixel and the bristles as
        // they were when the dab began, so the rows are laid side by side
        // (`PixelBands`). What each bristle passed over is added up after, a
        // pixel at a time in the order it always was, so the sums round the
        // same and the brush picks up exactly what it did.
        let width = box.width
        var passed = [Float](repeating: 0, count: box.width * box.height * 5)
        var bands = [Int32](repeating: -1, count: box.width * box.height)
        var held = (CoverageField(limit: red.limit), CoverageField(limit: red.limit), CoverageField(limit: red.limit),
                    CoverageField(limit: red.limit), CoverageField(limit: red.limit))
        swap(&held.0, &red); swap(&held.1, &green); swap(&held.2, &blue); swap(&held.3, &cover); swap(&held.4, &height)
        let reader = self
        swap(&held.0, &red); swap(&held.1, &green); swap(&held.2, &blue); swap(&held.3, &cover); swap(&held.4, &height)
        let fieldBox = red.box
        red.values.withUnsafeMutableBufferPointer { r in
        green.values.withUnsafeMutableBufferPointer { g in
        blue.values.withUnsafeMutableBufferPointer { b in
        cover.values.withUnsafeMutableBufferPointer { c in
        height.values.withUnsafeMutableBufferPointer { h in
        passed.withUnsafeMutableBufferPointer { passedOut in
        bands.withUnsafeMutableBufferPointer { bandsOut in
            guard let r = r.baseAddress, let g = g.baseAddress, let b = b.baseAddress, let c = c.baseAddress,
                  let h = h.baseAddress, let passedOut = passedOut.baseAddress,
                  let bandsOut = bandsOut.baseAddress else { return }
            PixelBands.run(box, bands: PixelBands.count(for: box)) { _, minRow, maxRow in
                for y in minRow..<maxRow {
                    for x in box.minX..<box.maxX {
                        let dx = CGFloat(x) + 0.5 - centre.x, dy = CGFloat(y) + 0.5 - centre.y
                        let u = (dx * across.dx + dy * across.dy) / radius
                        let v = (dx * along.dx + dy * along.dy) / length
                        // A pixel's soft edge: how far inside the footprint, in pixels.
                        guard abs(v) < 1 else { continue }
                        let w = Float(min(1, max(0, (1 - abs(u)) * radius + 0.5))) * (0.5 + 0.5 * Float(cos(.pi * v)))
                        guard w > 0 else { continue }
                        let (k, f) = reader.band(Float(min(0.9999, max(0, (u + 1) / 2))))
                        // Paint under the bristle, unpremultiplied, and how much.
                        var under4: (Float, Float, Float, Float) = (0, 0, 0, 0)
                        let slot = (y - box.minY) * width + (x - box.minX)
                        bandsOut[slot] = Int32(k)
                        passedOut[slot * 5] = w
                        if let under, x >= 0, y >= 0, x < under.width, y < under.height {
                            let o = under.offset(x, y)
                            under4 = (Float(under.data[o]) / 255, Float(under.data[o + 1]) / 255,
                                      Float(under.data[o + 2]) / 255, Float(under.data[o + 3]) / 255)
                            passedOut[slot * 5 + 1] = under4.0
                            passedOut[slot * 5 + 2] = under4.1
                            passedOut[slot * 5 + 3] = under4.2
                            passedOut[slot * 5 + 4] = under4.3
                        } else {
                            // Nothing under it: counted, but finds nothing.
                            passedOut[slot * 5 + 4] = -1
                        }
                        let bristle = reader.bristles[k]
                        // The paint stands as high as the bristles it lies between,
                        // eased from one to the next, with a shallow groove where
                        // each bristle ran.
                        let next = reader.bristles[min(count - 1, k + (f < 0.5 ? 0 : 1))]
                        let prev = reader.bristles[max(0, k - (f < 0.5 ? 1 : 0))]
                        let t = f < 0.5 ? f + 0.5 : f - 0.5
                        let ease = 0.5 - 0.5 * cos(Float.pi * t)
                        let lift = prev.lift + (next.lift - prev.lift) * ease
                        let ridge = 0.5 - 0.5 * cos(2 * Float.pi * f)
                        let flow = smoothstep(0.02, 0.5, bristle.paint) * (0.6 + 0.4 * bristle.press) * press
                        // A loaded brush covers solid; a dry one only along its bristles.
                        let laid = min(1, w * flow) * (1 - 0.6 * (1 - flow) * (1 - ridge))
                        guard laid > 0.0005 else { continue }
                        // Mixed in place with the wet paint it lands on.
                        var tint = (bristle.r * bristle.tint, bristle.g * bristle.tint, bristle.b * bristle.tint)
                        if under4.3 > 0.004 {
                            let mix = 0.4 * reader.smear * under4.3
                            tint.0 += mix * (under4.0 / under4.3 - tint.0)
                            tint.1 += mix * (under4.1 / under4.3 - tint.1)
                            tint.2 += mix * (under4.2 / under4.3 - tint.2)
                        }
                        let i = (y - fieldBox.minY) * fieldBox.width + (x - fieldBox.minX)
                        let keep = 1 - laid
                        r[i] = tint.0 * laid + r[i] * keep
                        g[i] = tint.1 * laid + g[i] * keep
                        b[i] = tint.2 * laid + b[i] * keep
                        c[i] = laid + c[i] * keep
                        // The paint pushed aside piles up at the stroke's sides.
                        let side = rim * smoothstep(0.8, 0.97, Float(abs(u))) * (1 - smoothstep(0.97, 1, Float(abs(u))))
                        let target = reader.thickness * ((0.65 + 0.35 * ridge) * lift * (0.45 + 0.55 * flow) + side)
                        h[i] += laid * (target - h[i])
                    }
                }
            }
        }}}}}}}
        // What each bristle passed over this dab, to pick up once it is done.
        var weight = [Float](repeating: 0, count: count)
        var found = [Float](repeating: 0, count: count * 4)
        for slot in bands.indices {
            let k = Int(bands[slot])
            guard k >= 0 else { continue }
            let w = passed[slot * 5]
            weight[k] += w
            guard passed[slot * 5 + 4] >= 0 else { continue }
            found[k * 4] += w * passed[slot * 5 + 1]
            found[k * 4 + 1] += w * passed[slot * 5 + 2]
            found[k * 4 + 2] += w * passed[slot * 5 + 3]
            found[k * 4 + 3] += w * passed[slot * 5 + 4]
        }
        pickUp(weight: weight, found: found)
        return box
    }

    /// Which bristle's band a place across the brush (0...1) falls in, and
    /// how far across that band, 0...1.
    @inline(__always)
    private func band(_ across: Float) -> (Int, Float) {
        var low = 0, high = bands.count - 1
        while low < high {
            let mid = (low + high) / 2
            if bands[mid] > across { high = mid } else { low = mid + 1 }
        }
        let start = low == 0 ? 0 : bands[low - 1]
        return (low, min(1, max(0, (across - start) / max(bands[low] - start, 1e-6))))
    }

    /// Each bristle runs down by the distance the brush moved, and the colour
    /// it picked up wears off toward its own.
    private mutating func spend(_ moved: CGFloat) {
        guard moved > 0 else { return }
        let used = Float(moved / reach)
        let clear = Float(min(1, moved / carry))
        for k in bristles.indices {
            bristles[k].paint = max(0, bristles[k].paint - used / bristles[k].endurance)
            bristles[k].r += clear * (own.0 - bristles[k].r)
            bristles[k].g += clear * (own.1 - bristles[k].g)
            bristles[k].b += clear * (own.2 - bristles[k].b)
        }
    }

    /// Each bristle takes on some of the paint it passed over, by Smear, and
    /// is reloaded a little by it.
    private mutating func pickUp(weight: [Float], found: [Float]) {
        guard smear > 0 else { return }
        for k in bristles.indices where weight[k] > 0 {
            let alpha = found[k * 4 + 3]
            guard alpha > 0.001 else { continue }
            let share = alpha / weight[k]
            let rate = 0.3 * smear * share
            bristles[k].r += rate * (found[k * 4] / alpha - bristles[k].r)
            bristles[k].g += rate * (found[k * 4 + 1] / alpha - bristles[k].g)
            bristles[k].b += rate * (found[k * 4 + 2] / alpha - bristles[k].b)
            bristles[k].paint = min(1, bristles[k].paint + 0.03 * smear * share)
        }
    }

    // MARK: - Laying it down, lit

    /// Where the light comes from: the upper left, high, in top-left pixels
    /// with z toward the viewer.
    private static let light: (Float, Float, Float) = {
        let x: Float = -0.5, y: Float = -0.6, z: Float = 0.62
        let n = (x * x + y * y + z * z).squareRoot()
        return (x / n, y / n, z / n)
    }()
    /// Halfway between the light and the eye, for the highlight.
    private static let halfway: (Float, Float, Float) = {
        let l = light
        let x = l.0, y = l.1, z = l.2 + 1
        let n = (x * x + y * y + z * z).squareRoot()
        return (x / n, y / n, z / n)
    }()

    /// The stroke's pixel at (x, y), premultiplied and lit: its paint shaded
    /// by the slope of its height, with a highlight where a ridge faces the
    /// light.
    @inline(__always)
    private func lit(_ x: Int, _ y: Int) -> (Float, Float, Float, Float) {
        let a = cover.value(x, y)
        guard a > 0.002 else { return (0, 0, 0, 0) }
        // The slope in points per point, from the neighbours' heights.
        let ppp = Float(pixelsPerPoint)
        let hx = (height.value(x + 1, y) - height.value(x - 1, y)) * 0.5 * ppp
        let hy = (height.value(x, y + 1) - height.value(x, y - 1)) * 0.5 * ppp
        let bump: Float = 1.2
        let nx = -hx * bump, ny = -hy * bump
        let norm = (nx * nx + ny * ny + 1).squareRoot()
        let l = Self.light, h = Self.halfway
        let facing = (nx * l.0 + ny * l.1 + l.2) / norm
        // One on flat paint; brighter toward the light, darker away.
        let shade = max(0.4, 1 + 0.9 * (facing - l.2))
        let gloss = max(0, (nx * h.0 + ny * h.1 + h.2) / norm)
        let shine = 0.22 * pow(gloss, 28) * a
        let s = strength
        return (min(a, red.value(x, y) * shade + shine) * s, min(a, green.value(x, y) * shade + shine) * s,
                min(a, blue.value(x, y) * shade + shine) * s, a * s)
    }

    /// Lays the stroke over `plane`: a stroke that lands.
    func composite(into plane: PixelPlane) {
        let box = cover.box.intersection(plane.box)
        guard !box.isEmpty else { return }
        PixelBands.run(box, bands: PixelBands.count(for: box)) { _, minRow, maxRow in
            for y in minRow..<maxRow {
                for x in box.minX..<box.maxX {
                    let s = lit(x, y)
                    guard s.3 > 0 else { continue }
                    let o = plane.offset(x, y)
                    let keep = 1 - s.3
                    plane.data[o] = byte(s.0 * 255 + Float(plane.data[o]) * keep)
                    plane.data[o + 1] = byte(s.1 * 255 + Float(plane.data[o + 1]) * keep)
                    plane.data[o + 2] = byte(s.2 * 255 + Float(plane.data[o + 2]) * keep)
                    plane.data[o + 3] = byte(s.3 * 255 + Float(plane.data[o + 3]) * keep)
                }
            }
        }
    }

    /// Writes the stroke as it now stands into `box` of `overlay` (and a
    /// pixel round it, whose light the box's heights change), in place of
    /// what was there. Shown over the canvas at full strength.
    func replace(_ box: PixelBox, in overlay: PixelPlane) {
        let grown = PixelBox(minX: box.minX - 1, minY: box.minY - 1, maxX: box.maxX + 1, maxY: box.maxY + 1)
            .intersection(overlay.box).intersection(cover.limit)
        guard !grown.isEmpty else { return }
        PixelBands.run(grown, bands: PixelBands.count(for: grown)) { _, minRow, maxRow in
            for y in minRow..<maxRow {
                for x in grown.minX..<grown.maxX {
                    let s = lit(x, y)
                    let o = overlay.offset(x, y)
                    overlay.data[o] = byte(s.0 * 255)
                    overlay.data[o + 1] = byte(s.1 * 255)
                    overlay.data[o + 2] = byte(s.2 * 255)
                    overlay.data[o + 3] = byte(s.3 * 255)
                }
            }
        }
    }
}

/// The tail of a live stroke (`LiveMarker`): drawn as if the stroke ended where
/// the pointer is, then taken back on the next move. The checkpoint is the
/// stroke apart from its fields, which keep what the tail wrote instead, so
/// neither copies a field the size of the stroke.
extension OilStroke {
    mutating func beginTail() -> OilStroke {
        var held = [CoverageField(limit: red.limit), CoverageField(limit: green.limit), CoverageField(limit: blue.limit), CoverageField(limit: cover.limit), CoverageField(limit: height.limit)]
        swap(&held[0], &red)
        swap(&held[1], &green)
        swap(&held[2], &blue)
        swap(&held[3], &cover)
        swap(&held[4], &height)
        let checkpoint = self
        swap(&held[0], &red)
        swap(&held[1], &green)
        swap(&held[2], &blue)
        swap(&held[3], &cover)
        swap(&held[4], &height)
        red.record()
        green.record()
        blue.record()
        cover.record()
        height.record()
        return checkpoint
    }

    mutating func takeBackTail(to checkpoint: OilStroke) {
        red.rollBack()
        green.rollBack()
        blue.rollBack()
        cover.rollBack()
        height.rollBack()
        var held = [CoverageField(limit: red.limit), CoverageField(limit: green.limit), CoverageField(limit: blue.limit), CoverageField(limit: cover.limit), CoverageField(limit: height.limit)]
        swap(&held[0], &red)
        swap(&held[1], &green)
        swap(&held[2], &blue)
        swap(&held[3], &cover)
        swap(&held[4], &height)
        self = checkpoint
        swap(&held[0], &red)
        swap(&held[1], &green)
        swap(&held[2], &blue)
        swap(&held[3], &cover)
        swap(&held[4], &height)
    }

    mutating func keepTail() {
        red.keep()
        green.keep()
        blue.keep()
        cover.keep()
        height.keep()
    }
}
