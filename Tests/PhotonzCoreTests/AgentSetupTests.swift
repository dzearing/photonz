import Foundation
import PhotonzAgentLink
import PhotonzCore
import Testing

/// Settings > Agents installs the Photonz server and skill for Claude Code and
/// GitHub Copilot (`docs/design/agent-mcp.md`, "Install"). These pin the one
/// promise that matters most: Install adds Photonz's own entry to a person's
/// config and Uninstall takes out only that, whatever else the file holds.
@Suite("Agent setup: installing into Claude Code and Copilot")
struct AgentSetupTests {

    static let helper = "/Applications/Photonz.app/Contents/Helpers/photonz-mcp"

    static func object(_ text: String?) throws -> [String: Any] {
        let data = Data((text ?? "").utf8)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Names and places

    @Test("Each build installs under a name of its own, so Dev and the shipping app sit side by side")
    func serverNames() {
        #expect(AgentSetup.serverName(bundleID: AgentChannelAddress.releaseBundleID) == "photonz")
        #expect(AgentSetup.serverName(bundleID: AgentChannelAddress.devBundleID) == "photonz-dev")
        #expect(AgentSetup.serverName(bundleID: AgentChannelAddress.probeBundleID) == "photonz-probe")
    }

    @Test("A bridge is Photonz's whether it is the bundled program or the repo's script")
    func bridgeRecognised() {
        #expect(AgentSetup.isPhotonzBridge(command: Self.helper))
        #expect(AgentSetup.isPhotonzBridge(command: "/Users/me/src/photonz/Scripts/photonz-mcp.sh"))
        #expect(!AgentSetup.isPhotonzBridge(command: "npx"))
        #expect(!AgentSetup.isPhotonzBridge(command: "/usr/local/bin/photonz-mcp-but-not"))
    }

    @Test("The places each tool reads its servers and skills from")
    func places() {
        #expect(AgentSetup.claudeSkillsDirectory(home: "/h") == "/h/.claude/skills")
        #expect(AgentSetup.claudeConfigPath(home: "/h") == "/h/.claude.json")
        #expect(AgentSetup.copilotSkillsDirectory(home: "/h") == "/h/.copilot/skills")
        #expect(AgentSetup.copilotConfigPath(home: "/h") == "/h/.copilot/mcp-config.json")
        #expect(AgentSetup.vsCodeConfigPath(home: "/h", edition: .stable)
            == "/h/Library/Application Support/Code/User/mcp.json")
        #expect(AgentSetup.vsCodeConfigPath(home: "/h", edition: .insiders)
            == "/h/Library/Application Support/Code - Insiders/User/mcp.json")
    }

    // MARK: Copilot CLI's config

    static let copilotConfig = """
    {
      "mcpServers": {
        "github": {
          "type": "http",
          "url": "https://api.example.com/mcp",
          "headers": { "Authorization": "Bearer abc" },
          "tools": ["*"]
        }
      },
      "theme": "dark"
    }
    """

    @Test("Install adds its entry to Copilot CLI's config and keeps everything else as it was")
    func copilotAdd() throws {
        let out = try AgentSetup.adding(name: "photonz", command: Self.helper, to: Self.copilotConfig, format: .copilotCLI)
        let after = try Self.object(out)
        let before = try Self.object(Self.copilotConfig)
        let servers = try #require(after["mcpServers"] as? [String: Any])
        let ours = try #require(servers["photonz"] as? [String: Any])
        #expect(ours["type"] as? String == "local")
        #expect(ours["command"] as? String == Self.helper)
        #expect(ours["args"] as? [String] == [])
        #expect(ours["tools"] as? [String] == ["*"])
        #expect(NSDictionary(dictionary: servers["github"] as? [String: Any] ?? [:])
            .isEqual(to: (before["mcpServers"] as? [String: Any])?["github"] as? [String: Any] ?? ["x": 1]))
        #expect(after["theme"] as? String == "dark")
    }

    @Test("Uninstall takes out only Photonz's entry: the file reads as it did before Install")
    func copilotRoundTrip() throws {
        let installed = try AgentSetup.adding(name: "photonz", command: Self.helper, to: Self.copilotConfig, format: .copilotCLI)
        let removed = try #require(try AgentSetup.removing(name: "photonz", from: installed, format: .copilotCLI))
        #expect(NSDictionary(dictionary: try Self.object(removed)).isEqual(to: try Self.object(Self.copilotConfig)))
    }

    @Test("No config yet: Install writes one holding only Photonz")
    func copilotFresh() throws {
        for start in [nil, "", "  \n"] as [String?] {
            let out = try AgentSetup.adding(name: "photonz", command: Self.helper, to: start, format: .copilotCLI)
            let servers = try #require(try Self.object(out)["mcpServers"] as? [String: Any])
            #expect(Array(servers.keys) == ["photonz"])
        }
    }

    @Test("Installing again replaces Photonz's own entry, from this copy or an older one, and nothing else")
    func reinstall() throws {
        let old = try AgentSetup.adding(name: "photonz", command: "/Users/me/src/photonz/Scripts/photonz-mcp.sh",
                                        to: Self.copilotConfig, format: .copilotCLI)
        let new = try AgentSetup.adding(name: "photonz", command: Self.helper, to: old, format: .copilotCLI)
        #expect(AgentSetup.command(named: "photonz", in: new, format: .copilotCLI) == Self.helper)
        let servers = try #require(try Self.object(new)["mcpServers"] as? [String: Any])
        #expect(Set(servers.keys) == ["github", "photonz"])
    }

    @Test("A server of the same name that is not Photonz's is never overwritten or removed")
    func someoneElsesServer() throws {
        let theirs = """
        {"mcpServers": {"photonz": {"type": "local", "command": "/opt/my/own-photonz-thing", "args": []}}}
        """
        #expect(throws: AgentSetup.ConfigError.taken(command: "/opt/my/own-photonz-thing")) {
            try AgentSetup.adding(name: "photonz", command: Self.helper, to: theirs, format: .copilotCLI)
        }
        #expect(try AgentSetup.removing(name: "photonz", from: theirs, format: .copilotCLI) == nil)
    }

    @Test("Uninstall with nothing of Photonz's in the file leaves the file alone")
    func removeNothing() throws {
        #expect(try AgentSetup.removing(name: "photonz", from: Self.copilotConfig, format: .copilotCLI) == nil)
        #expect(try AgentSetup.removing(name: "photonz", from: nil, format: .copilotCLI) == nil)
    }

    // MARK: VS Code's config

    static let vsCodeConfig = """
    {
    \t"servers": {
    \t\t"browser-tools": {
    \t\t\t"type": "stdio",
    \t\t\t"command": "npx",
    \t\t\t"args": ["@agentdeskai/browser-tools-mcp@1.2.0"]
    \t\t}
    \t},
    \t"inputs": [{"type": "promptString", "id": "key", "description": "API key", "password": true}]
    }
    """

    @Test("Install adds a stdio server to VS Code's mcp.json and keeps the person's servers and inputs")
    func vsCodeAdd() throws {
        let out = try AgentSetup.adding(name: "photonz", command: Self.helper, to: Self.vsCodeConfig, format: .vsCode)
        let after = try Self.object(out)
        let servers = try #require(after["servers"] as? [String: Any])
        let ours = try #require(servers["photonz"] as? [String: Any])
        #expect(ours["type"] as? String == "stdio")
        #expect(ours["command"] as? String == Self.helper)
        #expect(servers["browser-tools"] != nil)
        let inputs = try #require(after["inputs"] as? [[String: Any]])
        #expect(inputs.first?["password"] as? Bool == true)
        #expect(after["mcpServers"] == nil, "VS Code keeps its servers under \"servers\"")
        let removed = try #require(try AgentSetup.removing(name: "photonz", from: out, format: .vsCode))
        #expect(NSDictionary(dictionary: try Self.object(removed)).isEqual(to: try Self.object(Self.vsCodeConfig)))
    }

    @Test("A config with comments is refused rather than rewritten without them")
    func comments() {
        let commented = """
        {
          // my servers
          "servers": { "a": { "type": "stdio", "command": "x" }, },
        }
        """
        #expect(throws: AgentSetup.ConfigError.hasComments) {
            try AgentSetup.adding(name: "photonz", command: Self.helper, to: commented, format: .vsCode)
        }
        #expect(throws: AgentSetup.ConfigError.hasComments) {
            try AgentSetup.removing(name: "photonz", from: commented, format: .vsCode)
        }
    }

    @Test("A config that is not JSON at all is refused")
    func unreadable() {
        #expect(throws: AgentSetup.ConfigError.unreadable) {
            try AgentSetup.adding(name: "photonz", command: Self.helper, to: "servers = [", format: .vsCode)
        }
        #expect(throws: AgentSetup.ConfigError.unreadable) {
            try AgentSetup.adding(name: "photonz", command: Self.helper, to: "[1, 2]", format: .vsCode)
        }
    }

    // MARK: Claude Code

    /// The shape `claude mcp add --scope user` leaves in `~/.claude.json`,
    /// among the many other things Claude Code keeps there.
    static let claudeConfig = """
    {
      "numStartups": 412,
      "projects": { "/Users/me/src/app": { "mcpServers": { "photonz": { "type": "stdio", "command": "nope" } } } },
      "mcpServers": {
        "browser": { "type": "stdio", "command": "npx", "args": ["browser-mcp"], "env": {} },
        "photonz": { "type": "stdio", "command": "/Applications/Photonz.app/Contents/Helpers/photonz-mcp", "args": [], "env": {} }
      }
    }
    """

    @Test("Claude Code's user servers are read from the top of ~/.claude.json, never a project's")
    func claudeRead() {
        #expect(AgentSetup.command(named: "photonz", in: Self.claudeConfig, format: .claudeCode) == Self.helper)
        #expect(AgentSetup.command(named: "browser", in: Self.claudeConfig, format: .claudeCode) == "npx")
        #expect(AgentSetup.command(named: "photonz-dev", in: Self.claudeConfig, format: .claudeCode) == nil)
        #expect(AgentSetup.command(named: "photonz", in: nil, format: .claudeCode) == nil)
    }

    @Test("Claude Code gets its server through its own command, for this user, as a stdio server")
    func claudeArguments() throws {
        let add = AgentSetup.claudeAddArguments(name: "photonz", command: Self.helper)
        #expect(Array(add.prefix(5)) == ["mcp", "add-json", "--scope", "user", "photonz"])
        let json = try Self.object(add.last)
        #expect(json["type"] as? String == "stdio")
        #expect(json["command"] as? String == Self.helper)
        #expect(AgentSetup.claudeRemoveArguments(name: "photonz") == ["mcp", "remove", "--scope", "user", "photonz"])
    }

    @Test("Claude Code's own copy of ~/.claude.json, with an entry added by its command, keeps every other key")
    func claudeAddSample() throws {
        // The app leaves this file to Claude Code's own command; the shared
        // transform still keeps a file of this shape whole.
        let out = try AgentSetup.adding(name: "photonz-dev", command: Self.helper, to: Self.claudeConfig, format: .claudeCode)
        let after = try Self.object(out)
        #expect(after["numStartups"] as? Int == 412)
        #expect(after["projects"] != nil)
        let servers = try #require(after["mcpServers"] as? [String: Any])
        #expect(Set(servers.keys) == ["browser", "photonz", "photonz-dev"])
        let removed = try #require(try AgentSetup.removing(name: "photonz-dev", from: out, format: .claudeCode))
        #expect(NSDictionary(dictionary: try Self.object(removed)).isEqual(to: try Self.object(Self.claudeConfig)))
    }

    @Test("Another build's Photonz server is seen, so Uninstall keeps the skill it also reads")
    func otherBuilds() throws {
        let both = try AgentSetup.adding(name: "photonz-dev", command: "/x/Photonz Dev.app/Contents/Helpers/photonz-mcp",
                                         to: Self.claudeConfig, format: .claudeCode)
        #expect(AgentSetup.otherPhotonzServers(in: both, format: .claudeCode, except: "photonz-dev") == ["photonz"])
        #expect(AgentSetup.otherPhotonzServers(in: both, format: .claudeCode, except: "photonz") == ["photonz-dev"])
        #expect(AgentSetup.otherPhotonzServers(in: Self.copilotConfig, format: .copilotCLI, except: "photonz").isEmpty)
    }

    // MARK: What a row says

    @Test("A server entry is current, an older Photonz's, someone else's, or absent")
    func serverSlot() {
        #expect(AgentSetup.serverSlot(command: nil, ours: Self.helper) == .absent)
        #expect(AgentSetup.serverSlot(command: Self.helper, ours: Self.helper) == .current)
        #expect(AgentSetup.serverSlot(command: "/Volumes/Old/Photonz.app/Contents/Helpers/photonz-mcp", ours: Self.helper) == .stale)
        #expect(AgentSetup.serverSlot(command: "npx", ours: Self.helper) == .theirs)
    }

    @Test("A skill folder is ours when Photonz marked it or the repo's install linked it")
    func skillSlot() {
        let text = "---\nname: photonz\n---\n"
        #expect(AgentSetup.skillSlot(exists: false, linkDestination: nil, marked: false, installed: nil, bundled: text) == .absent)
        #expect(AgentSetup.skillSlot(exists: true, linkDestination: nil, marked: true, installed: text, bundled: text) == .current)
        #expect(AgentSetup.skillSlot(exists: true, linkDestination: nil, marked: true, installed: "old", bundled: text) == .stale)
        #expect(AgentSetup.skillSlot(exists: true, linkDestination: "/Users/me/src/photonz/plugin/skills/photonz",
                                     marked: false, installed: text, bundled: text) == .stale)
        #expect(AgentSetup.skillSlot(exists: true, linkDestination: nil, marked: false, installed: text, bundled: text) == .theirs)
    }

    @Test("The row: not found, ready to install, installed, out of date, or held up by something not ours")
    func rowState() {
        #expect(AgentSetup.rowState(found: false, slots: [.absent, .absent]) == .notFound)
        #expect(AgentSetup.rowState(found: true, slots: [.absent, .absent]) == .notInstalled)
        #expect(AgentSetup.rowState(found: true, slots: [.current, .current]) == .installed)
        // Uninstall stays reachable when the tool itself has since gone.
        #expect(AgentSetup.rowState(found: false, slots: [.current, .current]) == .installed)
        #expect(AgentSetup.rowState(found: true, slots: [.current, .absent]) == .needsUpdate)
        #expect(AgentSetup.rowState(found: true, slots: [.stale, .current]) == .needsUpdate)
        #expect(AgentSetup.rowState(found: true, slots: [.theirs, .absent]) == .taken)
    }
}

