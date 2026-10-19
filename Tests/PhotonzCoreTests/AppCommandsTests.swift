import Foundation
import PhotonzCore
import Testing

/// The table of every command the app runs, by name (`AppCommands.swift`,
/// `docs/design/agent-mcp.md` slice 2), and the checking of an agent's call
/// against it.
@Suite("App commands: one table, checked calls")
struct AppCommandsTests {

    static func args(_ json: String) throws -> AgentJSON {
        try AgentJSON.parse(Data(json.utf8))
    }

    @Test("Every command name has exactly one row in the table")
    func everyNameHasOneRow() {
        let ids = AppCommandTable.all.map(\.id)
        #expect(Set(ids).count == ids.count, "a command is in the table twice")
        for id in AppCommandID.allCases {
            #expect(AppCommandTable.command(id) != nil, "\(id.rawValue) has no row")
        }
    }

    @Test("Names are short snake case an agent can type")
    func namesAreClean() {
        for command in AppCommandTable.all {
            #expect(command.name.range(of: "^[a-z][a-z_]{1,40}$", options: .regularExpression) != nil,
                    "\(command.name)")
        }
    }

    @Test("Every command says where it lives and when it runs, in plain words")
    func everyCommandIsDescribed() {
        for command in AppCommandTable.all {
            #expect(!command.title.isEmpty, "\(command.name) has no title")
            #expect(!command.menu.isEmpty, "\(command.name) has no menu")
            #expect(!command.needs.isEmpty && command.needs.count <= 80, "\(command.name): \(command.needs)")
            let words = (command.title + command.needs + command.menu).lowercased()
            #expect(!words.contains("claude") && !words.contains("anthropic"), "\(command.name)")
            #expect(!words.contains("\u{2014}"), "\(command.name) has an em dash")
        }
    }

    @Test("Every command's schema is an object whose required arguments it declares")
    func schemasAreWellFormed() {
        for command in AppCommandTable.all {
            let schema = command.inputSchema
            #expect(schema["type"]?.stringValue == "object")
            #expect(schema["additionalProperties"] == .bool(false))
            let properties = schema["properties"]?.objectValue ?? [:]
            for required in schema["required"]?.arrayValue ?? [] {
                #expect(properties[required.stringValue ?? ""] != nil, "\(command.name) requires \(required)")
            }
            for (name, property) in properties {
                #expect(property["type"] != nil, "\(command.name).\(name) has no type")
                #expect(property["description"]?.stringValue?.isEmpty == false, "\(command.name).\(name)")
            }
        }
    }

    @Test("A command that picks a clip at a moment takes the playhead, layers and a piece")
    func picksBecomeArguments() {
        let split = AppCommandTable.command(.splitAtPlayhead)
        let names = Set(split?.arguments.map(\.name) ?? [])
        #expect(names == ["seconds", "layers", "piece"])
        let snap = AppCommandTable.command(.snapInTimeline)
        #expect(snap?.arguments.map(\.name) == ["on"], "a toggle takes on")
    }

    // MARK: Calls

    @Test("Cut the clip at 5 seconds: the call moves the playhead to 5000 ms first")
    func splitAtFiveSeconds() throws {
        let call = try AppCommandTable.call("split_at_playhead", arguments: Self.args(#"{"seconds": 5}"#)).get()
        #expect(call == AppCommandCall(.splitAtPlayhead, atMS: 5000))
        #expect(call.picksAnything)
    }

    @Test("No arguments is the menu row's own call: it acts on what is in hand")
    func noArgumentsIsTheMenuCall() throws {
        let call = try AppCommandTable.call("extract", arguments: nil).get()
        #expect(call == .menu(.extract))
        #expect(!call.picksAnything)
    }

    @Test("A command's own arguments come through, checked against their choices")
    func ownArguments() throws {
        let call = try AppCommandTable.call("set_transition",
                                            arguments: Self.args(#"{"kind": "dipToBlack", "seconds": 2.5}"#)).get()
        #expect(call.word("kind") == "dipToBlack")
        #expect(call.atMS == 2500)
        let speed = try AppCommandTable.call("set_speed", arguments: Self.args(#"{"percent": 200}"#)).get()
        #expect(speed.integer("percent") == 200)
    }

    @Test("A word that is not one of the choices is refused, naming them")
    func badChoiceIsRefused() throws {
        let result = AppCommandTable.call("set_transition", arguments: try Self.args(#"{"kind": "starWipe"}"#))
        guard case .failure(let error) = result else { Issue.record("starWipe was accepted"); return }
        #expect(error.message.contains("kind"))
        #expect(error.message.contains("dissolve"))
    }

    @Test("A speed the menu does not offer is refused")
    func badSpeedIsRefused() throws {
        let result = AppCommandTable.call("set_speed", arguments: try Self.args(#"{"percent": 123}"#))
        guard case .failure = result else { Issue.record("123% was accepted"); return }
    }

    @Test("A required argument left out is refused")
    func missingRequiredIsRefused() {
        guard case .failure(let error) = AppCommandTable.call("align", arguments: nil) else {
            Issue.record("align ran with no edge"); return
        }
        #expect(error.message.contains("edge is required"))
    }

    @Test("An argument the command does not take is refused, naming the ones it does")
    func extraArgumentIsRefused() throws {
        guard case .failure(let error) = AppCommandTable.call("extract", arguments: try Self.args(#"{"seconds": 1}"#))
        else { Issue.record("extract took seconds"); return }
        #expect(error.message.contains("this tool takes none") || error.message.contains("not an argument"))
    }

    @Test("Layers must be a list of ids, and a piece needs exactly one of them")
    func layersAndPieces() throws {
        let ok = try AppCommandTable.call("split_at_playhead",
                                          arguments: Self.args(#"{"layers": ["A"], "piece": 1}"#)).get()
        #expect(ok.layers == ["A"])
        #expect(ok.piece == 1)
        guard case .failure(let error) = AppCommandTable.call(
            "split_at_playhead", arguments: try Self.args(#"{"piece": 1}"#)) else {
            Issue.record("a piece with no clip was accepted"); return
        }
        #expect(error.message.contains("piece"))
        guard case .failure = AppCommandTable.call("split_at_playhead",
                                                   arguments: try Self.args(#"{"layers": [3]}"#)) else {
            Issue.record("a number was accepted as a layer id"); return
        }
    }

    @Test("A toggle is told on or off, or flips")
    func toggles() throws {
        #expect(try AppCommandTable.call("snap_in_timeline", arguments: Self.args(#"{"on": false}"#)).get().on == false)
        #expect(try AppCommandTable.call("snap_in_timeline", arguments: nil).get().on == nil)
    }

    @Test("A name that is not a command is refused with the nearest one")
    func unknownNameSuggests() {
        guard case .failure(let error) = AppCommandTable.call("split", arguments: nil) else {
            Issue.record("split ran"); return
        }
        #expect(error.message.contains("list_commands"))
        #expect(error.message.contains("Did you mean split_"))
    }

    // MARK: Listing

    @Test("A listing says name, words, menu, what it needs, and whether it can run now")
    func listing() {
        guard let split = AppCommandTable.command(.splitAtPlayhead) else { Issue.record("no split"); return }
        let entry = AppCommandTable.listing(split, ready: true)
        #expect(entry["name"]?.stringValue == "split_at_playhead")
        #expect(entry["title"]?.stringValue == "Split at Playhead")
        #expect(entry["menu"]?.stringValue == "Clip")
        #expect(entry["area"]?.stringValue == "timeline")
        #expect(entry["ready"] == .bool(true))
        #expect(entry["arguments"]?["seconds"]?["type"]?.stringValue == "number")
        let stop = AppCommandTable.command(.stop).map { AppCommandTable.listing($0, ready: false) }
        #expect(stop?["arguments"] == nil, "a command with no arguments lists none")
    }
}
