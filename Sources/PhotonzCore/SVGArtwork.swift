import CoreGraphics
import Foundation

// A drawing written as SVG, read into the shapes Photonz draws with
// (`docs/design/ask.md`, "Drawing a thing"): every circle and ellipse an oval
// layer, every box a rectangle, everything else a Pen path with its curves and
// holes kept. Ask's drawings come in through this, from the built-in drawing
// set or from an SVG the model wrote, so each part is a layer a person can
// pick, recolour and reshape, never a picture.
//
// It reads the part of SVG drawings are made of: path, circle, ellipse, rect,
// line, polyline, polygon and g, with fill, stroke, stroke-width, opacity,
// fill-rule, transform, display and a style attribute saying any of those. A
// gradient paints with its first colour. Text, images, filters, masks and
// clips are left out.

/// Why an SVG could not be read as a drawing, in one plain sentence.
public struct SVGArtworkError: Error, Hashable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

/// An SVG read into parts, in the SVG's own units.
public struct SVGArtwork: Hashable, Sendable {

    /// A path's outline: rings of anchors, each ring a loop or a run, with
    /// points in SVG units and handles as offsets from them.
    public struct Outline: Hashable, Sendable {
        public var rings: [[PathAnchor]]
        public var closed: Bool
        public var evenOdd: Bool
    }

    public enum Shape: Hashable, Sendable {
        case ellipse(CGRect)
        case rect(CGRect, radius: CGFloat)
        case path(Outline)
    }

    /// One thing drawn, bottom first.
    public struct Part: Hashable, Sendable {
        /// From its id or its group's, made readable; nil when it has none.
        public var name: String?
        public var shape: Shape
        /// "#RRGGBB", or nil for no fill.
        public var fill: String?
        public var stroke: String?
        public var strokeWidth: CGFloat
        public var opacity: Double
    }

    public let viewBox: CGRect?
    public private(set) var parts: [Part]

    /// The same drawing with its parts named, bottom first. A name list
    /// shorter than the parts leaves the rest as they were.
    public func named(_ names: [String]) -> SVGArtwork {
        var copy = self
        for (index, name) in names.enumerated() where index < copy.parts.count && !name.isEmpty {
            copy.parts[index].name = name
        }
        return copy
    }

    // MARK: Reading

    public static func parse(_ text: String) -> Result<SVGArtwork, SVGArtworkError> {
        guard let start = text.range(of: "<svg") else {
            return .failure(SVGArtworkError("That is not an SVG: it has no <svg> element."))
        }
        let body = String(text[start.lowerBound...])
        guard let root = SVGTree.parse(body) else {
            return .failure(SVGArtworkError("That SVG could not be read: its XML is broken."))
        }
        var reader = SVGReader(root: root)
        reader.read()
        guard !reader.parts.isEmpty else {
            return .failure(SVGArtworkError("That SVG draws nothing Photonz can draw: no paths or shapes."))
        }
        return .success(SVGArtwork(viewBox: reader.viewBox, parts: reader.parts))
    }

    // MARK: Size

    /// The box the drawing covers, lines included, in SVG units.
    public var bounds: CGRect {
        parts.reduce(CGRect.null) { box, part in
            var own = Self.shapeBounds(part.shape)
            if part.stroke != nil, part.strokeWidth > 0 {
                own = own.insetBy(dx: -part.strokeWidth / 2, dy: -part.strokeWidth / 2)
            }
            return box.union(own)
        }
    }

    static func shapeBounds(_ shape: Shape) -> CGRect {
        switch shape {
        case .ellipse(let box), .rect(let box, _): return box
        case .path(let outline):
            let anchors = outline.rings.flatMap { $0 }
            let content = PathContent(anchors: anchors, isClosed: outline.closed,
                                      ringStarts: ringStarts(outline.rings))
            return content.bounds
        }
    }

    static func ringStarts(_ rings: [[PathAnchor]]) -> [Int] {
        var starts: [Int] = []
        var count = 0
        for ring in rings {
            if count > 0 { starts.append(count) }
            count += ring.count
        }
        return starts
    }

    // MARK: Becoming layers

