import CoreGraphics
import Foundation

// An agent keys a layer with the keys a person sets on the timeline
// (task `an-agent-can-set-read-and-change-a-layer-s-keys`, `docs/design/agent-mcp.md`).
//
// There is no second model. A key set here is the `LayerMotion` Add Key and the
// panel's diamonds write (`PropertyKeys.swift`, `KeyMoments.swift`), on the lap
// a keyed picture already has (`PictureKeys.swift`), so it shows on the strip
// and a person can pick it, drag it and ease it. Times are the document's: a
// moment of the lap on a picture, of the video on a video.

/// One key as an agent states it.
public struct AgentKey: Hashable, Sendable {
    public var atMS: Int
    public var value: MotionValue
    /// The run LEAVING this key, in the words of the Curve dropdown. Nil leaves
    /// a key that is there as it was, and a new one on the keys' usual ease.
    public var curve: EasingCurve?

    public init(atMS: Int, value: MotionValue, curve: EasingCurve? = nil) {
        self.atMS = atMS
        self.value = value
        self.curve = curve
    }
}

/// What a turn turns about: a spot on the layer's own box, as a fraction of it,
/// or the middle of the artboard it is drawn on (`MotionPivot`).
public enum AgentKeyPivot: Hashable, Sendable {
    case unit(CGPoint)
    case artboard
}

/// A set_keys call.
public struct AgentSetKeys: Hashable, Sendable {
    public var layer: String
    public var property: MotionProperty
    /// Which shadow, glow or border, counting from nought.
    public var effect: Int
    public var keys: [AgentKey]
    /// True makes these the only keys the value has.
    public var replace: Bool
    public var pivot: AgentKeyPivot?

    public init(layer: String, property: MotionProperty, effect: Int = 0, keys: [AgentKey],
                replace: Bool = false, pivot: AgentKeyPivot? = nil) {
        self.layer = layer
        self.property = property
        self.effect = effect
        self.keys = keys
        self.replace = replace
        self.pivot = pivot
    }
}

/// A remove_keys call: one key, one value's keys, or everything on the layer.
public struct AgentRemoveKeys: Hashable, Sendable {
    public var layer: String
    public var property: MotionProperty?
    public var effect: Int
    public var atMS: Int?

    public init(layer: String, property: MotionProperty? = nil, effect: Int = 0, atMS: Int? = nil) {
        self.layer = layer
        self.property = property
        self.effect = effect
        self.atMS = atMS
    }
}

/// A set_timing call: a picture's lap.
public struct AgentTiming: Hashable, Sendable {
    public var lengthMS: Int?
    public var repeats: Bool?

    public init(lengthMS: Int? = nil, repeats: Bool? = nil) {
        self.lengthMS = lengthMS
        self.repeats = repeats
    }
}

/// A change_keys call: every key of what it names, faster or further at once.
public struct AgentChangeKeys: Hashable, Sendable {
    /// The layers, by id; every keyed layer when nil.
    public var layers: [String]?
    /// Only this value of them.
    public var property: MotionProperty?
    /// 2 is twice as fast.
    public var speed: Double?
    /// 1.5 goes half as far again from where each value starts; -1 the other way.
    public var amount: Double?

    public init(layers: [String]? = nil, property: MotionProperty? = nil, speed: Double? = nil, amount: Double? = nil) {
        self.layers = layers
        self.property = property
        self.speed = speed
        self.amount = amount
    }
}

/// What change_keys did.
public struct AgentKeysChanged: Encodable, Hashable, Sendable {
    /// How many values it changed.
    public let values: Int
    public let lapSeconds: Double?
}

/// What set_keys did.
public struct AgentKeysSet: Encodable, Hashable, Sendable {
    public let layer: String
    public let property: String
    /// How many keys the value has now.
    public let keys: Int
    /// A picture's lap, which a key past its end has grown.
    public let lapSeconds: Double?
}

