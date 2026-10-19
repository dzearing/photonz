import CoreGraphics
import Foundation

/// One tool the app offers an agent over the MCP channel
/// (`docs/design/agent-mcp.md`): its name, what it does in a sentence or two,
/// and the JSON schema its arguments are checked against.
public struct AgentTool: Hashable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: AgentJSON

    /// The tool as `tools/list` lists it.
    public var listing: AgentJSON {
        ["name": .string(name), "description": .string(description), "inputSchema": inputSchema]
    }
}

/// What an agent asked for, checked and typed: the only thing the app is ever
/// handed to act on.
public enum AgentRequest: Hashable, Sendable {
    public enum OpenTarget: Hashable, Sendable {
        case path(String)
        /// An item of History by its place in `list_history`, newest first.
        case history(index: Int)
    }

    case listDocuments
    case listHistory(limit: Int)
    case openDocument(OpenTarget)
    case readDocument(document: String?)
    case renderPicture(document: String?, layer: String?, region: CGRect?, maxSize: Int)
    case videoFrame(document: String?, atMS: Int, region: CGRect?, maxSize: Int)
    case contactSheet(document: String?, fromMS: Int?, toMS: Int?, count: Int, columns: Int?, cellWidth: Int)
    case undo(document: String?, steps: Int)
    case redo(document: String?, steps: Int)
    /// The command table, with whether each can run now on the document.
    case listCommands(document: String?, area: AppCommand.Area?, readyOnly: Bool)
    /// One command by name, its arguments already checked.
    case runCommand(document: String?, call: AppCommandCall)
}

/// Why a call was refused, in one sentence a model can act on.
public struct AgentToolError: Error, Hashable, Sendable {
    public let message: String
    /// No tool has the name asked for, which is a protocol error rather than
    /// a tool's own.
    public let isUnknownTool: Bool

    public init(_ message: String, isUnknownTool: Bool = false) {
        self.message = message
        self.isUnknownTool = isUnknownTool
    }
}

/// The tools of the agent channel and the checking of a call against them.
///
/// The first slice of the MCP ask: reach the app, read the open document, see
/// it, and step back. The second runs every command of the menus by name
/// (`AppCommandTable`). Later slices add drawing and video
/// tools here, each with its schema and its tests.
public enum AgentTools {

    /// How big a picture comes back unless asked otherwise: big enough to read
    /// a screenshot's text, small enough not to fill a model's context.
    public static let defaultMaxSize = 1024
    public static let largestMaxSize = 2048
    public static let defaultCellWidth = 320
    public static let defaultSheetCount = 12
    public static let mostSheetFrames = 48

    // MARK: Schema pieces

    private static let documentProperty: AgentJSON = [
        "type": "string",
        "description": "The document's id from list_documents, such as d1. Leave it out to use the document in front.",
    ]

    private static let maxSizeProperty: AgentJSON = [
        "type": "integer", "minimum": 64, "maximum": .number(Double(largestMaxSize)),
        "description": "The longest side of the picture in pixels. 1024 when left out.",
    ]

    private static let regionProperty: AgentJSON = [
        "type": "object",
        "description": "Only this part of the canvas, in document points from the top left.",
        "properties": [
            "x": ["type": "number", "description": "Left edge."],
            "y": ["type": "number", "description": "Top edge."],
            "width": ["type": "number", "minimum": 1, "description": "Width."],
            "height": ["type": "number", "minimum": 1, "description": "Height."],
        ],
        "required": ["x", "y", "width", "height"],
        "additionalProperties": false,
    ]

    private static func stepsProperty(_ verb: String) -> AgentJSON {
        ["type": "integer", "minimum": 1, "maximum": 50,
         "description": .string("How many steps to \(verb). 1 when left out.")]
    }

    private static func schema(_ properties: [String: AgentJSON], required: [String] = []) -> AgentJSON {
        ["type": "object", "properties": .object(properties),
         "required": .array(required.map(AgentJSON.string)), "additionalProperties": false]
    }

    // MARK: The tools

