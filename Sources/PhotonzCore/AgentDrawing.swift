import CoreGraphics
import Foundation

// The third slice of the agent tools (`docs/design/agent-mcp.md`): an agent
// builds a picture out of the same layers a person draws. Everything here is
// the pure half: what a call asks for, typed, and the layer it becomes. The
// app adds the layer through `EditorState.perform`, so it undoes like a click.

/// A colour an agent names: a hex, or none to take the paint away.
public enum AgentInk: Hashable, Sendable {
    case none
    case hex(String)

    /// "#RRGGBB", "#RRGGBBAA" or "none"; anything else is refused.
    public init?(_ text: String) {
        let word = text.trimmingCharacters(in: .whitespaces)
        if word.lowercased() == "none" { self = .none; return }
        guard word.hasPrefix("#"), word.count == 7 || word.count == 9, RGBA(hex: word) != nil else { return nil }
        self = .hex(word.uppercased())
    }

    public var hexValue: String? {
        if case .hex(let hex) = self { return hex }
        return nil
    }
}

/// A drop shadow an agent asks for, or none to take every shadow off.
public enum AgentShadow: Hashable, Sendable {
    case none
    case drop(ShadowStyle)
}

/// The paint and finish a shape, path or layer is given. Nil is "not said",
/// which leaves what is there (or the default, on a new layer).
public struct AgentLook: Hashable, Sendable {
    public var fill: AgentInk?
    public var stroke: AgentInk?
    public var strokeWidth: CGFloat?
    public var cornerRadius: CGFloat?
    public var opacity: Double?
    public var shadow: AgentShadow?

    public init(fill: AgentInk? = nil, stroke: AgentInk? = nil, strokeWidth: CGFloat? = nil,
                cornerRadius: CGFloat? = nil, opacity: Double? = nil, shadow: AgentShadow? = nil) {
        self.fill = fill
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.shadow = shadow
    }

    var isEmpty: Bool { self == AgentLook() }
}

/// One of the shape tool's shapes. A box, an oval and a highlight are given
/// a frame; a line and an arrow are given their two ends.
public struct AgentShape: Hashable, Sendable {
    public var kind: AnnotationShape
    public var frame: CGRect?
    public var from: CGPoint?
    public var to: CGPoint?
    public var look: AgentLook
    public var name: String?

    public init(kind: AnnotationShape, frame: CGRect? = nil, from: CGPoint? = nil, to: CGPoint? = nil,
                look: AgentLook = AgentLook(), name: String? = nil) {
        self.kind = kind
        self.frame = frame
        self.from = from
        self.to = to
        self.look = look
        self.name = name
    }
}

/// One point of a path, in canvas points from the top left.
public struct AgentPathPoint: Hashable, Sendable {
    public var point: CGPoint
    /// Smooth points are given handles along the line through their
    /// neighbours unless the call gives handles of its own.
    public var smooth: Bool
    /// Offsets from `point`, as the Pen stores them.
    public var handleIn: CGPoint?
    public var handleOut: CGPoint?
    public var cornerRadius: CGFloat

    public init(_ point: CGPoint, smooth: Bool = false, handleIn: CGPoint? = nil,
                handleOut: CGPoint? = nil, cornerRadius: CGFloat = 0) {
        self.point = point
        self.smooth = smooth
        self.handleIn = handleIn
        self.handleOut = handleOut
        self.cornerRadius = cornerRadius
    }
}

/// A path as the Pen would draw it: points in order, open or closed.
public struct AgentPath: Hashable, Sendable {
    public var points: [AgentPathPoint]
    public var closed: Bool
    public var look: AgentLook
    public var name: String?

    public init(points: [AgentPathPoint], closed: Bool, look: AgentLook = AgentLook(), name: String? = nil) {
        self.points = points
        self.closed = closed
        self.look = look
        self.name = name
    }
}

/// Words set at a point, the way the Text tool's click sets them.
public struct AgentText: Hashable, Sendable {
    public var string: String
    public var origin: CGPoint
    public var fontSize: CGFloat
    public var fontName: String?
    public var weight: TextWeight?
    public var colorHex: String?
    public var alignment: TextAlign?
    /// Wrap at this width; one natural line per paragraph when nil.
    public var width: CGFloat?
    public var name: String?
    /// The soft shadow the Text tool puts under every word so it reads on
    /// any picture (`TextBuilder.autoContrastShadow`). An icon turns it off:
    /// an SVG can only carry shadowed words as a picture of them.
    public var shadow: Bool

