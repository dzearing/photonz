import CoreGraphics
import Foundation

// The drawing surface the illustrator works on (`docs/design/ask.md`,
// "Drawing an illustration"): named shapes in groups, flat or gradient ink,
// clipped to the picture's frame in the geometry itself (a badge's circle, a
// poster's rounded box) so the SVG it writes needs no masks and nothing pokes
// past the picture by accident.

/// Deterministic randomness, so one brief always draws one picture.
struct IllustrationRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    /// SplitMix64.
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 up to 1.
    mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(1 << 53) }

    mutating func range(_ low: CGFloat, _ high: CGFloat) -> CGFloat { low + (high - low) * unit() }

    /// -1 to 1.
    mutating func signed() -> CGFloat { unit() * 2 - 1 }
}

/// How a shape is filled.
public enum IllustrationInk: Hashable, Sendable {
    case flat(String)
    /// A ramp at `angle` (CSS degrees, 180 runs top to bottom) across the shape's box.
    case linear([GradientStop], angle: Double)
    /// A ramp from the middle of the shape's box out to its corners.
    case radial([GradientStop])

    /// The one colour that stands for it where only one can be drawn.
    public var hex: String {
        switch self {
        case .flat(let hex): return hex
        case .linear(let stops, _), .radial(let stops):
            return String((stops.first?.hex ?? "#000000").prefix(7))
        }
    }

    /// The app's own paint for it.
    public var paint: Paint {
        switch self {
        case .flat(let hex): return Paint(hex: hex)
        case .linear(let stops, let angle): return Paint(hex: hex, kind: .linear, stops: stops, angle: angle)
        case .radial(let stops): return Paint(hex: hex, kind: .radial, stops: stops)
        }
    }
}

/// One run of points, a loop or a line.
public struct IllustrationPath: Hashable, Sendable {
    public var points: [CGPoint]
    public var closed: Bool
    /// Drawn as a curve through the points rather than straight between them.
    public var smooth: Bool
    /// Points a smooth path turns sharply at (ear tips, a nose).
    public var corners: Set<Int>

    public init(_ points: [CGPoint], closed: Bool = true, smooth: Bool = false, corners: Set<Int> = []) {
        self.points = points
        self.closed = closed
        self.smooth = smooth
        self.corners = corners
    }

    /// Straight segments that follow the curve, for clipping and measuring.
    public func flattened(steps: Int = 8) -> [CGPoint] {
        guard smooth, points.count >= 3 else { return points }
        var out: [CGPoint] = []
        let count = points.count
        let segments = closed ? count : count - 1
        for index in 0..<segments {
            let (a, c1, c2, b) = bezier(index)
            for step in 0..<steps {
                let t = CGFloat(step) / CGFloat(steps)
                let u = 1 - t
                out.append(CGPoint(
                    x: u * u * u * a.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * b.x,
                    y: u * u * u * a.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * b.y))
            }
        }
        if !closed, let last = points.last { out.append(last) }
        return out
    }

    /// The cubic from point `index` to the next: a Catmull-Rom curve, with
    /// no handle at a corner.
    func bezier(_ index: Int) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
        let count = points.count
        func at(_ i: Int) -> CGPoint {
            if closed { return points[((i % count) + count) % count] }
            return points[min(max(i, 0), count - 1)]
        }
        let a = at(index), b = at(index + 1)
        let before = at(index - 1), after = at(index + 2)
        let tension: CGFloat = 1.0 / 6.0
        let next = closed ? (index + 1) % count : index + 1
        let c1 = corners.contains(index) ? a
            : CGPoint(x: a.x + (b.x - before.x) * tension, y: a.y + (b.y - before.y) * tension)
        let c2 = corners.contains(next) ? b
            : CGPoint(x: b.x - (after.x - a.x) * tension, y: b.y - (after.y - a.y) * tension)
        return (a, c1, c2, b)
    }

    /// SVG path data.
    func data() -> String {
        guard let first = points.first else { return "" }
        var d = "M\(svgNumber(first.x)) \(svgNumber(first.y))"
        if smooth, points.count >= 3 {
            let segments = closed ? points.count : points.count - 1
            for index in 0..<segments {
                let (_, c1, c2, b) = bezier(index)
                d += "C\(svgNumber(c1.x)) \(svgNumber(c1.y)) \(svgNumber(c2.x)) \(svgNumber(c2.y)) \(svgNumber(b.x)) \(svgNumber(b.y))"
            }
        } else {
            for point in points.dropFirst() { d += "L\(svgNumber(point.x)) \(svgNumber(point.y))" }
        }
        if closed { d += "Z" }
        return d
    }

    var bounds: CGRect {
        let flat = flattened(steps: 4)
        guard let first = flat.first else { return .null }
        return flat.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }
}