    public static let all: [AgentTool] = [
        AgentTool(
            name: "list_documents",
            description: "The documents open in Photonz: id, title, file, picture or video, size, length, whether it is in front, and whether it can undo or redo.",
            inputSchema: schema([:])),
        AgentTool(
            name: "list_history",
            description: "The screenshots and recordings in Photonz History, newest first, with the index open_document takes.",
            inputSchema: schema([
                "limit": ["type": "integer", "minimum": 1, "maximum": 100,
                          "description": "How many to list. 20 when left out."],
            ])),
        AgentTool(
            name: "open_document",
            description: "Open a picture, recording or .photonz file in its own window, by path or by its index in list_history. Answers with the new document's id once it is open.",
            inputSchema: schema([
                "path": ["type": "string", "description": "An absolute path to the file."],
                "historyIndex": ["type": "integer", "minimum": 0,
                                 "description": "The item's index in list_history; 0 is the newest."],
            ])),
        AgentTool(
            name: "read_document",
            description: "The document as structured data: canvas, layers top first with frames, text and styles, and on a video the tracks with each clip's times, the cuts with their transitions, markers and the playhead. Times are in seconds.",
            inputSchema: schema(["document": documentProperty])),
        AgentTool(
            name: "render_picture",
            description: "A PNG of the canvas as it is now (a video at its playhead), or of one layer alone in place, or of one region. Use it to check your work.",
            inputSchema: schema([
                "document": documentProperty,
                "layer": ["type": "string", "description": "A layer id from read_document, drawn alone where it sits."],
                "region": regionProperty,
                "maxSize": maxSizeProperty,
            ])),
        AgentTool(
            name: "video_frame",
            description: "A PNG of a video document at a moment, drawn the way export draws it.",
            inputSchema: schema([
                "document": documentProperty,
                "seconds": ["type": "number", "minimum": 0, "description": "The moment, in seconds from the start."],
                "region": regionProperty,
                "maxSize": maxSizeProperty,
            ], required: ["seconds"])),
        AgentTool(
            name: "contact_sheet",
            description: "One PNG holding frames spread evenly across a stretch of a video, each labelled with its time, to see a whole edit at a glance.",
            inputSchema: schema([
                "document": documentProperty,
                "fromSeconds": ["type": "number", "minimum": 0, "description": "Where the stretch starts. The start of the video when left out."],
                "toSeconds": ["type": "number", "minimum": 0, "description": "Where it ends. The end of the video when left out."],
                "count": ["type": "integer", "minimum": 1, "maximum": .number(Double(mostSheetFrames)),
                          "description": "How many frames. 12 when left out."],
                "columns": ["type": "integer", "minimum": 1, "maximum": 12,
                            "description": "How many frames across. Chosen to make the sheet roughly square when left out."],
                "cellWidth": ["type": "integer", "minimum": 64, "maximum": 640,
                              "description": "Each frame's width in pixels. 320 when left out."],
            ])),
        AgentTool(
            name: "undo",
            description: "Undo the last step in the document, exactly as Edit > Undo does, whether a person or an agent made it.",
            inputSchema: schema(["document": documentProperty, "steps": stepsProperty("undo")])),
        AgentTool(
            name: "redo",
            description: "Redo what undo took back, exactly as Edit > Redo does.",
            inputSchema: schema(["document": documentProperty, "steps": stepsProperty("redo")])),
        AgentTool(
            name: "list_commands",
            description: "The commands of the menu bar and the right-click menus, by name: their menu, what they need, the arguments they take, and whether each can run right now on the document.",
            inputSchema: schema([
                "document": documentProperty,
                "area": ["type": "string", "enum": .array(AppCommand.Area.allCases.map { .string($0.rawValue) }),
                         "description": "Only commands about this: timeline, layers, edit, measure or view."],
                "readyOnly": ["type": "boolean", "description": "Only the commands that can run right now."],
            ])),
        AgentTool(
            name: "run_command",
            description: "Run one command from list_commands by name, as its menu row does. It can pick a playhead time, layers, a piece or a track first. One run is one undo step.",
            inputSchema: schema([
                "document": documentProperty,
                "command": ["type": "string", "description": "The command's name from list_commands, such as split_at_playhead."],
                "arguments": ["type": "object", "description": "The command's arguments, as list_commands gives them."],
            ], required: ["command"])),
    ]

    public static func tool(named name: String) -> AgentTool? { all.first { $0.name == name } }

    // MARK: Checking a call

