import CoreGraphics
import Foundation
import PhotonzCore

// Watercolour (`docs/design/brushes.md`, decision 4), after Curtis et al.,
// "Computer-Generated Watercolor" (SIGGRAPH 1997), simplified to what runs
// under the pointer: no fluid is simulated, but what the simulation produces
// is built from fields that a dab can update on its own.
//
// - The WET AREA is how far the water reached: the brush's own path, crept out
//   past it by the Bleed along irregular fingers, and, where the brush went
//   into a wash that is still wet, flooded on through that wash (a bloom).
//   Each pixel keeps how deep inside the wet area it is, the most any dab gave
//   it, so a stroke is one wash however often it goes over itself.
// - The PIGMENT laid is a thin wash, thinner the further the water carried it
//   from the brush, and POOLED darker in a band just inside the wet area's
//   edge, where the water evaporated first and drew pigment after it (edge
//   darkening). A front that bled into damp paper is feathered instead; the
//   front of a bloom is crisp and dark (a backrun's cauliflower edge).
// - GRANULATION settles pigment into the paper's pits (`PaperGrain`, the same
//   paper the dry media catch on), and a DRY brush (low Wetness) touches only
//   the paper's tooth and skips across the pits.
// - A stroke lands MULTIPLIED over the paint before it on the layer, the way a
//   transparent glaze filters what is under it, so crossing strokes deepen.
//
// The one departure, written in the design doc: a real bloom also lifts the
// earlier wash's pigment out of its middle. Paint here is only ever laid, never
// lifted, so the live overlay (which lies over the canvas) can show exactly
// what lands; the bloom is the new paint flooding through the wet wash with a
// pale inside and a dark ragged front.
//
// Shared by the stroke that lands (`PaintRasterizer`) and the stroke under the
// pointer (`PaintRasterizer.LiveMarker`), which hand over the same dabs in the
// same order, the same earlier wet washes, and the same pixels.

/// An earlier stroke's wash that was still wet when a later stroke began, and
/// how wet, 0...1.
struct WetWash {
    let wash: WatercolourStroke
    let wetness: Float
}

struct WatercolourStroke {
    let toPixels: CGAffineTransform
    let toPoints: CGAffineTransform
    let pixelsPerPoint: CGFloat
    /// The stroke's settings, 0...1.
    let wetness: Float
    let bleed: Float
    let granulation: Float
    /// How strong the paint is: Opacity and the colour's own alpha.
    let strength: Float
    /// The tip's radius, in pixels, that depths are measured in.
    let radius: CGFloat
    /// How far the water can creep past the brush along a finger, as a share
    /// of the radius: the Bleed, more of it the wetter the brush.
    let creep: Float
    /// How far a bloom floods past the brush where it meets a wet wash.
    let flood: Float
    /// The furthest the water reaches past the brush anywhere, as a share of
    /// the radius: what a dab's box has to hold.
    let farthest: Float
    /// Fixed for this stroke, so its fingers and its bloom's edge are its own
    /// and the same on every render.
    let salt: UInt32
    /// The earlier washes that are still wet.
    let under: [WetWash]
    private(set) var field: WetField

    /// The most the water may reach past the brush, as a share of its radius
    /// (`BrushMedium.reach` holds one more than this).
    static let maximumReach: Float = 3.5

    init(settings: BrushSettings, colour: RGBA, seed: UInt32, toPixels: CGAffineTransform, limit: PixelBox,
         under: [WetWash]) {
        self.toPixels = toPixels
        toPoints = toPixels.inverted()
        pixelsPerPoint = hypot(toPixels.a, toPixels.b)
        wetness = Float(settings.value("wetness") / 100)
        bleed = Float(settings.value("bleed") / 100)
        granulation = Float(settings.value("granulation") / 100)
        strength = Float(settings.opacity / 100) * Float(colour.a)
        radius = max(CGFloat(settings.size) / 2 * pixelsPerPoint, 0.5)
        creep = bleed * wetness * 1.2
        flood = under.isEmpty ? 0 : 1.4 + 2.4 * wetness
        farthest = min(Self.maximumReach, 0.08 + creep * 1.4 + flood * 1.2)
        var scatter = Scatter(seed: seed)
        salt = UInt32(scatter.unit() * Float(1 << 20)) | 1
        self.under = under
        field = WetField(limit: limit)
    }

    /// The pixels a wet area of this stroke covers, 0...1: what a later
    /// stroke blooms into.
    func water(_ x: Int, _ y: Int) -> Float {
        min(1, field.water(x, y))
    }

