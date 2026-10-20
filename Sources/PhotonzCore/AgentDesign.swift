import CoreGraphics
import Foundation

// The design-system tools of the agent channel (`docs/design/agent-mcp.md`,
// "Design systems"): what an agent needs to rebuild a website's look as a
// Library a person would build. Colours and type are saved under a name on
// the Library's Styles shelf and put on layers by name, the way choosing one
// from a colour row or the Style row does; spacing is a group's own layout (a
// stack or grid with its gap and padding), typed as the inspector's Layout
// section types it. Components themselves are a group made one with
// run_command make_component, then placed with place_component.
//
// The pure half: the typed calls, finding a style by name, the listing, and
// the layout numbers. The app half is `Sources/Photonz/Agent/AgentDesignWork.swift`.

/// A style to put on the Styles shelf.
public enum AgentNewStyle: Hashable, Sendable {
    case color(name: String, hex: String)
    case text(name: String, treatment: TextTreatment)

    public var name: String {
        switch self {
        case .color(let name, _), .text(let name, _): name
        }
    }
}

/// Which part of a layer a colour style paints.
public enum AgentStylePart: String, CaseIterable, Hashable, Sendable {
    case fill
    case stroke
    case text

    public var slot: ColorSlot {
        switch self {
        case .fill: .fill
        case .stroke: .stroke
        case .text: .text
        }
    }

    /// The part a colour goes on when the agent names none: the inside of
    /// anything that has one, the ink of words, else the line.
    public static func defaultSlot(for slots: [ColorSlot]) -> ColorSlot? {
        for slot in [ColorSlot.fill, .text, .stroke] where slots.contains(slot) { return slot }
        return slots.first
    }
}

/// A style found by name or id.
public enum AgentStyleMatch: Hashable, Sendable {
    case color(UUID)
    case text(UUID)
}

/// How big a group is on one axis: as big as its contents, or a number.
public enum AgentLayoutSize: Hashable, Sendable {
    case hug
    case fixed(CGFloat)

    var value: CGFloat? {
        if case .fixed(let size) = self { return size }
        return nil
    }
}

/// How a group arranges what is inside it.
public enum AgentArrange: String, CaseIterable, Hashable, Sendable {
    case stack
    case grid
    /// Arranges nothing and closes around its contents, keeping its padding.
    case free

    public var kind: GroupLayoutKind? {
        switch self {
        case .stack: .stack
        case .grid: .grid
        case .free: nil
        }
    }
}

/// The inspector's Layout section, said as numbers. Nil is "not said".
public struct AgentLayoutChange: Hashable, Sendable {
    public var arrange: AgentArrange?
    public var direction: StackDirection?
    public var gap: CGFloat?
    public var rowGap: CGFloat?
    public var columns: Int?
    public var padding: GroupPadding?
    public var width: AgentLayoutSize?
    public var height: AgentLayoutSize?
    public var spread: Bool?
    public var wraps: Bool?

    public init() {}

    public var isEmpty: Bool { self == AgentLayoutChange() }

    /// Every number said, onto a layout; the rest stays as it was.
    public func applied(to layout: inout GroupLayout) {
        if let direction { layout.direction = direction }
        if let gap { layout.gap = gap }
        if let rowGap { layout.rowGap = rowGap }
        if let columns { layout.columns = max(1, columns) }
        if let padding { layout.padding = padding }
        if let width { layout.width = width.value }
        if let height { layout.height = height.value }
        if let spread { layout.spreadsGap = spread }
        if let wraps { layout.wraps = wraps }
    }
}

extension PhotonzDocument {

    /// A saved colour or text style by its id, or by its name in any case.
    /// Colours are looked through first, as the Styles shelf lists them.
    public func agentStyle(named words: String) -> AgentStyleMatch? {
        let wanted = words.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = UUID(uuidString: wanted) {
            if colorStyle(id: id) != nil { return .color(id) }
            if textStyle(id: id) != nil { return .text(id) }
        }
        func same(_ name: String) -> Bool { name.caseInsensitiveCompare(wanted) == .orderedSame }
        if let style = colorStyles.first(where: { same($0.name) }) { return .color(style.id) }
        if let style = textStyles.first(where: { same($0.name) }) { return .text(style.id) }
        return nil
    }

