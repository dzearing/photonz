import Foundation

/// The words on the Layers group's header, as both component mocks draw it
/// (`component-configure-wt.html` `#gLayersH`, `components.html` `#layerMenu`):
/// how many layers there are, a Make Component button, and the panel menu's
/// rows. Every row is a command the menu bar already has, under the
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
        public enum Modifier: Sendable { case command, option, shift, control }
        public let key: Character
        public let modifiers: [Modifier]

        public init(key: Character, modifiers: [Modifier]) {
            self.key = key
            self.modifiers = modifiers
        }
    }

    /// The panel menu, top down. Stack Selection opens it, where
    /// `ui-autolayout.html` `#layerMenu` puts its "Wrap in auto-layout", in the
    /// Layer menu's words. Mirror Across Center and Center on the
    /// Artboard sit under Group Selection, then a divider and Union and
    /// Outline Stroke, where `icon-draw-wt.html` `#layerMenu` puts them.
    public enum MenuRow: CaseIterable, Sendable {
        case stackSelection, groupSelection, mirrorAcrossCenter, centerOnArtboard
        case union, outlineStroke
        case makeComponent, hidePanel

        /// The mock's words in the menu bar's Title Case.
        public var title: String {
            switch self {
            case .stackSelection: Self.stackTitle
            case .groupSelection: "Group Selection"
            case .mirrorAcrossCenter: MirrorAcrossCenter.title
            case .centerOnArtboard: CenterOnArtboard.title
            case .union: PathCombine.unionTitle
            case .outlineStroke: OutlineStroke.title
            case .makeComponent: LayersPanelHeader.makeComponent
            case .hidePanel: "Hide This " + PanelCopy.noun
            }
        }

        /// The key the menu bar row for the same command answers to.
        public var shortcut: Shortcut? {
            switch self {
            case .stackSelection: Shortcut(key: "g", modifiers: [.control, .command])
            case .groupSelection: Shortcut(key: "g", modifiers: [.command])
            // On a picture or an icon only: on a video ⇧⌘M is Go to Previous
            // Marker, and the app leaves this row out there.
            case .mirrorAcrossCenter: Shortcut(key: "m", modifiers: [.shift, .command])
            // The mock prints Option Command C, but that is Canvas Size, as it
            // is in Photoshop, so this row borrows no key.
            case .centerOnArtboard: nil
            case .union: Shortcut(key: "u", modifiers: [.option, .command])
            case .outlineStroke: Shortcut(key: "o", modifiers: [.shift, .command])
            case .makeComponent: Shortcut(key: "k", modifiers: [.option, .command])
            // Show Panel is a setting with a checkmark; this row only hides.
            case .hidePanel: nil
            }
        }

        /// Layer > Stack Selection, the right-click row and this one: one name
        /// in all three places.
        public static let stackTitle = "Stack Selection"

        /// Whether a divider goes above the row: one above the two that remake
        /// an outline, as the icon mock draws it, one above Make Component,
        /// and one above the last, which acts on the window.
        public var startsSection: Bool {
            switch self {
            case .union, .makeComponent, .hidePanel: true
            default: false
            }
        }
    }
}
