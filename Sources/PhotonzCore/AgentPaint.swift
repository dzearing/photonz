import CoreGraphics
import Foundation

// The brushes through the agent channel (`docs/design/brushes.md`, decision 8):
// list them and their settings, pick and set the armed brush, and paint a
// stroke from points with optional pressure. A stroke from here is the same
// `BrushStroke` a person's pointer makes and lands through the same editor
// call, so it renders the same and is one undo step. The agent plans the
// strokes; the engine makes them look like paint. Nothing here draws a subject.

/// A setting's value as an agent gives it: a number, or for a choice (a
/// pencil's grade, a marker's tip) the word for it.
public enum AgentBrushValue: Hashable, Sendable {
    case number(Double)
    case choice(String)

    init?(_ json: AgentJSON) {
        if let number = json.doubleValue {
            self = .number(number)
        } else if let word = json.stringValue {
            self = .choice(word)
        } else {
            return nil
        }
    }
}

/// What an agent says about a brush: any of its medium, mode, colour and
/// settings. What it leaves out stays as the brush it changes has it.
public struct AgentBrushChange: Hashable, Sendable {
    public var medium: BrushMedium?
    public var mode: BrushMode?
    /// #RRGGBB, upper case.
    public var colorHex: String?
    /// By setting id (`BrushMedium.settings`).
    public var settings: [String: AgentBrushValue]

    public init(medium: BrushMedium? = nil, mode: BrushMode? = nil, colorHex: String? = nil,
                settings: [String: AgentBrushValue] = [:]) {
        self.medium = medium
        self.mode = mode
        self.colorHex = colorHex
        self.settings = settings
    }

    public var isEmpty: Bool { medium == nil && mode == nil && colorHex == nil && settings.isEmpty }
}

/// A stroke an agent asked for, checked: its samples in canvas points with
/// their times worked out, the brush it is painted with over the armed one,
/// and where it goes.
public struct AgentStroke: Hashable, Sendable {
    public var samples: [StrokeSample]
    public var brush: AgentBrushChange
    /// A paint layer's id to add the stroke to.
    public var layer: String?
    /// Start a new Paint layer with this stroke rather than adding to the
    /// picked one.
    public var newLayer: Bool
    public var seed: UInt32?

    public init(samples: [StrokeSample], brush: AgentBrushChange = AgentBrushChange(), layer: String? = nil,
                newLayer: Bool = false, seed: UInt32? = nil) {
        self.samples = samples
        self.brush = brush
        self.layer = layer
        self.newLayer = newLayer
        self.seed = seed
    }
}

public enum AgentPaint {

    /// How fast an agent's stroke is drawn when its points carry no times, in
    /// points a millisecond: a steady hand, under the 0.4 where a mouse's
    /// press starts to lighten (`BrushDynamics.mousePressure`), so a stroke
    /// lays the weight its Size and medium say.
    public static let handSpeed = 0.3

    /// The time between two points given in the same place: a held brush,
    /// the pointer's own rate, so an airbrush held on a point builds up.
    public static let heldStepMS = 16.0

    /// How long a hand takes to lift and come down again between strokes, in
    /// seconds.
    public static let liftSeconds = 0.25

    /// When an agent's stroke begins: now, or a lift after the stroke before
    /// it on the same layer ended, whichever is later. Strokes sent one after
    /// another land milliseconds apart, and stamped that way every wash would
    /// still be soaking when the next touched it; a person's are seconds apart.
    public static func startedAt(now: Double, after previous: BrushStroke?) -> Double {
        guard let ended = previous?.endedAt else { return now }
        return max(now, ended + liftSeconds)
    }

    /// The samples for `points`: a time for every point that has none, at a
    /// steady hand's pace from the one before; times never going back; and a
    /// pen's reading missing from some points taken from the nearest that has
    /// one, since a pen reports on every point or on none.
    static func samples(_ points: [(point: CGPoint, pressure: Double?, tilt: CGPoint?, ms: Double?)]) -> [StrokeSample] {
        let pressures = filled(points.map(\.pressure))
        let tilts = filled(points.map(\.tilt))
        var samples: [StrokeSample] = []
        for (index, given) in points.enumerated() {
            var ms = given.ms ?? 0
            if let last = samples.last {
                if given.ms == nil {
                    let distance = hypot(given.point.x - last.point.x, given.point.y - last.point.y)
                    ms = last.ms + (distance > 0 ? Double(distance) / handSpeed : heldStepMS)
                }
                ms = max(ms, last.ms)
            }
            samples.append(StrokeSample(point: given.point, pressure: pressures[index], tilt: tilts[index], ms: max(0, ms)))
        }
        return samples
    }

