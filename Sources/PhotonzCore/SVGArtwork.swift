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
// linear or radial gradient fill becomes the app's own gradient paint (a
// stroke paints with its first colour). Text, images, filters, masks and clips
// are left out.

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
        /// The fill as a gradient, when the SVG filled it with one; `fill`
        /// is then its first colour.
        public var fillPaint: Paint?
        /// The named groups it sits in, outermost first: only read when the
        /// drawing is parsed keeping its groups.
        public var groups: [String] = []
        /// How its lines end and turn; nil where the SVG does not say.
        public var lineEnd: PathLineEnd?
        public var lineCorner: PathLineCorner?
    }

    public let viewBox: CGRect?

    /// The size the file says it is, from its width and height, in points
    /// (`SVGNumbers.absoluteLength`). Nil when it gives neither, or only a
    /// percentage, and its view box or what it draws has to answer.
    public internal(set) var ownSize: CGSize?

    /// What the file draws that these parts do not carry, one word each
    /// ("text", "clip-path"): empty when the parts are the whole drawing.
    public internal(set) var leftOut: Set<String> = []

    /// How an id reads as a part's name.
    static func readableID(_ id: String) -> String { SVGReader.readable(id) }
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

    /// `keepingGroups` keeps each `<g id>` as a group of layers (an
    /// painted drawing's colour layers) instead of one flat group.
    public static func parse(_ text: String, keepingGroups: Bool = false) -> Result<SVGArtwork, SVGArtworkError> {
        read(text, keepingGroups: keepingGroups).flatMap { artwork in
            artwork.parts.isEmpty
                ? .failure(SVGArtworkError("That SVG draws nothing Photonz can draw: no paths or shapes."))
                : .success(artwork)
        }
    }

    /// `parse`, with a file that holds no shapes coming back holding none, so
    /// what else it holds can still be asked (`leftOut`).
    static func read(_ text: String, keepingGroups: Bool) -> Result<SVGArtwork, SVGArtworkError> {
        guard let start = text.range(of: "<svg") else {
            return .failure(SVGArtworkError("That is not an SVG: it has no <svg> element."))
        }
        let body = String(text[start.lowerBound...])
        guard let root = SVGTree.parse(body) else {
            return .failure(SVGArtworkError("That SVG could not be read: its XML is broken."))
        }
        var reader = SVGReader(root: root)
        reader.keepsGroups = keepingGroups
        reader.read()
        var artwork = SVGArtwork(viewBox: reader.viewBox, parts: reader.parts)
        artwork.ownSize = reader.ownSize
        artwork.leftOut = reader.leftOut
        return .success(artwork)
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
    /// `within` is the part of the drawing that fills `box`: all of what is
    /// drawn when left out.
    ///
    /// `grid` puts every point, box and line weight on whole units of an icon
    /// (`IconGridLanding`); handles stay as the curve needs them.
    public func layers(named name: String, fitting box: CGRect, within: CGRect? = nil,
                       grid: IconGridLanding? = nil) -> [Layer] {
        let from = within ?? bounds
        guard !from.isNull, from.width > 0 || from.height > 0, box.width > 0, box.height > 0 else { return [] }
        let scale = min(from.width > 0 ? box.width / from.width : .infinity,
                        from.height > 0 ? box.height / from.height : .infinity)
        let offset = CGPoint(x: box.midX - from.width * scale / 2, y: box.midY - from.height * scale / 2)
        func placed(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - from.minX) * scale + offset.x, y: (p.y - from.minY) * scale + offset.y)
        }
        func map(_ p: CGPoint) -> CGPoint {
            grid?.landing(placed(p)) ?? placed(p)
        }
        func mapHandle(_ h: CGPoint?) -> CGPoint? { h.map { CGPoint(x: $0.x * scale, y: $0.y * scale) } }
        func mapRect(_ r: CGRect) -> CGRect {
            let o = map(r.origin)
            guard let grid else { return CGRect(x: o.x, y: o.y, width: r.width * scale, height: r.height * scale) }
            let far = map(CGPoint(x: r.maxX, y: r.maxY))
            return CGRect(x: o.x, y: o.y, width: max(far.x - o.x, grid.unit), height: max(far.y - o.y, grid.unit))
        }
        return parts.enumerated().map { index, part in
            let partName = part.name ?? "\(name) \(index + 1)"
            let strokeWidth = part.stroke == nil ? 0 : grid?.weight(part.strokeWidth * scale) ?? part.strokeWidth * scale
            var layer: Layer
            switch part.shape {
            case .ellipse(let rect), .rect(let rect, _):
                var radius: CGFloat = 0
                if case .rect(_, let r) = part.shape, r > 0 { radius = grid?.length(r * scale) ?? r * scale }
                let look = AgentLook(fill: part.fill.map { .hex($0) } ?? AgentInk.none,
                                     stroke: part.stroke.map { .hex($0) },
                                     strokeWidth: part.stroke == nil ? nil : strokeWidth,
                                     cornerRadius: radius)
                let kind: AnnotationShape = if case .ellipse = part.shape { .ellipse } else { .rectangle }
                layer = AgentDrawing.layer(for: AgentShape(kind: kind, frame: mapRect(rect), look: look, name: partName))
                if part.fill == nil, var annotation = layer.annotation {
                    annotation.fill = nil
                    layer.content = .annotation(annotation)
                } else if let paint = part.fillPaint, var annotation = layer.annotation {
                    annotation.fill = paint
                    layer.content = .annotation(annotation)
                }
                // An SVG's line rides the shape's edge, half each side. A box
                // starts with its line inside, which on the file's numbers is
                // half a line small all round: on 2026-11-09 an envelope's
                // body line sat a unit under the flap drawn to meet it.
                if part.stroke != nil, strokeWidth > 0, var annotation = layer.annotation {
                    annotation.strokePosition = .center
                    layer.content = .annotation(annotation)
                    layer.style.borderPosition = .center
                }
            case .path(let outline):
                let anchors = outline.rings.flatMap { ring in
                    var landed = ring.map { anchor in
                        var moved = anchor
                        moved.point = map(anchor.point)
                        moved.handleIn = mapHandle(anchor.handleIn)
                        moved.handleOut = mapHandle(anchor.handleOut)
                        return moved
                    }
                    if let grid { Self.stretchHandles(&landed, drawn: ring.map { placed($0.point) }, unit: grid.unit, closed: outline.closed) }
                    return landed
                }
                let ink = part.stroke ?? part.fill ?? AgentDrawing.defaultStrokeHex
                let content = PathContent(anchors: anchors, isClosed: outline.closed,
                                          ringStarts: Self.ringStarts(outline.rings),
                                          paint: Paint(hex: ink), strokeWidth: strokeWidth,
                                          fill: outline.closed ? (part.fillPaint ?? part.fill.map { Paint(hex: $0) }) : nil,
                                          fillRule: outline.evenOdd ? .evenOdd : .nonZero)
                var drawn = content
                if let end = part.lineEnd { drawn.lineEnd = end }
                if let corner = part.lineCorner { drawn.lineCorner = corner }
                layer = PathBuilder.layer(drawn, at: drawn.bounds.origin, name: partName)
            }
            if part.opacity < 1 { layer.style.opacity = max(0, part.opacity) }
            return layer
        }
    }

    /// Each run's handles stretched as its ends were by landing on units, so
    /// a curve keeps the shape it was drawn with. Pinned to their anchors
    /// unstretched, a curve whose end rounded half a unit came out longer and
    /// straighter than drawn (a balloon's string, the eval, 2026-11-08). A run
    /// under two units one way keeps that way's handles as they were:
    /// stretched, a short run's handles put a kink in a cloud's lobe.
    static func stretchHandles(_ landed: inout [PathAnchor], drawn: [CGPoint], unit: CGFloat, closed: Bool) {
        guard landed.count == drawn.count, landed.count >= 2 else { return }
        func stretch(_ old: CGFloat, _ new: CGFloat) -> CGFloat {
            guard abs(old) >= unit * 2 else { return 1 }
            let by = new / old
            return by >= 2.0 / 3 && by <= 1.5 ? by : 1
        }
        let runs = closed ? landed.count : landed.count - 1
        for start in 0..<runs {
            let end = (start + 1) % landed.count
            let sx = stretch(drawn[end].x - drawn[start].x, landed[end].point.x - landed[start].point.x)
            let sy = stretch(drawn[end].y - drawn[start].y, landed[end].point.y - landed[start].point.y)
            landed[start].handleOut = landed[start].handleOut.map { CGPoint(x: $0.x * sx, y: $0.y * sy) }
            landed[end].handleIn = landed[end].handleIn.map { CGPoint(x: $0.x * sx, y: $0.y * sy) }
        }
    }

    /// The drawing as one group named `name`, fitted into `box`; parts read
    /// keeping their groups sit in groups of their own inside it.
    public func group(named name: String, fitting box: CGRect) -> Layer {
        let parts = layers(named: name, fitting: box)
        if self.parts.contains(where: { !$0.groups.isEmpty }) {
            return Self.nest(name: name, Array(zip(parts, self.parts.map(\.groups))), depth: 0)
                ?? Layer(name: name, content: .group(GroupContent(children: [])), frame: CGRect(origin: box.origin, size: .zero))
        }
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

    /// Layers (in canvas points) with the groups they sit in, made into a
    /// group named `name` holding a group for each run of parts that share
    /// their next group, bottom first.
    private static func nest(name: String, _ items: [(Layer, [String])], depth: Int) -> Layer? {
        var children: [Layer] = []
        var index = 0
        while index < items.count {
            let groups = items[index].1
            guard depth < groups.count else {
                children.append(items[index].0)
                index += 1
                continue
            }
            let inner = groups[depth]
            var run: [(Layer, [String])] = []
            while index < items.count, depth < items[index].1.count, items[index].1[depth] == inner,
                  items[index].1.prefix(depth) == groups.prefix(depth) {
                run.append(items[index])
                index += 1
            }
            if let group = nest(name: inner, run, depth: depth + 1) { children.append(group) }
        }
        let union = children.reduce(CGRect.null) { $0.union(Self.canvasBox(of: $1)) }
        guard !union.isNull else { return nil }
        let placed = children.map { child -> Layer in
            var moved = child
            moved.frame = child.frame.offsetBy(dx: -union.minX, dy: -union.minY)
            return moved
        }
        return Layer(name: name, content: .group(GroupContent(children: placed)), frame: CGRect(origin: union.origin, size: .zero))
    }

    /// Where a layer built here sits on the canvas: a group's box is what it holds.
    private static func canvasBox(of layer: Layer) -> CGRect {
        if case .group(let group) = layer.content {
            let inside = group.children.reduce(CGRect.null) { $0.union(canvasBox(of: $1)) }
            return inside.isNull ? .null : inside.offsetBy(dx: layer.frame.minX, dy: layer.frame.minY)
        }
        return layer.localBounds
    }

    /// Where a drawing made on the 24 grid goes on a 24 unit picture when it
    /// can keep the whole numbers it was drawn in: at exactly one unit to its
    /// unit, moved by whole units to the middle. Stretching it to the live
    /// area would turn every one of those numbers into a fraction. Nil where
    /// it is not on that grid, or is too big for the live area or too small to
    /// read, which is what fitting is for.
    private func keptOnItsGrid(side: CGFloat) -> (box: CGRect, within: CGRect)? {
        let grid = IconKeylines.artboardSide
        guard side == IconUnits.pictureSide, let viewBox, viewBox.size == CGSize(width: grid, height: grid),
              !bounds.isNull else { return nil }
        // Its points are what the live area holds, as the model is told: a line
        // along the edge of it reaches a unit past, and that is still the grid.
        let points = parts.reduce(CGRect.null) { $0.union(Self.shapeBounds($1.shape)) }
        let reach = max(points.width, points.height)
        // A drawing placed exactly across the live area reads back a hair over.
        guard reach >= Self.smallestKeptReach, reach <= IconKeylines.liveAreaSide + 1e-3 else { return nil }
        let shift = CGPoint(x: (viewBox.midX - points.midX).rounded(), y: (viewBox.midY - points.midY).rounded())
        let unit = side / grid
        return (CGRect(x: shift.x * unit, y: shift.y * unit, width: side, height: side), viewBox)
    }

    /// Under this many units across, a drawing is fitted up to the live area
    /// rather than left small on its grid.
    private static let smallestKeptReach: CGFloat = 16

    /// The drawing as an icon: a square frame of `side` points with the
    /// drawing filling its live area, the margin every icon in a set keeps
    /// (`IconKeylines`).
    ///
    /// `onGrid` is an icon that moves: its viewBox fills the frame, so what
    /// was drawn stands where its grid says and has the room around it the
    /// drawing left, for parts that travel. Nothing is fitted to what happens
    /// to be drawn, and a `<g id>` read keeping its groups stays a group.
    public func iconFrame(named name: String, side: CGFloat, origin: CGPoint, onGrid: Bool = false) -> Layer {
        let size = CGSize(width: side, height: side)
        guard onGrid, let viewBox, viewBox.width > 0, viewBox.height > 0 else {
            if let kept = keptOnItsGrid(side: side) {
                return Layer.frameLayer(name: name, origin: origin, size: size,
                                        children: layers(named: name, fitting: kept.box, within: kept.within,
                                                         grid: IconGridLanding(side: side)),
                                        backgroundHex: nil)
            }
            let unit = side == IconUnits.pictureSide ? side / IconKeylines.artboardSide : 1
            let margin = IconKeylines.margin(forSide: side, unit: unit)
            let live = CGRect(x: margin, y: margin, width: side - 2 * margin, height: side - 2 * margin)
            return Layer.frameLayer(name: name, origin: origin, size: size,
                                    children: layers(named: name, fitting: live,
                                                     grid: IconGridLanding(side: side)),
                                    backgroundHex: nil)
        }
        let drawn = layers(named: name, fitting: CGRect(origin: .zero, size: size), within: viewBox,
                           grid: IconGridLanding(side: side))
        return Layer.frameLayer(name: name, origin: origin, size: size,
                                children: nested(drawn, named: name), backgroundHex: nil)
    }

    /// `drawn`, one layer a part, with the parts read keeping their groups
    /// gathered into those groups and every layer left where it stands.
    func nested(_ drawn: [Layer], named name: String) -> [Layer] {
        guard parts.contains(where: { !$0.groups.isEmpty }),
              let top = Self.nest(name: name, Array(zip(drawn, parts.map(\.groups))), depth: 0) else { return drawn }
        return top.children.map { child in
            var moved = child
            moved.frame = child.frame.offsetBy(dx: top.frame.minX, dy: top.frame.minY)
            return moved
        }
    }
}

