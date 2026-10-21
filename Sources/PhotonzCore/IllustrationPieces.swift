import CoreGraphics
import Foundation

// The illustrator's reusable pieces (`docs/design/ask.md`, "Drawing an
// illustration"): the techniques a graphic artist repeats, each a function a
// scene is composed from rather than written point by point. A ridge with
// broken, lopsided peaks; the shadow face along a peak's crease; ridge
// highlights and a snow cap cut from the lit side; a pine repeated into a
// treeline; an even ray burst; glitter on water; a reflection; rolling hills;
// a cloud; stars; birds; a lighthouse; a skyline; a fox.

enum IllustrationPieces {

    // MARK: Ridges

    struct Ridge {
        /// Left to right; x never goes back.
        var points: [CGPoint]
        var peaks: [Int]
        var valleys: [Int]

        /// The ridge's height at `x`.
        func y(at x: CGFloat) -> CGFloat {
            guard let first = points.first, let last = points.last else { return 0 }
            if x <= first.x { return first.y }
            if x >= last.x { return last.y }
            var low = 0, high = points.count - 1
            while high - low > 1 {
                let middle = (low + high) / 2
                if points[middle].x <= x { low = middle } else { high = middle }
            }
            let a = points[low], b = points[high]
            let t = b.x > a.x ? (x - a.x) / (b.x - a.x) : 0
            return a.y + (b.y - a.y) * t
        }
    }

    /// A mountain range across `block`: `count` peaks, lopsided, the one
    /// nearest `focusX` the tallest, broken by midpoint displacement.
    static func ridge(in block: CGRect, peaks count: Int, roughness: CGFloat, focusX: CGFloat?,
                      random: inout IllustrationRandom) -> Ridge {
        let slots = max(1, count)
        let slot = block.width / CGFloat(slots)
        var peakPoints: [CGPoint] = []
        for index in 0..<slots {
            let x = block.minX + slot * (CGFloat(index) + 0.5) + random.signed() * slot * 0.22
            let lift = random.range(0.05, 0.42)
            peakPoints.append(CGPoint(x: x, y: block.minY + block.height * lift))
        }
        if let focusX, let nearest = peakPoints.indices.min(by: { abs(peakPoints[$0].x - focusX) < abs(peakPoints[$1].x - focusX) }) {
            peakPoints[nearest].y = block.minY
        }
        var keys: [CGPoint] = [CGPoint(x: block.minX - block.width * 0.06,
                                       y: block.minY + block.height * random.range(0.45, 0.7))]
        var peakKeys: [Int] = []
        var valleyKeys: [Int] = []
        for (index, peak) in peakPoints.enumerated() {
            peakKeys.append(keys.count)
            keys.append(peak)
            if index + 1 < peakPoints.count {
                let next = peakPoints[index + 1]
                // Uneven slopes: the valley sits nearer one peak than the other.
                let x = peak.x + (next.x - peak.x) * random.range(0.32, 0.68)
                let deepest = max(peak.y, next.y)
                let y = deepest + (block.maxY - deepest) * random.range(0.35, 0.6)
                valleyKeys.append(keys.count)
                keys.append(CGPoint(x: x, y: y))
            }
        }
        keys.append(CGPoint(x: block.maxX + block.width * 0.06, y: block.minY + block.height * random.range(0.45, 0.7)))

        var points: [CGPoint] = []
        var peakIndices: [Int] = []
        var valleyIndices: [Int] = []
        for index in 0..<(keys.count - 1) {
            if peakKeys.contains(index) { peakIndices.append(points.count) }
            if valleyKeys.contains(index) { valleyIndices.append(points.count) }
            let run = displaced(from: keys[index], to: keys[index + 1], roughness: roughness, levels: 5, random: &random)
            points.append(contentsOf: run.dropLast())
        }
        if let last = keys.last { points.append(last) }
        return Ridge(points: points, peaks: peakIndices, valleys: valleyIndices)
    }