    private static func filled<T>(_ values: [T?]) -> [T?] {
        guard values.contains(where: { $0 != nil }) else { return values }
        return values.indices.map { index in
            if let value = values[index] { return value }
            for step in 1..<values.count {
                if index - step >= 0, let value = values[index - step] { return value }
                if index + step < values.count, let value = values[index + step] { return value }
            }
            return nil
        }
    }

    /// The brush `change` makes: over the armed brush for its own medium,
    /// over what another medium was last left at (`remembered`), each value
    /// checked against the medium's own settings.
    public static func brush(_ change: AgentBrushChange, armed: BrushSettings,
                             remembered: (BrushMedium) -> BrushSettings) -> Result<BrushSettings, AgentToolError> {
        let medium = change.medium ?? armed.medium
        var brush = medium == armed.medium ? armed : remembered(medium)
        if let mode = change.mode { brush.mode = mode }
        for id in change.settings.keys.sorted() {
            guard let given = change.settings[id] else { continue }
            guard let spec = medium.settings.first(where: { $0.id == medium.settingID(id.lowercased()) }) else {
                let ids = medium.settings.map(\.id).joined(separator: ", ")
                return .failure(AgentToolError("\(medium.title) has no setting called \(id); its settings are \(ids)."))
            }
            switch value(given, for: spec) {
            case .success(let value): brush.set(spec.id, to: value)
            case .failure(let refused): return .failure(refused)
            }
        }
        return .success(brush)
    }

    private static func value(_ given: AgentBrushValue, for spec: BrushSettingSpec) -> Result<Double, AgentToolError> {
        if let options = spec.options {
            let words = options.joined(separator: ", ")
            switch given {
            case .choice(let word):
                if let index = options.firstIndex(where: { $0.lowercased() == word.lowercased() }) {
                    return .success(Double(index))
                }
                if let number = Double(word) { return value(.number(number), for: spec) }
                return .failure(AgentToolError("\(spec.id) is \(word); it is one of \(words)."))
            case .number(let number):
                guard number.rounded() == number, options.indices.contains(Int(number)) else {
                    return .failure(AgentToolError("\(spec.id) is \(format(number)); it is one of \(words)."))
                }
                return .success(number)
            }
        }
        let number: Double
        switch given {
        case .number(let value): number = value
        case .choice(let word):
            guard let value = Double(word.trimmingCharacters(in: CharacterSet(charactersIn: " %pt"))) else {
                return .failure(AgentToolError("\(spec.id) is \(word); it is a number."))
            }
            number = value
        }
        guard number.isFinite, spec.range.contains(number) else {
            let range = "\(format(spec.range.lowerBound)) to \(format(spec.range.upperBound))"
            return .failure(AgentToolError("\(spec.id) is \(format(number)); it runs \(range)."))
        }
        return .success(number)
    }

    /// The stroke an agent's call paints: its samples, the brush it names over
    /// the armed one, the armed colour unless it names one, and its own seed
    /// when it gives one. The same value the pointer makes from the same hand.
    public static func brushStroke(_ call: AgentStroke, armed: BrushSettings, armedColorHex: String,
                                   remembered: (BrushMedium) -> BrushSettings,
                                   startedAt: Double, seed: UInt32) -> Result<BrushStroke, AgentToolError> {
        brush(call.brush, armed: armed, remembered: remembered).map { settings in
            BrushStroke(samples: call.samples, settings: settings, colorHex: call.brush.colorHex ?? armedColorHex,
                        seed: call.seed ?? seed, startedAt: startedAt)
        }
    }

    /// The points of a path written short: "x,y x,y", a third number on a
    /// pair being its pressure.
    static func path(_ text: String) -> Result<[(point: CGPoint, pressure: Double?)], AgentToolError> {
        var points: [(point: CGPoint, pressure: Double?)] = []
        for pair in text.split(whereSeparator: { $0 == " " || $0 == ";" || $0 == "\n" }) {
            let numbers = pair.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard (2...3).contains(numbers.count), numbers.allSatisfy({ $0?.isFinite == true }),
                  let x = numbers[0], let y = numbers[1] else {
                return .failure(AgentToolError("path has \(pair); write each point as x,y with spaces between points."))
            }
            let pressure = numbers.count == 3 ? numbers[2] : nil
            if let pressure, !(0...1).contains(pressure) {
                return .failure(AgentToolError("path has a pressure of \(format(pressure)); it runs 0 to 1."))
            }
            points.append((CGPoint(x: x, y: y), pressure))
        }
        return .success(points)
    }

    static func format(_ number: Double) -> String {
        number.rounded() == number ? String(Int(number)) : String(number)
    }
}

// MARK: - The listing