/// What remove_keys did.
public struct AgentKeysRemoved: Encodable, Hashable, Sendable {
    public let layer: String
    public let removed: Int
}

/// What set_timing did.
public struct AgentTimingSet: Encodable, Hashable, Sendable {
    public let lapSeconds: Double
    public let loop: Bool
}

/// A curve in the words set_keys takes and read_document gives back, so what is
/// read can be handed straight back.
public enum AgentKeyCurve {
    static let hold = "Hold"

    public static func word(_ curve: EasingCurve) -> String {
        curve == .steps(1) ? hold : curve.title
    }

    public static func curve(named word: String) -> EasingCurve? {
        let said = word.trimmingCharacters(in: .whitespaces)
        if said.caseInsensitiveCompare(hold) == .orderedSame { return .steps(1) }
        if let named = (EasingCurve.named + [.smooth]).first(where: { $0.title.caseInsensitiveCompare(said) == .orderedSame }) {
            return named
        }
        return bezier(said)
    }

    /// `cubic-bezier(x1, y1, x2, y2)`, what a drawn curve is called.
    private static func bezier(_ word: String) -> EasingCurve? {
        let prefix = "cubic-bezier("
        guard word.lowercased().hasPrefix(prefix), word.hasSuffix(")") else { return nil }
        let numbers = word.dropFirst(prefix.count).dropLast().split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 4, (0...1).contains(numbers[0]), (0...1).contains(numbers[2]) else { return nil }
        return .custom(x1: numbers[0], y1: numbers[1], x2: numbers[2], y2: numbers[3])
    }

    /// What the tool's description lists.
    static var words: String {
        (EasingCurve.named.map(word) + [hold]).joined(separator: ", ")
    }
}

extension AgentTools {

    private static let documentWords: AgentJSON = [
        "type": "string",
        "description": "The document's id from list_documents, such as d1. Leave it out to use the document in front.",
    ]

    private static let propertyNames: AgentJSON = .array(MotionProperty.allCases.map { .string($0.rawValue) })

    private static let effectProperty: AgentJSON = [
        "type": "integer", "minimum": 0, "maximum": 20,
        "description": "Which shadow, glow or border, counting from 0. 0 when left out.",
    ]

