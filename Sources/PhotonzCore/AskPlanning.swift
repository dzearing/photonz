import CoreGraphics
import Foundation

// Ask in the app (`docs/design/ask.md`): a request in plain words, turned by a
// model on this Mac into a plan of the agent tools (`AgentTools`), the same
// commands the MCP server offers. The model may LOOK (the read-only tools
// answer at once) but every editing call is only written into the plan,
// checked against its schema first, and runs, as one undo step, once the
// model is done. Nothing half planned ever touches the document.

/// Which agent tools Ask offers its model, and how they are shown to it.
public enum AskTools {

    /// Read-only: run while planning, their answers go back to the model.
    public static let looking: [String] = [
        "read_document", "find_elements", "find_measurements", "find_misalignments", "list_components", "list_styles", "list_titles",
        "recommended_zooms", "list_commands",
    ]

    /// Edits: written into the plan, run once it is complete. Nothing here opens a
    /// window, writes a file or steps the history, so the whole plan lands in
    /// the asking document's own undo history as one step.
    public static let doing: [String] = [
        "add_drawing", "add_photo", "add_shape", "add_path", "add_text", "set_layer", "add_measurement", "mark_measurements", "mark_misalignments",
        "place_component", "add_component",
        "add_style", "apply_style", "set_layout", "run_command",
        "add_title", "cut", "trim", "move_clip", "set_transition", "apply_zooms",
    ]

    /// Offered only for a painting, with the Brush there to paint it: what
    /// every other request is shown stays exactly as it was.
    public static let paintingLooking = ["list_brushes"]
    public static let paintingDoing = ["paint_stroke"]

    public static func looking(painting: Bool) -> [String] { painting ? looking + paintingLooking : looking }
    public static func doing(painting: Bool) -> [String] { painting ? doing + paintingDoing : doing }

    /// The tools shown to the model for a request, a painting's with the brush's.
    public static func modelTools(painting: Bool) -> [AgentJSON] {
        painting ? modelTools + (paintingLooking + paintingDoing).compactMap(modelTool) : modelTools
    }

    /// The tools in the shape Ollama's chat API takes them. `document` is left
    /// out (Ask always works on the document it was opened over), and a
    /// property given as a choice of types shows its first, since some model
    /// templates cannot read a property with no type. The real schema still
    /// checks every call.
    public static let modelTools: [AgentJSON] = (looking + doing).compactMap(modelTool)

    static func modelTool(_ name: String) -> AgentJSON? {
        guard let tool = AgentTools.tool(named: name) else { return nil }
        return ["type": "function",
                "function": ["name": .string(tool.name), "description": .string(tool.description),
                             "parameters": modelSchema(tool.inputSchema, top: true)]]
    }

    /// add_component's keys in the order a person writes them: what a part
    /// is, where it sits, its words, then its paint. A model runner that holds
    /// a tool call to its schema (the model built into Photonz) only lets the
    /// model write keys in the schema's own order, and sorted they put height
    /// before width and every look before the parts it changes, so a model
    /// that wrote width first could never give a height (2026-10-23).
    static let componentKeyOrder = [
        "name", "shape", "part", "x", "y", "width", "height", "step", "labels", "property", "parts", "firstLook", "looks", "changes",
        "text", "fontSize", "weight", "color", "alignment", "centerIn",
        "fill", "stroke", "strokeWidth", "cornerRadius", "opacity", "shadow", "removeShadow", "visible",
        "points", "closed", "smooth",
    ]

    /// A list_components answer with the Library's starters taken out. They
    /// are placeholders, and a model shown them answered "base components"
    /// with exactly their five kinds (the user, 2026-10-20; again 2026-10-23
    /// after add_component). A starter asked for by name still places.
    public static func withoutStarters(_ listing: String) -> String {
        guard let entries = (try? AgentJSON.parse(Data(listing.utf8)))?.arrayValue else { return listing }
        return AgentJSON.array(entries.filter { $0["from"]?.stringValue != "starter" }).encodedString()
    }

    /// A chat body as it goes to the model: keys sorted, add_component's
    /// schema in `componentKeyOrder`.
    public static func wireEncoded(_ body: AgentJSON) -> Data {
        body.encoded(leading: componentKeyOrder) { json in
            json["name"]?.stringValue == "add_component" && json["parameters"] != nil
        }
    }

    static func modelSchema(_ schema: AgentJSON, top: Bool = false) -> AgentJSON {
        switch schema {
        case .object(var object):
            if object["type"] == nil, let first = object["anyOf"]?.arrayValue?.first, let type = first["type"] {
                object["type"] = type
                object["anyOf"] = nil
            }
            if var properties = object["properties"]?.objectValue {
                if top { properties["document"] = nil }
                object["properties"] = .object(properties.mapValues { modelSchema($0) })
            }
            if top, let required = object["required"]?.arrayValue {
                object["required"] = .array(required.filter { $0 != "document" })
            }
            if let items = object["items"] { object["items"] = modelSchema(items) }
            return .object(object)
        case .array(let array):
            return .array(array.map { modelSchema($0) })
        default:
            return schema
        }
    }
}

/// One line of a plan: a tool and its arguments, as the model wrote them.
public struct AskStep: Hashable, Sendable {
    public let tool: String
    public let arguments: AgentJSON

    public init(tool: String, arguments: AgentJSON) {
        self.tool = tool
        self.arguments = arguments
    }

    /// The arguments with every `$N` swapped for what step N made, and the
    /// document Ask was opened over.
    public func resolvedArguments(document: String, made: [Int: String]) -> AgentJSON {
        func resolve(_ value: AgentJSON) -> AgentJSON {
            switch value {
            case .string(let word):
                if word.hasPrefix("$"), let n = Int(word.dropFirst()), let id = made[n] { return .string(id) }
                return value
            case .array(let array): return .array(array.map(resolve))
            case .object(let object): return .object(object.mapValues(resolve))
            default: return value
            }
        }
        var object = resolve(arguments).objectValue ?? [:]
        object["document"] = .string(document)
        return .object(object)
    }

    /// The step checked and typed, ready for the app to run.
    public func request(document: String, made: [Int: String]) -> Result<AgentRequest, AgentToolError> {
        AgentTools.request(tool: tool, arguments: resolvedArguments(document: document, made: made))
    }

    /// The id of what a step made, read from its answer: a layer, a clip or a
    /// title, so a later step's `$N` can name it.
    public static func madeID(fromAnswer text: String) -> String? {
        guard let answer = try? AgentJSON.parse(Data(text.utf8)) else { return nil }
        for key in ["layer", "clip", "title", "id"] {
            if let id = answer[key]?.stringValue { return id }
        }
        return nil
    }

    /// What a person reads in the plan: the command's name and a few words.
    public struct Line: Hashable, Sendable {
        public static let detailBudget = 28
        public let name: String
        public let detail: String
        public init(name: String, detail: String) {
            self.name = name
            self.detail = detail
        }
    }

    public var line: Line { line(names: [:]) }

    /// The line, with ids the model looked up shown by their names.
    public func line(names: [String: String]) -> Line {
        var text = detail
        if text.isEmpty, let component = arguments["component"]?.stringValue {
            // By the name list_components gave it; a model that named the
            // component by its name already wrote the words to show.
            text = names[component] ?? (UUID(uuidString: component) == nil ? component : "")
        }
        if text.isEmpty, let name = arguments["name"]?.stringValue { text = name }
        if text.count > Line.detailBudget { text = String(text.prefix(Line.detailBudget - 1)) + "\u{2026}" }
        return Line(name: tool, detail: text)
    }

    private var detail: String {
        let args = arguments
        func size(_ box: AgentJSON?) -> String? {
            guard let w = box?["width"]?.doubleValue, let h = box?["height"]?.doubleValue else { return nil }
            return "\(Self.number(w)) × \(Self.number(h))"
        }
        func quoted(_ words: String?) -> String? {
            guard let words, !words.isEmpty else { return nil }
            let room = Line.detailBudget - 2
            let flat = words.replacingOccurrences(of: "\n", with: " ")
            let cut = flat.count > room ? String(flat.prefix(room - 1)) + "\u{2026}" : flat
            return "\u{201C}\(cut)\u{201D}"
        }
        let words: String? = switch tool {
        case "add_text", "add_title": quoted(args["text"]?.stringValue)
        case "add_shape", "add_measurement":
            [args["kind"]?.stringValue, size(args["box"])].compactMap { $0 }.joined(separator: " ")
        case "run_command": args["command"]?.stringValue
        case "place_component": nil
        case "apply_style": args["style"]?.stringValue
        case "add_style": args["name"]?.stringValue
        case "set_layout": args["kind"]?.stringValue
        case "set_transition": args["kind"]?.stringValue
        case "cut": args["seconds"]?.doubleValue.map { "at \(Self.number($0)) s" }
        case "set_layer":
            (args.objectValue ?? [:]).keys.filter { $0 != "layer" && $0 != "document" }.sorted { a, b in
                (Self.layerKeyOrder.firstIndex(of: a) ?? 99, a) < (Self.layerKeyOrder.firstIndex(of: b) ?? 99, b)
            }.joined(separator: ", ")
        default: nil
        }
        let text = words ?? ""
        return text.count > Line.detailBudget ? String(text.prefix(Line.detailBudget - 1)) + "\u{2026}" : text
    }

