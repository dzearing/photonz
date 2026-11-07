import CoreGraphics
import Foundation

// A break in an icon (`docs/design/ask.md`, "An icon"). Asked for a balloon
// popping, the model draws a clean balloon and a poor burst: told to tear what
// it drew, it closed the tear, lost the balloon or made a bomb, at scores from
// 25 to 85 on the same request (the eval, 2026-11-05). Writing that geometry
// is what it cannot do, so it does not: it says what the object is, draws it
// whole, the way it draws every icon well, and this tears the outline it drew.
// A vector tool, like a zig zag or a scissors: it reads only the shapes it is
// given, knows nothing of what they are, and works on any closed outline.

public enum AskIconBreak {

    /// The most a good answer holds: an object, in a few words.
    public static let mostAnswerTokens = 24
    /// The marks flying from the tear.
    public static let markCount = 3

    /// How much of the outline goes.
    static let tornShare: CGFloat = 0.3
    /// How far the tear reaches into the object, as a share of its size,
    /// and how far back the middle of it comes.
    static let tearDepth: CGFloat = 0.2
    static let tearReturn: CGFloat = 0.3
    /// The marks, as shares of the object's size, and the angle between them.
    static let markGap: CGFloat = 0.155
    static let markLength: CGFloat = 0.16
    static let markWeight: CGFloat = 0.125
    static let markSpread: CGFloat = 0.6
    /// The heaviest a line may be, as a share of the object's size: past this
    /// the teeth of the tear close up at 16 px.
    static let lineShare: CGFloat = 0.146
    /// A closed outline under this share of the drawing clots: its line fills
    /// it, so it lands solid (`AskIcon.smallParts` says the same to the model).
    static let smallestOutline: CGFloat = 4.0 / 24
    /// Where it tears: the upper right, the way a mark is read in an icon,
    /// away from whatever an object hangs or stands on.
    static let tearAngle: CGFloat = -.pi / 4

    /// The question, asked before anything is drawn. Its example matters:
    /// without one the model answered no to a balloon popping.
    static let question = """
        An icon was asked for. Is the one object in it bursting, popping, breaking, tearing, cracking, shattering or broken?
        If it is, reply with only the object, whole and at rest, in a few words. For example: a kite
        If the object is whole, or something else is happening to it, reply only: no.

        The request:
        """

    /// The body of the one call that asks: no tools, no document.
    public static func questionBody(model: String, request: String) -> AgentJSON {
        ["model": .string(model), "stream": false, "think": false, "keep_alive": "30m",
         "messages": [["role": "user", "content": .string("\(question) \(request)")]],
         "options": ["temperature": 0, "num_predict": .number(Double(mostAnswerTokens))]]
    }

    /// The object to draw whole, or nil when nothing is breaking.
    public static func object(fromAnswer answer: String) -> String? {
        let words = AskConversation.withoutThinking(answer).trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        guard !words.isEmpty, words.lowercased() != "no", !words.contains("<"),
              words.split(separator: " ").count <= 8 else { return nil }
        return words
    }

    /// What the model is asked to draw in place of the request.
    static func wholeRequest(object: String, request: String) -> String {
        let kind = AskIcon.isAppIcon(request) ? "an app icon" : "an icon"
        let look = AskIcon.look(in: request).map { ", \($0.rawValue)" } ?? ""
        return "make \(kind) of \(object)\(look), whole and at rest, with nothing happening to it and no marks around it. "
            + "Include every part that makes it recognisable, the small ones and anything attached to it. "
            + "Draw its main outline as one closed shape, big: about 14 across and 15 tall, with what is attached to it "
            + "short. \(AskIcon.smallParts)"
    }

    /// What the model is told when its drawing has no outline to tear.
    static let needsAnOutline = """
        Not planned: its main outline is not one closed shape. Draw it as one circle, ellipse, rect or path ending \
        in Z, with an id, and no transform. Call add_drawing once more with the whole svg drawn again.
        """

    /// What every mark flying from a tear is named from, which is also how a
    /// torn drawing is told from one drawn on the grid.
    public static let markName = "burst-"

    /// Whether a part of a drawing is one of those marks. A part's id comes
    /// back tidied into a name, so "burst-1" reads "Burst 1" here.
    public static func isMark(_ name: String?) -> Bool {
        name?.lowercased().hasPrefix(markName.replacingOccurrences(of: "-", with: " ")) == true
    }

