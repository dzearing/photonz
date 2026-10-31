import CoreGraphics
import Foundation

/// A flat sketch painted with the Brush, stroke by stroke
/// (`docs/design/brushes.md`, decision 10).
///
/// Ask's model lays out a picture well as a flat SVG of shapes and badly as a
/// list of fifty brush paths (the eval, 2026-10-31: its strokes painted
/// level bands with no subject in them). So for a painting it sketches the
/// picture, and this paints the sketch the way a painter fills a drawing:
/// back to front, each shape covered with strokes laid closer together than
/// the brush is wide, running the way the shape runs (level across a wide
/// band, upright up a trunk, along the long side of anything long, on a
/// slant over anything round), in a few close shades of its colour, lighter
/// on the side the light comes from. Nothing here knows what a shape is: it
/// works the same on any subject.
///
/// Every stroke comes out as a paint_stroke call, so the painting is the same
/// strokes the agent tools would paint, editable and undone one step at a time.
public enum BrushSketch {

    /// The most strokes one sketch is painted in: enough for a scene with a
    /// few dozen things in it, few enough that the painting lands quickly.
    public static let mostStrokes = 900

    public struct Stroke: Hashable, Sendable {
        /// Where the brush goes, in canvas points.
        public var points: [CGPoint]
        /// The pen's press at each point, or empty for a mouse's.
        public var pressures: [Double] = []
        public var colorHex: String
        /// In points.
        public var size: Double
        /// 1 to 100.
        public var opacity: Double
        /// The medium's own settings this stroke is painted with, by id.
        public var settings: [String: Double]
        public var seed: UInt32
    }

    // MARK: The medium asked for

    /// The medium the words of a request name, oil when they name none.
    public static func medium(in request: String) -> BrushMedium {
        let words = AgentDrawingWords.words(request)
        let named: [(Set<String>, BrushMedium)] = [
            (["watercolour", "watercolours", "watercolor", "watercolors", "aquarelle", "gouache"], .watercolour),
            (["oil", "oils", "impasto"], .oil),
            (["charcoal"], .charcoal),
            (["chalk", "chalks", "pastel", "pastels"], .chalk),
            (["crayon", "crayons", "wax"], .crayon),
            (["marker", "markers", "felt"], .marker),
            (["airbrush", "airbrushed", "spray", "sprayed"], .airbrush),
            (["pencil", "pencils", "graphite"], .pencil),
        ]
        for word in words {
            if let found = named.first(where: { $0.0.contains(word) }) { return found.1 }
        }
        return .oil
    }

    // MARK: Painting a sketch

    /// The strokes that paint `art` over a canvas of `size`, in the order
    /// they are laid. The sketch is fitted to cover the canvas.
    public static func strokes(_ art: SVGArtwork, canvas: CGSize, medium: BrushMedium, seed: UInt64 = 1) -> [Stroke] {
        let regions = Self.regions(art, canvas: canvas, seed: seed)
        guard !regions.isEmpty else { return [] }
        var scale = 1.0
        var painted: [Stroke] = []
        for _ in 0..<8 {
            var random = SketchRandom(seed: seed)
            painted = regions.indices.flatMap { index in
                paint(regions[index], under: Array(regions[..<index]), over: Array(regions[(index + 1)...]),
                      canvas: canvas, medium: medium, sizeScale: scale, random: &random)
            }
            guard painted.count > mostStrokes else { break }
            scale *= (Double(painted.count) / Double(mostStrokes)).squareRoot() * 1.08
        }
        return Array(painted.prefix(mostStrokes))
    }

    /// paint_stroke calls for `strokes`, the first starting a Paint layer of
    /// its own so the painting can be hidden or taken away as one.
    public static func calls(_ strokes: [Stroke], medium: BrushMedium) -> [AgentJSON] {
        strokes.enumerated().map { index, stroke in
            var settings: [String: AgentJSON] = ["size": .number(stroke.size.rounded())]
            if stroke.opacity < 100 { settings["opacity"] = .number(stroke.opacity.rounded()) }
            for (id, value) in stroke.settings { settings[id] = .number(value.rounded()) }
            var call: [String: AgentJSON] = [
                "medium": .string(medium.rawValue),
                "color": .string(stroke.colorHex),
                "settings": .object(settings),
                "path": .string(path(stroke.points, pressures: stroke.pressures)),
                "seed": .number(Double(stroke.seed)),
            ]
            if index == 0 { call["newLayer"] = true }
            return .object(call)
        }
    }

    /// Points written the way paint_stroke's path takes them.
    static func path(_ points: [CGPoint], pressures: [Double] = []) -> String {
        points.enumerated().map { index, point in
            let pair = "\(Int(point.x.rounded())),\(Int(point.y.rounded()))"
            guard index < pressures.count else { return pair }
            return pair + "," + String(format: "%.2f", min(1, max(0, pressures[index])))
        }.joined(separator: " ")
    }

    // MARK: The sketch's shapes, in canvas points

    struct Region {
        var rings: [[CGPoint]]
        var fill: Paint?
        var line: String?
        var lineWidth: CGFloat
        var opacity: Double
        var box: CGRect

