import Foundation

/// macOS's own screenshot shortcuts (System Settings → Keyboard → Keyboard
/// Shortcuts → Screenshots) swallow ⇧⌘3/⇧⌘4/⇧⌘5 before any app's global
/// hotkeys can see them, even with Screen Recording granted. This maps the
/// user's `com.apple.symbolichotkeys` → `AppleSymbolicHotKeys` dictionary to
/// the Photonz capture hotkeys the system still owns, so the welcome flow can
/// walk the user through freeing them.
///
/// Macs with a Touch Bar add a fourth: ⇧⌘6 saves a picture of the Touch Bar,
/// which hides Photonz's Edit Last Capture. Keyboard Settings only shows that
/// row on those Macs, so it is only ever reported there (`hasTouchBar`).
public enum SystemScreenshotShortcuts {

    /// A Photonz capture hotkey that a built-in screenshot shortcut can shadow.
    /// Raw values are Apple's symbolic hotkey IDs.
    public enum Shortcut: Int, CaseIterable, Sendable {
        case fullScreen = 28   // ⇧⌘3 "Save picture of screen as a file"
        case region = 30       // ⇧⌘4 "Save picture of selected area as a file"
        case toolbar = 184     // ⇧⌘5 "Screenshot and recording options"
        case touchBar = 181    // ⇧⌘6 "Save picture of Touch Bar as a file"

        public var keyLabel: String {
            switch self {
            case .fullScreen: "⇧⌘3"
            case .region: "⇧⌘4"
            case .toolbar: "⇧⌘5"
            case .touchBar: "⇧⌘6"
            }
        }
    }

    /// The shortcuts the system still holds, given the raw
    /// `AppleSymbolicHotKeys` dictionary (keys are numeric strings, values are
    /// dictionaries with an optional `enabled` flag). Absence means the system
    /// default applies — enabled — so a `nil` dictionary (domain never
    /// customized), a missing entry, or an entry with no `enabled` key all
    /// count as conflicts. The Touch Bar shortcut is only considered when
    /// `touchBar` says the machine has one.
    public static func conflicting(in hotkeys: [String: Any]?, touchBar: Bool = false) -> [Shortcut] {
        let candidates = Shortcut.allCases.filter { touchBar || $0 != .touchBar }
        guard let hotkeys else { return candidates }
        return candidates.filter { shortcut in
            guard let entry = hotkeys[String(shortcut.rawValue)] as? [String: Any],
                  let flag = entry["enabled"] else { return true }
            if let enabled = flag as? Bool { return enabled }
            if let enabled = flag as? Int { return enabled != 0 }
            return true
        }
    }

    /// Every Mac Apple shipped with a Touch Bar (`hw.model` identifiers). Only
    /// the M1 13-inch (MacBookPro17,1) can run an arm64 build, but the Intel
    /// ones are listed so the answer stays right under Rosetta or a future
    /// universal build.
    public static let touchBarModelIdentifiers: Set<String> = [
        "MacBookPro13,2", "MacBookPro13,3",
        "MacBookPro14,2", "MacBookPro14,3",
        "MacBookPro15,1", "MacBookPro15,2", "MacBookPro15,3", "MacBookPro15,4",
        "MacBookPro16,1", "MacBookPro16,2", "MacBookPro16,3", "MacBookPro16,4",
        "MacBookPro17,1",
    ]

    /// Whether this machine has a Touch Bar, from its model identifier or,
    /// failing that, from macOS having written the Touch Bar screenshot
    /// hotkey into the preferences (it only does so on a Mac whose Keyboard
    /// Settings shows that row). Errs towards `false`: a warning about a key
    /// the user cannot find in Settings would be worse than no warning.
    public static func hasTouchBar(modelIdentifier: String, hotkeys: [String: Any]?) -> Bool {
        if touchBarModelIdentifiers.contains(modelIdentifier) { return true }
        return hotkeys?[String(Shortcut.touchBar.rawValue)] != nil
    }
}