    /// The layers, in canvas points, with the drawing scaled to fit `box` and
    /// centred in it. Bottom first.
    public func layers(named name: String, fitting box: CGRect) -> [Layer] {
        let from = bounds
        guard !from.isNull, from.width > 0 || from.height > 0, box.width > 0, box.height > 0 else { return [] }
        let scale = min(from.width > 0 ? box.width / from.width : .infinity,
                        from.height > 0 ? box.height / from.height : .infinity)
        let offset = CGPoint(x: box.midX - from.width * scale / 2, y: box.midY - from.height * scale / 2)
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - from.minX) * scale + offset.x, y: (p.y - from.minY) * scale + offset.y)
        }
        func mapHandle(_ h: CGPoint?) -> CGPoint? { h.map { CGPoint(x: $0.x * scale, y: $0.y * scale) } }
        func mapRect(_ r: CGRect) -> CGRect {
            let o = map(r.origin)
            return CGRect(x: o.x, y: o.y, width: r.width * scale, height: r.height * scale)
        }
        return parts.enumerated().map { index, part in
            let partName = part.name ?? "\(name) \(index + 1)"
            let strokeWidth = part.stroke == nil ? 0 : part.strokeWidth * scale
            var layer: Layer
            switch part.shape {
            case .ellipse(let rect), .rect(let rect, _):
                var radius: CGFloat = 0
                if case .rect(_, let r) = part.shape { radius = r * scale }
                let look = AgentLook(fill: part.fill.map { .hex($0) } ?? AgentInk.none,
                                     stroke: part.stroke.map { .hex($0) },
                                     strokeWidth: part.stroke == nil ? nil : strokeWidth,
                                     cornerRadius: radius)
                let kind: AnnotationShape = if case .ellipse = part.shape { .ellipse } else { .rectangle }
                layer = AgentDrawing.layer(for: AgentShape(kind: kind, frame: mapRect(rect), look: look, name: partName))
                if part.fill == nil, var annotation = layer.annotation {
                    annotation.fill = nil
                    layer.content = .annotation(annotation)
                }
            case .path(let outline):
                let anchors = outline.rings.flatMap { $0 }.map { anchor in
                    var moved = anchor
                    moved.point = map(anchor.point)
                    moved.handleIn = mapHandle(anchor.handleIn)
                    moved.handleOut = mapHandle(anchor.handleOut)
                    return moved
                }
                let ink = part.stroke ?? part.fill ?? AgentDrawing.defaultStrokeHex
                let content = PathContent(anchors: anchors, isClosed: outline.closed,
                                          ringStarts: Self.ringStarts(outline.rings),
                                          paint: Paint(hex: ink), strokeWidth: strokeWidth,
                                          fill: outline.closed ? part.fill.map { Paint(hex: $0) } : nil,
                                          fillRule: outline.evenOdd ? .evenOdd : .nonZero)
                layer = PathBuilder.layer(content, at: content.bounds.origin, name: partName)
            }
            if part.opacity < 1 { layer.style.opacity = max(0, part.opacity) }
            return layer
        }
    }

    /// The drawing as one group named `name`, fitted into `box`.
    public func group(named name: String, fitting box: CGRect) -> Layer {
        let parts = layers(named: name, fitting: box)
        let union = parts.reduce(CGRect.null) { $0.union($1.localBounds) }
        let origin = union.isNull ? box.origin : union.origin
        let children = parts.map { part -> Layer in
            var child = part
            child.frame = part.frame.offsetBy(dx: -origin.x, dy: -origin.y)
            return child
        }
        return Layer(name: name, content: .group(GroupContent(children: children)),
                     frame: CGRect(origin: origin, size: .zero))
    }

    /// The drawing as an icon: a square frame of `side` points with the
    /// drawing filling its live area, the margin every icon in a set keeps
    /// (`IconKeylines`).
    public func iconFrame(named name: String, side: CGFloat, origin: CGPoint) -> Layer {
        let margin = IconKeylines.margin(forSide: side)
        let live = CGRect(x: margin, y: margin, width: side - 2 * margin, height: side - 2 * margin)
        return Layer.frameLayer(name: name, origin: origin, size: CGSize(width: side, height: side),
                                children: layers(named: name, fitting: live))
    }
}

// MARK: - The XML

/// The SVG's elements as a tree, read once so a gradient defined after its
/// use is still found.
struct SVGTree {
    var name: String
    var attributes: [String: String]
    var children: [SVGTree] = []

    static func parse(_ text: String) -> SVGTree? {
        let builder = Builder()
        let parser = XMLParser(data: Data(text.utf8))
        parser.delegate = builder
        guard parser.parse(), let root = builder.root, root.name == "svg" else { return nil }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var stack: [SVGTree] = []
        var root: SVGTree?

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
            stack.append(SVGTree(name: local, attributes: attributeDict))
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            guard let done = stack.popLast() else { return }
            if stack.isEmpty { root = done } else { stack[stack.count - 1].children.append(done) }
        }
    }
}

// MARK: - Reading the tree

private struct SVGReader {
    let root: SVGTree
    var parts: [SVGArtwork.Part] = []
    var viewBox: CGRect?
    /// Gradient ids to their first colour.
    var gradients: [String: String] = [:]
    /// How many unnamed parts each group name has handed out.
    private var groupCounts: [String: Int] = [:]
    private var groupTotals: [String: Int] = [:]

    init(root: SVGTree) { self.root = root }

    struct Inherited {
        var fill: String? = "#000000"
        var stroke: String?
        var strokeWidth: CGFloat = 1
        var opacity: Double = 1
        var fillOpacity: Double = 1
        var strokeOpacity: Double = 1
        var evenOdd = false
        var transform = CGAffineTransform.identity
        var groupName: String?
    }