/// What one shape is.
public enum IllustrationGeometry: Hashable, Sendable {
    case ellipse(CGRect)
    case rect(CGRect, radius: CGFloat)
    case path([IllustrationPath])
}

/// One named thing drawn.
public struct IllustrationShape: Hashable, Sendable {
    public var name: String
    public var geometry: IllustrationGeometry
    public var fill: IllustrationInk?
    public var stroke: String?
    public var strokeWidth: CGFloat
    public var opacity: Double
    /// Rings that overlap cut holes in each other rather than joining.
    public var evenOdd = false

    public init(_ name: String, _ geometry: IllustrationGeometry, fill: IllustrationInk? = nil,
                stroke: String? = nil, strokeWidth: CGFloat = 0, opacity: Double = 1) {
        self.name = name
        self.geometry = geometry
        self.fill = fill
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.opacity = opacity
    }

    public static func path(_ name: String, _ path: IllustrationPath, fill: IllustrationInk? = nil,
                            stroke: String? = nil, strokeWidth: CGFloat = 0, opacity: Double = 1) -> IllustrationShape {
        IllustrationShape(name, .path([path]), fill: fill, stroke: stroke, strokeWidth: strokeWidth, opacity: opacity)
    }

    public var bounds: CGRect {
        switch geometry {
        case .ellipse(let box), .rect(let box, _): return box
        case .path(let paths): return paths.reduce(CGRect.null) { $0.union($1.bounds) }
        }
    }
}

/// A shape or a named group of them, bottom first.
public indirect enum IllustrationNode: Hashable, Sendable {
    case shape(IllustrationShape)
    case group(String, [IllustrationNode])

    public var name: String {
        switch self {
        case .shape(let shape): return shape.name
        case .group(let name, _): return name
        }
    }

    /// Every shape inside, bottom first.
    public var shapes: [IllustrationShape] {
        switch self {
        case .shape(let shape): return [shape]
        case .group(_, let children): return children.flatMap(\.shapes)
        }
    }
}

/// The picture's edge: everything is cut to it.
public enum IllustrationFrame: Hashable, Sendable {
    case box(CGRect, radius: CGFloat)
    case circle(center: CGPoint, radius: CGFloat)

    public var bounds: CGRect {
        switch self {
        case .box(let box, _): return box
        case .circle(let c, let r): return CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        }
    }

