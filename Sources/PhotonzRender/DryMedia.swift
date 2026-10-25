import CoreGraphics
import Foundation
import PhotonzCore

// Pencil, charcoal, chalk and crayon, and the smudge (`docs/design/brushes.md`,
// decisions 4 and 7). A round dab with a texture on it is explicitly not good
// enough, so these work on pixels: each dab lays down a tip shape whose edge
// is broken by the paper, that tip settles only on the paper's tooth
// (`PaperGrain`), and the deposit builds the way the real medium does.
//
// Everything here is shared by the stroke that lands (`PaintRasterizer`) and
// the stroke under the pointer (`PaintRasterizer.LiveMarker`): both hand the
// same dabs over in the same order, so what lands is what was seen.

// MARK: - Pixels

/// A box of whole pixels, `max` exclusive.
struct PixelBox: Equatable {
    var minX: Int, minY: Int, maxX: Int, maxY: Int

    static let empty = PixelBox(minX: 0, minY: 0, maxX: 0, maxY: 0)

    var isEmpty: Bool { maxX <= minX || maxY <= minY }
    var width: Int { max(0, maxX - minX) }
    var height: Int { max(0, maxY - minY) }

    func union(_ other: PixelBox) -> PixelBox {
        if isEmpty { return other }
        if other.isEmpty { return self }
        return PixelBox(minX: min(minX, other.minX), minY: min(minY, other.minY),
                        maxX: max(maxX, other.maxX), maxY: max(maxY, other.maxY))
    }

    func intersection(_ other: PixelBox) -> PixelBox {
        let box = PixelBox(minX: max(minX, other.minX), minY: max(minY, other.minY),
                           maxX: min(maxX, other.maxX), maxY: min(maxY, other.maxY))
        return box.isEmpty ? .empty : box
    }

    func contains(_ other: PixelBox) -> Bool {
        other.isEmpty || (other.minX >= minX && other.minY >= minY
                          && other.maxX <= maxX && other.maxY <= maxY)
    }

    /// The pixels within `radius` of `center`.
    static func around(_ center: CGPoint, radius: CGFloat) -> PixelBox {
        PixelBox(minX: Int((center.x - radius).rounded(.down)), minY: Int((center.y - radius).rounded(.down)),
                 maxX: Int((center.x + radius).rounded(.up)) + 1, maxY: Int((center.y + radius).rounded(.up)) + 1)
    }

    init(minX: Int, minY: Int, maxX: Int, maxY: Int) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    init(_ rect: CGRect) {
        self.init(minX: Int(rect.minX.rounded(.down)), minY: Int(rect.minY.rounded(.down)),
                  maxX: Int(rect.maxX.rounded(.up)), maxY: Int(rect.maxY.rounded(.up)))
    }
}

/// A premultiplied RGBA bitmap's own bytes, top row first: what the context
/// that `PaintRasterizer` and the live overlay make hands back as `data`.
struct PixelPlane {
    let data: UnsafeMutablePointer<UInt8>
    let width: Int
    let height: Int
    let bytesPerRow: Int

    init?(_ context: CGContext) {
        guard let raw = context.data, context.bitsPerComponent == 8, context.bitsPerPixel == 32,
              context.alphaInfo == .premultipliedLast else { return nil }
        data = raw.assumingMemoryBound(to: UInt8.self)
        width = context.width
        height = context.height
        bytesPerRow = context.bytesPerRow
    }

    var box: PixelBox { PixelBox(minX: 0, minY: 0, maxX: width, maxY: height) }

    @inline(__always) func offset(_ x: Int, _ y: Int) -> Int { y * bytesPerRow + x * 4 }
}

/// How much of a stroke is laid down at each pixel, 0...1, over a box that
/// grows as the stroke reaches new ground (the live stroke does not know where
/// it is going) but never past `limit`.
struct CoverageField {
    let limit: PixelBox
    private(set) var box = PixelBox.empty
    var values: [Float] = []

    init(limit: PixelBox) { self.limit = limit }

    mutating func ensure(_ wanted: PixelBox) {
        let wanted = wanted.intersection(limit)
        guard !box.contains(wanted) else { return }
        // Grow with room to spare, so a stroke moving steadily one way does
        // not copy its field at every dab.
        let margin = 96
        let grown = box.union(PixelBox(minX: wanted.minX - margin, minY: wanted.minY - margin,
                                       maxX: wanted.maxX + margin, maxY: wanted.maxY + margin))
            .intersection(limit)
        var next = [Float](repeating: 0, count: grown.width * grown.height)
        if !box.isEmpty {
            for y in box.minY..<box.maxY {
                let from = (y - box.minY) * box.width
                let to = (y - grown.minY) * grown.width + (box.minX - grown.minX)
                for x in 0..<box.width { next[to + x] = values[from + x] }
            }
        }
        box = grown
        values = next
    }

    @inline(__always) func index(_ x: Int, _ y: Int) -> Int { (y - box.minY) * box.width + (x - box.minX) }

