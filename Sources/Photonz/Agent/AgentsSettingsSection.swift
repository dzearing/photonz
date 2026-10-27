import AppKit
import PhotonzCore
import SwiftUI

/// Settings' Agents section (`docs/design/agent-mcp.md`, "Install"): one row
/// each for Claude Code and GitHub Copilot, saying whether that tool is on
/// this Mac, with the one button that sets Photonz up in it or takes Photonz
/// back out. Nothing to copy, no Terminal. Right-click a row for the command,
/// for a person who would rather run it themselves.
struct AgentsSettingsSection: View {
    @State private var statuses: [AgentSetup.Tool: AgentInstaller.Status] = [:]
    @State private var busy: AgentSetup.Tool?
    @State private var trouble: [AgentSetup.Tool: String] = [:]

    private let installer = AgentInstaller.forThisApp

    var body: some View {
        Section {
            ForEach(AgentSetup.Tool.allCases, id: \.self) { tool in
                row(tool)
            }
        } header: {
            Text("Agents")
        }
        .task { await reload() }
        // Installing the tool itself happens elsewhere, so the rows re-read
        // whenever Settings comes back to the front.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await reload() }
        }
    }

    // MARK: A row

    private func row(_ tool: AgentSetup.Tool) -> some View {
        let status = statuses[tool]
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(tool))
                    .font(.body.weight(.medium))
                line(tool, status: status)
                    .font(.callout)
            }
            .help(status.map { $0.foundIn.isEmpty ? "" : "Found: \($0.foundIn)" } ?? "")
            Spacer(minLength: 8)
            buttons(tool, status: status)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Copy Setup Command") { copyCommand(tool) }
        }
        .playtestTarget("Agents \(Self.title(tool))", kind: .row, detail: status.map { Self.stateName($0.state) } ?? "")
    }

    @ViewBuilder
    private func line(_ tool: AgentSetup.Tool, status: AgentInstaller.Status?) -> some View {
        if let words = trouble[tool] {
            Label(words, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        } else if let status {
            switch status.state {
            case .notFound:
                HStack(spacing: 4) {
                    Text("Not on this Mac.").foregroundStyle(.secondary)
                    Link(Self.getName(tool), destination: Self.getURL(tool))
                }
            case .notInstalled:
                Text("Lets it use Photonz. Found on this Mac.").foregroundStyle(.secondary)
            case .installed:
                Text("Installed. Its agents can use Photonz.").foregroundStyle(.secondary)
            case .needsUpdate:
                Text("Set up from another copy of Photonz.").foregroundStyle(.secondary)
            case .taken:
                Text("Another photonz is set up. Left alone.").foregroundStyle(.secondary)
            }
        } else {
            Text(" ")
        }
    }

    @ViewBuilder
    private func buttons(_ tool: AgentSetup.Tool, status: AgentInstaller.Status?) -> some View {
        let name = Self.title(tool)
        if busy == tool {
            ProgressView().controlSize(.small)
        } else if let status {
            switch status.state {
            case .notInstalled:
                Button("Install") { act(tool, install: true) }
                    .playtestControl("Agents \(name) Install", detail: "Install")
            case .installed:
                Button("Uninstall") { act(tool, install: false) }
                    .playtestControl("Agents \(name) Uninstall", detail: "Uninstall")
            case .needsUpdate:
                HStack {
                    Button("Uninstall") { act(tool, install: false) }
                        .playtestControl("Agents \(name) Uninstall", detail: "Uninstall")
                    Button("Update") { act(tool, install: true) }
                        .playtestControl("Agents \(name) Install", detail: "Update")
                }
            case .notFound, .taken:
                EmptyView()
            }
        }
    }

    // MARK: Acting

    private func act(_ tool: AgentSetup.Tool, install: Bool) {
        busy = tool
        trouble[tool] = nil
        let installer = installer
        Task {
            let failure: String? = await Task.detached {
                do {
                    if install { try installer.install(tool) } else { try installer.uninstall(tool) }
                    return nil
                } catch let trouble as AgentInstaller.Trouble {
                    return trouble.words
                } catch {
                    return "Could not finish. \(error.localizedDescription)"
                }
            }.value
            trouble[tool] = failure
            await reload()
            busy = nil
        }
    }

    private func reload() async {
        let installer = installer
        let found = await Task.detached {
            Dictionary(uniqueKeysWithValues: AgentSetup.Tool.allCases.map { ($0, installer.status($0)) })
        }.value
        statuses = found
    }

    private func copyCommand(_ tool: AgentSetup.Tool) {
        let line = switch tool {
        case .claudeCode: AgentSetup.claudeCommandLine(name: installer.serverName, command: installer.helperPath)
        case .copilot: AgentSetup.copilotCommandLine(name: installer.serverName, command: installer.helperPath)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line, forType: .string)
    }

    // MARK: Words

    static func title(_ tool: AgentSetup.Tool) -> String {
        switch tool {
        case .claudeCode: "Claude Code"
        case .copilot: "GitHub Copilot"
        }
    }

    static func getName(_ tool: AgentSetup.Tool) -> String {
        switch tool {
        case .claudeCode: "Get Claude Code"
        case .copilot: "Get VS Code"
        }
    }

    static func getURL(_ tool: AgentSetup.Tool) -> URL {
        switch tool {
        case .claudeCode: URL(string: "https://claude.com/product/claude-code") ?? URL(fileURLWithPath: "/")
        case .copilot: URL(string: "https://code.visualstudio.com") ?? URL(fileURLWithPath: "/")
        }
    }

    static func stateName(_ state: AgentSetup.RowState) -> String {
        switch state {
        case .notFound: "not found"
        case .notInstalled: "not installed"
        case .installed: "installed"
        case .needsUpdate: "needs update"
        case .taken: "taken"
        }
    }
}
