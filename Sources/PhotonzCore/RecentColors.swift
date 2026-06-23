import Foundation

/// A small, persisted most-recently-used list of colors, SHARED across every
/// color affordance (annotations, text, borders, shadows) — so a color you just
/// picked is one click away no matter which object you're styling next (13.2).
///
/// Stored as canonical `#RRGGBB` hex (uppercase, sRGB, alpha dropped). Records
/// are validated through `RGBA(hex:)`; malformed input is silently ignored so a
/// stray sample never corrupts the list. Codable so it survives launches.
public struct RecentColors: Codable, Sendable, Equatable {
    /// Most-recent first.
    public private(set) var colors: [String]

    /// The most colors kept; older entries fall off the end.
    public static let capacity = 10

    public init(colors: [String] = []) {
        self.colors = colors
    }

    /// Records a freshly committed color: canonicalized, deduped
    /// (case-insensitively), moved to the front, and capped at `capacity`.
    /// Malformed hex is ignored.
    public mutating func record(hex: String) {
        guard let canonical = RGBA(hex: hex)?.hexString else { return }
        colors.removeAll { $0.caseInsensitiveCompare(canonical) == .orderedSame }
        colors.insert(canonical, at: 0)
        if colors.count > Self.capacity {
            colors.removeLast(colors.count - Self.capacity)
        }
    }
}