    static let keyTools: [AgentTool] = [
        AgentTool(
            name: "set_keys",
            description: "Key one value of a layer, the keys a person sets on the timeline: it moves between them and a person can pick and change them. On a picture the first key gives it a lap (set_timing). Keys already there stay unless replace is true; a key at the same moment is rewritten. One undo step.",
            inputSchema: schema([
                "document": documentWords,
                "layer": ["type": "string", "description": "The layer's id from read_document."],
                "property": ["type": "string", "enum": propertyNames,
                             "description": "The value to key. position is the top left of its box, scale and opacity are percents (opacity 0 to 100), rotation is degrees clockwise, color is #RRGGBB."],
                "effect": effectProperty,
                "keys": ["type": "array", "description": "The keys, in any order.", "items": [
                    "type": "object",
                    "properties": [
                        "seconds": ["type": "number", "minimum": 0, "description": "The moment: from the top of a picture's lap, from the start of a video."],
                        "value": ["description": "A number; x and y for position; #RRGGBB for a colour.",
                                  "anyOf": [
                                      ["type": "number"],
                                      ["type": "string"],
                                      ["type": "object", "properties": ["x": ["type": "number", "description": "Across."],
                                                                        "y": ["type": "number", "description": "Down."]],
                                       "required": ["x", "y"], "additionalProperties": false],
                                  ]],
                        "curve": ["type": "string", "description": .string("The run from this key to the next: \(AgentKeyCurve.words), or cubic-bezier(x1, y1, x2, y2). Ease in out when left out on a new key.")],
                    ],
                    "required": ["seconds", "value"], "additionalProperties": false,
                ]],
                "replace": ["type": "boolean", "description": "Make these the only keys this value has."],
                "pivot": ["description": "What a rotation turns about: x and y as fractions of the layer's box (0.5, 0 is the middle of its top edge; outside 0 to 1 is off the layer), or artboard for the middle of the artboard. Its middle when left out. On rotationX or rotationY, the hinge it folds over.",
                          "anyOf": [
                              ["type": "string", "enum": ["artboard"]],
                              ["type": "object", "properties": ["x": ["type": "number", "description": "Across its box."],
                                                                "y": ["type": "number", "description": "Down its box."]],
                               "required": ["x", "y"], "additionalProperties": false],
                          ]],
            ], required: ["layer", "property", "keys"])),
        AgentTool(
            name: "remove_keys",
            description: "Take keys off a layer: the key at a moment, all of one value's, or with no property all of the layer's. A value losing its last key stays as it was at that key. One undo step.",
            inputSchema: schema([
                "document": documentWords,
                "layer": ["type": "string", "description": "The layer's id from read_document."],
                "property": ["type": "string", "enum": propertyNames, "description": "Only this value. Every value when left out."],
                "effect": effectProperty,
                "seconds": ["type": "number", "minimum": 0, "description": "Only the key at this moment. Every moment when left out."],
            ], required: ["layer"])),
        AgentTool(
            name: "change_keys",
            description: "Change an animation that is there, all at once: faster or slower, further or less far. Every key keeps its curve. With no layers, it changes everything keyed and the lap with it. One undo step.",
            inputSchema: schema([
                "document": documentWords,
                "layers": ["type": "array", "items": ["type": "string"], "description": "The layers' ids from read_document. Every keyed layer when left out."],
                "property": ["type": "string", "enum": propertyNames, "description": "Only this value. Left out, speed changes every value and amount changes position, rotation and scale."],
                "speed": ["type": "number", "exclusiveMinimum": 0, "maximum": 20, "description": "2 is twice as fast, 0.5 half as fast. A layer named on its own keeps when it starts."],
                "amount": ["type": "number", "minimum": -10, "maximum": 10, "description": "How far each value goes from where it starts: 1.5 is half as far again, 0.5 half as far, -1 the other way."],
            ])),
        AgentTool(
            name: "set_timing",
            description: "Say how a picture plays: the length of its lap and whether it loops. It stays a picture, and it moves once it has keys. A video's length is its clips. One undo step.",
            inputSchema: schema([
                "document": documentWords,
                "seconds": ["type": "number", "minimum": .number(0.1), "maximum": 600,
                            "description": "How long one lap is. It cannot end before the last key."],
                "loop": ["type": "boolean", "description": "true goes round for ever; false plays once and holds the end."],
            ])),
    ]

    static let keyToolNames: Set<String> = Set(keyTools.map(\.name))

    private static func milliseconds(_ seconds: Double) -> Int { Int((seconds * 1000).rounded()) }

    private static func motionValue(_ json: AgentJSON) -> MotionValue? {
        if let number = json.doubleValue { return .number(number) }
        if let word = json.stringValue {
            guard case .hex(let hex)? = AgentInk(word) else { return nil }
            return .color(hex.uppercased())
        }
        guard let x = json["x"]?.doubleValue, let y = json["y"]?.doubleValue else { return nil }
        return .point(CGPoint(x: x, y: y))
    }