/// What list_brushes answers: the armed brush, then every medium with every
/// setting it has (decision 7: one list, read by the panel, the tool options,
/// MCP and the tests).
public struct AgentBrushListing: Encodable, Hashable, Sendable {

    public struct Armed: Encodable, Hashable, Sendable {
        public let medium: String
        public let mode: String
        public let color: String
        public let settings: [String: AgentBrushValue]
    }

    public struct Setting: Encodable, Hashable, Sendable {
        public let id: String
        public let name: String
        /// A number's range; nil for a choice.
        public let min: Double?
        public let max: Double?
        /// A choice's words, in order.
        public let options: [String]?
        public let defaultValue: AgentBrushValue
        /// What the medium is set to now: the armed brush, or what it was last left at.
        public let value: AgentBrushValue
        /// How the app shows it: 16 pt, 60%, HB.
        public let reading: String

        enum CodingKeys: String, CodingKey {
            case id, name, min, max, options, value, reading
            case defaultValue = "default"
        }
    }

    public struct Brush: Encodable, Hashable, Sendable {
        public let medium: String
        public let name: String
        public let settings: [Setting]
    }

    public let armed: Armed
    public let modes: [String]
    public let brushes: [Brush]

    public static func make(armed: BrushSettings, colorHex: String,
                            remembered: (BrushMedium) -> BrushSettings) -> AgentBrushListing {
        func value(_ number: Double, _ spec: BrushSettingSpec) -> AgentBrushValue {
            if let options = spec.options, options.indices.contains(Int(number.rounded())) {
                return .choice(options[Int(number.rounded())])
            }
            return .number(number)
        }
        let brushes = BrushMedium.allCases.map { medium -> Brush in
            let settings = medium == armed.medium ? armed : remembered(medium)
            return Brush(medium: medium.rawValue, name: medium.title, settings: medium.settings.map { spec in
                let now = settings.value(spec.id)
                return Setting(id: spec.id, name: spec.name,
                               min: spec.options == nil ? spec.range.lowerBound : nil,
                               max: spec.options == nil ? spec.range.upperBound : nil,
                               options: spec.options, defaultValue: value(spec.defaultValue, spec),
                               value: value(now, spec), reading: spec.reading(now))
            })
        }
        var values: [String: AgentBrushValue] = [:]
        for spec in armed.medium.settings { values[spec.id] = value(armed.value(spec.id), spec) }
        return AgentBrushListing(
            armed: Armed(medium: armed.medium.rawValue, mode: armed.mode.rawValue, color: colorHex, settings: values),
            modes: BrushMode.allCases.map(\.rawValue), brushes: brushes)
    }
}

extension AgentBrushValue: Encodable {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let number): try c.encode(number)
        case .choice(let word): try c.encode(word)
        }
    }
}

// MARK: - The tools

extension AgentTools {

    private static func paintSchema(_ properties: [String: AgentJSON], required: [String] = []) -> AgentJSON {
        var all = properties
        all["document"] = ["type": "string",
                           "description": "The document's id from list_documents, such as d1. Leave it out to use the document in front."]
        return ["type": "object", "properties": .object(all),
                "required": .array(required.map(AgentJSON.string)), "additionalProperties": false]
    }

    private static let brushProperties: [String: AgentJSON] = [
        "medium": ["type": "string", "enum": .array(BrushMedium.allCases.map { .string($0.rawValue) }),
                   "description": "pencil, charcoal, chalk, crayon, marker, airbrush, oil or watercolour."],
        "mode": ["type": "string", "enum": .array(BrushMode.allCases.map { .string($0.rawValue) }),
                 "description": "paint lays the medium down; smudge drags paint already on a paint layer like a finger."],
        "color": ["type": "string", "description": "#RRGGBB, the paint's colour."],
        "settings": ["type": "object",
                     "description": "Setting ids from list_brushes and their values: a number inside its range, or a choice by its word (a pencil's hardness 2B, a marker's tip Chisel). Size is in points, the rest 0 to 100."],
    ]

