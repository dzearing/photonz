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
    /// Under this many units across, a torn drawing is brought up to it.
    static let smallestReach: CGFloat = 18
    /// How many sizes are tried before settling.
    static let mostTries = 6
    /// How far an outer mark may step, in units, to even a drawing's span.
    static let stepsToEven: [CGFloat] = [0, 1, -1]
    /// How far a mark's whole run may stray from its length, as shares of it,
    /// and what a share of that is worth against a radian of its heading.
    static let shortestMark: CGFloat = 0.75
    static let longestMark: CGFloat = 1.5
    static let markLengthWeighs: CGFloat = 0.5
    /// The shortest run a tear leaves at either end of what it kept, in units.
    static let shortestRun: CGFloat = 1.5
    /// The air a mark keeps from the outline's line, in units, and how many
    /// units it may step out to find that.
    static let markClearance: CGFloat = 0.5
    static let mostSteps = 4
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

    /// `svg` with its biggest outline torn at the upper right and marks flying
    /// from the tear, or nil when it has no closed outline to tear.
    ///
    /// On the 24 grid the tear is worked out where it will land, on whole units
    /// (`Placing`), so an icon picture writes it in whole numbers and nothing
    /// after this has to round what was cut.
    public static func applied(to svg: String) -> String? {
        guard !svg.contains("transform"), case .success(let art) = SVGArtwork.parse(svg) else { return nil }
        let grid = IconKeylines.artboardSide
        let drawn = art.parts.filter { $0.name?.lowercased() != "tile" }
        guard let asDrawn = torn(svg, art, drawn, Placing()) else { return nil }
        guard drawn.count == art.parts.count, art.viewBox?.size == CGSize(width: grid, height: grid),
              let reached = points(of: asDrawn) else { return asDrawn }

        guard let body = biggest(of: drawn) else { return asDrawn }
        let box = SVGArtwork.shapeBounds(body.shape)
        let reach = max(reached.width, reached.height), live = IconKeylines.liveAreaSide
        let scale = reach > live ? live / reach : reach < smallestReach ? smallestReach / reach : 1
        let long = max(box.width, box.height)
        // A round outline takes an even number of units, so its middle is whole
        // as well as its ends: the sides of a circle 15 across sit on a half,
        // and go their own ways when rounded. Whole units can reach past what
        // that sum said, so each try is the next size down.
        var step: CGFloat = 1
        if case .ellipse = body.shape { step = 2 }
        var placed = asDrawn
        for fewer in 0..<mostTries {
            let units = max(((long * scale) / step).rounded() * step - CGFloat(fewer) * step, step)
            var best: (svg: String, odd: Int)?
            // A drawing an odd number of units across cannot sit in the middle
            // of 24, so the two outer marks may each step a unit to even it.
            for across in stepsToEven {
                for down in stepsToEven {
                    var placing = Placing(drawing: reached, body: box, scale: units / long, side: grid)
                    placing.markSteps = CGPoint(x: across, y: down)
                    guard let fitted = torn(svg, art, drawn, placing), let landed = points(of: fitted) else { return asDrawn }
                    placed = fitted
                    guard max(landed.width, landed.height) <= live + 1e-3 else { continue }
                    let odd = oddSpans(of: fitted)
                    if odd < best?.odd ?? .max { best = (fitted, odd) }
                }
            }
            if let best { return best.svg }
        }
        return placed
    }

    /// How many of a drawing's two spans come to an odd number of units, read
    /// from where it really lands: rounding away from the middle depends on
    /// where the drawing ends up, so a sum here would disagree with it.
    private static func oddSpans(of svg: String) -> Int {
        guard case .success(let art) = SVGArtwork.parse(svg) else { return 2 }
        let side = IconUnits.pictureSide, unit = side / IconKeylines.artboardSide
        let box = art.iconFrame(named: "", side: side, origin: .zero).children.reduce(CGRect.null) { $0.union($1.frame) }
        return [box.width, box.height].filter { Int(($0 / unit).rounded()) % 2 != 0 }.count
    }

    private static func biggest(of parts: [SVGArtwork.Part]) -> SVGArtwork.Part? {
        parts.max { area($0) < area($1) }
    }

    /// The box of the points in a drawing, which is what the live area holds.
    private static func points(of svg: String) -> CGRect? {
        guard case .success(let art) = SVGArtwork.parse(svg) else { return nil }
        let box = art.parts.reduce(CGRect.null) { $0.union(SVGArtwork.shapeBounds($1.shape)) }
        return box.isNull ? nil : box
    }

    /// `svg` torn as `placing` says.
    private static func torn(_ svg: String, _ art: SVGArtwork, _ drawn: [SVGArtwork.Part], _ placing: Placing) -> String? {
        guard let body = biggest(of: drawn), let name = body.name,
              let drawnRuns = runs(of: body.shape), let tag = tag(named: name, in: svg) else { return nil }
        let box = SVGArtwork.shapeBounds(body.shape)
        let size = (box.width + box.height) / 2 * placing.scale
        let centre = placing.placed(CGPoint(x: box.midX, y: box.midY))
        let runs = drawnRuns.map(placing.placed)
        guard size > 0, let outline = torn(runs, centre: centre, size: size, placing: placing) else { return nil }

        let weighted = art.parts.first { $0.stroke != nil && $0.strokeWidth > 0 }
        guard let ink = weighted?.stroke ?? drawn.last(where: { $0.fill != nil })?.fill else { return nil }
        let drawnWeight = weighted.map { $0.strokeWidth * placing.scale }
        let weight = placing.line(drawnWeight.map { min($0, size * lineShare) } ?? size * markWeight)
        let said = placing.number(weight / placing.scale)
        let clearance = (body.stroke == nil ? weight / 2 : weight) + markClearance
        let marks = (0..<markCount).map { index -> String in
            let turn = (CGFloat(index) - CGFloat(markCount - 1) / 2) * markSpread
            let angle = tearAngle + turn
            let way = CGPoint(x: cos(angle), y: sin(angle))
            let edge = reach(of: runs, from: centre, along: way)
            let run = placing.run(along: way, length: size * markLength)
            let start = placing.stepped(placing.point(CGPoint(x: edge.x + way.x * size * markGap, y: edge.y + way.y * size * markGap)),
                                        mark: index)
            let flying = placing.clear(start, run: run, along: way, of: outline.line, by: clearance)
            let end = CGPoint(x: flying.x + run.x, y: flying.y + run.y)
            return #"<path id="burst-\#(index + 1)" d="M\#(placing.text(flying)) L\#(placing.text(end))" fill="none" stroke="\#(ink)" "#
                + #"stroke-width="\#(said)" stroke-linecap="round"/>"#
        }
        var out = svg
        out.replaceSubrange(tag.range, with: tag.asPath(outline.d))
        if let drawnWeight, weight != drawnWeight { out = thinned(out, to: said) }
        let small = (art.viewBox?.width ?? max(art.bounds.width, art.bounds.height)) * smallestOutline
        for part in drawn where part != body && part.fill == nil && part.stroke != nil && isClosed(part.shape) {
            let own = SVGArtwork.shapeBounds(part.shape)
            guard max(own.width, own.height) < small, let name = part.name, let found = Self.tag(named: name, in: out) else { continue }
            out.replaceSubrange(found.range, with: found.asSolid(ink: ink))
        }
        guard let close = out.range(of: "</svg>", options: .backwards) else { return nil }
        out.insert(contentsOf: marks.joined() , at: close.lowerBound)
        return placing.wrapping(out)
    }

    private static func isClosed(_ shape: SVGArtwork.Shape) -> Bool {
        if case .path(let outline) = shape { return outline.closed }
        return true
    }

    /// Every line in `svg` at `weight`.
    private static func thinned(_ svg: String, to weight: String) -> String {
        svg.replacingOccurrences(of: #"stroke-width\s*=\s*"[^"]*""#, with: #"stroke-width="\#(weight)""#,
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

        /// The run with its start on `point`, its handle going with it so the
        /// curve keeps the way it leaves.
        func starting(at point: CGPoint) -> Run {
            Run(start: point, control1: CGPoint(x: control1.x + point.x - start.x, y: control1.y + point.y - start.y),
                control2: control2, end: end)
        }

        /// The run with its end on `point`, its handle going with it.
        func ending(at point: CGPoint) -> Run {
            Run(start: start, control1: control1,
                control2: CGPoint(x: control2.x + point.x - end.x, y: control2.y + point.y - end.y), end: point)
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
    /// the `d` of a path, and the line that draws, in points along it. Curves
    /// stay curves.
    private static func torn(_ runs: [Run], centre: CGPoint, size: CGFloat,
                             placing: Placing) -> (d: String, line: [CGPoint])? {
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
        if placing.whole {
            // Rounded, what is left of a run cut near its end is a stub of curve
            // dragged a long way for its length, and reads as a lump.
            while kept.count > 2, kept[0].end.distance(to: placing.point(kept[0].start)) < shortestRun { kept.removeFirst() }
            while kept.count > 2, let end = kept.last, end.start.distance(to: placing.point(end.end)) < shortestRun { kept.removeLast() }
        }
        guard let start = kept.first?.start, let stop = kept.last?.end else { return nil }
        let first = placing.point(start), last = placing.point(stop)
        kept[0] = kept[0].starting(at: first)
        kept[kept.count - 1] = kept[kept.count - 1].ending(at: last)
        let teeth = (1...3).map { step -> CGPoint in
            let t = CGFloat(step) / 4
            let across = CGPoint(x: last.x + (first.x - last.x) * t, y: last.y + (first.y - last.y) * t)
            let inward = CGPoint(x: centre.x - across.x, y: centre.y - across.y)
            let length = max(hypot(inward.x, inward.y), 1e-6)
            let depth = size * tearDepth * (step == 2 ? tearReturn : 1)
            return placing.point(CGPoint(x: across.x + inward.x / length * depth, y: across.y + inward.y / length * depth))
        }
        var d = "M\(placing.text(first))"
        for run in kept where hypot(run.end.x - run.start.x, run.end.y - run.start.y) > 1e-6 {
            d += run.isStraight ? " L\(placing.text(run.end))"
                : " C\(placing.text(run.control1)) \(placing.text(run.control2)) \(placing.text(run.end))"
        }
        let notched = placing.notched(teeth, from: last, to: first, centre: centre)
        for tooth in notched { d += " L\(placing.text(tooth))" }
        let curve = kept.flatMap { run in (0...16).map { run.point(at: CGFloat($0) / 16) } }
        let across = zip([last] + notched, notched + [first]).flatMap { from, to in
            (0...8).map { step -> CGPoint in
                let t = CGFloat(step) / 8
                return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            }
        }
        return (d + " Z", curve + across)
    }

    // MARK: Where it lands

    /// What a tear is worked out in. Left alone it is the drawing's own
    /// numbers. On the 24 grid it is where the drawing will land: the scale
    /// that gets it and its marks into the live area, with every point the tear
    /// adds on a whole unit. The outline the model drew and everything else in
    /// the file go there through one group, so what comes back holds still in
    /// the live area and nothing is fitted to it afterwards: a fit is a
    /// fraction, and rounding after one is what squashed small parts and took a
    /// line from 1.5 to 1 (2026-11-06).
    ///
    /// The outline's own box lands on whole units too. A circle drawn on a half
    /// keeps its four ends where they belong that way, and stays a circle;
    /// rounded one point at a time it went lopsided.
    struct Placing {
        var scale: CGFloat = 1
        var offset = CGPoint.zero
        var whole = false
        /// How far the marks at the right go right and the ones at the top go up.
        var markSteps = CGPoint.zero

        init() {}

        /// `drawing` centred on a square of `side` at `scale`, as near as the
        /// corner of `body` landing on a whole unit lets it.
        init(drawing: CGRect, body: CGRect, scale: CGFloat, side: CGFloat) {
            self.scale = (scale * 1e5).rounded() / 1e5
            func shift(_ middle: CGFloat, _ corner: CGFloat) -> CGFloat {
                let centred = (side / 2 - middle * self.scale).rounded()
                let landed = corner * self.scale + centred
                return ((centred - (landed - landed.rounded())) * 1e5).rounded() / 1e5
            }
            offset = CGPoint(x: shift(drawing.midX, body.minX), y: shift(drawing.midY, body.minY))
            whole = true
        }

        func placed(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * scale + offset.x, y: point.y * scale + offset.y)
        }

        func placed(_ run: Run) -> Run {
            Run(start: placed(run.start), control1: placed(run.control1), control2: placed(run.control2), end: placed(run.end))
        }

        /// A point the tear adds, on a whole unit where there are units.
        func point(_ point: CGPoint) -> CGPoint {
            whole ? CGPoint(x: point.x.rounded(), y: point.y.rounded()) : point
        }

        /// A mark's start with its share of `markSteps`. The one in the middle
        /// can reach as far as either of the others, so it goes with both.
        func stepped(_ start: CGPoint, mark index: Int) -> CGPoint {
            CGPoint(x: start.x + (index > 0 ? markSteps.x : 0),
                    y: start.y - (index < markCount - 1 ? markSteps.y : 0))
        }

        /// A line weight. Where there are units it is a half unit at the finest,
        /// as `IconGridLanding` lands one: a weight is not a place, and a whole
        /// one is too heavy on an object brought down to fit its marks.
        func line(_ weight: CGFloat) -> CGFloat {
            whole ? max(1, (weight * 2).rounded() / 2) : weight
        }

        /// A stroke `length` long heading along `way`. Where there are units
        /// it is the whole number run nearest that heading, of about that
        /// length: rounding each end alone turns a mark to whatever the two
        /// roundings happen to give.
        func run(along way: CGPoint, length: CGFloat) -> CGPoint {
            guard whole else { return CGPoint(x: way.x * length, y: way.y * length) }
            let reach = Int((length * longestMark).rounded(.up))
            let heading = atan2(way.y, way.x)
            var best = (run: CGPoint(x: way.x.rounded(), y: way.y.rounded()), off: CGFloat.infinity)
            for x in -reach...reach {
                for y in -reach...reach {
                    let run = CGPoint(x: x, y: y), long = hypot(run.x, run.y)
                    guard long >= min(length * shortestMark, 2), long <= length * longestMark else { continue }
                    let turned = abs(atan2(sin(atan2(run.y, run.x) - heading), cos(atan2(run.y, run.x) - heading)))
                    let off = turned + abs(long - length) / length * markLengthWeighs
                    if off < best.off { best = (run, off) }
                }
            }
            return best.run
        }

        /// Where a mark starting at `start` stands clear of `line` by `clearance`,
        /// stepping out along `way`. Its gap is counted from where the outline
        /// would have been: beside the end of a tear, rounded, it can land on
        /// what is still there.
        func clear(_ start: CGPoint, run: CGPoint, along way: CGPoint, of line: [CGPoint], by clearance: CGFloat) -> CGPoint {
            guard whole else { return start }
            let step = CGPoint(x: way.x.rounded(), y: way.y.rounded())
            var flying = start
            for _ in 0..<mostSteps {
                let nearest = (0...8).map { index -> CGFloat in
                    let t = CGFloat(index) / 8
                    let along = CGPoint(x: flying.x + run.x * t, y: flying.y + run.y * t)
                    return line.map { hypot($0.x - along.x, $0.y - along.y) }.min() ?? .infinity
                }.min() ?? .infinity
                if nearest >= clearance { break }
                flying = CGPoint(x: flying.x + step.x, y: flying.y + step.y)
            }
            return flying
        }

        /// `teeth` as they cross from `from` to `to`, with the middle one still
        /// standing proud of the two beside it: rounded, it can land level with
        /// them and the tear reads as one straight bite.
        func notched(_ teeth: [CGPoint], from: CGPoint, to: CGPoint, centre: CGPoint) -> [CGPoint] {
            guard whole, teeth.count == 3 else { return teeth }
            let across = CGPoint(x: to.x - from.x, y: to.y - from.y)
            let long = max(hypot(across.x, across.y), 1e-6)
            var inward = CGPoint(x: -across.y / long, y: across.x / long)
            if (centre.x - from.x) * inward.x + (centre.y - from.y) * inward.y < 0 {
                inward = CGPoint(x: -inward.x, y: -inward.y)
            }
            func depth(_ point: CGPoint) -> CGFloat { (point.x - from.x) * inward.x + (point.y - from.y) * inward.y }
            func moved(_ point: CGPoint, inwards: Bool) -> CGPoint {
                let sign: CGFloat = inwards ? 1 : -1
                return abs(inward.x) > abs(inward.y)
                    ? CGPoint(x: point.x + sign * (inward.x < 0 ? -1 : 1), y: point.y)
                    : CGPoint(x: point.x, y: point.y + sign * (inward.y < 0 ? -1 : 1))
            }
            var out = teeth
            for index in [0, 2] {
                while depth(out[index]) < 1 { out[index] = moved(out[index], inwards: true) }
            }
            // A whole unit back: any less and it rounds to a staircase of right
            // angles, which reads as a step cut in it and not as a tear.
            while depth(out[1]) > min(depth(out[0]), depth(out[2])) - 1 { out[1] = moved(out[1], inwards: false) }
            return out
        }

        /// A number as `svg` says it: in the file's own numbers, so a point on
        /// a whole unit needs the places to come back to one.
        func number(_ value: CGFloat) -> String {
            let places: CGFloat = whole ? 1e5 : 100
            let shown = (value * places).rounded() / places
            if shown == shown.rounded() { return String(Int(shown)) }
            return whole ? String(format: "%.5f", Double(shown)) : String(format: "%.2f", Double(shown))
        }

        /// A placed point as the file's own numbers, inside the group.
        func text(_ point: CGPoint) -> String {
            "\(number((point.x - offset.x) / scale)) \(number((point.y - offset.y) / scale))"
        }

        /// `svg` with everything in it brought to where this puts it.
        func wrapping(_ svg: String) -> String {
            guard scale != 1 || offset != .zero, let open = svg.range(of: "<svg"),
                  let opened = svg.range(of: ">", range: open.upperBound..<svg.endIndex),
                  let close = svg.range(of: "</svg>", options: .backwards) else { return svg }
            var out = svg
            out.insert(contentsOf: "</g>", at: close.lowerBound)
            out.insert(contentsOf: #"<g transform="translate(\#(offset.x) \#(offset.y)) scale(\#(scale))">"#,
                       at: opened.upperBound)
            return out
        }
    }

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

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}
