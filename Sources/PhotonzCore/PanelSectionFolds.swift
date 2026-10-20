import Foundation

/// Which sections of the right hand panel are folded, as the one stored
/// setting keeps them: section names joined by commas, sorted so the same
/// folds always store the same words.
///
/// Names the app no longer has are kept rather than dropped, so a section that
/// comes back in a later build is still folded the way the person left it.
///
/// A few sections START folded (`startFolded`), and for those the setting
/// remembers the other way round: `+library` once the person has opened it.
public struct PanelSectionFolds: Equatable, Sendable {
    /// The sections folded by hand. Never holds a section that starts folded.
    public private(set) var folded: Set<String>
    /// The sections that start folded and have been opened by hand.
    public private(set) var opened: Set<String>

    /// The sections that are folded until somebody opens them. The Library:
    /// a video shows it without being asked, folded, so the media pool costs
    /// one row until it is wanted (decision on
    /// `a-video-document-shows-the-library-in-its-dock`, 2026-10-19), and the
    /// user said on 2026-10-18 that it should never arrive "expanded by
    /// default". View ▸ Library, and anything else that brings the shelf
    /// forward, opens it.
    public static let startFolded: Set<String> = ["library"]

    private static let openedMark = "+"

    public init(stored: String?) {
        var folded = Set<String>()
        var opened = Set<String>()
        for word in (stored ?? "").split(separator: ",").map(String.init) where !word.isEmpty {
            if word.hasPrefix(Self.openedMark) {
                let name = String(word.dropFirst(Self.openedMark.count))
                if Self.startFolded.contains(name) { opened.insert(name) }
            } else if !Self.startFolded.contains(word) {
                // A section that starts folded and was stored folded, by an
                // older build, is folded already.
                folded.insert(word)
            }
        }
        self.folded = folded
        self.opened = opened
    }

    /// The setting's words for these folds.
    public var stored: String {
        (folded.map { $0 } + opened.map { Self.openedMark + $0 }).sorted().joined(separator: ",")
    }

    public func contains(_ section: String) -> Bool {
        Self.startFolded.contains(section) ? !opened.contains(section) : folded.contains(section)
    }

    public mutating func toggle(_ section: String) {
        set(section, folded: !contains(section))
    }

    /// Opens a section, and says whether it was folded at all.
    @discardableResult
    public mutating func open(_ section: String) -> Bool {
        guard contains(section) else { return false }
        set(section, folded: false)
        return true
    }

    private mutating func set(_ section: String, folded isFolded: Bool) {
        if Self.startFolded.contains(section) {
            if isFolded { opened.remove(section) } else { opened.insert(section) }
        } else {
            if isFolded { folded.insert(section) } else { folded.remove(section) }
        }
    }

    /// The sections folded in one of these and open in the other: what a
    /// change of the setting actually flipped.
    public func flipped(from other: PanelSectionFolds) -> Set<String> {
        folded.symmetricDifference(other.folded)
            .union(opened.symmetricDifference(other.opened))
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