    func value(_ x: Int, _ y: Int) -> Float {
        guard x >= box.minX, x < box.maxX, y >= box.minY, y < box.maxY else { return 0 }
        return values[index(x, y)]
    }

    mutating func set(_ x: Int, _ y: Int, _ value: Float) { values[index(x, y)] = value }
}

@inline(__always) func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)
}

/// SplitMix64, the same numbers in the same order for the same seed: the dust
/// a charcoal stroke throws off is part of the stroke, not a fresh roll at
/// every render.
struct Scatter {
    private var state: UInt64

    init(seed: UInt32) { state = UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 ^ 0xD0_57 }

    mutating func unit() -> Float {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Float(z >> 40) / Float(1 << 24)
    }
}

// MARK: - What makes each medium itself

/// A fixed value in 0...1 for a whole-number point of a plane, from `salt`.
@inline(__always) func hashUnit(_ i: Int, _ j: Int, _ salt: UInt32) -> Float {
    var h = UInt64(bitPattern: Int64(i)) &* 0x9E37_79B9_7F4A_7C15
    h ^= UInt64(bitPattern: Int64(j)) &* 0xC2B2_AE3D_27D4_EB4F
    h ^= UInt64(salt) &* 0x1656_67B1_9E37_79F9
    h ^= h >> 31
    h &*= 0xBF58_476D_1CE4_E5B9
    h ^= h >> 29
    return Float(h >> 40) / Float(1 << 24)
}

/// Smooth value noise over a plane, 0...1, one lattice point per whole unit.
@inline(__always) func valueNoise(_ u: Double, _ v: Double, _ salt: UInt32) -> Float {
    let fu = u.rounded(.down), fv = v.rounded(.down)
    let i = Int(fu), j = Int(fv)
    var tx = Float(u - fu), ty = Float(v - fv)
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    let a = hashUnit(i, j, salt), b = hashUnit(i + 1, j, salt)
    let c = hashUnit(i, j + 1, salt), d = hashUnit(i + 1, j + 1, salt)
    return (a + (b - a) * tx) * (1 - ty) + (c + (d - c) * tx) * ty
}

/// The numbers that make pencil, charcoal, chalk and crayon four different
/// media (the design doc's table). Nil for the media that are not dry.
///
/// What tells them apart, at a glance: charcoal SHADES (a smoky grey that
/// fades out softly, fine tooth, dust); chalk is POWDER (opaque where it
/// lands, bare where it skips, many small crisp flecks, dry streaks that
/// break along the drag, crumbs at a ragged edge); crayon is WAX (a clean,
/// slightly wavering edge, colour on the high tooth only, so an even fine
/// pattern of bare pits, never fading); pencil is GRAPHITE (a thin grey line
/// that catches the tooth more the lighter it is pressed, wider and darker the
/// softer its lead, a broad grainy shading laid on its side, and a silvery
/// sheen where it piles up rather than a black).
struct DryLook {
    /// How stretched the paper is under this medium.
    var coarseness: Double
    /// How far the paper breaks the tip's edge, as a fraction of its radius,
    /// and how coarse that breakage is.
    var edgeBreak: Float
    var edgeCoarseness: Double
    /// The tip's profile: solid inside `inner`, nothing past `outer`, both as
    /// fractions of the radius. Charcoal fades over most of its radius;
    /// crayon stops at a line.
    var inner: Float
    var outer: Float
    /// How far down into the paper a full press reaches: 0.7 leaves the lowest
    /// 30 per cent of the paper bare.
    var reach: Float
    /// How sharply pigment stops at the tooth: wide for dusty charcoal,
    /// narrow for powder and wax.
    var softness: Float
    /// The most a stroke lays down at a pixel.
    var strength: Float
    /// The Grain setting, 0...1: none paints the whole tip, all of it paints
    /// only what the paper's tooth catches.
    var grain: Float
    /// Whether what the paper does not catch is still shaded in (charcoal's
    /// smoky wash, less of it the more Grain), or simply left bare: powder and
    /// wax are there or not, and Grain says how far into the paper they reach.
    var wash: Bool
    /// How strongly a stroke drags its own deposit along with it (the Smudge
    /// setting), per dab.
    var drag: Float
    /// Loose specks beside the stroke: soft charcoal dust, or crisp chalk
    /// crumbs that fall at the edge.
    var specks: Specks
    /// How deeply the stick's own uneven face streaks the stroke (at full
    /// Grain), how many streaks run across the tip, and how far, in points,
    /// a streak runs before the face meets the paper differently. Charcoal's
    /// run the whole stroke; chalk's skip and break every few points.
    var streaks: Float
    var streakCount: Float
    var streakRun: Double
    /// How much the stick's press drifts along the stroke, lighter and darker
    /// passages, as a fraction of a full press.
    var toneSwing: Float
    /// How flat the worn tip is: the tip's reach along the stroke over its
    /// reach across it. A crayon worn at an angle leaves short, squared ends
    /// rather than round ones.
    var tipLength: Float
    /// How far, in points, the stick keeps laying pigment after it catches a
    /// ridge of the paper: the short smears that run along a drag.
    var catchRun: Double
    /// Chalk's powder: how much a fine grit of its own, `powderSize` points
    /// across, breaks up the tooth it settles on, so it lands as many small
    /// crisp flecks rather than the paper's larger dimples.
    var powder: Float
    var powderSize: Double
    /// How far the stroke's edge wavers in and out as the hand moves, as a
    /// fraction of the radius, over `wobbleRun` points.
    var wobble: Float
    var wobbleRun: Double
    /// How wide the mark is against the Size: a soft lead wears blunter.
    var width: Float = 1
    /// Whether each dab's press shapes it (the pencil): a harder press is a
    /// wider, darker line reaching deeper into the paper.
    var pressed = false
    /// How much of the film thins with the press, so a light touch is pale as
    /// well as broken: 0 lays the full strength wherever the paper catches.
    var film: Float = 0
    /// How far a lean lays the side of the lead down (the Tilt Shading
    /// setting), 0...1.
    var tiltShading: Float = 0
    /// Graphite's sheen: how far the colour lifts toward a cool silver where
    /// the deposit is densest, so passes pile up to a sheen and not a black.
    var sheen: Float = 0

