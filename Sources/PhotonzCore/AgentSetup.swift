import Foundation

/// What Settings > Agents writes, and where (`docs/design/agent-mcp.md`,
/// "Install"): the Photonz server registered with Claude Code or GitHub Copilot
/// (VS Code and the Copilot CLI), and the Photonz skill copied where that tool
/// reads skills. The app does the file and process work; this decides what to
/// write and judges what is already there.
///
/// One promise above all: Install adds Photonz's own entry and Uninstall takes
/// out only that. A server or a skill of the same name that is not Photonz's is
/// never overwritten or removed, and a config file this cannot rewrite exactly
/// (one with comments) is refused rather than rewritten without them.
public enum AgentSetup {

    /// The bridge program's file name inside the bundle (`Contents/Helpers`).
    public static let helperName = "photonz-mcp"
    /// The repo's launcher, which `Scripts/install-mcp.sh` registers.
    public static let repoLauncherName = "photonz-mcp.sh"
    /// The skill's folder name, in the bundle and where it is installed.
    public static let skillName = "photonz"
    /// The file Install leaves in a skill folder it copied, so Uninstall knows
    /// the folder is Photonz's to take back.
    public static let markerName = ".installed-by-photonz"

    public enum Tool: String, CaseIterable, Sendable, Codable {
        case claudeCode, copilot
    }

    // MARK: Names and places

    /// The name each build installs under: the shipping app as "photonz", the
    /// Dev and Probe builds beside it, so installing one never replaces another.
    public static func serverName(bundleID: String) -> String {
        switch bundleID {
        case "com.dzearing.photonz": "photonz"
        case "com.dzearing.photonz.dev": "photonz-dev"
        case "com.dzearing.photonz.probe": "photonz-probe"
        default: "photonz-" + (bundleID.split(separator: ".").last.map(String.init) ?? "app")
        }
    }

    /// Whether a server's command is a Photonz bridge: the bundled program of
    /// any copy of the app, or the repo's launcher script.
    public static func isPhotonzBridge(command: String) -> Bool {
        let name = (command as NSString).lastPathComponent
        return name == helperName || name == repoLauncherName
    }

    public static func claudeConfigPath(home: String) -> String { home + "/.claude.json" }
    public static func claudeSkillsDirectory(home: String) -> String { home + "/.claude/skills" }
    public static func copilotConfigPath(home: String) -> String { home + "/.copilot/mcp-config.json" }
    public static func copilotSkillsDirectory(home: String) -> String { home + "/.copilot/skills" }

    public enum VSCodeEdition: String, CaseIterable, Sendable {
        case stable = "Code"
        case insiders = "Code - Insiders"

        public var bundleID: String {
            switch self {
            case .stable: "com.microsoft.VSCode"
            case .insiders: "com.microsoft.VSCodeInsiders"
            }
        }
    }

    public static func vsCodeConfigPath(home: String, edition: VSCodeEdition) -> String {
        home + "/Library/Application Support/" + edition.rawValue + "/User/mcp.json"
    }

    // MARK: Config files

    /// Which file shape: the key the servers live under and how an entry looks.
    public enum ConfigFormat: Sendable {
        /// `~/.claude.json`: `mcpServers` at the top (a project's own servers
        /// sit deeper and are never read).
        case claudeCode
        /// `~/.copilot/mcp-config.json`: `mcpServers`, type `local`.
        case copilotCLI
        /// VS Code's `User/mcp.json`: `servers`, type `stdio`.
        case vsCode

        var serversKey: String { self == .vsCode ? "servers" : "mcpServers" }

        func entry(command: String) -> [String: Any] {
            switch self {
            case .copilotCLI: ["type": "local", "command": command, "args": [String](), "tools": ["*"]]
            case .claudeCode, .vsCode: ["type": "stdio", "command": command, "args": [String]()]
            }
        }
    }

    public enum ConfigError: Error, Equatable, Sendable {
        /// The file has comments or trailing commas, which rewriting would lose.
        case hasComments
        /// The file is not a JSON object.
        case unreadable
        /// A server of that name is there and is not Photonz's.
        case taken(command: String)
    }

    /// `text` with Photonz's server `name` running `command` added, or put
    /// back in place of an older Photonz's. Everything else stays.
    public static func adding(name: String, command: String, to text: String?, format: ConfigFormat) throws -> String {
        var root = try parse(text)
        var servers = root[format.serversKey] as? [String: Any] ?? [:]
        if let existing = servers[name] as? [String: Any] {
            let theirs = existing["command"] as? String ?? ""
            if !isPhotonzBridge(command: theirs) { throw ConfigError.taken(command: theirs) }
        } else if servers[name] != nil {
            throw ConfigError.taken(command: "")
        }
        servers[name] = format.entry(command: command)
        root[format.serversKey] = servers
        return try write(root)
    }

