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
    /// -100 to 100: cooler (toward blue) to warmer (toward orange). On a
    /// photo it is the colour grade's temperature.
    public var warmth: Double?
    /// How many times its size, about its own middle.
    public var scale: Double?
    public var dx: Double?
    public var dy: Double?
    public var remove: Bool
    /// A point on the canvas inside the part, for a drawing whose layers are
    /// named by colour rather than by part: the piece drawn there is split
    /// out of its layer, named `part`, and changed alone.
    public var at: CGPoint?
    /// On a component drawn in several looks (Default, Hover, Pressed), the
    /// one look to change. Nil changes the part in every look, each keeping
    /// its difference from the first.
    public var look: String?

    public init(part: String, layer: String? = nil, colorHex: String? = nil, hue: Double? = nil,
                saturation: Double? = nil, lightness: Double? = nil, warmth: Double? = nil, scale: Double? = nil,
                dx: Double? = nil, dy: Double? = nil, remove: Bool = false, at: CGPoint? = nil, look: String? = nil) {
        self.part = part
        self.layer = layer
        self.colorHex = colorHex
        self.hue = hue
        self.saturation = saturation
        self.lightness = lightness
        self.warmth = warmth
        self.scale = scale
        self.dx = dx
        self.dy = dy
        self.remove = remove
        self.at = at
        self.look = look
    }

    var recolours: Bool { colorHex != nil || hue != nil || saturation != nil || lightness != nil || warmth != nil }
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
        while let first = words.first, ["a", "an", "the"].contains(first), words.count > 1 { words.removeFirst() }
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
                "color": ["type": "string", "description": "#RRGGBB: the part's main colour becomes this; its lighter and darker shades keep their difference. The way to make a part bluer, redder, more purple or any colour: give that colour."],
                "hue": ["type": "number", "minimum": -180, "maximum": 180, "description": "Turn its colours round the colour wheel by this many degrees. Rarely wanted: for a colour named in the request, give color."],
                "saturation": ["type": "number", "minimum": -100, "maximum": 100, "description": "Greyer (below 0) or stronger (above 0)."],
                "lightness": ["type": "number", "minimum": -100, "maximum": 100, "description": "Darker (below 0) or lighter (above 0)."],
                "warmth": ["type": "number", "minimum": -100, "maximum": 100, "description": "Cooler, toward blue (below 0), or warmer, toward orange (above 0). The way to make a photo warmer or cooler."],
                "scale": ["type": "number", "minimum": .number(0.1), "maximum": 10, "description": "Times its size, about its own middle: 1.5 is half as big again, 0.5 half the size."],
                "dx": ["type": "number", "description": "Move it right by this many points (left below 0)."],
                "dy": ["type": "number", "description": "Move it down by this many points (up below 0)."],
                "remove": ["type": "boolean", "description": "Take the part away."],
                "at": ["type": "object", "description": "A point on the canvas inside the part, in canvas points from the top left. Give it when no layer or painted part has the part's name (a drawing whose layers are named by colour): the piece drawn there is split out, given the part's name, and changed alone.",
                       "properties": ["x": ["type": "number"], "y": ["type": "number"]], "required": ["x", "y"], "additionalProperties": false],
                "look": ["type": "string", "description": "On a component drawn in several looks (read_document gives each drawing's look: Default, Hover, Pressed), the one look to change. Left out, the part changes in every look: the first look takes the colour given and the others keep their difference from it, so a Pressed look stays darker and a Disabled one faded."],
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
        change.warmth = args["warmth"]?.doubleValue
        change.scale = args["scale"]?.doubleValue
        change.dx = args["dx"]?.doubleValue
        change.dy = args["dy"]?.doubleValue
        change.remove = args["remove"]?.boolValue ?? false
        if let look = args["look"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !look.isEmpty {
            change.look = look
        }
        if let at = args["at"] {
            guard let x = at["x"]?.doubleValue, let y = at["y"]?.doubleValue else { return fail("at takes x and y.") }
            change.at = CGPoint(x: x, y: y)
        }
        if let scale = change.scale, !(0.1...10).contains(scale) { return fail("scale runs 0.1 to 10.") }
        guard change.changesAnything else {
            return fail("say what to change: color, hue, saturation, lightness, warmth, scale, dx and dy, or remove.")
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
        // The layer given is itself the part asked for ("the fox", on the
        // drawing's own group): the whole of it changes, unless a point
        // says which piece of it.
        if named.isEmpty, change.at == nil, let scope, change.names(scope.name) { named = [scope.id] }
        // Nothing of that name, and a point given: the piece drawn there.
        if named.isEmpty, let point = change.at {
            switch splitPiece(at: point, named: change.part, within: candidates) {
            case .success(let id): named = [id]
            case .failure(let refused): return .failure(refused)
            }
        }
        guard !named.isEmpty else {
            let known = (painted + names).prefix(24)
            let listed = known.isEmpty ? "" : " The parts there are: \(known.joined(separator: ", "))."
            return .failure(AgentToolError("change_part: nothing is called \(change.part).\(listed) Give at, a point inside it on the canvas, when its layers are named by colour."))
        }
        // A piece of a component's copy is rebuilt from its original after
        // every edit: the change goes to the original's layer it shows, so
        // the copy, and every other copy, follows.
        var redirected: [UUID] = []
        for id in named {
            let target = componentPiece(of: id).flatMap { $0.isNested ? nil : $0.source } ?? id
            if !redirected.contains(target) { redirected.append(target) }
        }
        named = redirected
        // A part of one look of a component is that part in every look (a
        // primary button made green is green when hovered and pressed too),
        // unless the call names the look. The first look takes the colour
        // asked for; the rest keep their difference from it.
        let anchor: [UUID]
        switch lookPieces(of: named, look: change.look) {
        case .success(let found):
            named = found.pieces
            anchor = found.anchor
        case .failure(let refused): return .failure(refused)
        }
        if change.colorHex != nil || change.hue != nil,
           let photo = named.compactMap({ layer(id: $0) }).first(where: Self.isPicture) {
            return .failure(AgentToolError("change_part: \(photo.name) is a photo, one picture with no parts to recolour toward a colour. Use warmth, saturation or lightness on it."))
        }
        if let locked = named.compactMap({ layer(id: $0) }).first(where: \.isLocked) {
            return .failure(AgentToolError("change_part: \(locked.name) is locked."))
        }
        if change.remove {
            removeLayers(ids: Set(named))
            return .success(AgentPartChanged(part: change.part, strokes: nil, layers: named.count))
        }
        // One shift for the whole part, worked out from the anchor's
        // colours: two clouds, or four looks of a button, keep their shades.
        var colours: [String] = []
        for id in anchor { if let layer = layer(id: id) { Self.collectColours(layer, into: &colours) } }
        let shift = AgentPartColour.shift(from: colours, change)
        let canvas = canvasSize
        for id in named {
            updateLayer(id: id) { layer in layer = Self.changing(layer, change, canvas: canvas, shift: shift) }
        }
        return .success(AgentPartChanged(part: change.part, strokes: nil, layers: named.count))
    }

    // MARK: A component's looks

    /// The same piece in every look of the component each of `ids` sits in
    /// (or in the one look named), with the pieces of the first look (or the
    /// named one) as the anchor the colour is worked out from. A layer in no
    /// component of several looks is its own anchor.
    func lookPieces(of ids: [UUID], look: String?) -> Result<(pieces: [UUID], anchor: [UUID]), AgentToolError> {
        var pieces: [UUID] = [], anchor: [UUID] = []
        var looksSeen: [String] = []
        var inLooks = false
        func add(_ id: UUID, anchoring: Bool) {
            if !pieces.contains(id) { pieces.append(id) }
            if anchoring, !anchor.contains(id) { anchor.append(id) }
        }
        for id in ids {
            guard let (main, route) = owningMain(of: id), let componentID = main.componentID,
                  case let versions = componentVersions(of: componentID), versions.count > 1,
                  let name = layer(id: id)?.name else {
                add(id, anchoring: true)
                continue
            }
            inLooks = true
            for version in versions where !looksSeen.contains(version.option) { looksSeen.append(version.option) }
            for (index, version) in versions.enumerated() {
                let picked = look.map { AgentPartChange.words($0) == AgentPartChange.words(version.option) } ?? true
                guard picked, let drawing = layer(id: version.layerID),
                      let piece = Self.piece(in: drawing, at: route, named: name) else { continue }
                add(piece, anchoring: look != nil || index == 0)
            }
        }
        if let look, inLooks, pieces.isEmpty {
            return .failure(AgentToolError("change_part: there is no \(look) look. The looks are: \(looksSeen.joined(separator: ", ")). Leave look out to change every look."))
        }
        return .success((pieces, anchor.isEmpty ? pieces : anchor))
    }

    /// The component drawing (a main of one look) holding `id`, or being it,
    /// innermost first, and the route of child indices from it down to `id`.
    private func owningMain(of id: UUID) -> (Layer, [Int])? {
        guard let path = path(of: id) else { return nil }
        var list = layers
        var found: (Layer, [Int])?
        for (depth, index) in path.enumerated() {
            guard list.indices.contains(index) else { return found }
            let layer = list[index]
            if layer.isMainComponent { found = (layer, Array(path.dropFirst(depth + 1))) }
            list = layer.children
        }
        return found
    }

    /// The layer at `route` inside `drawing`, when it carries `name`; else
    /// the first layer of that name inside it.
    private static func piece(in drawing: Layer, at route: [Int], named name: String) -> UUID? {
        var layer = drawing
        for index in route {
            let children = layer.children
            guard children.indices.contains(index) else { layer = drawing; break }
            layer = children[index]
        }
        if layer.name == name, route.isEmpty || layer.id != drawing.id { return layer.id }
        return drawing.selfAndDescendants.dropFirst().first { $0.name == name }?.id
    }

    // MARK: A piece by where it is

    /// The piece drawn at `point` (canvas points) among `layers`: the topmost
    /// filled path holding it, and of that path only the smallest ring that
    /// holds it with every ring inside that ring (its holes and details).
    /// When the path has other rings too, the piece is split out into a
    /// layer of its own just above it, named `part`, so a later request finds
    /// it by name. Its id, or why there is none.
    mutating func splitPiece(at point: CGPoint, named part: String, within layers: [Layer]) -> Result<UUID, AgentToolError> {
        var hits: [(id: UUID, local: CGPoint)] = []
        func walk(_ layer: Layer, offset: CGPoint) {
            guard layer.isVisible else { return }
            let origin = CGPoint(x: offset.x + layer.frame.minX, y: offset.y + layer.frame.minY)
            if let children = layer.group?.children {
                for child in children { walk(child, offset: origin) }
                return
            }
            let local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
            if let path = layer.path, path.paintsAnInside, path.containsInside(local) { hits.append((layer.id, local)) }
        }
        for layer in layers { walk(layer, offset: .zero) }
        // Children and layers run bottom first: the last hit is on top.
        guard let hit = hits.last, let layer = layer(id: hit.id), let path = layer.path else {
            return .failure(AgentToolError("change_part: nothing filled is drawn at \(Int(point.x)),\(Int(point.y)). Give a point inside the part, in canvas points from the top left."))
        }
        let rings = path.ringRanges.map { range -> PathContent in
            var one = path
            one.anchors = Array(path.anchors[range])
            one.ringStarts = []
            return one
        }
        let holding = rings.indices.filter { rings[$0].containsInside(hit.local) }
        guard let chosen = holding.min(by: { area(rings[$0].bounds) < area(rings[$1].bounds) }) else {
            return .success(hit.id)
        }
        let box = rings[chosen].bounds
        let inPiece = rings.indices.filter { $0 == chosen || ($0 != chosen && box.contains(rings[$0].bounds)) }
        guard inPiece.count < rings.count else {
            updateLayer(id: hit.id) { $0.name = Self.title(part) }
            return .success(hit.id)
        }
        func joined(_ indices: [Int]) -> PathContent {
            var out = path
            out.anchors = indices.flatMap { rings[$0].anchors }
            var starts: [Int] = []
            var count = 0
            for index in indices.dropLast() {
                count += rings[index].anchors.count
                starts.append(count)
            }
            out.ringStarts = starts
            return out
        }
        let rest = rings.indices.filter { !inPiece.contains($0) }
        let pieceContent = joined(inPiece)
        let pieceBox = pieceContent.bounds
        var piece = PathBuilder.layer(pieceContent, at: CGPoint(x: layer.frame.minX + pieceBox.minX, y: layer.frame.minY + pieceBox.minY),
                                      name: Self.title(part))
        piece.style = layer.style
        updateLayer(id: hit.id) { $0.content = .path(joined(rest)) }
        if let parent = parentID(of: hit.id) {
            updateLayer(id: parent) { group in
                guard var content = group.group, let at = content.children.firstIndex(where: { $0.id == hit.id }) else { return }
                content.children.insert(piece, at: at + 1)
                group.content = .group(content)
            }
        } else if let at = self.layers.firstIndex(where: { $0.id == hit.id }) {
            addLayer(piece, at: at + 1)
        }
        return .success(piece.id)
    }

    private func area(_ box: CGRect) -> CGFloat { box.width * box.height }

    /// "door" reads as "Door", the way a layer is named.
    static func title(_ part: String) -> String {
        let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return part }
        return first.uppercased() + trimmed.dropFirst()
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

    static func isPicture(_ layer: Layer) -> Bool {
        if case .image = layer.content { return true }
        return false
    }

    static func changing(_ layer: Layer, _ change: AgentPartChange, canvas: CGSize,
                         shift: ((String) -> String)? = nil) -> Layer {
        var layer = layer
        if change.recolours, isPicture(layer) {
            // A photo's colours change through its colour grade, the Effects
            // list's own, so the panel shows what was done and can undo it.
            var grade = ColorGradeEffect.neutral
            let at = layer.style.effects.firstIndex { if case .colorGrade = $0 { return true }; return false }
            if let at, case .colorGrade(let had) = layer.style.effects[at] { grade = had }
            grade = ColorGradeEffect(temperature: grade.temperature + (change.warmth ?? 0), tint: grade.tint,
                                     exposure: grade.exposure + (change.lightness ?? 0) / 50, contrast: grade.contrast,
                                     saturation: grade.saturation + (change.saturation ?? 0), isOn: true)
            if let at { layer.style.effects[at] = .colorGrade(grade) } else { layer.style.effects.append(.colorGrade(grade)) }
        } else if change.recolours {
            var colours: [String] = []
            collectColours(layer, into: &colours)
            layer = recoloured(layer, shift ?? AgentPartColour.shift(from: colours, change))
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

    static func collectColours(_ layer: Layer, into colours: inout [String]) {
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
        let warmth = (change.warmth ?? 0) / 100
        return { hex in
            let was = AgentGroupRecolour.hsl(AgentGroupRecolour.rgb(hex))
            var hue = (was.h + h).truncatingRemainder(dividingBy: 1)
            if hue < 0 { hue += 1 }
            if warmth != 0 {
                // Toward orange or toward blue, at most half way round.
                let toward = warmth > 0 ? 0.08 : 0.6
                var gap = toward - hue
                if gap > 0.5 { gap -= 1 }
                if gap < -0.5 { gap += 1 }
                hue += gap * min(1, abs(warmth)) * 0.5
            }
            hue = hue.truncatingRemainder(dividingBy: 1)
            if hue < 0 { hue += 1 }
            // Kept off pure white and black, except a colour already there:
            // a white label stays white.
            let lightness = min(max(0.98, was.l), max(min(0.02, was.l), was.l + l))
            return AgentGroupRecolour.hexString(fromHSL: (hue, min(1, max(0, was.s + s)), lightness))
        }
    }

    /// The colours' middle, each weighted by how coloured it is: a white
    /// label on a blue button is not part of the blue the button is, so it
    /// neither pulls the middle lighter nor gets darkened toward the colour.
    static func mean(_ colours: [(h: Double, s: Double, l: Double)]) -> (h: Double, s: Double, l: Double) {
        var x = 0.0, y = 0.0, s = 0.0, l = 0.0, total = 0.0
        for colour in colours {
            let weight = max(colour.s, 0.001)
            x += cos(colour.h * 2 * .pi) * weight
            y += sin(colour.h * 2 * .pi) * weight
            s += colour.s * weight
            l += colour.l * weight
            total += weight
        }
        var h = atan2(y, x) / (2 * .pi)
        if h < 0 { h += 1 }
        return (h, s / total, l / total)
    }
}
