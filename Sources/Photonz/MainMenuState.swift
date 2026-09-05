import AppKit
import PhotonzCore

/// Keeps the menu-bar checkmarks that change with what is on screen honest.
///
/// SwiftUI builds the Capture menu from a `Commands` body, and it re-runs that
/// body only while it is processing an event — not when the value the item
/// reads changes. A shortcut is exactly that kind of event, so pressing ⇧⌘H
/// rebuilds the menu from the state BEFORE the item's action runs, and the item
/// is left one toggle behind: history is on screen and the menu still says it
/// is not. Nothing later disturbs it (proven on 2026-09-04 with five menu
/// readings over six seconds, all stale).
///
/// So the app writes the true state onto the live item itself, right after it
/// changes. A later SwiftUI rebuild reads the same state and writes the same
/// value, so the two never fight.
///
/// It used to be the item's TITLE that was corrected here, back when the item
/// renamed itself Hide History. It keeps one name now and wears a checkmark
/// instead (`MenuToggleNames`), which is both easier to find in a live menu and
/// what the item reports to accessibility.
@MainActor
enum MainMenuState {
    /// Tick or untick the Show History item wherever it sits in the menu bar.
    static func markHistory(isShown: Bool, in bar: NSMenu? = NSApp.mainMenu) {
        mark(named: CaptureMenuNames.history, isOn: isShown, in: bar)
    }

    private static func mark(named name: String, isOn: Bool, in bar: NSMenu?) {
        guard let bar else { return }
        let wanted: NSControl.StateValue = isOn ? .on : .off
        for top in bar.items {
            guard let submenu = top.submenu else { continue }
            for item in submenu.items where item.title == name && item.state != wanted {
                item.state = wanted
            }
        }
    }
}