    public init(string: String, origin: CGPoint, fontSize: CGFloat = 24, fontName: String? = nil,
                weight: TextWeight? = nil, colorHex: String? = nil, alignment: TextAlign? = nil,
                width: CGFloat? = nil, name: String? = nil, shadow: Bool = true) {
        self.shadow = shadow
        self.string = string
        self.origin = origin
        self.fontSize = fontSize
        self.fontName = fontName
        self.weight = weight
        self.colorHex = colorHex
        self.alignment = alignment
        self.width = width
        self.name = name
    }

    /// The text content this becomes, before the app measures its box.
    public var content: TextContent {
        var content = TextContent(string: string, fontName: fontName ?? "SF Pro", fontSize: fontSize,
                                  colorHex: colorHex ?? "#1C1C1E", weight: weight ?? .regular,
                                  alignment: alignment)
        content.string = string
        return content
    }
}

/// What set_layer changes. Nil is "leave it".
public struct AgentLayerChange: Hashable, Sendable {
    public var x: CGFloat?
    public var y: CGFloat?
    public var width: CGFloat?
    public var height: CGFloat?
    public var name: String?
    public var visible: Bool?
    public var look: AgentLook
    public var text: String?
    public var fontSize: CGFloat?
    /// Mirror it about its own middle, as Edit ▸ Transform ▸ Flip does: once
    /// per axis named.
    public var flip: Set<FlipAxis>

    public init(x: CGFloat? = nil, y: CGFloat? = nil, width: CGFloat? = nil, height: CGFloat? = nil,
                name: String? = nil, visible: Bool? = nil, look: AgentLook = AgentLook(),
                text: String? = nil, fontSize: CGFloat? = nil, flip: Set<FlipAxis> = []) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.name = name
        self.visible = visible
        self.look = look
        self.text = text
        self.fontSize = fontSize
        self.flip = flip
    }

    public var movesOrSizes: Bool { x != nil || y != nil || width != nil || height != nil }
    /// Whether the words or their size changed, so the box has to be measured again.
    public var changesTheWords: Bool { text != nil || fontSize != nil }
}

/// A measurement the Measure tool would place, said the way an agent can say it.
public enum AgentMeasurement: Hashable, Sendable {
    /// Size mode on a box: a width and a height caliper around it.
    case size(CGRect)
    /// Size mode's click: the element under the point, read off the picture
    /// (and the drawn layers) the way the tool reads it. `level` climbs out
    /// to the thing holding it, as `]` does.
    case sizeAt(CGPoint, level: Int)
    /// The space between two boxes, measured across where they face.
    case gap(CGRect, CGRect)
    /// Gap mode's click: the space around the point, read off the picture.
    case gapAt(CGPoint)
    /// A caliper between two points along one axis.
    case distance(from: CGPoint, to: CGPoint, axis: MeasureMode)
}

/// How a picture leaves the app.
public enum AgentExportFormat: String, CaseIterable, Hashable, Sendable {
    case png
    case svg
    /// A video, written as it plays (`AgentVideo.swift`).
    case mp4
}

// MARK: - Building the layers

public enum AgentDrawing {

    /// What a new box or oval is filled with when the call names no paint at all.
    public static let defaultFillHex = "#0A84FF"
    /// What a new line, arrow or open path is drawn in when the call names none.
    public static let defaultStrokeHex = "#1C1C1E"