    /// Midpoint displacement between two points: a broken line that never
    /// rises above the higher end, so a peak stays the top of its slope.
    static func displaced(from a: CGPoint, to b: CGPoint, roughness: CGFloat, levels: Int,
                          random: inout IllustrationRandom) -> [CGPoint] {
        var line = [a, b]
        var amplitude = hypot(b.x - a.x, b.y - a.y) * roughness
        let ceiling = min(a.y, b.y) + 2
        let floor = max(a.y, b.y)
        for _ in 0..<levels {
            var next: [CGPoint] = []
            for index in 0..<(line.count - 1) {
                let p = line[index], q = line[index + 1]
                next.append(p)
                var y = (p.y + q.y) / 2 + random.signed() * amplitude
                y = min(max(y, ceiling), floor + amplitude * 0.5)
                next.append(CGPoint(x: (p.x + q.x) / 2 + random.signed() * (q.x - p.x) * 0.08, y: y))
            }
            if let last = line.last { next.append(last) }
            line = next
            amplitude *= 0.52
        }
        return line
    }

    /// A range's whole shape: the ridge closed down to `bottom`.
    static func silhouette(_ ridge: Ridge, bottom: CGFloat) -> [CGPoint] {
        guard let first = ridge.points.first, let last = ridge.points.last else { return [] }
        return ridge.points + [CGPoint(x: last.x, y: bottom), CGPoint(x: first.x, y: bottom)]
    }

    /// The side of a peak away from the light: its ridge from the peak down
    /// to the valley beyond, and a broken crease back up to the peak.
    /// `away` is +1 when the shadow side is to the right.
    static func shadowFace(_ ridge: Ridge, peak: Int, away: CGFloat, bottom: CGFloat,
                           random: inout IllustrationRandom) -> [CGPoint] {
        let points = ridge.points
        guard points.indices.contains(peak) else { return [] }
        let top = points[peak]
        // Along the ridge on the shadow side to the next valley (or the end).
        var edge: [CGPoint] = [top]
        if away > 0 {
            let stop = ridge.valleys.first { $0 > peak } ?? points.count - 1
            if stop > peak { edge.append(contentsOf: points[(peak + 1)...stop]) }
        } else {
            let stop = ridge.valleys.last { $0 < peak } ?? 0
            if stop < peak { edge.append(contentsOf: points[stop..<peak].reversed()) }
        }
        guard let end = edge.last else { return [] }
        let span = abs(end.x - top.x)
        let height = bottom - top.y
        // The crease runs down from the peak a little into the lit side, in
        // steps, so the face reads as rock.
        // The face narrows to a point below the valley, never a straight
        // drop: a vertical edge under a valley reads as a seam, not rock.
        let foot = min(bottom, max(end.y, top.y + height * 0.3) + height * 0.38)
        let base = CGPoint(x: top.x - away * span * 0.1, y: foot)
        var crease = displaced(from: top, to: base, roughness: 0, levels: 4, random: &random)
        for index in crease.indices.dropFirst().dropLast() {
            let t = CGFloat(index) / CGFloat(crease.count - 1)
            let wobble = random.signed() * height * 0.035 + away * sin(t * .pi * 3) * height * 0.025
            crease[index].x += wobble
            crease[index].y = max(crease[index].y, ridge.y(at: crease[index].x) + 3)
        }
        let gully = CGPoint(x: end.x - away * span * 0.35, y: foot + height * 0.04)
        return edge + [gully] + crease.reversed().dropLast()
    }

    /// Light catching the rock ribs on the lit side of a peak: narrow
    /// wedges running down from just under the ridge.
    static func highlights(_ ridge: Ridge, peak: Int, toward lit: CGFloat, bottom: CGFloat,
                           random: inout IllustrationRandom) -> [[CGPoint]] {
        guard ridge.points.indices.contains(peak) else { return [] }
        let top = ridge.points[peak]
        let height = bottom - top.y
        var wedges: [[CGPoint]] = []
        for index in 0..<2 {
            let along = height * (0.06 + CGFloat(index) * 0.11) * random.range(0.8, 1.2)
            let startX = top.x + lit * along * random.range(0.55, 0.9)
            let startY = ridge.y(at: startX) + 4
            let length = height * random.range(0.18, 0.34)
            let width = height * random.range(0.018, 0.03)
            let endX = startX + lit * length * random.range(0.05, 0.25)
            let endY = startY + length
            let wedge = [CGPoint(x: startX - width, y: startY), CGPoint(x: startX + width * 0.6, y: startY + width),
                         CGPoint(x: (startX + endX) / 2 + lit * width * 0.4, y: (startY + endY) / 2),
                         CGPoint(x: endX, y: endY)]
            wedges.append(wedge.map { CGPoint(x: $0.x, y: max($0.y, ridge.y(at: $0.x) + 3)) })
        }
        return wedges
    }

