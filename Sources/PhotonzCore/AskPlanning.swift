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
        "read_document", "find_elements", "list_components", "list_styles", "list_titles",
        "recommended_zooms", "list_commands",
    ]

    /// Edits: written into the plan, run once it is complete. Nothing here opens a
    /// window, writes a file or steps the history, so the whole plan lands in
    /// the asking document's own undo history as one step.
    public static let doing: [String] = [
        "add_drawing", "add_shape", "add_path", "add_text", "set_layer", "add_measurement", "place_component",
        "add_style", "apply_style", "set_layout", "run_command",
        "add_title", "cut", "trim", "move_clip", "set_transition", "apply_zooms",
    ]

    /// The tools in the shape Ollama's chat API takes them. `document` is left
    /// out (Ask always works on the document it was opened over), and a
    /// property given as a choice of types shows its first, since some model
    /// templates cannot read a property with no type. The real schema still
    /// checks every call.
    public static let modelTools: [AgentJSON] = (looking + doing).compactMap { name in
        guard let tool = AgentTools.tool(named: name) else { return nil }
        return ["type": "function",
                "function": ["name": .string(tool.name), "description": .string(tool.description),
                             "parameters": modelSchema(tool.inputSchema, top: true)]]
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
    /// What list_components named each id.
    public private(set) var names: [String: String] = [:]
    /// How many times the model has been asked; the app stops at `mostRounds`.
    public private(set) var rounds = 0
    public static let mostRounds = 12
    /// More readouts than this crowd a screenshot past reading.
    public static let mostMeasurements = 12
    public static let contextWindow = 32768

    /// The canvas's width, read from the document, for sorting what
    /// `find_elements` finds.
    private let canvasWidth: Double

    /// `components` and `styles` are list_components' and list_styles'
    /// answers, handed over up front so "on brand" never starts from nothing.
    /// The built-in drawings add_drawing draws from, so a thing the set does
    /// not have goes back to the model for its own SVG while it still plans.
    private let drawings: DrawingLibrary?
    /// What the person typed, read for the look they named.
    private let request: String

    public init(request: String, documentRead: String, components: String = "", styles: String = "",
                titles: String = "", drawings: DrawingLibrary? = nil) {
        self.drawings = drawings
        self.request = request
        canvasWidth = (try? AgentJSON.parse(Data(documentRead.utf8)))?["canvas"]?["width"]?.doubleValue ?? 0
        var instructions = Self.instructions(documentRead: documentRead)
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
        ["model": .string(model), "messages": .array(messages), "tools": .array(AskTools.modelTools),
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
        if calls.isEmpty { calls = Self.callsWritten(in: content) }
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
            return .planned(AskPlan(steps: steps, summary: sentence, names: names))
        }
        var looks: [AskLook] = []
        for (name, arguments) in calls {
            if AskTools.looking.contains(name) {
                looks.append(AskLook(tool: name, arguments: arguments))
            } else if AskTools.doing.contains(name) {
                var step = AskStep(tool: name, arguments: arguments)
                if name == "add_measurement",
                   steps.filter({ $0.tool == "add_measurement" }).count >= Self.mostMeasurements {
                    tell(name, "Not planned: \(Self.mostMeasurements) measurements is the most a picture reads well with. Plan nothing more of them; finish.")
                    continue
                }
                let arguments = name == "add_drawing" ? Self.withStyleWords(arguments, from: request) : arguments
                if name == "add_drawing", let problem = drawingProblem(arguments) {
                    tell(name, "Not planned. \(problem)")
                    continue
                }
                if name == "add_drawing" {
                    step = AskStep(tool: name, arguments: Self.withStyleWords(arguments, from: request))
                }
                if let earlier = repeated(step) {
                    tell(name, "Not planned: step \(earlier) already does that. Plan something else, or finish.")
                    continue
                }
                // Checked as it would run, with $N standing in for ids not made yet.
                switch AgentTools.request(tool: name, arguments: arguments) {
                case .success:
                    steps.append(step)
                    tell(name, "Planned as step \(steps.count). Refer to what it makes as $\(steps.count).")
                case .failure(let failure):
                    tell(name, "Not planned. \(failure.message)")
                }
            } else {
                tell(name, "\(name) is not one of your tools here. Use only the tools you were given.")
            }
        }
        return .again(looks: looks)
    }

    /// Why an add_drawing call cannot draw, or nil when it can: a thing the
    /// set has not got needs the model's own SVG, and that SVG has to read.
    func drawingProblem(_ arguments: AgentJSON) -> String? {
        let subject = arguments["subject"]?.stringValue ?? ""
        let builtIn = arguments["builtIn"]?.boolValue ?? true
        let svg = arguments["svg"]?.stringValue ?? ""
        let styled = Self.withStyleWords(arguments, from: request)
        if IllustrationBrief.make(subject: subject, style: styled["style"]?.stringValue,
                                  icon: arguments["icon"]?.boolValue ?? false) != nil { return nil }
        if builtIn, let drawings, drawings.match(subject) != nil { return nil }
        guard !svg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return drawings == nil ? nil : AgentDrawingCall.noBuiltIn(subject)
        }
        if case .failure(let trouble) = SVGArtwork.parse(svg) {
            return "add_drawing: \(trouble.message) Write the whole svg again."
        }
        return nil
    }

    /// An add_drawing call with the look words the person typed added to its
    /// style, so "as line art" or "a badge" reaches the illustrator even when
    /// the model left it out.
    static func withStyleWords(_ arguments: AgentJSON, from request: String) -> AgentJSON {
        var typed = IllustrationBrief.lookWords(in: request)
        guard var object = arguments.objectValue else { return arguments }
        let subject = object["subject"]?.stringValue ?? ""
        // What else the person put in the scene ("with pines"), when the
        // subject is a scene the model shortened.
        if IllustrationBrief.make(subject: subject, style: nil) != nil {
            let named = Set(IllustrationBrief.words(subject))
            typed += IllustrationBrief.sceneWords(in: request).filter { !named.contains($0) }
        }
        // A badge is not an icon: a scene stays an illustration unless the
        // person said icon.
        if object["icon"]?.boolValue == true, !IllustrationBrief.words(request).contains("icon"),
           IllustrationBrief.make(subject: subject, style: (object["style"]?.stringValue ?? "") + " " + typed.joined(separator: " ")) != nil {
            object["icon"] = nil
        }
        if typed.isEmpty, object["style"] != nil,
           IllustrationBrief.make(subject: subject, style: nil, icon: object["icon"]?.boolValue ?? false) == nil {
            // A look the person never asked for, on a thing that is no scene
            // ("a picture of a bird"), is the model's guess: the thing stays a thing.
            object["style"] = nil
            return .object(object)
        }
        guard !typed.isEmpty else { return .object(object) }
        let given = object["style"]?.stringValue ?? ""
        let missing = typed.filter { !given.lowercased().contains($0) }
        guard !missing.isEmpty else { return arguments }
        object["style"] = .string(([given] + missing).filter { !$0.isEmpty }.joined(separator: " "))
        return .object(object)
    }

    /// The drawing did not read as `subject` to a model that could see it
    /// (`AskDrawingCheck`): the plan starts again, told what was seen.
    public mutating func revise(subject: String, seen: String) {
        steps = []
        rounds = 0
        messages.append(["role": "user", "content": .string(AskDrawingCheck.revisionNote(subject: subject, seen: seen))])
    }

    /// The step already planned that this one repeats: the same call, or a
    /// size measurement of what is the same box give or take a few points
    /// (`find_elements` lists one control by several readers).
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
    static let nudge = "Try again with the tools and what is listed above: plan it step by step. Answer I can't only if no tool can do any part of it."

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
    static func instructions(documentRead: String) -> String {
        """
        You are Ask, the helper inside Photonz, a Mac picture and video editor. The person typed \
        a request about the document in front of them. Turn it into a plan of tool calls on that document.
        - Looking tools (\(AskTools.looking.joined(separator: ", "))) answer right away. Use them when you need facts.
        - Editing tools are NOT run now. Each call is written into a plan that runs when you finish, and is \
        answered "Planned as step N". Call them in the order they should run, with every argument filled \
        in. To name the layer, clip or title a planned step makes, write "$N" where its id goes.
        - Coordinates are points from the top left of the canvas. Keep everything inside the canvas, \
        lined up on an 8 point grid, using the document's own styles and components when it has them.
        - To measure a screenshot, call find_elements. Each box says what it looksLike, controls \
        first. The major elements are the controls (switches, fields, buttons), each measured once, \
        plus at most two cards. Skip rows and strips. Add a gap between a \
        few neighbouring controls. 6 to 12 measurements in all, never the same box twice.
        - To draw a thing (a dog, a house, a coffee cup, a smiley face), call \
        add_drawing once with its subject, and icon true when an icon was asked for. Photonz has clean drawings \
        of about a thousand everyday things; when it has none of yours it says so, and you call add_drawing \
        again with svg, your own drawing as one complete SVG. Never build a drawing from add_shape or add_path, \
        and put no words, components or backdrop on it unless they were asked for.
        - To draw an illustration or a scene (the sun over mountains, a forest at dusk, a lighthouse on a cliff, \
        a city skyline, a fox in its setting), call add_drawing once with the scene as its subject and style \
        set to the look asked for (line art, silhouette, badge, sunset, flat), or "illustration" when none \
        was named. Photonz draws it itself; send no svg.
        - "On brand" means the document's saved styles and the Library's components, both listed \
        below (the Library always offers starters such as a Card and a Button). Use them: place \
        components rather than drawing look-alikes, and paint with the saved styles. An empty canvas is a place to build, not a reason to refuse.
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

    /// The plan's drawings: which step, and what it was asked to be.
    public static func drawings(in plan: AskPlan, library: DrawingLibrary? = nil) -> [(step: Int, subject: String)] {
        plan.steps.enumerated().compactMap { index, step in
            guard step.tool == "add_drawing", let subject = step.arguments["subject"]?.stringValue else { return nil }
            // An illustration is the illustrator's, checked by its own
            // critique pass; it is never taken back for the model's own svg.
            if IllustrationBrief.make(subject: subject, style: step.arguments["style"]?.stringValue,
                                      icon: step.arguments["icon"]?.boolValue ?? false) != nil { return nil }
            // A drawing from the built-in set is known to read; a small model
            // misreading it ("a mushroom" for the tree) must not swap it for
            // the planning model's own svg.
            if step.arguments["builtIn"]?.boolValue != false, let library, library.match(subject) != nil { return nil }
            return (index + 1, subject)
        }
    }

    public static let visionContextWindow = 4096

    public static let seePrompt = "What does this drawing show? Answer with just the name of the thing, in one to three words."

    /// The request to the model that sees: the picture and the question, nothing more.
    public static func visionBody(model: String, png: Data) -> AgentJSON {
        // A small window of its own: one picture and one question. Left out,
        // Ollama loads the model at its own default, as big as 128k, which
        // pushes the planning model out of memory on every look.
        ["model": .string(model), "stream": false, "keep_alive": "30m",
         "options": ["temperature": 0, "num_ctx": .number(Double(visionContextWindow))],
         "messages": [["role": "user", "content": .string(seePrompt), "images": [.string(png.base64EncodedString())]]]]
    }

    /// Words that name no particular thing.
    static let generic: Set<String> = ["face", "thing", "object", "picture", "drawing", "shape", "icon", "symbol",
                                       "logo", "image", "illustration", "cartoon", "simple", "emoji", "vector"]

    /// True when what was seen names the thing or a word it is known by; nil
    /// when it shares no word with it, which the planning model then judges
    /// (a "puppy" is plainly a dog, a "mouse" plainly not, and a "hound" is
    /// for a model to say).
    public static func reads(_ seen: String, as subject: String, library: DrawingLibrary?) -> Bool? {
        var known = Set(DrawingLibrary.words(subject))
        if let entry = library?.match(subject) {
            for label in [entry.name] + entry.aliases + entry.words { known.formUnion(DrawingLibrary.words(label)) }
        }
        let saw = Set(DrawingLibrary.words(seen)).subtracting(generic)
        return saw.isDisjoint(with: known.subtracting(generic)) ? nil : true
    }

    /// The planning model asked whether what was seen is the thing.
    public static func judgeBody(model: String, subject: String, seen: String) -> AgentJSON {
        let question = "Someone was shown a drawing and said it shows: \"\(seen)\". Would most people say it is a drawing of \(subject)? Answer only yes or no."
        // The planning model's own window, so asking it does not reload it.
        return ["model": .string(model), "stream": false, "think": false, "keep_alive": "30m",
                "options": ["temperature": 0, "num_ctx": .number(Double(AskConversation.contextWindow))],
                "messages": [["role": "user", "content": .string(question)]]]
    }

    public static func judged(_ answer: String) -> Bool {
        AskConversation.withoutThinking(answer).trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("yes")
    }

    static func revisionNote(subject: String, seen: String) -> String {
        """
        Someone who could not see this request looked at the drawing and said it shows: "\(seen)". It has to read \
        at a glance as \(subject), and it was taken back. Draw it again: call add_drawing with subject \
        "\(subject)", builtIn false, and a new svg. Use bigger, simpler shapes and the parts that make \
        \(subject) recognisable, in the colours it really has, every part touching the part it belongs to.
        """
    }
}

/// Which model on this Mac answers Ask.
public enum AskModels {

    /// Models that can see, best first, for Ask's look at a drawing.
    public static let preferredVision = ["llama3.2-vision:latest", "llama3.2-vision", "llama3.2-vision:11b",
                                         "qwen2.5vl:7b", "gemma3:12b", "gemma3:27b", "llava:latest"]

    /// The first model on the Mac that can see, or nil (Ask then hands back
    /// without looking).
    public static func vision(installed: [String]) -> String? {
        preferredVision.first { installed.contains($0) }
    }

    /// The default, measured on the user's three try paths (`docs/design/ask.md`):
    /// the first of these the Mac has, in order.
    public static let preferred = ["qwen3:30b", "qwen3:32b", "qwen3:14b", "qwen3:8b"]

    /// What a Mac with none of them would download: the measured default.
    public static let recommended = "qwen3:30b"
    /// Its download, as Ollama lists it, for the one-time setup to say up front.
    public static let recommendedGigabytes = 18.6

    /// The best model the Mac already has, or nil when it has none that plans well.
    public static func automatic(installed: [String]) -> String? {
        preferred.first { installed.contains($0) }
    }

    /// The model chosen in Settings while it is still on the Mac, else automatic.
    public static func resolve(chosen: String?, installed: [String]) -> String? {
        if let chosen, installed.contains(chosen) { return chosen }
        return automatic(installed: installed)
    }
}
