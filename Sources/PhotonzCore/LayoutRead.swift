import CoreGraphics
import Foundation

/// One thing a designer would point at in a UI screenshot: a card, a control,
/// a line of words, an icon, a divider. Read off the pixels by `LayoutRead`,
/// in the picture's own pixels, top-left origin.
public struct LayoutNode: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// A shape with one flat fill or a ring of border round flat space: a
        /// card, a button, a field, a switch, an avatar disc. What sits inside
        /// it is read as its children.
        case box
        /// A shape with no one fill (a photo, a gradient): nothing inside it
        /// is read.
        case picture
        /// A line of words: several marks side by side on one line.
        case text
        /// Ink that is not a line of words: an icon, a single glyph.
        case mark
        /// A divider: a hairline much longer than it is thick.
        case rule
    }

    public var rect: CGRect
    public var kind: Kind
    /// The node this one sits inside, as an index into the same list. Nil for
    /// what sits on the picture's own background.
    public var parent: Int?
    /// A box's border in pixels, top, left, bottom, right. Zero for a box with
    /// none and for every other kind.
    public var border: [CGFloat]
    /// A box's fill, packed as `LumaField` reads it (luma, red-green,
    /// yellow-blue, a byte each). Nil for every other kind.
    public var fill: UInt32?
    /// A line of words: the top of its lowercase letters and its baseline,
    /// so lines are compared by where the eye reads them, not by the
    /// ascenders and descenders that happen to be in them.
    public var textTop: CGFloat?
    public var baseline: CGFloat?

    public init(rect: CGRect, kind: Kind, parent: Int? = nil, border: [CGFloat] = [0, 0, 0, 0],
                textTop: CGFloat? = nil, baseline: CGFloat? = nil, fill: UInt32? = nil) {
        self.rect = rect
        self.kind = kind
        self.parent = parent
        self.border = border
        self.textTop = textTop
        self.baseline = baseline
        self.fill = fill
    }

    /// The border most of the box's sides have, in pixels.
    public var borderWidth: CGFloat {
        let counts = Dictionary(grouping: border, by: { $0 }).mapValues(\.count)
        return counts.max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key ?? 0
    }

    /// Where a line of words sits for the eye: halfway between the top of its
    /// small letters and its baseline. A box's middle for anything else.
    public var opticalMidY: CGFloat {
        if let textTop, let baseline { return (textTop + baseline) / 2 }
        return rect.midY
    }
}

/// Reads a UI screenshot into the things on it, nested as they are drawn:
/// the page's background, the cards and controls on it, what is inside each
/// of those, the lines of words and the icons. Pure pixel reading, exact to
/// the pixel, so two things one point apart on a Retina capture read two
/// pixels apart.
///
/// How: the background of a region is its most common colour. Everything
/// that differs from it is ink, and ink that touches is one piece. A piece
/// that is mostly one flat colour (a card, a button) or a ring round flat
/// space (a bordered card on the page colour) is a box, and the space inside
/// it is read again against its own fill. Other ink is joined into lines of
/// words by how close the letters sit, and what stays alone is a mark.
public enum LayoutRead {

    /// How different (largest of the three channel differences, 0...255) a
    /// pixel must be from the background to count as ink.
    public static let inkThreshold = 6

    /// The things on `luma` (inside `region`, the whole picture when nil),
    /// parents before their children.
    public static func read(_ luma: LumaField, pixelScale: CGFloat, region: CGRect? = nil) -> [LayoutNode] {
        guard !luma.isEmpty else { return [] }
        let full = CGRect(x: 0, y: 0, width: luma.width, height: luma.height)
        let area = (region ?? full).integral.intersection(full)
        guard !area.isNull, area.width >= 4, area.height >= 4 else { return [] }
        let reader = Reader(luma: luma, scale: max(1, pixelScale))
        let box = IntBox(x: Int(area.minX), y: Int(area.minY), w: Int(area.width), h: Int(area.height))
        let allowed = [Bool](repeating: true, count: box.w * box.h)
        // The page's own colour is the one round its rim: a page of white
        // cards can have more white in it than page.
        var rim = [Bool](repeating: false, count: box.w * box.h)
        let band = max(1, Int(2 * max(1, pixelScale)))
        for y in 0..<box.h {
            for x in 0..<box.w where x < band || y < band || x >= box.w - band || y >= box.h - band {
                rim[y * box.w + x] = true
            }
        }
        let background = reader.commonColour(in: box, allowed: rim)
        var nodes: [LayoutNode] = []
        reader.scan(box, allowed: allowed, background: background, parent: nil, depth: 0, into: &nodes)
        return nodes
    }