    private static let layerKeyOrder = ["text", "fill", "stroke", "x", "y", "width", "height"]

    private static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// The steps the model wrote, run together once it is done.
public struct AskPlan: Hashable, Sendable {
    public let steps: [AskStep]
    /// The model's one sentence saying what the plan does.
    public let summary: String
    /// Names of things the model looked up by id (components), for its lines.
    public let names: [String: String]

    public init(steps: [AskStep], summary: String, names: [String: String] = [:]) {
        self.steps = steps
        self.summary = summary
        self.names = names
    }

    /// Step `number`'s line, as the Agent group shows it.
    public func line(_ number: Int) -> AskStep.Line { steps[number - 1].line(names: names) }

    /// The plan with step `number`'s drawing given `statements` as its plan
    /// (`AskDrawingCheck.unplanned`). No statements changes nothing.
    public func settingDrawingPlan(step number: Int, to statements: [String]) -> AskPlan {
        guard !statements.isEmpty, steps.indices.contains(number - 1),
              var arguments = steps[number - 1].arguments.objectValue else { return self }
        arguments["plan"] = .array(statements.map { .string($0) })
        var changed = steps
        changed[number - 1] = AskStep(tool: changed[number - 1].tool, arguments: .object(arguments))
        return AskPlan(steps: changed, summary: summary, names: names)
    }

    /// The plan with step `number`'s drawing plan replaced by `statements`;
    /// none takes the plan off, so the drawing is a plain thing.
    public func replacingDrawingPlan(step number: Int, with statements: [String]) -> AskPlan {
        guard steps.indices.contains(number - 1), var arguments = steps[number - 1].arguments.objectValue else { return self }
        arguments["plan"] = statements.isEmpty ? nil : .array(statements.map { .string($0) })
        var changed = steps
        changed[number - 1] = AskStep(tool: changed[number - 1].tool, arguments: .object(arguments))
        return AskPlan(steps: changed, summary: summary, names: names)
    }

    /// Whether a step after step `number` names what it makes (`$number`).
    /// A step the app refuses changes nothing, so it can be passed over,
    /// unless a later step was counting on it.
    public func isNamedLater(_ number: Int) -> Bool {
        let name = AgentJSON.string("$\(number)")
        func names(_ value: AgentJSON) -> Bool {
            switch value {
            case .string: value == name
            case .array(let array): array.contains(where: names)
            case .object(let object): object.values.contains(where: names)
            default: false
            }
        }
        return steps.dropFirst(number).contains { names($0.arguments) }
    }
}

/// A looking call the app runs while planning.
public struct AskLook: Hashable, Sendable {
    public let tool: String
    public let arguments: AgentJSON
}

/// The talk with the model while it plans: the messages so far and the plan
/// it has written. The app sends `chatBody`, hands each reply to `take`, runs
/// the looks it returns and answers them, and asks again until the model
/// stops calling tools.
public struct AskConversation: Sendable {

    public enum Outcome: Hashable, Sendable {
        /// Run these looks (maybe none), answer them, and ask the model again.
        case again(looks: [AskLook])
        /// The model is done: here is the plan.
        case planned(AskPlan)
        /// The model wrote no step: its own short sentence why.
        case cannot(String)
    }

    public private(set) var messages: [AgentJSON]
    public private(set) var steps: [AskStep] = []
    /// One line Ask says beside what it made: that it made a different kind
    /// of picture from the one asked for, and why.
    public private(set) var note: String?
    /// What list_components named each id.
    public private(set) var names: [String: String] = [:]
    /// How many times the model has been asked; the app stops at `mostRounds`.
    public private(set) var rounds = 0
    /// Every tool call the model has made, and the ones that came back
    /// broken: arguments the tool cannot take, a tool it was never given, or
    /// a call written out as text. What the model bake-off counts
    /// (`docs/design/ask.md`, "The model").
    public private(set) var calls = 0
    public private(set) var brokenCalls = 0
    /// Thirty since 2026-10-23: a kit of base components is one add_component
    /// a round, a dozen or more of them, then its title and labels, and twelve
    /// rounds ran out before the last few components. A model stuck sending
    /// one refused call is stopped sooner (`mostSameRefusals`).
    public static let mostRounds = 30
    /// More readouts than this crowd a screenshot past reading.
    public static let mostMeasurements = 12
    /// A sheet of components fills a picture at about this many rows.
    public static let mostComponents = 12
    public static let contextWindow = 32768

    /// The canvas's width, read from the document, for sorting what
    /// `find_elements` finds. A sheet of components that needs more room
    /// than the canvas has grows it as it lands, from the table as laid out
    /// (`AgentDesignWork.addComponent`), so the plan needs no height.
    private let canvasWidth: Double
    private let canvasHeight: Double

    /// `components` and `styles` are list_components' and list_styles'
    /// answers, handed over up front so "on brand" never starts from nothing.
    /// What the person typed, read for the look they named.
    private let request: String
    /// Every drawing is painted by the picture model on this Mac and traced
    /// into layers ("Ask paints its drawings"), so any subject plans as it
    /// is and no svg is asked for.
    private let paints: Bool
    /// The Brush paints here (a picture, in a release that has it), so a
    /// painting asked for is painted stroke by stroke with paint_stroke.
    private let brushes: Bool
    /// This request is a painting and the Brush is there to paint it.
    private let painting: Bool

    public init(request: String, documentRead: String, components: String = "", styles: String = "",
                titles: String = "", paints: Bool = false, brushes: Bool = false) {
        self.request = request
        self.paints = paints
        self.brushes = brushes
        let canvas = (try? AgentJSON.parse(Data(documentRead.utf8)))?["canvas"]
        canvasWidth = canvas?["width"]?.doubleValue ?? 0
        canvasHeight = canvas?["height"]?.doubleValue ?? 0
        let painting = brushes && AgentPictureKind.asked(in: request) == .paint
        self.painting = painting
        var instructions = Self.instructions(documentRead: documentRead, paints: paints, painting: painting)
        if !components.isEmpty { instructions += "\nThe Library's components (list_components):\n\(components)" }
        if !styles.isEmpty { instructions += "\nThe saved styles (list_styles):\n\(styles)" }
        if !titles.isEmpty {
            instructions += "\nThe title styles add_title takes, by name (list_titles):\n\(titles)"
        }
        messages = [
            ["role": "system", "content": .string(instructions)],
            ["role": "user", "content": .string(request)],
        ]
        learnNames(components)
    }

    private mutating func learnNames(_ listing: String) {
        guard let listed = try? AgentJSON.parse(Data(listing.utf8)) else { return }
        for entry in listed.arrayValue ?? [] {
            if let id = entry["id"]?.stringValue, let name = entry["name"]?.stringValue { names[id] = name }
        }
    }

    /// The body of one `POST /api/chat`.
    public func chatBody(model: String) -> AgentJSON {
        ["model": .string(model), "messages": .array(messages), "tools": .array(AskTools.modelTools(painting: painting)),
         "stream": false, "think": false, "keep_alive": "30m",
         "options": ["num_ctx": .number(Double(Self.contextWindow)), "temperature": 0]]
    }

