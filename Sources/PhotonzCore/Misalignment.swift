import CoreGraphics
import Foundation

/// One inconsistency a sharp-eyed designer would mark on a UI screenshot:
/// an edge that almost lines up with the others but misses, a gap in a
/// repeated run that is not the same as the rest, a card or control whose
/// padding or border differs from its siblings'. Every number in it is
/// measured off the pixels by `MisalignmentScan`; nothing is guessed.
public struct Misalignment: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case edge, gap, padding, border }
    public enum Axis: String, Codable, Sendable { case x, y }

    /// Which line of an element is being compared.
    public enum Reading: String, Codable, Sendable, CaseIterable {
        case left, right, centerX, top, bottom, centerY, baseline

        public var axis: Axis {
            switch self {
            case .left, .right, .centerX: .x
            case .top, .bottom, .centerY, .baseline: .y
            }
        }

        public var word: String {
            switch self {
            case .left: "Left edge"
            case .right: "Right edge"
            case .centerX, .centerY: "Center"
            case .top: "Top edge"
            case .bottom: "Bottom edge"
            case .baseline: "Baseline"
            }
        }
    }

    public var kind: Kind
    public var axis: Axis
    public var reading: Reading?
    /// What is off, in the picture's pixels: the element, the gap, the box.
    public var subject: CGRect
    /// What it was compared with, all agreeing with each other, in pixels.
    public var others: [CGRect]
    /// An edge finding's reference: where the subject's compared line would
    /// be if it agreed with the others, in pixels (x for an x finding).
    public var line: CGFloat?
    /// Where the subject's compared line actually is, in pixels.
    public var actual: CGFloat?
    /// The value the others share and the subject's own, in points.
    public var expected: CGFloat
    public var found: CGFloat

    public init(kind: Kind, axis: Axis, reading: Reading? = nil, subject: CGRect, others: [CGRect],
                line: CGFloat? = nil, actual: CGFloat? = nil, expected: CGFloat, found: CGFloat) {
        self.kind = kind
        self.axis = axis
        self.reading = reading
        self.subject = subject
        self.others = others
        self.line = line
        self.actual = actual
        self.expected = expected
        self.found = found
    }

    /// How far off, in points, signed (found minus expected).
    public var delta: CGFloat { found - expected }

    /// What is off, in a few words: "Gap 2 pt wider", "Left edge 1 pt off".
    public var label: String {
        let d = Self.number(abs(delta))
        switch kind {
        case .edge: return "\((reading ?? .left).word) \(d) pt off"
        case .gap: return "Gap \(d) pt \(delta > 0 ? "wider" : "narrower")"
        case .padding: return "Padding \(d) pt \(delta > 0 ? "more" : "less")"
        case .border: return "Border \(d) pt \(delta > 0 ? "thicker" : "thinner")"
        }
    }

    /// The two numbers compared, this one first: "18 vs 16".
    public var numbers: String { "\(Self.number(found)) vs \(Self.number(expected))" }

    /// The readout a mark carries: the label and both numbers, at most 30
    /// characters so it fits the chrome's budget. A center finding's numbers
    /// are offsets from a middle, which read as noise, so it says only how
    /// far off it is.
    public var chip: String {
        if reading == .centerX || reading == .centerY { return label }
        let full = "\(label): \(numbers)"
        if full.count <= 30 { return full }
        // "Left edge" says no more than "Left" beside the numbers.
        let short = "\(label.replacingOccurrences(of: " edge", with: "")): \(numbers)"
        return short.count <= 30 ? short : label
    }

    /// Points as a person writes them: whole when whole, else one decimal.
    public static func number(_ v: CGFloat) -> String {
        let r = (v * 2).rounded() / 2
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }
}

/// Finds what is inconsistent on a UI screenshot. Detection is code, read off
/// the things `LayoutRead` finds:
///
/// * **Edges.** Things that should agree are grouped: the children of one
///   box, or of a set of twin boxes (cards of one width, controls of one
///   height), compared by their inset from their own box, so a list of cards
///   compares every card's title with every other's. Each kind is compared
///   with its own kind (words with words, shapes with shapes) on each of its
///   lines (left, right, center; top, bottom, center, and baseline for
///   words). When most agree and one misses by 1 to 8 points, it is marked,
///   unless it agrees on another line that more of them share (a narrow
///   icon centred among wide ones).
/// * **Gaps.** A run of three or more like things in a row or a column; the
///   runs of one box pooled, so a grid's rows are judged together.
/// * **Padding.** A box whose content all sits off by the same amount from
///   where its twins hold theirs, or whose inset differs from same-height
///   siblings that hug their content (chips, buttons).
/// * **Borders.** Twin boxes whose border widths differ.
///
/// Nothing that is fine is marked: two things that differ by more than
/// `largest` points are taken to differ on purpose, less than `smallest` is
/// within what antialiasing and glyph shapes move.
public enum MisalignmentScan {

    /// A difference above this many points is a different design, not a slip.
    public static let largest: CGFloat = 8.5
    /// A difference below this many points is not marked.
    public static let smallest: CGFloat = 0.9
    /// Things within this many points of each other agree.
    public static let agree: CGFloat = 0.5
    /// Lines of words agree more loosely: a line starting with an A sits
    /// further left in its box than one starting with an L, by up to a
    /// point, though both were set at the same place.
    public static let agreeWords: CGFloat = 1
    public static let smallestWords: CGFloat = 1.5

    /// What is inconsistent on `luma` (inside `region`).
    public static func findings(luma: LumaField, pixelScale: CGFloat, region: CGRect? = nil) -> [Misalignment] {
        let canvas = CGRect(x: 0, y: 0, width: luma.width, height: luma.height)
        let nodes = LayoutRead.read(luma, pixelScale: pixelScale, region: region)
        return findings(in: nodes, canvas: region ?? canvas, pixelScale: pixelScale)
    }

