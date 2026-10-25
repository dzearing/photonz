import CoreGraphics
import Foundation

/// Numbers read off a rendered straight stroke, so how a medium LOOKS is
/// measured rather than asserted (`docs/design/brushes.md`): the tests and the
/// stroke sheet in the audit read the same ones.
///
/// Each takes the picture, the stroke's two ends and its tip size in points,
/// and how many pixels a point is. The ends are kept out of every reading.
public enum PaintMeasures {

    /// The bar a dry medium's stroke must clear on `interiorGapFraction`, set
    /// where the foundation slice's soft round tip (0 per cent) fails it and
    /// all three dry media at their defaults pass it.
    public static let dryMediaGapBar = 0.12

    /// The pencil's bars, read with `lineProfile` and `interiorGapFraction`
    /// off straight strokes at Size 4 (`PencilRenderingTests`). The round tip
    /// draws the same line whatever the grade and leaves no tooth at any
    /// press, so it fails all three. An 8B is at least this many times as wide
    /// as a 2H, and this many times as dark...
    public static let pencilGradeWidthBar = 1.4
    public static let pencilGradeDarknessBar = 1.8
    /// ...and a light press (0.2) leaves at least this share of the line's
    /// core to the paper's tooth.
    public static let pencilLightToothBar = 0.3

    /// The marker's bar, read with `flatShare` off a stroke that doubles back
    /// over itself: a marker lays one even colour edge to edge however often
    /// it covers the same ground. The round tip's soft edge leaves about half
    /// its stroke in a fall-off, so it fails.
    public static let markerFlatBar = 0.9

    /// The airbrush's bar: held still for a second, it leaves at least this
    /// many times the coverage a steady pass does (`meanAlpha` at each). The
    /// round tip covers both the same, so it fails.
    public static let airbrushBuildUpBar = 1.6
    /// The airbrush's spray bars, read off a straight stroke at Size 40
    /// (`AirbrushRenderingTests`). Its width is mostly fall-off, densest at
    /// the line and feathering out (`featherShare`)...
    public static let airbrushFeatherBar = 0.6
    /// ...its fringe is specked with droplets, at least this many a square
    /// point (`edgeDroplets`), where the round tip's smooth edge has none...
    public static let airbrushEdgeDropletBar = 0.1
    /// ...and a slow pass leaves at least this many times the paint of a fast
    /// one, the spray landing by time (`meanAlpha` at the middle of each).
    public static let airbrushSlowOverFastBar = 1.4

    /// Watercolour's two bars, read off a straight stroke at Size 40
    /// (`WatercolourRenderingTests`). Its edge, where the pigment pooled as
    /// the wash dried, is at least this many times as dark as its middle
    /// (`edgeToCentre`); the round tip is darkest in its middle, so it reads
    /// about 1 or less and fails...
    public static let watercolourEdgeBar = 1.3
    /// ...and the wash spreads at least this share of the tip's radius past
    /// the path the brush took (`spreadPastPath`); the round tip stops at its
    /// edge, about 0, and fails.
    public static let watercolourSpreadBar = 0.15

    /// How much darker a stroke's edge is than its middle: across short
    /// stretches of its middle length (each averaged along, so a grainy wash
    /// reads as a person sees it), the darkest coverage in the outer third
    /// of the width it covers, over the mean coverage in its middle third.
    /// The median of those.
    public static func edgeToCentre(_ image: CGImage, from a: CGPoint, to b: CGPoint, diameter: CGFloat,
                                    scale: CGFloat) -> Double {
        var ratios: [Double] = []
        for profile in profiles(image, from: a, to: b, diameter: diameter, scale: scale) {
            guard let peak = profile.max(), peak > 0.02,
                  let top = profile.firstIndex(where: { $0 >= peak * 0.08 }),
                  let bottom = profile.lastIndex(where: { $0 >= peak * 0.08 }), bottom - top >= 6 else { continue }
            let half = Double(bottom - top) / 2, middle = Double(top + bottom) / 2
            var centre = 0.0, count = 0
            var upper = 0.0, lower = 0.0
            for j in top...bottom {
                let off = (Double(j) - middle) / half
                if abs(off) <= 1 / 3 {
                    centre += profile[j]
                    count += 1
                } else if off < -1 / 3 {
                    upper = max(upper, profile[j])
                } else {
                    lower = max(lower, profile[j])
                }
            }
            guard count > 0, centre > 0 else { continue }
            ratios.append((upper + lower) / 2 / (centre / Double(count)))
        }
        return median(ratios)
    }

