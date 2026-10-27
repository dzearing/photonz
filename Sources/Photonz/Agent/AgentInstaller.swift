import AppKit
import Foundation
import PhotonzCore

/// Settings > Agents' hands (`docs/design/agent-mcp.md`, "Install"): finds
/// Claude Code and GitHub Copilot on this Mac, and puts the server and skill
/// that ship inside this copy of Photonz where each one reads them. What to
/// write, and whether what is there is Photonz's, is `AgentSetup`'s call.
///
/// Everything here blocks (files, and Claude Code's own command), so the
/// section calls it off the main thread.
struct AgentInstaller: Sendable {

    let home: String
    let bundlePath: String
    let serverName: String

    /// A walk's own home (`agentHome` in a walk's setup), so a walk that
    /// presses Install never touches the person's tools. Nil: the real one.
    @MainActor static var walkHome: String?

    @MainActor static var forThisApp: AgentInstaller {
        AgentInstaller(home: walkHome ?? NSHomeDirectory(), bundlePath: Bundle.main.bundlePath,
                       serverName: AgentSetup.serverName(bundleID: Bundle.main.bundleIdentifier ?? ""))
    }

    var helperPath: String { bundlePath + "/Contents/Helpers/" + AgentSetup.helperName }
    var bundledSkill: String { bundlePath + "/Contents/Resources/AgentSkill/" + AgentSetup.skillName }

    /// A plain sentence for the row when something went wrong.
    struct Trouble: Error, Sendable {
        let words: String
    }

    struct Status: Sendable, Equatable {
        var state: AgentSetup.RowState
        /// Where the tool was found, for the row's tip ("VS Code and the Copilot CLI").
        var foundIn: String
    }

    // MARK: Status

    func status(_ tool: AgentSetup.Tool) -> Status {
        let bundled = read(bundledSkill + "/SKILL.md") ?? ""
        switch tool {
        case .claudeCode:
            let found = Self.executable("claude")
            let server = AgentSetup.serverSlot(
                command: AgentSetup.command(named: serverName, in: read(AgentSetup.claudeConfigPath(home: home)),
                                            format: .claudeCode),
                ours: helperPath)
            let skill = skillSlot(in: AgentSetup.claudeSkillsDirectory(home: home), bundled: bundled)
            return Status(state: AgentSetup.rowState(found: found != nil, slots: [server, skill]),
                          foundIn: found == nil ? "" : "Claude Code")
        case .copilot:
            let places = copilotPlaces()
            let servers = places.configs.map { config in
                AgentSetup.serverSlot(command: AgentSetup.command(named: serverName, in: read(config.path),
                                                                  format: config.format),
                                      ours: helperPath)
            }
            let skill = skillSlot(in: AgentSetup.copilotSkillsDirectory(home: home), bundled: bundled)
            return Status(state: AgentSetup.rowState(found: !places.found.isEmpty, slots: servers + [skill]),
                          foundIn: places.found.joined(separator: " and the "))
        }
    }

    // MARK: Install and uninstall