    mutating func read() {
        if let box = root.attributes["viewBox"].map(SVGNumbers.list), box.count == 4, box[2] > 0, box[3] > 0 {
            viewBox = CGRect(x: box[0], y: box[1], width: box[2], height: box[3])
        } else if let w = root.attributes["width"].flatMap(SVGNumbers.length),
                  let h = root.attributes["height"].flatMap(SVGNumbers.length), w > 0, h > 0 {
            viewBox = CGRect(x: 0, y: 0, width: w, height: h)
        }
        collectGradients(root)
        countGroups(root, group: nil)
        walk(root, Inherited())
    }

    private mutating func collectGradients(_ node: SVGTree) {
        if node.name == "linearGradient" || node.name == "radialGradient", let id = node.attributes["id"] {
            let style = Self.style(of: node)
            let stop = node.children.first { $0.name == "stop" }
            let stopStyle = stop.map(Self.style(of:)) ?? [:]
            if let color = (stopStyle["stop-color"] ?? stop?.attributes["stop-color"]).flatMap(SVGColor.hex) {
                gradients[id] = color
            } else if let linked = (style["href"] ?? node.attributes["xlink:href"] ?? node.attributes["href"]),
                      linked.hasPrefix("#") {
                gradients[id] = "link:" + linked.dropFirst()
            }
        }
        for child in node.children { collectGradients(child) }
    }

    private static let skipped: Set<String> = [
        "defs", "clipPath", "mask", "symbol", "linearGradient", "radialGradient", "pattern", "filter",
        "text", "title", "desc", "metadata", "style", "image", "use", "marker", "foreignObject",
    ]

    private static let drawn: Set<String> = ["path", "circle", "ellipse", "rect", "line", "polyline", "polygon"]

    /// How many drawn things with no id of their own each named group holds,
    /// so a group of one gives its name whole and a group of two numbers them.
    private mutating func countGroups(_ node: SVGTree, group: String?) {
        if Self.skipped.contains(node.name) { return }
        let own = node.attributes["id"].map(Self.readable)
        if Self.drawn.contains(node.name) {
            if own == nil, let group { groupTotals[group, default: 0] += 1 }
            return
        }
        for child in node.children { countGroups(child, group: node.name == "g" ? (own ?? group) : group) }
    }

    private mutating func walk(_ node: SVGTree, _ given: Inherited) {
        if Self.skipped.contains(node.name) { return }
        let style = Self.style(of: node)
        func value(_ key: String) -> String? { style[key] ?? node.attributes[key] }
        if value("display") == "none" || value("visibility") == "hidden" { return }
        var state = given
        if let fill = value("fill") { state.fill = paint(fill) }
        if let stroke = value("stroke") { state.stroke = paint(stroke) }
        if let width = value("stroke-width").flatMap(SVGNumbers.length) { state.strokeWidth = width }
        if let o = value("opacity").flatMap(SVGNumbers.length) { state.opacity *= o }
        if let o = value("fill-opacity").flatMap(SVGNumbers.length) { state.fillOpacity = o }
        if let o = value("stroke-opacity").flatMap(SVGNumbers.length) { state.strokeOpacity = o }
        if let rule = value("fill-rule") { state.evenOdd = rule == "evenodd" }
        if let transform = node.attributes["transform"] {
            state.transform = SVGTransform.parse(transform).concatenating(state.transform)
        }
        let id = node.attributes["id"].map(Self.readable)
        switch node.name {
        case "svg", "g", "a", "switch":
            if node.name == "g", let id { state.groupName = id }
            for child in node.children { walk(child, state) }
        case "path", "circle", "ellipse", "rect", "line", "polyline", "polygon":
            add(node, state, id: id)
        default:
            return
        }
    }

    private func paint(_ text: String) -> String? {
        let word = text.trimmingCharacters(in: .whitespaces)
        if word.hasPrefix("url(") {
            let inside = word.dropFirst(4).prefix { $0 != ")" }
            var id = String(inside.trimmingCharacters(in: CharacterSet(charactersIn: "#'\" ")))
            for _ in 0..<4 {
                guard let found = gradients[id] else { break }
                if found.hasPrefix("link:") { id = String(found.dropFirst(5)) } else { return found }
            }
            // A paint that cannot be read is drawn in a middle grey rather
            // than black, so it reads as a shape and not a hole.
            return "#8E8E93"
        }
        return SVGColor.hex(word)
    }