    public static func findings(in nodes: [LayoutNode], canvas: CGRect, pixelScale: CGFloat) -> [Misalignment] {
        Scan(nodes: nodes, canvas: canvas, scale: max(1, pixelScale)).run()
    }

    /// A finding's id in an answer: m1, m2, ... in reading order, the same
    /// every time the same picture is read.
    public static func id(_ index: Int) -> String { "m\(index + 1)" }

    /// The answer `find_misalignments` gives: each finding's id, what is off
    /// with both numbers, and its box in canvas points. With none, the one
    /// short sentence to say.
    public static func report(_ findings: [Misalignment]) -> AgentJSON {
        func box(_ r: CGRect) -> AgentJSON {
            ["x": .number(Double(r.minX)), "y": .number(Double(r.minY)),
             "width": .number(Double(r.width)), "height": .number(Double(r.height))]
        }
        var json: AgentJSON = [
            "count": .number(Double(findings.count)),
            "findings": .array(findings.enumerated().map { i, f in
                ["id": .string(id(i)), "what": .string(f.chip), "kind": .string(f.kind.rawValue), "box": box(f.subject)]
            }),
        ]
        if findings.isEmpty, case .object(var object) = json {
            object["say"] = "Nothing is out of line."
            json = .object(object)
        }
        return json
    }

    /// What a thing is compared with: words with words, shapes with shapes.
    enum Family { case words, shape, mark, rule }

    static func readings(_ family: Family, _ axis: Misalignment.Axis) -> [Misalignment.Reading] {
        switch (family, axis) {
        case (_, .x): [.left, .right, .centerX]
        case (.words, .y): [.baseline]
        case (.rule, .y): [.top]
        case (_, .y): [.top, .bottom, .centerY]
        }
    }

    struct Scan {
        let nodes: [LayoutNode]
        let canvas: CGRect
        let scale: CGFloat
        var children: [Int?: [Int]] = [:]

        init(nodes: [LayoutNode], canvas: CGRect, scale: CGFloat) {
            self.nodes = nodes
            self.canvas = canvas
            self.scale = scale
            for (i, n) in nodes.enumerated() {
                // A child that fills its box is the box's own skin, not content.
                if let p = n.parent, n.rect.width * n.rect.height >= 0.9 * nodes[p].rect.width * nodes[p].rect.height {
                    continue
                }
                children[n.parent, default: []].append(i)
            }
        }

        func origin(_ parent: Int?) -> CGRect { parent.map { nodes[$0].rect } ?? canvas }

        func family(_ i: Int) -> Family {
            switch nodes[i].kind {
            case .text: .words
            case .box: .shape
            case .picture: .shape
            case .mark: .mark
            case .rule: .rule
            }
        }

        func tolerance(_ f: Family) -> (agree: CGFloat, least: CGFloat) {
            f == .words ? (agreeWords, smallestWords) : (agree, smallest)
        }

        func value(_ i: Int, _ r: Misalignment.Reading) -> CGFloat? {
            let n = nodes[i], o = origin(n.parent), rect = n.rect
            let px: CGFloat
            switch r {
            case .left: px = rect.minX - o.minX
            case .right: px = o.maxX - rect.maxX
            case .centerX: px = rect.midX - o.midX
            case .top: px = rect.minY - o.minY
            case .bottom: px = o.maxY - rect.maxY
            case .centerY: px = n.opticalMidY - o.midY
            case .baseline:
                guard let b = n.baseline else { return nil }
                px = b - o.minY
            }
            return px / scale
        }

        /// The absolute pixel line a reading value stands for, in the frame
        /// of `i`'s own box.
        func line(_ i: Int, _ r: Misalignment.Reading, _ v: CGFloat) -> CGFloat {
            let o = origin(nodes[i].parent), px = v * scale
            switch r {
            case .left: return o.minX + px
            case .right: return o.maxX - px
            case .centerX: return o.midX + px
            case .top, .baseline: return o.minY + px
            case .bottom: return o.maxY - px
            case .centerY: return o.midY + px
            }
        }

        func same(_ a: CGFloat, _ b: CGFloat, within points: CGFloat) -> Bool { abs(a - b) <= points * scale }

        // MARK: Settling a set of numbers

        struct Verdict {
            /// The value most of them share.
            var reference: CGFloat
            /// Indices (into the values) that agree with it.
            var agreeing: [Int]
            /// Indices that miss it by `smallest` to `largest`.
            var off: [Int]
        }

        /// Every window of values that are within `largest` of each other,
        /// settled: what most share, and who misses it. A window with no
        /// majority is a `tie` (its two values and who holds each).
        func settle(_ values: [CGFloat], agree: CGFloat = MisalignmentScan.agree,
                    least smallest: CGFloat = MisalignmentScan.smallest) -> (verdicts: [Verdict], ties: [(Int, Int)]) {
            let order = values.indices.sorted { values[$0] < values[$1] }
            var windows: [[Int]] = []
            for i in order {
                if let last = windows.last?.last, values[i] - values[last] <= largest {
                    windows[windows.count - 1].append(i)
                } else {
                    windows.append([i])
                }
            }
            var verdicts: [Verdict] = []
            var ties: [(Int, Int)] = []
            for window in windows where window.count >= 2 {
                // The values in a band `agree` wide starting at this one: the
                // densest band is what most of them share.
                func support(_ i: Int) -> [Int] {
                    window.filter { values[$0] >= values[i] - 0.001 && values[$0] <= values[i] + agree + 0.001 }
                }
                func spread(_ ids: [Int]) -> CGFloat {
                    let v = ids.map { values[$0] }
                    return (v.max() ?? 0) - (v.min() ?? 0)
                }
                let best = window.map { (i: $0, s: support($0)) }.max { a, b in
                    // Most support, then the tightest band.
                    (a.s.count, -spread(a.s)) < (b.s.count, -spread(b.s))
                }
                guard let best else { continue }
                let rivals = window.filter { !best.s.contains($0) && support($0).count >= best.s.count }
                if !rivals.isEmpty {
                    if window.count == 2 { ties.append((window[0], window[1])) }
                    if window.count >= 2, rivals.count == window.count - best.s.count,
                       best.s.count == window.count - best.s.count {
                        // Two camps of equal size: no majority to judge by.
                        verdicts.append(Verdict(reference: .nan, agreeing: best.s, off: rivals))
                    }
                    continue
                }
                let ref = median(best.s.map { values[$0] })
                let off = window.filter { abs(values[$0] - ref) >= smallest && abs(values[$0] - ref) <= largest }
                guard best.s.count >= 2, best.s.count > off.count else { continue }
                verdicts.append(Verdict(reference: ref, agreeing: best.s, off: off))
            }
            return (verdicts, ties)
        }