    /// Reads one reply from the model.
    public mutating func take(_ response: AgentJSON) -> Outcome {
        rounds += 1
        let message = response["message"] ?? [:]
        messages.append(message)
        let content = Self.withoutThinking(message["content"]?.stringValue ?? "")
        var calls: [(String, AgentJSON)] = (message["tool_calls"]?.arrayValue ?? []).compactMap { call in
            guard let name = call["function"]?["name"]?.stringValue else { return nil }
            return (name, Self.arguments(call["function"]?["arguments"]))
        }
        if calls.isEmpty {
            calls = Self.callsWritten(in: content)
            brokenCalls += calls.count
        }
        self.calls += calls.count
        guard !calls.isEmpty else {
            let sentence = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if steps.isEmpty, !nudged {
                // A small model gives up early: ask once more to try.
                nudged = true
                messages.append(["role": "user", "content": .string(Self.nudge)])
                return .again(looks: [])
            }
            if steps.isEmpty {
                return .cannot(sentence.isEmpty ? Self.noPlanSentence : sentence)
            }
            // A sheet of labelled rows with no title is asked for one once
            // (the eval, 2026-10-23: twelve rows and no title).
            if askForTitle() { return .again(looks: []) }
            return .planned(AskPlan(steps: steps, summary: sentence, names: names))
        }
        var looks: [AskLook] = []
        for (name, said) in calls {
            let arguments = name == "add_text" || name == "add_component" ? Self.withoutEntities(said) : said
            if AskTools.looking(painting: painting).contains(name) {
                looks.append(AskLook(tool: name, arguments: arguments))
            } else if AskTools.doing(painting: painting).contains(name) {
                var step = AskStep(tool: name, arguments: arguments)
                if name == "add_measurement",
                   steps.filter({ $0.tool == "add_measurement" }).count >= Self.mostMeasurements {
                    tell(name, "Not planned: \(Self.mostMeasurements) measurements is the most a picture reads well with. Plan nothing more of them; finish.")
                    continue
                }
                if name == "add_component",
                   steps.filter({ $0.tool == "add_component" }).count >= Self.mostComponents {
                    tell(name, "Not planned: \(Self.mostComponents) components fill a sheet. Plan nothing more of them; finish.")
                    continue
                }
                if name == "add_text", let words = arguments["text"]?.stringValue, let earlier = labelledBy(words) {
                    tell(name, "Not planned: step \(earlier) already sets those words beside its row. Plan something else, or finish.")
                    continue
                }
                // The title comes first; after it the table names every row
                // and state, and words of the model's own (a section heading)
                // were laid over by its rows (the eval, 2026-10-23).
                if name == "add_text", steps.contains(where: { $0.tool == "add_text" }),
                   steps.contains(where: { $0.tool == "add_component" && $0.arguments["labels"]?.boolValue == true }) {
                    refuse(name, arguments, "Not planned: the table names its own rows and states, and words of your own would land on it. Plan the next component, or finish.")
                    continue
                }
                // A painting is sketched, and the sketch painted stroke by stroke.
                if painting, name == "add_drawing" {
                    paintSketch(arguments)
                    continue
                }
                // A photo, a drawing or a painting, as the person's words say.
                var name = name, arguments = arguments
                if name == "add_drawing" || name == "add_photo" {
                    let routed = Self.routed(name, arguments, request: request, paints: paints, brushes: brushes)
                    if let refusal = routed.refusal {
                        tell(name, refusal)
                        continue
                    }
                    (name, arguments) = (routed.tool, routed.arguments)
                    if let line = routed.note { note = line }
                    step = AskStep(tool: name, arguments: arguments)
                }
                arguments = name == "add_drawing" ? Self.withStyleWords(arguments, from: request) : arguments
                if name == "add_drawing", let problem = drawingProblem(arguments) {
                    brokenCalls += 1
                    tell(name, "Not planned. \(problem)")
                    continue
                }
                if name == "add_drawing" {
                    var drawing = arguments
                    if paints, var object = drawing.objectValue {
                        object["asked"] = .string(request)
                        drawing = .object(object)
                    }
                    step = AskStep(tool: name, arguments: drawing)
                }
                if name == "add_component" {
                    step = AskStep(tool: name, arguments: AgentNewComponent.madePlain(arguments))
                }
                if let earlier = repeated(step) {
                    refuse(name, step.arguments, "Not planned: step \(earlier) already does that. Plan something else, or finish.")
                    continue
                }
                if name == "add_drawing", let earlier = stacked(step) {
                    tell(name, "Not planned: step \(earlier) already draws the whole picture in that place, and a second one would land on top of it. A scene is one add_drawing. Plan something else, or finish.")
                    continue
                }
                // Checked as it would run, with $N standing in for ids not made yet.
                switch AgentTools.request(tool: name, arguments: name == "add_component" ? step.arguments : arguments) {
                case .success(.addComponent(_, let component)) where drawnBefore(component) != nil:
                    let (earlier, kind) = drawnBefore(component) ?? (0, "")
                    let made = steps.compactMap { $0.tool == "add_component" ? $0.arguments["name"]?.stringValue : nil }
                    refuse(name, step.arguments, "Not planned: \(component.name) is drawn the same as \(kind), step \(earlier). A sheet shows each kind of control once. Planned so far: \(made.joined(separator: ", ")). Make a kind that is not in that list, drawn as that kind is, or finish.")
                case .success(.addComponent(_, let component)) where component.labels && namedBefore(component) != nil:
                    // Two rows with one name read as the same thing twice (the
                    // eval, 2026-10-24: a filled and a grey button both "Button").
                    let earlier = namedBefore(component) ?? 0
                    refuse(name, step.arguments, "Not planned: step \(earlier) already has a row called \(component.name.trimmingCharacters(in: .whitespaces)). Name this one for what makes it different from that row, or finish.")
                case .success(.addComponent(_, let component)) where Self.cannotBuild(component) != nil:
                    brokenCalls += 1
                    refuse(name, step.arguments, "Not planned. \(Self.cannotBuild(component) ?? "")")
                case .success:
                    // The title asked for after the rows goes first, so it
                    // sits above them, when no step names another by $N.
                    if askedForTitle, name == "add_text", !steps.contains(where: { $0.tool == "add_text" }),
                       !steps.contains(where: { $0.arguments.encodedString().contains("\"$") }) {
                        steps.insert(step, at: 0)
                        sameRefusals = 0
                        lastRefused = ""
                        tell(name, "Planned as step 1.")
                        continue
                    }
                    steps.append(step)
                    if name == "add_component" { alignSheet() }
                    sameRefusals = 0
                    lastRefused = ""
                    tell(name, "Planned as step \(steps.count). Refer to what it makes as $\(steps.count).")
                case .failure(let failure):
                    brokenCalls += 1
                    refuse(name, step.arguments, "Not planned. \(failure.message)")
                }
            } else {
                brokenCalls += 1
                tell(name, "\(name) is not one of your tools here. Use only the tools you were given.")
            }
        }
        // A component sent back unchanged once is taken out of the talk and
        // the model asked, as a new turn, for the next kind: told so in a
        // tool answer it sent the same call a third time (the eval,
        // 2026-10-23), and one kind it cannot draw ended the sheet.
        if calls.count == 1, calls[0].0 == "add_component", sameRefusals == 1,
           let kind = calls[0].1["name"]?.stringValue, leftOut.insert(kind).inserted,
           messages.count >= 2, messages[messages.count - 1]["role"]?.stringValue == "tool" {
            messages.removeLast(2)
            messages.append(["role": "user", "content": .string("Leave \(kind) out: it could not be planned. Plan the next kind of component the sheet does not have yet, or finish.")])
            sameRefusals = 0
            lastRefused = ""
            return .again(looks: [])
        }
        // A small model at temperature 0 that sends a refused call back
        // unchanged sends it every round after; the plan it has is offered
        // instead of the rest of the rounds going on the same refusal.
        if sameRefusals >= Self.mostSameRefusals, !steps.isEmpty, looks.isEmpty {
            return .planned(AskPlan(steps: steps, summary: "", names: names))
        }
        return .again(looks: looks)
    }