    static func keyRequest(_ name: String, _ args: [String: AgentJSON],
                           document: String?) -> Result<AgentRequest, AgentToolError> {
        func fail(_ words: String) -> Result<AgentRequest, AgentToolError> { .failure(AgentToolError("\(name): \(words)")) }
        let effect = args["effect"]?.intValue ?? 0
        var property: MotionProperty?
        if let word = args["property"]?.stringValue {
            guard let named = MotionProperty(rawValue: word) else { return fail("there is no property called \(word).") }
            property = named
        }
        switch name {
        case "set_timing":
            let timing = AgentTiming(lengthMS: args["seconds"]?.doubleValue.map(milliseconds), repeats: args["loop"]?.boolValue)
            guard timing != AgentTiming() else { return fail("say seconds, loop or both.") }
            return .success(.setTiming(document: document, timing: timing))
        case "change_keys":
            let call = AgentChangeKeys(layers: args["layers"]?.arrayValue?.compactMap(\.stringValue), property: property,
                                       speed: args["speed"]?.doubleValue, amount: args["amount"]?.doubleValue)
            guard call.speed != nil || call.amount != nil else { return fail("say speed, amount or both.") }
            if let speed = call.speed, speed <= 0 { return fail("speed is above 0: 2 is twice as fast.") }
            return .success(.changeKeys(document: document, call: call))
        case "remove_keys":
            let layer = args["layer"]?.stringValue ?? ""
            return .success(.removeKeys(document: document, call: AgentRemoveKeys(
                layer: layer, property: property, effect: effect, atMS: args["seconds"]?.doubleValue.map(milliseconds))))
        default:
            break
        }
        guard let property else { return fail("say which property.") }
        let list = args["keys"]?.arrayValue ?? []
        guard !list.isEmpty else { return fail("give at least one key; remove_keys takes keys away.") }
        var keys: [AgentKey] = []
        for key in list {
            guard let seconds = key["seconds"]?.doubleValue, let json = key["value"] else { return fail("each key has seconds and a value.") }
            guard let value = motionValue(json) else {
                return fail("\(json.encodedString()) is not a value: give a number, x and y, or #RRGGBB.")
            }
            var curve: EasingCurve?
            if let word = key["curve"]?.stringValue {
                guard let named = AgentKeyCurve.curve(named: word) else {
                    return fail("there is no curve called \(word). The curves are \(AgentKeyCurve.words), or cubic-bezier(x1, y1, x2, y2).")
                }
                curve = named
            }
            keys.append(AgentKey(atMS: milliseconds(seconds), value: value, curve: curve))
        }
        keys.sort { $0.atMS < $1.atMS }
        for (one, next) in zip(keys, keys.dropFirst()) where next.atMS - one.atMS <= PropertyKeys.nearMS {
            return fail("two keys at \(Double(one.atMS) / 1000) s are one key on the timeline; put them further apart.")
        }
        var pivot: AgentKeyPivot?
        if let json = args["pivot"] {
            // A fold turns in space about its hinge (`LayerTurn3D.hinge`),
            // which is a place on its own box: there is no artboard for it.
            let folds = property == .rotationX || property == .rotationY
            guard property == .rotation || folds else { return fail("only rotation, rotationX and rotationY turn about a pivot.") }
            if json.stringValue != nil {
                guard !folds else { return fail("a fold's pivot is x and y on its own box, the edge it folds over.") }
                pivot = .artboard
            } else if let x = json["x"]?.doubleValue, let y = json["y"]?.doubleValue {
                pivot = .unit(CGPoint(x: x, y: y))
            }
        }
        return .success(.setKeys(document: document, call: AgentSetKeys(
            layer: args["layer"]?.stringValue ?? "", property: property, effect: effect, keys: keys,
            replace: args["replace"]?.boolValue ?? false, pivot: pivot)))
    }
}

extension PhotonzDocument {

    private func keyTarget(_ layer: String, _ tool: String) -> Result<Layer, AgentToolError> {
        guard let id = UUID(uuidString: layer), let found = self.layer(id: id) else {
            return .failure(AgentToolError("\(tool): there is no layer \(layer) in this document. read_document lists the layer ids."))
        }
        guard !found.isLocked else {
            return .failure(AgentToolError("\(tool): \(found.name) is locked. Unlock it with run_command lock_layer, on false."))
        }
        return .success(found)
    }

