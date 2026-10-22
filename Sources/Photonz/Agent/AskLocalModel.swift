import Foundation
import PhotonzCore

/// The model on this Mac that answers Ask (`docs/design/ask.md`). By
/// default it runs inside Photonz (`AskModelServer`, on a model Settings
/// downloads); Ollama on its loopback port only when a person picks it in
/// Settings. Nothing goes further than this Mac: the address is 127.0.0.1,
/// and Ask never names another.
@MainActor
enum AskLocalModel {

    /// Ollama's address, used only when Settings says Ollama (`AskRuntime`).
    static let base = AskRuntime.ollamaBase
    /// Settings' choice of model; absent means automatic (`AskModels`).
    static let choiceKey = "ask.model"
    /// Settings' choice of built-in model; absent means automatic.
    static let builtInChoiceKey = "ask.builtInModel"

    static var chosen: String? {
        get { UserDefaults.standard.string(forKey: choiceKey) }
        set { UserDefaults.standard.set(newValue, forKey: choiceKey) }
    }

    static var builtInChosen: String? {
        get { UserDefaults.standard.string(forKey: builtInChoiceKey) }
        set { UserDefaults.standard.set(newValue, forKey: builtInChoiceKey) }
    }

    /// Where Ask's model runs: inside Photonz unless Settings says Ollama.
    static var runtime: AskRuntime {
        get { AskRuntime.from(stored: UserDefaults.standard.string(forKey: AskRuntime.settingKey)) }
        set { UserDefaults.standard.set(newValue == .builtIn ? nil : newValue.rawValue, forKey: AskRuntime.settingKey) }
    }

    /// A model to look at drawings with instead of the planning model. Not in
    /// Settings: it is how the eval measures one model against two
    /// (`docs/design/ask.md`, "The model"), set with `defaults write`.
    static var eyesOverride: String? { UserDefaults.standard.string(forKey: "ask.eyes") }

    /// This Mac's memory, in GB, for which models it can hold.
    static var memoryGigabytes: Double { AskModels.gigabytes(ofMemory: ProcessInfo.processInfo.physicalMemory) }

    enum Trouble: Error, Equatable {
        /// Ollama, picked in Settings, does not answer.
        case noRunner
        /// No model Ask plans well with is on the Mac yet.
        case noModel
        /// The model is still downloading.
        case downloading
        /// The built-in model would not start.
        case wouldNotStart
        /// It answered with an error of its own.
        case said(String)

        /// One short plain sentence for the panel.
        var sentence: String {
            switch self {
            case .noRunner: "Ask can't reach Ollama. See Settings."
            case .noModel: "Ask needs its model. Get it in Settings."
            case .downloading: "Ask is getting its model ready."
            case .wouldNotStart: "Ask's model didn't start. Try again."
            case .said(let words): words
            }
        }

        /// Whether Settings is where it gets fixed, so Ask offers the way there.
        var isSetup: Bool { self == .noRunner || self == .noModel || self == .downloading }

        /// The sentences Settings fixes, so the panel can offer the way there.
        static let setupSentences: Set<String> = Set([Trouble.noRunner, .noModel, .downloading].map(\.sentence))
    }

    /// The models Ask can use: the built-in ones downloaded, or Ollama's, or
    /// nil when Ollama is picked and does not answer.
    static func installed() async -> [String]? {
        if runtime == .builtIn { return AskModelServer.downloaded }
        return await ollamaInstalled()
    }

    /// The models Ollama has, or nil when Ollama does not answer.
    static func ollamaInstalled() async -> [String]? {
        guard let url = base?.appending(path: "api/tags") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? AgentJSON.parse(data) else { return nil }
        return (json["models"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue }
    }

    /// The model Ask will use now, or why there is none.
    static func model() async -> Result<String, Trouble> {
        if runtime == .builtIn {
            guard let choice = AskBuiltInModels.resolve(chosen: builtInChosen, downloaded: AskModelServer.downloaded,
                                                        memoryGigabytes: memoryGigabytes) else {
                return .failure(AskModelDownload.shared.active ? .downloading : .noModel)
            }
            return .success(choice.id)
        }
        guard let installed = await installed() else { return .failure(.noRunner) }
        guard let model = AskModels.resolve(chosen: chosen, installed: installed, memoryGigabytes: memoryGigabytes) else {
            return .failure(.noModel)
        }
        return .success(model)
    }

    /// Whether a model can see a picture, as Ollama says (`/api/show`'s
    /// capabilities), falling back to the measured list.
    static func sees(_ model: String) async -> Bool {
        if runtime == .builtIn { return AskBuiltInModels.choice(id: model)?.sees ?? false }
        let measured = AskModels.ranked.first { $0.tag == model }?.sees ?? false
        guard let url = base?.appending(path: "api/show") else { return measured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = (["model": .string(model)] as AgentJSON).encoded()
        request.timeoutInterval = 5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let capabilities = (try? AgentJSON.parse(data))?["capabilities"]?.arrayValue else { return measured }
        return capabilities.contains { $0.stringValue == "vision" }
    }

    /// Ask's own session: nothing cached, nothing shared with the rest of the app.
    nonisolated private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
    }()

    /// One turn of the chat. A big model's first answer can take a while to
    /// load, so the wait is long; Stop cancels it.
    static func chat(_ body: AgentJSON) async throws -> AgentJSON {
        if runtime == .builtIn {
            guard let choice = body["model"]?.stringValue.flatMap(AskBuiltInModels.choice(id:)),
                  AskModelServer.isDownloaded(choice) else { throw Trouble.noModel }
            let json: AgentJSON
            do {
                json = try await AskModelServer.shared.chat(body, on: choice)
            } catch is AskModelServer.Failure {
                throw Trouble.wouldNotStart
            }
            if let said = json["error"]?.stringValue { throw Trouble.said(said) }
            return json
        }
        guard let url = base?.appending(path: "api/chat") else { throw Trouble.noRunner }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.encoded()
        request.timeoutInterval = 300
        let data = try await send(request)
        let json = try AgentJSON.parse(data)
        if let said = json["error"]?.stringValue { throw Trouble.said(said) }
        return json
    }

    nonisolated static func send(_ request: URLRequest) async throws -> Data {
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                let task = session.dataTask(with: request) { data, _, error in
                    if let data {
                        continuation.resume(returning: data)
                    } else if (error as? URLError)?.code == .cancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(throwing: Trouble.noRunner)
                    }
                }
                box.task = task
                task.resume()
            }
        } onCancel: {
            box.task?.cancel()
        }
    }

    /// The running request, for Stop.
    private final class TaskBox: @unchecked Sendable {
        // Written once before the request starts, read by a cancel.
        var task: URLSessionDataTask?
    }
}
