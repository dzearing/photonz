import AppKit
import PhotonzCore
import SwiftUI

/// Settings' Ask section (`docs/design/ask.md`, "Choosing a model"): every
/// model Ask can run, one row each, with what it needs, its measured quality
/// and speed, and Download, Use and Delete; the picture model is a row of its
/// own. Nothing is downloaded until a person presses Download here or in Ask's
/// setup dialog (`AskSetupSheet`, which offers the set for the Mac).
///
/// By default the model runs inside Photonz. Ollama is a choice for people
/// who already keep it running, off unless they turn it on.
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
    @State private var deleting: AskSettingsDelete?
    /// Ask may open a web page the request names (`AskWeb`). On until the
    /// person turns it off; off, a request with an address is answered in
    /// one line and nothing is opened.
    @AppStorage(AskWeb.settingKey) private var opensPages = true
    private var fetch: AskModelDownload { AskModelDownload.shared }
    private var pictureFetch: AskModelDownload { AskModelDownload.pictures }
    private var memory: Double { AskLocalModel.memoryGigabytes }

    var body: some View {
        Section {
            if useOllama {
                ollama
            } else {
                builtIn
            }
            if AskSetup.paints {
                pictures
            }
            Toggle("Use Ollama instead", isOn: $useOllama)
                .onChange(of: useOllama) { _, now in
                    AskLocalModel.runtime = now ? .ollama : .builtIn
                    if now { AskModelServer.shared.stop() }
                    Task { await reload() }
                }
                .playtestControl("Ask Use Ollama", detail: useOllama ? "on" : "off")
            Toggle("Open web pages you name", isOn: $opensPages)
                .help("Ask opens an address in your request to mock its page. Turn this off to keep Ask off the web.")
                .playtestControl("Ask Open Web Pages", detail: opensPages ? "on" : "off")
        } header: {
            Text("Ask")
        }
        .task { await reload() }
        .onChange(of: fetch.active) { _, _ in downloaded = AskModelServer.downloaded }
        .onChange(of: pictureFetch.active) { _, _ in picturesInstalled = AskPictureServer.isInstalled }
    }

    // MARK: Built in

    /// The model Ask answers with now, or nil with none downloaded.
    private var inUse: AskBuiltInModels.Choice? {
        AskBuiltInModels.resolve(chosen: builtInChosen.isEmpty ? nil : builtInChosen, downloaded: downloaded,
                                 memoryGigabytes: memory)
    }

    /// One row a model: what it is, what it needs, how good and fast it is,
    /// and Download, Use or Delete. Nothing is downloaded until a person
    /// presses Download here or in Ask's setup dialog.
    @ViewBuilder
    private var builtIn: some View {
        let using = inUse?.id
        ForEach(AskModelSetup.listed(downloaded: downloaded), id: \.id) { choice in
            modelRow(choice, inUse: choice.id == using)
        }
        if let trouble = fetch.trouble {
            Text(trouble).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func modelRow(_ choice: AskBuiltInModels.Choice, inUse: Bool) -> some View {
        let have = downloaded.contains(choice.id)
        let fits = AskModelSetup.fits(choice, memoryGigabytes: memory)
        let mac = AskMacSizes.smallest(holding: choice.gigabytes)
        return AskModelRow(
            name: choice.name, blurb: choice.blurb, inUse: inUse,
            needs: mac.map { "Needs \([8, 18].contains($0) ? "an" : "a") \($0) GB Mac" } ?? "Needs more memory than any Mac",
            size: AskBuiltInModels.sizeWords(choice.downloadBytes),
            tooBig: !fits, measured: choice.measured,
            downloading: fetch.item?.id == choice.id ? fetch : nil
        ) {
            if fetch.item?.id == choice.id {
                Button("Stop") { fetch.stop() }
                    .playtestControl("Ask Stop \(choice.name)", detail: "Stop")
            } else if deleting?.id == choice.id {
                confirmDelete
            } else if have {
                if !inUse {
                    Button("Use") { use(choice) }
                        .playtestControl("Ask Use \(choice.name)", detail: "Use")
                }
                Button("Delete") {
                    deleting = AskSettingsDelete(id: choice.id, name: choice.name, bytes: choice.downloadBytes)
                }
                .playtestControl("Ask Delete \(choice.name)", detail: "Delete")
            } else if choice.measured?.canDoAsksWork == false {
                Text("Too weak for Ask").font(.callout).foregroundStyle(.secondary)
            } else {
                Button("Download") { fetch.start(choice) }
                    .disabled(!fits || fetch.active)
                    .playtestControl("Ask Download \(choice.name)", detail: fits ? "Download" : "too big for this Mac")
            }
        }
        .playtestControl("Ask Model \(choice.name)",
                         detail: [inUse ? "in use" : nil, have ? "downloaded" : nil, fits ? nil : "too big"]
                            .compactMap { $0 }.joined(separator: ", "))
    }

    /// Delete asks in the row itself: Cancel, or Delete with what it frees.
    /// Ask can download it again later.
    @ViewBuilder
    private var confirmDelete: some View {
        if let old = deleting {
            Button("Cancel") { deleting = nil }
                .playtestControl("Ask Cancel Delete", detail: old.name)
            Button("Delete \(AskBuiltInModels.sizeWords(old.bytes))") {
                deleting = nil
                delete(old)
            }
            .playtestControl("Ask Confirm Delete", detail: old.name)
        }
    }

    private func use(_ choice: AskBuiltInModels.Choice) {
        AskModelServer.shared.stop()
        builtInChosen = choice.id
        AskLocalModel.builtInChosen = choice.id
    }

    private func delete(_ old: AskSettingsDelete) {
        if old.id == AskPictureModelPlan.id {
            AskPictureServer.delete()
            picturesInstalled = AskPictureServer.isInstalled
            return
        }
        if let choice = AskBuiltInModels.choice(id: old.id) { AskModelServer.shared.delete(choice) }
        // Ask falls back to the next model on the Mac, or to its setup dialog.
        if AskLocalModel.builtInChosen == old.id {
            AskLocalModel.builtInChosen = nil
            builtInChosen = ""
        }
        downloaded = AskModelServer.downloaded
    }

    // MARK: Pictures

    /// The picture model Ask paints its drawings with, a row like the
    /// chat models': it runs beside whichever chat model is in use, so what
    /// it needs is memory on top of that one's. Without it Ask draws with the
    /// chat model alone.
    @ViewBuilder
    private var pictures: some View {
        let chat = useOllama ? nil : inUse ?? AskBuiltInModels.recommended(memoryGigabytes: memory)
        let fits = AskPictureModelPlan.fits(memoryGigabytes: memory, beside: chat)
        AskModelRow(
            name: AskPictureModelPlan.name, blurb: AskPictureModelPlan.blurb, inUse: picturesInstalled,
            needs: String(format: "Needs %.0f GB more", AskPictureModelPlan.gigabytes),
            size: AskBuiltInModels.sizeWords(AskPictureModelPlan.downloadBytes),
            tooBig: !fits, measured: AskPictureModelPlan.measured,
            downloading: pictureFetch.active ? pictureFetch : nil,
            settingUp: pictureFetch.settingUp
        ) {
            if pictureFetch.active {
                Button("Stop") { pictureFetch.stop() }
                    .playtestControl("Ask Pictures Stop", detail: "Stop")
            } else if deleting?.id == AskPictureModelPlan.id {
                confirmDelete
            } else if picturesInstalled {
                Button("Delete") {
                    deleting = AskSettingsDelete(id: AskPictureModelPlan.id, name: AskPictureModelPlan.name,
                                                 bytes: AskPictureModelPlan.downloadBytes)
                }
                .playtestControl("Ask Pictures Delete", detail: "Delete")
            } else {
                Button("Download") { AskPictureServer.download() }
                    .disabled(!fits)
                    .playtestControl("Ask Pictures Download", detail: fits ? "Download \(AskPictureModelPlan.name)" : "too big for this Mac")
            }
        }
        .playtestControl("Ask Pictures", detail: [picturesInstalled ? "in use" : nil, fits ? nil : "too big"]
                            .compactMap { $0 }.joined(separator: ", "))
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
        builtInChosen = AskLocalModel.builtInChosen ?? ""
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
                        if let said = json["error"]?.stringValue { throw Trouble.server(said) }
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

/// A model a person asked to delete, waiting for the confirmation.
struct AskSettingsDelete: Equatable {
    let id: String
    let name: String
    let bytes: Int64
}

/// One model in Settings > Ask: its name and what it is good at, marked when
/// Ask uses it; what it needs and its size, "Too big for this Mac" when it
/// is; its quality and speed as five dots each, with the measured numbers in
/// the help tag; and its buttons. A download shows its progress and size in
/// place of the needs.
struct AskModelRow<Buttons: View>: View {
    let name: String
    let blurb: String
    let inUse: Bool
    let needs: String
    let size: String
    let tooBig: Bool
    let measured: AskModelMeasure?
    var downloading: AskModelDownload?
    var settingUp = false
    @ViewBuilder let buttons: () -> Buttons

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name).font(.body.weight(.medium))
                    if inUse {
                        Label("In Use", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tint)
                    }
                }
                Text(blurb)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let downloading {
                    ProgressView(value: downloading.fraction)
                        .playtestControl("Ask Progress \(name)", detail: String(format: "%.0f%%", downloading.fraction * 100))
                    Text(settingUp ? "Setting up" : "\(AskBuiltInModels.sizeWords(downloading.done)) of \(size)")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                } else {
                    HStack(spacing: 6) {
                        Text("\(needs) · \(size)")
                            .foregroundStyle(.secondary)
                        if tooBig {
                            Text("Too big for this Mac")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                }
                if let measured {
                    HStack(spacing: 14) {
                        AskRatingDots(label: "Quality", value: measured.quality)
                            .help(measured.qualityWords)
                        AskRatingDots(label: "Speed", value: measured.speed)
                            .help(measured.speedWords)
                    }
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) { buttons() }
                .controlSize(.small)
        }
        .padding(.vertical, 3)
    }
}

/// A 1 to 5 rating as five dots, filled up to the value.
struct AskRatingDots: View {
    let label: String
    let value: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { dot in
                    Circle()
                        .fill(dot <= value ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value) of 5")
    }
}