    /// Why a component whose call reads fine still could not be built, or
    /// nil: it is built once on an empty picture, words sized from their
    /// font, so a look whose change cannot land is refused while the model
    /// can still fix it. A planned Navigation was skipped when the plan ran
    /// and the sheet asked for navigation had none (the eval, 2026-10-24).
    static func cannotBuild(_ component: AgentNewComponent) -> String? {
        var scratch = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024), layers: [])
        let estimate: (TextContent, CGFloat?) -> CGSize = { content, width in
            let natural = CGFloat(content.string.count) * content.fontSize * AgentNewComponent.letterWidth
            return CGSize(width: max(1, min(natural, width ?? natural)), height: content.fontSize * 1.3)
        }
        if case .failure(let error) = scratch.agentAddComponent(component, measure: estimate) { return error.message }
        return nil
    }

    /// How tall a labelled component's row is: its tallest part and the
    /// state names under it.
    static func rowHeight(_ arguments: AgentJSON) -> Double {
        let parts = (arguments["parts"]?.arrayValue ?? []).map {
            ($0["y"]?.doubleValue ?? 0) + ($0["height"]?.doubleValue ?? 0)
        }.max() ?? 0
        return parts + Double(AgentNewComponent.labelSize + 4 + AgentNewComponent.captionGap)
    }

    /// The planned labelled component whose own labels already say `words`
    /// (its name or a look's), by step number. The model set its own row
    /// names over the ones add_component placed (2026-10-23).
    func labelledBy(_ words: String) -> Int? {
        let said = words.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for (index, step) in steps.enumerated()
        where step.tool == "add_component" && step.arguments["labels"]?.boolValue == true {
            let names = [step.arguments["name"]?.stringValue, step.arguments["firstLook"]?.stringValue]
                + (step.arguments["looks"]?.arrayValue ?? []).map { $0["name"]?.stringValue }
            if names.compactMap({ $0?.lowercased() }).contains(said) { return index + 1 }
        }
        return nil
    }

    /// Whether a runner's error says it could not read the model's reply as
    /// a tool call (llama.cpp: "Failed to parse tool call arguments as
    /// JSON"). One such reply twenty calls into a kit lost every step already
    /// planned (2026-10-23); with steps planned the app offers them instead,
    /// as it does when the rounds run out.
    public static func isUnreadableReply(_ words: String) -> Bool {
        words.hasPrefix("Failed to parse tool call")
    }

    /// Labelled components are one sheet: every row starts at the first
    /// one's x, and when the longest row fits the canvas they share one step
    /// (the widest look plus the gap), so each state sits in a column. A
    /// small model planning blind gives each its own x and step, and the rows
    /// came out staggered (2026-10-23).
    /// The least room a sheet leaves at the page's left edge, and so at its right.
    static let sheetMargin = 64.0

    mutating func alignSheet() {
        let rows = steps.indices.filter { steps[$0].tool == "add_component" && steps[$0].arguments["labels"]?.boolValue == true }
        guard let first = rows.first, let asked = steps[first].arguments["x"]?.doubleValue else { return }
        // No nearer the page's edge than its margin, the title over it too:
        // at 40 every judge read the last column as nearly touching the
        // right edge (the eval, 2026-10-24).
        let x = max(asked, Self.sheetMargin)
        let top = steps[first].arguments["y"]?.doubleValue ?? 0
        for index in steps.indices where steps[index].tool == "add_text" && index < first {
            guard var arguments = steps[index].arguments.objectValue,
                  let at = arguments["x"]?.doubleValue, at < Self.sheetMargin,
                  (arguments["y"]?.doubleValue ?? 0) < top else { continue }
            arguments["x"] = .number(Self.sheetMargin)
            steps[index] = AskStep(tool: "add_text", arguments: .object(arguments))
        }
        func width(_ arguments: AgentJSON) -> Double {
            (arguments["parts"]?.arrayValue ?? []).map {
                ($0["x"]?.doubleValue ?? 0) + ($0["width"]?.doubleValue ?? 0)
            }.max() ?? 0
        }
        func looks(_ arguments: AgentJSON) -> Int { 1 + (arguments["looks"]?.arrayValue?.count ?? 0) }
        // The shared step is the widest look that still lets its own row
        // fit the canvas at that step; a look wider than that keeps its own.
        let room = canvasWidth - x - Double(AgentNewComponent.labelColumn)
        func fits(_ index: Int, _ step: Double) -> Bool {
            canvasWidth > 0 && Double(looks(steps[index].arguments)) * step <= room
        }
        let gap = Double(AgentNewComponent.lookGap)
        let step = rows.map { (width(steps[$0].arguments) + gap).rounded() }
            .filter { candidate in rows.filter { width(steps[$0].arguments) + gap <= candidate }.allSatisfy { fits($0, candidate) } }
            .max()
        // And down: each row straight under the last, where the app will find
        // it free, so a later row never lands on an earlier one.
        var y = steps[first].arguments["y"]?.doubleValue ?? 0
        for index in rows {
            guard var arguments = steps[index].arguments.objectValue else { continue }
            arguments["x"] = .number(x)
            arguments["y"] = .number(y)
            y += Self.rowHeight(steps[index].arguments) + gap
            let shares = step.map { width(steps[index].arguments) + gap <= $0 && fits(index, $0) } ?? false
            arguments["step"] = shares ? step.map(AgentJSON.number) : nil
            steps[index] = AskStep(tool: "add_component", arguments: .object(arguments))
        }
    }

    /// What Ask says when it was asked to paint before the brushes can.
    public static let brushesNotReady = "No brushes yet, so I made one image."
    /// Told to the model when it plans a painting as one picture.
    static let paintWithStrokes = "Not planned: a painting is painted with the Brush. Call paint_stroke once for every stroke, as the instructions say, and no add_drawing or add_photo."
    public static let brushesNotReadyDrawn = "No brushes yet, so I drew vector art."
    /// Told to the model when a photo is asked for and nothing on this Mac can paint one.
    static let noPhotos = "Not planned: Photonz cannot paint a photo on this Mac until its picture model is set up in Settings, Ask. Call no more tools and answer: I can't make photos until the picture model is set up in Settings, Ask."

    /// Which tool makes the picture the person asked for
    /// (`AgentPictureKind`): a photo when their words say photo, layers when
    /// they say vector art, a drawing or an icon, and the model's own choice
    /// when they say neither. A painting is made the nearest way until the
    /// brushes can paint one, with a line saying so.
    static func routed(_ tool: String, _ arguments: AgentJSON, request: String, paints: Bool, brushes: Bool = false)
        -> (tool: String, arguments: AgentJSON, note: String?, refusal: String?) {
        guard var object = arguments.objectValue else { return (tool, arguments, nil, nil) }
        let kind = AgentPictureKind.asked(in: request)
        // A painting is painted with the brushes, stroke by stroke: one
        // picture made in a painted look is what Ask made before they were.
        if brushes, kind == .paint, object["icon"]?.boolValue != true {
            return (tool, arguments, nil, Self.paintWithStrokes)
        }
        func asPhoto(_ look: AgentPhotoCall.Look) -> AgentJSON {
            var photo: [String: AgentJSON] = ["subject": object["subject"] ?? "", "asked": .string(request)]
            for key in ["frame", "name"] { photo[key] = object[key] }
            if look != .photo { photo["look"] = .string(look.rawValue) }
            return .object(photo)
        }
        if tool == "add_drawing" {
            if object["icon"]?.boolValue == true { return (tool, arguments, nil, nil) }
            switch kind {
            case .photo? where paints: return ("add_photo", asPhoto(.photo), nil, nil)
            case .paint? where paints: return ("add_photo", asPhoto(.painting), Self.brushesNotReady, nil)
            case .paint?: return (tool, arguments, Self.brushesNotReadyDrawn, nil)
            default: return (tool, arguments, nil, nil)
            }
        }
        // add_photo
        switch kind {
        case .vector?:
            var drawing: [String: AgentJSON] = ["subject": object["subject"] ?? ""]
            for key in ["frame", "name"] { drawing[key] = object[key] }
            return ("add_drawing", .object(drawing), nil, nil)
        case _ where !paints:
            return (tool, arguments, nil, Self.noPhotos)
        case .paint?:
            object["look"] = .string(AgentPhotoCall.Look.painting.rawValue)
            object["asked"] = .string(request)
            return (tool, .object(object), Self.brushesNotReady, nil)
        default:
            object["asked"] = .string(request)
            return (tool, .object(object), nil, nil)
        }
    }

    /// Why an add_drawing call cannot draw, or nil when it can: with no
    /// picture model to paint it, the drawing is the model's own SVG, and that
    /// SVG has to read.
    func drawingProblem(_ arguments: AgentJSON) -> String? {
        let subject = arguments["subject"]?.stringValue ?? ""
        if paints { return nil }
        let svg = arguments["svg"]?.stringValue ?? ""
        guard !svg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AgentDrawingCall.needsSVG(subject)
        }
        if case .failure(let trouble) = SVGArtwork.parse(svg) {
            return "add_drawing: \(trouble.message) Write the whole svg again."
        }
        return nil
    }

    /// An add_drawing call with the look words the person typed added to its
    /// style, so "as line art" or "a badge" reaches the drawing even when the
    /// model left it out, and a look the person never named taken off it.
    static func withStyleWords(_ arguments: AgentJSON, from request: String) -> AgentJSON {
        let typed = AgentDrawingWords.lookWords(in: request)
        guard var object = arguments.objectValue else { return arguments }
        let said = Set(AgentDrawingWords.words(request))
        // A badge is not an icon unless the person said icon.
        if object["icon"]?.boolValue == true, !said.contains("icon"), said.contains("badge") {
            object["icon"] = nil
        }
        let given = object["style"]?.stringValue ?? ""
        if typed.isEmpty, !given.isEmpty, said.isDisjoint(with: AgentDrawingWords.words(given)) {
            // A look the person never asked for is the model's guess: the
            // drawing is made in no particular look.
            object["style"] = nil
            return .object(object)
        }
        let missing = typed.filter { !given.lowercased().contains($0) }
        guard !missing.isEmpty else { return .object(object) }
        object["style"] = .string(([given] + missing).filter { !$0.isEmpty }.joined(separator: " "))
        return .object(object)
    }

    /// The drawing did not read as `subject` to a model that could see it
    /// (`AskDrawingCheck`): the plan starts again, told what was seen.
    public mutating func revise(subject: String, seen: String, unmet: [String] = []) {
        steps = []
        rounds = 0
        messages.append(["role": "user", "content": .string(AskDrawingCheck.revisionNote(subject: subject, seen: seen, paints: paints,
                                                                                       unmet: unmet))])
    }

    /// The drawing already planned that this one would land on top of: both
    /// centred (no frame), or their frames mostly the same place. A model
    /// that sends a scene's add_drawing again with its plan reworded would
    /// otherwise paint two whole pictures one over the other.
    func stacked(_ step: AskStep) -> Int? {
        func frame(_ step: AskStep) -> CGRect? {
            let box = step.arguments["frame"]
            guard let x = box?["x"]?.doubleValue, let y = box?["y"]?.doubleValue,
                  let width = box?["width"]?.doubleValue, let height = box?["height"]?.doubleValue else { return nil }
            return CGRect(x: x, y: y, width: width, height: height)
        }
        let mine = frame(step)
        for (index, earlier) in steps.enumerated() where earlier.tool == "add_drawing" {
            let theirs = frame(earlier)
            switch (mine, theirs) {
            case (nil, nil):
                return index + 1
            case (let a?, let b?):
                let shared = a.intersection(b)
                let smaller = min(a.width * a.height, b.width * b.height)
                if !shared.isNull, smaller > 0, shared.width * shared.height > smaller * 0.5 { return index + 1 }
            default:
                continue
            }
        }
        return nil
    }

    /// The step already planned that this one repeats: the same call, or a
    /// size measurement of what is the same box give or take a few points
    /// (`find_elements` lists one control by several readers).
    /// Words with the web's escapes a model sometimes writes ("Cards &amp;
    /// Containers") set as the characters they stand for.
    static func withoutEntities(_ json: AgentJSON) -> AgentJSON {
        switch json {
        case .string(let words) where words.contains("&"):
            var plain = words
            for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&amp;", "&")] {
                plain = plain.replacingOccurrences(of: entity, with: character)
            }
            return .string(plain)
        case .array(let items): return .array(items.map(withoutEntities))
        case .object(let fields): return .object(fields.mapValues(withoutEntities))
        default: return json
        }
    }

    /// The earlier add_component step drawn the same as this one, and what
    /// it is called: a Toggle and a Switch drawn alike are one control twice.
    func drawnBefore(_ component: AgentNewComponent) -> (Int, String)? {
        for (index, step) in steps.enumerated() where step.tool == "add_component" {
            guard case .success(.addComponent(_, let earlier)) = AgentTools.request(tool: step.tool, arguments: step.arguments),
                  component.drawnLike(earlier) else { continue }
            return (index + 1, earlier.name)
        }
        return nil
    }

    /// The earlier labelled add_component step whose row has this one's
    /// name, whatever its case or spaces.
    func namedBefore(_ component: AgentNewComponent) -> Int? {
        func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespaces).lowercased() }
        return steps.indices.first { index in
            let step = steps[index]
            return step.tool == "add_component" && step.arguments["labels"]?.boolValue == true
                && key(step.arguments["name"]?.stringValue ?? "") == key(component.name)
        }.map { $0 + 1 }
    }

    func repeated(_ step: AskStep) -> Int? {
        for (index, earlier) in steps.enumerated() {
            if earlier == step { return index + 1 }
            if step.tool == "add_measurement", earlier.tool == "add_measurement",
               step.arguments["kind"] == "size", earlier.arguments["kind"] == "size",
               let a = Self.box(step.arguments["box"]), let b = Self.box(earlier.arguments["box"]),
               Self.overlap(a, b) > 0.85 {
                return index + 1
            }
        }
        return nil
    }

    private static func box(_ json: AgentJSON?) -> CGRect? {
        guard let x = json?["x"]?.doubleValue, let y = json?["y"]?.doubleValue,
              let w = json?["width"]?.doubleValue, let h = json?["height"]?.doubleValue else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Shared area over the area of both together.
    private static func overlap(_ a: CGRect, _ b: CGRect) -> Double {
        let shared = a.intersection(b)
        guard !shared.isNull else { return 0 }
        let common = shared.width * shared.height
        let union = a.width * a.height + b.width * b.height - common
        return union > 0 ? Double(common / union) : 0
    }

    /// The answer to a look, handed back to the model.
    public mutating func answer(_ look: AskLook, with text: String) {
        if look.tool == "list_components" { learnNames(text) }
        let readable = look.tool == "find_elements" && canvasWidth > 0
            ? AskElements.sorted(text, canvasWidth: canvasWidth) : text
        tell(look.tool, String(readable.prefix(Self.longestLookAnswer)))
    }

    static let longestLookAnswer = 16000
    public static let noPlanSentence = "I couldn't make a plan for that."
    private var nudged = false
    /// The last call refused, and how many rounds running it came back the same.
    private var lastRefused = ""
    private var sameRefusals = 0
    /// Components the model was asked to leave out after sending one back unchanged.
    private var leftOut: Set<String> = []
    private var askedForTitle = false
    static let mostSameRefusals = 2
    static let nudge = "Try again with the tools and what is listed above: plan it step by step. Answer I can't only if no tool can do any part of it."

    /// Asks once for a title when the plan is a sheet of labelled rows with
    /// none, and says whether it asked. Also called when the model's last
    /// reply could not be read, so a sheet offered then still gets one.
    public mutating func askForTitle() -> Bool {
        guard !askedForTitle, !steps.contains(where: { $0.tool == "add_text" }),
              steps.contains(where: { $0.tool == "add_component" && $0.arguments["labels"]?.boolValue == true }) else { return false }
        askedForTitle = true
        messages.append(["role": "user", "content": .string("A sheet starts with its title: plan one add_text at the top left, the largest words on the sheet, then finish.")])
        return true
    }

    /// Tells the model a call was not planned, counted toward stopping a
    /// model that sends it back unchanged.
    private mutating func refuse(_ tool: String, _ arguments: AgentJSON, _ text: String) {
        let said = "\(tool) \(arguments.encodedString())"
        sameRefusals = said == lastRefused ? sameRefusals + 1 : 0
        lastRefused = said
        tell(tool, text)
    }

    /// A painting's sketch, painted (`BrushSketch`): every stroke one
    /// paint_stroke step, in the medium the person named.
    private mutating func paintSketch(_ arguments: AgentJSON) {
        if steps.contains(where: { $0.tool == "paint_stroke" }), steps.count > 1 {
            tell("add_drawing", Self.sketchedAlready)
            return
        }
        let svg = arguments["svg"]?.stringValue ?? ""
        guard !svg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            brokenCalls += 1
            tell("add_drawing", Self.sketchFirst)
            return
        }
        let art: SVGArtwork
        switch SVGArtwork.parse(svg) {
        case .success(let read): art = read
        case .failure(let failure):
            brokenCalls += 1
            tell("add_drawing", "Not planned. \(failure.message) Send the sketch again as one complete SVG.")
            return
        }
        let canvas = CGSize(width: canvasWidth > 0 ? canvasWidth : 960, height: canvasHeight > 0 ? canvasHeight : 640)
        let medium = BrushSketch.medium(in: request)
        let calls = BrushSketch.calls(BrushSketch.strokes(art, canvas: canvas, medium: medium), medium: medium)
        guard !calls.isEmpty else {
            brokenCalls += 1
            tell("add_drawing", "Not planned: that sketch has no filled shapes to paint. Send it again with a fill on every shape.")
            return
        }
        let first = steps.count + 1
        steps += calls.map { AskStep(tool: "paint_stroke", arguments: $0) }
        sameRefusals = 0
        lastRefused = ""
        tell("add_drawing", "Planned as steps \(first) to \(steps.count): your sketch painted in \(calls.count) strokes of \(medium.title.lowercased()). \(Self.afterSketch)")
    }

    public static let sketchFirst = "Not planned: a painting starts from your sketch. Call add_drawing once with svg, the whole picture as one SVG of filled shapes over the whole canvas, and Photonz paints it with the Brush."
    public static let sketchedAlready = "Not planned: the sketch is already painted. Add a few small paint_stroke details, or finish."
    static let afterSketch = "Add at most a few small paint_stroke strokes of detail or light where the picture needs them, or finish."

    private mutating func tell(_ tool: String, _ text: String) {
        messages.append(["role": "tool", "tool_name": .string(tool), "content": .string(text)])
    }

    private static func arguments(_ json: AgentJSON?) -> AgentJSON {
        // Some servers hand arguments over as a JSON string.
        if let text = json?.stringValue, let parsed = try? AgentJSON.parse(Data(text.utf8)) { return parsed }
        return json ?? .object([:])
    }

    static func withoutThinking(_ text: String) -> String {
        guard let end = text.range(of: "</think>") else { return text }
        return String(text[end.upperBound...])
    }

    /// Calls a model wrote out as text (`{"name": …, "arguments": {…}}`,
    /// with or without `<tool_call>` tags) instead of as tool calls.
    static func callsWritten(in text: String) -> [(String, AgentJSON)] {
        var found: [(String, AgentJSON)] = []
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{") {
            var depth = 0
            var inString = false
            var escaped = false
            var close: Substring.Index?
            for index in rest[open...].indices {
                let character = rest[index]
                if inString {
                    if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { inString = false }
                    continue
                }
                if character == "\"" { inString = true }
                if character == "{" { depth += 1 }
                if character == "}" {
                    depth -= 1
                    if depth == 0 { close = index; break }
                }
            }
            guard let close else { break }
            let piece = rest[open...close]
            if let json = try? AgentJSON.parse(Data(piece.utf8)), let name = json["name"]?.stringValue {
                found.append((name, arguments(json["arguments"] ?? json["parameters"])))
            }
            rest = rest[rest.index(after: close)...]
        }
        return found
    }

    /// What the model is told before the person's request.
    static func instructions(documentRead: String, paints: Bool = false, painting: Bool = false) -> String {
        let drawingRules = painting ? Self.brushRules : paints ? Self.paintingRules : Self.drawingRules
        return """
        You are Ask, the helper inside Photonz, a Mac picture and video editor. The person typed \
        a request about the document in front of them. Turn it into a plan of tool calls on that document.
        - Looking tools (\(AskTools.looking(painting: painting).joined(separator: ", "))) answer right away. Use them when you need facts.
        - Editing tools are NOT run now. Each call is written into a plan that runs when you finish, and is \
        answered "Planned as step N". Call them in the order they should run, with every argument filled \
        in. To name the layer, clip or title a planned step makes, write "$N" where its id goes.
        - Coordinates are points from the top left of the canvas. Keep everything inside the canvas, \
        lined up on an 8 point grid, using the document's own styles and components when it has them.
        - To measure or redline a screenshot ("annotate with measurements", "measure the major \
        elements", "spec this"), call find_measurements, then mark_measurements once with the ids \
        that answer the request: all of them for a general request, only those whose what or role \
        matches when the person names particular things (just the buttons, only the spacing). Never \
        place those yourself. When it lists nothing, or nothing that matches what was named, call \
        find_elements and add_measurement for what was asked.
        - To check a screenshot for what is inconsistent (misalignments, uneven spacing or gaps, padding \
        or borders that differ, "check the spacing", "what is inconsistent here"), call find_misalignments, \
        then mark_misalignments once with the ids of every finding worth showing. Never measure them \
        yourself. When it finds nothing, call no editing tool and say so in one short sentence.
        - To point something out with a labelled arrow ("call out the save button", "mark this as \
        wrong"), use add_shape with shape arrow, the words in caption, and its chip and marker: \
        marker error for a problem, warning for a concern, success for what is right, info for a \
        note; a chip that suits the picture (paper or hairline on a busy or dark screenshot, solid \
        otherwise). The head goes on the thing, the tail where the label has room.
        \(drawingRules)
        - "On brand" means the document's saved styles and its own components, both listed \
        below. Use them: place its components rather than drawing look-alikes, and paint with the saved styles. \
        An empty canvas is a place to build, not a reason to refuse.
        \(Self.componentRules)
        - On a video, times are seconds on the video's clock. add_title with clip puts a title page in \
        front of that clip.
        - Plan only what was asked. When the plan is complete, answer with one short sentence saying \
        what it will do, and call no more tools.
        - If the request cannot be done with these tools, call no editing tools and answer with one \
        short plain sentence that starts "I can't".
        The document now (read_document):
        \(documentRead)
        """
    }

    /// How to make components, a kit or a design system. Which kinds a kit
    /// holds and how each looks is the model's own knowledge of real kits: no
    /// list of them is written here or anywhere in the app (the user,
    /// 2026-10-20: "i don't want a hardcoded anything").
    static let componentRules = """
        - Asked for components, base components, controls, a UI kit or a design system, make each one \
        yourself with add_component, never by placing the Library's starters. Think of the real design kit \
        for the platform asked for (Apple's when none is named) and make the kinds of control it is built \
        from: a set of base components is a dozen kinds or more. Give each the looks that kit shows for it (its states: \
        default, hover, pressed, disabled, on and off, selected, focused, as that kind has them), the first \
        look as parts and every other look as only what changes. Make them look like the kit: the system \
        font at one small type scale, the platform's own light-appearance colours put straight on the parts (save no styles \
        unless asked), one corner radius per kind, padding on the 8 point grid, words centred in their control.
        - Shown as a table or sheet: first a title with add_text at the top left, the largest words on \
        the sheet; then one row per component, each add_component with labels true, the same x for \
        every component and each row's y below the last. Photonz lays the labelled rows out as one table \
        (the names down the left, each state named once over its column, every look in its cell, the canvas \
        grown when it needs more room), so set no labels or headers yourself. Only kinds with the same states \
        share a header row: give every kind that has them the same state names. Place no starters on it.
        """

    /// How to paint with the Brush (`docs/design/brushes.md`, decision 8):
    /// a painter's general way of working, which holds for any subject. The
    /// model decides what the strokes are; the engine makes them look like
    /// paint. Nothing here names a subject.
    static let brushRules = """
        - This request is a painting: paint it with the Brush, from a sketch. First call add_drawing once with \
        subject and svg: your sketch of the whole picture as one complete SVG whose viewBox is the canvas \
        ("0 0 width height" from the document below), made of filled shapes only. Photonz paints every shape \
        of it with brush strokes in the medium asked for, back to front, so the sketch is the painting's plan: \
        never add_photo, add_shape or add_path.
        - Sketch it the way a painter plans a picture. First shapes that cover the whole canvas to every edge \
        with no gap between them: the sky or the wall at the back, then the ground or the water, each its own \
        shape (a gradient for a sky is good). Then what is far away, then the middle, then what is near, last \
        the small things; later shapes sit on top of earlier ones. Make the subject asked for big and plain to \
        see, every thing in it the shape it really has (a peak is a point, a hull is long and curved, a tree is \
        a trunk under a crown), and give each big thing a lit side and a shadow side as two shapes of close colours. \
        Draw every edge the way it really runs, with many points and curves (a ridge rises and falls unevenly, a \
        shore wanders, a crown is lumpy), never a plain triangle, rectangle or circle unless the thing is one. \
        Put in the things that make the place read at a glance, each a few shapes, and vary their sizes. \
        Strong, true colours with real darks: darker and cooler away from the light, lighter and warmer toward \
        it, greyer and paler in the distance. A line (stroke, no fill) only for thin things such as a mast, a \
        branch or a rope. No words, no outlines around shapes.
        - After the sketch is painted you may add a few small paint_stroke strokes of detail or light (medium, \
        color, settings.size, and path: x,y pairs with spaces, such as 40,60 300,52), then finish.
        """

    /// How to draw when there is no picture model: the model's own svg.
    static let drawingRules = """
        - To draw anything (a thing, an animal, a scene: a dog, a coffee cup, a smiley face, the sun over \
        mountains), call add_drawing once with its subject, icon true when an icon was asked for, style set to \
        the look asked for when one was named, and svg, your own drawing as one complete SVG: a viewBox, \
        a few flat colours, curves where the thing is round, a lit side and a shadow side on each big form, every \
        part touching the part it belongs to. Never build a drawing from add_shape or add_path, and put no words, \
        components or backdrop on it unless they were asked for.
        """

    /// How to draw when the picture model paints every drawing.
    static let paintingRules = """
        - To draw anything (a thing, an animal, a pose, a scene, a named style: a dog, a horse rearing \
        up, an owl reading a book, a lighthouse on a cliff at dusk), call add_drawing once with subject \
        set to the whole of what to draw in the person's words: what it is, what it is doing, where, and \
        style set to the look asked for (line art, silhouette, watercolor, flat), or leave style out when \
        none was named, and scene true when it is a place or a scene with its own sky or ground (a \
        landscape, a skyline, a forest at dusk). Photonz paints it itself and turns it into layers; send no svg. Never build a \
        drawing from add_shape or add_path, and put no words, components or backdrop on it unless they \
        were asked for. A request with two or more things, or one thing in a pose, an action or a view, is ONE \
        add_drawing of the whole picture, never one per thing.
        - A photo (a photo, a photograph, photorealistic, realistic) is add_photo, once, with subject set to the \
        whole of what it shows in the person's words: what it is, what it is doing, where, the light. It is painted \
        as one real photograph filling the picture, or the frame given. A drawing, vector art, an icon, a logo or an \
        illustration is add_drawing. When the request says neither, pick: add_photo for a real place, animal, \
        person or moment as a camera would see it, add_drawing for a thing to design with (an icon, a symbol, \
        a mascot, a sticker).
        - When the request names more than the thing, give add_drawing a plan: one to four short statements, \
        each one someone looking at the picture can answer yes or no, for exactly what the request names: each \
        pose, action, view, mood and relationship ("a horse rearing up": it stands on its hind legs; its \
        front hooves are in the air). When two things act together, say which parts touch and what is in front \
        ("its hand grips the umbrella's handle"). For a view the request names, say what the eye sees, \
        not the word for it: which sides show and which do not ("a house seen from above": we see its whole \
        roof from straight above; no walls show). Nothing the request did not ask for: no statement about where it sits in the \
        picture, how big it is on the canvas, or a detail nobody named. A plain thing ("a dog") has no plan.
        """
}