    struct IntBox: Equatable {
        var x, y, w, h: Int
        var maxX: Int { x + w }
        var maxY: Int { y + h }
        var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    }

    struct Piece {
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        var count = 0
        var w: Int { maxX - minX + 1 }
        var h: Int { maxY - minY + 1 }
        mutating func add(_ x: Int, _ y: Int) {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
            count += 1
        }
    }

    struct Reader {
        let luma: LumaField
        let scale: CGFloat
        let width: Int
        let hasColour: Bool

        init(luma: LumaField, scale: CGFloat) {
            self.luma = luma
            self.scale = scale
            self.width = luma.width
            self.hasColour = luma.hasColour
        }

        func colour(_ i: Int) -> UInt32 {
            let l = UInt32(luma.samples[i])
            guard hasColour else { return l << 16 | 128 << 8 | 128 }
            return l << 16 | UInt32(luma.redGreen[i]) << 8 | UInt32(luma.yellowBlue[i])
        }

        static func distance(_ a: UInt32, _ b: UInt32) -> Int {
            let dl = abs(Int((a >> 16) & 0xFF) - Int((b >> 16) & 0xFF))
            let dr = abs(Int((a >> 8) & 0xFF) - Int((b >> 8) & 0xFF))
            let dy = abs(Int(a & 0xFF) - Int(b & 0xFF))
            return max(dl, max(dr, dy))
        }

        /// The most common exact colour among the allowed pixels of `box`.
        func commonColour(in box: IntBox, allowed: [Bool]) -> UInt32 {
            var counts: [UInt32: Int] = [:]
            let step = box.w * box.h > 400_000 ? 2 : 1
            var y = 0
            while y < box.h {
                var x = 0
                while x < box.w {
                    if allowed[y * box.w + x] { counts[colour((box.y + y) * width + box.x + x), default: 0] += 1 }
                    x += step
                }
                y += step
            }
            return counts.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? 0
        }

        // MARK: Pieces

        /// Labels every connected run of ink (8-connected) in `box`.
        func pieces(in box: IntBox, ink: [Bool]) -> (labels: [Int32], pieces: [Piece]) {
            let n = box.w * box.h
            var labels = [Int32](repeating: -1, count: n)
            var parent: [Int32] = []
            func find(_ a: Int32) -> Int32 {
                var a = a
                while parent[Int(a)] != a {
                    parent[Int(a)] = parent[Int(parent[Int(a)])]
                    a = parent[Int(a)]
                }
                return a
            }
            func union(_ a: Int32, _ b: Int32) {
                let ra = find(a), rb = find(b)
                if ra != rb { parent[Int(max(ra, rb))] = min(ra, rb) }
            }
            for y in 0..<box.h {
                for x in 0..<box.w {
                    let i = y * box.w + x
                    guard ink[i] else { continue }
                    var mine: Int32 = -1
                    let neighbours = [(x - 1, y), (x - 1, y - 1), (x, y - 1), (x + 1, y - 1)]
                    for (nx, ny) in neighbours where nx >= 0 && ny >= 0 && nx < box.w {
                        let l = labels[ny * box.w + nx]
                        guard l >= 0 else { continue }
                        if mine < 0 { mine = l } else if mine != l { union(mine, l) }
                    }
                    if mine < 0 {
                        mine = Int32(parent.count)
                        parent.append(mine)
                    }
                    labels[i] = mine
                }
            }
            var remap = [Int32](repeating: -1, count: parent.count)
            var found: [Piece] = []
            for i in 0..<n where labels[i] >= 0 {
                let root = find(labels[i])
                if remap[Int(root)] < 0 {
                    remap[Int(root)] = Int32(found.count)
                    found.append(Piece())
                }
                let id = remap[Int(root)]
                labels[i] = id
                found[Int(id)].add(i % box.w, i / box.w)
            }
            return (labels, found)
        }