    enum Specks { case none, dust, crumbs }

    init?(_ settings: BrushSettings) {
        let grain = Float(settings.value("grain") / 100)
        // Squared, so the low default only softens and the top end drags hard.
        let smudge = pow(Float(settings.value("smudge") / 100), 2) * 0.25
        switch settings.medium {
        case .charcoal:
            // Velvety and smoky: a dense dark core that fades out softly over
            // most of its radius, the tooth shading its tone rather than
            // cutting it, long faint streaks, loose dust beside it.
            self.init(coarseness: 0.65, edgeBreak: 0.25, edgeCoarseness: 0.7, inner: 0.45, outer: 1.1,
                      reach: 0.64, softness: 0.12, strength: 1, grain: grain, wash: true,
                      drag: smudge, specks: .dust, streaks: 0.15, streakCount: 14, streakRun: 60, toneSwing: 0.1,
                      tipLength: 1, catchRun: 1.3, powder: 0, powderSize: 1, wobble: 0.06, wobbleRun: 30)
        case .chalk:
            // Powder: a lighter film than charcoal's carbon (chalk is mostly
            // white binder), even where it lands and bare where it skips, a
            // fine grit of crisp flecks all through it, a ragged edge that
            // sheds crumbs.
            self.init(coarseness: 0.9, edgeBreak: 0.5, edgeCoarseness: 1.4, inner: 0.6, outer: 0.85,
                      reach: 0.72, softness: 0.04, strength: 0.8, grain: grain, wash: false,
                      drag: smudge, specks: .crumbs, streaks: 0.6, streakCount: 13, streakRun: 14, toneSwing: 0.3,
                      tipLength: 1, catchRun: 3, powder: 0.75, powderSize: 0.65, wobble: 0.1, wobbleRun: 12)
        case .crayon:
            // Wax: a hard edge that wavers with the hand, colour only on the
            // high tooth, an even fine pattern of bare pits, faint striations.
            // More wax is a firmer press: it reaches further into the paper.
            let wax = Float(settings.value("wax") / 100)
            self.init(coarseness: 0.9, edgeBreak: 0.1, edgeCoarseness: 1, inner: 0.84, outer: 0.97,
                      reach: 0.47 + 0.3 * wax, softness: 0.05, strength: 0.95, grain: grain, wash: false,
                      drag: 0, specks: .none, streaks: 0.5, streakCount: 11, streakRun: 30, toneSwing: 0.12,
                      tipLength: 0.55, catchRun: 4, powder: 0, powderSize: 1, wobble: 0.16, wobbleRun: 10)
        case .pencil:
            // Graphite: a thin line with a clean, barely broken edge, fine
            // striations along the drag, no dust and no smear of its own. The
            // lead's grade sets how wide, how dark and how deep it reaches.
            let grades = Double(BrushMedium.pencilGrades.count - 1)
            let soft = Float(settings.value("hardness") / grades)
            self.init(coarseness: 0.65, edgeBreak: 0.12, edgeCoarseness: 0.5, inner: 0.5, outer: 1,
                      reach: 0.42 + 0.34 * soft, softness: 0.08, strength: 0.42 + 0.52 * soft, grain: grain,
                      wash: false, drag: 0, specks: .none, streaks: 0.3, streakCount: 6, streakRun: 40,
                      toneSwing: 0.05, tipLength: 1, catchRun: 0.8, powder: 0, powderSize: 1,
                      wobble: 0.03, wobbleRun: 40)
            width = 0.75 + 0.6 * soft
            pressed = true
            film = 0.7
            tiltShading = Float(settings.value("tilt") / 100)
            sheen = 0.35
        case .marker, .airbrush, .oil, .watercolour:
            return nil
        }
    }

