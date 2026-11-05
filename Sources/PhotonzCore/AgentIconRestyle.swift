import CoreGraphics
import Foundation

// A tweak to a whole icon: "make it outline", "thicker lines", "make it red"
// (`docs/design/ask.md`, "An icon"). A small model asked to do these by hand
// deleted an envelope's flap to fill it and thickened one line of a gear's two,
// so the whole icon changes here, every part alike, in place, as one undo step.
// It reads shapes and their sizes, never what the icon is of.

public struct AgentIconRestyle: Hashable, Sendable {

    public enum Look: String, Hashable, Sendable, CaseIterable {
        case outline, filled
    }

    public enum Weight: String, Hashable, Sendable, CaseIterable {
        case thicker, thinner
    }

    public var look: Look?
    public var weight: Weight?
    public var colorHex: String?

    public init(look: Look? = nil, weight: Weight? = nil, colorHex: String? = nil) {
        self.look = look
        self.weight = weight
        self.colorHex = colorHex
    }

    /// How much one step of thicker or thinner changes a line.
    static let step: CGFloat = 1.35
    /// The lightest and heaviest a line may get, as shares of the icon's side.
    static let thinnest: CGFloat = 1.0 / 32
    static let heaviest: CGFloat = 1.0 / 7
    /// The line a solid icon takes when it becomes an outline, as a share of
    /// the side: what two units on the 24 grid come to, fitted into the frame.
    static let plainWeight: CGFloat = 0.068
    /// A solid shape this share of the drawing or more is the icon's body; a
    /// smaller one is too small to hold a line of its own.
    static let bodyShare: CGFloat = 0.15
    /// What a line on a solid shape is drawn in: the cut it stands for.
    static let cutHex = "#FFFFFF"
}

/// What restyle_icon did.
public struct AgentIconRestyled: Encodable, Hashable, Sendable {
    public let layers: Int
}

extension AgentTools {

    static let iconTools: [AgentTool] = [
        AgentTool(
            name: "restyle_icon",
            description: "Change a whole icon in place: every part alike, none added or taken away. One undo step.",
            inputSchema: ["type": "object", "properties": [
                "document": ["type": "string",
                             "description": "The document's id from list_documents, such as d1. Leave it out to use the document in front."],
                "look": ["type": "string", "enum": ["outline", "filled"], "description": "outline: drawn in lines. filled: solid shapes."],
                "weight": ["type": "string", "enum": ["thicker", "thinner"], "description": "Every line a step thicker or thinner."],
                "color": ["type": "string", "description": "#RRGGBB: the icon's colour."],
            ], "additionalProperties": false]),
    ]

    static let iconToolNames: Set<String> = Set(iconTools.map(\.name))

    static func iconRequest(_ name: String, _ args: [String: AgentJSON],
                            document: String?) -> Result<AgentRequest, AgentToolError> {
        func fail(_ words: String) -> Result<AgentRequest, AgentToolError> { .failure(AgentToolError("\(name): \(words)")) }
        var change = AgentIconRestyle()
        if let word = args["look"]?.stringValue {
            guard let look = AgentIconRestyle.Look(rawValue: word) else { return fail("look is outline or filled, not \(word).") }
            change.look = look
        }
        if let word = args["weight"]?.stringValue {
            guard let weight = AgentIconRestyle.Weight(rawValue: word) else { return fail("weight is thicker or thinner, not \(word).") }
            change.weight = weight
        }
        if let word = args["color"]?.stringValue {
            guard case .hex(let hex)? = AgentInk(word), hex.count == 7 else { return fail("color is \(word); give #RRGGBB.") }
            change.colorHex = hex.uppercased()
        }
        guard change != AgentIconRestyle() else { return fail("say what to change: look, weight or color.") }
        return .success(.restyleIcon(document: document, change: change))
    }
}

extension PhotonzDocument {