    /// Why this value cannot stand on this property, or nil where it can.
    private static func problem(with value: MotionValue, for property: MotionProperty,
                                like still: MotionValue) -> String? {
        switch (still, value) {
        case (.number, .number(let number)):
            let percent: Set<MotionProperty> = [.opacity, .shadowOpacity, .glowOpacity]
            if percent.contains(property), !(0...100).contains(number) {
                return "\(property.rawValue) runs 0 to 100, not \(MotionNumber.text(number))."
            }
            return property == .scale && number < 0 ? "scale cannot go below 0." : nil
        case (.point, .point), (.color, .color): return nil
        case (.number, _): return "\(property.rawValue) takes a number."
        case (.point, _): return "\(property.rawValue) takes x and y."
        case (.color, _): return "\(property.rawValue) takes a colour as #RRGGBB."
        }
    }

    /// Lands a set_keys call. Nothing changes where it is refused.
    public mutating func agentSetKeys(_ call: AgentSetKeys) -> Result<AgentKeysSet, AgentToolError> {
        func fail(_ words: String) -> Result<AgentKeysSet, AgentToolError> { .failure(AgentToolError("set_keys: \(words)")) }
        let layer: Layer
        switch keyTarget(call.layer, "set_keys") {
        case .success(let found): layer = found
        case .failure(let refused): return .failure(refused)
        }
        if let piece = componentPiece(of: layer.id) {
            let original = mainComponent(componentID: piece.componentID)?.name ?? "its original"
            return fail("\(layer.name) is part of a copy of \(original), and follows the original. Key the copy itself.")
        }
        let keyable = layer.keyableProperties
        guard keyable.contains(.motion(call.property, effect: call.effect)),
              let still = layer.keyStill(call.property, effect: call.effect) else {
            let names = keyable.compactMap { offered -> String? in
                guard case let .motion(property, effect) = offered, effect == 0 else { return nil }
                return property.rawValue
            }
            return fail("\(layer.name) cannot key \(call.property.rawValue). It can key \(names.joined(separator: ", ")).")
        }
        for key in call.keys {
            if let problem = Self.problem(with: key.value, for: call.property, like: still) { return fail(problem) }
        }
        let owner = clockOwner(of: layer)
        if hasTime, let time = owner.time,
           let outside = call.keys.first(where: { $0.atMS < time.inMS || $0.atMS > time.outMS }) {
            return fail("\(layer.name) plays from \(Double(time.inMS) / 1000) to \(Double(time.outMS) / 1000) s, "
                        + "so there is no key at \(Double(outside.atMS) / 1000) s.")
        }
        var pivot: MotionPivot?
        switch call.pivot {
        case .unit(let point)?: pivot = MotionPivot(unit: point)
        case .artboard?:
            guard let middle = artboardPivot(for: layer.id) else { return fail("\(layer.name) is not on an artboard.") }
            pivot = middle
        case nil: break
        }

        startKeyLap()
        let clocks = call.keys.map { clipKeyClock(owner, atDocumentMS: $0.atMS) }
        let there = layer.keyedMotion(call.property, effect: call.effect)
        var motion = there
        if call.replace, let first = call.keys.first, let clock = clocks.first {
            motion = there?.rebuilt(from: [MotionStop(atMS: clock, value: first.value)])
        }
        for (key, clock) in zip(call.keys, clocks) {
            motion = motion?.settingKey(atMS: clock, value: key.value)
                ?? .keyed(call.property, effect: call.effect, atMS: clock, value: key.value)
        }
        guard var made = motion else { return fail("give at least one key.") }
        for (key, clock) in zip(call.keys, clocks) {
            if let curve = key.curve, let index = made.keyIndex(near: clock) { made = made.curvingStretch(index, curve) }
        }
        // A fold's pivot is the hinge it turns about in space; a flat turn's
        // is the motion's own.
        let hinge = call.property.isSpace ? pivot?.unit : nil
        if let pivot, hinge == nil { made.pivot = pivot }
        let finished = made
        updateLayer(id: layer.id) { edited in
            if let hinge {
                var turn = edited.turn3D ?? LayerTurn3D()
                turn.hinge = hinge
                edited.turn3D = turn
            }
            var motions = edited.motions ?? []
            if let index = motions.firstIndex(where: { $0.id == there?.id }) {
                motions[index] = finished
            } else {
                motions.append(finished)
            }
            edited.motions = motions
        }
        settleHollowMoments(layerID: layer.id)
        if !hasTime, let last = call.keys.last, last.atMS > motionCycleLengthMS { motionCycleMS = last.atMS }
        return .success(AgentKeysSet(layer: layer.id.uuidString, property: call.property.rawValue,
                                     keys: finished.keyframes.count,
                                     lapSeconds: hasTime ? nil : Double(motionCycleLengthMS) / 1000))
    }