        // MARK: Reading a region

        func scan(_ box: IntBox, allowed: [Bool], background: UInt32, parent: Int?, depth: Int,
                  into nodes: inout [LayoutNode]) {
            var ink = [Bool](repeating: false, count: box.w * box.h)
            for y in 0..<box.h {
                let row = (box.y + y) * width + box.x
                for x in 0..<box.w where allowed[y * box.w + x] {
                    ink[y * box.w + x] = Self.distance(colour(row + x), background) > LayoutRead.inkThreshold
                }
            }
            let (labels, pieces) = self.pieces(in: box, ink: ink)
            var loose: [Int] = []
            var boxes: [(Int, Shape)] = []
            for (id, piece) in pieces.enumerated() where piece.count >= 2 {
                if let shape = depth < 6 ? self.shape(of: piece, id: Int32(id), in: box, labels: labels) : nil {
                    boxes.append((id, shape))
                } else {
                    loose.append(id)
                }
            }
            // Ink inside a ring (a bordered card on the page's own colour) is
            // not joined to it, so it is set aside here and read as the
            // ring's own content.
            let rings = boxes.map { pieces[$0.0] }
            func inRing(_ p: Piece) -> Bool {
                rings.contains { r in p.minX > r.minX && p.maxX < r.maxX && p.minY > r.minY && p.maxY < r.maxY }
            }
            loose.removeAll { inRing(pieces[$0]) }
            boxes.removeAll { inRing(pieces[$0.0]) }
            // Rules and loose ink first, in reading order, then the boxes with
            // what is inside them.
            var rules: [Int] = []
            var marks: [Int] = []
            for id in loose {
                let p = pieces[id]
                let thin = CGFloat(min(p.w, p.h)), long = CGFloat(max(p.w, p.h))
                if thin <= 2.5 * scale, long >= 12 * thin, Double(p.count) >= 0.8 * Double(p.w * p.h) {
                    rules.append(id)
                } else {
                    marks.append(id)
                }
            }
            for id in rules {
                let p = pieces[id]
                nodes.append(LayoutNode(rect: CGRect(x: box.x + p.minX, y: box.y + p.minY, width: p.w, height: p.h),
                                        kind: .rule, parent: parent))
            }
            for line in icons(lines(marks, pieces: pieces), pieces: pieces) {
                var r = Piece()
                for id in line { let p = pieces[id]; r.add(p.minX, p.minY); r.add(p.maxX, p.maxY) }
                // A speck on its own is a rounded corner's antialiasing or
                // noise, never something a designer points at.
                guard CGFloat(max(r.w, r.h)) >= 2 * scale else { continue }
                let rect = CGRect(x: box.x + r.minX, y: box.y + r.minY, width: r.w, height: r.h)
                let wordy = line.count >= 2 && CGFloat(r.w) >= 1.2 * CGFloat(r.h)
                var node = LayoutNode(rect: rect, kind: wordy ? .text : .mark, parent: parent)
                if wordy {
                    let (top, base) = textLines(line: Set(line.map { Int32($0) }), piece: r, box: box, labels: labels)
                    node.textTop = CGFloat(box.y + top)
                    node.baseline = CGFloat(box.y + base)
                }
                nodes.append(node)
            }
            for (id, shape) in boxes {
                let p = pieces[id]
                let rect = CGRect(x: box.x + p.minX, y: box.y + p.minY, width: p.w, height: p.h)
                let index = nodes.count
                nodes.append(LayoutNode(rect: rect, kind: shape.isPicture ? .picture : .box, parent: parent,
                                        border: shape.border.map { CGFloat($0) }, fill: shape.fill))
                guard !shape.isPicture else { continue }
                let inner = IntBox(x: box.x + p.minX, y: box.y + p.minY, w: p.w, h: p.h)
                scan(inner, allowed: shape.inside, background: shape.fill, parent: index, depth: depth + 1, into: &nodes)
            }
        }

