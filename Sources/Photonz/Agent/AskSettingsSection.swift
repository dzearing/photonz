import AppKit
import PhotonzCore
import SwiftUI

/// Settings' Ask section (`docs/design/ask.md`): which model on this Mac
/// answers Ask, and the one-time setup when there is none. The only place a
/// model is ever chosen; Ask itself never asks (the user, 2026-10-19).
struct AskSettingsSection: View {
    @State private var installed: [String]?
    @State private var checked = false
    @State private var chosen = AskLocalModel.chosen ?? ""
    @State private var pull: Double?
    @State private var pullTrouble: String?

    var body: some View {
        Section {
            if !checked {
                ProgressView().controlSize(.small)
            } else if let installed {
                if let automatic = AskModels.automatic(installed: installed, memoryGigabytes: AskLocalModel.memoryGigabytes) {
                    Picker("Model", selection: $chosen) {
                        Text("Automatic (\(automatic))").tag("")
                        ForEach(installed, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: chosen) { _, now in AskLocalModel.chosen = now.isEmpty ? nil : now }
                    .playtestControl("Ask Model", detail: chosen.isEmpty ? "Automatic" : chosen)
                    Text("Runs on this Mac with Ollama. Nothing leaves the Mac.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    download
                }
            } else {
                Text("Ask runs on a model on this Mac, through Ollama, a free app. Install it, then come back here to get the model.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Get Ollama") { open("https://ollama.com/download") }
                    Button("Check Again") { Task { await reload() } }
                }
            }
        } header: {
            Text("Ask")
        }
        .task { await reload() }
    }

    @ViewBuilder
    private var download: some View {
        if let offer = AskModels.recommended(memoryGigabytes: AskLocalModel.memoryGigabytes) {
            Text("Ask needs a model on this Mac: \(offer.tag), a one-time download of \(String(format: "%.1f", offer.download)) GB, about 10 to 30 minutes on a fast connection.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let pull {
                ProgressView(value: pull)
            } else {
                Button("Download \(offer.tag)") { Task { await download(offer.tag) } }
            }
        } else {
            Text("Ask needs more memory than this Mac has.")
                .font(.callout)
        }
        if let pullTrouble {
            Text(pullTrouble).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func reload() async {
        installed = await AskLocalModel.installed()
        checked = true
    }

    private func open(_ address: String) {
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }

    /// Ollama's own pull, shown as it goes.
    private func download(_ model: String) async {
        pull = 0
        pullTrouble = nil
        defer { pull = nil }
        do {
            for try await fraction in AskLocalModel.pull(model) { pull = fraction }
            await reload()
        } catch {
            pullTrouble = "The download stopped. Try again."
        }
    }
}

extension AskLocalModel {
    /// Downloads a model through Ollama, answering how far along it is.
    static func pull(_ model: String) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard let url = base?.appending(path: "api/pull") else {
                    continuation.finish(throwing: Trouble.noRunner)
                    return
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = AgentJSON.object(["model": .string(model), "stream": true]).encoded()
                request.timeoutInterval = 3600
                do {
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    for try await line in bytes.lines {
                        guard let json = try? AgentJSON.parse(Data(line.utf8)) else { continue }
                        if let said = json["error"]?.stringValue { throw Trouble.said(said) }
                        if let total = json["total"]?.doubleValue, total > 0,
                           let done = json["completed"]?.doubleValue {
                            continuation.yield(done / total)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