// MARK: - The XML

/// The SVG's elements as a tree, read once so a gradient defined after its
/// use is still found.
struct SVGTree {
    var name: String
    var attributes: [String: String]
    var children: [SVGTree] = []
    /// The words directly inside it, which only a style sheet is asked for.
    var text = ""

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

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard let open = stack.last, open.name == "style" else { return }
            stack[stack.count - 1].text = open.text + string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard let open = stack.last, open.name == "style" else { return }
            stack[stack.count - 1].text = open.text + String(decoding: CDATABlock, as: UTF8.self)
        }
    }
}

// MARK: - Reading the tree

private struct SVGReader {
    let root: SVGTree
    var parts: [SVGArtwork.Part] = []
    var viewBox: CGRect?
    var ownSize: CGSize?
    var leftOut: Set<String> = []
    /// What the style sheets say about each class.
    private var classRules: [String: [String: String]] = [:]
    /// Clip ids to the element they name.
    private var clips: [String: SVGTree] = [:]
    /// Gradient ids to their first colour.
    var gradients: [String: String] = [:]
    /// Gradient ids to the paint they are.
    var paints: [String: Paint] = [:]
    var keepsGroups = false
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
        var fillPaint: Paint?
        var groups: [String] = []
        var lineEnd: PathLineEnd?
        var lineCorner: PathLineCorner?
        /// Inside the outermost `svg`, where another one is a drawing placed
        /// in this one.
        var insideSVG = false
    }

    mutating func read() {
        if let w = root.attributes["width"].flatMap(SVGNumbers.absoluteLength),
           let h = root.attributes["height"].flatMap(SVGNumbers.absoluteLength), w > 0, h > 0 {
            ownSize = CGSize(width: w, height: h)
        }
        if let box = root.attributes["viewBox"].map(SVGNumbers.list), box.count == 4, box[2] > 0, box[3] > 0 {
            viewBox = CGRect(x: box[0], y: box[1], width: box[2], height: box[3])
        } else if let ownSize {
            viewBox = CGRect(origin: .zero, size: ownSize)
        }
        collectGradients(root)
        collectClips(root)
        readStyleSheets(root)
        countGroups(root, group: nil)
        walk(root, Inherited())
    }

    private mutating func collectGradients(_ node: SVGTree) {
        if node.name == "linearGradient" || node.name == "radialGradient", let id = node.attributes["id"],
           let paint = Self.gradientPaint(node) {
            paints[id] = paint
        }
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

    /// A gradient element as the app's paint, with its stops, its direction
    /// and (for a radial one) its middle, read in the shape's own box.
    static func gradientPaint(_ node: SVGTree) -> Paint? {
        func unit(_ key: String, _ fallback: CGFloat) -> CGFloat {
            guard let text = node.attributes[key]?.trimmingCharacters(in: .whitespaces) else { return fallback }
            if text.hasSuffix("%"), let value = Double(text.dropLast()) { return CGFloat(value / 100) }
            return SVGNumbers.length(text) ?? fallback
        }
        var stops: [(String, CGFloat, Double)] = []
        for stop in node.children where stop.name == "stop" {
            let style = style(of: stop)
            guard let colour = (style["stop-color"] ?? stop.attributes["stop-color"]).flatMap(SVGColor.hex) else { continue }
            let offsetText = (stop.attributes["offset"] ?? "0").trimmingCharacters(in: .whitespaces)
            let offset: CGFloat = offsetText.hasSuffix("%") ? CGFloat(Double(offsetText.dropLast()) ?? 0) / 100
                : (SVGNumbers.length(offsetText) ?? 0)
            let alpha = (style["stop-opacity"] ?? stop.attributes["stop-opacity"]).flatMap(SVGNumbers.length).map(Double.init) ?? 1
            stops.append((colour, min(max(offset, 0), 1), min(max(alpha, 0), 1)))
        }
        guard stops.count >= 2, let first = stops.first else { return nil }
        func hex(_ colour: String, _ alpha: Double) -> String {
            alpha >= 0.999 ? colour : colour + String(format: "%02X", Int((alpha * 255).rounded()))
        }
        if node.name == "radialGradient" {
            let cx = unit("cx", 0.5), cy = unit("cy", 0.5), r = unit("r", 0.5)
            // The app's ramp reaches the box's furthest corner.
            let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)]
            let reach = corners.map { hypot($0.x - cx, $0.y - cy) }.max() ?? 1
            let scale = reach > 0 ? r / reach : 1
            return Paint(hex: first.0, kind: .radial,
                         stops: stops.map { GradientStop(hex: hex($0.0, $0.2), position: Double($0.1 * scale)) },
                         center: CGPoint(x: cx, y: cy))
        }
        let x1 = unit("x1", 0), y1 = unit("y1", 0), x2 = unit("x2", 1), y2 = unit("y2", 0)
        let dx = x2 - x1, dy = y2 - y1
        let length = hypot(dx, dy)
        guard length > 0 else { return Paint(hex: first.0) }
        let d = CGPoint(x: dx / length, y: dy / length)
        // 0 degrees runs up the box, 90 to the right (`Paint.angle`).
        let angle = atan2(d.x, -d.y) * 180 / .pi
        let span = abs(d.x) + abs(d.y)
        let start = ((x1 - 0.5) * d.x + (y1 - 0.5) * d.y) / span + 0.5
        let positions = stops.map { start + $0.1 * length / span }
        return Paint(hex: first.0, kind: .linear,
                     stops: zip(stops, positions).map { GradientStop(hex: hex($0.0, $0.2), position: Double($1)) },
                     angle: Double(angle < 0 ? angle + 360 : angle))
    }

    private static let skipped: Set<String> = [
        "defs", "clipPath", "mask", "symbol", "linearGradient", "radialGradient", "pattern", "filter",
        "text", "title", "desc", "metadata", "style", "image", "use", "marker", "foreignObject",
    ]

    private static let drawn: Set<String> = ["path", "circle", "ellipse", "rect", "line", "polyline", "polygon"]

    /// What is `skipped` and is seen when the file is shown: the rest of that
    /// list only ever lends itself to something else.
    private static let shownButNotRead: Set<String> = ["text", "image", "use", "foreignObject"]

    /// Settings that change how a thing is drawn and that no part holds.
    private static let unreadSettings = ["clip-path", "mask", "filter", "stroke-dasharray",
                                         "marker-start", "marker-mid", "marker-end"]

    /// Reads the file's style sheets. The one kind of rule a drawing tool
    /// writes is read, `.st0{fill:none}`, which is how Illustrator paints every
    /// shape it saves; a sheet saying anything else (an animation, a hover, a
    /// rule about what sits inside what) is left out whole.
    private mutating func readStyleSheets(_ node: SVGTree) {
        if node.name == "style", !readClassRules(node.text) { leftOut.insert("style") }
        for child in node.children { readStyleSheets(child) }
    }

    /// Takes in every rule in `sheet`, and says whether that was all of it.
    private mutating func readClassRules(_ sheet: String) -> Bool {
        let bare = sheet.replacing(/\/\*[\s\S]*?\*\//, with: "")
        var rest = Substring(bare)
        while let open = rest.firstIndex(of: "{") {
            guard let close = rest[open...].firstIndex(of: "}") else { return false }
            let selectors = rest[..<open].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !selectors.isEmpty,
                  selectors.allSatisfy({ $0.wholeMatch(of: /\.[A-Za-z_][\w-]*/) != nil }) else { return false }
            let declarations = Self.declarations(String(rest[rest.index(after: open)..<close]))
            for selector in selectors { classRules[String(selector.dropFirst()), default: [:]].merge(declarations) { $1 } }
            rest = rest[rest.index(after: close)...]
        }
        return rest.allSatisfy(\.isWhitespace)
    }

    /// What is said about this element: its classes, in the order the sheet
    /// gave them, and then its own style attribute over the top.
    private func style(of node: SVGTree) -> [String: String] {
        var said: [String: String] = [:]
        for name in (node.attributes["class"] ?? "").split(whereSeparator: \.isWhitespace) {
            said.merge(classRules[String(name)] ?? [:]) { $1 }
        }
        return said.merging(Self.style(of: node)) { $1 }
    }

    private func isHidden(_ node: SVGTree) -> Bool {
        let style = style(of: node)
        func value(_ key: String) -> String? { style[key] ?? node.attributes[key] }
        return value("display") == "none" || value("visibility") == "hidden"
    }

    /// Whether the clip `reference` names cuts nothing the canvas shows, seen
    /// through `transform`: one square cornered box reaching past every edge.
    /// A design tool wraps whatever it exports in one, and so does a frame.
    private func clipCoversTheCanvas(_ reference: String, through transform: CGAffineTransform) -> Bool {
        let word = reference.trimmingCharacters(in: .whitespaces)
        guard word.hasPrefix("url("), let viewBox else { return false }
        let id = word.dropFirst(4).prefix { $0 != ")" }.trimmingCharacters(in: CharacterSet(charactersIn: "#'\" "))
        guard let clip = clips[id], clip.children.count == 1, let box = clip.children.first, box.name == "rect",
              clip.attributes["clipPathUnits"] == nil, clip.attributes["transform"] == nil,
              box.attributes["transform"] == nil, box.attributes["rx"] == nil, box.attributes["ry"] == nil
        else { return false }
        func number(_ key: String) -> CGFloat { box.attributes[key].flatMap(SVGNumbers.length) ?? 0 }
        let rect = CGRect(x: number("x"), y: number("y"), width: number("width"), height: number("height"))
        return rect.applying(transform).insetBy(dx: -0.01, dy: -0.01).contains(viewBox)
    }

    private mutating func collectClips(_ node: SVGTree) {
        if node.name == "clipPath", let id = node.attributes["id"] { clips[id] = node }
        for child in node.children { collectClips(child) }
    }

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
        if isHidden(node) { return }
        if Self.skipped.contains(node.name) {
            if Self.shownButNotRead.contains(node.name) { leftOut.insert(node.name) }
            return
        }
        let style = style(of: node)
        func value(_ key: String) -> String? { style[key] ?? node.attributes[key] }
        var state = given
        let own = node.attributes["transform"].map(SVGTransform.parse) ?? .identity
        for setting in Self.unreadSettings {
            guard let said = value(setting), said.trimmingCharacters(in: .whitespaces) != "none" else { continue }
            if setting == "clip-path", clipCoversTheCanvas(said, through: own.concatenating(given.transform)) { continue }
            leftOut.insert(setting.hasPrefix("marker") ? "marker" : setting)
        }
        if node.name == "svg" {
            if given.insideSVG { leftOut.insert("svg") }
            state.insideSVG = true
        }
        if let fill = value("fill") {
            state.fill = paint(fill)
            state.fillPaint = gradient(fill)
            if Self.isReference(fill), state.fillPaint == nil { leftOut.insert("paint") }
        }
        if let stroke = value("stroke") {
            state.stroke = paint(stroke)
            // A line paints with one colour, so a gradient on one is lost too.
            if Self.isReference(stroke) { leftOut.insert("paint") }
        }
        if let width = value("stroke-width").flatMap(SVGNumbers.length) { state.strokeWidth = width }
        if let o = value("opacity").flatMap(SVGNumbers.length) { state.opacity *= o }
        if let o = value("fill-opacity").flatMap(SVGNumbers.length) { state.fillOpacity = o }
        if let o = value("stroke-opacity").flatMap(SVGNumbers.length) { state.strokeOpacity = o }
        if let rule = value("fill-rule") { state.evenOdd = rule == "evenodd" }
        if let end = value("stroke-linecap").flatMap({ word in PathLineEnd.allCases.first { $0.svgName == word } }) {
            state.lineEnd = end
        }
        if let corner = value("stroke-linejoin").flatMap({ word in PathLineCorner.allCases.first { $0.svgName == word } }) {
            state.lineCorner = corner
        }
        if let transform = node.attributes["transform"] {
            state.transform = SVGTransform.parse(transform).concatenating(state.transform)
        }
        let id = node.attributes["id"].map(Self.readable)
        switch node.name {
        case "svg", "g", "a", "switch":
            if node.name == "g", let id {
                state.groupName = id
                if keepsGroups { state.groups.append(id) }
            }
            for child in node.children { walk(child, state) }
        case "path", "circle", "ellipse", "rect", "line", "polyline", "polygon":
            add(node, state, id: id)
        default:
            return
        }
    }

    private static func isReference(_ paint: String) -> Bool {
        paint.trimmingCharacters(in: .whitespaces).hasPrefix("url(")
    }

    /// The gradient a `url(#id)` fill names, following links to its stops.
    private func gradient(_ text: String) -> Paint? {
        let word = text.trimmingCharacters(in: .whitespaces)
        guard word.hasPrefix("url(") else { return nil }
        let inside = word.dropFirst(4).prefix { $0 != ")" }
        var id = String(inside.trimmingCharacters(in: CharacterSet(charactersIn: "#'\" ")))
        for _ in 0..<4 {
            if let paint = paints[id] { return paint }
            guard let found = gradients[id], found.hasPrefix("link:") else { return nil }
            id = String(found.dropFirst(5))
        }
        return nil
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
        let before = parts.count
        defer {
            let paint = node.name == "line" ? nil : state.fillPaint
            for index in before..<parts.count {
                if parts[index].fill != nil { parts[index].fillPaint = paint }
                parts[index].groups = state.groups
                parts[index].lineEnd = state.lineEnd
                parts[index].lineCorner = state.lineCorner
            }
        }
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
        node.attributes["style"].map(declarations) ?? [:]
    }

    /// `fill:none;stroke:#000` as what it says.
    static func declarations(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for declaration in text.split(separator: ";") {
            let pair = declaration.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { continue }
            out[pair[0].trimmingCharacters(in: .whitespacesAndNewlines)] = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// A width or height as a size in points, at the 96 to the inch SVG counts
    /// in: "24", "24px", "2in", "210mm". Nil for a percentage, or an em, which
    /// are about something outside the file.
    static func absoluteLength(_ text: String) -> CGFloat? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        let unit = String(trimmed.reversed().prefix { $0.isLetter || $0 == "%" }.reversed())
        guard let scale = pointsPerUnit[unit] else { return nil }
        var scanner = Scanner(String(trimmed.dropLast(unit.count)))
        return scanner.number().map { $0 * scale }
    }

    private static let pointsPerUnit: [String: CGFloat] = [
        "": 1, "px": 1, "pt": 4.0 / 3, "pc": 16, "in": 96, "cm": 96 / 2.54, "mm": 96 / 25.4,
    ]

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
            let values = SVGNumbers.list(String(word.drop { $0 != "(" }.dropFirst()).replacing("%", with: " "))
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

/// Landing a drawing on the whole units of a 24 unit picture, the pass an icon
/// designer makes by hand so each edge falls on the grid.
///
/// Every point rounds AWAY FROM THE MIDDLE of the artboard rather than from its
/// corner, so a drawing that mirrors keeps mirroring: 10.5 and 13.5 land on 10
/// and 14, where rounding from the corner gives 11 and 14 and leaves it half a
/// unit off centre. Nothing here knows what is drawn.
public struct IconGridLanding: Sendable {
    public let unit: CGFloat
    let middle: CGFloat

    /// The landing for an icon of this side, or nil where it has no 24 units.
    public init?(side: CGFloat) {
        guard side == IconUnits.pictureSide else { return nil }
        unit = side / IconKeylines.artboardSide
        middle = side / 2
    }

    func landing(_ point: CGPoint) -> CGPoint {
        CGPoint(x: middle + units(point.x - middle) * unit, y: middle + units(point.y - middle) * unit)
    }

    /// A corner, never rounded away to nothing.
    func length(_ value: CGFloat) -> CGFloat {
        max(1, units(value)) * unit
    }

    /// A line weight: one already on a half unit stays there, since a weight is
    /// not a place on the grid and 1.5 is a line icon sets use. Anything else
    /// comes to a whole unit, as a corner does.
    func weight(_ value: CGFloat) -> CGFloat {
        let halves = value / unit * 2
        guard abs(halves - halves.rounded()) < 1e-3 else { return length(value) }
        return max(1, halves.rounded() / 2) * unit
    }

    /// Whole units in `value`. A number that has been through a scale sits a
    /// hair either side of a half, so the hair goes first: both sides of a
    /// mirror have to round the same way.
    private func units(_ value: CGFloat) -> CGFloat {
        ((value / unit * 1e6).rounded() / 1e6).rounded()
    }
}