/// What `find_elements` finds, made easy for a small model to read: each box
/// labelled by what its shape says it is, the controls a person uses first,
/// and a box listed by two readers kept once. The boxes are untouched.
public enum AskElements {

    public static func sorted(_ answer: String, canvasWidth: Double) -> String {
        guard var json = (try? AgentJSON.parse(Data(answer.utf8)))?.objectValue,
              let elements = json["elements"]?.arrayValue else { return answer }
        var kept: [(CGRect, AgentJSON)] = []
        for element in elements {
            guard let x = element["x"]?.doubleValue, let y = element["y"]?.doubleValue,
                  let w = element["width"]?.doubleValue, let h = element["height"]?.doubleValue else { continue }
            let box = CGRect(x: x, y: y, width: w, height: h)
            if kept.contains(where: { near($0.0, box) }) { continue }
            var labelled = element.objectValue ?? [:]
            labelled["looksLike"] = .string(looks(box, canvasWidth: canvasWidth))
            kept.append((box, .object(labelled)))
        }
        let order = ["control", "card", "row", "strip"]
        let listed = kept.enumerated().sorted { a, b in
            let ra = order.firstIndex(of: a.element.1["looksLike"]?.stringValue ?? "") ?? 9
            let rb = order.firstIndex(of: b.element.1["looksLike"]?.stringValue ?? "") ?? 9
            return (ra, a.offset) < (rb, b.offset)
        }.map(\.element.1)
        json["elements"] = .array(listed)
        json["count"] = .number(Double(listed.count))
        return AgentJSON.object(json).encodedString()
    }