    /// The layer an add_shape call becomes: the shape tool's own layer, so a
    /// person can pick it up and edit it afterwards like any they drew.
    public static func layer(for shape: AgentShape) -> Layer {
        let look = shape.look
        let start: CGPoint
        let end: CGPoint
        switch shape.kind {
        case .rectangle, .ellipse, .highlight:
            let box = (shape.frame ?? .zero).standardized
            start = box.origin
            end = CGPoint(x: box.maxX, y: box.maxY)
        case .line, .arrow:
            start = shape.from ?? .zero
            end = shape.to ?? .zero
        }
        let hasInside = shape.kind == .rectangle || shape.kind == .ellipse
        let strokeHex = look.stroke?.hexValue
        let fillHex = look.fill?.hexValue
        var content: AnnotationContent
        if hasInside {
            // A box with nothing said is a filled box; one with only an edge
            // said is an outline.
            let fill = look.fill == nil && look.stroke == nil ? defaultFillHex : fillHex
            let width = strokeHex == nil ? 0 : (look.strokeWidth ?? 2)
            content = AnnotationContent(shape: shape.kind, strokeWidth: width,
                                        colorHex: strokeHex ?? fill ?? defaultStrokeHex,
                                        cornerRadii: CornerRadii(shape.kind == .rectangle ? (look.cornerRadius ?? 0) : 0),
                                        fillColorHex: fill)
        } else {
            let ink = strokeHex ?? fillHex ?? (shape.kind == .highlight ? "#FFD60A" : defaultStrokeHex)
            content = AnnotationContent(shape: shape.kind,
                                        strokeWidth: look.strokeWidth ?? (shape.kind == .highlight ? 16 : 4),
                                        colorHex: ink)
        }
        var layer = AnnotationBuilder.layer(content: content, from: start, to: end)
        if let name = shape.name { layer.name = name }
        apply(look, keepingPaint: true, to: &layer)
        return layer
    }

    /// The anchors a path call becomes, in canvas points, with a smooth point's
    /// handles worked out from its neighbours where the call gave none.
    public static func anchors(for path: AgentPath) -> [PathAnchor] {
        let points = path.points.map(\.point)
        let count = points.count
        return path.points.enumerated().map { index, spec in
            var anchor = PathAnchor(point: spec.point, handleIn: spec.handleIn, handleOut: spec.handleOut,
                                    kind: spec.smooth ? .smooth : .corner, cornerRadius: max(0, spec.cornerRadius))
            if spec.smooth, spec.handleIn == nil, spec.handleOut == nil, count > 2 {
                // A Catmull-Rom curve through the points: each handle a sixth
                // of the way between the neighbours either side.
                let before = index > 0 ? points[index - 1] : (path.closed ? points[count - 1] : spec.point)
                let after = index < count - 1 ? points[index + 1] : (path.closed ? points[0] : spec.point)
                let tangent = CGPoint(x: (after.x - before.x) / 6, y: (after.y - before.y) / 6)
                anchor.handleOut = tangent
                anchor.handleIn = CGPoint(x: -tangent.x, y: -tangent.y)
            }
            return anchor
        }
    }

    /// The layer an add_path call becomes: the Pen's own layer, boxed round the
    /// shape it covers.
    public static func layer(for path: AgentPath) -> Layer {
        let look = path.look
        let strokeHex = look.stroke?.hexValue
        let fillHex = look.fill?.hexValue
        let content: PathContent
        if path.closed {
            let fill = look.fill == nil && look.stroke == nil ? defaultFillHex : fillHex
            content = PathContent(anchors: anchors(for: path), isClosed: true,
                                  paint: Paint(hex: strokeHex ?? fill ?? defaultStrokeHex),
                                  strokeWidth: strokeHex == nil ? 0 : (look.strokeWidth ?? 2),
                                  fill: fill.map { Paint(hex: $0) })
        } else {
            content = PathContent(anchors: anchors(for: path), isClosed: false,
                                  paint: Paint(hex: strokeHex ?? fillHex ?? defaultStrokeHex),
                                  strokeWidth: look.strokeWidth ?? 2, fill: nil)
        }
        var layer = PathBuilder.layer(content, at: content.bounds.origin)
        if let name = path.name { layer.name = name }
        apply(look, keepingPaint: true, to: &layer)
        return layer
    }

    /// A set_layer call landed on `layer`, or the sentence saying why it cannot.
    /// The words of a text layer are changed here; the app measures their box.
    /// Where a layer is, in its parent's space: a leaf's frame, a group's
    /// box (what it holds plus its padding, from its anchor; a group's stored
    /// size is unused). `localBounds` is already in the parent's space, so it
    /// is never shifted by the anchor again.
    public static func box(of layer: Layer) -> CGRect {
        layer.isGroup ? layer.localBounds : layer.frame
    }