    static let paintTools: [AgentTool] = [
        AgentTool(
            name: "list_brushes",
            description: "The brushes the Brush tool paints with (pencil, charcoal, chalk, crayon, marker, airbrush, oil, watercolour), every setting each has with its range and default, and the brush in hand.",
            inputSchema: paintSchema([:])),
        AgentTool(
            name: "set_brush",
            description: "Pick and set the brush in hand, as the tool options do: its medium, paint or smudge, colour and settings. What you leave out stays; another medium starts as it was last left. Strokes already painted keep their own brush.",
            inputSchema: paintSchema(brushProperties)),
        AgentTool(
            name: "paint_stroke",
            description: "Paint one brush stroke through points in canvas points, as dragging the Brush does: a smooth curve through them, optional pen pressure. It lands on the picked paint layer or a new Paint layer above the picked layer. Brush values here are for this stroke only. One undo step.",
            inputSchema: paintSchema(brushProperties.merging([
                "points": ["type": "array", "minItems": 2,
                           "description": "Where the brush goes, in order. A click is two points in one place.",
                           "items": ["type": "object", "properties": [
                               "x": ["type": "number", "description": "Across, from the left."],
                               "y": ["type": "number", "description": "Down, from the top."],
                               "pressure": ["type": "number", "minimum": 0, "maximum": 1,
                                            "description": "How hard a pen presses, 0 to 1. Left out on every point, the stroke is a mouse's: it tapers in and out."],
                               "tilt": ["type": "object", "description": "How far a pen leans, each of x and y -1 to 1.",
                                        "properties": ["x": ["type": "number", "minimum": -1, "maximum": 1, "description": "Lean across."],
                                                       "y": ["type": "number", "minimum": -1, "maximum": 1, "description": "Lean down."]],
                                        "required": ["x", "y"], "additionalProperties": false],
                               "ms": ["type": "number", "minimum": 0,
                                      "description": "Milliseconds since the stroke began. Left out, a steady hand's pace."],
                           ], "required": ["x", "y"], "additionalProperties": false]],
                "path": ["type": "string",
                         "description": "The points written short instead of points: x,y pairs in order, spaces between them, such as 40,60 200,55 360,70. A third number on a pair is its pressure."],
                "layer": ["type": "string", "description": "A paint layer's id from read_document to add the stroke to."],
                "newLayer": ["type": "boolean", "description": "Start a new Paint layer with this stroke."],
                "seed": ["type": "integer", "minimum": 1, "maximum": .number(Double(UInt32.max)),
                         "description": "The same seed paints the same grain and bristles every time. Random when left out."],
            ]) { $1 })),
    ]

    static let paintToolNames: Set<String> = Set(paintTools.map(\.name))

    static func paintRequest(_ name: String, _ args: [String: AgentJSON],
                             document: String?) -> Result<AgentRequest, AgentToolError> {
        func fail(_ words: String) -> Result<AgentRequest, AgentToolError> { .failure(AgentToolError("\(name): \(words)")) }
        var change = AgentBrushChange()
        change.medium = args["medium"]?.stringValue.flatMap(BrushMedium.init(rawValue:))
        change.mode = args["mode"]?.stringValue.flatMap(BrushMode.init(rawValue:))
        if let word = args["color"]?.stringValue {
            guard case .hex(let hex)? = AgentInk(word), hex.count == 7 else {
                return fail("color is \(word); give #RRGGBB.")
            }
            change.colorHex = hex
        }
        for (id, json) in args["settings"]?.objectValue ?? [:] {
            guard let value = AgentBrushValue(json) else { return fail("settings.\(id) should be a number or a word.") }
            change.settings[id] = value
        }
        switch name {
        case "list_brushes":
            return .success(.listBrushes(document: document))
        case "set_brush":
            guard !change.isEmpty else { return fail("say what to change: medium, mode, color or settings.") }
            return .success(.setBrush(document: document, brush: change))
        case "paint_stroke":
            if args["points"] != nil, args["path"] != nil { return fail("give points or path, not both.") }
            var points = (args["points"]?.arrayValue ?? []).map { point in
                (point: CGPoint(x: point["x"]?.doubleValue ?? 0, y: point["y"]?.doubleValue ?? 0),
                 pressure: point["pressure"]?.doubleValue,
                 tilt: point["tilt"].flatMap { tilt -> CGPoint? in
                     guard let x = tilt["x"]?.doubleValue, let y = tilt["y"]?.doubleValue else { return nil }
                     return CGPoint(x: x, y: y)
                 },
                 ms: point["ms"]?.doubleValue)
            }
            if let path = args["path"]?.stringValue {
                switch AgentPaint.path(path) {
                case .success(let read): points = read.map { (point: $0.point, pressure: $0.pressure, tilt: nil, ms: nil) }
                case .failure(let refused): return fail(refused.message)
                }
            }
            guard points.count >= 2 else { return fail("give two or more points; a click is two points in one place.") }
            let layer = args["layer"]?.stringValue
            let newLayer = args["newLayer"]?.boolValue ?? false
            if layer != nil, newLayer { return fail("give layer or newLayer, not both.") }
            let seed = args["seed"]?.intValue.flatMap { UInt32(exactly: $0) }
            return .success(.paintStroke(document: document, stroke: AgentStroke(
                samples: AgentPaint.samples(points), brush: change, layer: layer, newLayer: newLayer, seed: seed)))
        default:
            return .failure(AgentToolError("There is no tool called \(name).", isUnknownTool: true))
        }
    }
}
