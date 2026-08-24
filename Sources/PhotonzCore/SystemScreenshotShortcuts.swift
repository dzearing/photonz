import Foundation

/// macOS's own screenshot shortcuts (System Settings → Keyboard → Keyboard
/// Shortcuts → Screenshots) swallow ⇧⌘3/⇧⌘4/⇧⌘5 before any app's global
/// hotkeys can see them, even with Screen Recording granted. This maps the
/// user's `com.apple.symbolichotkeys` → `AppleSymbolicHotKeys` dictionary to
/// the Photonz capture hotkeys the system still owns, so the welcome flow can
/// walk the user through freeing them.
public enum SystemScreenshotShortcuts {

    /// A Photonz capture hotkey that a built-in screenshot shortcut can shadow.
    /// Raw values are Apple's symbolic hotkey IDs.
    public enum Shortcut: Int, CaseIterable, Sendable {
        case fullScreen = 28   // ⇧⌘3 "Save picture of screen as a file"
        case region = 30       // ⇧⌘4 "Save picture of selected area as a file"
        case toolbar = 184     // ⇧⌘5 "Screenshot and recording options"

        public var keyLabel: String {
            switch self {
            case .fullScreen: "⇧⌘3"
            case .region: "⇧⌘4"
            case .toolbar: "⇧⌘5"
            }
        }
    }

    /// The shortcuts the system still holds, given the raw
    /// `AppleSymbolicHotKeys` dictionary (keys are numeric strings, values are
    /// dictionaries with an optional `enabled` flag). Absence means the system
    /// default applies — enabled — so a `nil` dictionary (domain never
    /// customized), a missing entry, or an entry with no `enabled` key all
    /// count as conflicts.
    public static func conflicting(in hotkeys: [String: Any]?) -> [Shortcut] {
        guard let hotkeys else { return Shortcut.allCases }
        return Shortcut.allCases.filter { shortcut in
            guard let entry = hotkeys[String(shortcut.rawValue)] as? [String: Any],
                  let flag = entry["enabled"] else { return true }
            if let enabled = flag as? Bool { return enabled }
            if let enabled = flag as? Int { return enabled != 0 }
            return true
        }
    }
}