    public static func applying(_ change: AgentLayerChange, to layer: Layer,
                                canvas: CGSize?) -> Result<Layer, AgentToolError> {
        var layer = layer
        if change.movesOrSizes {
            let box = box(of: layer)
            let frame = CGRect(x: change.x ?? box.minX, y: change.y ?? box.minY,
                               width: change.width ?? box.width, height: change.height ?? box.height)
            guard frame.width > 0, frame.height > 0 else {
                return .failure(AgentToolError("set_layer: width and height must be more than 0."))
            }
            if change.width == nil, change.height == nil {
                layer.frame.origin.x += frame.minX - box.minX
                layer.frame.origin.y += frame.minY - box.minY
            } else {
                layer = layer.geometrySet(to: frame, canvas: canvas, byHand: true)
            }
        }
        if let name = change.name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .failure(AgentToolError("set_layer: a name cannot be empty.")) }
            layer.name = trimmed
        }
        if let visible = change.visible { layer.isVisible = visible }
        if change.text != nil || change.fontSize != nil {
            guard var text = layer.text else {
                return .failure(AgentToolError("set_layer: text and fontSize only apply to a text layer, and \(layer.name) is not one."))
            }
            if let words = change.text { text.string = words }
            if let size = change.fontSize { text.fontSize = size }
            layer.content = .text(text)
        }
        if let problem = refusal(change.look, for: layer) { return .failure(AgentToolError("set_layer: \(problem)")) }
        apply(change.look, keepingPaint: false, to: &layer)
        if !change.flip.isEmpty {
            guard layer.canBeMirrored else {
                return .failure(AgentToolError("set_layer: \(layer.name) is a reading of the picture, which a flip would point at something else."))
            }
            for axis in FlipAxis.allCases where change.flip.contains(axis) {
                layer = layer.flipped(axis, at: axis.mid(layer.flipBox))
            }
        }
        return .success(layer)
    }

    /// Why `look` cannot land on `layer`, or nil when it can.
    static func refusal(_ look: AgentLook, for layer: Layer) -> String? {
        if look.fill != nil, !takesFill(layer) {
            return "\(layer.name) has no inside to fill."
        }
        if look.stroke != nil || look.strokeWidth != nil, layer.text != nil {
            return "a text layer has no line round it; use fill for the colour of the words."
        }
        return nil
    }

    static func takesFill(_ layer: Layer) -> Bool {
        if let annotation = layer.annotation { return annotation.shape == .rectangle || annotation.shape == .ellipse }
        if let path = layer.path { return path.isClosed }
        return layer.text != nil
    }

    /// Puts `look` on `layer`. `keepingPaint` is the add tools' case, where
    /// the paint already went into the content when it was built.
    static func apply(_ look: AgentLook, keepingPaint: Bool, to layer: inout Layer) {
        if let opacity = look.opacity { layer.style.opacity = min(1, max(0, opacity)) }
        switch look.shadow {
        case .none?: layer.style.shadows = []
        case .drop(let shadow)?: layer.style.shadow = shadow
        case nil: break
        }
        if keepingPaint { return }
        if var annotation = layer.annotation {
            let hasInside = annotation.shape == .rectangle || annotation.shape == .ellipse
            if let fill = look.fill { annotation.fill = fill.hexValue.map { Paint(hex: $0) } }
            if let radius = look.cornerRadius, annotation.shape == .rectangle {
                annotation.cornerRadii = CornerRadii(max(0, radius))
            }
            if hasInside {
                // A box's edge is its Border, which is where the shape tool
                // puts it too (`OutlineRetirement.swift`).
                switch look.stroke {
                case .none?: layer.style.borderWidth = 0
                case .hex(let hex)?:
                    if layer.style.borderWidth == 0 { layer.style.borderWidth = look.strokeWidth ?? 2 }
                    layer.style.borderColorHex = hex
                case nil: break
                }
                if let width = look.strokeWidth, look.stroke != AgentInk.none { layer.style.borderWidth = max(0, width) }
            } else {
                if let hex = look.stroke?.hexValue ?? look.fill?.hexValue { annotation.colorHex = hex; annotation.headColorHex = hex }
                if let width = look.strokeWidth { annotation.strokeWidth = max(0.5, width) }
            }
            layer.content = .annotation(annotation)
        } else if var path = layer.path {
            if let fill = look.fill { path.fill = fill.hexValue.map { Paint(hex: $0) } }
            switch look.stroke {
            case .none?: path.strokeWidth = 0
            case .hex(let hex)?:
                path.paint = Paint(hex: hex)
                if path.strokeWidth == 0 { path.strokeWidth = look.strokeWidth ?? 2 }
            case nil: break
            }
            if let width = look.strokeWidth, look.stroke != AgentInk.none { path.strokeWidth = max(0, width) }
            if let radius = look.cornerRadius {
                for index in path.anchors.indices { path.anchors[index].cornerRadius = max(0, radius) }
            }
            layer.content = .path(path)
        } else if var text = layer.text {
            if let hex = look.fill?.hexValue { text.colorHex = hex }
            layer.content = .text(text)
        } else {
            // A picture, a group or a component: the edge and the corners are
            // the layer's own style.
            if let radius = look.cornerRadius { layer.style.cornerRadius = max(0, radius) }
            switch look.stroke {
            case .none?: layer.style.borderWidth = 0
            case .hex(let hex)?:
                if layer.style.borderWidth == 0 { layer.style.borderWidth = look.strokeWidth ?? 2 }
                layer.style.borderColorHex = hex
            case nil: break
            }
            if let width = look.strokeWidth, look.stroke != AgentInk.none { layer.style.borderWidth = max(0, width) }
        }
    }
}