        func median(_ v: [CGFloat]) -> CGFloat {
            let s = v.sorted()
            guard !s.isEmpty else { return 0 }
            return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
        }

        // MARK: Running every check

        func run() -> [Misalignment] {
            var found: [Misalignment] = []
            var padded: Set<Int> = []
            for axis in [Misalignment.Axis.x, .y] {
                for pool in pools(axis) {
                    let (edges, padding) = edgeFindings(pool, axis)
                    found += padding
                    for f in padding { if let p = index(of: f.subject) { padded.insert(p) } }
                    found += edges
                }
                found += hugPadding(axis)
                found += gaps(axis)
                found += attachments(axis)
            }
            found += borders()
            return tidy(found, padded: padded).map(placed)
        }

        /// A padding or border finding with the two lines its mark spans: the
        /// box's inside edge and its content's edge for padding, the box's
        /// outside and inside edge for a border.
        func placed(_ f: Misalignment) -> Misalignment {
            guard f.kind == .padding || f.kind == .border, let p = index(of: f.subject) else { return f }
            var f = f
            let r = nodes[p].rect, b = nodes[p].border
            if f.kind == .border {
                f.line = r.minY
                f.actual = r.minY + f.found * scale
                return f
            }
            let content = (children[p] ?? []).map { nodes[$0].rect }.reduce(CGRect.null) { $0.union($1) }
            guard !content.isNull else { return f }
            switch f.reading ?? .left {
            case .left: f.line = r.minX + b[1]; f.actual = content.minX
            case .right: f.line = r.maxX - b[3]; f.actual = content.maxX
            case .top, .baseline: f.line = r.minY + b[0]; f.actual = content.minY
            case .bottom: f.line = r.maxY - b[2]; f.actual = content.maxY
            case .centerX, .centerY: break
            }
            return f
        }

        func index(of rect: CGRect) -> Int? { nodes.firstIndex { $0.rect == rect } }

        // MARK: Pools

        /// Boxes that should hold their content the same way along `axis`:
        /// siblings of one kind and one size on that axis. Each set is
        /// judged as one pool of children; the page itself is its own pool.
        func pools(_ axis: Misalignment.Axis) -> [[Int?]] {
            var out: [[Int?]] = [[nil]]
            var seen: Set<Int> = []
            let boxes = nodes.indices.filter { nodes[$0].kind == .box && !(children[$0] ?? []).isEmpty }
            for b in boxes where !seen.contains(b) {
                let size = axis == .x ? nodes[b].rect.width : nodes[b].rect.height
                let twins = boxes.filter { o in
                    !seen.contains(o) && nodes[o].parent == nodes[b].parent
                        && same(axis == .x ? nodes[o].rect.width : nodes[o].rect.height, size, within: agree)
                }
                for t in twins { seen.insert(t) }
                out.append(twins.map { Optional($0) })
            }
            return out
        }

        // MARK: Edges