    private init(coarseness: Double, edgeBreak: Float, edgeCoarseness: Double, inner: Float, outer: Float,
                 reach: Float, softness: Float, strength: Float, grain: Float, wash: Bool, drag: Float,
                 specks: Specks,
                 streaks: Float, streakCount: Float, streakRun: Double, toneSwing: Float, tipLength: Float,
                 catchRun: Double, powder: Float, powderSize: Double, wobble: Float, wobbleRun: Double) {
        self.coarseness = coarseness
        self.edgeBreak = edgeBreak
        self.edgeCoarseness = edgeCoarseness
        self.inner = inner
        self.outer = outer
        self.reach = reach
        self.softness = softness
        self.strength = strength
        self.grain = grain
        self.wash = wash
        self.drag = drag
        self.specks = specks
        self.streaks = streaks
        self.streakCount = streakCount
        self.streakRun = streakRun
        self.toneSwing = toneSwing
        self.tipLength = tipLength
        self.catchRun = catchRun
        self.powder = powder
        self.powderSize = powderSize
        self.wobble = wobble
        self.wobbleRun = wobbleRun
    }

    /// What the tip lays down at a pixel the tip covers by `tip` (0...1),
    /// over paper of height `paper`.
    @inline(__always) func deposit(tip: Float, paper: Float) -> Float {
        guard wash else {
            // No Grain reaches past the deepest pit even at the stroke's
            // lightest passage.
            let threshold = 1 - tip * (reach + (1 - grain) * (1 - grain) * (1.4 - reach))
            let caught = smoothstep(threshold - softness, threshold + softness, paper)
            return strength * caught * (1 - film + film * tip)
        }
        // The tooth is caught to the same depth right across the tip, and the
        // tip's own fall-off shades over it: a smoky edge with the paper's
        // texture in it, not a ring of specks.
        let threshold = 1 - reach
        let caught = smoothstep(threshold - softness, threshold + softness, paper)
        // How much the pits are still shaded in: a little at the default
        // Grain, all of it with none.
        let shade = (1 - grain) * (1 - grain)
        return strength * tip * (shade + (1 - shade) * caught)
    }

    /// The colour laid where the stroke covers `coverage` (0...1), 0...1 per
    /// channel, not premultiplied. Graphite is never black: a dark colour is
    /// lifted toward a cool silver, a little more where the deposit is
    /// densest, so passes piled up go to a sheen rather than to black. A pale
    /// colour is lifted less, white not at all.
    @inline(__always) func shade(_ r: Float, _ g: Float, _ b: Float,
                                 coverage: Float) -> (Float, Float, Float) {
        guard sheen > 0 else { return (r, g, b) }
        let dark = 1 - (0.2126 * r + 0.7152 * g + 0.0722 * b)
        let lift = sheen * dark * dark * (0.6 + 0.4 * smoothstep(0.45, 0.95, coverage))
        return (r + (0.40 - r) * lift, g + (0.42 - g) * lift, b + (0.47 - b) * lift)
    }

    /// The paper as this medium meets it, at a point of the layer: the shared
    /// tooth, with chalk's own grit worked in. Fixed to the layer like the
    /// paper itself, so two passes catch the same flecks.
    @inline(__always) func paper(_ tile: UnsafeBufferPointer<Float>, x: Double, y: Double) -> Float {
        let tooth = PaperGrain.height(tile, x: x, y: y, coarseness: coarseness)
        guard powder > 0 else { return tooth }
        let grit = valueNoise(x / powderSize, y / powderSize, 0xC4A1)
        // Spread back out to about the paper's own range.
        return min(1, max(0, 0.5 + (tooth - 0.5) * (1 - powder) + (grit - 0.5) * powder * 1.5))
    }
}

// MARK: - Laying a dry stroke down

/// One charcoal, chalk or crayon stroke being laid down, dab by dab, into its
/// own coverage. The caller puts the coverage onto pixels: over what is there
/// for a stroke that lands, in place of what was there for the live overlay.
struct DryStroke {
    let look: DryLook
    /// The stroke's own points to the bitmap's pixels, and back.
    let toPixels: CGAffineTransform
    let toPoints: CGAffineTransform
    let pixelsPerPoint: CGFloat
    private(set) var field: CoverageField
    private var scatter: Scatter
    /// What the stroke is carrying from the dab before, for its own Smudge.
    private var carried: [Float] = []
    private var carriedSide = 0
    /// This stroke's stick: its face and its hand, the same along the stroke.
    private let stick: UInt32
    /// How the press drifts along the stroke.
    private let drift: [Float]
    private var lastCentre: CGPoint?
    private var heading = CGVector(dx: 1, dy: 0)
    /// How far along the stroke the tip has come, in points.
    private var travelled: CGFloat = 0