    /// A call checked against its tool's schema and made into a request, or
    /// the sentence saying what was wrong with it.
    public static func request(tool name: String, arguments: AgentJSON?) -> Result<AgentRequest, AgentToolError> {
        guard let tool = tool(named: name) else {
            return .failure(AgentToolError("There is no tool called \(name).", isUnknownTool: true))
        }
        let given = arguments ?? .object([:])
        if let problem = AgentSchema.problem(with: given, against: tool.inputSchema, at: "") {
            return .failure(AgentToolError("\(name): \(problem)"))
        }
        let args = given.objectValue ?? [:]
        let document = args["document"]?.stringValue
        let maxSize = args["maxSize"]?.intValue ?? defaultMaxSize
        switch name {
        case "list_documents":
            return .success(.listDocuments)
        case "list_history":
            return .success(.listHistory(limit: args["limit"]?.intValue ?? 20))
        case "open_document":
            switch (args["path"]?.stringValue, args["historyIndex"]?.intValue) {
            case (let path?, nil):
                return .success(.openDocument(.path(path)))
            case (nil, let index?):
                return .success(.openDocument(.history(index: index)))
            default:
                return .failure(AgentToolError("open_document: give either path or historyIndex, not both and not neither."))
            }
        case "read_document":
            return .success(.readDocument(document: document))
        case "render_picture":
            return .success(.renderPicture(document: document, layer: args["layer"]?.stringValue,
                                           region: region(args["region"]), maxSize: maxSize))
        case "video_frame":
            let seconds = args["seconds"]?.doubleValue ?? 0
            return .success(.videoFrame(document: document, atMS: ms(seconds),
                                        region: region(args["region"]), maxSize: maxSize))
        case "contact_sheet":
            let from = args["fromSeconds"]?.doubleValue.map(ms)
            let to = args["toSeconds"]?.doubleValue.map(ms)
            if let from, let to, to < from {
                return .failure(AgentToolError("contact_sheet: toSeconds comes before fromSeconds."))
            }
            return .success(.contactSheet(document: document, fromMS: from, toMS: to,
                                          count: args["count"]?.intValue ?? defaultSheetCount,
                                          columns: args["columns"]?.intValue,
                                          cellWidth: args["cellWidth"]?.intValue ?? defaultCellWidth))
        case "undo":
            return .success(.undo(document: document, steps: args["steps"]?.intValue ?? 1))
        case "redo":
            return .success(.redo(document: document, steps: args["steps"]?.intValue ?? 1))
        case "list_commands":
            return .success(.listCommands(document: document,
                                          area: args["area"]?.stringValue.flatMap(AppCommand.Area.init(rawValue:)),
                                          readyOnly: args["readyOnly"]?.boolValue ?? false))
        case "run_command":
            return AppCommandTable.call(args["command"]?.stringValue ?? "", arguments: args["arguments"])
                .map { .runCommand(document: document, call: $0) }
        default:
            return .failure(AgentToolError("There is no tool called \(name).", isUnknownTool: true))
        }
    }

    private static func ms(_ seconds: Double) -> Int { Int((seconds * 1000).rounded()) }

    private static func region(_ json: AgentJSON?) -> CGRect? {
        guard let json, let x = json["x"]?.doubleValue, let y = json["y"]?.doubleValue,
              let width = json["width"]?.doubleValue, let height = json["height"]?.doubleValue else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// The small part of JSON Schema the tools use: types, required properties,
/// no extra properties, and numeric bounds.
enum AgentSchema {
    static func problem(with value: AgentJSON, against schema: AgentJSON, at path: String) -> String? {
        let name = path.isEmpty ? "the arguments" : path
        if let type = schema["type"]?.stringValue, !matches(value, type) {
            return "\(name) should be \(article(type)) \(type), not \(article(value.typeName)) \(value.typeName)."
        }
        if let minimum = schema["minimum"]?.doubleValue, let number = value.doubleValue, number < minimum {
            return "\(name) is \(format(number)); it can be no less than \(format(minimum))."
        }
        if let maximum = schema["maximum"]?.doubleValue, let number = value.doubleValue, number > maximum {
            return "\(name) is \(format(number)); it can be no more than \(format(maximum))."
        }
        if let choices = schema["enum"]?.arrayValue, !choices.contains(value) {
            let said = choices.map { $0.stringValue ?? $0.doubleValue.map(format) ?? "?" }.joined(separator: ", ")
            return "\(name) should be one of \(said)."
        }
        if let items = schema["items"], let array = value.arrayValue {
            for (index, item) in array.enumerated() {
                if let problem = problem(with: item, against: items, at: "\(name)[\(index)]") { return problem }
            }
        }
        guard let object = value.objectValue else { return nil }
        let properties = schema["properties"]?.objectValue ?? [:]
        for required in schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
        where object[required] == nil {
            return "\(join(path, required)) is required."
        }
        if schema["additionalProperties"] == .bool(false) {
            let known = properties.keys.sorted().joined(separator: ", ")
            for key in object.keys.sorted() where properties[key] == nil {
                return known.isEmpty
                    ? "\(join(path, key)) is not an argument; this tool takes none."
                    : "\(join(path, key)) is not an argument; the arguments are \(known)."
            }
        }
        for key in object.keys.sorted() {
            guard let value = object[key], let property = properties[key] else { continue }
            if let problem = problem(with: value, against: property, at: join(path, key)) { return problem }
        }
        return nil
    }

    private static func matches(_ value: AgentJSON, _ type: String) -> Bool {
        switch type {
        case "integer": value.intValue != nil
        case "number": value.doubleValue != nil
        default: value.typeName == type || (type == "number" && value.typeName == "integer")
        }
    }

    private static func join(_ path: String, _ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }

    private static func article(_ word: String) -> String {
        ["a", "e", "i", "o", "u"].contains(word.prefix(1)) ? "an" : "a"
    }

    private static func format(_ number: Double) -> String {
        number.rounded() == number ? String(Int(number)) : String(number)
    }
}