        func edgeFindings(_ pool: [Int?], _ axis: Misalignment.Axis) -> ([Misalignment], [Misalignment]) {
            let members = pool.flatMap { children[$0] ?? [] }
            var edges: [Misalignment] = []
            var padding: [Misalignment] = []
            // Per parent, per reading: how its members fared, for padding.
            var perParent: [Int: [Misalignment.Reading: [(off: Bool, delta: CGFloat)]]] = [:]
            for family in [Family.words, .shape, .mark, .rule] {
                let all = members.filter { self.family($0) == family }
                // A highlight round one of the things (a picked row round
                // its icon) is not one of them.
                let group = all.filter { w in
                    !(children[w] ?? []).contains { c in all.contains { $0 != w && twins($0, c) } }
                }
                let tol = tolerance(family)
                guard group.count >= 2 else { continue }
                let readings = MisalignmentScan.readings(family, axis)
                var settled: [Misalignment.Reading: (ids: [Int], values: [CGFloat], verdicts: [Verdict])] = [:]
                for r in readings {
                    let ids = group.filter { value($0, r) != nil }
                    let values = ids.compactMap { value($0, r) }
                    // A line's last glyph is often a figure, set with room
                    // either side of its ink, so a right edge of words is
                    // marked only when it is clearly off.
                    let least = family == .words && r == .right ? 2 : tol.least
                    settled[r] = (ids, values, settle(values, agree: tol.agree, least: least).verdicts)
                }
                for r in readings {
                    guard let s = settled[r] else { continue }
                    for v in s.verdicts {
                        if v.reference.isNaN {
                            padding += splitCamps(v, ids: s.ids, values: s.values, reading: r, axis: axis, pool: pool,
                                                  agree: tol.agree)
                            continue
                        }
                        for a in v.agreeing {
                            if let p = nodes[s.ids[a]].parent { perParent[p, default: [:]][r, default: []].append((false, 0)) }
                        }
                        for o in v.off {
                            let id = s.ids[o]
                            let delta = s.values[o] - v.reference
                            if excused(id, delta: delta, by: r, settled: settled) { continue }
                            let mates = v.agreeing.map { s.ids[$0] }.filter { columnMate($0, of: id, axis: axis) }
                            guard mates.count >= 2 || (mates.count == 1 && twins(mates[0], id)) else { continue }
                            if let p = nodes[id].parent { perParent[p, default: [:]][r, default: []].append((true, delta)) }
                            let near = mates.filter { nodes[$0].parent == nodes[id].parent }
                            edges.append(Misalignment(kind: .edge, axis: axis, reading: r, subject: nodes[id].rect,
                                                      others: near.map { nodes[$0].rect },
                                                      line: line(id, r, v.reference), actual: line(id, r, s.values[o]),
                                                      expected: v.reference, found: s.values[o]))
                        }
                    }
                }
                // Two twins and nothing else to judge by: they differ.
                if family == .shape {
                    for r in readings {
                        guard let s = settled[r] else { continue }
                        for (a, b) in settle(s.values, agree: tol.agree, least: tol.least).ties {
                            let ia = s.ids[a], ib = s.ids[b]
                            guard twins(ia, ib), nodes[ia].parent == nodes[ib].parent, columnMate(ia, of: ib, axis: axis),
                                  abs(s.values[a] - s.values[b]) >= smallest else { continue }
                            if excused(ib, delta: s.values[b] - s.values[a], by: r, settled: settled) { continue }
                            let (first, second, fv, sv) = readingOrder(ia, ib) ? (ia, ib, s.values[a], s.values[b])
                                                                               : (ib, ia, s.values[b], s.values[a])
                            edges.append(Misalignment(kind: .edge, axis: axis, reading: r, subject: nodes[second].rect,
                                                      others: [nodes[first].rect], line: line(second, r, fv),
                                                      actual: line(second, r, sv), expected: fv, found: sv))
                        }
                    }
                }
            }
            // A box whose every compared member is off by the same amount
            // has different padding; its members are fine.
            guard pool.count >= 2 else { return (edges, padding) }
            for (p, byReading) in perParent {
                // The line on which all of the box's members are off alike.
                let sides: [Misalignment.Reading] = [.left, .top, .right, .bottom, .baseline]
                guard let (side, offs) = sides.compactMap({ r in byReading[r].map { (r, $0) } }).first(where: { _, results in
                    let offs = results.filter(\.off)
                    guard offs.count >= 2, offs.count == results.count, let d = offs.first?.delta else { return false }
                    return offs.allSatisfy { abs($0.delta - d) <= 1 }
                }), let d = offs.first?.delta else { continue }
                let box = nodes[p].rect
                edges.removeAll { e in nodes.firstIndex { $0.rect == e.subject }.flatMap { nodes[$0].parent } == p }
                let twinsOf = pool.compactMap { $0 }.filter { $0 != p }
                let expected = (inset(p, side) ?? 0) - d
                padding.append(Misalignment(kind: .padding, axis: axis, reading: side, subject: box,
                                            others: twinsOf.map { nodes[$0].rect },
                                            expected: expected, found: inset(p, side) ?? d))
            }
            return (edges, padding)
        }

        /// Two equal camps in a pool of two boxes, each camp one box: the
        /// boxes hold their content differently.
        func splitCamps(_ v: Verdict, ids: [Int], values: [CGFloat], reading: Misalignment.Reading,
                        axis: Misalignment.Axis, pool: [Int?], agree: CGFloat) -> [Misalignment] {
            guard pool.count == 2, let pa = pool[0], let pb = pool[1] else { return [] }
            let a = Set(v.agreeing.map { nodes[ids[$0]].parent }), b = Set(v.off.map { nodes[ids[$0]].parent })
            // Each camp at least two things, so one control of another
            // height is not read as a box's padding.
            guard a.count == 1, b.count == 1, a != b, v.agreeing.count >= 2, v.off.count >= 2,
                  let av = v.agreeing.first.map({ values[$0] }), let bv = v.off.first.map({ values[$0] }),
                  v.agreeing.allSatisfy({ abs(values[$0] - av) <= agree }),
                  v.off.allSatisfy({ abs(values[$0] - bv) <= agree }),
                  abs(av - bv) >= smallest, reading != .centerX, reading != .centerY else { return [] }
            let (first, second) = readingOrder(pa, pb) ? (pa, pb) : (pb, pa)
            guard let fi = inset(first, reading), let si = inset(second, reading) else { return [] }
            guard abs(fi - si) >= smallest, abs(fi - si) <= largest else { return [] }
            return [Misalignment(kind: .padding, axis: axis, reading: reading, subject: nodes[second].rect,
                                 others: [nodes[first].rect], expected: fi, found: si)]
        }

        /// The space between a box's inside edge and its content on the side
        /// `reading` names, in points.
        func inset(_ p: Int, _ reading: Misalignment.Reading) -> CGFloat? {
            let kids = children[p] ?? []
            guard !kids.isEmpty else { return nil }
            let r = nodes[p].rect, b = nodes[p].border
            let content = kids.map { nodes[$0].rect }.reduce(CGRect.null) { $0.union($1) }
            let px: CGFloat
            switch reading {
            case .left: px = content.minX - r.minX - b[1]
            case .right: px = r.maxX - content.maxX - b[3]
            case .top, .baseline: px = content.minY - r.minY - b[0]
            case .bottom: px = r.maxY - content.maxY - b[2]
            case .centerX, .centerY: return nil
            }
            return px / scale
        }