    /// `text` with Photonz's server `name` taken out, or nil when there is
    /// nothing of Photonz's to take (absent, or someone else's of that name).
    public static func removing(name: String, from text: String?, format: ConfigFormat) throws -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var root = try parse(text)
        guard var servers = root[format.serversKey] as? [String: Any],
              let existing = servers[name] as? [String: Any],
              isPhotonzBridge(command: existing["command"] as? String ?? "") else { return nil }
        servers[name] = nil
        root[format.serversKey] = servers
        return try write(root)
    }

    /// The command of the server `name`, if the file has one.
    public static func command(named name: String, in text: String?, format: ConfigFormat) -> String? {
        guard let root = try? parse(text),
              let servers = root[format.serversKey] as? [String: Any],
              let entry = servers[name] as? [String: Any] else { return nil }
        return entry["command"] as? String
    }

    /// The other Photonz servers in a file (another build's, the repo's), by
    /// name. Uninstall leaves the shared skill in place while any remain,
    /// since they read it too.
    public static func otherPhotonzServers(in text: String?, format: ConfigFormat, except name: String) -> [String] {
        guard let root = try? parse(text), let servers = root[format.serversKey] as? [String: Any] else { return [] }
        return servers.compactMap { key, value in
            guard key != name, let command = (value as? [String: Any])?["command"] as? String,
                  isPhotonzBridge(command: command) else { return nil }
            return key
        }.sorted()
    }

    private static func parse(_ text: String?) throws -> [String: Any] {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        let data = Data(text.utf8)
        if let object = try? JSONSerialization.jsonObject(with: data) {
            guard let root = object as? [String: Any] else { throw ConfigError.unreadable }
            return root
        }
        if (try? JSONSerialization.jsonObject(with: data, options: .json5Allowed)) is [String: Any] {
            throw ConfigError.hasComments
        }
        throw ConfigError.unreadable
    }

    private static func write(_ root: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: root,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    // MARK: Claude Code's own command

    /// `claude` arguments that register the server for this user. Claude Code
    /// owns `~/.claude.json` and its running sessions rewrite it constantly,
    /// so its own command does the writing.
    public static func claudeAddArguments(name: String, command: String) -> [String] {
        let json = (try? write(ConfigFormat.claudeCode.entry(command: command)))?
            .replacingOccurrences(of: "\n", with: "") ?? ""
        return ["mcp", "add-json", "--scope", "user", name, json]
    }

    public static func claudeRemoveArguments(name: String) -> [String] {
        ["mcp", "remove", "--scope", "user", name]
    }

    /// The one line a person can paste into Terminal instead of pressing Install.
    public static func claudeCommandLine(name: String, command: String) -> String {
        "claude mcp add --scope user \(name) -- '\(command)'"
    }

    /// The Copilot CLI's equivalent, for its row's Copy Setup Command.
    public static func copilotCommandLine(name: String, command: String) -> String {
        "copilot mcp add \(name) -- '\(command)'"
    }

    // MARK: What is there now

    /// One thing Install puts in place (a server entry or a skill folder), as
    /// it stands.
    public enum Slot: Equatable, Sendable {
        case absent
        /// Photonz's, and this copy's.
        case current
        /// Photonz's, from another copy or an older version.
        case stale
        /// Something of the same name that is not Photonz's.
        case theirs
    }

    public static func serverSlot(command: String?, ours: String) -> Slot {
        guard let command else { return .absent }
        if command == ours { return .current }
        return isPhotonzBridge(command: command) ? .stale : .theirs
    }

    /// A skill folder is Photonz's when Install marked it, or when it is the
    /// repo's link (`Scripts/install-mcp.sh`) to `plugin/skills/photonz`.
    public static func skillSlot(exists: Bool, linkDestination: String?, marked: Bool,
                                 installed: String?, bundled: String) -> Slot {
        guard exists else { return .absent }
        if let linkDestination {
            return linkDestination.hasSuffix("plugin/skills/" + skillName) ? .stale : .theirs
        }
        guard marked else { return .theirs }
        return installed == bundled ? .current : .stale
    }

    /// What a tool's row says and offers.
    public enum RowState: Equatable, Sendable {
        /// The tool is not on this Mac and nothing of Photonz's is set up for it.
        case notFound
        case notInstalled
        case installed
        /// Set up, from another copy of the app or an older one: Install updates it.
        case needsUpdate
        /// A server or skill named photonz that is not Photonz's is in the way.
        case taken
    }

    public static func rowState(found: Bool, slots: [Slot]) -> RowState {
        if slots.contains(.theirs) { return .taken }
        if slots.allSatisfy({ $0 == .absent }) { return found ? .notInstalled : .notFound }
        if slots.allSatisfy({ $0 == .current }) { return .installed }
        return .needsUpdate
    }
}