    static func looks(_ box: CGRect, canvasWidth: Double) -> String {
        let thin = min(box.width, box.height)
        if thin < 16 { return "strip" }
        if box.width > canvasWidth * 0.5 { return box.height >= 150 ? "card" : "row" }
        if max(box.width, box.height) / thin > 10 { return "strip" }
        if box.height > 160 { return "card" }
        return "control"
    }

    /// The same box give or take a few points.
    static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 4 && abs(a.minY - b.minY) <= 4
            && abs(a.width - b.width) <= 8 && abs(a.height - b.height) <= 8
    }
}

/// Ask looking at a drawing it made before it hands back (`docs/design/ask.md`,
/// "Drawing a thing"): the drawing is shown to a model on this Mac that can
/// see, with no hint of what was asked, and what it names is checked against
/// what was asked. A drawing that does not read is drawn again, twice at most.
public enum AskDrawingCheck {

    /// How many times a drawing that did not read is drawn again.
    public static let mostRevisions = 2

    /// The plan's drawings: which step, what it was asked to be, and the
    /// statements the picture has to bear out.
    public static func drawings(in plan: AskPlan) -> [(step: Int, subject: String, plan: [String])] {
        plan.steps.enumerated().compactMap { index, step in
            guard step.tool == "add_drawing", let subject = step.arguments["subject"]?.stringValue else { return nil }
            return (index + 1, subject, AgentDrawingCall.statements(step.arguments["plan"]))
        }
    }