    /// How far a stroke spreads past the path its tip took, as a share of
    /// the tip's radius: across short stretches of its middle length, how far
    /// from the line the paint still reaches a twentieth of its strongest
    /// (and at least 3 per cent coverage), either side, less the radius. The
    /// median of those. A tip that stops at its edge reads about 0.
    public static func spreadPastPath(_ image: CGImage, from a: CGPoint, to b: CGPoint, diameter: CGFloat,
                                      scale: CGFloat) -> Double {
        let radius = Double(diameter / 2 * scale)
        var spreads: [Double] = []
        for profile in profiles(image, from: a, to: b, diameter: diameter, scale: scale) {
            guard let peak = profile.max(), peak > 0.02 else { continue }
            let floor = max(0.03, peak * 0.05)
            guard let top = profile.firstIndex(where: { $0 >= floor }),
                  let bottom = profile.lastIndex(where: { $0 >= floor }) else { continue }
            let mid = Double(profile.count - 1) / 2
            let reach = (mid - Double(top) + Double(bottom) - mid) / 2 + 0.5
            spreads.append((reach - radius) / radius)
        }
        return median(spreads)
    }

    /// The stroke's coverage across it, a profile for each short stretch of
    /// its middle length (half a radius long, averaged along it), reaching
    /// out three radii either side of the line.
    private static func profiles(_ image: CGImage, from a: CGPoint, to b: CGPoint, diameter: CGFloat,
                                 scale: CGFloat) -> [[Double]] {
        guard let grid = Grid(image, from: a, to: b, diameter: diameter, scale: scale),
              !grid.alongRange.isEmpty else { return [] }
        let side = Int((diameter * 1.5 * scale).rounded())
        let stretch = max(1, Int((diameter / 4 * scale).rounded()))
        var out: [[Double]] = []
        var start = grid.alongRange.lowerBound
        while start + stretch <= grid.alongRange.upperBound {
            out.append((-side...side).map { j in
                var sum = 0.0
                for i in start..<(start + stretch) { sum += grid.alpha(i, j) }
                return sum / Double(stretch)
            })
            start += stretch
        }
        return out
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.sorted()[values.count / 2]
    }

    /// How much of what a stroke touched is one even colour: among the pixels
    /// above a twentieth of its strongest coverage, the share within a tenth of
    /// that strongest. A flat marker scores near 1; a soft edge or a pass that
    /// builds on itself lowers it.
    public static func flatShare(_ image: CGImage) -> Double {
        let alphas = alphaPlane(image)
        guard let top = alphas.max(), top > 0 else { return 0 }
        let touched = alphas.filter { $0 >= top * 0.05 }
        guard !touched.isEmpty else { return 0 }
        // The strongest the stroke usually reaches, not one stray pixel.
        let strong = touched.sorted()[Int(Double(touched.count - 1) * 0.95)]
        return Double(touched.filter { abs($0 - strong) <= strong * 0.1 }.count) / Double(touched.count)
    }

    /// The average coverage within `radius` points of `point`, 0...1.
    public static func meanAlpha(_ image: CGImage, around point: CGPoint, radius: CGFloat,
                                 scale: CGFloat) -> Double {
        let alphas = alphaPlane(image)
        guard !alphas.isEmpty else { return 0 }
        let width = image.width, height = image.height
        let cx = point.x * scale, cy = point.y * scale, r = radius * scale
        var sum = 0.0, count = 0
        for y in max(0, Int(cy - r))..<min(height, Int(cy + r) + 1) {
            for x in max(0, Int(cx - r))..<min(width, Int(cx + r) + 1)
            where hypot(CGFloat(x) + 0.5 - cx, CGFloat(y) + 0.5 - cy) <= r {
                sum += alphas[y * width + x]
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : 0
    }

    /// How grainy a stroke's fringe is: across the band from half its radius
    /// out to nine tenths, how far each pixel stands off the average of the
    /// pixels around it, as a share of the band's coverage. A smooth fall-off,
    /// however steep, reads near 0; a spray of fine droplets does not.
    public static func fringeGrain(_ image: CGImage, from a: CGPoint, to b: CGPoint,
                                   diameter: CGFloat, scale: CGFloat) -> Double {
        let alphas = alphaPlane(image)
        let width = image.width, height = image.height
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard !alphas.isEmpty, length > 0, diameter > 0, width > 2, height > 2 else { return 0 }
        let radius = diameter / 2
        var off = 0.0, cover = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let p = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / (length * length)
                guard t >= 0.1, t <= 0.9 else { continue }
                let across = abs((p.x - a.x) * dy - (p.y - a.y) * dx) / length / radius
                guard across >= 0.5, across <= 0.9 else { continue }
                var around = 0.0
                for j in -1...1 { for i in -1...1 { around += alphas[(y + j) * width + x + i] } }
                let here = alphas[y * width + x]
                off += abs(here - around / 9)
                cover += here
            }
        }
        return cover > 0 ? off / cover : 0
    }