    private mutating func add(_ node: SVGTree, _ state: Inherited, id: String?) {
        let a = node.attributes
        func number(_ key: String) -> CGFloat { a[key].flatMap(SVGNumbers.length) ?? 0 }
        let t = state.transform
        let upright = abs(t.b) < 1e-9 && abs(t.c) < 1e-9 && t.a > 0 && t.d > 0
        var shape: SVGArtwork.Shape?
        var outline: SVGPathBuilder?
        switch node.name {
        case "circle", "ellipse":
            let cx = number("cx"), cy = number("cy")
            let rx = node.name == "circle" ? number("r") : number("rx")
            let ry = node.name == "circle" ? number("r") : number("ry")
            guard rx > 0, ry > 0 else { return }
            let box = CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
            if upright {
                shape = .ellipse(box.applying(t))
            } else {
                var builder = SVGPathBuilder()
                builder.ellipse(box)
                outline = builder
            }
        case "rect":
            let box = CGRect(x: number("x"), y: number("y"), width: number("width"), height: number("height"))
            guard box.width > 0, box.height > 0 else { return }
            var rx = a["rx"].flatMap(SVGNumbers.length) ?? a["ry"].flatMap(SVGNumbers.length) ?? 0
            rx = min(rx, box.width / 2, box.height / 2)
            if upright {
                shape = .rect(box.applying(t), radius: rx * min(t.a, t.d))
            } else {
                var builder = SVGPathBuilder()
                builder.rect(box, radius: rx)
                outline = builder
            }
        case "line":
            var builder = SVGPathBuilder()
            builder.move(CGPoint(x: number("x1"), y: number("y1")))
            builder.line(CGPoint(x: number("x2"), y: number("y2")))
            outline = builder
        case "polyline", "polygon":
            let values = SVGNumbers.list(a["points"] ?? "")
            guard values.count >= 4 else { return }
            var builder = SVGPathBuilder()
            builder.move(CGPoint(x: values[0], y: values[1]))
            var index = 2
            while index + 1 < values.count {
                builder.line(CGPoint(x: values[index], y: values[index + 1]))
                index += 2
            }
            if node.name == "polygon" { builder.close() }
            outline = builder
        case "path":
            var builder = SVGPathBuilder()
            builder.read(a["d"] ?? "")
            outline = builder
        default:
            return
        }
        // A line has no inside, whatever fill it inherits.
        let fill = node.name == "line" ? nil : state.fill
        let stroke = state.stroke
        let strokeWidth = state.strokeWidth * sqrt(abs(t.a * t.d - t.b * t.c))
        guard fill != nil || (stroke != nil && strokeWidth > 0) else { return }
        let opacity = state.opacity * (fill != nil ? state.fillOpacity : state.strokeOpacity)
        var name = id
        if name == nil, let group = state.groupName {
            let total = groupTotals[group] ?? 0
            groupCounts[group, default: 0] += 1
            name = total > 1 ? "\(group) \(groupCounts[group] ?? 1)" : group
        }
        if let shape {
            parts.append(SVGArtwork.Part(name: name, shape: shape, fill: fill, stroke: stroke,
                                         strokeWidth: strokeWidth, opacity: opacity))
            return
        }
        guard var builder = outline else { return }
        builder.finish()
        let rings = builder.rings.map { ring in ring.transformed(t) }.filter { $0.anchors.count >= 2 }
        guard !rings.isEmpty else { return }
        if fill != nil {
            // A filled outline is one shape, every run closed as a browser fills it.
            parts.append(SVGArtwork.Part(
                name: name, shape: .path(.init(rings: rings.map { $0.closedAnchors() }, closed: true,
                                               evenOdd: state.evenOdd)),
                fill: fill, stroke: stroke, strokeWidth: strokeWidth, opacity: opacity))
        } else if rings.allSatisfy(\.closed) {
            parts.append(SVGArtwork.Part(
                name: name, shape: .path(.init(rings: rings.map { $0.closedAnchors() }, closed: true,
                                               evenOdd: state.evenOdd)),
                fill: nil, stroke: stroke, strokeWidth: strokeWidth, opacity: opacity))
        } else {
            // Lines that are not loops: one layer a line, since a path is
            // open or closed as a whole.
            for (index, ring) in rings.enumerated() {
                let ringName = rings.count > 1 ? name.map { "\($0) \(index + 1)" } : name
                parts.append(SVGArtwork.Part(
                    name: ringName,
                    shape: .path(.init(rings: [ring.closed ? ring.closedAnchors() : ring.anchors], closed: ring.closed,
                                       evenOdd: false)),
                    fill: nil, stroke: stroke, strokeWidth: strokeWidth, opacity: opacity))
            }
        }
    }

