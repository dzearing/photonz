import Foundation

/// Which sections of the right hand panel are folded, as the one stored
/// setting keeps them: section names joined by commas, sorted so the same
/// folds always store the same words.
///
/// Names the app no longer has are kept rather than dropped, so a section that
/// comes back in a later build is still folded the way the person left it.
public struct PanelSectionFolds: Equatable, Sendable {
    public private(set) var folded: Set<String>

    public init(stored: String?) {
        folded = Set((stored ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    /// The setting's words for these folds.
    public var stored: String { folded.sorted().joined(separator: ",") }

    public func contains(_ section: String) -> Bool { folded.contains(section) }

    public mutating func toggle(_ section: String) {
        if folded.remove(section) == nil { folded.insert(section) }
    }

    /// Opens a section, and says whether it was folded at all.
    @discardableResult
    public mutating func open(_ section: String) -> Bool {
        folded.remove(section) != nil
    }

    /// The sections folded in one of these and open in the other: what a
    /// change of the setting actually flipped.
    public func flipped(from other: PanelSectionFolds) -> Set<String> {
        folded.symmetricDifference(other.folded)
    }
}

/// Whether a stored setting's value really changed, read as the property list
/// object the defaults hand back.
///
/// A view's `@AppStorage` whose key has a dot in it (`inspector.width`) cannot
/// be watched on its own, and SwiftUI then treats EVERY write to ANY setting
/// as a change to it: one fold of a panel section rebuilt the whole editor,
/// canvas, tool bar and timeline included (measured 2026-10-04 with a bare
/// SwiftUI window: `x.width` rebuilt on writes of unrelated keys, `xwidth` did
/// not). The app's own setting cells compare with this before telling anyone.
public enum StoredSettingValue {
    public static func differs(_ old: Any?, _ new: Any?) -> Bool {
        switch (old, new) {
        case (nil, nil): return false
        case let (old?, new?): return !(old as AnyObject).isEqual(new)
        default: return true
        }
    }
}
