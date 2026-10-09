import Foundation

/// The words on the Layers group's header, as both component mocks draw it
/// (`component-configure-wt.html` `#gLayersH`, `components.html` `#layerMenu`):
/// how many layers there are, a Make Component button, and the panel menu's
/// three rows. Every row is a command the menu bar already has, under the
/// same name and on the same key, so nothing learned here is wrong there.
///
/// Next only (`next-dock-headers`). The app draws it; the words live here so
/// they can be tested.
public enum LayersPanelHeader {
    /// The chip beside the title: every layer the list could show, groups'
    /// contents included, which is the same total the find field counts
    /// against. Nothing for an empty document.
    public static func countChip(layerCount: Int) -> String? {
        DockGroupHeader.countChip(layerCount)
    }

    /// The button's name: the Layer menu's row.
    public static let makeComponent = "Make Component"

    /// Resting on the button: the command and the key that does it anywhere.
    public static let makeComponentHelp = "\(makeComponent) (\u{2325}\u{2318}K)"

    /// The three dots at the end of the header, as VoiceOver and a walk say it.
    public static let menuName = "Layers Menu"

    /// A key a row answers to. Plain data, so the core never names a UI type.
    public struct Shortcut: Equatable, Sendable {
        public enum Modifier: Sendable { case command, option, shift }
        public let key: Character
        public let modifiers: [Modifier]

        public init(key: Character, modifiers: [Modifier]) {
            self.key = key
            self.modifiers = modifiers
        }
    }

    /// The panel menu, top down. Mirror Across Center sits under Group
    /// Selection, where `icon-draw-wt.html` `#layerMenu` puts it.
    public enum MenuRow: CaseIterable, Sendable {
        case groupSelection, mirrorAcrossCenter, makeComponent, hidePanel

        /// The mock's words in the menu bar's Title Case.
        public var title: String {
            switch self {
            case .groupSelection: "Group Selection"
            case .mirrorAcrossCenter: MirrorAcrossCenter.title
            case .makeComponent: LayersPanelHeader.makeComponent
            case .hidePanel: "Hide This " + PanelCopy.noun
            }
        }

        /// The key the menu bar row for the same command answers to.
        public var shortcut: Shortcut? {
            switch self {
            case .groupSelection: Shortcut(key: "g", modifiers: [.command])
            // On a picture or an icon only: on a video ⇧⌘M is Go to Previous
            // Marker, and the app leaves this row out there.
            case .mirrorAcrossCenter: Shortcut(key: "m", modifiers: [.shift, .command])
            case .makeComponent: Shortcut(key: "k", modifiers: [.option, .command])
            // Show Panel is a setting with a checkmark; this row only hides.
            case .hidePanel: nil
            }
        }

        /// Whether a divider goes above the row: the others act on the
        /// layers, the last on the window.
        public var startsSection: Bool { self == .hidePanel }
    }
}
