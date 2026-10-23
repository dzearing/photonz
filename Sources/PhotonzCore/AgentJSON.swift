import Foundation

/// Any JSON value, as the agent channel reads and writes it
/// (`docs/design/agent-mcp.md`).
///
/// The channel carries JSON-RPC whose arguments are whatever a client sends,
/// so they are read into this first and checked against a tool's schema
/// before anything typed is made of them (`AgentTools`).
public enum AgentJSON: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AgentJSON])
    case object([String: AgentJSON])

    public subscript(key: String) -> AgentJSON? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    /// The number, when it is a whole one.
    public var intValue: Int? {
        guard case .number(let value) = self, value.rounded() == value,
              abs(value) < 9_007_199_254_740_992 else { return nil }
        return Int(value)
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var arrayValue: [AgentJSON]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: AgentJSON]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// The JSON type name a schema uses for this value.
    public var typeName: String {
        switch self {
        case .null: "null"
        case .bool: "boolean"
        case .number: intValue != nil ? "integer" : "number"
        case .string: "string"
        case .array: "array"
        case .object: "object"
        }
    }

    public static func parse(_ data: Data) throws -> AgentJSON {
        try JSONDecoder().decode(AgentJSON.self, from: data)
    }

    /// One line of compact JSON, keys sorted so the same value always reads
    /// the same.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data("null".utf8)
    }

    public func encodedString() -> String { String(decoding: encoded(), as: UTF8.self) }

    /// `encoded()`, except that inside every object `scope` picks out, keys
    /// named in `leading` come first, in that order, and the rest after them
    /// sorted. A model runner that constrains a tool call to its schema writes
    /// the keys in the order the schema lists them, so this is the order the
    /// model has to write them in (`AskTools.wireEncoded`).
    public func encoded(leading: [String], inside scope: (AgentJSON) -> Bool) -> Data {
        let rank = Dictionary(leading.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        var out = ""
        write(into: &out, ordered: false, rank: rank, scope: scope)
        return Data(out.utf8)
    }

    private func write(into out: inout String, ordered: Bool, rank: [String: Int], scope: (AgentJSON) -> Bool) {
        switch self {
        case .array(let items):
            out += "["
            for (index, item) in items.enumerated() {
                if index > 0 { out += "," }
                item.write(into: &out, ordered: ordered, rank: rank, scope: scope)
            }
            out += "]"
        case .object(let object):
            let inScope = ordered || scope(self)
            let keys = object.keys.sorted { a, b in
                guard inScope else { return a < b }
                return (rank[a] ?? Int.max, a) < (rank[b] ?? Int.max, b)
            }
            out += "{"
            for (index, key) in keys.enumerated() {
                if index > 0 { out += "," }
                out += AgentJSON.string(key).encodedString() + ":"
                object[key]?.write(into: &out, ordered: inScope, rank: rank, scope: scope)
            }
            out += "}"
        default:
            out += encodedString()
        }
    }
}

extension AgentJSON: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AgentJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: AgentJSON].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // An id of 7 goes back as 7, never 7.0: a client matches answers
            // to questions by it.
            if let whole = intValue { try container.encode(whole) } else { try container.encode(value) }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension AgentJSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
                     ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: AgentJSON...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, AgentJSON)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