        // MARK: Boxes

        struct Shape {
            var fill: UInt32
            var isPicture: Bool
            var border: [Int]
            /// Inside the shape and clear of its border, piece-local.
            var inside: [Bool]
        }

        /// A box when the piece is a filled shape or a ring round flat space;
        /// nil for ink that is neither.
        func shape(of p: Piece, id: Int32, in box: IntBox, labels: [Int32]) -> Shape? {
            let smallest = Int((10 * scale).rounded())
            guard p.w >= smallest, p.h >= smallest else { return nil }
            let w = p.w, h = p.h
            // Outside the shape: everything in its bounds reachable from the
            // bounds' rim without crossing the piece.
            var outside = [Bool](repeating: false, count: w * h)
            var stack: [Int] = []
            func member(_ x: Int, _ y: Int) -> Bool { labels[(p.minY + y) * box.w + p.minX + x] == id }
            func seed(_ x: Int, _ y: Int) {
                let i = y * w + x
                if !outside[i] && !member(x, y) { outside[i] = true; stack.append(i) }
            }
            for x in 0..<w { seed(x, 0); seed(x, h - 1) }
            for y in 0..<h { seed(0, y); seed(w - 1, y) }
            while let i = stack.popLast() {
                let x = i % w, y = i / w
                if x > 0 { seed(x - 1, y) }
                if x < w - 1 { seed(x + 1, y) }
                if y > 0 { seed(x, y - 1) }
                if y < h - 1 { seed(x, y + 1) }
            }
            var insideCount = 0
            var counts: [UInt32: Int] = [:]
            var memberColours: [UInt32: Int] = [:]
            for y in 0..<h {
                for x in 0..<w where !outside[y * w + x] {
                    insideCount += 1
                    let c = colour((box.y + p.minY + y) * width + box.x + p.minX + x)
                    counts[c, default: 0] += 1
                    if member(x, y) { memberColours[c, default: 0] += 1 }
                }
            }
            let solidity = Double(insideCount) / Double(w * h)
            guard solidity >= 0.7 else { return nil }
            let ring = Double(p.count) < 0.6 * Double(insideCount)
            if ring {
                // A ring is a box only when it is thin and round flat space:
                // a letter O is a ring too, but small and thick.
                guard p.w >= Int(20 * scale), p.h >= Int(20 * scale) else { return nil }
            }
            guard let (mode, _) = counts.max(by: { ($0.value, $0.key) < ($1.value, $1.key) }) else { return nil }
            // A flat fill is one exact colour over much of the shape; a photo
            // or a gradient has no colour that holds more than a sliver.
            let exact = counts[mode] ?? 0
            if Double(exact) < 0.15 * Double(insideCount) {
                // No one fill: a photo or a gradient, unless it is only ink.
                guard !ring, p.w >= Int(10 * scale), p.h >= Int(10 * scale) else { return nil }
                return Shape(fill: mode, isPicture: true, border: [0, 0, 0, 0], inside: [])
            }
            let fill = mode
            // A fill is flat space, not strokes: most of it has the same
            // colour two points away on every side. The bowl of a big bold
            // letter is mostly one colour too, but nowhere that deep.
            let reachFlat = max(1, Int((2 * scale).rounded()))
            func flatAt(_ x: Int, _ y: Int) -> Bool {
                guard x >= 0, y >= 0, x < w, y < h, !outside[y * w + x] else { return false }
                return Self.distance(colour((box.y + p.minY + y) * width + box.x + p.minX + x), fill)
                    <= LayoutRead.inkThreshold
            }
            var deep = 0
            var probes = 0
            let stride = max(1, min(w, h) / 40)
            for y in Swift.stride(from: 0, to: h, by: stride) {
                for x in Swift.stride(from: 0, to: w, by: stride) where !outside[y * w + x] {
                    probes += 1
                    if flatAt(x, y), flatAt(x - reachFlat, y), flatAt(x + reachFlat, y),
                       flatAt(x, y - reachFlat), flatAt(x, y + reachFlat) { deep += 1 }
                }
            }
            guard probes > 0, Double(deep) >= 0.12 * Double(probes) else { return nil }
            // The border, side by side: from the shape's edge inward, the run
            // that is not the fill, read at a quarter, half and three quarters
            // along the side and the middle one of the three kept.
            func run(_ xs: (Int) -> (Int, Int), along length: Int, depth: Int) -> Int {
                var reads: [Int] = []
                for f in [0.25, 0.5, 0.75] {
                    let t = Int(Double(length) * f)
                    var started = false, n = 0
                    for d in 0..<depth {
                        let (x, y) = xs(t * 100_000 + d)
                        guard x >= 0, y >= 0, x < w, y < h else { break }
                        if outside[y * w + x] { if started { break } else { continue } }
                        started = true
                        let c = colour((box.y + p.minY + y) * width + box.x + p.minX + x)
                        if Self.distance(c, fill) <= LayoutRead.inkThreshold { break }
                        n += 1
                    }
                    reads.append(n)
                }
                return reads.sorted()[1]
            }
            let reach = Int(12 * scale)
            let top = run({ ($0 / 100_000, $0 % 100_000) }, along: w, depth: min(reach, h / 2))
            let left = run({ ($0 % 100_000, $0 / 100_000) }, along: h, depth: min(reach, w / 2))
            let bottom = run({ ($0 / 100_000, h - 1 - $0 % 100_000) }, along: w, depth: min(reach, h / 2))
            let right = run({ (w - 1 - $0 % 100_000, $0 / 100_000) }, along: h, depth: min(reach, w / 2))
            // What is inside, kept clear of the border and the shape's own
            // antialiased rim, so neither reads as a child.
            let clear = max(max(top, bottom), max(left, right)) + 1
            var inside = [Bool](repeating: false, count: w * h)
            for y in 0..<h {
                for x in 0..<w where !outside[y * w + x] {
                    var near = false
                    var d = 1
                    while d <= clear && !near {
                        if x - d < 0 || x + d >= w || y - d < 0 || y + d >= h
                            || outside[y * w + x - d] || outside[y * w + x + d]
                            || outside[(y - d) * w + x] || outside[(y + d) * w + x] { near = true }
                        d += 1
                    }
                    inside[y * w + x] = !near
                }
            }
            return Shape(fill: fill, isPicture: false, border: [top, left, bottom, right], inside: inside)
        }