    func install(_ tool: AgentSetup.Tool) throws {
        guard FileManager.default.isExecutableFile(atPath: helperPath),
              FileManager.default.fileExists(atPath: bundledSkill + "/SKILL.md") else {
            throw Trouble(words: "This copy of Photonz has no agent server.")
        }
        switch tool {
        case .claudeCode:
            guard let claude = Self.executable("claude") else { throw Trouble(words: "Claude Code is not on this Mac.") }
            try checkSkillIsFree(in: AgentSetup.claudeSkillsDirectory(home: home))
            let current = AgentSetup.command(named: serverName, in: read(AgentSetup.claudeConfigPath(home: home)),
                                             format: .claudeCode)
            switch AgentSetup.serverSlot(command: current, ours: helperPath) {
            case .theirs: throw Trouble(words: "Another \(serverName) server is set up. Left alone.")
            case .current: break
            case .stale:
                try run(claude, AgentSetup.claudeRemoveArguments(name: serverName))
                try run(claude, AgentSetup.claudeAddArguments(name: serverName, command: helperPath))
            case .absent:
                try run(claude, AgentSetup.claudeAddArguments(name: serverName, command: helperPath))
            }
            try placeSkill(in: AgentSetup.claudeSkillsDirectory(home: home))
        case .copilot:
            // Every file is checked before any is written, so a refusal
            // leaves nothing half done.
            let configs = copilotPlaces().configs
            var edits: [(path: String, text: String)] = []
            for config in configs {
                do {
                    edits.append((config.path, try AgentSetup.adding(name: serverName, command: helperPath,
                                                                    to: read(config.path), format: config.format)))
                } catch let error as AgentSetup.ConfigError {
                    throw Trouble(words: words(error, file: config.label))
                }
            }
            try checkSkillIsFree(in: AgentSetup.copilotSkillsDirectory(home: home))
            for edit in edits { try write(edit.text, to: edit.path) }
            try placeSkill(in: AgentSetup.copilotSkillsDirectory(home: home))
        }
    }

    func uninstall(_ tool: AgentSetup.Tool) throws {
        switch tool {
        case .claudeCode:
            let config = read(AgentSetup.claudeConfigPath(home: home))
            let current = AgentSetup.command(named: serverName, in: config, format: .claudeCode)
            if let current, AgentSetup.isPhotonzBridge(command: current) {
                guard let claude = Self.executable("claude") else {
                    throw Trouble(words: "Claude Code is not on this Mac.")
                }
                try run(claude, AgentSetup.claudeRemoveArguments(name: serverName))
            }
            if AgentSetup.otherPhotonzServers(in: config, format: .claudeCode, except: serverName).isEmpty {
                try removeSkill(in: AgentSetup.claudeSkillsDirectory(home: home))
            }
        case .copilot:
            var othersRemain = false
            for config in copilotPlaces().configs {
                let text = read(config.path)
                do {
                    if let out = try AgentSetup.removing(name: serverName, from: text, format: config.format) {
                        try write(out, to: config.path)
                    }
                } catch let error as AgentSetup.ConfigError {
                    throw Trouble(words: words(error, file: config.label))
                }
                othersRemain = othersRemain
                    || !AgentSetup.otherPhotonzServers(in: text, format: config.format, except: serverName).isEmpty
            }
            if !othersRemain { try removeSkill(in: AgentSetup.copilotSkillsDirectory(home: home)) }
        }
    }

    // MARK: Copilot's places

    struct Config: Sendable {
        let path: String
        let format: AgentSetup.ConfigFormat
        let label: String
    }