    init(look: DryLook, seed: UInt32, toPixels: CGAffineTransform, limit: PixelBox) {
        self.look = look
        self.toPixels = toPixels
        toPoints = toPixels.inverted()
        pixelsPerPoint = hypot(toPixels.a, toPixels.b)
        field = CoverageField(limit: limit)
        var scatter = Scatter(seed: seed)
        stick = UInt32(scatter.unit() * Float(1 << 20))
        drift = (0..<64).map { _ in scatter.unit() }
        self.scatter = scatter
    }

    /// A smooth wander through `table`, 0...1, at `u` (in table steps).
    @inline(__always) private func wave(_ table: [Float], at u: Float) -> Float {
        let k = Int(u.rounded(.down)), t = u - Float(k)
        let a = table[((k % 64) + 64) % 64], b = table[(((k + 1) % 64) + 64) % 64]
        return a + (b - a) * t * t * (3 - 2 * t)
    }

    /// How hard the stick's face presses at `across` (-1...1 from one side of
    /// the tip to the other) when it is `along` points down the stroke, 0...1:
    /// streaks that run along the drag and, for chalk, skip and break.
    @inline(__always) private func pressure(across: Float, along: Double) -> Float {
        let u = Double((across + 1) * 0.5 * look.streakCount)
        let v = along / look.streakRun
        return smoothstep(0.25, 0.75, valueNoise(u, v, stick))
    }