    /// `svg` with its biggest outline torn at the upper right and marks flying
    /// from the tear, or nil when it has no closed outline to tear.
    public static func applied(to svg: String) -> String? {
        guard !svg.contains("transform"), case .success(let art) = SVGArtwork.parse(svg) else { return nil }
        let drawn = art.parts.filter { $0.name?.lowercased() != "tile" }
        guard let body = drawn.max(by: { area($0) < area($1) }), let name = body.name,
              let runs = runs(of: body.shape), let tag = tag(named: name, in: svg) else { return nil }
        let box = SVGArtwork.shapeBounds(body.shape)
        let size = (box.width + box.height) / 2
        let centre = CGPoint(x: box.midX, y: box.midY)
        guard size > 0, let outline = torn(runs, centre: centre, size: size) else { return nil }

        let weighted = art.parts.first { $0.stroke != nil && $0.strokeWidth > 0 }
        guard let ink = weighted?.stroke ?? drawn.last(where: { $0.fill != nil })?.fill else { return nil }
        let drawnWeight = weighted?.strokeWidth
        let weight = drawnWeight.map { min($0, size * lineShare) } ?? size * markWeight
        let marks = (0..<markCount).map { index -> String in
            let turn = (CGFloat(index) - CGFloat(markCount - 1) / 2) * markSpread
            let angle = tearAngle + turn
            let way = CGPoint(x: cos(angle), y: sin(angle))
            let edge = reach(of: runs, from: centre, along: way)
            let start = CGPoint(x: edge.x + way.x * size * markGap, y: edge.y + way.y * size * markGap)
            let end = CGPoint(x: start.x + way.x * size * markLength, y: start.y + way.y * size * markLength)
            return #"<path id="\#(markName)\#(index + 1)" d="M\#(text(start)) L\#(text(end))" fill="none" stroke="\#(ink)" "#
                + #"stroke-width="\#(number(weight))" stroke-linecap="round"/>"#
        }
        var out = svg
        out.replaceSubrange(tag.range, with: tag.asPath(outline))
        if let drawnWeight, weight < drawnWeight { out = thinned(out, to: weight) }
        let small = (art.viewBox?.width ?? max(art.bounds.width, art.bounds.height)) * smallestOutline
        for part in drawn where part != body && part.fill == nil && part.stroke != nil && isClosed(part.shape) {
            let own = SVGArtwork.shapeBounds(part.shape)
            guard max(own.width, own.height) < small, let name = part.name, let found = Self.tag(named: name, in: out) else { continue }
            out.replaceSubrange(found.range, with: found.asSolid(ink: ink))
        }
        guard let close = out.range(of: "</svg>", options: .backwards) else { return nil }
        out.insert(contentsOf: marks.joined() , at: close.lowerBound)
        return out
    }

    private static func isClosed(_ shape: SVGArtwork.Shape) -> Bool {
        if case .path(let outline) = shape { return outline.closed }
        return true
    }

    /// Every line in `svg` at `weight`.
    private static func thinned(_ svg: String, to weight: CGFloat) -> String {
        svg.replacingOccurrences(of: #"stroke-width\s*=\s*"[^"]*""#, with: #"stroke-width="\#(number(weight))""#,
                                 options: .regularExpression)
    }

    // MARK: The outline

    /// One cubic run of an outline.
    struct Run {
        var start, control1, control2, end: CGPoint

        func point(at t: CGFloat) -> CGPoint {
            CGPoint(x: Bezier.value(start.x, control1.x, control2.x, end.x, at: t),
                    y: Bezier.value(start.y, control1.y, control2.y, end.y, at: t))
        }

        /// The run between `from` and `to`, each from 0 to 1.
        func between(_ from: CGFloat, _ to: CGFloat) -> Run {
            let tail = from <= 0 ? self : split(at: from).after
            return to >= 1 ? tail : tail.split(at: from <= 0 ? to : (to - from) / (1 - from)).before
        }

        private func split(at t: CGFloat) -> (before: Run, after: Run) {
            func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
            let a = mix(start, control1), b = mix(control1, control2), c = mix(control2, end)
            let d = mix(a, b), e = mix(b, c), f = mix(d, e)
            return (Run(start: start, control1: a, control2: d, end: f), Run(start: f, control1: e, control2: c, end: end))
        }

        var isStraight: Bool {
            func on(_ p: CGPoint) -> Bool {
                let line = CGPoint(x: end.x - start.x, y: end.y - start.y)
                return abs((p.x - start.x) * line.y - (p.y - start.y) * line.x) < 1e-6 * max(1, hypot(line.x, line.y))
            }
            return on(control1) && on(control2)
        }
    }

    private static func area(_ part: SVGArtwork.Part) -> CGFloat {
        let box = SVGArtwork.shapeBounds(part.shape)
        return box.width * box.height
    }