        /// The child of `p` nearest its side `reading`.
        func edgeChild(_ p: Int, _ reading: Misalignment.Reading) -> Int? {
            let kids = children[p] ?? []
            switch reading {
            case .left: return kids.min { nodes[$0].rect.minX < nodes[$1].rect.minX }
            case .right: return kids.max { nodes[$0].rect.maxX < nodes[$1].rect.maxX }
            case .top, .baseline: return kids.min { nodes[$0].rect.minY < nodes[$1].rect.minY }
            case .bottom: return kids.max { nodes[$0].rect.maxY < nodes[$1].rect.maxY }
            case .centerX, .centerY: return nil
            }
        }

        /// A member off on one line that agrees on another line more of the
        /// group share is placed on purpose: a narrow icon centred among
        /// wide ones, a short label right-aligned in a column of them.
        func excused(_ id: Int, delta: CGFloat, by r: Misalignment.Reading,
                     settled: [Misalignment.Reading: (ids: [Int], values: [CGFloat], verdicts: [Verdict])]) -> Bool {
            guard let mine = settled[r] else { return false }
            let support = mine.verdicts.first { v in v.off.contains { mine.ids[$0] == id } }?.agreeing.count ?? 0
            // A shape that agrees on its left but not its right is a
            // different width, which is a fault; only a centred one is placed
            // on purpose. Words of different lengths agree on one end only.
            // A shape of another height (for an x line) is another kind of
            // thing, which may well share only one end with them.
            let centred: Set<Misalignment.Reading> = [.centerX, .centerY]
            let agreeing = mine.verdicts.first { v in v.off.contains { mine.ids[$0] == id } }?.agreeing.map { mine.ids[$0] } ?? []
            let kin = agreeing.contains { a in
                r.axis == .x ? same(nodes[a].rect.height, nodes[id].rect.height, within: 1)
                             : same(nodes[a].rect.width, nodes[id].rect.width, within: 1)
            }
            for (other, s) in settled where other != r && (family(id) == .words || !kin || centred.contains(other)) {
                guard let at = s.ids.firstIndex(of: id) else { continue }
                for v in s.verdicts where !v.reference.isNaN && v.agreeing.contains(at) && v.agreeing.count >= support {
                    return true
                }
            }
            return false
        }

        /// Whether `a` is in the same column (for an x line) or row (for a
        /// y line) as `b`: in another box of the pool, or in the same box
        /// but clear of it across the axis.
        func columnMate(_ a: Int, of b: Int, axis: Misalignment.Axis) -> Bool {
            guard nodes[a].parent == nodes[b].parent else { return true }
            let ra = nodes[a].rect, rb = nodes[b].rect
            return axis == .x ? (ra.maxY <= rb.minY || rb.maxY <= ra.minY) : (ra.maxX <= rb.minX || rb.maxX <= ra.minX)
        }

        func twins(_ a: Int, _ b: Int) -> Bool {
            let ra = nodes[a].rect, rb = nodes[b].rect
            return family(a) == family(b)
                && same(ra.width, rb.width, within: agree) && same(ra.height, rb.height, within: agree)
        }

        func readingOrder(_ a: Int, _ b: Int) -> Bool {
            let ra = nodes[a].rect, rb = nodes[b].rect
            return (ra.minY, ra.minX) < (rb.minY, rb.minX)
        }

        // MARK: Padding of boxes that hug their content

        /// Siblings of one height (for left and right) or one width (top and
        /// bottom) whose other size follows their content, chips and
        /// buttons: their insets should match.
        func hugPadding(_ axis: Misalignment.Axis) -> [Misalignment] {
            var out: [Misalignment] = []
            // Boxes that hold only words: chips, buttons, tags.
            let boxes = nodes.indices.filter { i in
                nodes[i].kind == .box && !(children[i] ?? []).isEmpty
                    && (children[i] ?? []).allSatisfy { family($0) == .words }
            }
            var seen: Set<Int> = []
            for b in boxes where !seen.contains(b) {
                let cross = axis == .x ? nodes[b].rect.height : nodes[b].rect.width
                let group = boxes.filter { o in
                    !seen.contains(o) && nodes[o].parent == nodes[b].parent
                        && same(axis == .x ? nodes[o].rect.height : nodes[o].rect.width, cross, within: agree)
                }
                for g in group { seen.insert(g) }
                guard group.count >= 3 else { continue }
                // Only boxes that differ along the axis hug their content.
                let along = group.map { axis == .x ? nodes[$0].rect.width : nodes[$0].rect.height }
                guard let lo = along.min(), let hi = along.max(), hi - lo > agree * scale else { continue }
                for side in axis == .x ? [Misalignment.Reading.left, .right] : [.top, .bottom] {
                    let ids = group.filter { inset($0, side) != nil }
                    let values = ids.compactMap { inset($0, side) }
                    // Content that starts with a word is judged as words are.
                    let wordy = ids.contains { edgeChild($0, side).map { family($0) == .words } ?? false }
                    let tol = tolerance(wordy ? .words : .shape)
                    for v in settle(values, agree: tol.agree, least: tol.least).verdicts where !v.reference.isNaN {
                        for o in v.off {
                            out.append(Misalignment(kind: .padding, axis: axis, reading: side, subject: nodes[ids[o]].rect,
                                                    others: v.agreeing.map { nodes[ids[$0]].rect },
                                                    expected: v.reference, found: values[o]))
                        }
                    }
                }
            }
            return out
        }

        // MARK: Words and what they belong to