// MARK: - Measuring

public enum AgentMeasurePlan {

    /// The space between two boxes, across where they face each other: side by
    /// side reads across, one above the other reads down. Nil when they overlap
    /// or sit corner to corner with nothing facing.
    public static func gap(between a: CGRect, and b: CGRect) -> GapMeasurement? {
        let a = a.standardized, b = b.standardized
        let (left, right) = a.midX <= b.midX ? (a, b) : (b, a)
        let (top, bottom) = a.midY <= b.midY ? (a, b) : (b, a)
        let overlapY = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let overlapX = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        if right.minX >= left.maxX, overlapY > 0 {
            let y = ((max(a.minY, b.minY) + min(a.maxY, b.maxY)) / 2).rounded()
            return GapMeasurement(axis: .horizontal, start: CGPoint(x: left.maxX, y: y),
                                  end: CGPoint(x: right.minX, y: y))
        }
        if bottom.minY >= top.maxY, overlapX > 0 {
            let x = ((max(a.minX, b.minX) + min(a.maxX, b.maxX)) / 2).rounded()
            return GapMeasurement(axis: .vertical, start: CGPoint(x: x, y: top.maxY),
                                  end: CGPoint(x: x, y: bottom.minY))
        }
        return nil
    }

    /// How far a measured side may sit from an edge in the picture and still
    /// count as on it, in image pixels: a two pixel border has two flanks and
    /// the edge map can name either.
    public static let edgeTolerance: Double = 3

    /// How many of `box`'s four sides land on an edge the picture really has.
    public static func sidesOnEdges(_ box: CGRect, in edges: EdgeMap,
                                    tolerance: Double = edgeTolerance) -> Int {
        guard !edges.isEmpty, box.width > 0, box.height > 0 else { return 0 }
        let vertical = edges.verticalEdges(inYRange: Double(box.minY)...Double(box.maxY))
        let horizontal = edges.horizontalEdges(inXRange: Double(box.minX)...Double(box.maxX))
        func near(_ value: CGFloat, _ list: [EdgeCandidate]) -> Bool {
            list.contains { abs($0.position - Double(value)) <= tolerance }
        }
        return [near(box.minX, vertical), near(box.maxX, vertical),
                near(box.minY, horizontal), near(box.maxY, horizontal)].filter { $0 }.count
    }

    /// How many of a caliper's two feet land on an edge the picture really has.
    public static func feetOnEdges(from start: CGPoint, to end: CGPoint, axis: MeasureMode,
                                   in edges: EdgeMap, tolerance: Double = edgeTolerance) -> Int {
        guard !edges.isEmpty else { return 0 }
        let reach = 6.0
        func on(_ foot: CGPoint) -> Bool {
            switch axis {
            case .horizontal:
                let list = edges.verticalEdges(inYRange: Double(foot.y) - reach...Double(foot.y) + reach)
                return list.contains { abs($0.position - Double(foot.x)) <= tolerance }
            case .vertical:
                let list = edges.horizontalEdges(inXRange: Double(foot.x) - reach...Double(foot.x) + reach)
                return list.contains { abs($0.position - Double(foot.y)) <= tolerance }
            }
        }
        return [on(start), on(end)].filter { $0 }.count
    }