    static func style(of node: SVGTree) -> [String: String] {
        guard let text = node.attributes["style"] else { return [:] }
        var out: [String: String] = [:]
        for declaration in text.split(separator: ";") {
            let pair = declaration.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { continue }
            out[pair[0].trimmingCharacters(in: .whitespaces)] = pair[1].trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    /// "left-ear", "left_ear" and "leftEar" all read as "Left ear".
    static func readable(_ id: String) -> String {
        var words: [String] = []
        var current = ""
        for character in id {
            if character == "-" || character == "_" || character == " " || character == "." {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else if character.isUppercase, let last = current.last, last.isLowercase {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        let joined = words.map { $0.lowercased() }.joined(separator: " ")
        guard let first = joined.first else { return id }
        return first.uppercased() + joined.dropFirst()
    }
}

// MARK: - Path data

/// One run of a path, as the reader builds it.
struct SVGRing {
    var anchors: [PathAnchor]
    var closed: Bool

    func transformed(_ t: CGAffineTransform) -> SVGRing {
        guard t != .identity else { return self }
        let linear = CGAffineTransform(a: t.a, b: t.b, c: t.c, d: t.d, tx: 0, ty: 0)
        return SVGRing(anchors: anchors.map { anchor in
            var moved = anchor
            moved.point = anchor.point.applying(t)
            moved.handleIn = anchor.handleIn.map { $0.applying(linear) }
            moved.handleOut = anchor.handleOut.map { $0.applying(linear) }
            return moved
        }, closed: closed)
    }

    /// The anchors of a loop, with a last point sitting on the first folded
    /// into it, which is how nearly every SVG closes a curved shape.
    func closedAnchors() -> [PathAnchor] {
        var list = anchors
        guard list.count >= 3, let first = list.first, let last = list.last else { return list }
        if hypot(first.point.x - last.point.x, first.point.y - last.point.y) < 1e-6 {
            list.removeLast()
            list[0].handleIn = last.handleIn
            list[0].kind = SVGPathBuilder.kind(of: list[0])
        }
        return list
    }
}

struct SVGPathBuilder {
    private(set) var rings: [SVGRing] = []
    private var current: [PathAnchor] = []
    private var start = CGPoint.zero
    private var pen = CGPoint.zero

    mutating func move(_ point: CGPoint) {
        flush(closed: false)
        current = [PathAnchor(point: point)]
        start = point
        pen = point
    }

    mutating func line(_ point: CGPoint) {
        if current.isEmpty { current = [PathAnchor(point: pen)] }
        current.append(PathAnchor(point: point))
        pen = point
    }

    mutating func curve(_ c1: CGPoint, _ c2: CGPoint, _ end: CGPoint) {
        if current.isEmpty { current = [PathAnchor(point: pen)] }
        let lastIndex = current.count - 1
        let from = current[lastIndex].point
        let out = CGPoint(x: c1.x - from.x, y: c1.y - from.y)
        current[lastIndex].handleOut = abs(out.x) < 1e-9 && abs(out.y) < 1e-9 ? nil : out
        current[lastIndex].kind = Self.kind(of: current[lastIndex])
        let into = CGPoint(x: c2.x - end.x, y: c2.y - end.y)
        current.append(PathAnchor(point: end, handleIn: abs(into.x) < 1e-9 && abs(into.y) < 1e-9 ? nil : into))
        pen = end
    }

    mutating func close() {
        flush(closed: true)
        pen = start
    }

    mutating func finish() { flush(closed: false) }

    private mutating func flush(closed: Bool) {
        if current.count >= 2 { rings.append(SVGRing(anchors: current, closed: closed)) }
        current = []
    }

    static func kind(of anchor: PathAnchor) -> PathAnchorKind {
        guard let a = anchor.handleIn, let b = anchor.handleOut else { return .corner }
        let cross = a.x * b.y - a.y * b.x
        let dot = a.x * b.x + a.y * b.y
        let scale = max(hypot(a.x, a.y) * hypot(b.x, b.y), 1e-12)
        return abs(cross) / scale < 0.02 && dot < 0 ? .smooth : .corner
    }

    /// Four quarter curves, the way an oval is drawn as a path.
    mutating func ellipse(_ box: CGRect) {
        let k: CGFloat = 0.5522847498
        let rx = box.width / 2, ry = box.height / 2
        let c = CGPoint(x: box.midX, y: box.midY)
        move(CGPoint(x: c.x + rx, y: c.y))
        curve(CGPoint(x: c.x + rx, y: c.y + ry * k), CGPoint(x: c.x + rx * k, y: c.y + ry), CGPoint(x: c.x, y: c.y + ry))
        curve(CGPoint(x: c.x - rx * k, y: c.y + ry), CGPoint(x: c.x - rx, y: c.y + ry * k), CGPoint(x: c.x - rx, y: c.y))
        curve(CGPoint(x: c.x - rx, y: c.y - ry * k), CGPoint(x: c.x - rx * k, y: c.y - ry), CGPoint(x: c.x, y: c.y - ry))
        curve(CGPoint(x: c.x + rx * k, y: c.y - ry), CGPoint(x: c.x + rx, y: c.y - ry * k), CGPoint(x: c.x + rx, y: c.y))
        close()
    }

    mutating func rect(_ box: CGRect, radius: CGFloat) {
        guard radius > 0 else {
            move(box.origin)
            line(CGPoint(x: box.maxX, y: box.minY))
            line(CGPoint(x: box.maxX, y: box.maxY))
            line(CGPoint(x: box.minX, y: box.maxY))
            close()
            return
        }
        let r = radius, k: CGFloat = 0.5522847498 * radius
        move(CGPoint(x: box.minX + r, y: box.minY))
        line(CGPoint(x: box.maxX - r, y: box.minY))
        curve(CGPoint(x: box.maxX - r + k, y: box.minY), CGPoint(x: box.maxX, y: box.minY + r - k), CGPoint(x: box.maxX, y: box.minY + r))
        line(CGPoint(x: box.maxX, y: box.maxY - r))
        curve(CGPoint(x: box.maxX, y: box.maxY - r + k), CGPoint(x: box.maxX - r + k, y: box.maxY), CGPoint(x: box.maxX - r, y: box.maxY))
        line(CGPoint(x: box.minX + r, y: box.maxY))
        curve(CGPoint(x: box.minX + r - k, y: box.maxY), CGPoint(x: box.minX, y: box.maxY - r + k), CGPoint(x: box.minX, y: box.maxY - r))
        line(CGPoint(x: box.minX, y: box.minY + r))
        curve(CGPoint(x: box.minX, y: box.minY + r - k), CGPoint(x: box.minX + r - k, y: box.minY), CGPoint(x: box.minX + r, y: box.minY))
        close()
    }

    /// Reads a `d` attribute.
    mutating func read(_ data: String) {
        var scanner = SVGNumbers.Scanner(data)
        var command: Character = "M"
        var lastControl: CGPoint?
        var lastQuad: CGPoint?
        while let next = scanner.command() ?? (scanner.hasNumber ? command : nil) {
            var kind = next
            if kind == "M" || kind == "m" {
                // Pairs after a move are lines.
                command = kind == "M" ? "L" : "l"
            } else {
                command = kind
            }
            let relative = kind.isLowercase
            let base = relative ? pen : .zero
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: base.x + x, y: base.y + y) }
            kind = Character(kind.uppercased())
            var control: CGPoint?
            var quad: CGPoint?
            switch kind {
            case "M":
                guard let x = scanner.number(), let y = scanner.number() else { return }
                move(point(x, y))
            case "L":
                guard let x = scanner.number(), let y = scanner.number() else { return }
                line(point(x, y))
            case "H":
                guard let x = scanner.number() else { return }
                line(CGPoint(x: relative ? pen.x + x : x, y: pen.y))
            case "V":
                guard let y = scanner.number() else { return }
                line(CGPoint(x: pen.x, y: relative ? pen.y + y : y))
            case "C":
                guard let x1 = scanner.number(), let y1 = scanner.number(), let x2 = scanner.number(),
                      let y2 = scanner.number(), let x = scanner.number(), let y = scanner.number() else { return }
                let c2 = point(x2, y2)
                curve(point(x1, y1), c2, point(x, y))
                control = c2
            case "S":
                guard let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return }
                let c1 = lastControl.map { CGPoint(x: 2 * pen.x - $0.x, y: 2 * pen.y - $0.y) } ?? pen
                let c2 = point(x2, y2)
                curve(c1, c2, point(x, y))
                control = c2
            case "Q":
                guard let qx = scanner.number(), let qy = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return }
                let q = point(qx, qy)
                quadratic(q, point(x, y))
                quad = q
            case "T":
                guard let x = scanner.number(), let y = scanner.number() else { return }
                let q = lastQuad.map { CGPoint(x: 2 * pen.x - $0.x, y: 2 * pen.y - $0.y) } ?? pen
                quadratic(q, point(x, y))
                quad = q
            case "A":
                guard let rx = scanner.number(), let ry = scanner.number(), let angle = scanner.number(),
                      let large = scanner.flag(), let sweep = scanner.flag(),
                      let x = scanner.number(), let y = scanner.number() else { return }
                arc(rx: rx, ry: ry, angle: angle, large: large, sweep: sweep, to: point(x, y))
            case "Z":
                close()
            default:
                return
            }
            lastControl = control
            lastQuad = quad
        }
    }

    private mutating func quadratic(_ q: CGPoint, _ end: CGPoint) {
        let from = pen
        let c1 = CGPoint(x: from.x + 2.0 / 3 * (q.x - from.x), y: from.y + 2.0 / 3 * (q.y - from.y))
        let c2 = CGPoint(x: end.x + 2.0 / 3 * (q.x - end.x), y: end.y + 2.0 / 3 * (q.y - end.y))
        curve(c1, c2, end)
    }

    /// An elliptical arc as cubic curves, a quarter turn at most each (SVG 1.1, F.6.5).
    private mutating func arc(rx: CGFloat, ry: CGFloat, angle: CGFloat, large: Bool, sweep: Bool, to end: CGPoint) {
        let from = pen
        var rx = abs(rx), ry = abs(ry)
        guard rx > 0, ry > 0, from != end else { line(end); return }
        let phi = angle * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (from.x - end.x) / 2, dy = (from.y - end.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = denominator == 0 ? 0 : sqrt(max(0, numerator / denominator))
        if large == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (from.x + end.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (from.y + end.y) / 2
        func angleBetween(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let sign: CGFloat = ux * vy - uy * vx < 0 ? -1 : 1
            let dot = (ux * vx + uy * vy) / (hypot(ux, uy) * hypot(vx, vy))
            return sign * acos(min(1, max(-1, dot)))
        }
        let theta1 = angleBetween(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angleBetween((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }
        let pieces = max(1, Int(ceil(abs(delta) / (.pi / 2) - 1e-9)))
        let step = delta / CGFloat(pieces)
        let t = 4.0 / 3.0 * tan(step / 4)
        func onEllipse(_ a: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(a) * cosPhi - ry * sin(a) * sinPhi,
                    y: cy + rx * cos(a) * sinPhi + ry * sin(a) * cosPhi)
        }
        func derivative(_ a: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(a) * cosPhi - ry * cos(a) * sinPhi,
                    y: -rx * sin(a) * sinPhi + ry * cos(a) * cosPhi)
        }
        var a = theta1
        for index in 0..<pieces {
            let b = a + step
            let p0 = onEllipse(a)
            let p3 = index == pieces - 1 ? end : onEllipse(b)
            let d0 = derivative(a), d3 = derivative(b)
            curve(CGPoint(x: p0.x + t * d0.x, y: p0.y + t * d0.y),
                  CGPoint(x: p3.x - t * d3.x, y: p3.y - t * d3.y), p3)
            a = b
        }
    }
}

// MARK: - Numbers, transforms and colours

enum SVGNumbers {

    /// Every number in a list such as a viewBox or a polygon's points.
    static func list(_ text: String) -> [CGFloat] {
        var scanner = Scanner(text)
        var out: [CGFloat] = []
        while let n = scanner.number() { out.append(n) }
        return out
    }

    /// A length such as "12", "12px" or "1.5e1"; a percentage is not one.
    static func length(_ text: String) -> CGFloat? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasSuffix("%") else { return nil }
        var scanner = Scanner(trimmed)
        return scanner.number()
    }

    struct Scanner {
        private let characters: [Character]
        private var index = 0

        init(_ text: String) { characters = Array(text) }

        private mutating func skipSeparators() {
            while index < characters.count, characters[index].isWhitespace || characters[index] == "," { index += 1 }
        }

        var hasNumber: Bool {
            var probe = self
            probe.skipSeparators()
            guard probe.index < characters.count else { return false }
            let c = probe.characters[probe.index]
            return c.isNumber || c == "-" || c == "+" || c == "."
        }

        mutating func command() -> Character? {
            skipSeparators()
            guard index < characters.count else { return nil }
            let c = characters[index]
            guard c.isLetter, c != "e", c != "E" else { return nil }
            index += 1
            return c
        }

        /// An arc's flag: one character, 0 or 1, with nothing needed after it.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard index < characters.count else { return nil }
            let c = characters[index]
            guard c == "0" || c == "1" else { return nil }
            index += 1
            return c == "1"
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            var text = ""
            var seenDot = false
            var seenDigit = false
            if index < characters.count, characters[index] == "-" || characters[index] == "+" {
                text.append(characters[index])
                index += 1
            }
            while index < characters.count {
                let c = characters[index]
                if c.isASCII, c.isNumber {
                    seenDigit = true
                    text.append(c)
                } else if c == ".", !seenDot {
                    seenDot = true
                    text.append(c)
                } else {
                    break
                }
                index += 1
            }
            guard seenDigit else { return nil }
            if index < characters.count, characters[index] == "e" || characters[index] == "E" {
                var exponent = "e"
                var probe = index + 1
                if probe < characters.count, characters[probe] == "-" || characters[probe] == "+" {
                    exponent.append(characters[probe])
                    probe += 1
                }
                var digits = false
                while probe < characters.count, characters[probe].isASCII, characters[probe].isNumber {
                    exponent.append(characters[probe])
                    probe += 1
                    digits = true
                }
                if digits {
                    text += exponent
                    index = probe
                }
            }
            return Double(text).map { CGFloat($0) }
        }
    }
}

enum SVGTransform {