    /// Lays one dab down and hands back the pixels it touched.
    mutating func mark(_ dab: BrushDab) -> PixelBox {
        var radius = max(dab.diameter / 2 * CGFloat(look.width), 0.25)
        // A pressed medium's press: a harder one is a little wider and a good
        // deal darker. Everything else paints its one weight.
        var weight: Float = 1
        // The side of the lead: how far the pen leans, as the tip's long and
        // short reach over its upright radius, and which way.
        var lean: Float = 0
        var leanAxis = CGVector(dx: 1, dy: 0)
        if look.pressed {
            let p = Float(min(1, max(0, dab.pressure)))
            radius *= CGFloat(0.8 + 0.35 * p)
            weight = 0.3 + 0.7 * pow(p, 0.8)
            let leaning = Float(hypot(dab.tilt.x, dab.tilt.y))
            lean = smoothstep(0.12, 0.8, leaning) * look.tiltShading
            if lean > 0.01 {
                leanAxis = CGVector(dx: dab.tilt.x / CGFloat(leaning), dy: dab.tilt.y / CGFloat(leaning))
                // Laid on its side the lead spreads its press over a broad
                // patch: paler, and only the high tooth catches.
                weight *= 1 - 0.5 * lean
            } else {
                lean = 0
            }
        }
        let long = 1 + 6 * lean, short = 1 + 2.5 * lean
        let centre = dab.center.applying(toPixels)
        let speckReach: CGFloat
        switch look.specks {
        case .none: speckReach = 0
        case .dust: speckReach = radius * 1.7 + 1
        case .crumbs: speckReach = radius * 1.35 + 1.5
        }
        let reach = max(radius * CGFloat(long) * CGFloat(1 + look.edgeBreak / 2 + look.wobble), speckReach)
            * pixelsPerPoint + 1
        let box = PixelBox.around(centre, radius: reach).intersection(field.limit)
        // Rolled whatever happens, so the live stroke and the landed one draw
        // the same specks even when a dab falls outside the bitmap.
        var specks: [(CGPoint, CGFloat, Float)] = []
        switch look.specks {
        case .none:
            break
        case .dust:
            for _ in 0..<2 {
                let roll = scatter.unit(), angle = scatter.unit() * 2 * .pi
                let distance = radius * CGFloat(0.85 + 0.75 * scatter.unit())
                let size = CGFloat(0.35 + 0.45 * scatter.unit())
                let amount = 0.25 + 0.4 * scatter.unit()
                if roll < 0.3 {
                    specks.append((CGPoint(x: dab.center.x + cos(CGFloat(angle)) * distance,
                                           y: dab.center.y + sin(CGFloat(angle)) * distance), size, amount))
                }
            }
        case .crumbs:
            // Chalk breaks off at its edge: fewer, crisp, close to the stroke.
            let roll = scatter.unit(), angle = scatter.unit() * 2 * .pi
            let distance = radius * CGFloat(0.95 + 0.3 * scatter.unit())
            let size = CGFloat(0.35 + 0.6 * scatter.unit())
            let amount = 0.85 + 0.15 * scatter.unit()
            if roll < 0.5 {
                specks.append((CGPoint(x: dab.center.x + cos(CGFloat(angle)) * distance,
                                       y: dab.center.y + sin(CGFloat(angle)) * distance), size, amount))
            }
        }
        // Which way the stick is travelling, so its streaks run along the
        // stroke.
        if let last = lastCentre {
            let dx = dab.center.x - last.x, dy = dab.center.y - last.y
            let length = hypot(dx, dy)
            if length > 0.01 { heading = CGVector(dx: dx / length, dy: dy / length) }
            travelled += length
        }
        lastCentre = dab.center
        // Lighter and darker passages, about every two tip widths.
        let press = weight * (1 - look.toneSwing * (1 - wave(drift, at: Float(travelled / (radius * 4)))))
        guard !box.isEmpty else { return .empty }
        field.ensure(box)

        let tipReach = Float(1 + look.edgeBreak + look.wobble)
        let streaking = look.streaks * look.grain
        // The run is read every pixel, so a pit narrower than a step cannot
        // leave a comb of copies behind it.
        let catchSteps = max(1, Int((look.catchRun * Double(pixelsPerPoint)).rounded()))
        let catchSpread = Float(1 + 0.4 * look.catchRun)
        // The tip's own pixels: the specks have boxes of their own.
        let tipBox = PixelBox.around(centre, radius: radius * CGFloat(tipReach * long) * pixelsPerPoint + 1)
            .intersection(box)
        // A lead on its side has a soft edge: its press fades out across it.
        let inner = look.inner * (1 - 0.75 * lean)
        guard !tipBox.isEmpty else {
            for (at, size, amount) in specks { speck(at: at, size: size, amount: amount) }
            return box
        }
        PaperGrain.tile.withUnsafeBufferPointer { paperTile in
        for y in tipBox.minY..<tipBox.maxY {
            for x in tipBox.minX..<tipBox.maxX {
                let p = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5).applying(toPoints)
                let ahead = (p.x - dab.center.x) * heading.dx + (p.y - dab.center.y) * heading.dy
                let along = Float(ahead / radius) / look.tipLength
                var side = Float(((p.x - dab.center.x) * -heading.dy + (p.y - dab.center.y) * heading.dx)
                                 / radius)
                // How far down the stroke this pixel is: the stick's face and
                // the hand's waver are read there, so they follow the curve.
                let down = Double(travelled + ahead)
                if look.wobble > 0 {
                    // The hand wavers: the whole edge moves in and out
                    // together, slowly, never in step on both sides.
                    let near = side > 0 ? valueNoise(down / look.wobbleRun, 3.5, stick &+ 7)
                                        : valueNoise(down / look.wobbleRun, 9.5, stick &+ 7)
                    side /= 1 + look.wobble * (near * 2 - 1)
                }
                var r = (along * along + side * side).squareRoot()
                if lean > 0 {
                    // The patch the side of the lead lays down, long the way
                    // the pen leans, whichever way the hand is moving.
                    let dx = p.x - dab.center.x, dy = p.y - dab.center.y
                    let u = Float((dx * leanAxis.dx + dy * leanAxis.dy) / radius) / long
                    let v = Float((dx * -leanAxis.dy + dy * leanAxis.dx) / radius) / short
                    r = (u * u + v * v).squareRoot()
                }
                guard r < tipReach else { continue }
                let edge = PaperGrain.height(paperTile, x: Double(p.x) + 41.3, y: Double(p.y) + 17.9,
                                             coarseness: look.edgeCoarseness)
                var tip = 1 - smoothstep(inner, look.outer, r + look.edgeBreak * (edge - 0.5))
                guard tip > 0 else { continue }
                if streaking > 0 {
                    tip *= 1 - streaking * (1 - pressure(across: max(-1, min(1, side)), along: down))
                }
                tip *= press
                // The highest ridge the stick met over its last short run.
                var paper: Float = 0
                for k in 0...catchSteps {
                    let back = look.catchRun * Double(k) / Double(catchSteps)
                    paper = max(paper, look.paper(paperTile, x: Double(p.x) - Double(heading.dx) * back,
                                                  y: Double(p.y) - Double(heading.dy) * back))
                }
                // The highest of several heights runs high; spread it back out
                // so a press reaches about the same share of the paper.
                paper = pow(paper, catchSpread)
                let laid = look.deposit(tip: tip, paper: paper)
                let i = field.index(x, y)
                if laid > field.values[i] { field.values[i] = laid }
            }
        }
        }
        for (at, size, amount) in specks { speck(at: at, size: size, amount: amount) }
        if look.drag > 0 { drag(at: centre, radius: radius * pixelsPerPoint) }
        return box
    }

    /// One fleck beside the stroke, caught by the paper like the rest: soft
    /// charcoal dust, or a crisp crumb of chalk.
    private mutating func speck(at point: CGPoint, size: CGFloat, amount: Float) {
        let centre = point.applying(toPixels)
        let reach = size * pixelsPerPoint + 1
        let box = PixelBox.around(centre, radius: reach).intersection(field.box)
        guard !box.isEmpty else { return }
        let crisp = look.specks == .crumbs
        for y in box.minY..<box.maxY {
            for x in box.minX..<box.maxX {
                let p = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5).applying(toPoints)
                let d = Float(hypot(p.x - point.x, p.y - point.y) / size)
                guard d < 1 else { continue }
                let paper = PaperGrain.height(x: Double(p.x), y: Double(p.y), coarseness: look.coarseness)
                let shape = crisp ? 1 - smoothstep(0.75, 1, d) : 1 - smoothstep(0.4, 1, d)
                let laid = amount * shape * (paper > 0.35 ? 1 : 0.35) * look.strength
                if laid > field.value(x, y) { field.set(x, y, laid) }
            }
        }
    }

    /// The stroke's own Smudge: what it picked up under the dab before is
    /// pressed into the valleys under this one, so the deposit is dragged
    /// along the stroke and the tooth fills in.
    private mutating func drag(at centre: CGPoint, radius: CGFloat) {
        let half = max(1, Int(radius.rounded(.up)))
        let side = half * 2 + 1
        let cx = Int(centre.x.rounded(.down)), cy = Int(centre.y.rounded(.down))
        let fresh = carriedSide != side
        if fresh {
            carried = [Float](repeating: 0, count: side * side)
            carriedSide = side
        }
        let pickup: Float = 0.12
        for oy in -half...half {
            for ox in -half...half {
                let x = cx + ox, y = cy + oy
                let i = (oy + half) * side + (ox + half)
                let d = Float(hypot(CGFloat(ox), CGFloat(oy)) / radius)
                let inside = x >= field.box.minX && x < field.box.maxX && y >= field.box.minY && y < field.box.maxY
                if !fresh, d < 1, inside {
                    let here = field.value(x, y), held = carried[i]
                    if held > here {
                        let w = 1 - smoothstep(0.3, 1, d)
                        field.set(x, y, here + look.drag * w * (held - here))
                    }
                }
                let under = inside ? field.value(x, y) : 0
                carried[i] = fresh ? under : carried[i] + pickup * (under - carried[i])
            }
        }
    }

    /// Lays the coverage over `plane` in `colour` (premultiplied), at
    /// `opacity`: a stroke that lands.
    func composite(into plane: PixelPlane, colour: RGBA, opacity: Float) {
        let box = field.box.intersection(plane.box)
        guard !box.isEmpty else { return }
        let alpha = Float(colour.a) * opacity
        let r = Float(colour.r), g = Float(colour.g), b = Float(colour.b)
        for y in box.minY..<box.maxY {
            for x in box.minX..<box.maxX {
                let coverage = field.values[field.index(x, y)]
                let a = coverage * alpha
                guard a > 0 else { continue }
                let o = plane.offset(x, y)
                let keep = 1 - a
                let (r, g, b) = look.shade(r, g, b, coverage: coverage)
                plane.data[o] = byte(r * a * 255 + Float(plane.data[o]) * keep)
                plane.data[o + 1] = byte(g * a * 255 + Float(plane.data[o + 1]) * keep)
                plane.data[o + 2] = byte(b * a * 255 + Float(plane.data[o + 2]) * keep)
                plane.data[o + 3] = byte(a * 255 + Float(plane.data[o + 3]) * keep)
            }
        }
    }

    /// Writes the coverage in `colour` over `box` of `plane`, in place of
    /// what was there: the live overlay holds only this stroke.
    func replace(_ box: PixelBox, in plane: PixelPlane, colour: RGBA) {
        let box = box.intersection(plane.box)
        guard !box.isEmpty else { return }
        let alpha = Float(colour.a)
        let r = Float(colour.r), g = Float(colour.g), b = Float(colour.b)
        for y in box.minY..<box.maxY {
            for x in box.minX..<box.maxX {
                let coverage = field.value(x, y)
                let a = coverage * alpha
                let o = plane.offset(x, y)
                let (r, g, b) = look.shade(r, g, b, coverage: coverage)
                plane.data[o] = byte(r * a * 255)
                plane.data[o + 1] = byte(g * a * 255)
                plane.data[o + 2] = byte(b * a * 255)
                plane.data[o + 3] = byte(a * 255)
            }
        }
    }
}