        /// A line of words placed against a shape beside it or above it, a
        /// label against its switch, a caption under its picture: each pair
        /// on the page should sit the same way.
        func attachments(_ axis: Misalignment.Axis) -> [Misalignment] {
            struct Pair { var words: Int; var anchor: Int; var values: [Misalignment.Reading: CGFloat] }
            var pairs: [Pair] = []
            for (_, kids) in children {
                let shapes = kids.filter { [.shape, .mark].contains(family($0)) }
                for t in kids where family(t) == .words {
                    let rt = nodes[t].rect
                    if axis == .x {
                        // A caption: the nearest shape just above it, over it.
                        let above = shapes.filter { a in
                            let ra = nodes[a].rect
                            let overlap = min(ra.maxX, rt.maxX) - max(ra.minX, rt.minX)
                            return ra.maxY <= rt.minY + 1 && rt.minY - ra.maxY <= 2 * rt.height
                                && overlap >= 0.8 * min(rt.width, ra.width)
                        }
                        if let a = above.max(by: { nodes[$0].rect.maxY < nodes[$1].rect.maxY }) {
                            let ra = nodes[a].rect
                            pairs.append(Pair(words: t, anchor: a, values: [.left: (rt.minX - ra.minX) / scale,
                                                                             .centerX: (rt.midX - ra.midX) / scale]))
                        }
                        // A label just left of its control: the space between.
                        let beside = shapes.filter { a in
                            let ra = nodes[a].rect
                            return ra.minX >= rt.maxX && ra.minX - rt.maxX <= 3 * rt.height
                                && min(ra.maxY, rt.maxY) - max(ra.minY, rt.minY) >= 0.5 * rt.height
                        }
                        if let a = beside.min(by: { nodes[$0].rect.minX < nodes[$1].rect.minX }) {
                            pairs.append(Pair(words: t, anchor: a, values: [.right: (nodes[a].rect.minX - rt.maxX) / scale]))
                        }
                    } else {
                        // In a row with a control: where the words sit across it,
                        // by their baseline. The top of the small letters reads
                        // less surely: a word full of capitals and ascenders
                        // lifts it.
                        let band = (nodes[t].textTop ?? rt.minY)...(nodes[t].baseline ?? rt.maxY)
                        let row = shapes.filter { a in
                            let ra = nodes[a].rect
                            let overlap = min(ra.maxY, band.upperBound) - max(ra.minY, band.lowerBound)
                            return overlap >= 0.5 * (band.upperBound - band.lowerBound) && ra.height < 3 * rt.height
                                && (ra.maxX <= rt.minX || ra.minX >= rt.maxX)
                        }
                        if let a = row.min(by: { distance(nodes[$0].rect, rt) < distance(nodes[$1].rect, rt) }) {
                            pairs.append(Pair(words: t, anchor: a,
                                              values: [.baseline: ((nodes[t].baseline ?? rt.maxY) - nodes[a].rect.midY) / scale]))
                        }
                    }
                }
            }
            var out: [Misalignment] = []
            let readings: [Misalignment.Reading] = axis == .x ? [.left, .centerX, .right] : [.baseline]
            var settled: [Misalignment.Reading: (ids: [Int], values: [CGFloat], verdicts: [Verdict])] = [:]
            for r in readings {
                let ids = pairs.indices.filter { pairs[$0].values[r] != nil }
                let values = ids.compactMap { pairs[$0].values[r] }
                // Where words sit across a row is read off their small
                // letters, which do not vary with the glyphs; along it, the
                // first and last glyph move the ink.
                let tol = r == .baseline ? (agree, CGFloat(1)) : tolerance(.words)
                settled[r] = (ids, values, settle(values, agree: tol.0, least: tol.1).verdicts)
            }
            for r in readings {
                guard let s = settled[r] else { continue }
                for v in s.verdicts where !v.reference.isNaN {
                    for o in v.off {
                        let pair = pairs[s.ids[o]]
                        // Placed on purpose if it agrees on the other line.
                        let other = readings.filter { $0 != r }.contains { r2 in
                            guard let s2 = settled[r2], let at = s2.ids.firstIndex(of: s.ids[o]) else { return false }
                            return s2.verdicts.contains { !$0.reference.isNaN && $0.agreeing.contains(at)
                                && $0.agreeing.count >= v.agreeing.count }
                        }
                        if other { continue }
                        let rt = nodes[pair.words].rect, ra = nodes[pair.anchor].rect
                        let shift = (s.values[o] - v.reference) * scale
                        let actual: CGFloat
                        switch r {
                        case .left: actual = rt.minX
                        case .centerX: actual = rt.midX
                        case .right: actual = rt.maxX
                        default: actual = nodes[pair.words].baseline ?? rt.maxY
                        }
                        let reading: Misalignment.Reading = r == .right ? .right : r
                        out.append(Misalignment(kind: .edge, axis: axis, reading: reading, subject: rt, others: [ra],
                                                line: r == .right ? actual + shift : actual - shift, actual: actual,
                                                expected: v.reference, found: s.values[o]))
                    }
                }
            }
            return out
        }

        func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
            max(0, max(a.minX - b.maxX, b.minX - a.maxX)) + max(0, max(a.minY - b.maxY, b.minY - a.maxY))
        }

        // MARK: Gaps

        struct Gap {
            var rect: CGRect
            var size: CGFloat
            var before: Int
            var after: Int
        }

