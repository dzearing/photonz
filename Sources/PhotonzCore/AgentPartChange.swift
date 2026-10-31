import CoreGraphics
import Foundation

/// change_part: one named part of something already made, changed in place
/// ("make the water bluer", "make the sun bigger", "less clouds"). A part is
/// found by the name it was made with, never by words coded here: on a
/// painting, the strokes whose `part` the sketch named; on a drawing, the
/// layers of that name. Its colour moves toward the one asked for (or by
/// hue, saturation and lightness) with every shade in it kept, it grows or
/// shrinks about its own middle, moves, or comes out. Nothing else moves.
public struct AgentPartChange: Hashable, Sendable {
    /// What to change, as read_document names it ("water", "Sun").
    public var part: String
    /// A layer's id to look in: a paint layer, or a group holding the part.
    /// Nil looks through the whole document.
    public var layer: String?
    /// "#RRGGBB": the part's main colour becomes this, each shade in it
    /// keeping how much lighter or darker it was.
    public var colorHex: String?
    /// Degrees round the colour wheel, -180 to 180.
    public var hue: Double?
    /// -100 to 100: greyer to stronger.
    public var saturation: Double?
    /// -100 to 100: darker to lighter.
    public var lightness: Double?
    /// How many times its size, about its own middle.
    public var scale: Double?
    public var dx: Double?
    public var dy: Double?
    public var remove: Bool

    public init(part: String, layer: String? = nil, colorHex: String? = nil, hue: Double? = nil,
                saturation: Double? = nil, lightness: Double? = nil, scale: Double? = nil,
                dx: Double? = nil, dy: Double? = nil, remove: Bool = false) {
        self.part = part
        self.layer = layer
        self.colorHex = colorHex
        self.hue = hue
        self.saturation = saturation
        self.lightness = lightness
        self.scale = scale
        self.dx = dx
        self.dy = dy
        self.remove = remove
    }

    var recolours: Bool { colorHex != nil || hue != nil || saturation != nil || lightness != nil }
    var moves: Bool { (dx ?? 0) != 0 || (dy ?? 0) != 0 }
    var changesAnything: Bool { remove || recolours || moves || (scale.map { $0 != 1 } ?? false) }

    // MARK: Names

    /// Lowercased words, each without a plural s, no trailing number: "Cloud
    /// 2", "clouds" and "cloud" all read as ["cloud"].
    static func words(_ name: String) -> [String] {
        var words = name.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        while let last = words.last, last.allSatisfy(\.isNumber), words.count > 1 { words.removeLast() }
        return words.map { word in
            word.count > 3 && word.hasSuffix("s") && !word.hasSuffix("ss") ? String(word.dropLast()) : word
        }
    }

    /// Whether `name` is the part asked for or a piece of it: "sun" takes in
    /// "Sun", "Sun 2" and "Sun glow"; "sea" never takes in "Seagull".
    func names(_ name: String) -> Bool {
        let asked = Self.words(part), own = Self.words(name)
        guard !asked.isEmpty, own.count >= asked.count else { return false }
        return Array(own.prefix(asked.count)) == asked
    }
}

/// What change_part did.
public struct AgentPartChanged: Encodable, Hashable, Sendable {
    public let part: String
    /// Painted strokes changed, when the part was painted.
    public let strokes: Int?
    /// Layers changed, when the part was layers.
    public let layers: Int?
}

extension AgentTools {