    /// Lands a restyle_icon call on the icon in this picture.
    public mutating func agentRestyleIcon(_ change: AgentIconRestyle) -> Result<AgentIconRestyled, AgentToolError> {
        guard let frame = layers.first(where: { $0.isFrame && IconPreviews.isIconSize($0.frame.size) && !$0.children.isEmpty }) else {
            return .failure(AgentToolError("restyle_icon: there is no icon in this picture."))
        }
        let side = frame.frame.width
        var parts: [Layer] = []
        func collect(_ layer: Layer) {
            if layer.isGroup { layer.children.forEach(collect) } else if layer.path != nil || layer.annotation != nil { parts.append(layer) }
        }
        frame.children.forEach(collect)
        guard !parts.isEmpty else { return .failure(AgentToolError("restyle_icon: that icon has no shapes to change.")) }
        if let locked = parts.first(where: \.isLocked) {
            return .failure(AgentToolError("restyle_icon: \(locked.name) is locked."))
        }
        var drawn = parts.map(IconPart.init)
        switch change.look {
        case .filled?: IconPart.fill(&drawn)
        case .outline?: IconPart.outline(&drawn, side: side)
        case nil: break
        }
        if let weight = change.weight {
            let times = weight == .thicker ? AgentIconRestyle.step : 1 / AgentIconRestyle.step
            for index in drawn.indices where drawn[index].weight > 0 {
                drawn[index].weight = min(max(drawn[index].weight * times, side * AgentIconRestyle.thinnest),
                                          side * AgentIconRestyle.heaviest)
            }
        }
        if let hex = change.colorHex {
            let colours = drawn.flatMap { [$0.fill, $0.weight > 0 ? $0.ink : nil] }.compactMap { $0 }
                .filter { $0.uppercased() != AgentIconRestyle.cutHex }
            var asked = AgentPartChange(part: "icon", layer: nil)
            asked.colorHex = hex
            let shift = AgentPartColour.shift(from: colours, asked)
            for index in drawn.indices {
                drawn[index].fill = drawn[index].fill.map { $0.uppercased() == AgentIconRestyle.cutHex ? $0 : shift($0) }
                if drawn[index].ink.uppercased() != AgentIconRestyle.cutHex { drawn[index].ink = shift(drawn[index].ink) }
            }
        }
        for part in drawn {
            updateLayer(id: part.id) { part.write(to: &$0) }
        }
        return .success(AgentIconRestyled(layers: drawn.count))
    }
}

/// One shape of an icon, whichever kind of layer holds it.
private struct IconPart {
    let id: UUID
    let box: CGRect
    let isClosed: Bool
    var fill: String?
    var ink: String
    var weight: CGFloat

    init(_ layer: Layer) {
        id = layer.id
        box = layer.frame
        if let path = layer.path {
            isClosed = path.isClosed
            fill = path.fill?.hex
            ink = path.colorHex
            weight = path.strokeWidth
        } else {
            // A box's edge is its Border.
            isClosed = true
            fill = layer.annotation?.fill?.hex
            weight = layer.style.borderWidth
            ink = weight > 0 ? layer.style.borderColorHex : layer.annotation?.colorHex ?? AgentDrawing.defaultStrokeHex
        }
    }

    func write(to layer: inout Layer) {
        if var path = layer.path {
            path.fill = isClosed ? fill.map { Paint(hex: $0) } : nil
            path.colorHex = ink
            path.strokeWidth = weight
            layer.content = .path(path)
        } else if var annotation = layer.annotation {
            annotation.fill = fill.map { Paint(hex: $0) }
            annotation.colorHex = ink
            layer.content = .annotation(annotation)
            layer.style.borderWidth = weight
            if weight > 0 { layer.style.borderColorHex = ink }
        }
    }

    private var area: CGFloat { box.width * box.height }
    private var isCut: Bool { ink.uppercased() == AgentIconRestyle.cutHex || fill?.uppercased() == AgentIconRestyle.cutHex }

    private func lies(on body: IconPart) -> Bool {
        body.id != id && body.area > area && body.box.contains(CGPoint(x: box.midX, y: box.midY))
    }

    /// The main ink of the icon: the biggest shape's.
    private static func mainInk(_ parts: [IconPart]) -> String {
        let uncut = parts.filter { !$0.isCut }
        let biggest = uncut.max { $0.area < $1.area } ?? parts[0]
        return biggest.fill ?? biggest.ink
    }

    /// Every closed shape big enough fills; what lies on one is cut out of it.
    static func fill(_ parts: inout [IconPart]) {
        let ink = mainInk(parts)
        let drawing = parts.reduce(CGRect.null) { $0.union($1.box) }
        let body = drawing.width * drawing.height * AgentIconRestyle.bodyShare
        let solid = parts.filter { $0.isClosed && $0.area >= body }
        let biggest = solid.max { $0.area < $1.area }?.id
        for index in parts.indices {
            let part = parts[index]
            if solid.contains(where: { $0.id == part.id }), part.id == biggest || !solid.contains(where: part.lies(on:)) {
                parts[index].fill = ink
                parts[index].ink = ink
                parts[index].weight = 0
            } else if solid.contains(where: part.lies(on:)) {
                if part.isClosed, part.weight == 0 || part.area < body {
                    parts[index].fill = AgentIconRestyle.cutHex
                    parts[index].weight = 0
                }
                parts[index].ink = AgentIconRestyle.cutHex
            }
        }
    }

    /// Every big solid shape becomes a line; a cut comes back in the icon's ink.
    static func outline(_ parts: inout [IconPart], side: CGFloat) {
        let ink = mainInk(parts)
        let line = parts.map(\.weight).filter { $0 > 0 }.max() ?? side * AgentIconRestyle.plainWeight
        let drawing = parts.reduce(CGRect.null) { $0.union($1.box) }
        let body = drawing.width * drawing.height * AgentIconRestyle.bodyShare
        for index in parts.indices {
            let part = parts[index]
            if part.isCut {
                parts[index].ink = ink
                parts[index].fill = nil
                parts[index].weight = part.weight > 0 ? part.weight : line
            } else if part.fill != nil, part.area >= body {
                parts[index].fill = nil
                parts[index].ink = ink
                parts[index].weight = line
            }
        }
    }
}