    /// The drawings the model sent with no plan. A plan is optional in the
    /// tool, and the model built into Photonz leaves it out even for a pose or
    /// a scene, so each of these is asked for its plan on its own
    /// (`planningBody`) before it is painted.
    public static func unplanned(in plan: AskPlan) -> [(step: Int, subject: String)] {
        drawings(in: plan).filter { $0.plan.isEmpty }.map { ($0.step, $0.subject) }
    }

    /// The planning model asked, statement by statement, whether the person's
    /// words ask for it. Asked to plan only what the words name, the model
    /// built into Photonz still adds details ("an angry bird": its body is
    /// round and red, it has a black beak), and every one the painting misses
    /// paints the picture again for nothing anybody asked; on 2026-10-23 every
    /// try painted again on one climb run was for such a detail.
    public static func groundingBody(model: String, request: String, plan: [String]) -> AgentJSON {
        let listed = plan.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let question = """
        Someone asked for: "\(request)".
        These statements were written about the picture:
        \(listed)
        For each statement, answer yes if those words ask for it: a pose, action, view, mood or relationship \
        the words name, or what that plainly takes (someone playing a guitar has their hands on it). Answer no \
        if it adds a colour, shape, part, place or detail the words do not name.
        Answer with one line per statement and nothing else, like: 1 yes
        """
        return ["model": .string(model), "stream": false, "think": false, "keep_alive": "30m",
                "options": ["temperature": 0, "num_ctx": .number(Double(AskConversation.contextWindow))],
                "messages": [["role": "user", "content": .string(question)]]]
    }

    /// The statements the words ask for: those the answer says no to are
    /// dropped, and a line it cannot read keeps its statement.
    public static func grounded(_ plan: [String], answer: String) -> [String] {
        let dropped = unmet(answer, plan: plan)
        return plan.filter { !dropped.contains($0) }
    }

    /// A plan drawn again with each drawing given the plan the first try's
    /// drawing in the same place was checked against (`carried`, in drawing
    /// order). The model rewords the subject when it draws again and leaves
    /// the plan out or rewrites it, and a plan asked afresh of the reworded
    /// subject grows details nobody asked for, each one a reason to draw
    /// again; the request's own plan is the bar every try is held to. A
    /// drawing whose first plan was none (a plain thing) is left as sent.
    /// Nil when the plan has a different number of drawings, so each is
    /// asked for afresh.
    public static func carryingPlans(_ carried: [[String]], into plan: AskPlan) -> AskPlan? {
        let drawn = drawings(in: plan)
        guard drawn.count == carried.count else { return nil }
        return zip(drawn, carried).reduce(plan) { $0.settingDrawingPlan(step: $1.0.step, to: $1.1) }
    }

    /// How close a try at drawing came: whether each drawing read as the
    /// thing asked for, and how many statements of its plan it did not show.
    public struct Attempt: Sendable, Equatable {
        public var reads: Bool
        public var missed: Int
        public init(reads: Bool, missed: Int) {
            self.reads = reads
            self.missed = missed
        }
    }

    /// Whether `attempt` came closer than `held`: one that reads beats one
    /// that does not, fewer statements missed beats more, and a tie goes to
    /// the later try, drawn with the misses named. A try that does not read
    /// is never kept.
    public static func isCloser(_ attempt: Attempt, than held: Attempt?) -> Bool {
        guard attempt.reads else { return false }
        guard let held, held.reads else { return true }
        return attempt.missed <= held.missed
    }

    /// The planning model asked for one drawing's plan, the same rules the
    /// instructions give it, and "none" for a plain thing.
    public static func planningBody(model: String, subject: String) -> AgentJSON {
        let question = """
        A picture is about to be drawn of: "\(subject)".
        Write what has to be true of the picture for it to show exactly that: one to four short statements, \
        each one someone looking at the picture can answer yes or no, for each pose, action, view, mood and \
        relationship those words name ("a horse rearing up": it stands on its hind legs; its front hooves are \
        in the air). When two things act together, say which parts touch and what is in front ("its hand grips \
        the umbrella's handle"). For a view, say what the eye sees, not the word for it: which sides show and \
        which do not. Nothing the words do not ask for: no statement about where it sits in the picture, how \
        big it is, or a detail nobody named.
        If the words name only a thing, with no pose, action, view, mood or relationship ("a dog"), answer none.
        Answer with one statement per line and nothing else.
        """
        return ["model": .string(model), "stream": false, "think": false, "keep_alive": "30m",
                "options": ["temperature": 0, "num_ctx": .number(Double(AskConversation.contextWindow))],
                "messages": [["role": "user", "content": .string(question)]]]
    }

    /// The statements in the planning model's answer: one per line, with any
    /// numbering or bullet and the closing full stop taken off, at most four.
    /// "none" (a plain thing) is no plan.
    public static func statements(fromAnswer answer: String) -> [String] {
        let lines = AskConversation.withoutThinking(answer).split(whereSeparator: \.isNewline).map { line -> String in
            var text = Substring(line).drop { $0.isWhitespace || $0.isNumber || "-*•.)".contains($0) }
            while let last = text.last, last.isWhitespace || last == "." { text = text.dropLast() }
            return String(text)
        }.filter { !$0.isEmpty }
        if lines.count == 1, lines[0].lowercased() == "none" { return [] }
        return Array(lines.filter { $0.lowercased() != "none" }.prefix(4))
    }

    /// The model that sees asked, statement by statement, whether the drawing
    /// shows what its plan said: the picture and the statements, nothing of
    /// the request or the subject.
    public static func planBody(model: String, png: Data, plan: [String], planner: Bool = false) -> AgentJSON {
        let listed = plan.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let question = """
        Look closely at this drawing. For each statement, answer yes only if the drawing plainly shows it, \
        and no if it does not or you cannot tell.
        \(listed)
        Answer with one line per statement and nothing else, like: 1 yes
        """
        return visionBody(model: model, png: png, planner: planner, question: question)
    }