    /// The element the Measure tool's Size mode would pick at `point`: a
    /// drawn layer first and exactly, then the picture read outwards from it.
    public static func element(at point: CGPoint, level: Int, edges: EdgeMap, luma: LumaField,
                               document: PhotonzDocument) -> CGRect? {
        let scale = max(1, document.pixelScale)
        let picture = ElementBounds.ladder(at: point, in: edges, luma: luma,
                                           minElement: max(10, 10 * document.pixelScale),
                                           textGap: AlignmentScan.visibleGap * scale,
                                           readsShapes: true)
        let drawn = LayerElements.candidates(at: point, in: document)
        let ladder = drawn.isEmpty
            ? picture
            : ElementBounds.Ladder(rungs: LayerElements.merged(
                drawn: drawn, picture: Array(picture.rungs.dropFirst(picture.start))))
        return ladder.rung(level)
    }

    /// What a Size measurement's two readouts steer round, gathered the way
    /// the canvas gathers it for a click (`CanvasMeasure.neighbors`): the
    /// elements touching `rect`, the ones as far out as a number will travel,
    /// and the drawn layers beside it. With fewer, an agent's numbers land on
    /// the next control where a click's do not.
    public static func sizeNeighbors(of rect: CGRect, style: MeasureContent, edges: EdgeMap, luma: LumaField,
                                     document: PhotonzDocument) -> [CGRect] {
        let canvas = document.canvasSize
        var width = style
        width.mode = .horizontal
        var height = style
        height.mode = .vertical
        let widthHead = MeasureBuilder.clearingHeadOffset(content: width, from: CGPoint(x: rect.minX, y: rect.maxY),
                                                          to: CGPoint(x: rect.maxX, y: rect.maxY), canvas: canvas)
        let heightHead = MeasureBuilder.clearingHeadOffset(content: height, from: CGPoint(x: rect.maxX, y: rect.minY),
                                                           to: CGPoint(x: rect.maxX, y: rect.maxY), canvas: canvas)
        let reach = max(abs(widthHead) + width.estimatedLabelSize.height / 2,
                        abs(heightHead) + height.estimatedLabelSize.width / 2)
        let scale = max(1, document.pixelScale)
        var found = edges.isEmpty || luma.isEmpty ? [] : ElementBounds.neighbors(
            of: rect, in: edges, luma: luma, minElement: max(10, 10 * scale),
            textGap: AlignmentScan.visibleGap * scale,
            reaches: [ElementBounds.neighborProbeReach, Double(reach)], readsShapes: true)
        let drawn = LayerElements.neighbors(of: rect, in: document, reach: reach)
        found += drawn.filter { box in !found.contains { $0.intersects(box) } }
        return found
    }

    /// Gap mode's click at `point`: the space around it, read off the picture
    /// and the drawn layers together.
    public static func gap(at point: CGPoint, luma: LumaField, document: PhotonzDocument) -> GapMeasurement? {
        ElementBounds.gap(at: point, luma: luma, drawn: LayerElements.boxes(in: document),
                          textGap: AlignmentScan.visibleGap * max(1, document.pixelScale))
    }
}

// MARK: - Finding what is in a picture

public enum AgentElementScan {

    public static let defaultLimit = 40
    /// The smallest element worth listing, in points on a side.
    public static let smallest: CGFloat = 12

