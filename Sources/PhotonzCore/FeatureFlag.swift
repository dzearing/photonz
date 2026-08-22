import Foundation

/// Limits for a number parameter: what the dialog's stepper offers and what any
/// stored value is clamped to on the way in.
public struct NumberBounds: Codable, Sendable, Hashable {
    public let minimum: Double
    public let maximum: Double
    /// Stepper increment. Also the hint for how many decimals to show.
    public let step: Double

    public init(minimum: Double, maximum: Double, step: Double = 1) {
        self.minimum = minimum
        self.maximum = maximum
        self.step = step
    }

    public func clamped(_ value: Double) -> Double {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}

/// A feature flag's typed parameter value. Four kinds, each with a control in
/// the Experiments dialog: number (stepper + field), string (text field),
/// boolean (toggle), enumeration (picker over a fixed set of string cases).
public enum FeatureParameterValue: Codable, Sendable, Hashable {
    case number(Double)
    case string(String)
    case boolean(Bool)
    /// A fixed set of allowed cases plus the current selection.
    case enumeration(cases: [String], selection: String)

    public enum Kind: String, Codable, Sendable, Hashable {
        case number, string, boolean, enumeration
    }

    public var kind: Kind {
        switch self {
        case .number: .number
        case .string: .string
        case .boolean: .boolean
        case .enumeration: .enumeration
        }
    }

    public var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var booleanValue: Bool? {
        if case .boolean(let value) = self { return value }
        return nil
    }

    public var enumerationSelection: String? {
        if case .enumeration(_, let selection) = self { return selection }
        return nil
    }

    public var enumerationCases: [String]? {
        if case .enumeration(let cases, _) = self { return cases }
        return nil
    }

    // Explicit coding: the payload is keyed by kind so the stored JSON stays
    // readable and a value that changed type is detectable rather than fatal.
    private enum CodingKeys: String, CodingKey {
        case kind, number, string, boolean, cases, selection
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .number:
            self = .number(try container.decode(Double.self, forKey: .number))
        case .string:
            self = .string(try container.decode(String.self, forKey: .string))
        case .boolean:
            self = .boolean(try container.decode(Bool.self, forKey: .boolean))
        case .enumeration:
            self = .enumeration(cases: try container.decode([String].self, forKey: .cases),
                                selection: try container.decode(String.self, forKey: .selection))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .number(let value): try container.encode(value, forKey: .number)
        case .string(let value): try container.encode(value, forKey: .string)
        case .boolean(let value): try container.encode(value, forKey: .boolean)
        case .enumeration(let cases, let selection):
            try container.encode(cases, forKey: .cases)
            try container.encode(selection, forKey: .selection)
        }
    }
}

/// One knob on a feature flag. The name is the stable identifier; the label is
/// what the dialog shows.
public struct FeatureParameter: Codable, Sendable, Hashable, Identifiable {
    public let name: String
    public let label: String
    /// Number parameters only; ignored for the other kinds.
    public let bounds: NumberBounds?
    public private(set) var value: FeatureParameterValue

    public var id: String { name }

    public init(name: String, label: String, value: FeatureParameterValue, bounds: NumberBounds? = nil) {
        self.name = name
        self.label = label
        self.bounds = bounds
        self.value = value
        // Normalize whatever was handed in through the same gate edits use.
        setValue(value)
    }

    /// Applies a new value, refusing anything that doesn't fit: a different
    /// kind, an enum case this parameter doesn't offer, or a number outside the
    /// bounds (clamped rather than refused). The declared enum cases always
    /// come from this parameter, never from the incoming value.
    public mutating func setValue(_ newValue: FeatureParameterValue) {
        switch (value, newValue) {
        case (.number, .number(let incoming)):
            value = .number(bounds?.clamped(incoming) ?? incoming)
        case (.string, .string(let incoming)):
            value = .string(incoming)
        case (.boolean, .boolean(let incoming)):
            value = .boolean(incoming)
        case (.enumeration(let cases, _), .enumeration(_, let incoming)):
            guard cases.contains(incoming) else { return }
            value = .enumeration(cases: cases, selection: incoming)
        default:
            return
        }
    }

    /// Shorthand for enum parameters: pick a case by name.
    public mutating func select(_ caseName: String) {
        guard let cases = value.enumerationCases else { return }
        setValue(.enumeration(cases: cases, selection: caseName))
    }

    public func settingValue(_ newValue: FeatureParameterValue) -> FeatureParameter {
        var copy = self
        copy.setValue(newValue)
        return copy
    }
}

