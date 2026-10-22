import AppKit
import PhotonzCore
import SwiftUI

/// Settings' Ask section (`docs/design/ask.md`): which model on this Mac
/// answers Ask, and the one-time download when there is none. The only place a
/// model is ever chosen; Ask itself never asks (the user, 2026-10-19).
///
/// By default the model runs inside Photonz, so the whole setup is one
/// Download here. Ollama is a choice for people who already keep it running,
/// off unless they turn it on.
struct AskSettingsSection: View {
    @State private var installed: [String]?
    @State private var checked = false
    @State private var chosen = AskLocalModel.chosen ?? ""
    @State private var builtInChosen = AskLocalModel.builtInChosen ?? ""
    @State private var useOllama = AskLocalModel.runtime == .ollama
    @State private var downloaded = AskModelServer.downloaded
    @State private var pull: Double?
    @State private var pullTrouble: String?
    @State private var picturesInstalled = AskPictureServer.isInstalled
    private var fetch: AskModelDownload { AskModelDownload.shared }
    private var pictureFetch: AskModelDownload { AskModelDownload.pictures }

    var body: some View {
        Section {
            if useOllama {
                ollama
            } else {
                builtIn
            }
            if Experiments.shared.isEnabled(FeatureCatalog.askPaintsFlag) {
                pictures
            }
            Toggle("Use Ollama instead", isOn: $useOllama)
                .onChange(of: useOllama) { _, now in
                    AskLocalModel.runtime = now ? .ollama : .builtIn
                    if now { AskModelServer.shared.stop() }
                    Task { await reload() }
                }
                .playtestControl("Ask Use Ollama", detail: useOllama ? "on" : "off")
        } header: {
            Text("Ask")
        }
        .task { await reload() }
        .onChange(of: fetch.active) { _, _ in downloaded = AskModelServer.downloaded }
        .onChange(of: pictureFetch.active) { _, _ in picturesInstalled = AskPictureServer.isInstalled }
    }

    // MARK: Built in

    @ViewBuilder
    private var builtIn: some View {
        let have = AskBuiltInModels.ranked.filter { downloaded.contains($0.id) }
        if let downloading = fetch.item {
            VStack(alignment: .leading, spacing: 6) {
                Text("Downloading \(downloading.name)")
                ProgressView(value: fetch.fraction)
                    .playtestControl("Ask Download Progress", detail: String(format: "%.0f%%", fetch.fraction * 100))
                Text("\(AskBuiltInModels.sizeWords(fetch.done)) of \(AskBuiltInModels.sizeWords(downloading.totalBytes))")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            Button("Stop") { fetch.stop() }
                .playtestControl("Ask Stop Download", detail: "Stop")
        } else if let automatic = AskBuiltInModels.resolve(chosen: nil, downloaded: downloaded,
                                                             memoryGigabytes: AskLocalModel.memoryGigabytes) {
            if have.count > 1 {
                Picker("Model", selection: $builtInChosen) {
                    Text("Automatic (\(automatic.name))").tag("")
                    ForEach(have, id: \.id) { Text($0.name).tag($0.id) }
                }
                .onChange(of: builtInChosen) { _, now in AskLocalModel.builtInChosen = now.isEmpty ? nil : now }
                .playtestControl("Ask Model", detail: builtInChosen.isEmpty ? "Automatic" : builtInChosen)
            } else {
                LabeledContent("Model", value: automatic.name)
                    .playtestControl("Ask Model", detail: automatic.name)
            }
            Text("Runs inside Photonz. Nothing leaves the Mac.")
                .font(.callout).foregroundStyle(.secondary)
        } else if let offer = AskBuiltInModels.recommended(memoryGigabytes: AskLocalModel.memoryGigabytes) {
            Text("Ask needs a model on this Mac: \(offer.name), \(AskBuiltInModels.sizeWords(offer.downloadBytes)). It goes in Application Support > Photonz > Models.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .playtestControl("Ask Download Offer", detail: offer.name)
            Button("Download") { fetch.start(offer) }
                .playtestControl("Ask Download", detail: "Download \(offer.name)")
        } else {
            Text("Ask needs more memory than this Mac has.")
                .font(.callout)
        }
        if let trouble = fetch.trouble {
            Text(trouble).font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: Pictures

    /// The picture model Ask paints its drawings with: set up here in one
    /// download, run by Photonz. Offered when the Mac can hold it beside the
    /// chat model; without it Ask draws with the chat model alone.
    @ViewBuilder
    private var pictures: some View {
        let chat = useOllama ? nil : AskBuiltInModels.resolve(chosen: AskLocalModel.builtInChosen, downloaded: downloaded,
                                                              memoryGigabytes: AskLocalModel.memoryGigabytes)
            ?? AskBuiltInModels.recommended(memoryGigabytes: AskLocalModel.memoryGigabytes)
        if pictureFetch.active {
            VStack(alignment: .leading, spacing: 6) {
                Text(pictureFetch.settingUp ? "Setting up \(AskPictureModelPlan.name)"
                     : "Downloading \(AskPictureModelPlan.name)")
                ProgressView(value: pictureFetch.fraction)
                    .playtestControl("Ask Pictures Progress", detail: String(format: "%.0f%%", pictureFetch.fraction * 100))
                Text("\(AskBuiltInModels.sizeWords(pictureFetch.done)) of \(AskBuiltInModels.sizeWords(AskPictureModelPlan.downloadBytes))")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            Button("Stop") { pictureFetch.stop() }
                .playtestControl("Ask Pictures Stop", detail: "Stop")
        } else if picturesInstalled {
            LabeledContent("Pictures", value: AskPictureModelPlan.name)
                .playtestControl("Ask Pictures", detail: AskPictureModelPlan.name)
        } else if AskPictureModelPlan.fits(memoryGigabytes: AskLocalModel.memoryGigabytes, beside: chat) {
            Text("Ask can paint its drawings with \(AskPictureModelPlan.name), \(AskBuiltInModels.sizeWords(AskPictureModelPlan.downloadBytes)). It goes in Application Support > Photonz > Models.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .playtestControl("Ask Pictures Offer", detail: AskPictureModelPlan.name)
            Button("Download \(AskPictureModelPlan.name)") { AskPictureServer.download() }
                .playtestControl("Ask Pictures Download", detail: "Download \(AskPictureModelPlan.name)")
        }
        if let trouble = pictureFetch.trouble {
            Text(trouble).font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: Ollama

    @ViewBuilder
    private var ollama: some View {
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
            Text("Ollama isn't answering on this Mac.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Get Ollama") { open("https://ollama.com/download") }
                Button("Check Again") { Task { await reload() } }
            }
        }
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
        downloaded = AskModelServer.downloaded
        picturesInstalled = AskPictureServer.isInstalled
        guard useOllama else { return }
        installed = await AskLocalModel.ollamaInstalled()
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