@inline(__always) func byte(_ value: Float) -> UInt8 {
    UInt8(min(255, max(0, value.rounded())))
}

// MARK: - Smudging what is painted

/// A smudge: a finger dragged through paint already on the layer. Under each
/// dab it presses down what it picked up under the dab before, and picks up a
/// little of what is under it now, so the deposit is carried along and runs
/// out over bare paper (decision 7).
///
/// It only ever adds: paint is pulled into lighter places, never scraped off.
/// That keeps the live overlay honest, because "laid over" stacks: what the
/// finger lays over the layer, laid over an empty overlay, shows the same
/// thing over the composite as the landed stroke shows inside the layer.
struct SmudgeStroke {
    let toPixels: CGAffineTransform
    let toPoints: CGAffineTransform
    let pixelsPerPoint: CGFloat
    let limit: PixelBox
    /// How much of what it carries it presses down per dab.
    let strength: Float
    private var carried: [Float] = []
    private var carriedSide = 0

    init(settings: BrushSettings, toPixels: CGAffineTransform, limit: PixelBox) {
        self.toPixels = toPixels
        toPoints = toPixels.inverted()
        pixelsPerPoint = hypot(toPixels.a, toPixels.b)
        self.limit = limit
        strength = 0.6 * Float(settings.opacity / 100)
    }