    static let partTools: [AgentTool] = [
        AgentTool(
            name: "change_part",
            description: "Change one part of something already made, in place: a painting's strokes of that part, or the layers of that name in a drawing (read_document lists a painting's parts and every layer's name). Recolour it toward color, keeping its shading, or shift its hue, saturation or lightness; grow or shrink it about its middle with scale; move it by dx and dy; or remove it. Nothing else moves. One undo step.",
            inputSchema: ["type": "object", "properties": [
                "document": ["type": "string",
                             "description": "The document's id from list_documents, such as d1. Leave it out to use the document in front."],
                "part": ["type": "string", "description": "The part by its name in read_document: a painting's part (water, sun) or a layer's name."],
                "layer": ["type": "string", "description": "A layer's id to look in: the painting's paint layer, or the drawing's group. Left out, the whole document."],
                "color": ["type": "string", "description": "#RRGGBB: the part's main colour becomes this; its lighter and darker shades keep their difference."],
                "hue": ["type": "number", "minimum": -180, "maximum": 180, "description": "Turn its colours round the colour wheel by this many degrees."],
                "saturation": ["type": "number", "minimum": -100, "maximum": 100, "description": "Greyer (below 0) or stronger (above 0)."],
                "lightness": ["type": "number", "minimum": -100, "maximum": 100, "description": "Darker (below 0) or lighter (above 0)."],
                "scale": ["type": "number", "minimum": .number(0.1), "maximum": 10, "description": "Times its size, about its own middle: 1.5 is half as big again, 0.5 half the size."],
                "dx": ["type": "number", "description": "Move it right by this many points (left below 0)."],
                "dy": ["type": "number", "description": "Move it down by this many points (up below 0)."],
                "remove": ["type": "boolean", "description": "Take the part away."],
            ], "required": ["part"], "additionalProperties": false]),
    ]

    static let partToolNames: Set<String> = Set(partTools.map(\.name))

