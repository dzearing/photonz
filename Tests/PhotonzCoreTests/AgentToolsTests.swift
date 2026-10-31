import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The tools an agent is offered through the MCP channel (`docs/design/agent-mcp.md`):
/// every one carries a schema a client can read, and every call is checked
/// against it before the app is asked to do anything.
@Suite("Agent tools: schemas and checked calls")
struct AgentToolsTests {

    static func args(_ json: String) throws -> AgentJSON {
        try AgentJSON.parse(Data(json.utf8))
    }

    @Test("The slices offer the reach, read, see and undo tools, the commands, drawing, video, design, components, then brushes")
    func theSliceIsComplete() {
        #expect(AgentTools.all.map(\.name) == [
            "list_documents", "list_history", "open_document", "read_document",
            "render_picture", "video_frame", "contact_sheet", "undo", "redo",
            "list_commands", "run_command",
            "new_picture", "add_shape", "add_path", "add_drawing", "add_photo", "add_text", "set_layer", "find_elements",
            "add_measurement", "find_measurements", "mark_measurements", "find_misalignments", "mark_misalignments",
            "list_components", "place_component",
            "export", "new_video", "add_clip", "cut", "trim", "move_clip", "set_transition", "add_title",
            "list_titles", "recommended_zooms", "apply_zooms", "set_playhead",
            "list_styles", "add_style", "apply_style", "set_layout",
            "add_component",
            "list_brushes", "set_brush", "paint_stroke",
            "change_part",
        ])
    }

    @Test("list_commands filters by area and by what can run now")
    func listCommands() throws {
        let request = try AgentTools.request(tool: "list_commands",
                                             arguments: Self.args(#"{"area": "timeline", "readyOnly": true}"#)).get()
        #expect(request == .listCommands(document: nil, area: .timeline, readyOnly: true))
        #expect(try AgentTools.request(tool: "list_commands", arguments: nil).get()
                == .listCommands(document: nil, area: nil, readyOnly: false))
        guard case .failure = AgentTools.request(tool: "list_commands", arguments: try Self.args(#"{"area": "sky"}"#))
        else { Issue.record("an area that does not exist was accepted"); return }
    }

    @Test("run_command checks the command's own arguments before the app sees them")
    func runCommand() throws {
        let request = try AgentTools.request(
            tool: "run_command",
            arguments: Self.args(#"{"document": "d1", "command": "split_at_playhead", "arguments": {"seconds": 5}}"#)).get()
        #expect(request == .runCommand(document: "d1", call: AppCommandCall(.splitAtPlayhead, atMS: 5000)))
        guard case .failure(let error) = AgentTools.request(
            tool: "run_command", arguments: try Self.args(#"{"command": "split_at_playhead", "arguments": {"secs": 5}}"#))
        else { Issue.record("a misspelt argument was accepted"); return }
        #expect(error.message.contains("secs is not an argument"))
        #expect(!error.isUnknownTool, "a bad command is the tool's error, not the protocol's")
        guard case .failure = AgentTools.request(tool: "run_command", arguments: nil)
        else { Issue.record("run_command ran with no command"); return }
    }

    @Test("Every tool has a description and an object schema whose required arguments it declares")
    func schemasAreWellFormed() {
        for tool in AgentTools.all {
            #expect(!tool.description.isEmpty, "\(tool.name) says nothing about itself")
            #expect(tool.description.count <= 400, "\(tool.name)'s description is too long to read")
            let schema = tool.inputSchema
            #expect(schema["type"]?.stringValue == "object", "\(tool.name)")
            #expect(schema["additionalProperties"] == .bool(false), "\(tool.name) takes anything")
            let properties = schema["properties"]?.objectValue ?? [:]
            for required in schema["required"]?.arrayValue ?? [] {
                #expect(properties[required.stringValue ?? ""] != nil,
                        "\(tool.name) requires \(required) without declaring it")
            }
            for (name, property) in properties {
                #expect(property["type"] != nil || property["anyOf"] != nil, "\(tool.name).\(name) has no type")
                let words = property["description"]?.stringValue ?? ""
                #expect(words.isEmpty == false, "\(tool.name).\(name) has no description")
            }
        }
    }

    @Test("Tool names are unique and in the form clients accept")
    func namesAreClean() {
        let names = AgentTools.all.map(\.name)
        #expect(Set(names).count == names.count)
        for name in names {
            #expect(name.range(of: "^[a-z][a-z_]{2,40}$", options: .regularExpression) != nil, "\(name)")
        }
    }

    @Test("No tool description names a vendor")
    func noVendorNames() {
        for tool in AgentTools.all {
            let words = (tool.description + (tool.inputSchema.encodedString())).lowercased()
            #expect(!words.contains("claude") && !words.contains("anthropic"), "\(tool.name)")
        }
    }

    @Test("A call with no arguments takes the front document and the defaults")
    func defaults() throws {
        #expect(try AgentTools.request(tool: "list_documents", arguments: nil).get() == .listDocuments)
        #expect(try AgentTools.request(tool: "read_document", arguments: .object([:])).get()
                == .readDocument(document: nil, layer: nil))
        #expect(try AgentTools.request(tool: "render_picture", arguments: nil).get()
                == .renderPicture(document: nil, layer: nil, region: nil, maxSize: AgentTools.defaultMaxSize))
        #expect(try AgentTools.request(tool: "undo", arguments: nil).get() == .undo(document: nil, steps: 1))
        #expect(try AgentTools.request(tool: "list_history", arguments: nil).get() == .listHistory(limit: 20))
    }

    @Test("A video frame is asked for in seconds and handed to the app in milliseconds")
    func frameInSeconds() throws {
        let request = try AgentTools.request(tool: "video_frame",
                                             arguments: Self.args(#"{"seconds": 10, "document": "d2"}"#)).get()
        #expect(request == .videoFrame(document: "d2", atMS: 10_000, region: nil, maxSize: AgentTools.defaultMaxSize))
        let fraction = try AgentTools.request(tool: "video_frame", arguments: Self.args(#"{"seconds": 1.2345}"#)).get()
        #expect(fraction == .videoFrame(document: nil, atMS: 1235, region: nil, maxSize: AgentTools.defaultMaxSize))
    }

    @Test("A region and a layer reach the app as a rectangle and an id")
    func regionAndLayer() throws {
        let request = try AgentTools.request(tool: "render_picture", arguments: Self.args(
            #"{"layer": "ABC", "region": {"x": 10, "y": 20, "width": 300, "height": 200}, "maxSize": 512}"#)).get()
        #expect(request == .renderPicture(document: nil, layer: "ABC",
                                          region: CGRect(x: 10, y: 20, width: 300, height: 200), maxSize: 512))
    }

    @Test("A contact sheet takes a range and a count, and stays within bounds")
    func contactSheet() throws {
        let request = try AgentTools.request(tool: "contact_sheet", arguments: Self.args(
            #"{"fromSeconds": 2, "toSeconds": 8, "count": 6, "columns": 3}"#)).get()
        #expect(request == .contactSheet(document: nil, fromMS: 2000, toMS: 8000, count: 6, columns: 3,
                                         cellWidth: AgentTools.defaultCellWidth))
        let tooMany = AgentTools.request(tool: "contact_sheet", arguments: try Self.args(#"{"count": 500}"#))
        #expect(tooMany.failure?.message.contains("count") == true)
    }

    @Test("open_document takes a file or a History item, exactly one")
    func openTakesOne() throws {
        #expect(try AgentTools.request(tool: "open_document", arguments: Self.args(#"{"path": "/tmp/a.png"}"#)).get()
                == .openDocument(.path("/tmp/a.png")))
        #expect(try AgentTools.request(tool: "open_document", arguments: Self.args(#"{"historyIndex": 0}"#)).get()
                == .openDocument(.history(index: 0)))
        #expect(AgentTools.request(tool: "open_document", arguments: nil).failure != nil)
        #expect(AgentTools.request(tool: "open_document",
                                   arguments: try Self.args(#"{"path": "/a", "historyIndex": 1}"#)).failure != nil)
    }

    @Test("A wrong argument is refused with a sentence that names it")
    func refusals() throws {
        let unknown = AgentTools.request(tool: "undo", arguments: try Self.args(#"{"stepz": 2}"#))
        #expect(unknown.failure?.message.contains("stepz") == true)
        let wrongType = AgentTools.request(tool: "video_frame", arguments: try Self.args(#"{"seconds": "ten"}"#))
        #expect(wrongType.failure?.message.contains("seconds") == true)
        let missing = AgentTools.request(tool: "video_frame", arguments: nil)
        #expect(missing.failure?.message.contains("seconds") == true)
        let fractionalInt = AgentTools.request(tool: "undo", arguments: try Self.args(#"{"steps": 1.5}"#))
        #expect(fractionalInt.failure?.message.contains("steps") == true)
        let negative = AgentTools.request(tool: "video_frame", arguments: try Self.args(#"{"seconds": -1}"#))
        #expect(negative.failure?.message.contains("seconds") == true)
        let notATool = AgentTools.request(tool: "paint_it_black", arguments: nil)
        #expect(notATool.failure?.isUnknownTool == true)
        let notAnObject = AgentTools.request(tool: "undo", arguments: .array([]))
        #expect(notAnObject.failure != nil)
    }

    @Test("The system font's other names are read as SF Pro, so a plan never dies on one")
    func systemFontNames() throws {
        for name in ["SF Pro Display", "SF Pro Text", "San Francisco", "System", "-apple-system", "system-ui", ".AppleSystemUIFont"] {
            let request = try AgentTools.request(tool: "add_text", arguments: Self.args(#"{"text":"Hi","x":0,"y":0,"fontName":"\#(name)"}"#)).get()
            guard case .addText(_, let text) = request else { Issue.record("\(request)"); continue }
            #expect(text.fontName == nil, "\(name) should be the system font")
        }
        for name in ["SF Pro Rounded", "New York", "Helvetica Neue"] {
            let request = try AgentTools.request(tool: "add_text", arguments: Self.args(#"{"text":"Hi","x":0,"y":0,"fontName":"\#(name)"}"#)).get()
            guard case .addText(_, let text) = request else { Issue.record("\(request)"); continue }
            #expect(text.fontName == name, "\(name) is a font of its own")
        }
        let style = try AgentTools.request(tool: "add_style", arguments: Self.args(#"{"kind":"text","name":"Body","font":"SF Pro Text"}"#)).get()
        guard case .addStyle(_, .text(_, let treatment)) = style else { Issue.record("\(style)"); return }
        #expect(treatment.fontName == "SF Pro")
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }

}