    /// Where Copilot is (VS Code, the Copilot CLI) and the configs to write.
    /// The CLI's config is always written: it costs one small file, VS Code's
    /// own Copilot reads the same skills folder, and a person who installs
    /// the CLI later finds Photonz already there.
    private func copilotPlaces() -> (found: [String], configs: [Config]) {
        var found: [String] = []
        var configs = [Config(path: AgentSetup.copilotConfigPath(home: home), format: .copilotCLI,
                              label: "the Copilot CLI's mcp-config.json")]
        for edition in AgentSetup.VSCodeEdition.allCases {
            let path = AgentSetup.vsCodeConfigPath(home: home, edition: edition)
            let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: edition.bundleID)
            let userFolder = (path as NSString).deletingLastPathComponent
            guard app != nil || FileManager.default.fileExists(atPath: userFolder) else { continue }
            if app != nil, !found.contains("VS Code") { found.append("VS Code") }
            configs.append(Config(path: path, format: .vsCode, label: "VS Code's mcp.json"))
        }
        if Self.executable("copilot") != nil { found.append("Copilot CLI") }
        return (found, configs)
    }

    private func words(_ error: AgentSetup.ConfigError, file: String) -> String {
        switch error {
        case .hasComments: "Comments in \(file). Add it by hand."
        case .unreadable: "Could not read \(file)."
        case .taken: "Another \(serverName) server is set up. Left alone."
        }
    }

    // MARK: The skill

    private func skillSlot(in skills: String, bundled: String) -> AgentSetup.Slot {
        let folder = skills + "/" + AgentSetup.skillName
        let manager = FileManager.default
        let link = try? manager.destinationOfSymbolicLink(atPath: folder)
        let exists = link != nil || manager.fileExists(atPath: folder)
        return AgentSetup.skillSlot(exists: exists, linkDestination: link,
                                    marked: manager.fileExists(atPath: folder + "/" + AgentSetup.markerName),
                                    installed: read(folder + "/SKILL.md"), bundled: bundled)
    }

    private func checkSkillIsFree(in skills: String) throws {
        let bundled = read(bundledSkill + "/SKILL.md") ?? ""
        if skillSlot(in: skills, bundled: bundled) == .theirs {
            throw Trouble(words: "A skill named \(AgentSetup.skillName) is already there. Left alone.")
        }
    }

    /// A copy, never a link: the skill keeps working if this copy of the app
    /// moves, and Install puts the newer one in place after an update.
    private func placeSkill(in skills: String) throws {
        try checkSkillIsFree(in: skills)
        let manager = FileManager.default
        let folder = skills + "/" + AgentSetup.skillName
        try manager.createDirectory(atPath: skills, withIntermediateDirectories: true)
        if (try? manager.destinationOfSymbolicLink(atPath: folder)) != nil || manager.fileExists(atPath: folder) {
            try manager.removeItem(atPath: folder)
        }
        try manager.copyItem(atPath: bundledSkill, toPath: folder)
        try Data((bundlePath + "\n").utf8).write(to: URL(fileURLWithPath: folder + "/" + AgentSetup.markerName))
    }

    private func removeSkill(in skills: String) throws {
        let folder = skills + "/" + AgentSetup.skillName
        switch skillSlot(in: skills, bundled: read(bundledSkill + "/SKILL.md") ?? "") {
        case .current, .stale: try FileManager.default.removeItem(atPath: folder)
        case .absent, .theirs: break
        }
    }

    // MARK: Files and programs

    private func read(_ path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    /// Written whole and swapped in, keeping the file's own permissions (the
    /// Copilot CLI keeps its config readable by you alone).
    private func write(_ text: String, to path: String) throws {
        let manager = FileManager.default
        let permissions = (try? manager.attributesOfItem(atPath: path))?[.posixPermissions]
        try manager.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                    withIntermediateDirectories: true)
        try Data(text.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        let mode = permissions ?? NSNumber(value: path.hasPrefix(home + "/.copilot/") ? 0o600 : 0o644)
        try manager.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: home)
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home
        // An npm-installed tool is a script that needs node beside it.
        environment["PATH"] = ([(executable as NSString).deletingLastPathComponent] + Self.searchFolders(home: home)
            + [environment["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        process.environment = environment
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(30)
        while process.isRunning, Date() < deadline { usleep(50_000) }
        if process.isRunning {
            process.terminate()
            throw Trouble(words: "Claude Code did not answer.")
        }
        guard process.terminationStatus == 0 else {
            let said = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            NSLog("Photonz agents: %@ %@ failed: %@", executable, arguments.joined(separator: " "), said)
            throw Trouble(words: "Claude Code turned it down.")
        }
    }

    // MARK: Finding the tools

    /// An app opened from the Finder gets no shell PATH, so the places the
    /// usual installers put these commands are looked through by hand.
    static func searchFolders(home: String) -> [String] {
        var folders = [home + "/.local/bin", home + "/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
                       home + "/.npm-global/bin", home + "/.bun/bin", home + "/.volta/bin", home + "/bin"]
        let nvm = home + "/.nvm/versions/node"
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: nvm)) ?? []
        folders += versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }.map { nvm + "/" + $0 + "/bin" }
        return folders
    }

    static func executable(_ name: String) -> String? {
        let home = NSHomeDirectory()
        let path = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        for folder in searchFolders(home: home) + path {
            let candidate = folder + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
