import Foundation
import PhotonzCore

/// The model on this Mac that answers Ask (`docs/design/ask.md`), reached
/// through Ollama on its loopback port. Nothing goes further than this Mac:
/// the address is 127.0.0.1, and Ask never names another.
@MainActor
enum AskLocalModel {

    static let base = URL(string: "http://127.0.0.1:11434")
    /// Settings' choice of model; absent means automatic (`AskModels`).
    static let choiceKey = "ask.model"

    static var chosen: String? {
        get { UserDefaults.standard.string(forKey: choiceKey) }
        set { UserDefaults.standard.set(newValue, forKey: choiceKey) }
    }

    enum Trouble: Error, Equatable {
        /// Ollama is not running, or not installed.
        case noRunner
        /// It runs, but has none of the models Ask plans well with.
        case noModel
        /// It answered with an error of its own.
        case said(String)

        /// One short plain sentence for the panel.
        var sentence: String {
            switch self {
            case .noRunner: "Ask needs Ollama. See Settings."
            case .noModel: "Ask needs a local model. See Settings."
            case .said(let words): words
            }
        }
    }

    /// The models Ollama has, or nil when Ollama does not answer.
    static func installed() async -> [String]? {
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
        guard let installed = await installed() else { return .failure(.noRunner) }
        guard let model = AskModels.resolve(chosen: chosen, installed: installed) else { return .failure(.noModel) }
        return .success(model)
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

    nonisolated private static func send(_ request: URLRequest) async throws -> Data {
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
