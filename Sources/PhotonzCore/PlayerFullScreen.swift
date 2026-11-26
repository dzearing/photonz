import Foundation

/// **Full screen for a player**: F fills the screen with the video you are
/// watching and F or Escape bring it back, the way QuickTime and every web
/// player have it. View ▸ Enter Full Screen carries the Mac's own ⌃⌘F in
/// every window, picture or video, View or Edit.
///
/// F is the player's only while the window is one (`ViewEditMode.view`): in
/// the editor F stays the Frame tool, Photoshop's place for it being taken by
/// Lens (the user, 2026-10-11, asked for F in the player; the editor's F is a
/// question of its own).
///
/// The transport fades away in full screen as it does in a window
/// (`PlayerControlsFade`). The menu bar is the Mac's own business in
/// full screen: it stays away until the pointer reaches the top.
public enum PlayerFullScreen {

    /// What a key does to full screen.
    public enum Command: Equatable, Sendable {
        /// In if out, out if in.
        case toggle
        /// Out, and nothing if already out.
        case leave
    }

    /// The plain letter that toggles it while watching.
    public static let key: Character = "f"

    /// The Mac's own chord for it, as the View menu prints it.
    public static let menuShortcut = "⌃⌘F"

    /// What the transport's button says on hover.
    public static let tooltip = "Full Screen (F)"

    /// What `press` does to full screen, or nil when it is not full screen's
    /// press at all and carries on to whatever would have had it.
    ///
    /// - Parameters:
    ///   - watching: the window is a player (`ViewEditMode.view`).
    ///   - isFullScreen: the window fills the screen right now.
    public static func command(for press: TimelineKeyPress, watching: Bool, isFullScreen: Bool) -> Command? {
        guard watching, press.modifiers.isEmpty, !press.isRepeat else { return nil }
        switch press.key {
        case .letter(key): return .toggle
        case .escape: return isFullScreen ? .leave : nil
        default: return nil
        }
    }

    /// The View menu's row: what picking it will do, the Mac's own words.
    public static func menuTitle(isFullScreen: Bool) -> String {
        isFullScreen ? "Exit Full Screen" : "Enter Full Screen"
    }
}