    /// The elements the Measure tool can see across `region` (the whole canvas
    /// when nil): the picture read at a grid of points the way Size mode reads
    /// under the pointer, plus every drawn layer's box. Largest first, each
    /// listed once.
    public static func elements(in document: PhotonzDocument, edges: EdgeMap, luma: LumaField,
                                region: CGRect? = nil, limit: Int = defaultLimit,
                                across: Int = 16) -> [CGRect] {
        let canvas = CGRect(origin: .zero, size: document.canvasSize)
        let area = (region ?? canvas).intersection(canvas)
        guard !area.isNull, area.width >= 1, area.height >= 1, limit > 0 else { return [] }
        var found: [CGRect] = []
        // Two reads of one element can disagree by a border's width, more on
        // a big capture.
        let slack = max(4, max(canvas.width, canvas.height) / 150)
        // A point inside a small element already read reads the same element
        // again, so it is skipped: each probe costs a few milliseconds. Only a
        // small one: a card read from its background still holds the buttons.
        var innermost: [CGRect] = []
        func keep(_ rect: CGRect) {
            let rect = rect.integral.intersection(canvas)
            guard !rect.isNull, rect.width >= smallest, rect.height >= smallest,
                  rect.intersects(area),
                  rect.width * rect.height < canvas.width * canvas.height * 0.9 else { return }
            if found.contains(where: { same($0, rect, slack: slack) }) { return }
            found.append(rect)
        }
        for box in LayerElements.boxes(in: document) { keep(box) }
        if !edges.isEmpty, !luma.isEmpty {
            let minElement = Double(max(10, 10 * document.pixelScale))
            let textGap = Double(AlignmentScan.visibleGap * max(1, document.pixelScale))
            // The straight reads already read again, so a long row is
            // re-read once, not at every probe along it.
            var reread: [CGRect] = []
            func probe(_ point: CGPoint, shapes: Bool, step: CGFloat) {
                if innermost.contains(where: { $0.contains(point) }) { return }
                // A label and the control around it is as far up as the
                // first rung ever looks.
                let ladder = ElementBounds.ladder(at: point, in: edges, luma: luma, minElement: minElement,
                                                  textGap: textGap, limit: 2, readsShapes: shapes)
                // The element a click there would measure; what holds it is
                // read from a probe on the holder's own background.
                guard let first = ladder.rung(0) else { return }
                // Something control-sized or thin is read again with the shape
                // reader, once per element rather than per probe. That reader is the
                // one Size mode clicks with, so its box is the one listed: it
                // takes a field's outer border where the straight reader can
                // take the inner one, and sees a switch's round pill. The
                // straight read is kept too where it found something else
                // (a switch, where the round read is its knob).
                if !shapes, first.width < step * 2 || first.height < step * 2,
                   !reread.contains(where: { same($0, first, slack: slack) }),
                   let round = ElementBounds.ladder(at: point, in: edges, luma: luma, minElement: minElement,
                                                    textGap: textGap, limit: 2, readsShapes: true).rung(0) {
                    reread.append(first)
                    keep(round)
                }
                keep(first)
                if first.width < step * 2, first.height < step * 2 { innermost.append(first) }
            }
            // Straight-edged things first, densely: rows, fields, buttons,
            // switches and lines of words, at a few milliseconds a probe.
            let step = max(8, max(area.width, area.height) / CGFloat(max(4, across)))
            for y in rows(in: area, edges: edges, step: step) {
                var x = area.minX + step / 2
                while x < area.maxX { probe(CGPoint(x: x, y: y), shapes: false, step: step); x += step }
            }
            // Then round-cornered cards, avatars and icons, which only the
            // shape reader sees and which costs many times more a probe, on a
            // grid half as fine.
            let coarse = step * 2
            var y = area.minY + coarse / 2
            while y < area.maxY {
                var x = area.minX + coarse / 2
                while x < area.maxX { probe(CGPoint(x: x, y: y), shapes: true, step: step); x += coarse }
                y += coarse
            }
        }
        return Array(found.sorted { $0.width * $0.height > $1.width * $1.height }.prefix(limit))
    }

    /// The heights the probes run along: the middle of every band between two
    /// of the picture's own horizontal edges, so a control shorter than the
    /// grid still has a row of probes through it, and rows half a step apart
    /// besides, for a control whose own edges are too short to show across
    /// the whole picture (a switch at the end of a row).
    public static func rows(in area: CGRect, edges: EdgeMap, step: CGFloat) -> [CGFloat] {
        let lines = edges.horizontalEdges(inXRange: Double(area.minX)...Double(area.maxX))
            .map { CGFloat($0.position) }
            .filter { $0 > area.minY && $0 < area.maxY }
            .sorted()
        let bounds = [area.minY] + lines + [area.maxY]
        var rows: [CGFloat] = []
        for (top, bottom) in zip(bounds, bounds.dropFirst()) where bottom - top >= smallest {
            rows.append(((top + bottom) / 2).rounded())
        }
        var y = area.minY + step / 4
        while y < area.maxY {
            if !rows.contains(where: { abs($0 - y) < step / 8 }) { rows.append(y.rounded()) }
            y += step / 2
        }
        return rows.sorted()
    }

    /// Whether two boxes are the same element, read twice.
    static func same(_ a: CGRect, _ b: CGRect, slack: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= slack && abs(a.minY - b.minY) <= slack
            && abs(a.maxX - b.maxX) <= slack && abs(a.maxY - b.maxY) <= slack
    }
}