    /// The edge as a convex polygon, clockwise on screen.
    var polygon: [CGPoint] {
        switch self {
        case .circle(let c, let r):
            return (0..<96).map { i in
                let a = CGFloat(i) / 96 * 2 * .pi
                return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            }
        case .box(let box, let radius):
            let r = min(radius, box.width / 2, box.height / 2)
            guard r > 0.5 else {
                return [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                        CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
            }
            var out: [CGPoint] = []
            let corners: [(CGPoint, CGFloat)] = [
                (CGPoint(x: box.maxX - r, y: box.minY + r), -.pi / 2),
                (CGPoint(x: box.maxX - r, y: box.maxY - r), 0),
                (CGPoint(x: box.minX + r, y: box.maxY - r), .pi / 2),
                (CGPoint(x: box.minX + r, y: box.minY + r), .pi),
            ]
            for (centre, start) in corners {
                for step in 0...8 {
                    let a = start + CGFloat(step) / 8 * (.pi / 2)
                    out.append(CGPoint(x: centre.x + r * cos(a), y: centre.y + r * sin(a)))
                }
            }
            return out
        }
    }

    func contains(_ p: CGPoint, inset: CGFloat = 0) -> Bool {
        switch self {
        case .circle(let c, let r): return hypot(p.x - c.x, p.y - c.y) <= r - inset
        case .box:
            return IllustrationClip.inside(p, polygon, inset: inset)
        }
    }

    /// The frame as a shape.
    func shape(named name: String, fill: IllustrationInk?, stroke: String? = nil, strokeWidth: CGFloat = 0) -> IllustrationShape {
        switch self {
        case .circle(let c, let r):
            return IllustrationShape(name, .ellipse(CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                                     fill: fill, stroke: stroke, strokeWidth: strokeWidth)
        case .box(let box, let radius):
            return IllustrationShape(name, .rect(box, radius: radius), fill: fill, stroke: stroke, strokeWidth: strokeWidth)
        }
    }
}

/// Cutting shapes to the frame.
enum IllustrationClip {

    /// Whether `p` is inside the convex polygon (either winding), at least
    /// `inset` in from every edge.
    static func inside(_ p: CGPoint, _ polygon: [CGPoint], inset: CGFloat = 0) -> Bool {
        let sign = orientation(polygon)
        for index in polygon.indices {
            let a = polygon[index], b = polygon[(index + 1) % polygon.count]
            let edge = hypot(b.x - a.x, b.y - a.y)
            guard edge > 0 else { continue }
            let cross = ((b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)) * sign / edge
            if cross < inset { return false }
        }
        return true
    }

    static func orientation(_ polygon: [CGPoint]) -> CGFloat {
        var area: CGFloat = 0
        for index in polygon.indices {
            let a = polygon[index], b = polygon[(index + 1) % polygon.count]
            area += a.x * b.y - b.x * a.y
        }
        return area >= 0 ? 1 : -1
    }

    /// The pieces of a segment inside any polygon (even-odd): where it
    /// crosses the edges, sorted along it, taken in pairs.
    static func inside(segment: (CGPoint, CGPoint), of polygon: [CGPoint]) -> [(CGPoint, CGPoint)] {
        let (p, q) = segment
        var hits: [CGFloat] = []
        for index in polygon.indices {
            let a = polygon[index], b = polygon[(index + 1) % polygon.count]
            let r = CGPoint(x: q.x - p.x, y: q.y - p.y), s = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let denominator = r.x * s.y - r.y * s.x
            guard abs(denominator) > 1e-9 else { continue }
            let t = ((a.x - p.x) * s.y - (a.y - p.y) * s.x) / denominator
            let u = ((a.x - p.x) * r.y - (a.y - p.y) * r.x) / denominator
            if t >= 0, t <= 1, u >= 0, u < 1 { hits.append(t) }
        }
        hits.sort()
        var pieces: [(CGPoint, CGPoint)] = []
        var index = 0
        while index + 1 < hits.count {
            let t0 = hits[index], t1 = hits[index + 1]
            pieces.append((CGPoint(x: p.x + (q.x - p.x) * t0, y: p.y + (q.y - p.y) * t0),
                           CGPoint(x: p.x + (q.x - p.x) * t1, y: p.y + (q.y - p.y) * t1)))
            index += 2
        }
        return pieces
    }

    /// Sutherland–Hodgman: the subject polygon cut to the convex clip polygon.
    static func polygon(_ subject: [CGPoint], to clip: [CGPoint]) -> [CGPoint] {
        var output = subject
        let sign = orientation(clip)
        for index in clip.indices {
            guard !output.isEmpty else { break }
            let a = clip[index], b = clip[(index + 1) % clip.count]
            func side(_ p: CGPoint) -> CGFloat { ((b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)) * sign }
            let input = output
            output = []
            for j in input.indices {
                let current = input[j], previous = input[(j + input.count - 1) % input.count]
                let sc = side(current), sp = side(previous)
                if sc >= 0 {
                    if sp < 0 { output.append(cross(previous, current, sp, sc)) }
                    output.append(current)
                } else if sp >= 0 {
                    output.append(cross(previous, current, sp, sc))
                }
            }
        }
        return output
    }

    private static func cross(_ p: CGPoint, _ q: CGPoint, _ sp: CGFloat, _ sq: CGFloat) -> CGPoint {
        let t = sp / (sp - sq)
        return CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)
    }

    /// An open line cut to the convex polygon: the runs of it inside.
    static func line(_ points: [CGPoint], to clip: [CGPoint]) -> [[CGPoint]] {
        var runs: [[CGPoint]] = []
        var current: [CGPoint] = []
        let sign = orientation(clip)
        for index in 0..<max(0, points.count - 1) {
            let p = points[index], q = points[index + 1]
            var t0: CGFloat = 0, t1: CGFloat = 1
            var visible = true
            for e in clip.indices {
                let a = clip[e], b = clip[(e + 1) % clip.count]
                func side(_ s: CGPoint) -> CGFloat { ((b.x - a.x) * (s.y - a.y) - (b.y - a.y) * (s.x - a.x)) * sign }
                let sp = side(p), sq = side(q)
                if sp < 0 && sq < 0 { visible = false; break }
                if sp < 0 { t0 = max(t0, sp / (sp - sq)) } else if sq < 0 { t1 = min(t1, sp / (sp - sq)) }
            }
            if !visible || t0 >= t1 {
                if current.count >= 2 { runs.append(current) }
                current = []
                continue
            }
            let start = CGPoint(x: p.x + (q.x - p.x) * t0, y: p.y + (q.y - p.y) * t0)
            let end = CGPoint(x: p.x + (q.x - p.x) * t1, y: p.y + (q.y - p.y) * t1)
            if current.isEmpty || t0 > 0 {
                if current.count >= 2 { runs.append(current) }
                current = [start]
            }
            current.append(end)
            if t1 < 1 {
                runs.append(current)
                current = []
            }
        }
        if current.count >= 2 { runs.append(current) }
        return runs
    }

    /// The shape cut to the frame: untouched when wholly inside it, gone when
    /// wholly outside.
    static func shape(_ shape: IllustrationShape, to frame: IllustrationFrame) -> IllustrationShape? {
        let clip = frame.polygon
        let box = shape.bounds
        guard !box.isNull, box.intersects(frame.bounds.insetBy(dx: -1, dy: -1)) else { return nil }
        let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                       CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
        if corners.allSatisfy({ inside($0, clip, inset: -0.5) }) { return shape }
        var cut = shape
        switch shape.geometry {
        case .ellipse(let rect):
            let ring = (0..<72).map { i -> CGPoint in
                let a = CGFloat(i) / 72 * 2 * .pi
                return CGPoint(x: rect.midX + rect.width / 2 * cos(a), y: rect.midY + rect.height / 2 * sin(a))
            }
            let kept = polygon(ring, to: clip)
            guard kept.count >= 3 else { return nil }
            cut.geometry = .path([IllustrationPath(kept)])
        case .rect(let rect, _):
            if case .box(let edge, let radius) = frame, rect.insetBy(dx: -1, dy: -1).contains(edge) {
                cut.geometry = .rect(edge, radius: radius)
                return cut
            }
            let ring = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                        CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
            let kept = polygon(ring, to: clip)
            guard kept.count >= 3 else { return nil }
            cut.geometry = .path([IllustrationPath(kept)])
        case .path(let paths):
            var kept: [IllustrationPath] = []
            for path in paths {
                let flat = path.flattened()
                if path.closed && shape.fill != nil {
                    let ring = polygon(flat, to: clip)
                    if ring.count >= 3 { kept.append(IllustrationPath(ring)) }
                } else {
                    for run in line(path.closed ? flat + [flat[0]] : flat, to: clip) {
                        kept.append(IllustrationPath(run, closed: false))
                    }
                }
            }
            guard !kept.isEmpty else { return nil }
            cut.geometry = .path(kept)
        }
        return cut
    }
}

/// Two decimals at most, no trailing zeros: SVG numbers people can read.
func svgNumber(_ value: CGFloat) -> String {
    let rounded = (value * 10).rounded() / 10
    if rounded == rounded.rounded() { return String(Int(rounded)) }
    return String(format: "%.1f", Double(rounded))
}

/// A finished illustration, ready to write out or turn into layers.
public struct IllustrationScene: Hashable, Sendable {
    public var size: CGSize
    public var nodes: [IllustrationNode]