/// The bridge inside a bundle reaches the app it ships in, so a server
/// installed from the shipping app never drives a Dev build and the other way
/// round (`docs/design/agent-mcp.md`, "How it reaches the app").
@Suite("Agent channel: the bundled bridge reaches its own app")
struct AgentBundledBridgeTests {

    @Test("The app a bundled bridge sits in is found from its own path")
    func ownBundle() {
        #expect(AgentChannelAddress.bundle(containingHelper: "/Applications/Photonz.app/Contents/Helpers/photonz-mcp")
            == "/Applications/Photonz.app")
        #expect(AgentChannelAddress.bundle(containingHelper: "/Users/me/dist/Photonz Dev.app/Contents/Helpers/photonz-mcp")
            == "/Users/me/dist/Photonz Dev.app")
        #expect(AgentChannelAddress.bundle(containingHelper: "/Users/me/src/photonz/.build-mcp/release/PhotonzMCP") == nil)
    }

    @Test("Its own app is the default; PHOTONZ_APP and a go loop session still win")
    func choice() {
        let own = AgentChannelAddress.releaseBundleID
        #expect(AgentChannelAddress.choice(environment: [:], ownBundleID: own) == own)
        #expect(AgentChannelAddress.candidates(for: AgentChannelAddress.choice(environment: [:], ownBundleID: own)) == [own])
        #expect(AgentChannelAddress.choice(environment: ["PHOTONZ_APP": "dev"], ownBundleID: own) == "dev")
        #expect(AgentChannelAddress.choice(environment: ["GO_LOOP_PID": "12"], ownBundleID: own) == "probe")
        #expect(AgentChannelAddress.choice(environment: [:], ownBundleID: nil) == nil)
    }
}