    /// Lands a remove_keys call.
    public mutating func agentRemoveKeys(_ call: AgentRemoveKeys) -> Result<AgentKeysRemoved, AgentToolError> {
        func fail(_ words: String) -> Result<AgentKeysRemoved, AgentToolError> { .failure(AgentToolError("remove_keys: \(words)")) }
        let layer: Layer
        switch keyTarget(call.layer, "remove_keys") {
        case .success(let found): layer = found
        case .failure(let refused): return .failure(refused)
        }
        let id = layer.id
        let keyed = keyedMotions(of: layer).filter { motion in
            call.property.map { $0 == motion.property && call.effect == motion.effectOrdinal } ?? true
        }
        let hollow = call.property == nil ? hollowMomentsMS(of: layer) : []
        func count() -> Int {
            guard let now = self.layer(id: id) else { return 0 }
            return keyedMotions(of: now).reduce(0) { $0 + $1.keyframes.count } + hollowMomentsMS(of: now).count
        }
        let before = count()
        if let ms = call.atMS {
            for motion in keyed {
                _ = removeKey(layerID: id, .motion(motion.property, effect: motion.effectOrdinal), atDocumentTimeMS: ms)
            }
            if call.property == nil { dropHollowMoments(layerID: id, near: [ms]) }
        } else {
            // Each value keeps what it has at the first moment, which is what
            // a still of this picture has always shown (`keyedStill`).
            for motion in keyed {
                _ = stopKeying(layerID: id, .motion(motion.property, effect: motion.effectOrdinal), atDocumentTimeMS: 0)
            }
            if !hollow.isEmpty { updateLayer(id: id) { $0.hollowKeyMoments = nil } }
        }
        let removed = before - count()
        guard removed > 0 else {
            let what = call.property?.rawValue ?? layer.name
            return fail("there is no key on \(what)\(call.atMS.map { " at \(Double($0) / 1000) s" } ?? "").")
        }
        return .success(AgentKeysRemoved(layer: id.uuidString, removed: removed))
    }

    /// The values `amount` changes when none is named: what a person means by
    /// further. A fade or a colour has no further to go.
    private static let amountChanges: Set<MotionProperty> = [.position, .rotation, .scale]

    /// `value`, `amount` times as far from `rest`.
    private static func further(_ value: MotionValue, from rest: MotionValue, amount: Double,
                                property: MotionProperty) -> MotionValue? {
        switch (rest, value) {
        case let (.point(start), .point(point)):
            return .point(CGPoint(x: start.x + (point.x - start.x) * amount, y: start.y + (point.y - start.y) * amount))
        case let (.number(start), .number(number)):
            let moved = start + (number - start) * amount
            if [.opacity, .shadowOpacity, .glowOpacity, .trimStart, .trimEnd].contains(property) { return .number(min(max(moved, 0), 100)) }
            return .number(property == .scale ? max(moved, 0) : moved)
        default:
            return nil
        }
    }