        /// Runs of three or more like things side by side (x) or stacked
        /// (y), and the gaps between them, pooled by box.
        func gaps(_ axis: Misalignment.Axis) -> [Misalignment] {
            var out: [Misalignment] = []
            for (_, kids) in children {
                let things = kids.filter { [.shape, .mark].contains(family($0)) }
                guard things.count >= 3 else { continue }
                // Runs: like things that share a row (x) or a column (y).
                var runs: [[Int]] = []
                var placed: Set<Int> = []
                for t in things where !placed.contains(t) {
                    var run = [t]
                    placed.insert(t)
                    for u in things where !placed.contains(u) && inLine(t, u, axis) {
                        run.append(u)
                        placed.insert(u)
                    }
                    if run.count >= 3 { runs.append(run) }
                }
                // Pool the runs of one size: a grid's rows are judged together.
                var pools: [[Gap]] = []
                var poolSizes: [CGFloat] = []
                for run in runs {
                    let sorted = run.sorted { axis == .x ? nodes[$0].rect.minX < nodes[$1].rect.minX
                                                         : nodes[$0].rect.minY < nodes[$1].rect.minY }
                    var gaps: [Gap] = []
                    for (a, b) in zip(sorted, sorted.dropFirst()) {
                        let ra = nodes[a].rect, rb = nodes[b].rect
                        let size = axis == .x ? rb.minX - ra.maxX : rb.minY - ra.maxY
                        guard size > 0 else { continue }
                        let rect = axis == .x
                            ? CGRect(x: ra.maxX, y: min(ra.minY, rb.minY), width: size,
                                     height: max(ra.maxY, rb.maxY) - min(ra.minY, rb.minY))
                            : CGRect(x: min(ra.minX, rb.minX), y: ra.maxY,
                                     width: max(ra.maxX, rb.maxX) - min(ra.minX, rb.minX), height: size)
                        gaps.append(Gap(rect: rect, size: size / scale, before: a, after: b))
                    }
                    let cross = axis == .x ? nodes[run[0]].rect.height : nodes[run[0]].rect.width
                    if let i = poolSizes.firstIndex(where: { same($0, cross, within: 1) }) {
                        pools[i] += gaps
                    } else {
                        pools.append(gaps)
                        poolSizes.append(cross)
                    }
                }
                for pool in pools where pool.count >= 2 {
                    let values = pool.map(\.size)
                    let (verdicts, ties) = settle(values)
                    var off: [(Gap, CGFloat, [CGRect])] = []
                    for v in verdicts where !v.reference.isNaN {
                        for o in v.off { off.append((pool[o], v.reference, v.agreeing.map { pool[$0].rect })) }
                    }
                    if pool.count == 2, let (a, b) = ties.first, abs(values[a] - values[b]) >= smallest {
                        let (first, second) = pool[a].rect.minX + pool[a].rect.minY <= pool[b].rect.minX + pool[b].rect.minY
                            ? (a, b) : (b, a)
                        off.append((pool[second], values[first], [pool[first].rect]))
                    }
                    // Both gaps round one thing off by the same amount, one
                    // wider and one narrower: the thing moved, not the gaps.
                    var used: Set<Int> = []
                    for (i, (g, ref, _)) in off.enumerated() where !used.contains(i) {
                        if let j = off.indices.first(where: { j in
                            j != i && !used.contains(j) && off[j].0.before == g.after
                                && abs((off[j].0.size - off[j].1) + (g.size - ref)) <= agree
                        }) {
                            used.insert(i)
                            used.insert(j)
                            let moved = g.after, r = nodes[moved].rect
                            let reading: Misalignment.Reading = axis == .x ? .left : .top
                            let shift = (g.size - ref) * scale
                            let actualLine = axis == .x ? r.minX : r.minY
                            out.append(Misalignment(kind: .edge, axis: axis, reading: reading, subject: r,
                                                    others: [nodes[g.before].rect, nodes[off[j].0.after].rect],
                                                    line: actualLine - shift, actual: actualLine,
                                                    expected: ref, found: g.size))
                        }
                    }
                    for (i, (g, ref, others)) in off.enumerated() where !used.contains(i) {
                        out.append(Misalignment(kind: .gap, axis: axis, subject: g.rect, others: others,
                                                expected: ref, found: g.size))
                    }
                }
            }
            return out
        }

        /// Like things in one row (x) or column (y): the same kind, the same
        /// size across the axis, overlapping across it by at least half.
        func inLine(_ a: Int, _ b: Int, _ axis: Misalignment.Axis) -> Bool {
            guard family(a) == family(b) else { return false }
            let ra = nodes[a].rect, rb = nodes[b].rect
            if axis == .x {
                guard same(ra.height, rb.height, within: 1) else { return false }
                let overlap = min(ra.maxY, rb.maxY) - max(ra.minY, rb.minY)
                return overlap >= 0.5 * min(ra.height, rb.height)
            }
            guard same(ra.width, rb.width, within: 1) else { return false }
            let overlap = min(ra.maxX, rb.maxX) - max(ra.minX, rb.minX)
            return overlap >= 0.5 * min(ra.width, rb.width)
        }

        // MARK: Borders

        func borders() -> [Misalignment] {
            var out: [Misalignment] = []
            let boxes = nodes.indices.filter { nodes[$0].kind == .box }
            var seen: Set<Int> = []
            for b in boxes where !seen.contains(b) {
                let group = boxes.filter { o in
                    !seen.contains(o) && nodes[o].parent == nodes[b].parent && sameFill(o, b)
                        // A thicker border can grow the box it rings.
                        && (same(nodes[o].rect.width, nodes[b].rect.width, within: 4)
                            || same(nodes[o].rect.height, nodes[b].rect.height, within: 4))
                }
                for g in group { seen.insert(g) }
                guard group.count >= 2, group.contains(where: { nodes[$0].borderWidth >= scale }) else { continue }
                let values = group.map { nodes[$0].borderWidth / scale }
                let (verdicts, ties) = settle(values)
                for v in verdicts where !v.reference.isNaN {
                    for o in v.off {
                        out.append(Misalignment(kind: .border, axis: .x, subject: nodes[group[o]].rect,
                                                others: v.agreeing.map { nodes[group[$0]].rect },
                                                expected: v.reference, found: values[o]))
                    }
                }
                if group.count == 2, let (a, b) = ties.first, abs(values[a] - values[b]) >= smallest {
                    let (first, second) = readingOrder(group[a], group[b]) ? (a, b) : (b, a)
                    out.append(Misalignment(kind: .border, axis: .x, subject: nodes[group[second]].rect,
                                            others: [nodes[group[first]].rect],
                                            expected: values[first], found: values[second]))
                }
            }
            return out
        }