    /// `shape` as a loop of runs, or nil when it is not one closed outline.
    static func runs(of shape: SVGArtwork.Shape) -> [Run]? {
        switch shape {
        case .ellipse(let box):
            return loop(corners(of: box, radiusX: box.width / 2, radiusY: box.height / 2))
        case .rect(let box, let radius):
            return loop(corners(of: box, radiusX: radius, radiusY: radius))
        case .path(let outline):
            guard outline.closed, outline.rings.count == 1, let ring = outline.rings.first, ring.count >= 3 else { return nil }
            return ring.indices.map { index in
                let from = ring[index], to = ring[(index + 1) % ring.count]
                let out = from.handleOut ?? .zero, into = to.handleIn ?? .zero
                return Run(start: from.point, control1: CGPoint(x: from.point.x + out.x, y: from.point.y + out.y),
                           control2: CGPoint(x: to.point.x + into.x, y: to.point.y + into.y), end: to.point)
            }
        }
    }

    /// A box with rounded corners as the four arcs and four sides it is made of.
    private static func corners(of box: CGRect, radiusX: CGFloat, radiusY: CGFloat) -> [Run] {
        let k: CGFloat = 0.5522847498
        let x = min(radiusX, box.width / 2), y = min(radiusY, box.height / 2)
        func arc(_ from: CGPoint, _ to: CGPoint, _ corner: CGPoint) -> Run {
            Run(start: from, control1: CGPoint(x: from.x + (corner.x - from.x) * k, y: from.y + (corner.y - from.y) * k),
                control2: CGPoint(x: to.x + (corner.x - to.x) * k, y: to.y + (corner.y - to.y) * k), end: to)
        }
        let (l, r, t, b) = (box.minX, box.maxX, box.minY, box.maxY)
        return [arc(CGPoint(x: r - x, y: t), CGPoint(x: r, y: t + y), CGPoint(x: r, y: t)),
                arc(CGPoint(x: r, y: b - y), CGPoint(x: r - x, y: b), CGPoint(x: r, y: b)),
                arc(CGPoint(x: l + x, y: b), CGPoint(x: l, y: b - y), CGPoint(x: l, y: b)),
                arc(CGPoint(x: l, y: t + y), CGPoint(x: l + x, y: t), CGPoint(x: l, y: t))]
    }

    /// Arcs joined by whatever straight sides lie between them.
    private static func loop(_ arcs: [Run]) -> [Run] {
        arcs.indices.flatMap { index -> [Run] in
            let arc = arcs[index], next = arcs[(index + 1) % arcs.count]
            guard hypot(arc.end.x - next.start.x, arc.end.y - next.start.y) > 1e-6 else { return [arc] }
            return [arc, Run(start: arc.end, control1: arc.end, control2: next.start, end: next.start)]
        }
    }

    /// Where along a loop each run starts and how long it is, in small steps.
    private static func lengths(_ runs: [Run]) -> [CGFloat] {
        runs.map { run in
            (1...32).reduce((length: CGFloat(0), last: run.start)) { sum, step in
                let point = run.point(at: CGFloat(step) / 32)
                return (sum.length + hypot(point.x - sum.last.x, point.y - sum.last.y), point)
            }.length
        }
    }

    /// The run and the place in it `distance` along the loop.
    private static func place(_ distance: CGFloat, lengths: [CGFloat]) -> (run: Int, t: CGFloat) {
        let total = lengths.reduce(0, +)
        var left = distance.truncatingRemainder(dividingBy: total)
        if left < 0 { left += total }
        for (index, length) in lengths.enumerated() {
            if left <= length, length > 0 { return (index, left / length) }
            left -= length
        }
        return (lengths.count - 1, 1)
    }

    /// The furthest of the outline along `way` from `centre`, and how far
    /// round the loop it is.
    private static func furthest(of runs: [Run], from centre: CGPoint, along way: CGPoint,
                                 lengths: [CGFloat]) -> (point: CGPoint, distance: CGFloat) {
        var best = (point: runs[0].start, distance: CGFloat(0), reach: -CGFloat.infinity)
        var before: CGFloat = 0
        for (index, run) in runs.enumerated() {
            for step in 0...32 {
                let t = CGFloat(step) / 32
                let point = run.point(at: t)
                let reach = (point.x - centre.x) * way.x + (point.y - centre.y) * way.y
                if reach > best.reach { best = (point, before + lengths[index] * t, reach) }
            }
            before += lengths[index]
        }
        return (best.point, best.distance)
    }