    /// Lands a change_keys call. Nothing changes where it is refused.
    public mutating func agentChangeKeys(_ call: AgentChangeKeys) -> Result<AgentKeysChanged, AgentToolError> {
        func fail(_ words: String) -> Result<AgentKeysChanged, AgentToolError> { .failure(AgentToolError("change_keys: \(words)")) }
        var targets: [Layer] = []
        if let named = call.layers {
            for id in named {
                switch keyTarget(id, "change_keys") {
                case .success(let found): targets.append(found)
                case .failure(let refused): return .failure(refused)
                }
            }
        } else {
            targets = keyedLayers()
        }
        // Naming every keyed layer is the whole motion, however it was said.
        let whole = call.property == nil && Set(keyedLayers().map(\.id)).isSubset(of: Set(targets.map(\.id)))
        var work = self
        var values = 0
        for layer in targets {
            let motions = keyedMotions(of: layer).filter { motion in call.property.map { $0 == motion.property } ?? true }
            var lead = motions.compactMap { $0.keyframes.first?.atMS }.min() ?? 0
            if whole { lead = 0 }
            for motion in motions {
                var stops = motion.keyframes
                guard let first = stops.first else { continue }
                var changed = false
                if let amount = call.amount, call.property != nil || Self.amountChanges.contains(motion.property) {
                    for index in stops.indices {
                        if let moved = Self.further(stops[index].value, from: first.value, amount: amount, property: motion.property) {
                            stops[index].value = moved
                            changed = true
                        }
                    }
                }
                if let speed = call.speed {
                    for index in stops.indices {
                        stops[index].atMS = lead + Int((Double(stops[index].atMS - lead) / speed).rounded())
                    }
                    changed = true
                    for (one, next) in zip(stops, stops.dropFirst()) where next.atMS - one.atMS <= PropertyKeys.nearMS {
                        return fail("\(layer.name)'s keys would land on each other at that speed. Ask for less, or remove some with remove_keys.")
                    }
                }
                guard changed else { continue }
                let made = motion.rebuilt(from: stops)
                work.updateLayer(id: layer.id) { edited in
                    guard let index = edited.motions?.firstIndex(where: { $0.id == motion.id }) else { return }
                    edited.motions?[index] = made
                }
                values += 1
            }
        }
        guard values > 0 else {
            return fail("nothing there to change\(call.property.map { " on \($0.rawValue)" } ?? ""). read_document lists what is keyed.")
        }
        if let speed = call.speed, !hasTime {
            if whole {
                work.motionCycleMS = max(1, Int((Double(motionCycleLengthMS) / speed).rounded()))
            } else {
                // A key past the end of the lap would never be reached.
                let last = work.keyedLayers().flatMap { work.keyedMotions(of: $0) }.compactMap { $0.keyframes.last?.atMS }.max() ?? 0
                if last > motionCycleLengthMS { work.motionCycleMS = last }
            }
        }
        self = work
        return .success(AgentKeysChanged(values: values, lapSeconds: hasTime ? nil : Double(work.motionCycleLengthMS) / 1000))
    }

    /// Every layer with a key on it, in the order they are listed.
    private func keyedLayers() -> [Layer] {
        func walk(_ list: [Layer]) -> [Layer] {
            list.flatMap { layer in (keyedMotions(of: layer).isEmpty ? [] : [layer]) + walk(layer.children) }
        }
        return walk(layers)
    }

    /// Lands a set_timing call. The lap is written down whether or not there
    /// are keys yet, and the first key keeps it (`startKeyLap`).
    public mutating func agentSetTiming(_ timing: AgentTiming) -> Result<AgentTimingSet, AgentToolError> {
        guard !hasTime else {
            return .failure(AgentToolError("set_timing: a video's length is its clips, and it does not loop."))
        }
        if let length = timing.lengthMS {
            let last = shortestKeyLapMS - 1
            guard length >= last else {
                return .failure(AgentToolError("set_timing: the last key is at \(Double(last) / 1000) s, so a lap cannot end before that."))
            }
        }
        startKeyLap()
        if let length = timing.lengthMS { motionCycleMS = length }
        if let repeats = timing.repeats { keyLap?.repeats = repeats }
        return .success(AgentTimingSet(lapSeconds: Double(motionCycleLengthMS) / 1000, loop: keyLap?.repeats ?? true))
    }
}