        func sameFill(_ a: Int, _ b: Int) -> Bool {
            guard let fa = nodes[a].fill, let fb = nodes[b].fill else { return false }
            return LayoutRead.Reader.distance(fa, fb) <= LayoutRead.inkThreshold
        }

        // MARK: One mark per fault

        /// One finding per thing and axis (the biggest), none inside a box
        /// already marked for its padding on that axis, and a box whose
        /// border differs not marked again for the padding the border moved.
        func tidy(_ all: [Misalignment], padded: Set<Int>) -> [Misalignment] {
            var best: [String: Misalignment] = [:]
            var order: [String] = []
            let bordered = Set(all.filter { $0.kind == .border }.map(\.subject))
            for f in all {
                if f.kind != .border && bordered.contains(f.subject) { continue }
                if f.kind == .edge, let i = index(of: f.subject), let p = nodes[i].parent,
                   all.contains(where: { $0.kind == .padding && $0.axis == f.axis && $0.subject == nodes[p].rect }) {
                    continue
                }
                let key: String
                switch f.kind {
                case .edge: key = "e\(f.subject)\(f.axis)"
                case .padding: key = "p\(f.subject)"
                case .gap: key = "g\(f.subject)"
                case .border: key = "b\(f.subject)"
                }
                if let have = best[key] {
                    // The biggest miss; of two the same, the one measured from
                    // the nearer edge, whose numbers a person can check.
                    let bigger = abs(f.delta) > abs(have.delta) + agree
                    let nearer = abs(abs(f.delta) - abs(have.delta)) <= agree && abs(f.found) < abs(have.found)
                    if bigger || nearer || (have.reading == .centerX || have.reading == .centerY) {
                        best[key] = f
                    }
                } else {
                    best[key] = f
                    order.append(key)
                }
            }
            return order.compactMap { best[$0] }.sorted { a, b in
                (a.subject.minY, a.subject.minX) < (b.subject.minY, b.subject.minX)
            }
        }
    }
}

// MARK: - The mark

/// Where a finding's mark goes, in the Measure tool's own look: an edge is an
/// alignment guide down the line the others share, with the bracket the
/// guide draws round whatever misses it; a gap, a padding and a border are
/// a caliper across the space or band that differs. Every mark carries the
/// finding's words and numbers as its readout.
public struct MisalignmentMark: Hashable, Sendable {
    public var mode: MeasureMode
    public var start: CGPoint
    public var end: CGPoint
    /// For an edge: the guide's check, the others ticked where they agree
    /// and the subject bracketed where it misses.
    public var alignment: AlignmentCheck?
    /// The readout, and the layer's name.
    public var chip: String
    public var name: String
    /// What the readout must stay off.
    public var subjects: [CGRect]

    public init?(_ f: Misalignment, pixelScale: CGFloat) {
        let scale = max(1, pixelScale)
        chip = f.chip
        name = f.label
        subjects = [f.subject] + f.others
        switch f.kind {
        case .edge:
            guard let line = f.line, let actual = f.actual else { return nil }
            let vertical = f.axis == .x
            func span(_ r: CGRect) -> (CGFloat, CGFloat) { vertical ? (r.minY, r.maxY) : (r.minX, r.maxX) }
            var items = f.others.map { o -> AlignmentItem in
                let (a, b) = span(o)
                return AlignmentItem(edge: line, spanStart: a, spanEnd: b)
            }
            let (s0, s1) = span(f.subject)
            // Nothing beside it on the page to tick (it was compared with the
            // same thing in other cards): the guide itself reaches past it
            // either side, where the others' line runs.
            if items.isEmpty {
                let reach = max(s1 - s0, 12 * scale)
                items = [AlignmentItem(edge: line, spanStart: s0 - reach - 4 * scale, spanEnd: s0 - 4 * scale),
                         AlignmentItem(edge: line, spanStart: s1 + 4 * scale, spanEnd: s1 + reach + 4 * scale)]
            }
            items.append(AlignmentItem(edge: actual, spanStart: s0, spanEnd: s1))
            let lo = items.map { min($0.spanStart, $0.spanEnd) }.min() ?? s0
            let hi = items.map { max($0.spanStart, $0.spanEnd) }.max() ?? s1
            mode = vertical ? .vertical : .horizontal
            start = vertical ? CGPoint(x: line, y: lo) : CGPoint(x: lo, y: line)
            end = vertical ? CGPoint(x: line, y: hi) : CGPoint(x: hi, y: line)
            alignment = AlignmentCheck(items: items, tolerance: AlignmentCheck.deviceTolerance(logical: 0.5, pixelScale: scale))
        case .gap:
            let g = f.subject
            alignment = nil
            if f.axis == .x {
                mode = .horizontal
                start = CGPoint(x: g.minX, y: g.midY)
                end = CGPoint(x: g.maxX, y: g.midY)
            } else {
                mode = .vertical
                start = CGPoint(x: g.midX, y: g.minY)
                end = CGPoint(x: g.midX, y: g.maxY)
            }
        case .padding, .border:
            guard let line = f.line, let actual = f.actual, abs(actual - line) >= 1 else { return nil }
            let r = f.subject
            alignment = nil
            let across = f.kind == .border || [.top, .bottom, .baseline].contains(f.reading ?? .left)
            if across {
                mode = .vertical
                start = CGPoint(x: r.midX, y: min(line, actual))
                end = CGPoint(x: r.midX, y: max(line, actual))
            } else {
                mode = .horizontal
                start = CGPoint(x: min(line, actual), y: r.midY)
                end = CGPoint(x: max(line, actual), y: r.midY)
            }
            // The readout stays off the content, not the whole box it is in.
            subjects = f.others
        }
    }
}
