import AppKit
import PhotonzCore
import SwiftUI

/// The first Ask on a Mac with no model (`docs/design/ask.md`, "Choosing a
/// model"): nothing is downloaded until a person wants Ask, and then one
/// dialog offers the set for this Mac (`AskModelSetup.plan`), downloads it and
/// carries on with what they asked, without it being typed again.
@MainActor
enum AskSetup {

    /// Whether Ask has no model to answer with: built in and none downloaded.
    /// Ollama, picked by hand, is set up in Settings instead.
    static var needed: Bool {
        AskLocalModel.runtime == .builtIn
            && AskBuiltInModels.resolve(chosen: AskLocalModel.builtInChosen, downloaded: AskModelServer.downloaded,
                                        memoryGigabytes: AskLocalModel.memoryGigabytes) == nil
    }

    /// Free space where the models go.
    static var freeBytes: Int64 {
        let folder = AskModelServer.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// Whether Ask paints its drawings at all in this build (`next-ask-paints-drawings`).
    static var paints: Bool { Experiments.shared.isEnabled(FeatureCatalog.askPaintsFlag) }

    /// The set this Mac should get now.
    static var plan: AskSetupPlan {
        AskModelSetup.plan(memoryGigabytes: AskLocalModel.memoryGigabytes, freeBytes: freeBytes,
                           downloaded: AskModelServer.downloaded,
                           pictureInstalled: !paints || AskPictureServer.isInstalled)
    }

    /// Either download is under way.
    static var downloading: Bool { AskModelDownload.shared.active || AskModelDownload.pictures.active }
}

/// Every word the setup dialog shows, in one place.
enum AskSetupCopy {
    static let title = "Set Up Ask"
    static let what = "Ask makes changes from your words. It runs on this Mac, so it needs a model first."
    static let download = "Download"
    static let notNow = "Not Now"
    static let hide = "Hide"
    static let stop = "Stop"
    static let otherModels = "Other Models…"
    static let ok = "OK"
    static let chatRole = "Requests"
    static let pictureRole = "Drawings"
    static let tooLittleMemory = "This Mac doesn't have enough memory for Ask."
    static func tooLittleDisk(_ bytes: Int64) -> String {
        "Free up \(AskBuiltInModels.sizeWords(bytes)) of disk space to set up Ask."
    }
    static func total(_ bytes: Int64, free: Int64) -> String {
        "\(AskBuiltInModels.sizeWords(bytes)) in all, \(AskBuiltInModels.sizeWords(free)) free"
    }
    static let runsAfter = "What you asked runs when it's done."
}

/// The dialog itself: what Ask is, the set for this Mac with its sizes and
/// the space left, Download and Not Now. While the set downloads it shows how
/// far along each part is; Hide puts it away and the download carries on.
struct AskSetupSheet: View {
    @Environment(EditorState.self) private var editorState
    @State private var plan = AskSetup.plan
    @State private var free = AskSetup.freeBytes
    private var chatFetch: AskModelDownload { AskModelDownload.shared }
    private var pictureFetch: AskModelDownload { AskModelDownload.pictures }

    var body: some View {
        let ask = editorState.ask
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(AskSetupCopy.title)
                    .font(.title3.weight(.semibold))
            }
            Text(AskSetupCopy.what)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .playtestControl("Ask Setup What", detail: AskSetupCopy.what)
            if let short = plan.short {
                Text(shortWords(short))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .playtestControl("Ask Setup Short", detail: shortWords(short))
            } else {
                VStack(spacing: 0) {
                    if let chat = plan.chat {
                        part(name: chat.name, role: AskSetupCopy.chatRole, bytes: chat.downloadBytes,
                             fetch: chatFetch, control: "Ask Setup Model")
                    }
                    if plan.chat != nil && plan.picture { Divider().padding(.vertical, 6) }
                    if plan.picture {
                        part(name: AskPictureModelPlan.name, role: AskSetupCopy.pictureRole,
                             bytes: AskPictureModelPlan.downloadBytes, fetch: pictureFetch, control: "Ask Setup Pictures")
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
                Text(AskSetup.downloading ? AskSetupCopy.runsAfter : AskSetupCopy.total(plan.bytes, free: free))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .playtestControl("Ask Setup Total", detail: AskSetupCopy.total(plan.bytes, free: free))
                if let trouble = chatFetch.trouble ?? pictureFetch.trouble {
                    Text(trouble).font(.callout).foregroundStyle(.secondary)
                }
            }
            buttons(ask)
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { refresh() }
    }

    private func refresh() {
        // A download already under way keeps the plan it started with.
        guard !AskSetup.downloading else { return }
        plan = AskSetup.plan
        free = AskSetup.freeBytes
    }

    private func shortWords(_ short: AskSetupPlan.Short) -> String {
        switch short {
        case .memory: AskSetupCopy.tooLittleMemory
        case .disk(let needed): AskSetupCopy.tooLittleDisk(needed)
        }
    }

    /// One part of the set: its name, what it is for and its size, or how far
    /// along its download is.
    private func part(name: String, role: String, bytes: Int64, fetch: AskModelDownload, control: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.body.weight(.medium))
                Text(role).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text(fetch.active ? "\(AskBuiltInModels.sizeWords(fetch.done)) of \(AskBuiltInModels.sizeWords(bytes))"
                                  : AskBuiltInModels.sizeWords(bytes))
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            if fetch.active {
                ProgressView(value: fetch.fraction)
                    .playtestControl("\(control) Progress", detail: String(format: "%.0f%%", fetch.fraction * 100))
            }
        }
        .playtestControl(control, detail: "\(name), \(AskBuiltInModels.sizeWords(bytes))")
    }

    @ViewBuilder
    private func buttons(_ ask: AskSession) -> some View {
        HStack {
            Button(AskSetupCopy.otherModels) {
                ask.hideSetup()
                AppDelegate.coordinator?.showSettings(section: .ask)
            }
            .playtestControl("Ask Setup Other Models", detail: AskSetupCopy.otherModels)
            Spacer()
            if plan.short != nil {
                Button(AskSetupCopy.ok) { ask.cancelSetup() }
                    .keyboardShortcut(.defaultAction)
                    .playtestControl("Ask Setup OK", detail: AskSetupCopy.ok)
            } else if AskSetup.downloading {
                Button(AskSetupCopy.stop) { ask.stopSetup() }
                    .playtestControl("Ask Setup Stop", detail: AskSetupCopy.stop)
                Button(AskSetupCopy.hide) { ask.hideSetup() }
                    .keyboardShortcut(.defaultAction)
                    .playtestControl("Ask Setup Hide", detail: AskSetupCopy.hide)
            } else {
                Button(AskSetupCopy.notNow) { ask.cancelSetup() }
                    .keyboardShortcut(.cancelAction)
                    .playtestControl("Ask Setup Not Now", detail: AskSetupCopy.notNow)
                Button(AskSetupCopy.download) { ask.startSetup(plan) }
                    .keyboardShortcut(.defaultAction)
                    .playtestControl("Ask Setup Download", detail: AskSetupCopy.download)
            }
        }
    }
}