        // MARK: Lines of words

        /// Joins loose ink into lines: a dot over its letter, letters beside
        /// letters on one line, words a space apart.
        func lines(_ ids: [Int], pieces: [Piece]) -> [[Int]] {
            guard !ids.isEmpty else { return [] }
            var group = Array(0..<ids.count)
            func find(_ a: Int) -> Int {
                var a = a
                while group[a] != a { group[a] = group[group[a]]; a = group[a] }
                return a
            }
            let bounds = ids.map { pieces[$0] }
            // A dot or an accent over (or under) a bigger piece it overlaps.
            for i in 0..<ids.count {
                for j in 0..<ids.count where i != j {
                    let s = bounds[i], b = bounds[j]
                    guard max(s.w, s.h) * 100 <= 45 * b.h,
                          s.minX <= b.maxX, b.minX <= s.maxX else { continue }
                    let gap = max(s.minY - b.maxY, b.minY - s.maxY)
                    if gap >= 0, gap * 100 <= 45 * b.h { group[find(i)] = find(j) }
                }
            }
            // Then pieces side by side on one line, until nothing more joins.
            var changed = true
            while changed {
                changed = false
                var merged: [Int: Piece] = [:]
                for i in 0..<ids.count {
                    let r = find(i)
                    var m = merged[r] ?? Piece()
                    m.add(bounds[i].minX, bounds[i].minY); m.add(bounds[i].maxX, bounds[i].maxY)
                    merged[r] = m
                }
                let roots = merged.sorted { $0.value.minX < $1.value.minX }
                for n in roots.indices {
                    for m in roots.indices where m > n {
                        let (a, pa) = roots[n], (b, pb) = roots[m]
                        guard find(a) != find(b) else { continue }
                        let overlap = min(pa.maxY, pb.maxY) - max(pa.minY, pb.minY) + 1
                        guard overlap * 2 >= min(pa.h, pb.h) else { continue }
                        let gap = max(pb.minX - pa.maxX, pa.minX - pb.maxX) - 1
                        guard gap * 100 <= 55 * max(pa.h, pb.h) else { continue }
                        // Lines of very different heights are a label and
                        // something else, not one line.
                        // Punctuation is small beside its line and joins it.
                        let small = pa.h < pb.h ? pa : pb, big = pa.h < pb.h ? pb : pa
                        guard big.h * 10 <= 25 * small.h
                                || max(small.w, small.h) * 10 <= 4 * big.h else { continue }
                        group[find(b)] = find(a)
                        changed = true
                    }
                }
            }
            var out: [Int: [Int]] = [:]
            for i in 0..<ids.count { out[find(i), default: []].append(ids[i]) }
            return out.values.sorted { a, b in
                let pa = pieces[a[0]], pb = pieces[b[0]]
                return (pa.minY, pa.minX) < (pb.minY, pb.minX)
            }
        }