/// A feature flag: a named, describable switch with typed parameters. Flags are
/// scoped to a release — the same flag under Public and under Next carries its
/// own independent state.
public struct FeatureFlag: Codable, Sendable, Hashable, Identifiable {
    /// Stable identifier. Persisted, and what call sites ask for.
    public let name: String
    /// Short human name for the dialog row.
    public let title: String
    /// What turning this on actually does, in plain words.
    public let description: String
    public var isEnabled: Bool
    public private(set) var parameters: [FeatureParameter]

    public var id: String { name }

    public init(name: String, title: String, description: String,
                isEnabled: Bool, parameters: [FeatureParameter] = []) {
        self.name = name
        self.title = title
        self.description = description
        self.isEnabled = isEnabled
        self.parameters = parameters
    }

    public func parameter(named name: String) -> FeatureParameter? {
        parameters.first { $0.name == name }
    }

    public func number(_ name: String) -> Double? { parameter(named: name)?.value.numberValue }
    public func string(_ name: String) -> String? { parameter(named: name)?.value.stringValue }
    public func boolean(_ name: String) -> Bool? { parameter(named: name)?.value.booleanValue }
    public func selection(_ name: String) -> String? { parameter(named: name)?.value.enumerationSelection }

    /// Edits one parameter. Unknown names and unusable values are ignored.
    public mutating func setParameter(_ name: String, to value: FeatureParameterValue) {
        guard let index = parameters.firstIndex(where: { $0.name == name }) else { return }
        parameters[index].setValue(value)
    }

    /// Folds previously persisted state (`stored`) onto this catalog definition:
    /// the enabled bit and any still-valid parameter values are kept, while the
    /// copy, the parameter list, and the limits all come from the definition.
    func applying(stored: FeatureFlag) -> FeatureFlag {
        var merged = self
        merged.isEnabled = stored.isEnabled
        for parameter in parameters {
            guard let storedValue = stored.parameter(named: parameter.name)?.value else { continue }
            merged.setParameter(parameter.name, to: storedValue)
        }
        return merged
    }
}

/// One release's feature-flag state: the catalog's flags with this release's
/// enabled bits and parameter values. Value-typed and Codable, so persisting it
/// is one `JSONEncoder` call.
public struct FeatureFlagSettings: Codable, Sendable, Hashable {
    /// In catalog order — that's the order the dialog lists them in.
    public private(set) var flags: [FeatureFlag]

    public init(flags: [FeatureFlag] = []) {
        self.flags = flags
    }

    public func flag(named name: String) -> FeatureFlag? {
        flags.first { $0.name == name }
    }

    /// False for a flag that doesn't exist, so a call site guarded on a removed
    /// flag simply goes quiet.
    public func isEnabled(_ flagName: String) -> Bool {
        flag(named: flagName)?.isEnabled ?? false
    }

    public func number(_ flagName: String, _ parameter: String) -> Double? {
        flag(named: flagName)?.number(parameter)
    }

    public func string(_ flagName: String, _ parameter: String) -> String? {
        flag(named: flagName)?.string(parameter)
    }

    public func boolean(_ flagName: String, _ parameter: String) -> Bool? {
        flag(named: flagName)?.boolean(parameter)
    }

    public func selection(_ flagName: String, _ parameter: String) -> String? {
        flag(named: flagName)?.selection(parameter)
    }

    public mutating func setEnabled(_ enabled: Bool, for flagName: String) {
        guard let index = flags.firstIndex(where: { $0.name == flagName }) else { return }
        flags[index].isEnabled = enabled
    }

    public mutating func setParameter(_ parameter: String, of flagName: String,
                                      to value: FeatureParameterValue) {
        guard let index = flags.firstIndex(where: { $0.name == flagName }) else { return }
        flags[index].setParameter(parameter, to: value)
    }

    /// Flags matching a search query, for the dialog's filter field. Every
    /// whitespace-separated term has to match somewhere in the flag (its title,
    /// its identifier, its description, or one of its parameter labels), so
    /// "toast fade" narrows rather than widens. An empty query matches
    /// everything.
    public func flags(matching query: String) -> [FeatureFlag] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return flags }
        return flags.filter { flag in
            let haystack = ([flag.title, flag.name, flag.description]
                + flag.parameters.map(\.label)).joined(separator: " ").lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    /// Rebuilds this state against the flags the code actually has today:
    /// flags that vanished are dropped, new ones arrive with their defaults,
    /// and titles, descriptions, parameter lists and limits always come from
    /// the catalog. Only the enabled bits and still-valid values survive from
    /// storage.
    public func reconciled(with catalog: [FeatureFlag]) -> FeatureFlagSettings {
        FeatureFlagSettings(flags: catalog.map { definition in
            guard let stored = flag(named: definition.name) else { return definition }
            return definition.applying(stored: stored)
        })
    }
}