        /// Whether `p` is inside the shape, its box asked first.
        func covers(_ p: CGPoint) -> Bool {
            p.x >= box.minX && p.x <= box.maxX && p.y >= box.minY && p.y <= box.maxY && BrushSketch.inside(p, rings)
        }
    }

    static func regions(_ art: SVGArtwork, canvas: CGSize, seed: UInt64 = 1) -> [Region] {
        var random = SketchRandom(seed: seed ^ 0x5EED_0F_ED6E)
        let from = art.viewBox.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil } ?? art.bounds
        guard !from.isNull, from.width > 0, from.height > 0, canvas.width > 0, canvas.height > 0 else { return [] }
        let scale = max(canvas.width / from.width, canvas.height / from.height)
        let dx = (canvas.width - from.width * scale) / 2 - from.minX * scale
        let dy = (canvas.height - from.height * scale) / 2 - from.minY * scale
        func place(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale + dx, y: p.y * scale + dy) }
        return art.parts.compactMap { part in
            var rings = outline(part.shape).map { $0.map(place) }.filter { $0.count >= 2 }
            guard !rings.isEmpty else { return nil }
            let fill = part.fillPaint ?? part.fill.map(Paint.solid)
            if fill != nil {
                let placed = rings.flatMap { $0 }.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
                let amplitude = min(min(placed.width, placed.height) * 0.06, max(canvas.width, canvas.height) * 0.012)
                rings = rings.map { loosened($0, canvas: canvas, amplitude: amplitude, random: &random) }
            }
            let line = part.strokeWidth > 0 ? part.stroke : nil
            guard fill != nil || line != nil else { return nil }
            let box = rings.flatMap { $0 }.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
            return Region(rings: rings, fill: fill, line: line, lineWidth: part.strokeWidth * scale,
                          opacity: part.opacity, box: box)
        }
    }

    /// A ring's edge loosened the way a hand's is: walked in short steps and
    /// each moved along the edge's normal by a slow, uneven wave of at most
    /// `amplitude`, so a straight ridge or a perfect circle in the sketch is
    /// painted as an edge a person would paint. Points on the canvas's border
    /// stay put, so a shape that fills to the edge still does.
    static func loosened(_ ring: [CGPoint], canvas: CGSize, amplitude: CGFloat,
                         random: inout SketchRandom) -> [CGPoint] {
        guard ring.count >= 3, amplitude >= 1 else { return ring }
        let closed = ring + [ring[0]]
        let perimeter = zip(closed, closed.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        guard perimeter > 0 else { return ring }
        let step = max(4, perimeter / 160)
        // Walk the edge in steps, keeping every corner.
        var walked: [CGPoint] = []
        for (a, b) in zip(closed, closed.dropFirst()) {
            let length = hypot(b.x - a.x, b.y - a.y)
            let pieces = max(1, Int((length / step).rounded(.up)))
            for i in 0..<pieces {
                let t = CGFloat(i) / CGFloat(pieces)
                walked.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        let wave = max(40, amplitude * 12)
        let waves: [(length: CGFloat, weight: CGFloat, phase: CGFloat)] = [
            (wave, 0.6, CGFloat(random.between(0, 2 * .pi))),
            (wave * 0.43, 0.28, CGFloat(random.between(0, 2 * .pi))),
            (wave * 0.17, 0.12, CGFloat(random.between(0, 2 * .pi))),
        ]
        let count = walked.count
        var travelled: CGFloat = 0
        return walked.indices.map { index in
            let p = walked[index]
            if index > 0 { travelled += hypot(p.x - walked[index - 1].x, p.y - walked[index - 1].y) }
            let before = walked[(index + count - 1) % count], after = walked[(index + 1) % count]
            var n = CGPoint(x: -(after.y - before.y), y: after.x - before.x)
            let length = hypot(n.x, n.y)
            guard length > 0 else { return p }
            n = CGPoint(x: n.x / length, y: n.y / length)
            let toBorder = min(p.x, p.y, canvas.width - p.x, canvas.height - p.y)
            let hold = max(0, min(1, (toBorder - 1) / amplitude))
            let offset = waves.reduce(0) { $0 + $1.weight * sin(2 * .pi * travelled / $1.length + $1.phase) }
            return CGPoint(x: p.x + n.x * offset * amplitude * hold, y: p.y + n.y * offset * amplitude * hold)
        }
    }

    /// A shape as rings of points, its curves walked in short straight steps.
    static func outline(_ shape: SVGArtwork.Shape) -> [[CGPoint]] {
        switch shape {
        case .rect(let box, _):
            return [[CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                     CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]]
        case .ellipse(let box):
            return [(0..<40).map { step in
                let a = Double(step) / 40 * 2 * .pi
                return CGPoint(x: box.midX + box.width / 2 * cos(a), y: box.midY + box.height / 2 * sin(a))
            }]
        case .path(let outline):
            return outline.rings.map { ring in
                guard let first = ring.first else { return [] }
                var points = [first.point]
                let count = ring.count
                let runs = outline.closed ? count : count - 1
                for index in 0..<max(runs, 0) {
                    let a = ring[index], b = ring[(index + 1) % count]
                    if a.handleOut == nil, b.handleIn == nil {
                        points.append(b.point)
                        continue
                    }
                    let c1 = CGPoint(x: a.point.x + (a.handleOut?.x ?? 0), y: a.point.y + (a.handleOut?.y ?? 0))
                    let c2 = CGPoint(x: b.point.x + (b.handleIn?.x ?? 0), y: b.point.y + (b.handleIn?.y ?? 0))
                    for step in 1...10 {
                        let t = CGFloat(step) / 10, s = 1 - t
                        points.append(CGPoint(
                            x: s * s * s * a.point.x + 3 * s * s * t * c1.x + 3 * s * t * t * c2.x + t * t * t * b.point.x,
                            y: s * s * s * a.point.y + 3 * s * s * t * c1.y + 3 * s * t * t * c2.y + t * t * t * b.point.y))
                    }
                }
                return points
            }
        }
    }

    // MARK: Filling a shape

    /// `under` and `over` are the sketch's other shapes, painted before and
    /// after this one: what its edge is seen against.
    static func paint(_ region: Region, under: [Region] = [], over: [Region] = [], canvas: CGSize, medium: BrushMedium,
                      sizeScale: Double, random: inout SketchRandom) -> [Stroke] {
        var strokes: [Stroke] = []
        if let fill = region.fill {
            strokes += self.fill(region, paint: fill, canvas: canvas, medium: medium, sizeScale: sizeScale, random: &random)
            strokes += contour(region, paint: fill, against: under, covered: over, strokes: strokes,
                               canvas: canvas, medium: medium, random: &random)
        }
        if let line = region.line {
            strokes += self.line(region, hex: line, canvas: canvas, medium: medium, random: &random)
        }
        return strokes
    }

    static func area(_ rings: [[CGPoint]]) -> CGFloat {
        abs(rings.reduce(0) { total, ring in
            total + zip(ring, ring.dropFirst() + ring.prefix(1)).reduce(0) { $0 + ($1.0.x * $1.1.y - $1.1.x * $1.0.y) }
        } / 2)
    }

    /// Whether `p` is inside the rings, even-odd.
    static func inside(_ p: CGPoint, _ rings: [[CGPoint]]) -> Bool {
        var crossings = 0
        for ring in rings {
            for (a, b) in zip(ring, ring.dropFirst() + ring.prefix(1)) where (a.y > p.y) != (b.y > p.y) {
                let x = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
                if x > p.x { crossings += 1 }
            }
        }
        return crossings % 2 == 1
    }

    /// The way a shape runs: its long axis, from points spread over it.
    static func axis(_ region: Region) -> (angle: CGFloat, elongation: CGFloat, centre: CGPoint) {
        let box = region.box
        var points: [CGPoint] = []
        let steps = 24
        for i in 0..<steps {
            for j in 0..<steps {
                let p = CGPoint(x: box.minX + box.width * (CGFloat(i) + 0.5) / CGFloat(steps),
                                y: box.minY + box.height * (CGFloat(j) + 0.5) / CGFloat(steps))
                if inside(p, region.rings) { points.append(p) }
            }
        }
        guard points.count >= 3 else { return (box.width >= box.height ? 0 : .pi / 2, 1, CGPoint(x: box.midX, y: box.midY)) }
        let n = CGFloat(points.count)
        let mx = points.reduce(0) { $0 + $1.x } / n, my = points.reduce(0) { $0 + $1.y } / n
        var xx: CGFloat = 0, yy: CGFloat = 0, xy: CGFloat = 0
        for p in points {
            xx += (p.x - mx) * (p.x - mx)
            yy += (p.y - my) * (p.y - my)
            xy += (p.x - mx) * (p.y - my)
        }
        let angle = 0.5 * atan2(2 * xy, xx - yy)
        let trace = xx + yy, det = xx * yy - xy * xy
        let gap = max(0, trace * trace / 4 - det).squareRoot()
        let major = trace / 2 + gap, minor = max(trace / 2 - gap, 1e-6)
        return (angle, (major / minor).squareRoot(), CGPoint(x: mx, y: my))
    }

    static func fill(_ region: Region, paint: Paint, canvas: CGSize, medium: BrushMedium, sizeScale: Double,
                     random: inout SketchRandom) -> [Stroke] {
        let area = Self.area(region.rings)
        guard area > 2 else { return [] }
        let canvasArea = canvas.width * canvas.height
        let large = area > canvasArea * 0.2
        let (axisAngle, elongation, centre) = axis(region)
        let angle: CGFloat
        if large || region.box.width > region.box.height * 2.2 {
            angle = CGFloat(random.between(-0.03, 0.03))
        } else if elongation >= 1.5 {
            angle = axisAngle
        } else {
            // Round things are hatched on a rising slant, as a hand moves.
            angle = CGFloat(-0.55 + random.between(-0.15, 0.15))
        }
        let c = cos(angle), s = sin(angle)
        func toUV(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * c + p.y * s, y: -p.x * s + p.y * c) }
        func fromUV(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * c - p.y * s, y: p.x * s + p.y * c) }
        let rings = region.rings.map { $0.map(toUV) }
        let all = rings.flatMap { $0 }
        guard let vLow = all.map(\.y).min(), let vHigh = all.map(\.y).max() else { return [] }
        let across = vHigh - vLow
        let longest = max(canvas.width, canvas.height)
        let widest = longest / 10, narrowest = max(3, longest / 160)
        // A big area is worked with a brush a painter would hold, not a broom:
        // a brush a seventh of the canvas wide combed it like brushed metal
        // (2026-10-31).
        var size = min(max(across / 2.6, narrowest) * sizeScale, widest * (large ? 0.9 : 1.4))
        // A wash bleeds well past where the brush went (`BrushMedium.reach`).
        if medium == .watercolour { size *= 0.75 }
        size = min(size, BrushSize.range.upperBound)
        var spine = false
        if across < size * 1.1 {
            size = max(across * 0.95, 2)
            spine = true
        }
        let rows: [CGFloat]
        if spine {
            rows = [(vLow + vHigh) / 2]
        } else {
            // The first and last rows sit half a brush in from an edge the
            // edge pass paints, so a level horizon is not crenellated by
            // their ends; at the canvas's border they hang over it instead.
            let topBorder = region.box.minY <= 2, bottomBorder = region.box.maxY >= canvas.height - 2
            let first = vLow + size * (topBorder || medium == .watercolour ? 0.3 : 0.5)
            let last = vHigh - size * (bottomBorder || medium == .watercolour ? 0.3 : 0.5)
            let gap: CGFloat = medium == .watercolour ? 0.9 : 0.55
            let count = max(1, Int(((last - first) / (size * gap)).rounded(.up)) + 1)
            rows = count == 1 ? [(first + last) / 2]
                : (0..<count).map { first + (last - first) * CGFloat($0) / CGFloat(count - 1) }
        }
        let small = area < canvasArea * 0.06
        let radius = max(region.box.width, region.box.height) / 2
        var strokes: [Stroke] = []
        /// Rows of strokes of one size; `narrowerThan` keeps only the spans
        /// narrower than it (the corners and tips a bigger brush left).
        func lay(_ rows: [CGFloat], size: CGFloat, narrowerThan: CGFloat? = nil, band: CGFloat = 0.4,
                 random: inout SketchRandom) {
            for v in rows {
                let border = { (u: CGFloat, at: CGFloat) in atEdge(fromUV(CGPoint(x: u, y: at)), canvas, slack: 2) }
                let spans = band > 0 ? banded(rings, at: v, half: size * band, low: vLow, high: vHigh, border: border)
                    : chords(rings, at: v)
                for (u0, u1) in spans {
                    if let narrowerThan, u1 - u0 >= narrowerThan { continue }
                    var from = u0, to = u1
                    // A stroke that reaches the canvas's edge runs off it, so
                    // its thin end falls outside. Anywhere else it runs to
                    // the shape's edge, its end tapering there.
                    let start = fromUV(CGPoint(x: u0, y: v)), end = fromUV(CGPoint(x: u1, y: v))
                    // Far enough that its frayed end lifts off past the edge too.
                    if atEdge(start, canvas, slack: size * 0.3) { from -= size * 1.3 }
                    if atEdge(end, canvas, slack: size * 0.3) { to += size * 1.3 }
                    let length = to - from
                    // A span shorter than the brush is wide would be a blob
                    // (over a peak, say): the edge pass paints it.
                    guard length >= size * 0.5 || rows.count == 1 else { continue }
                    let target = size * CGFloat(large ? random.between(2.5, 5) : random.between(3.5, 6.5))
                    let pieces = max(1, Int((length / target).rounded()))
                    var cuts = (0...pieces).map { from + length * CGFloat($0) / CGFloat(pieces) }
                    for index in cuts.indices.dropFirst().dropLast() {
                        cuts[index] += length / CGFloat(pieces) * CGFloat(random.between(-0.25, 0.25))
                    }
                    for (a, b) in zip(cuts, cuts.dropFirst()) {
                        let overlap = size * 0.4
                        let pa = max(from, a - overlap), pb = min(to, b + overlap)
                        // Enough points that a row along a wavy edge can follow it.
                        let count = min(10, max(3, Int(((pb - pa) / (size * 0.9)).rounded(.up)) + 1))
                        let bow = size * CGFloat(random.between(-0.12, 0.12))
                        let own = spine ? size : size * CGFloat(random.between(0.85, 1.15))
                        let middle = (pa + pb) / 2
                        // A slant, its ends never more than a quarter brush off the row.
                        // Over a big area the strokes cross at livelier angles, as a hand
                        // working a sky does.
                        // The rows along its top and bottom stay level, so
                        // no corner of canvas is left bare.
                        let lively = large && v - vLow > size * 1.2 && vHigh - v > size * 1.2
                        let tilt = CGFloat(random.between(-1, 1))
                            * min(lively ? 0.2 : 0.09, size * (lively ? 0.6 : 0.25) / max((pb - pa) / 2, 1))
                        let rowV = v + size * CGFloat(random.between(-0.06, 0.06))
                        let points = (0..<count).map { step -> CGPoint in
                            let t = CGFloat(step) / CGFloat(count - 1)
                            let u = pa + (pb - pa) * t
                            let wanted = rowV + bow * sin(.pi * t) + tilt * (u - middle)
                            return fromUV(CGPoint(x: u, y: spine ? wanted
                                : keptInside(wanted, at: u, rings: rings, room: own * 0.45,
                                             border: { atEdge(fromUV($0), canvas, slack: 2) })))
                        }
                        let mid = fromUV(CGPoint(x: middle, y: rowV))
                        let hex = shade(paint, region: region, at: mid, centre: centre, radius: radius,
                                        lit: !large, random: &random)
                        strokes.append(Stroke(points: points, colorHex: hex, size: Double(own),
                                              opacity: max(1, min(100, region.opacity * 100)),
                                              settings: varied(mediumSettings(medium, large: large, small: small),
                                                               random: &random),
                                              seed: random.seed()))
                    }
                }
            }
        }
        lay(rows, size: size, random: &random)
        // The tips and corners the big brush could not reach, with one half its size.
        let half: CGFloat = size / 2
        if !spine, half >= narrowest, medium != .watercolour {
            let first = vLow + half * 0.3, last = vHigh - half * 0.3
            let count = max(1, Int(((last - first) / (half * 0.6)).rounded(.up)) + 1)
            let fine: [CGFloat] = count == 1 ? [(first + last) / 2]
                : (0..<count).map { first + (last - first) * CGFloat($0) / CGFloat(count - 1) }
            // Small enough that a corner poking past a slope does not show,
            // and cutting it to the slope would leave a peak bare.
            lay(fine, size: half, narrowerThan: size * 1.6, band: 0, random: &random)
        }
        // Broken colour: short dabs of nearby shades over a sizeable area,
        // the way a painter works back into a block-in, so it is never one
        // flat run of stripes.
        if !spine, medium != .watercolour, area > canvasArea * 0.02 {
            // Over a big area (a sky) fewer, smaller and nearly level, so they
            // break it up without reading as patches.
            let dab = size * (large ? 0.35 : 0.55)
            let wanted = min(large ? 18 : 24, Int(area / (size * size * (large ? 5 : 4))))
            var made = 0, tries = 0
            while made < wanted, tries < wanted * 8 {
                tries += 1
                let p = CGPoint(x: random.between(Double(region.box.minX), Double(region.box.maxX)),
                                y: random.between(Double(region.box.minY), Double(region.box.maxY)))
                let turn = angle + CGFloat(large ? random.between(-0.12, 0.12) : random.between(-0.4, 0.4))
                let reach = dab * CGFloat(random.between(0.6, 2.4))
                let d = CGPoint(x: cos(turn) * reach, y: sin(turn) * reach)
                let ends = [CGPoint(x: p.x - d.x, y: p.y - d.y), CGPoint(x: p.x + d.x, y: p.y + d.y)]
                // Its sides inside too, so a dab near the edge never pokes past it.
                let width = dab * 0.65
                let side = CGPoint(x: -sin(turn) * width, y: cos(turn) * width)
                let corners = ([p] + ends).flatMap { [CGPoint(x: $0.x + side.x, y: $0.y + side.y),
                                                      CGPoint(x: $0.x - side.x, y: $0.y - side.y)] }
                guard ([p] + ends + corners).allSatisfy({ inside($0, region.rings) || atEdge($0, canvas, slack: 0) })
                else { continue }
                let bend = dab * CGFloat(random.between(-0.25, 0.25))
                let middle = CGPoint(x: p.x - sin(turn) * bend, y: p.y + cos(turn) * bend)
                let near = shade(paint, region: region, at: p, centre: centre, radius: radius, lit: !large, random: &random)
                let hex = large ? jitter(near, light: 0, random: &random) : broken(near, random: &random)
                strokes.append(Stroke(points: [ends[0], middle, ends[1]], colorHex: hex,
                                      size: Double(dab) * random.between(0.55, 1.3),
                                      opacity: max(1, min(100, region.opacity * 100)),
                                      settings: varied(mediumSettings(medium, large: large, small: !large), random: &random),
                                      seed: random.seed()))
                made += 1
            }
        }
        return strokes
    }

    /// The shape's silhouette painted along its length with a smaller brush,
    /// just inside it, the way a painter cuts in an edge after blocking in: a
    /// peak stays a peak and a curve a curve, where the rows that fill it
    /// end in steps. Only where the shape is seen against something of
    /// another colour: not along the canvas's border, not against a
    /// neighbour of nearly its own colour (a mountain's lit half against its
    /// shadow half, where an edge would read as a drawn line), and not where
    /// a later shape covers it.
    static func contour(_ region: Region, paint: Paint, against under: [Region], covered over: [Region],
                        strokes filled: [Stroke], canvas: CGSize, medium: BrushMedium,
                        random: inout SketchRandom) -> [Stroke] {
        guard medium != .watercolour, let biggest = filled.map(\.size).max(), filled.count > 1 else { return [] }
        let longest = max(canvas.width, canvas.height)
        let edge = CGFloat(max(biggest * 0.42, max(3, Double(longest) / 240)))
        guard edge < CGFloat(biggest) * 0.8 else { return [] }
        let centre = CGPoint(x: region.box.midX, y: region.box.midY)
        let radius = max(region.box.width, region.box.height) / 2
        let lit = Self.area(region.rings) <= canvas.width * canvas.height * 0.2
        func behind(_ p: CGPoint) -> String? {
            for other in under.reversed() where other.fill != nil && other.covers(p) {
                return other.fill.map { colour($0, in: other.box, at: p) }
            }
            return nil
        }
        var strokes: [Stroke] = []
        for ring in region.rings where ring.count >= 3 {
            let count = ring.count
            // Each run of edge that shows against another colour.
            var runs: [[CGPoint]] = []
            var run: [CGPoint] = []
            var runIsSeam = false
            /// The colour beyond a seam, by the index its run will have.
            var blend: [Int: String] = [:]
            func close() {
                if run.count >= 2 { runs.append(run) } else { blend[runs.count] = nil }
                run = []
            }
            for index in 0..<count {
                let a = ring[index], b = ring[(index + 1) % count]
                let length = hypot(b.x - a.x, b.y - a.y)
                guard length > 0.5 else { continue }
                var n = CGPoint(x: -(b.y - a.y) / length, y: (b.x - a.x) / length)
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                if inside(CGPoint(x: mid.x + n.x * 2, y: mid.y + n.y * 2), region.rings) { n = CGPoint(x: -n.x, y: -n.y) }
                let out = CGPoint(x: mid.x + n.x * edge * 1.5, y: mid.y + n.y * edge * 1.5)
                let border = atEdge(a, canvas, slack: 2) && atEdge(b, canvas, slack: 2)
                let hidden = over.contains { $0.fill != nil && $0.opacity > 0.9 && $0.covers(mid) && $0.covers(out) }
                let outside = behind(out)
                let seam = outside.map { similar($0, colour(paint, in: region.box, at: mid)) } ?? false
                if border || hidden {
                    close()
                    continue
                }
                // A seam against a neighbour of nearly its own colour is
                // painted in the two colours mixed: a soft wet join where an
                // edge of its own colour reads as a drawn line.
                if seam != runIsSeam, !run.isEmpty { close() }
                runIsSeam = seam
                blend[runs.count] = seam ? outside : nil
                let inward = CGPoint(x: -n.x * edge * 0.5, y: -n.y * edge * 0.5)
                if run.isEmpty { run.append(CGPoint(x: a.x + inward.x, y: a.y + inward.y)) }
                run.append(CGPoint(x: b.x + inward.x, y: b.y + inward.y))
                // A sharp corner ends the stroke, so a peak stays a point.
                let c = ring[(index + 2) % count]
                let turn = abs(atan2((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x),
                                     (b.x - a.x) * (c.x - b.x) + (b.y - a.y) * (c.y - b.y)))
                if turn > 0.6 { close() }
            }
            close()
            for (number, run) in runs.enumerated() {
                var start = 0
                while start < run.count - 1 {
                    var end = start + 1
                    var length: CGFloat = 0
                    while end < run.count - 1, length < edge * 10 {
                        length += hypot(run[end].x - run[end - 1].x, run[end].y - run[end - 1].y)
                        end += 1
                    }
                    let piece = Array(run[start...end])
                    let step = max(1, piece.count / 10)
                    var points = stride(from: 0, to: piece.count, by: step).map { piece[$0] }
                    if let last = piece.last, points.last != last { points.append(last) }
                    let travelled = zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
                    if points.count >= 2, travelled >= edge {
                        let at = points[points.count / 2]
                        var hex = shade(paint, region: region, at: at, centre: centre, radius: radius, lit: lit,
                                        random: &random)
                        if let beyond = blend[number] { hex = mix(hex, beyond) }
                        strokes.append(Stroke(points: points, colorHex: hex,
                                              size: Double(edge), opacity: max(1, min(100, region.opacity * 100)),
                                              settings: mediumSettings(medium, large: !lit, small: true),
                                              seed: random.seed()))
                    }
                    start = end
                }
            }
        }
        return strokes
    }

    /// Two colours close enough that an edge between them is a seam, not a silhouette.
    static func similar(_ a: String, _ b: String) -> Bool {
        let x = AgentGroupRecolour.rgb(a), y = AgentGroupRecolour.rgb(b)
        return abs(x.r - y.r) + abs(x.g - y.g) + abs(x.b - y.b) < 0.22
    }

    /// Oil's Load and Smear for a stroke: a full brush and a light drag, so
    /// each shape keeps its own colour over what is under it (at the brush's
    /// own Smear a mountain over a sky turned the sky's grey, 2026-10-31);
    /// the big areas blend a little more, small things the least.
    /// Watercolour's the same way: the big washes wet, the shapes over them
    /// drier so they hold their edge instead of blooming into mud.
    static func mediumSettings(_ medium: BrushMedium, large: Bool, small: Bool) -> [String: Double] {
        switch medium {
        case .oil:
            if large { return ["load": 95, "smear": 16] }
            return small ? ["load": 100, "smear": 3] : ["load": 100, "smear": 5]
        case .watercolour:
            if large { return ["wetness": 50, "bleed": 25] }
            return small ? ["wetness": 15, "bleed": 5] : ["wetness": 30, "bleed": 12]
        default:
            return [:]
        }
    }

    /// A hand never loads the brush the same twice: oil's Load and Smear
    /// moved a little each stroke, so no two strokes carry the same ridges.
    static func varied(_ settings: [String: Double], random: inout SketchRandom) -> [String: Double] {
        var out = settings
        if let load = settings["load"] { out["load"] = min(100, max(40, load + random.between(-25, 0))) }
        if let smear = settings["smear"] { out["smear"] = min(100, max(0, smear + random.between(0, 14))) }
        return out
    }

    /// `v` moved, where it has to be, to sit at least `room` inside the
    /// shape's edge straight above and below it at `u` (in the rows' own
    /// frame), so a row along a wavy top or bottom follows the edge instead
    /// of poking out where it dips. An edge on the canvas's border holds
    /// nothing back: rows hang over it on purpose. Where the shape is
    /// thinner than that there, the row goes down its middle.
    static func keptInside(_ v: CGFloat, at u: CGFloat, rings: [[CGPoint]], room: CGFloat,
                           border: (CGPoint) -> Bool) -> CGFloat {
        var crossings: [CGFloat] = []
        for ring in rings {
            for (a, b) in zip(ring, ring.dropFirst() + ring.prefix(1)) where (a.x > u) != (b.x > u) {
                crossings.append(a.y + (u - a.x) / (b.x - a.x) * (b.y - a.y))
            }
        }
        guard let top = crossings.filter({ $0 <= v + room }).max(),
              let bottom = crossings.filter({ $0 >= v - room }).min(), bottom > top else { return v }
        let low = border(CGPoint(x: u, y: top)) ? -CGFloat.infinity : top + room
        let high = border(CGPoint(x: u, y: bottom)) ? CGFloat.infinity : bottom - room
        if low > high { return (top + bottom) / 2 }
        return min(max(v, low), high)
    }

    /// Where a level line at `v` crosses into and out of the rings, as spans.
    static func chords(_ rings: [[CGPoint]], at v: CGFloat) -> [(CGFloat, CGFloat)] {
        var crossings: [CGFloat] = []
        for ring in rings {
            for (a, b) in zip(ring, ring.dropFirst() + ring.prefix(1)) where (a.y > v) != (b.y > v) {
                crossings.append(a.x + (v - a.y) / (b.y - a.y) * (b.x - a.x))
            }
        }
        crossings.sort()
        return stride(from: 0, to: crossings.count - 1, by: 2).map { (crossings[$0], crossings[$0 + 1]) }
    }

    /// The spans at `v`, each cut to where the shape is still under it a
    /// little above and below, so a level stroke a brush wide laid across a
    /// slope does not poke a corner out past the slope. An end on the
    /// canvas's border cuts nothing: the stroke runs off the canvas there.
    static func banded(_ rings: [[CGPoint]], at v: CGFloat, half: CGFloat, low: CGFloat, high: CGFloat,
                       border: (CGFloat, CGFloat) -> Bool) -> [(CGFloat, CGFloat)] {
        // Near the shape's top or bottom the level comes in to halfway, so the
        // first and last rows are cut a little, never to a sliver.
        let up = max(v - half, (v + low) / 2), down = min(v + half, (v + high) / 2)
        let bands = [(up, chords(rings, at: up)), (down, chords(rings, at: down))]
        return chords(rings, at: v).compactMap { span in
            var from = span.0, to = span.1
            for (level, other) in bands {
                // Only the row's two ends are trimmed, to the outermost spans
                // it overlaps there: a wavy edge crossing the level breaks it
                // into pieces, and keeping just one dropped the rest of the
                // row and left the canvas bare (the try path, 2026-10-31).
                let hits = other.filter { $0.1 > from && $0.0 < to }
                guard let first = hits.map(\.0).min(), let last = hits.map(\.1).max() else { continue }
                if !border(first, level) { from = max(from, first) }
                if !border(last, level) { to = min(to, last) }
            }
            return to > from ? (from, to) : nil
        }
    }

    static func atEdge(_ p: CGPoint, _ canvas: CGSize, slack: CGFloat) -> Bool {
        p.x <= slack || p.y <= slack || p.x >= canvas.width - slack || p.y >= canvas.height - slack
    }

    /// A line in the sketch, painted along its length at its own width.
    static func line(_ region: Region, hex: String, canvas: CGSize, medium: BrushMedium,
                     random: inout SketchRandom) -> [Stroke] {
        let size = Double(max(2, min(region.lineWidth, BrushSize.range.upperBound)))
        var strokes: [Stroke] = []
        for ring in region.rings {
            var run = ring
            if region.fill != nil, let first = ring.first { run.append(first) }
            // Walked in pieces of a few points, as a hand paints a long line.
            var start = 0
            while start < run.count - 1 {
                var end = start + 1
                var length: CGFloat = 0
                while end < run.count - 1, length < CGFloat(size) * 14 {
                    length += hypot(run[end].x - run[end - 1].x, run[end].y - run[end - 1].y)
                    end += 1
                }
                let piece = Array(run[start...end])
                let step = max(1, piece.count / 6)
                var points = stride(from: 0, to: piece.count, by: step).map { piece[$0] }
                if let last = piece.last, points.last != last { points.append(last) }
                if points.count >= 2 {
                    var settings: [String: Double] = [:]
                    if medium == .oil { settings = ["load": 90, "smear": 10] }
                    strokes.append(Stroke(points: points, colorHex: jitter(hex, light: 0, random: &random), size: size,
                                          opacity: max(1, min(100, region.opacity * 100)), settings: settings,
                                          seed: random.seed()))
                }
                start = end
            }
        }
        return strokes
    }

    // MARK: Colour

    /// The colour the sketch has at `p`, its gradient read there.
    static func colour(_ paint: Paint, in box: CGRect, at p: CGPoint) -> String {
        guard paint.isGradient, box.width > 0, box.height > 0 else { return paint.hex }
        let x = (p.x - box.minX) / box.width, y = (p.y - box.minY) / box.height
        let t: Double
        switch paint.kind {
        case .linear:
            let a = paint.angle * .pi / 180
            let d = CGPoint(x: sin(a), y: -cos(a))
            let span = abs(d.x) + abs(d.y)
            t = Double(((x - 0.5) * d.x + (y - 0.5) * d.y) / span + 0.5)
        case .radial:
            let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)]
            let reach = corners.map { hypot($0.x - paint.center.x, $0.y - paint.center.y) }.max() ?? 1
            t = Double(hypot(x - paint.center.x, y - paint.center.y) / max(reach, 0.001))
        default:
            return paint.hex
        }
        guard let rgba = paint.color(at: t) else { return paint.hex }
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(rgba.r), byte(rgba.g), byte(rgba.b))
    }

    /// One stroke's colour: the sketch's colour there, a close shade of it,
    /// lighter toward the light (from the upper left) on a shape that has a
    /// lit side and a shadow side.
    static func shade(_ paint: Paint, region: Region, at p: CGPoint, centre: CGPoint, radius: CGFloat, lit: Bool,
                      random: inout SketchRandom) -> String {
        var light = 0.0
        if lit, radius > 0 {
            let toward = CGPoint(x: -0.5, y: -0.85)
            let reach = ((p.x - centre.x) * toward.x + (p.y - centre.y) * toward.y) / radius
            light = 0.08 * Double(max(-1, min(1, reach)))
        }
        return jitter(colour(paint, in: region.box, at: p), light: light, random: &random)
    }

    /// Two colours half and half.
    static func mix(_ a: String, _ b: String) -> String {
        let x = AgentGroupRecolour.rgb(a), y = AgentGroupRecolour.rgb(b)
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte((x.r + y.r) / 2), byte((x.g + y.g) / 2), byte((x.b + y.b) / 2))
    }

    /// A shade a little further off: a dab of broken colour.
    static func broken(_ hex: String, random: inout SketchRandom) -> String {
        var hsl = AgentGroupRecolour.hsl(AgentGroupRecolour.rgb(hex))
        hsl.h = (hsl.h + random.between(-0.025, 0.025) + 1).truncatingRemainder(dividingBy: 1)
        hsl.s = min(1, max(0, hsl.s + random.between(-0.08, 0.1)))
        hsl.l = min(0.97, max(0.03, hsl.l + random.between(-0.07, 0.07)))
        return AgentGroupRecolour.hexString(fromHSL: hsl)
    }

    static func jitter(_ hex: String, light: Double, random: inout SketchRandom) -> String {
        var hsl = AgentGroupRecolour.hsl(AgentGroupRecolour.rgb(hex))
        hsl.h = (hsl.h + random.between(-0.015, 0.015) + 1).truncatingRemainder(dividingBy: 1)
        hsl.s = min(1, max(0, hsl.s + random.between(-0.06, 0.06)))
        hsl.l = min(0.97, max(0.03, hsl.l + light + random.between(-0.045, 0.045)))
        return AgentGroupRecolour.hexString(fromHSL: hsl)
    }
}

/// The same numbers from the same seed, so a sketch paints the same way twice.
struct SketchRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func between(_ low: Double, _ high: Double) -> Double {
        low + (high - low) * Double(next() >> 11) / Double(1 << 53)
    }

    mutating func seed() -> UInt32 { UInt32(truncatingIfNeeded: next() % UInt64(UInt32.max - 1)) + 1 }
}