    public init(size: CGSize, nodes: [IllustrationNode]) {
        self.size = size
        self.nodes = nodes
    }

    public var shapes: [IllustrationShape] { nodes.flatMap(\.shapes) }

    /// Every shape cut to `frame`; a group left empty goes.
    public func clipped(to frame: IllustrationFrame) -> IllustrationScene {
        func cut(_ node: IllustrationNode) -> IllustrationNode? {
            switch node {
            case .shape(let shape): return IllustrationClip.shape(shape, to: frame).map { .shape($0) }
            case .group(let name, let children):
                let kept = children.compactMap(cut)
                return kept.isEmpty ? nil : .group(name, kept)
            }
        }
        return IllustrationScene(size: size, nodes: nodes.compactMap(cut))
    }

    /// The scene as one clean SVG: a group per part of the picture, an id on
    /// every shape naming it, gradients in defs.
    public func svg() -> String {
        var defs: [String] = []
        var body: [String] = []
        var used: [String: Int] = [:]
        func id(_ name: String) -> String {
            let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
                .split(separator: "-").joined(separator: "-")
            let base = slug.isEmpty ? "part" : slug
            let count = (used[base] ?? 0) + 1
            used[base] = count
            return count == 1 ? base : "\(base)-\(count)"
        }
        func ink(_ ink: IllustrationInk) -> String {
            switch ink {
            case .flat(let hex): return hex
            case .linear(let stops, let angle):
                let gid = "gradient-\(defs.count + 1)"
                let radians = angle * .pi / 180
                let dx = sin(radians), dy = -cos(radians)
                let x1 = 0.5 - dx / 2, y1 = 0.5 - dy / 2, x2 = 0.5 + dx / 2, y2 = 0.5 + dy / 2
                defs.append("<linearGradient id=\"\(gid)\" x1=\"\(svgNumber(CGFloat(x1)))\" y1=\"\(svgNumber(CGFloat(y1)))\" x2=\"\(svgNumber(CGFloat(x2)))\" y2=\"\(svgNumber(CGFloat(y2)))\">\(stopsSVG(stops))</linearGradient>")
                return "url(#\(gid))"
            case .radial(let stops):
                let gid = "gradient-\(defs.count + 1)"
                defs.append("<radialGradient id=\"\(gid)\" cx=\"0.5\" cy=\"0.5\" r=\"0.71\">\(stopsSVG(stops))</radialGradient>")
                return "url(#\(gid))"
            }
        }
        func stopsSVG(_ stops: [GradientStop]) -> String {
            stops.sorted { $0.position < $1.position }.map { stop in
                let colour = String(stop.hex.prefix(7))
                var alpha = ""
                if stop.hex.count == 9, let value = UInt8(stop.hex.suffix(2), radix: 16) {
                    alpha = " stop-opacity=\"\(String(format: "%.2f", Double(value) / 255))\""
                }
                return "<stop offset=\"\(svgNumber(CGFloat(stop.position * 100)))%\" stop-color=\"\(colour)\"\(alpha)/>"
            }.joined()
        }
        func write(_ node: IllustrationNode, depth: Int) {
            let pad = String(repeating: "  ", count: depth)
            switch node {
            case .group(let name, let children):
                body.append("\(pad)<g id=\"\(id(name))\">")
                for child in children { write(child, depth: depth + 1) }
                body.append("\(pad)</g>")
            case .shape(let shape):
                var attributes = "id=\"\(id(shape.name))\""
                attributes += " fill=\"\(shape.fill.map(ink) ?? "none")\""
                if let stroke = shape.stroke, shape.strokeWidth > 0 {
                    attributes += " stroke=\"\(stroke)\" stroke-width=\"\(svgNumber(shape.strokeWidth))\" stroke-linecap=\"round\" stroke-linejoin=\"round\""
                }
                if shape.opacity < 1 { attributes += " opacity=\"\(String(format: "%.2f", shape.opacity))\"" }
                switch shape.geometry {
                case .ellipse(let r):
                    if abs(r.width - r.height) < 0.01 {
                        body.append("\(pad)<circle \(attributes) cx=\"\(svgNumber(r.midX))\" cy=\"\(svgNumber(r.midY))\" r=\"\(svgNumber(r.width / 2))\"/>")
                    } else {
                        body.append("\(pad)<ellipse \(attributes) cx=\"\(svgNumber(r.midX))\" cy=\"\(svgNumber(r.midY))\" rx=\"\(svgNumber(r.width / 2))\" ry=\"\(svgNumber(r.height / 2))\"/>")
                    }
                case .rect(let r, let radius):
                    let corner = radius > 0 ? " rx=\"\(svgNumber(radius))\"" : ""
                    body.append("\(pad)<rect \(attributes) x=\"\(svgNumber(r.minX))\" y=\"\(svgNumber(r.minY))\" width=\"\(svgNumber(r.width))\" height=\"\(svgNumber(r.height))\"\(corner)/>")
                case .path(let paths):
                    let d = paths.map { $0.data() }.joined()
                    let rule = shape.evenOdd && shape.fill != nil ? " fill-rule=\"evenodd\"" : ""
                    body.append("\(pad)<path \(attributes)\(rule) d=\"\(d)\"/>")
                }
            }
        }
        for node in nodes { write(node, depth: 1) }
        var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(svgNumber(size.width)) \(svgNumber(size.height))\" width=\"\(svgNumber(size.width))\" height=\"\(svgNumber(size.height))\">\n"
        if !defs.isEmpty { out += "  <defs>\n" + defs.map { "    " + $0 }.joined(separator: "\n") + "\n  </defs>\n" }
        out += body.joined(separator: "\n") + "\n</svg>\n"
        return out
    }
}