        /// Joins the pieces of one icon (the dashes of a dashed square, the
        /// bars of a chart glyph): lines of one piece within 3.5 points of
        /// each other on both axes. A line of words is left as it is.
        func icons(_ lines: [[Int]], pieces: [Piece]) -> [[Int]] {
            var out = lines
            func bounds(_ line: [Int]) -> Piece {
                var r = Piece()
                for id in line { r.add(pieces[id].minX, pieces[id].minY); r.add(pieces[id].maxX, pieces[id].maxY) }
                return r
            }
            func wordy(_ line: [Int]) -> Bool {
                let r = bounds(line)
                return line.count >= 2 && CGFloat(r.w) >= 1.2 * CGFloat(r.h)
            }
            // Icon sized: no wider or taller than a large icon.
            func small(_ line: [Int]) -> Bool {
                let r = bounds(line)
                return CGFloat(max(r.w, r.h)) <= 16 * scale
            }
            let reach = Int((3.5 * scale).rounded())
            var changed = true
            while changed {
                changed = false
                search: for i in out.indices where !wordy(out[i]) || small(out[i]) {
                    for j in out.indices where j != i && (!wordy(out[j]) || small(out[j])) {
                        let a = bounds(out[i]), b = bounds(out[j])
                        guard a.minX - reach <= b.maxX, b.minX - reach <= a.maxX,
                              a.minY - reach <= b.maxY, b.minY - reach <= a.maxY else { continue }
                        out[i] += out[j]
                        out.remove(at: j)
                        changed = true
                        break search
                    }
                }
            }
            return out
        }

        /// The top of a line's small letters and its baseline, box-local: the
        /// first and last rows where the ink is at least 40 per cent as busy as
        /// its busiest row.
        func textLines(line: Set<Int32>, piece r: Piece, box: IntBox, labels: [Int32]) -> (Int, Int) {
            var rows = [Int](repeating: 0, count: r.h)
            for y in r.minY...r.maxY {
                for x in r.minX...r.maxX where line.contains(labels[y * box.w + x]) { rows[y - r.minY] += 1 }
            }
            let peak = rows.max() ?? 0
            let busy = rows.indices.filter { rows[$0] * 10 >= peak * 4 }
            guard let first = busy.first, let last = busy.last else { return (r.minY, r.maxY + 1) }
            return (r.minY + first, r.minY + last + 1)
        }
    }
}