    static func partRequest(_ name: String, _ args: [String: AgentJSON],
                            document: String?) -> Result<AgentRequest, AgentToolError> {
        func fail(_ words: String) -> Result<AgentRequest, AgentToolError> { .failure(AgentToolError("\(name): \(words)")) }
        let part = (args["part"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !part.isEmpty else { return fail("say which part, by its name in read_document.") }
        var change = AgentPartChange(part: part, layer: args["layer"]?.stringValue)
        if let word = args["color"]?.stringValue {
            guard case .hex(let hex)? = AgentInk(word), hex.count == 7 else { return fail("color is \(word); give #RRGGBB.") }
            change.colorHex = hex.uppercased()
        }
        change.hue = args["hue"]?.doubleValue
        change.saturation = args["saturation"]?.doubleValue
        change.lightness = args["lightness"]?.doubleValue
        change.scale = args["scale"]?.doubleValue
        change.dx = args["dx"]?.doubleValue
        change.dy = args["dy"]?.doubleValue
        change.remove = args["remove"]?.boolValue ?? false
        if let scale = change.scale, !(0.1...10).contains(scale) { return fail("scale runs 0.1 to 10.") }
        guard change.changesAnything else {
            return fail("say what to change: color, hue, saturation, lightness, scale, dx and dy, or remove.")
        }
        if change.remove, change.recolours || change.moves || change.scale != nil {
            return fail("remove takes the part away; give it alone.")
        }
        return .success(.changePart(document: document, change: change))
    }
}

extension PhotonzDocument {

    /// Lands a change_part call: on the painted strokes of that part when a
    /// paint layer in reach has them, otherwise on the layers of that name.
    public mutating func agentChangePart(_ change: AgentPartChange) -> Result<AgentPartChanged, AgentToolError> {
        var scope: Layer?
        if let named = change.layer {
            guard let id = UUID(uuidString: named), let layer = layer(id: id) else {
                return .failure(AgentToolError("change_part: there is no layer \(named). read_document lists the layers."))
            }
            scope = layer
        }
        let candidates = scope.map { [$0] } ?? layers
        // A painting's strokes first.
        var paintLayers: [UUID] = []
        var painted: [String] = []
        func walk(_ layer: Layer) {
            if let paint = layer.paint {
                if paint.strokes.contains(where: { $0.part.map(change.names) ?? false }) { paintLayers.append(layer.id) }
                for stroke in paint.strokes { if let part = stroke.part, !painted.contains(part) { painted.append(part) } }
            }
            for child in layer.group?.children ?? [] { walk(child) }
        }
        candidates.forEach(walk)
        if !paintLayers.isEmpty {
            var count = 0
            for id in paintLayers {
                if layer(id: id)?.isLocked == true {
                    return .failure(AgentToolError("change_part: \(layer(id: id)?.name ?? "that layer") is locked."))
                }
                updateLayer(id: id) { layer in
                    guard var paint = layer.paint else { return }
                    count += Self.changing(&paint, change)
                    layer.content = .paint(paint)
                }
            }
            return .success(AgentPartChanged(part: change.part, strokes: count, layers: nil))
        }
        // A drawing's layers of that name, outermost only.
        var named: [UUID] = []
        var names: [String] = []
        func find(_ layer: Layer, inside: Bool) {
            if inside, change.names(layer.name) {
                named.append(layer.id)
                return
            }
            if inside, !names.contains(layer.name) { names.append(layer.name) }
            for child in layer.group?.children ?? [] { find(child, inside: true) }
        }
        for layer in candidates { find(layer, inside: scope == nil || layer.id != scope?.id || layer.group == nil) }
        guard !named.isEmpty else {
            let known = (painted + names).prefix(24)
            let listed = known.isEmpty ? "" : " The parts there are: \(known.joined(separator: ", "))."
            return .failure(AgentToolError("change_part: nothing is called \(change.part).\(listed)"))
        }
        if let locked = named.compactMap({ layer(id: $0) }).first(where: \.isLocked) {
            return .failure(AgentToolError("change_part: \(locked.name) is locked."))
        }
        if change.remove {
            removeLayers(ids: Set(named))
            return .success(AgentPartChanged(part: change.part, strokes: nil, layers: named.count))
        }
        let canvas = canvasSize
        for id in named {
            updateLayer(id: id) { layer in layer = Self.changing(layer, change, canvas: canvas) }
        }
        return .success(AgentPartChanged(part: change.part, strokes: nil, layers: named.count))
    }

    // MARK: Painted parts

    /// Changes the strokes of `change.part` in `paint`; how many it changed.
    static func changing(_ paint: inout PaintContent, _ change: AgentPartChange) -> Int {
        let picked = paint.strokes.indices.filter { paint.strokes[$0].part.map(change.names) ?? false }
        guard !picked.isEmpty else { return 0 }
        if change.remove {
            let gone = Set(picked)
            paint.strokes = paint.strokes.enumerated().filter { !gone.contains($0.offset) }.map(\.element)
            return picked.count
        }
        if change.recolours {
            let shift = AgentPartColour.shift(from: picked.map { paint.strokes[$0].colorHex }, change)
            for index in picked { paint.strokes[index].colorHex = shift(paint.strokes[index].colorHex) }
        }
        if let scale = change.scale, scale != 1 {
            let box = picked.reduce(CGRect.null) { box, index in
                paint.strokes[index].samples.reduce(box) { $0.union(CGRect(origin: $1.point, size: .zero)) }
            }
            let middle = CGPoint(x: box.midX, y: box.midY)
            for index in picked {
                var stroke = paint.strokes[index]
                stroke.samples = stroke.samples.map { sample in
                    var sample = sample
                    sample.point = CGPoint(x: middle.x + (sample.point.x - middle.x) * scale,
                                           y: middle.y + (sample.point.y - middle.y) * scale)
                    return sample
                }
                stroke.settings.set("size", to: stroke.settings.size * scale)
                paint.strokes[index] = stroke
            }
        }
        if change.moves {
            for index in picked {
                paint.strokes[index] = paint.strokes[index].offsetBy(dx: CGFloat(change.dx ?? 0), dy: CGFloat(change.dy ?? 0))
            }
        }
        return picked.count
    }

    // MARK: Drawn parts

    static func changing(_ layer: Layer, _ change: AgentPartChange, canvas: CGSize) -> Layer {
        var layer = layer
        if change.recolours {
            var colours: [String] = []
            collectColours(layer, into: &colours)
            let shift = AgentPartColour.shift(from: colours, change)
            layer = recoloured(layer, shift)
        }
        if let scale = change.scale, scale != 1 {
            let box = AgentDrawing.box(of: layer)
            let frame = CGRect(x: box.midX - box.width * scale / 2, y: box.midY - box.height * scale / 2,
                               width: box.width * scale, height: box.height * scale)
            layer = layer.geometrySet(to: frame, canvas: canvas, byHand: true)
        }
        if change.moves {
            layer.frame.origin.x += CGFloat(change.dx ?? 0)
            layer.frame.origin.y += CGFloat(change.dy ?? 0)
        }
        return layer
    }

    private static func collectColours(_ layer: Layer, into colours: inout [String]) {
        for child in layer.group?.children ?? [] { collectColours(child, into: &colours) }
        if let fill = layer.path?.fill { colours.append(fill.hex) }
        if let fill = layer.annotation?.fill { colours.append(fill.hex) }
        if let text = layer.text { colours.append(text.colorHex) }
    }

    private static func recoloured(_ layer: Layer, _ shift: (String) -> String) -> Layer {
        var layer = layer
        if var group = layer.group {
            group.children = group.children.map { recoloured($0, shift) }
            layer.content = .group(group)
        } else if var path = layer.path {
            if let fill = path.fill { path.fill = Paint(hex: shift(fill.hex)) }
            path.colorHex = shift(path.colorHex)
            layer.content = .path(path)
        } else if var annotation = layer.annotation {
            if let fill = annotation.fill { annotation.fill = Paint(hex: shift(fill.hex)) }
            annotation.colorHex = shift(annotation.colorHex)
            layer.content = .annotation(annotation)
        } else if var text = layer.text {
            text.colorHex = shift(text.colorHex)
            layer.content = .text(text)
        }
        return layer
    }
}

/// The colour maths of change_part: one shift worked out from all of a
/// part's colours, then put on each, so its shades keep their differences.
enum AgentPartColour {

    static func shift(from colours: [String], _ change: AgentPartChange) -> (String) -> String {
        let hues = colours.map { AgentGroupRecolour.hsl(AgentGroupRecolour.rgb($0)) }
        var dh = 0.0, ds = 0.0, dl = 0.0
        if let target = change.colorHex, !hues.isEmpty {
            let to = AgentGroupRecolour.hsl(AgentGroupRecolour.rgb(target))
            let mean = Self.mean(hues)
            dh = to.h - mean.h
            ds = to.s - mean.s
            dl = to.l - mean.l
        }
        dh += (change.hue ?? 0) / 360
        ds += (change.saturation ?? 0) / 100
        dl += (change.lightness ?? 0) / 100
        let (h, s, l) = (dh, ds, dl)
        return { hex in
            let was = AgentGroupRecolour.hsl(AgentGroupRecolour.rgb(hex))
            var hue = (was.h + h).truncatingRemainder(dividingBy: 1)
            if hue < 0 { hue += 1 }
            return AgentGroupRecolour.hexString(fromHSL: (hue, min(1, max(0, was.s + s)), min(0.98, max(0.02, was.l + l))))
        }
    }

    /// The colours' middle: hue as an angle, weighted by how coloured each is.
    static func mean(_ colours: [(h: Double, s: Double, l: Double)]) -> (h: Double, s: Double, l: Double) {
        let n = Double(colours.count)
        var x = 0.0, y = 0.0
        for colour in colours {
            let weight = max(colour.s, 0.001)
            x += cos(colour.h * 2 * .pi) * weight
            y += sin(colour.h * 2 * .pi) * weight
        }
        var h = atan2(y, x) / (2 * .pi)
        if h < 0 { h += 1 }
        return (h, colours.reduce(0) { $0 + $1.s } / n, colours.reduce(0) { $0 + $1.l } / n)
    }
}