    /// The inspector's Layout section on one group: the arrangement first (read
    /// off where the contents already are, as choosing it in the inspector
    /// does), then the numbers typed into it.
    public mutating func agentSetLayout(id: UUID, _ change: AgentLayoutChange) {
        if let arrange = change.arrange { setGroupLayout(id: id, kind: arrange.kind) }
        var numbers = change
        numbers.arrange = nil
        guard !numbers.isEmpty else { return }
        updateGroupLayout(id: id) { numbers.applied(to: &$0) }
    }
}

/// What became of words an agent typed over a layer inside a component copy.
public enum AgentPieceWording: Hashable, Sendable {
    /// Not inside a copy: an ordinary edit.
    case notAPiece
    /// On the copy's own answer to the piece's wording knob; `madeAdjustable`
    /// when the original had no knob and was given one, as the inspector's
    /// Make Adjustable does.
    case landed(madeAdjustable: Bool)
    /// Why it could not land, and what to do instead.
    case refused(String)
}

extension PhotonzDocument {

    /// Typing over a piece of a copy, the way the canvas routes it
    /// (`ComponentPieceEditing`): onto the copy's wording knob, after giving
    /// the original one when it has none (an agent cannot press Make
    /// Adjustable, so saying the words is the press). Writing onto the piece
    /// itself would be thrown away by the next sync, which is how set_layer
    /// used to answer "done" while nothing changed.
    public mutating func agentWordCopyPiece(_ id: UUID, to string: String) -> AgentPieceWording {
        switch wordingEdit(of: id) {
        case .ordinary:
            return .notAPiece
        case .knob:
            return setPieceWording(of: id, to: string) ? .landed(madeAdjustable: false)
                                                       : .refused("Photonz could not word that piece.")
        case .refused(let refusal):
            let copy = layer(id: refusal.piece.instance)?.name ?? refusal.component
            switch refusal.remedy {
            case .exposeWording:
                guard exposePieceWording(of: id) != nil, setPieceWording(of: id, to: string) else {
                    return .refused("Photonz could not make \(refusal.pieceName) in \(copy) adjustable.")
                }
                return .landed(madeAdjustable: true)
            case .unlock:
                return .refused("\(copy) is locked. Unlock it with run_command lock_layer, on false.")
            case .detach:
                return .refused("\(refusal.pieceName) is inside \(copy), a copy of \(refusal.component), and its words cannot be made adjustable from here. run_command make_unique on the copy to stop it following the original, then word it.")
            }
        }
    }
}

/// What `list_styles` answers: the Styles shelf, colours then type.
public struct AgentStyleListing: Codable, Hashable, Sendable {
    public struct Color: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var color: String
    }

    public struct Text: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var font: String
        public var size: Double
        public var weight: String
        public var color: String

        public init(id: String, name: String, font: String, size: Double, weight: String, color: String) {
            self.id = id
            self.name = name
            self.font = font
            self.size = size
            self.weight = weight
            self.color = color
        }
    }

    public var colors: [Color]
    public var text: [Text]

    public static func make(_ document: PhotonzDocument) -> AgentStyleListing {
        AgentStyleListing(
            colors: document.colorStyles.map { Color(id: $0.id.uuidString, name: $0.name, color: $0.colorHex) },
            text: document.textStyles.map {
                Text(id: $0.id.uuidString, name: $0.name, font: $0.treatment.fontName,
                     size: AgentDocumentRead.tidy($0.treatment.fontSize), weight: $0.treatment.weight.rawValue,
                     color: $0.treatment.colorHex)
            })
    }
}

// MARK: - The tools

extension AgentTools {

    private static func designSchema(_ properties: [String: AgentJSON], required: [String] = []) -> AgentJSON {
        var all = properties
        all["document"] = ["type": "string",
                           "description": "The document's id from list_documents, such as d1. Leave it out to use the document in front."]
        return ["type": "object", "properties": .object(all),
                "required": .array(required.map(AgentJSON.string)), "additionalProperties": false]
    }