    /// Snow on a peak: the ridge's top `depth` either side of it, closed by a
    /// ragged lower edge that drips down the gullies.
    static func snowCap(_ ridge: Ridge, peak: Int, depth: CGFloat, random: inout IllustrationRandom) -> [CGPoint]? {
        let points = ridge.points
        guard points.indices.contains(peak) else { return nil }
        let top = points[peak]
        let limit = top.y + depth
        var left = peak, right = peak
        while left > 0, points[left - 1].y < limit { left -= 1 }
        while right < points.count - 1, points[right + 1].y < limit { right += 1 }
        guard right - left >= 2 else { return nil }
        let rim = Array(points[left...right])
        guard let first = rim.first, let last = rim.last else { return nil }
        var edge: [CGPoint] = []
        let teeth = 7
        for index in (1..<teeth).reversed() {
            let x = first.x + (last.x - first.x) * CGFloat(index) / CGFloat(teeth)
            let drop = index % 2 == 0 ? depth * random.range(0.55, 0.85) : depth * random.range(0.95, 1.35)
            let y = max(top.y + drop, ridge.y(at: x) + 4)
            edge.append(CGPoint(x: x, y: y))
        }
        return rim + edge
    }

    // MARK: Trees

    /// One pine: a trunk and drooping tiers, narrowest at the tip.
    static func pine(base: CGPoint, height: CGFloat, random: inout IllustrationRandom) -> [CGPoint] {
        let width = height * random.range(0.36, 0.44)
        let tiers = height > 60 ? 5 : 4
        let trunk = height * 0.1
        let crown = height - trunk
        var right: [CGPoint] = []
        var left: [CGPoint] = []
        for tier in 1...tiers {
            let t = CGFloat(tier) / CGFloat(tiers)
            let y = base.y - trunk - crown * (1 - t)
            let half = width / 2 * (0.3 + 0.7 * t)
            // Each side's branches differ a little, and droop at the tips.
            let r = half * random.range(0.86, 1.12), l = half * random.range(0.86, 1.12)
            right.append(CGPoint(x: base.x + r, y: y + height * random.range(0.006, 0.03)))
            left.append(CGPoint(x: base.x - l, y: y + height * random.range(0.006, 0.03)))
            if tier < tiers {
                right.append(CGPoint(x: base.x + half * random.range(0.36, 0.5), y: y - crown * 0.03))
                left.append(CGPoint(x: base.x - half * random.range(0.36, 0.5), y: y - crown * 0.03))
            }
        }
        let tip = CGPoint(x: base.x + random.signed() * width * 0.03, y: base.y - height)
        let trunkHalf = width * 0.06
        var outline = [tip] + right
        outline.append(CGPoint(x: base.x + trunkHalf, y: base.y - trunk))
        outline.append(CGPoint(x: base.x + trunkHalf, y: base.y))
        outline.append(CGPoint(x: base.x - trunkHalf, y: base.y))
        outline.append(CGPoint(x: base.x - trunkHalf, y: base.y - trunk))
        outline.append(contentsOf: left.reversed())
        return outline
    }

