import Foundation
import PhotonzCore

/// The picture model on this Mac that paints Ask's drawings when "Ask paints
/// its drawings" is on (`Scripts/picture-model/`): Z-Image Turbo behind a
/// loopback port, which answers with the picture already traced into named,
/// filled paths. Like Ask's planning model, nothing goes further than
/// 127.0.0.1.
@MainActor
enum AskPictureModel {

    static let base = URL(string: "http://127.0.0.1:8793")
    /// A picture takes about 25 seconds; a first one also loads the model.
    static let patienceSeconds: TimeInterval = 180

    struct Painted {
        let svg: String
        let model: String
        let paths: Int
        let seconds: Double
    }

    /// Whether the switch is on and the picture model answers.
    static func isReady() async -> Bool {
        guard Experiments.shared.isEnabled(FeatureCatalog.askPaintsFlag),
              let url = base?.appending(path: "health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? AgentJSON.parse(data) else { return false }
        return json["ready"]?.boolValue == true
    }

    /// The drawing `call` asks for, painted and traced; nil when the switch
    /// is off or the picture model is not there, so the drawing is made the
    /// usual way instead.
    static func paint(_ call: AgentDrawingCall) async -> Result<Painted, AgentWork.Failure>? {
        guard Experiments.shared.isEnabled(FeatureCatalog.askPaintsFlag), call.svg == nil,
              let url = base?.appending(path: "draw"), await isReady() else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = patienceSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = (try? JSONEncoder().encode(PictureModelRequest(call)))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        // A drawing Ask looks at and draws again gets a new picture, not the same one.
        body["seed"] = Int.random(in: 1...999_999)
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let json = try? AgentJSON.parse(data) else {
            return .failure(AgentWork.Failure("add_drawing: the picture model did not answer."))
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200, let svg = json["svg"]?.stringValue else {
            return .failure(AgentWork.Failure("add_drawing: the picture model said \(json["error"]?.stringValue ?? "nothing")."))
        }
        let model = (json["model"]?.stringValue ?? "z-image-turbo").split(separator: "/").last.map(String.init) ?? "picture model"
        return .success(Painted(svg: svg, model: model, paths: Int(json["paths"]?.doubleValue ?? 0),
                                seconds: json["seconds"]?.doubleValue ?? 0))
    }
}