    /// A transform list, applied the way SVG applies it: the rightmost first.
    static func parse(_ text: String) -> CGAffineTransform {
        var result = CGAffineTransform.identity
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")") {
            let name = rest[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " ,\t\n"))
            let values = SVGNumbers.list(String(rest[rest.index(after: open)..<close]))
            var step = CGAffineTransform.identity
            switch name {
            case "matrix" where values.count == 6:
                step = CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3],
                                         tx: values[4], ty: values[5])
            case "translate" where !values.isEmpty:
                step = CGAffineTransform(translationX: values[0], y: values.count > 1 ? values[1] : 0)
            case "scale" where !values.isEmpty:
                step = CGAffineTransform(scaleX: values[0], y: values.count > 1 ? values[1] : values[0])
            case "rotate" where !values.isEmpty:
                let radians = values[0] * .pi / 180
                if values.count == 3 {
                    step = CGAffineTransform(translationX: -values[1], y: -values[2])
                        .concatenating(CGAffineTransform(rotationAngle: radians))
                        .concatenating(CGAffineTransform(translationX: values[1], y: values[2]))
                } else {
                    step = CGAffineTransform(rotationAngle: radians)
                }
            case "skewX" where !values.isEmpty:
                step = CGAffineTransform(a: 1, b: 0, c: tan(values[0] * .pi / 180), d: 1, tx: 0, ty: 0)
            case "skewY" where !values.isEmpty:
                step = CGAffineTransform(a: 1, b: tan(values[0] * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
            default:
                break
            }
            // Written left to right, the right one acts first on the point.
            result = step.concatenating(result)
            rest = rest[rest.index(after: close)...]
        }
        return result
    }
}