    /// One pine repeated along a line, varied in height, taller toward the
    /// edges so the row frames the picture; with the ground it stands on.
    static func treeline(from left: CGFloat, to right: CGFloat, baseline: (CGFloat) -> CGFloat, height: CGFloat,
                         bottom: CGFloat, spacing: CGFloat, edgeLift: CGFloat, groundDepth: CGFloat = .infinity,
                         random: inout IllustrationRandom) -> [IllustrationPath] {
        var trees: [IllustrationPath] = []
        var x = left + random.range(0, spacing)
        let middle = (left + right) / 2
        let half = max(1, (right - left) / 2)
        while x < right {
            let edge = pow(abs(x - middle) / half, 2)
            let h = height * random.range(0.7, 1.15) * (1 + edgeLift * edge)
            trees.append(IllustrationPath(pine(base: CGPoint(x: x, y: baseline(x) + h * 0.04), height: h, random: &random)))
            x += spacing * random.range(0.55, 1.05)
        }
        // The ground under them, following the baseline.
        var ground: [CGPoint] = []
        var gx = left
        while gx <= right {
            ground.append(CGPoint(x: gx, y: baseline(gx)))
            gx += (right - left) / 40
        }
        ground.append(CGPoint(x: right, y: baseline(right)))
        // A back row stands on a band that follows the land under it, so the
        // land shows below; a front row's ground runs to the bottom.
        if groundDepth.isFinite {
            ground += ground.reversed().map { CGPoint(x: $0.x, y: min(bottom, $0.y + groundDepth)) }
        } else {
            ground.append(CGPoint(x: right, y: bottom))
            ground.append(CGPoint(x: left, y: bottom))
        }
        // A row standing straight on the land in front of it needs no strip.
        return groundDepth <= 0 ? trees : [IllustrationPath(ground)] + trees
    }

    // MARK: Light