    /// The stroke's coverage across it, averaged along its middle stretch:
    /// one reading a pixel from `reach` points one side of the line to `reach`
    /// the other, each with how far off the line it is, in points. What the
    /// audit plots, and what `featherShare` reads.
    public static func crossProfile(_ image: CGImage, from a: CGPoint, to b: CGPoint, reach: CGFloat,
                                    scale: CGFloat) -> [(at: Double, alpha: Double)] {
        guard let grid = Grid(image, from: a, to: b, diameter: reach * 2, scale: scale),
              !grid.alongRange.isEmpty else { return [] }
        let side = Int((reach * scale).rounded())
        return (-side...side).map { j in
            var sum = 0.0
            for i in grid.alongRange { sum += grid.alpha(i, j) }
            return (at: Double(j) / Double(scale), alpha: sum / Double(grid.alongRange.count))
        }
    }

    /// How much of a stroke's width is fall-off rather than body: across its
    /// averaged cross profile, one less the width at nine tenths of its peak
    /// over the width at a twentieth. A flat band with a crisp edge scores
    /// near 0; a spray densest along the line that feathers out to nothing,
    /// a bell, scores about 0.8.
    public static func featherShare(_ image: CGImage, from a: CGPoint, to b: CGPoint, diameter: CGFloat,
                                    scale: CGFloat) -> Double {
        let profile = crossProfile(image, from: a, to: b, reach: diameter, scale: scale)
        guard let peak = profile.map(\.alpha).max(), peak > 0 else { return 0 }
        let body = profile.filter { $0.alpha >= peak * 0.9 }.count
        let whole = profile.filter { $0.alpha >= peak * 0.05 }.count
        return whole > 0 ? 1 - Double(body) / Double(whole) : 0
    }