    /// Drags under one dab, in `target` (and the same change laid over
    /// `mirror`), and hands back the pixels it touched.
    mutating func mark(_ dab: BrushDab, target: PixelPlane, mirror: PixelPlane?) -> PixelBox {
        let radius = max(dab.diameter / 2, 0.25) * pixelsPerPoint
        let centre = dab.center.applying(toPixels)
        let half = max(1, Int(radius.rounded(.up)))
        let side = half * 2 + 1
        let cx = Int(centre.x.rounded(.down)), cy = Int(centre.y.rounded(.down))
        let fresh = carriedSide != side
        if fresh {
            carried = [Float](repeating: 0, count: side * side * 4)
            carriedSide = side
        }
        let pickup: Float = 0.14
        // A finger blurs what it carries: the grain goes out of it.
        if !fresh { blurCarried(side: side) }
        let bounds = limit.intersection(target.box)
        for oy in -half...half {
            for ox in -half...half {
                let x = cx + ox, y = cy + oy
                let i = ((oy + half) * side + (ox + half)) * 4
                let inside = x >= bounds.minX && x < bounds.maxX && y >= bounds.minY && y < bounds.maxY
                guard inside else {
                    // Off the layer: nothing under the finger to pick up.
                    for k in 0..<4 { carried[i + k] = fresh ? 0 : carried[i + k] * (1 - pickup) }
                    continue
                }
                let o = target.offset(x, y)
                let d = Float(hypot(CGFloat(ox), CGFloat(oy)) / radius)
                if !fresh, d < 1 {
                    let heldAlpha = carried[i + 3]
                    let hereAlpha = Float(target.data[o + 3]) / 255
                    // A finger spreads what it carries thinner than it found it.
                    let spread = heldAlpha * 0.65
                    if heldAlpha > 0.004, spread > hereAlpha, hereAlpha < 1 {
                        // What the finger presses down still sits on the
                        // paper: more on the tooth, less in the pits, so a
                        // smear keeps the paper's texture.
                        let p = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5).applying(toPoints)
                        let tooth = PaperGrain.height(x: Double(p.x), y: Double(p.y), coarseness: 0.65)
                        let w = (1 - smoothstep(0, 1, d)) * (0.15 + 0.85 * smoothstep(0.25, 0.8, tooth))
                        let wanted = hereAlpha + strength * w * (spread - hereAlpha)
                        let laid = min(1, max(0, (wanted - hereAlpha) / (1 - hereAlpha)))
                        if laid > 0 {
                            // The colour carried, unpremultiplied, laid over at `laid`.
                            let r = carried[i] / heldAlpha * laid, g = carried[i + 1] / heldAlpha * laid
                            let b = carried[i + 2] / heldAlpha * laid
                            lay(r, g, b, laid, at: o, in: target)
                            if let mirror { lay(r, g, b, laid, at: mirror.offset(x, y), in: mirror) }
                        }
                    }
                }
                for k in 0..<4 {
                    let under = Float(target.data[o + k]) / 255
                    carried[i + k] = fresh ? under : carried[i + k] + pickup * (under - carried[i + k])
                }
            }
        }
        return PixelBox(minX: cx - half, minY: cy - half, maxX: cx + half + 1, maxY: cy + half + 1)
            .intersection(bounds)
    }

    /// A three by three blur of what the finger carries.
    private mutating func blurCarried(side: Int) {
        let source = carried
        for y in 0..<side {
            for x in 0..<side {
                for k in 0..<4 {
                    var total: Float = 0
                    var count: Float = 0
                    for dy in -1...1 {
                        let yy = y + dy
                        guard yy >= 0, yy < side else { continue }
                        for dx in -1...1 {
                            let xx = x + dx
                            guard xx >= 0, xx < side else { continue }
                            total += source[(yy * side + xx) * 4 + k]
                            count += 1
                        }
                    }
                    carried[(y * side + x) * 4 + k] = total / count
                }
            }
        }
    }

    @inline(__always) private func lay(_ r: Float, _ g: Float, _ b: Float, _ a: Float,
                                       at o: Int, in plane: PixelPlane) {
        let keep = 1 - a
        plane.data[o] = byte(r * 255 + Float(plane.data[o]) * keep)
        plane.data[o + 1] = byte(g * 255 + Float(plane.data[o + 1]) * keep)
        plane.data[o + 2] = byte(b * 255 + Float(plane.data[o + 2]) * keep)
        plane.data[o + 3] = byte(a * 255 + Float(plane.data[o + 3]) * keep)
    }
}