    /// Rays as an even burst of tapered wedges round `center`, from angle
    /// `from` to `to` (radians, 0 pointing right, counting clockwise on screen).
    static func rayBurst(center: CGPoint, inner: CGFloat, outer: CGFloat, count: Int, from: CGFloat, to: CGFloat,
                         width: CGFloat) -> [IllustrationPath] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let t = count == 1 ? 0.5 : CGFloat(index) / CGFloat(count - 1)
            let angle = from + (to - from) * t
            let reach = index % 2 == 0 ? outer : inner + (outer - inner) * 0.62
            let spread = width / inner / 2
            let tipSpread = spread * 0.25
            let a = CGPoint(x: center.x + inner * cos(angle - spread), y: center.y + inner * sin(angle - spread))
            let b = CGPoint(x: center.x + reach * cos(angle - tipSpread * inner / reach), y: center.y + reach * sin(angle - tipSpread * inner / reach))
            let c = CGPoint(x: center.x + reach * cos(angle + tipSpread * inner / reach), y: center.y + reach * sin(angle + tipSpread * inner / reach))
            let d = CGPoint(x: center.x + inner * cos(angle + spread), y: center.y + inner * sin(angle + spread))
            return IllustrationPath([a, b, c, d])
        }
    }

    /// Light on water: stacked horizontal strokes under `x`, shortening and
    /// thinning as they go down and away.
    static func glitter(under x: CGFloat, from top: CGFloat, to bottom: CGFloat, width: CGFloat, count: Int,
                        random: inout IllustrationRandom) -> [IllustrationPath] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let t = CGFloat(index) / CGFloat(max(1, count - 1))
            let y = top + (bottom - top) * pow(t, 1.25)
            let half = width / 2 * (1 - t * 0.55) * random.range(0.55, 1)
            let shift = random.signed() * width * 0.12
            return IllustrationPath([CGPoint(x: x + shift - half, y: y), CGPoint(x: x + shift + half, y: y)], closed: false)
        }
    }

    /// Ripple lines across water: short strokes scattered between `top` and `bottom`.
    static func ripples(in box: CGRect, count: Int, random: inout IllustrationRandom) -> [IllustrationPath] {
        (0..<count).map { _ in
            let y = box.minY + box.height * pow(random.unit(), 0.8)
            let length = box.width * random.range(0.04, 0.12) * (0.4 + (y - box.minY) / max(1, box.height))
            let x = box.minX + random.unit() * box.width
            return IllustrationPath([CGPoint(x: x, y: y), CGPoint(x: x + length, y: y)], closed: false)
        }
    }

    /// `points` mirrored in the waterline.
    static func reflected(_ points: [CGPoint], in waterline: CGFloat) -> [CGPoint] {
        points.map { CGPoint(x: $0.x, y: 2 * waterline - $0.y) }
    }

    // MARK: Land and sky

    /// Rolling hills: a smooth crest across `block`.
    static func hills(in block: CGRect, swells: Int, random: inout IllustrationRandom) -> [CGPoint] {
        var crest: [CGPoint] = []
        let steps = max(4, swells * 3)
        let phase = random.range(0, 2 * .pi)
        let second = random.range(0, 2 * .pi)
        for index in 0...steps {
            let t = CGFloat(index) / CGFloat(steps)
            let x = block.minX - block.width * 0.05 + (block.width * 1.1) * t
            let wave = sin(t * .pi * CGFloat(swells) + phase) * 0.5 + sin(t * .pi * CGFloat(swells) * 2.3 + second) * 0.18
            crest.append(CGPoint(x: x, y: block.minY + block.height * (0.35 + 0.32 * wave)))
        }
        return crest
    }

    /// A streak of cloud: a long thin lens, fuller on top, tapering to a
    /// point at each end.
    static func cloud(center: CGPoint, width: CGFloat, random: inout IllustrationRandom) -> [CGPoint] {
        let height = width * random.range(0.035, 0.05)
        let lean = random.range(-0.12, 0.12)
        return [CGPoint(x: center.x - width / 2, y: center.y + height * 0.2),
                CGPoint(x: center.x - width * (0.22 + lean), y: center.y - height * 0.55),
                CGPoint(x: center.x + width * (0.08 - lean), y: center.y - height),
                CGPoint(x: center.x + width / 2, y: center.y),
                CGPoint(x: center.x + width * 0.18, y: center.y + height * 0.38),
                CGPoint(x: center.x - width * 0.24, y: center.y + height * 0.42)]
    }

    /// Stars scattered over `box`, kept clear of `avoid`.
    static func stars(in box: CGRect, count: Int, avoid: CGRect, random: inout IllustrationRandom) -> [IllustrationPath] {
        var made: [IllustrationPath] = []
        var tries = 0
        while made.count < count, tries < count * 6 {
            tries += 1
            let p = CGPoint(x: box.minX + random.unit() * box.width, y: box.minY + pow(random.unit(), 1.4) * box.height)
            if avoid.contains(p) { continue }
            let r = random.range(1.2, 3.0)
            made.append(IllustrationPath([CGPoint(x: p.x + r, y: p.y), CGPoint(x: p.x, y: p.y + r),
                                          CGPoint(x: p.x - r, y: p.y), CGPoint(x: p.x, y: p.y - r)], smooth: true))
        }
        return made
    }

    /// A few birds in flight near `focus`: each a soft M.
    static func birds(near focus: CGPoint, size: CGFloat, count: Int, random: inout IllustrationRandom) -> [IllustrationPath] {
        (0..<count).map { index in
            let s = size * random.range(0.7, 1.2) * (index == 0 ? 1.2 : 1)
            let c = CGPoint(x: focus.x + CGFloat(index) * size * 1.6 + random.signed() * size * 0.6,
                            y: focus.y + random.signed() * size * 1.1 - CGFloat(index) * size * 0.35)
            return IllustrationPath([CGPoint(x: c.x - s, y: c.y - s * 0.15), CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.42),
                                     CGPoint(x: c.x, y: c.y), CGPoint(x: c.x + s * 0.5, y: c.y - s * 0.42),
                                     CGPoint(x: c.x + s, y: c.y - s * 0.15)], closed: false, smooth: true, corners: [2])
        }
    }

    // MARK: Buildings

    struct Skyline {
        var bodies: [IllustrationPath]
        /// The strip of each building's side the light falls on.
        var lit: [IllustrationPath]
        /// The strip of each building's side turned away from the light.
        var shade: [IllustrationPath]
        var antennas: [IllustrationPath]
        var windows: [CGRect]
        var spires: [IllustrationPath]
    }

    /// A row of buildings standing on `ground`, tallest near `focusX`.
    static func skyline(from left: CGFloat, to right: CGFloat, ground: CGFloat, tallest: CGFloat, shortest: CGFloat,
                        focusX: CGFloat, lightSide: CGFloat, windows: Bool, random: inout IllustrationRandom) -> Skyline {
        var row = Skyline(bodies: [], lit: [], shade: [], antennas: [], windows: [], spires: [])
        var x = left
        let span = right - left
        while x < right {
            let width = span * random.range(0.035, 0.075)
            let near = 1 - min(1, abs(x + width / 2 - focusX) / (span * 0.45))
            let height = shortest + (tallest - shortest) * (0.25 + 0.75 * near * near) * random.range(0.65, 1.05)
            let top = ground - height
            var outline = [CGPoint(x: x, y: ground), CGPoint(x: x, y: top)]
            var shoulder: CGFloat = 0
            // A setback on some: the top steps in.
            if random.unit() < 0.35, height > tallest * 0.45 {
                let inset = width * 0.18
                let step = height * 0.12
                outline = [CGPoint(x: x, y: ground), CGPoint(x: x, y: top + step), CGPoint(x: x + inset, y: top + step),
                           CGPoint(x: x + inset, y: top), CGPoint(x: x + width - inset, y: top),
                           CGPoint(x: x + width - inset, y: top + step), CGPoint(x: x + width, y: top + step),
                           CGPoint(x: x + width, y: ground)]
                shoulder = step
            } else {
                outline += [CGPoint(x: x + width, y: top), CGPoint(x: x + width, y: ground)]
            }
            row.bodies.append(IllustrationPath(outline))
            if random.unit() < 0.22, height > tallest * 0.6 {
                let mid = x + width / 2
                let spire = height * random.range(0.12, 0.22)
                row.spires.append(IllustrationPath([CGPoint(x: mid - width * 0.08, y: top), CGPoint(x: mid, y: top - spire),
                                                    CGPoint(x: mid + width * 0.08, y: top)]))
            }
            let face = width * 0.16
            let faceX = lightSide > 0 ? x + width - face : x
            row.lit.append(IllustrationPath([CGPoint(x: faceX, y: top + shoulder), CGPoint(x: faceX + face, y: top + shoulder),
                                             CGPoint(x: faceX + face, y: ground), CGPoint(x: faceX, y: ground)]))
            let shadeX = lightSide > 0 ? x : x + width - face
            row.shade.append(IllustrationPath([CGPoint(x: shadeX, y: top + shoulder), CGPoint(x: shadeX + face, y: top + shoulder),
                                               CGPoint(x: shadeX + face, y: ground), CGPoint(x: shadeX, y: ground)]))
            if random.unit() < 0.3, height > tallest * 0.7, shoulder == 0 {
                let ax = x + width * random.range(0.3, 0.7)
                row.antennas.append(IllustrationPath([CGPoint(x: ax, y: top), CGPoint(x: ax, y: top - height * 0.12)], closed: false))
            }
            if windows {
                let columns = max(2, Int(width / 14))
                let gapX = width / CGFloat(columns)
                var y = top + shoulder + 12
                while y < ground - 14 {
                    // Whole floors lit together read as people at home, not noise.
                    let floorLit = random.unit() < 0.45
                    for column in 0..<columns where random.unit() < (floorLit ? 0.8 : 0.12) {
                        row.windows.append(CGRect(x: x + gapX * CGFloat(column) + gapX * 0.28, y: y,
                                                  width: gapX * 0.44, height: 6))
                    }
                    y += 15
                }
            }
            x += width + span * random.range(0, 0.008)
        }
        return row
    }

    // MARK: A lighthouse

    struct Part {
        var name: String
        var geometry: IllustrationGeometry
        var role: Role
        enum Role { case wall, stripe, dark, lamp, glass, roof, white, body, shade, ink }
    }

    /// A striped lighthouse standing at `base` (the middle of its foot),
    /// `height` tall, with its gallery, lamp room and cap.
    static func lighthouse(base: CGPoint, height: CGFloat) -> [Part] {
        let bottomHalf = height * 0.13
        let topHalf = height * 0.085
        let towerTop = base.y - height * 0.74
        func halfWidth(_ y: CGFloat) -> CGFloat {
            let t = (base.y - y) / (base.y - towerTop)
            return bottomHalf + (topHalf - bottomHalf) * t
        }
        var parts: [Part] = []
        let bands = 4
        for band in 0..<bands {
            let y0 = base.y - (base.y - towerTop) * CGFloat(band) / CGFloat(bands)
            let y1 = base.y - (base.y - towerTop) * CGFloat(band + 1) / CGFloat(bands)
            let quad = [CGPoint(x: base.x - halfWidth(y0), y: y0), CGPoint(x: base.x - halfWidth(y1), y: y1),
                        CGPoint(x: base.x + halfWidth(y1), y: y1), CGPoint(x: base.x + halfWidth(y0), y: y0)]
            parts.append(Part(name: band % 2 == 0 ? "Tower white \(band / 2 + 1)" : "Tower red \(band / 2 + 1)",
                              geometry: .path([IllustrationPath(quad)]), role: band % 2 == 0 ? .wall : .stripe))
        }
        let door = CGRect(x: base.x - bottomHalf * 0.22, y: base.y - height * 0.09, width: bottomHalf * 0.44, height: height * 0.09)
        parts.append(Part(name: "Door", geometry: .rect(door, radius: bottomHalf * 0.22), role: .dark))
        let gallery = CGRect(x: base.x - topHalf * 1.45, y: towerTop - height * 0.035, width: topHalf * 2.9, height: height * 0.035)
        parts.append(Part(name: "Gallery", geometry: .rect(gallery, radius: 2), role: .dark))
        let room = CGRect(x: base.x - topHalf * 0.8, y: gallery.minY - height * 0.1, width: topHalf * 1.6, height: height * 0.1)
        parts.append(Part(name: "Lamp room", geometry: .rect(room, radius: 0), role: .lamp))
        let mullion = CGRect(x: base.x - topHalf * 0.07, y: room.minY, width: topHalf * 0.14, height: room.height)
        parts.append(Part(name: "Lamp room frame", geometry: .rect(mullion, radius: 0), role: .dark))
        let capBase = room.minY
        let cap = [CGPoint(x: base.x - topHalf * 1.05, y: capBase), CGPoint(x: base.x - topHalf * 0.75, y: capBase - height * 0.05),
                   CGPoint(x: base.x, y: capBase - height * 0.085), CGPoint(x: base.x + topHalf * 0.75, y: capBase - height * 0.05),
                   CGPoint(x: base.x + topHalf * 1.05, y: capBase)]
        parts.append(Part(name: "Cap", geometry: .path([IllustrationPath(cap, smooth: true, corners: [0, 4])]), role: .roof))
        return parts
    }

    /// The cottage beside the lighthouse.
    static func cottage(base: CGPoint, width: CGFloat) -> [Part] {
        let wallHeight = width * 0.5
        let wall = CGRect(x: base.x - width / 2, y: base.y - wallHeight, width: width, height: wallHeight)
        let roof = [CGPoint(x: wall.minX - width * 0.08, y: wall.minY), CGPoint(x: base.x - width * 0.18, y: wall.minY - width * 0.34),
                    CGPoint(x: base.x + width * 0.18, y: wall.minY - width * 0.34), CGPoint(x: wall.maxX + width * 0.08, y: wall.minY)]
        let window = CGRect(x: base.x - width * 0.3, y: wall.minY + wallHeight * 0.3, width: width * 0.16, height: width * 0.16)
        let door = CGRect(x: base.x + width * 0.12, y: base.y - wallHeight * 0.62, width: width * 0.16, height: wallHeight * 0.62)
        return [Part(name: "Cottage wall", geometry: .rect(wall, radius: 0), role: .wall),
                Part(name: "Cottage roof", geometry: .path([IllustrationPath(roof)]), role: .roof),
                Part(name: "Cottage window", geometry: .rect(window, radius: 1), role: .lamp),
                Part(name: "Cottage door", geometry: .rect(door, radius: 1), role: .dark)]
    }

    // MARK: A fox

    /// A fox sitting, facing left, its feet at `base`, `height` tall, its
    /// tail wrapped round its feet.
    static func fox(base: CGPoint, height: CGFloat, facingRight: Bool = false) -> [Part] {
        let s = height / 120
        // Drawn facing left; mirrored to face the light when it is on the right.
        let flip: CGFloat = facingRight ? -1 : 1
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: base.x + flip * (x - 50) * s, y: base.y + (y - 118) * s) }
        // The brush lies on the ground behind, sweeping out and back, its
        // white tip at the far end.
        let tail = IllustrationPath([p(68, 86), p(84, 90), p(100, 98), p(114, 104), p(126, 108), p(130, 114),
                                     p(120, 119), p(100, 119), p(80, 116), p(66, 108)],
                                    smooth: true, corners: [5])
        let tailTip = IllustrationPath([p(114, 104), p(126, 108), p(130, 114), p(124, 118.6), p(112, 117)], smooth: true, corners: [2])
        let body = IllustrationPath([p(38, 44), p(28, 58), p(25, 80), p(28, 104), p(48, 111), p(70, 107),
                                     p(80, 92), p(78, 70), p(66, 50), p(52, 40)], smooth: true)
        let backLeg = IllustrationPath([p(52, 92), p(64, 88), p(70, 100), p(62, 110), p(48, 110)], smooth: true)
        // Slender front legs, wider at the shoulder, a dark stocking below.
        let legs = [IllustrationPath([p(28, 74), p(36, 76), p(35.5, 92), p(34.5, 108), p(30, 108), p(29.5, 92)], smooth: true, corners: [3, 4]),
                    IllustrationPath([p(37, 76), p(45, 78), p(44, 94), p(43.5, 109), p(39, 109), p(38.5, 94)], smooth: true, corners: [3, 4])]
        let socks = [IllustrationPath([p(29.8, 99), p(35.2, 99), p(34.6, 108), p(30, 108)], smooth: true, corners: [2, 3]),
                     IllustrationPath([p(38.8, 100), p(43.8, 100), p(43.6, 109), p(39, 109)], smooth: true, corners: [2, 3])]
        let paws = [IllustrationPath([p(27, 106), p(36, 106), p(37, 111), p(26, 111)], smooth: true),
                    IllustrationPath([p(36, 107), p(45, 107), p(46, 112), p(35, 112)], smooth: true)]
        let bib = IllustrationPath([p(22, 40), p(36, 46), p(40, 58), p(34, 72), p(28, 64), p(24, 50)], smooth: true, corners: [3])
        let head = IllustrationPath([p(6, 36), p(14, 42), p(26, 46), p(40, 46), p(50, 38), p(52, 26), p(48, 18),
                                     p(46, 3), p(38, 13), p(30, 12), p(22, 1), p(18, 16), p(14, 25), p(9, 31)],
                                    smooth: true, corners: [0, 7, 10])
        let muzzle = IllustrationPath([p(6, 36), p(14, 42), p(26, 46), p(34, 44), p(26, 38), p(16, 36)], smooth: true, corners: [0, 4])
        let ears = [IllustrationPath([p(44, 7), p(47.5, 17), p(40, 14)]), IllustrationPath([p(23, 5), p(26, 13), p(19.5, 15)])]
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            let a = p(x, y), b = p(x + w, y + h)
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        }
        let eye = box(21, 24.5, 5.5, 3.6)
        let glint = box(22.2, 25, 1.6, 1.4)
        let nose = box(3.5, 33.5, 5, 4.5)
        return [
            Part(name: "Tail", geometry: .path([tail]), role: .body),
            Part(name: "Back leg", geometry: .path([backLeg]), role: .body),
            Part(name: "Body", geometry: .path([body]), role: .body),
            Part(name: "Front legs", geometry: .path(legs), role: .body),
            Part(name: "Socks", geometry: .path(socks), role: .ink),
            Part(name: "Paws", geometry: .path(paws), role: .ink),
            Part(name: "Chest", geometry: .path([bib]), role: .white),
            Part(name: "Tail tip", geometry: .path([tailTip]), role: .white),
            Part(name: "Head", geometry: .path([head]), role: .body),
            Part(name: "Muzzle", geometry: .path([muzzle]), role: .white),
            Part(name: "Ears", geometry: .path(ears), role: .ink),
            Part(name: "Eye", geometry: .ellipse(eye), role: .ink),
            Part(name: "Eye light", geometry: .ellipse(glint), role: .white),
            Part(name: "Nose", geometry: .ellipse(nose), role: .ink),
        ]
    }
}