    private static let sizeWords = "A number of points, or hug to be as big as what is inside plus the padding."

    static let designTools: [AgentTool] = [
        AgentTool(
            name: "list_styles",
            description: "The colours and text styles saved by name on the Library's Styles shelf, with what each holds and the id apply_style takes.",
            inputSchema: designSchema([:])),
        AgentTool(
            name: "add_style",
            description: "Save a colour or a text style by name on the Library's Styles shelf, as Save as Style does. A design system's colours and type go here, then onto layers with apply_style, so changing a style later changes everything wearing it. One undo step.",
            inputSchema: designSchema([
                "kind": ["type": "string", "enum": ["color", "text"], "description": "A colour, or a text style (font, size, weight and colour)."],
                "name": ["type": "string", "description": "What the shelf calls it, such as Primary or Heading 1."],
                "color": ["type": "string", "description": "#RRGGBB or #RRGGBBAA. Required for a colour; a text style's ink, near black when left out."],
                "font": ["type": "string", "description": "Text style: a font family on this Mac. SF Pro when left out."],
                "size": ["type": "number", "minimum": 4, "maximum": 1000, "description": "Text style: points. 16 when left out."],
                "weight": ["type": "string", "enum": .array(TextWeight.allCases.map { .string($0.rawValue) }),
                           "description": "Text style: regular, medium, semibold or bold. regular when left out."],
            ], required: ["kind", "name"])),
        AgentTool(
            name: "apply_style",
            description: "Put a saved style on layers, as choosing it from a colour row or the Style row does: a text style re-sets the words (their box re-measured); a colour paints the part named. Layers inside a component's original change every copy. One undo step.",
            inputSchema: designSchema([
                "style": ["type": "string", "description": "Its name or id from list_styles."],
                "layers": ["type": "array", "items": ["type": "string"], "minItems": 1, "description": "Layer ids from read_document."],
                "part": ["type": "string", "enum": .array(AgentStylePart.allCases.map { .string($0.rawValue) }),
                         "description": "A colour only: fill (the inside), stroke (the line) or text (the words' ink). The inside, or the words' ink, when left out."],
            ], required: ["style", "layers"])),
        AgentTool(
            name: "set_layout",
            description: "How a group or frame arranges its contents, as the inspector's Layout section sets it: a stack (one row or column with an even gap) or a grid, the padding inside its edges, and its size. A button is a stack with padding; a card is a column stack; a nav bar is a row that spreads. Make a group first with run_command group. One undo step.",
            inputSchema: designSchema([
                "layer": ["type": "string", "description": "The group or frame's id from read_document."],
                "arrange": ["type": "string", "enum": .array(AgentArrange.allCases.map { .string($0.rawValue) }),
                            "description": "stack, grid, or free (arranges nothing, keeps its padding). Turning one on reads the gap off where things already are."],
                "direction": ["type": "string", "enum": .array(StackDirection.allCases.map { .string($0.rawValue) }),
                              "description": "A stack: row (left to right) or column (top to bottom)."],
                "gap": ["type": "number", "minimum": 0, "maximum": 2000, "description": "Points between one item and the next."],
                "rowGap": ["type": "number", "minimum": 0, "maximum": 2000, "description": "A grid, or a row that wraps: points between rows."],
                "columns": ["type": "integer", "minimum": 1, "maximum": 50, "description": "A grid: cells in a row."],
                "padding": ["description": "Room inside the edges: one number for all four sides, or an object with top, right, bottom and left.",
                            "anyOf": [["type": "number", "minimum": 0],
                                      ["type": "object", "properties": [
                                          "top": ["type": "number", "minimum": 0], "right": ["type": "number", "minimum": 0],
                                          "bottom": ["type": "number", "minimum": 0], "left": ["type": "number", "minimum": 0]],
                                       "additionalProperties": false]]],
                "width": ["description": .string(sizeWords), "anyOf": [["type": "number", "minimum": 1], ["type": "string", "enum": ["hug"]]]],
                "height": ["description": .string(sizeWords), "anyOf": [["type": "number", "minimum": 1], ["type": "string", "enum": ["hug"]]]],
                "spread": ["type": "boolean", "description": "A stack with a size of its own: share the room left over between items instead of the gap (a logo at one end, links at the other)."],
                "wraps": ["type": "boolean", "description": "A row with a width: carry on onto the next line when it runs out of room."],
            ], required: ["layer"])),
    ]

