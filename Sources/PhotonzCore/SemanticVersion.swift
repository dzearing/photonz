/// A `major.minor.patch` semantic version, used by the updater (phase 11.6) to
/// compare the running build against the published `site/version.json`. Pure
/// value logic so the comparison is testable; the network fetch + alert is a
/// thin app-side shell.
public struct SemanticVersion: Comparable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `"1.2.3"`, tolerating a leading `v`/`V` and surrounding
    /// whitespace, and treating a missing minor/patch as `0` (so `"1"` and
    /// `"1.4"` parse). Returns `nil` for anything non-numeric or with more than
    /// three components.
    public init?(_ string: String) {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first, first == "v" || first == "V" {
            trimmed.removeFirst()
        }
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 3 else { return nil }

        var components = [Int]()
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            components.append(value)
        }
        self.major = components[0]
        self.minor = components.count > 1 ? components[1] : 0
        self.patch = components.count > 2 ? components[2] : 0
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

/// The outcome of comparing the running build to the latest published version.
public enum UpdateAvailability: Equatable, Sendable {
    case upToDate
    case updateAvailable(SemanticVersion)

    /// An update is offered only when `latest` is strictly newer than
    /// `current` — a dev build ahead of the release reports `.upToDate`.
    public init(current: SemanticVersion, latest: SemanticVersion) {
        self = latest > current ? .updateAvailable(latest) : .upToDate
    }
}