enum SVGColor {

    /// "#RRGGBB" for a colour, nil for none.
    static func hex(_ text: String) -> String? {
        let word = text.trimmingCharacters(in: .whitespaces).lowercased()
        if word.isEmpty || word == "none" || word == "transparent" { return nil }
        if word == "currentcolor" { return "#000000" }
        if word.hasPrefix("#") {
            let digits = Array(word.dropFirst())
            switch digits.count {
            case 3, 4: return "#" + digits.prefix(3).map { "\($0)\($0)" }.joined().uppercased()
            case 6, 8: return "#" + String(digits.prefix(6)).uppercased()
            default: return nil
            }
        }
        if word.hasPrefix("rgb") {
            let values = SVGNumbers.list(String(word.drop { $0 != "(" }))
            guard values.count >= 3 else { return nil }
            let percent = word.contains("%")
            let channels = values.prefix(3).map { value -> Int in
                let v = percent ? value * 2.55 : value
                return Int(min(255, max(0, v.rounded())))
            }
            return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
        }
        return named[word]
    }

    static let named: [String: String] = [
        "black": "#000000", "white": "#FFFFFF", "red": "#FF0000", "green": "#008000", "blue": "#0000FF",
        "yellow": "#FFFF00", "orange": "#FFA500", "purple": "#800080", "pink": "#FFC0CB", "brown": "#A52A2A",
        "gray": "#808080", "grey": "#808080", "silver": "#C0C0C0", "gold": "#FFD700", "navy": "#000080",
        "teal": "#008080", "maroon": "#800000", "olive": "#808000", "lime": "#00FF00", "aqua": "#00FFFF",
        "cyan": "#00FFFF", "magenta": "#FF00FF", "fuchsia": "#FF00FF", "beige": "#F5F5DC", "tan": "#D2B48C",
        "khaki": "#F0E68C", "coral": "#FF7F50", "salmon": "#FA8072", "crimson": "#DC143C", "indigo": "#4B0082",
        "violet": "#EE82EE", "skyblue": "#87CEEB", "lightblue": "#ADD8E6", "darkblue": "#00008B",
        "lightgreen": "#90EE90", "darkgreen": "#006400", "forestgreen": "#228B22", "saddlebrown": "#8B4513",
        "chocolate": "#D2691E", "sienna": "#A0522D", "peru": "#CD853F", "wheat": "#F5DEB3", "ivory": "#FFFFF0",
        "lightgray": "#D3D3D3", "lightgrey": "#D3D3D3", "darkgray": "#A9A9A9", "darkgrey": "#A9A9A9",
        "dimgray": "#696969", "orangered": "#FF4500", "tomato": "#FF6347", "turquoise": "#40E0D0",
        "lavender": "#E6E6FA", "plum": "#DDA0DD", "goldenrod": "#DAA520", "sandybrown": "#F4A460",
        "steelblue": "#4682B4", "royalblue": "#4169E1", "dodgerblue": "#1E90FF", "deepskyblue": "#00BFFF",
        "hotpink": "#FF69B4", "deeppink": "#FF1493", "limegreen": "#32CD32", "seagreen": "#2E8B57",
        "olivedrab": "#6B8E23", "yellowgreen": "#9ACD32", "darkorange": "#FF8C00", "firebrick": "#B22222",
        "lightyellow": "#FFFFE0", "lightpink": "#FFB6C1", "darkred": "#8B0000", "burlywood": "#DEB887",
        "rosybrown": "#BC8F8F", "slategray": "#708090", "midnightblue": "#191970", "springgreen": "#00FF7F",
        "mediumseagreen": "#3CB371", "orchid": "#DA70D6", "peachpuff": "#FFDAB9", "mintcream": "#F5FFFA",
        "snow": "#FFFAFA", "whitesmoke": "#F5F5F5", "gainsboro": "#DCDCDC", "linen": "#FAF0E6",
        "cornsilk": "#FFF8DC", "lemonchiffon": "#FFFACD", "darkslategray": "#2F4F4F", "cadetblue": "#5F9EA0",
        "lightskyblue": "#87CEFA", "powderblue": "#B0E0E6", "darkolivegreen": "#556B2F", "darkkhaki": "#BDB76B",
    ]
}