    static let designToolNames: Set<String> = Set(designTools.map(\.name))

    static func designRequest(_ name: String, _ args: [String: AgentJSON],
                              document: String?) -> Result<AgentRequest, AgentToolError> {
        func fail(_ words: String) -> Result<AgentRequest, AgentToolError> { .failure(AgentToolError("\(name): \(words)")) }
        switch name {
        case "list_styles":
            return .success(.listStyles(document: document))
        case "add_style":
            let styleName = (args["name"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !styleName.isEmpty else { return fail("name is empty.") }
            var hex: String?
            if let word = args["color"]?.stringValue {
                guard case .hex(let value)? = AgentInk(word) else { return fail("color is \(word); give #RRGGBB or #RRGGBBAA.") }
                hex = value
            }
            if args["kind"]?.stringValue == "color" {
                if args["font"] != nil || args["size"] != nil || args["weight"] != nil {
                    return fail("font, size and weight belong to a text style, not a colour.")
                }
                guard let hex else { return fail("a colour style needs a color.") }
                return .success(.addStyle(document: document, style: .color(name: styleName, hex: hex)))
            }
            let treatment = TextTreatment(
                fontName: args["font"]?.stringValue ?? "SF Pro",
                fontSize: CGFloat(args["size"]?.doubleValue ?? 16),
                weight: args["weight"]?.stringValue.flatMap(TextWeight.init(rawValue:)) ?? .regular,
                colorHex: hex ?? AgentDrawing.defaultStrokeHex)
            return .success(.addStyle(document: document, style: .text(name: styleName, treatment: treatment)))
        case "apply_style":
            let layers = (args["layers"]?.arrayValue ?? []).compactMap(\.stringValue)
            guard !layers.isEmpty else { return fail("name at least one layer.") }
            return .success(.applyStyle(document: document, style: args["style"]?.stringValue ?? "", layers: layers,
                                        part: args["part"]?.stringValue.flatMap(AgentStylePart.init(rawValue:))))
        case "set_layout":
            var change = AgentLayoutChange()
            change.arrange = args["arrange"]?.stringValue.flatMap(AgentArrange.init(rawValue:))
            change.direction = args["direction"]?.stringValue.flatMap(StackDirection.init(rawValue:))
            change.gap = args["gap"]?.doubleValue.map { CGFloat($0) }
            change.rowGap = args["rowGap"]?.doubleValue.map { CGFloat($0) }
            change.columns = args["columns"]?.intValue
            change.spread = args["spread"]?.boolValue
            change.wraps = args["wraps"]?.boolValue
            if let padding = args["padding"] {
                if let all = padding.doubleValue {
                    change.padding = GroupPadding(CGFloat(all))
                } else {
                    func side(_ key: String) -> CGFloat { CGFloat(padding[key]?.doubleValue ?? 0) }
                    change.padding = GroupPadding(top: side("top"), right: side("right"),
                                                  bottom: side("bottom"), left: side("left"))
                }
            }
            for (key, path) in [("width", \AgentLayoutChange.width), ("height", \AgentLayoutChange.height)] {
                guard let given = args[key] else { continue }
                if let points = given.doubleValue {
                    change[keyPath: path] = .fixed(CGFloat(points))
                } else if given.stringValue == "hug" {
                    change[keyPath: path] = .hug
                } else {
                    return fail("\(key) is a number of points, or hug.")
                }
            }
            guard !change.isEmpty else { return fail("nothing to change; say arrange, a gap, padding or a size.") }
            return .success(.setLayout(document: document, layer: args["layer"]?.stringValue ?? "", change: change))
        default:
            return .failure(AgentToolError("There is no tool called \(name).", isUnknownTool: true))
        }
    }
}