    /// How far the water reaches past the brush at a pixel, as a share of the
    /// radius, how wet the earlier washes are there, and the paper and the
    /// wash's own unevenness there: worked out the first time a dab comes
    /// near the pixel, then kept in the pixel's fields (`v`, its six values).
    /// Everything it reads but the fields, apart from the stroke, so the
    /// bands of a dab can work it out side by side.
    struct Reacher {
        let toPoints: CGAffineTransform
        let radius: CGFloat
        let pixelsPerPoint: CGFloat
        let salt: UInt32
        let creep: Float
        let flood: Float
        let under: [WetWash]

        /// The most the water can reach where no earlier wash is wet: the
        /// wobble and the creep at their highest. Past it, a pixel with no
        /// wet wash under it can never be reached, so its reach is never
        /// worked out (a wash still wet under a big brush made every dab
        /// work out the bloom four radii round, 2026-10-27).
        var dryReach: Float { 0.07 + 0.025 + creep * 1.45 + 0.01 }

        /// Whether any earlier wash is wet at the pixel.
        @inline(__always)
        func isWet(_ x: Int, _ y: Int) -> Bool {
            for earlier in under where earlier.wash.water(x, y) * earlier.wetness > 0 { return true }
            return false
        }

        @inline(__always)
        func reach(_ x: Int, _ y: Int, _ v: UnsafeMutablePointer<Float>) -> Float {
            let kept = v[2]
            if kept > 0 { return kept - 1 }
            let p = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5).applying(toPoints)
            let px = Double(p.x), py = Double(p.y)
            // The point measured in the brush's own size, so a big brush has big
            // lobes and a small one small ones.
            let size = Double(radius / pixelsPerPoint)
            // Every wash's edge wanders a little, never a perfect circle.
            let wobble = (valueNoise(px / (size * 0.9), py / (size * 0.9), salt) - 0.5) * 0.14
                + (valueNoise(px / 2.5, py / 2.5, salt &+ 7) - 0.5) * 0.05
            var reach = wobble
            if creep > 0 {
                // Lobes and fingers: the water runs out further along some paths
                // of the paper than others.
                let lobe = valueNoise(px / (size * 0.6), py / (size * 0.6), salt &+ 11)
                let fine = valueNoise(px / (size * 0.2), py / (size * 0.2), salt &+ 13)
                let finger = min(1, max(0, lobe * 0.85 + fine * 0.25 - 0.05))
                reach += creep * (0.35 + 1.1 * finger * finger.squareRoot())
            }
            var wet: Float = 0
            for earlier in under {
                wet = max(wet, earlier.wash.water(x, y) * earlier.wetness)
            }
            if wet > 0 {
                // A bloom's front is ragged at the scale of cauliflower florets,
                // and of smaller florets on those.
                let floret = valueNoise(px / (size * 0.5), py / (size * 0.5), salt &+ 17)
                let small = valueNoise(px / (size * 0.17), py / (size * 0.17), salt &+ 19)
                reach += wet * flood * (0.25 + 1.1 * floret * floret + 0.08 * small)
            }
            reach = min(WatercolourStroke.maximumReach, max(-0.2, reach))
            // A wash is never quite even: the pigment gathers in soft blotches the
            // size of the brush and smaller.
            let mottle = 1 + 0.4 * (valueNoise(px / (size * 0.5), py / (size * 0.5), salt &+ 23) - 0.5)
                + 0.2 * (valueNoise(px / 4, py / 4, salt &+ 29) - 0.5)
            v[2] = reach + 1
            v[3] = wet
            v[4] = mottle
            v[5] = PaperGrain.height(x: px, y: py, coarseness: 2)
            return reach
        }
    }

    private var reacher: Reacher {
        Reacher(toPoints: toPoints, radius: radius, pixelsPerPoint: pixelsPerPoint, salt: salt, creep: creep,
                flood: flood, under: under)
    }

    /// Lays one dab and hands back the pixels whose wash changed: where it
    /// laid water, or deepened the brush's path where there is water. (Where
    /// there is none the path changes nothing anyone sees, and counting it
    /// made a dab beside a wet wash redraw four radii round on every move.)
    mutating func mark(_ dab: BrushDab) -> PixelBox {
        let centre = dab.center.applying(toPixels)
        let r = max(dab.diameter / 2 * pixelsPerPoint, 0.5)
        let box = PixelBox.around(centre, radius: r * CGFloat(1 + farthest) + 2).intersection(field.limit)
        guard !box.isEmpty else { return .empty }
        field.ensure(box)
        let pad = Float(radius) * Self.maximumReach + 1
        let rf = Float(r)
        let reacher = self.reacher
        let anyWet = !reacher.under.isEmpty
        let reachable = rf * (1 + farthest) + 1
        let dry = rf * (1 + reacher.dryReach) + 1
        let fieldBox = field.box
        return field.values.withUnsafeMutableBufferPointer { buffer -> PixelBox in
            guard let values = buffer.baseAddress else { return .empty }
            return PixelBands.union(box, bands: PixelBands.count(forDab: box)) { minRow, maxRow in
                var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
                for y in minRow..<maxRow {
                    let dy = Float(CGFloat(y) + 0.5 - centre.y)
                    for x in box.minX..<box.maxX {
                        let dx = Float(CGFloat(x) + 0.5 - centre.x)
                        let d = (dx * dx + dy * dy).squareRoot()
                        // Nothing this dab could reach, wherever the water ran.
                        guard d < reachable else { continue }
                        let v = values + ((y - fieldBox.minY) * fieldBox.width + (x - fieldBox.minX))
                            * WetField.channels
                        var seen = false
                        // Past the dry reach only a pixel already worked out, or
                        // one a wet wash lies under, can take the water.
                        if d < dry || v[2] > 0 || (anyWet && reacher.isWet(x, y)) {
                            let water = rf * (1 + reacher.reach(x, y, v)) - d + 0.5
                            if water > v[0] {
                                v[0] = water
                                seen = true
                            }
                        }
                        let path = rf - d + pad
                        if path > v[1] {
                            v[1] = path
                            if v[0] > 0 { seen = true }
                        }
                        if seen {
                            minX = min(minX, x)
                            maxX = max(maxX, x)
                            minY = min(minY, y)
                            maxY = max(maxY, y)
                        }
                    }
                }
                return minX <= maxX ? PixelBox(minX: minX, minY: minY, maxX: maxX + 1, maxY: maxY + 1) : .empty
            }
        }
    }

    /// How much light the wash takes at a pixel, 0...1, from its fields and
    /// the paper there.
    @inline(__always)
    private func pigment(_ x: Int, _ y: Int, _ i: Int) -> Float {
        let water = field.values[i]
        guard water > 0 else { return 0 }
        let r = Float(radius)
        let pad = r * Self.maximumReach + 1
        // How deep inside the wet area's edge, and inside the brush's path
        // (below zero out in the bleed), as shares of the radius.
        let depth = (water - 0.5) / r
        let core = (field.values[i + 1] - pad) / r
        let reach = max(0.05, field.values[i + 2] - 1)
        let wet = field.values[i + 3]
        // Antialiased at the very edge.
        var a = min(1, water)
        // A thin, uneven wash, thinner the further the water carried it, and
        // paler where it flooded into a wet wash.
        let carried = max(0, -core) / reach
        a *= (0.34 + 0.14 * (1 - wetness)) * field.values[i + 4]
            * (1 - 0.25 * smoothstep(0, 1, carried)) * (1 - 0.3 * wet)
        // Bled into damp paper, the front feathers, and so does paint dropped
        // into a wash that is still soaking; where it met dry paper it is
        // crisp.
        let soak = smoothstep(0.45, 0.95, wet)
        let feather = max(0.6 * smoothstep(0.4, 1, bleed) * (1 - wet), 0.9 * soak)
        if feather > 0.01 { a *= smoothstep(0, feather, depth) }
        // Pooled at the edge: more water, more pigment drawn to it. Paint
        // dropped into a wash that has begun to dry pushes the water back
        // into a hard, dark, ragged front: a backrun.
        let band: Float = 0.07 + 0.06 * wetness
        let pool = (0.4 + 1.3 * wetness) * (1 - 0.55 * smoothstep(0.4, 1, bleed)) + 2 * wet * (1 - soak)
        a *= 1 + pool * exp(-depth / band)
        // The paper, in the layer's own points: the same tooth the dry media
        // catch, a little broader.
        let paper = field.values[i + 5]
        if granulation > 0 {
            a *= max(0.15, 1 + granulation * 1.3 * (0.5 - paper))
        }
        // A dry brush catches only the tooth, skipping the pits, more toward
        // its edges than its middle.
        let dryness = 1 - smoothstep(0.05, 0.4, wetness)
        if dryness > 0 {
            let threshold = dryness * (0.8 - 0.35 * min(1, max(0, core)))
            a *= 1 - dryness + dryness * smoothstep(threshold - 0.06, threshold + 0.06, paper)
        }
        return min(0.95, a * strength)
    }

    /// The wash over one pixel `under` (premultiplied, 0...1), as the pixel to
    /// lay OVER it with plain source-over: the multiply of the wash and what
    /// is there, which is what lets the live overlay show what lands.
    @inline(__always)
    private func over(_ a: Float, colour: (Float, Float, Float),
                      under: (Float, Float, Float, Float)) -> (Float, Float, Float, Float) {
        let keep = 1 - under.3
        return (a * colour.0 * (keep + under.0), a * colour.1 * (keep + under.1),
                a * colour.2 * (keep + under.2), a)
    }

    /// Lays the stroke over `plane` in `colour`: a stroke that lands.
    func composite(into plane: PixelPlane, colour: RGBA) {
        let box = field.box.intersection(plane.box)
        guard !box.isEmpty else { return }
        let c = (Float(colour.r), Float(colour.g), Float(colour.b))
        PixelBands.run(box, bands: PixelBands.count(for: box)) { _, minRow, maxRow in
            for y in minRow..<maxRow {
                for x in box.minX..<box.maxX {
                    let a = pigment(x, y, field.index(x, y))
                    guard a > 0 else { continue }
                    let o = plane.offset(x, y)
                    let d = (Float(plane.data[o]) / 255, Float(plane.data[o + 1]) / 255,
                             Float(plane.data[o + 2]) / 255, Float(plane.data[o + 3]) / 255)
                    let s = over(a, colour: c, under: d)
                    let keep = 1 - s.3
                    plane.data[o] = byte((s.0 + d.0 * keep) * 255)
                    plane.data[o + 1] = byte((s.1 + d.1 * keep) * 255)
                    plane.data[o + 2] = byte((s.2 + d.2 * keep) * 255)
                    plane.data[o + 3] = byte((s.3 + d.3 * keep) * 255)
                }
            }
        }
    }

    /// Writes what the stroke lays over `under` (the paint it lands on, in
    /// the overlay's pixels, or nothing) into `box` of `overlay`, in place of
    /// what was there. Shown over the canvas at full strength.
    func replace(_ box: PixelBox, in overlay: PixelPlane, under: PixelPlane?, colour: RGBA) {
        let box = box.intersection(overlay.box).intersection(field.box)
        guard !box.isEmpty else { return }
        let c = (Float(colour.r), Float(colour.g), Float(colour.b))
        PixelBands.run(box, bands: PixelBands.count(for: box)) { _, minRow, maxRow in
            for y in minRow..<maxRow {
                for x in box.minX..<box.maxX {
                    var d: (Float, Float, Float, Float) = (0, 0, 0, 0)
                    if let under, x < under.width, y < under.height {
                        let u = under.offset(x, y)
                        d = (Float(under.data[u]) / 255, Float(under.data[u + 1]) / 255,
                             Float(under.data[u + 2]) / 255, Float(under.data[u + 3]) / 255)
                    }
                    let s = over(pigment(x, y, field.index(x, y)), colour: c, under: d)
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

/// A watercolour stroke's own fields over a box that grows as the stroke
/// reaches new ground, never past `limit`: four numbers a pixel, how deep in
/// the wet area (pixels, 0 outside), how deep in the brush's path (pixels,
/// padded so the bleed beyond it reads below the pad), the reach there plus
/// one (0 until worked out), how wet the washes under it are, how uneven the
/// wash is there, and the paper's height.
struct WetField {
    static let channels = 6
    let limit: PixelBox
    private(set) var box = PixelBox.empty
    var values: [Float] = []

    init(limit: PixelBox) { self.limit = limit }

    mutating func ensure(_ wanted: PixelBox) {
        let wanted = wanted.intersection(limit)
        defer { journal?.save(wanted, from: values, box: box, channels: WetField.channels) }
        guard !box.contains(wanted) else { return }
        // Grown in proportion to the dab and to what it already holds, so a
        // stroke copies its field a handful of times rather than on every
        // move: by a fixed 96 pixels, a 500 point brush outran it on nearly
        // every move and copied a field as big as the stroke each time
        // (2026-10-27, 60 to 120 ms a move on a 12 megapixel canvas).
        let margin = max(96, max(wanted.width, wanted.height), max(box.width, box.height) / 4)
        let grown = box.union(PixelBox(minX: wanted.minX - margin, minY: wanted.minY - margin,
                                       maxX: wanted.maxX + margin, maxY: wanted.maxY + margin))
            .intersection(limit)
        var next = [Float](repeating: 0, count: grown.width * grown.height * WetField.channels)
        if !box.isEmpty {
            for y in box.minY..<box.maxY {
                let from = (y - box.minY) * box.width * WetField.channels
                let to = ((y - grown.minY) * grown.width + (box.minX - grown.minX)) * WetField.channels
                for k in 0..<(box.width * WetField.channels) { next[to + k] = values[from + k] }
            }
        }
        box = grown
        values = next
    }

    /// What it held over each box it was asked for since `record`, so a live
    /// stroke's tail, drawn as if the stroke ended where the pointer is, can
    /// be taken back on the next move (`LiveMarker`).
    private(set) var journal: FieldJournal?

    mutating func record() { journal = FieldJournal() }

    /// Puts back everything written since `record`.
    mutating func rollBack() {
        journal?.restore(into: &values, box: box, channels: WetField.channels)
        journal = nil
    }

    /// Keeps what was written since `record`.
    mutating func keep() { journal = nil }

    @inline(__always) func index(_ x: Int, _ y: Int) -> Int {
        ((y - box.minY) * box.width + (x - box.minX)) * WetField.channels
    }

    func water(_ x: Int, _ y: Int) -> Float {
        guard x >= box.minX, x < box.maxX, y >= box.minY, y < box.maxY else { return 0 }
        return values[index(x, y)]
    }
}

/// The watercolour washes on one layer that are still wet, kept as its strokes
/// are replayed in order, so each new stroke knows what it is painting into.
struct WetWashes {
    private var washes: [(stroke: BrushStroke, wash: WatercolourStroke)] = []

    /// The washes still wet when `stroke` begins. Ones that have dried are
    /// let go: strokes are painted in time order, so they stay dry.
    mutating func under(_ stroke: BrushStroke) -> [WetWash] {
        var out: [WetWash] = []
        var keep: [(stroke: BrushStroke, wash: WatercolourStroke)] = []
        for entry in washes {
            let wet = entry.stroke.wetness(when: stroke)
            guard wet > 0 else { continue }
            keep.append(entry)
            out.append(WetWash(wash: entry.wash, wetness: Float(wet)))
        }
        washes = keep
        return out
    }

    mutating func add(_ stroke: BrushStroke, _ wash: WatercolourStroke) {
        washes.append((stroke, wash))
    }

    /// The wet washes `stroke` paints into, out of the `earlier` strokes of
    /// its layer, worked out in `toPixels` within `limit`: the earlier strokes
    /// that can still matter are replayed (only their water, nothing is
    /// drawn), the same way the renderer replays them, so the live stroke
    /// blooms where the landed one will.
    static func under(_ stroke: BrushStroke, earlier: [BrushStroke], toPixels: CGAffineTransform,
                      limit: PixelBox) -> [WetWash] {
        guard stroke.settings.medium == .watercolour, stroke.settings.mode == .paint else { return [] }
        // Which earlier strokes matter: wet when this one begins, or when a
        // later one that matters began.
        var needed = [Bool](repeating: false, count: earlier.count)
        var targets = [stroke]
        for i in earlier.indices.reversed() where targets.contains(where: { earlier[i].wetness(when: $0) > 0 }) {
            needed[i] = true
            targets.append(earlier[i])
        }
        var washes = WetWashes()
        for (i, earlierStroke) in earlier.enumerated() where needed[i] {
            guard let colour = RGBA(hex: earlierStroke.colorHex) else { continue }
            PaintRasterizer.countSimulated()
            var wash = WatercolourStroke(settings: earlierStroke.settings, colour: colour, seed: earlierStroke.seed,
                                         toPixels: toPixels, limit: limit, under: washes.under(earlierStroke))
            for dab in BrushPlacement.dabs(for: earlierStroke) { _ = wash.mark(dab) }
            washes.add(earlierStroke, wash)
        }
        return washes.under(stroke)
    }
}

/// The tail of a live stroke (`LiveMarker`): drawn as if the stroke ended where
/// the pointer is, then taken back on the next move. The checkpoint is the
/// stroke apart from its fields, which keep what the tail wrote instead, so
/// neither copies a field the size of the stroke.
extension WatercolourStroke {
    mutating func beginTail() -> WatercolourStroke {
        var held = [WetField(limit: field.limit)]
        swap(&held[0], &field)
        let checkpoint = self
        swap(&held[0], &field)
        field.record()
        return checkpoint
    }

    mutating func takeBackTail(to checkpoint: WatercolourStroke) {
        field.rollBack()
        var held = [WetField(limit: field.limit)]
        swap(&held[0], &field)
        self = checkpoint
        swap(&held[0], &field)
    }

    mutating func keepTail() {
        field.keep()
    }
}