    /// Where the outline lies in the direction of `way`.
    private static func reach(of runs: [Run], from centre: CGPoint, along way: CGPoint) -> CGPoint {
        var best = runs[0].start, nearest = -CGFloat.infinity
        for run in runs {
            for step in 0...32 {
                let point = run.point(at: CGFloat(step) / 32)
                let length = hypot(point.x - centre.x, point.y - centre.y)
                guard length > 0 else { continue }
                let lined = ((point.x - centre.x) * way.x + (point.y - centre.y) * way.y) / length
                if lined > nearest { (best, nearest) = (point, lined) }
            }
        }
        return best
    }

    /// The loop with a stretch of it gone and two teeth across the gap, as
    /// the `d` of a path. Curves stay curves.
    private static func torn(_ runs: [Run], centre: CGPoint, size: CGFloat) -> String? {
        let lengths = lengths(runs)
        let total = lengths.reduce(0, +)
        guard total > 0 else { return nil }
        let way = CGPoint(x: cos(tearAngle), y: sin(tearAngle))
        let middle = furthest(of: runs, from: centre, along: way, lengths: lengths).distance
        let from = place(middle + total * tornShare / 2, lengths: lengths)
        let to = place(middle - total * tornShare / 2, lengths: lengths)
        var kept = [runs[from.run].between(from.t, 1)]
        var index = (from.run + 1) % runs.count
        while index != to.run {
            kept.append(runs[index])
            index = (index + 1) % runs.count
        }
        kept.append(runs[to.run].between(0, to.t))
        guard let first = kept.first?.start, let last = kept.last?.end else { return nil }
        let teeth = (1...3).map { step -> CGPoint in
            let t = CGFloat(step) / 4
            let across = CGPoint(x: last.x + (first.x - last.x) * t, y: last.y + (first.y - last.y) * t)
            let inward = CGPoint(x: centre.x - across.x, y: centre.y - across.y)
            let length = max(hypot(inward.x, inward.y), 1e-6)
            let depth = size * tearDepth * (step == 2 ? tearReturn : 1)
            return CGPoint(x: across.x + inward.x / length * depth, y: across.y + inward.y / length * depth)
        }
        var d = "M\(text(first))"
        for run in kept where hypot(run.end.x - run.start.x, run.end.y - run.start.y) > 1e-6 {
            d += run.isStraight ? " L\(text(run.end))" : " C\(text(run.control1)) \(text(run.control2)) \(text(run.end))"
        }
        for tooth in teeth { d += " L\(text(tooth))" }
        return d + " Z"
    }

    private static func number(_ value: CGFloat) -> String {
        let shown = (value * 100).rounded() / 100
        return shown == shown.rounded() ? String(Int(shown)) : String(format: "%.2f", Double(shown))
    }

    private static func text(_ point: CGPoint) -> String { "\(number(point.x)) \(number(point.y))" }

    // MARK: The SVG's text

    /// One shape's tag in the text.
    struct Tag {
        var range: Range<String.Index>
        var kept: String
        var name: String
        var attributes: String

        func asPath(_ d: String) -> String { #"<path\#(kept) d="\#(d)"/>"# }

        /// The same shape, solid in `ink` with no line.
        func asSolid(ink: String) -> String {
            let plain = attributes.replacingOccurrences(of: #"\s(fill|stroke)\s*=\s*"[^"]*""#, with: "", options: .regularExpression)
            return #"<\#(name)\#(plain) fill="\#(ink)" stroke="none"/>"#
        }
    }

    /// The tag of the shape read as `name`, with its own geometry taken off.
    static func tag(named name: String, in svg: String) -> Tag? {
        let pattern = #"<(path|ellipse|circle|rect|polygon)\b([^>]*?)(/>|>\s*</\1>|>)"#
        guard let tags = try? NSRegularExpression(pattern: pattern),
              let geometry = try? NSRegularExpression(pattern: #"\s(d|cx|cy|r|rx|ry|x|y|width|height|points)\s*=\s*"[^"]*""#),
              let ids = try? NSRegularExpression(pattern: #"\sid\s*=\s*"([^"]*)""#) else { return nil }
        for match in tags.matches(in: svg, range: NSRange(svg.startIndex..., in: svg)) {
            guard let whole = Range(match.range, in: svg), let kind = Range(match.range(at: 1), in: svg),
                  let inside = Range(match.range(at: 2), in: svg) else { continue }
            let attributes = String(svg[inside])
            let all = NSRange(attributes.startIndex..., in: attributes)
            guard let id = ids.firstMatch(in: attributes, range: all), let said = Range(id.range(at: 1), in: attributes),
                  SVGArtwork.readableID(String(attributes[said])) == name else { continue }
            return Tag(range: whole, kept: geometry.stringByReplacingMatches(in: attributes, range: all, withTemplate: ""),
                       name: String(svg[kind]), attributes: attributes)
        }
        return nil
    }
}