    /// The statements the answer says no to. A line it cannot read, or a
    /// number the plan does not have, is no miss: a garbled answer never
    /// throws a drawing away.
    public static func unmet(_ answer: String, plan: [String]) -> [String] {
        var missed: [Int] = []
        for line in AskConversation.withoutThinking(answer).split(whereSeparator: \.isNewline) {
            let words = line.lowercased().split { !$0.isLetter && !$0.isNumber }
            guard let number = words.first.flatMap({ Int($0) }), (1...plan.count).contains(number),
                  let verdict = words.dropFirst().first else { continue }
            if verdict == "no", !missed.contains(number) { missed.append(number) }
        }
        return missed.sorted().map { plan[$0 - 1] }
    }

    public static let visionContextWindow = 4096

    public static let seePrompt = "What does this drawing show? Answer with just the name of the thing, in one to three words."

    /// The request to the model that sees: the picture and the question, nothing more.
    public static func visionBody(model: String, png: Data, planner: Bool = false, question: String = seePrompt) -> AgentJSON {
        let messages: AgentJSON = [["role": "user", "content": .string(question), "images": [.string(png.base64EncodedString())]]]
        // The planning model looking keeps its own window and does not think,
        // so Ollama answers from the model it already has loaded.
        if planner {
            return ["model": .string(model), "stream": false, "think": false, "keep_alive": "30m",
                    "options": ["temperature": 0, "num_ctx": .number(Double(AskConversation.contextWindow))],
                    "messages": messages]
        }
        // A small window of its own: one picture and one question. Left out,
        // Ollama loads the model at its own default, as big as 128k, which
        // pushes the planning model out of memory on every look.
        return ["model": .string(model), "stream": false, "keep_alive": "30m",
                "options": ["temperature": 0, "num_ctx": .number(Double(visionContextWindow))],
                "messages": messages]
    }

    /// Words that name no particular thing.
    static let generic: Set<String> = ["face", "thing", "object", "picture", "drawing", "shape", "icon", "symbol",
                                       "logo", "image", "illustration", "cartoon", "simple", "emoji", "vector"]

    /// True when what was seen names the thing or a word it is known by; nil
    /// when it shares no word with it, which the planning model then judges
    /// (a "puppy" is plainly a dog, a "mouse" plainly not, and a "hound" is
    /// for a model to say).
    public static func reads(_ seen: String, as subject: String) -> Bool? {
        let known = Set(stems(subject))
        let saw = Set(stems(seen)).subtracting(generic)
        return saw.isDisjoint(with: known.subtracting(generic)) ? nil : true
    }

    /// Words with a plural's s taken off, so "mountains" meets "mountain".
    static func stems(_ text: String) -> [String] {
        AgentDrawingWords.words(text).map { $0.count > 3 && $0.hasSuffix("s") && !$0.hasSuffix("ss") ? String($0.dropLast()) : $0 }
    }

    /// The planning model asked whether what was seen is the thing. Only the
    /// kind of thing: a one to three word name cannot carry a pose, an action
    /// or a place, so asking whether "Bluebird" is "a bird on a branch
    /// singing" got no and threw away a scene that showed exactly that. The
    /// pose and the setting are the plan check's (`planBody`).
    public static func judgeBody(model: String, subject: String, seen: String) -> AgentJSON {
        let question = """
        A drawing was asked to show: "\(subject)". Someone shown it, without being told what it was, named it in a \
        few words: "\(seen)". A name that short leaves out any pose, action, mood or setting, so judge only the \
        kind of thing: is what they named the main thing asked for, or a kind of it? Answer only yes or no.
        """
        // The planning model's own window, so asking it does not reload it.
        return ["model": .string(model), "stream": false, "think": false, "keep_alive": "30m",
                "options": ["temperature": 0, "num_ctx": .number(Double(AskConversation.contextWindow))],
                "messages": [["role": "user", "content": .string(question)]]]
    }

    public static func judged(_ answer: String) -> Bool {
        AskConversation.withoutThinking(answer).trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("yes")
    }

    static func revisionNote(subject: String, seen: String, paints: Bool = false, unmet: [String] = []) -> String {
        if !unmet.isEmpty {
            let listed = unmet.map { "\"\($0)\"" }.joined(separator: ", ")
            return """
            Someone who could not see this request looked closely at the drawing of \(subject). It does not show: \
            \(listed), and it was taken back. Draw it again: call add_drawing once more\(paints ? " with no svg" : " with a new svg"), \
            the same plan, and a subject that says what the eye sees in place of the word for it: which sides and \
            parts show and which do not, where the head, body and each limb are, which part touches which, what is \
            in front.
            """
        }
        if paints {
            return """
            Someone who could not see this request looked at the drawing and said it shows: "\(seen)". It has to \
            read at a glance as \(subject), and it was taken back. Draw it again: call add_drawing once more with \
            no svg, its subject saying plainly what \(subject) is and the parts that make it recognisable.
            """
        }
        return """
        Someone who could not see this request looked at the drawing and said it shows: "\(seen)". It has to read \
        at a glance as \(subject), and it was taken back. Draw it again: call add_drawing with subject \
        "\(subject)" and a new svg. Use bigger, simpler shapes and the parts that make \
        \(subject) recognisable, in the colours it really has, every part touching the part it belongs to.
        """
    }
}

/// Which model on this Mac answers Ask.
public enum AskModels {

    /// A model Ask plans well with, as the bake-off measured it
    /// (`docs/design/ask.md`, "The model"): its Ollama tag, the memory it
    /// holds while Ask uses it (with Ask's 32k window, as Ollama reports it),
    /// its download, both in GB, and whether it can see a picture.
    public struct Choice: Sendable, Equatable {
        public let tag: String
        public let gigabytes: Double
        public let download: Double
        public let sees: Bool

        public init(tag: String, gigabytes: Double, download: Double, sees: Bool) {
            self.tag = tag
            self.gigabytes = gigabytes
            self.download = download
            self.sees = sees
        }
    }

    /// Best first, by the bake-off of 2026-10-21 (M4 Max, 64 GB, Ollama
    /// 0.40.7): the held-out score among the models that answer in under 30
    /// seconds a request, then smaller models for Macs with less memory.
    public static let ranked: [Choice] = [
        Choice(tag: "qwen3.6:27b", gigabytes: 29.9, download: 18, sees: true),
        Choice(tag: "qwen3.6:35b", gigabytes: 32.7, download: 23, sees: true),
        Choice(tag: "gemma4:26b", gigabytes: 25.7, download: 16, sees: true),
        Choice(tag: "qwen3:30b", gigabytes: 21.9, download: 18.6, sees: false),
        Choice(tag: "gemma4:e4b", gigabytes: 18.6, download: 9.5, sees: true),
        Choice(tag: "gemma4:12b", gigabytes: 17.3, download: 7.7, sees: true),
    ]

    /// The most of the Mac's memory a model may hold, so macOS, Photonz and a
    /// browser keep the rest.
    public static let memoryShare = 0.6

    public static func fits(_ choice: Choice, memoryGigabytes: Double) -> Bool {
        choice.gigabytes <= memoryGigabytes * memoryShare
    }

    /// The Mac's memory in GB, for the rule above.
    public static func gigabytes(ofMemory bytes: UInt64) -> Double { Double(bytes) / 1e9 }

    /// Models that can see, best first, for Ask's look at a drawing when the
    /// planning model cannot.
    public static let preferredVision = ["llama3.2-vision:latest", "llama3.2-vision", "llama3.2-vision:11b",
                                         "qwen2.5vl:7b", "gemma3:12b", "gemma3:27b", "llava:latest"]

    /// The model that looks at a drawing: the planning model itself when it
    /// can see (one model loaded, not two), else the first on the Mac that
    /// can, else nil (Ask then hands back without looking).
    public static func eyes(planner: String, plannerSees: Bool, installed: [String]) -> String? {
        if plannerSees { return planner }
        return preferredVision.first { installed.contains($0) }
    }

    /// The best measured model the Mac already has and can hold, or nil when
    /// it has none.
    public static func automatic(installed: [String], memoryGigabytes: Double) -> String? {
        ranked.first { installed.contains($0.tag) && fits($0, memoryGigabytes: memoryGigabytes) }?.tag
    }

    /// What a Mac with none of them is offered to download: the best it can hold.
    public static func recommended(memoryGigabytes: Double) -> Choice? {
        ranked.first { fits($0, memoryGigabytes: memoryGigabytes) }
    }

    /// The model chosen in Settings while it is still on the Mac, else automatic.
    public static func resolve(chosen: String?, installed: [String], memoryGigabytes: Double) -> String? {
        if let chosen, installed.contains(chosen) { return chosen }
        return automatic(installed: installed, memoryGigabytes: memoryGigabytes)
    }
}