    /// How many droplets a stroke's fringe holds, a square point: across the
    /// band from half its radius out to nine tenths, either side, the pixels
    /// that stand above all eight around them by at least `lift` (a speck of
    /// paint, not a smooth slope), over the band's area in square points. A
    /// smooth fall-off holds none.
    public static func edgeDroplets(_ image: CGImage, from a: CGPoint, to b: CGPoint, diameter: CGFloat,
                                    scale: CGFloat, lift: Double = 0.02) -> Double {
        let alphas = alphaPlane(image)
        let width = image.width, height = image.height
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard !alphas.isEmpty, length > 0, diameter > 0, width > 2, height > 2 else { return 0 }
        let radius = diameter / 2
        var specks = 0, band = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let p = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / (length * length)
                guard t >= 0.1, t <= 0.9 else { continue }
                let across = abs((p.x - a.x) * dy - (p.y - a.y) * dx) / length / radius
                guard across >= 0.5, across <= 0.9 else { continue }
                band += 1
                let here = alphas[y * width + x]
                var highest = 0.0
                for j in -1...1 {
                    for i in -1...1 where i != 0 || j != 0 { highest = max(highest, alphas[(y + j) * width + x + i]) }
                }
                if here >= highest + lift { specks += 1 }
            }
        }
        guard band > 0 else { return 0 }
        return Double(specks) / (Double(band) / Double(scale * scale))
    }

    /// How big a stroke's specks are, in points: across the band from a third
    /// of its radius out to nine tenths, the mean length of the runs of
    /// pixels, along each row, that stand above the average of the 7 by 7
    /// around them by `lift`. A fine mist reads about half a point at 2x;
    /// coarse spatter well over a point.
    public static func speckSize(_ image: CGImage, from a: CGPoint, to b: CGPoint, diameter: CGFloat,
                                 scale: CGFloat, lift: Double = 0.04) -> Double {
        let alphas = alphaPlane(image)
        let width = image.width, height = image.height
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard !alphas.isEmpty, length > 0, diameter > 0, width > 6, height > 6 else { return 0 }
        let radius = diameter / 2
        var runs = 0, pixels = 0
        for y in 3..<(height - 3) {
            var inRun = false
            for x in 3..<(width - 3) {
                let p = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / (length * length)
                let across = abs((p.x - a.x) * dy - (p.y - a.y) * dx) / length / radius
                guard t >= 0.1, t <= 0.9, across >= 1.0 / 3.0, across <= 0.9 else {
                    inRun = false
                    continue
                }
                var around = 0.0
                for j in -3...3 { for i in -3...3 { around += alphas[(y + j) * width + x + i] } }
                let speck = alphas[y * width + x] >= around / 49 + lift
                if speck {
                    pixels += 1
                    if !inRun { runs += 1 }
                }
                inRun = speck
            }
        }
        return runs > 0 ? Double(pixels) / Double(runs) / Double(scale) : 0
    }

    /// The share of the stroke's core (within a third of its radius of the
    /// line) that the paper left bare: pixels under half of the core's
    /// strongest coverage. A soft round tip covers its core solidly and
    /// scores 0; a medium that catches on a grain leaves the valleys open.
    public static func interiorGapFraction(_ image: CGImage, from a: CGPoint, to b: CGPoint,
                                           diameter: CGFloat, scale: CGFloat) -> Double {
        let core = samples(image, from: a, to: b, diameter: diameter, scale: scale)
            .filter { $0.across <= 1.0 / 3.0 }.map(\.alpha)
        guard !core.isEmpty else { return 0 }
        let strongest = core.sorted()[Int(Double(core.count - 1) * 0.95)]
        guard strongest > 0 else { return 0 }
        return Double(core.filter { $0 < strongest / 2 }.count) / Double(core.count)
    }

    /// How much of the radius the stroke takes to fade from strong to faint:
    /// the distance, as a fraction of the radius, between where the averaged
    /// coverage across the stroke drops to 80 per cent of its core and to 20
    /// per cent. Charcoal fades over much of its width; crayon stops at a line.
    public static func edgeSoftness(_ image: CGImage, from a: CGPoint, to b: CGPoint,
                                    diameter: CGFloat, scale: CGFloat) -> Double {
        let bins = 32
        var sum = [Double](repeating: 0, count: bins), count = [Int](repeating: 0, count: bins)
        for s in samples(image, from: a, to: b, diameter: diameter, scale: scale) {
            let bin = Int(s.across / 1.6 * Double(bins))
            guard bin < bins else { continue }
            sum[bin] += s.alpha
            count[bin] += 1
        }
        // Bins no pixel fell in (a thin stroke at 1x) are left out.
        var profile: [(at: Double, alpha: Double)] = []
        for k in 0..<bins where count[k] > 0 {
            let at = (Double(k) + 0.5) / Double(bins) * 1.6
            profile.append((at: at, alpha: sum[k] / Double(count[k])))
        }
        let core: [Double] = profile.filter { $0.at <= 0.25 }.map { $0.alpha }
        guard !core.isEmpty else { return 0 }
        let top = core.reduce(0, +) / Double(core.count)
        guard top > 0 else { return 0 }
        func crossing(_ level: Double) -> Double {
            profile.first { $0.alpha < top * level }?.at ?? 1.6
        }
        return crossing(0.2) - crossing(0.8)
    }

    /// The average coverage of the stroke's core, 0...1.
    public static func meanCoreAlpha(_ image: CGImage, from a: CGPoint, to b: CGPoint,
                                     diameter: CGFloat, scale: CGFloat) -> Double {
        let core = samples(image, from: a, to: b, diameter: diameter, scale: scale)
            .filter { $0.across <= 1.0 / 3.0 }.map(\.alpha)
        guard !core.isEmpty else { return 0 }
        return core.reduce(0, +) / Double(core.count)
    }

    /// How much of what a stroke lays in its core is half-tone rather than
    /// there-or-not: among core pixels it touched at all, the share between a
    /// fifth and four fifths of its strongest coverage. Charcoal shades, so
    /// much of it is half-tone; chalk's powder and crayon's wax land crisp.
    public static func halfToneShare(_ image: CGImage, from a: CGPoint, to b: CGPoint,
                                     diameter: CGFloat, scale: CGFloat) -> Double {
        let core = samples(image, from: a, to: b, diameter: diameter, scale: scale)
            .filter { $0.across <= 0.5 }.map(\.alpha)
        guard !core.isEmpty else { return 0 }
        let strongest = core.sorted()[Int(Double(core.count - 1) * 0.95)]
        guard strongest > 0 else { return 0 }
        let touched = core.filter { $0 >= strongest * 0.05 }
        guard !touched.isEmpty else { return 0 }
        return Double(touched.filter { $0 >= strongest * 0.2 && $0 <= strongest * 0.8 }.count)
            / Double(touched.count)
    }

    /// How alike the stroke's core is with itself `offset` points further
    /// ALONG the stroke, and `offset` points ACROSS it: two correlations,
    /// -1...1. Streaks that run along the drag read high along and low across;
    /// round blotches read the same both ways.
    public static func streakAgreement(_ image: CGImage, from a: CGPoint, to b: CGPoint,
                                       diameter: CGFloat, scale: CGFloat,
                                       offset: CGFloat) -> (along: Double, across: Double) {
        guard let grid = Grid(image, from: a, to: b, diameter: diameter, scale: scale) else { return (0, 0) }
        let shift = max(1, Int((offset * scale).rounded()))
        let band = Int((diameter / 2 * 0.6 * scale).rounded())
        var al: [(Double, Double)] = [], ac: [(Double, Double)] = []
        for j in -band...band {
            for i in grid.alongRange where i + shift < grid.alongRange.upperBound {
                al.append((grid.alpha(i, j), grid.alpha(i + shift, j)))
                if j + shift <= band { ac.append((grid.alpha(i, j), grid.alpha(i, j + shift))) }
            }
        }
        return (correlation(al), correlation(ac))
    }

    /// How much the stroke's width wavers along its length: the spread of the
    /// width (where coverage passes half its strongest), each read averaged
    /// over a few points, as a fraction of the mean width. A ruler-straight
    /// edge scores near 0; a hand's waver scores more.
    public static func widthWaver(_ image: CGImage, from a: CGPoint, to b: CGPoint,
                                  diameter: CGFloat, scale: CGFloat) -> Double {
        guard let grid = Grid(image, from: a, to: b, diameter: diameter, scale: scale) else { return 0 }
        let reach = Int((diameter * 0.8 * scale).rounded())
        var strongest = 0.0
        for i in grid.alongRange { strongest = max(strongest, grid.alpha(i, 0)) }
        guard strongest > 0 else { return 0 }
        var widths: [Double] = []
        for i in grid.alongRange {
            var top = 0, bottom = 0
            for j in 0...reach where grid.alpha(i, j) > strongest / 2 { top = j }
            for j in 0...reach where grid.alpha(i, -j) > strongest / 2 { bottom = j }
            widths.append(Double(top + bottom))
        }
        let window = max(1, Int((3 * scale).rounded()))
        let smoothed = stride(from: 0, to: widths.count - window, by: window).map {
            widths[$0..<($0 + window)].reduce(0, +) / Double(window)
        }
        guard smoothed.count > 2 else { return 0 }
        let mean = smoothed.reduce(0, +) / Double(smoothed.count)
        guard mean > 0 else { return 0 }
        let variance = smoothed.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(smoothed.count)
        return variance.squareRoot() / mean
    }

    /// The stroke's width and darkness, read off its coverage averaged along
    /// its middle stretch: the width, in points, over which that average is at
    /// least half its peak, and the peak itself (0...1), the darkness at the
    /// line. `reach` is how far either side of the line to look, in points.
    /// Grain-broken strokes average out, so the reading is the line a person
    /// sees from a step back, not one row of pixels.
    public static func lineProfile(_ image: CGImage, from a: CGPoint, to b: CGPoint, reach: CGFloat,
                                   scale: CGFloat) -> (width: Double, darkness: Double) {
        guard let grid = Grid(image, from: a, to: b, diameter: reach * 2, scale: scale),
              !grid.alongRange.isEmpty else { return (0, 0) }
        let side = Int((reach * scale).rounded())
        let profile = (-side...side).map { j -> Double in
            var sum = 0.0
            for i in grid.alongRange { sum += grid.alpha(i, j) }
            return sum / Double(grid.alongRange.count)
        }
        let peak = profile.max() ?? 0
        guard peak > 0 else { return (0, 0) }
        let wide = profile.filter { $0 >= peak / 2 }.count
        return (Double(wide) / Double(scale), peak)
    }

    /// How uneven a patch of paint is: the spread of coverage over its mean,
    /// among the pixels in `rect` (points) that hold any. A smooth smear
    /// scores low; one that still shows the paper's tooth scores higher.
    public static func unevenness(_ image: CGImage, in rect: CGRect, scale: CGFloat) -> Double {
        let alphas = alphaPlane(image)
        let width = image.width
        var values: [Double] = []
        for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
            for x in Int(rect.minX * scale)..<Int(rect.maxX * scale)
            where x >= 0 && y >= 0 && x < width && y < image.height {
                let a = alphas[y * width + x]
                if a > 0.01 { values.append(a) }
            }
        }
        guard values.count > 8 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return variance.squareRoot() / mean
    }

    /// The image's coverage, 0...1, top row first.
    private static func alphaPlane(_ image: CGImage) -> [Double] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 3, to: data.count, by: 4).map { Double(data[$0]) / 255 }
    }

    /// The stroke read on its own axes, one step a pixel: `i` along the line
    /// (its middle stretch only), `j` across it.
    private struct Grid {
        let alphas: [Double]
        let width: Int
        let height: Int
        let a: CGPoint
        let unitAlong: CGVector
        let unitAcross: CGVector
        let scale: CGFloat
        let alongRange: Range<Int>

        init?(_ image: CGImage, from a: CGPoint, to b: CGPoint, diameter: CGFloat, scale: CGFloat) {
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 0, diameter > 0, scale > 0 else { return nil }
            alphas = PaintMeasures.alphaPlane(image)
            guard !alphas.isEmpty else { return nil }
            width = image.width
            height = image.height
            self.a = a
            unitAlong = CGVector(dx: (b.x - a.x) / length, dy: (b.y - a.y) / length)
            unitAcross = CGVector(dx: -unitAlong.dy, dy: unitAlong.dx)
            self.scale = scale
            let steps = length * scale
            alongRange = Int((steps * 0.1).rounded())..<Int((steps * 0.9).rounded())
        }

        func alpha(_ i: Int, _ j: Int) -> Double {
            let t = CGFloat(i) / scale, s = CGFloat(j) / scale
            let x = Int(((a.x + unitAlong.dx * t + unitAcross.dx * s) * scale).rounded(.down))
            let y = Int(((a.y + unitAlong.dy * t + unitAcross.dy * s) * scale).rounded(.down))
            guard x >= 0, y >= 0, x < width, y < height else { return 0 }
            return alphas[y * width + x]
        }
    }

    private static func correlation(_ pairs: [(Double, Double)]) -> Double {
        guard pairs.count > 1 else { return 0 }
        let n = Double(pairs.count)
        let ma = pairs.map(\.0).reduce(0, +) / n, mb = pairs.map(\.1).reduce(0, +) / n
        var sab = 0.0, saa = 0.0, sbb = 0.0
        for (x, y) in pairs {
            sab += (x - ma) * (y - mb)
            saa += (x - ma) * (x - ma)
            sbb += (y - mb) * (y - mb)
        }
        guard saa > 0, sbb > 0 else { return 0 }
        return sab / (saa * sbb).squareRoot()
    }

    /// Every pixel alongside the stroke's middle stretch: its coverage, and
    /// how far it is from the line as a fraction of the radius.
    private static func samples(_ image: CGImage, from a: CGPoint, to b: CGPoint,
                                diameter: CGFloat, scale: CGFloat) -> [(alpha: Double, across: Double)] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0, diameter > 0 else { return [] }
        let radius = diameter / 2
        var out: [(Double, Double)] = []
        for y in 0..<height {
            for x in 0..<width {
                let p = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / (length * length)
                guard t >= 0.1, t <= 0.9 else { continue }
                let across = abs((p.x - a.x) * dy - (p.y - a.y) * dx) / length / radius
                guard across <= 1.6 else { continue }
                out.append((Double(data[(y * width + x) * 4 + 3]) / 255, Double(across)))
            }
        }
        return out
    }
}
