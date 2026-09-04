import AppKit
import PhotonzCore

/// Keeps the menu-bar titles that change with what is on screen honest.
///
/// SwiftUI builds the Capture menu from a `Commands` body, and it re-runs that
/// body only while it is processing an event — not when the value the title
/// reads changes. A shortcut is exactly that kind of event, so pressing ⇧⌘H
/// rebuilds the menu from the state BEFORE the item's action runs, and the
/// title is left one toggle behind: history is on screen and the menu still
/// offers to show it. Nothing later disturbs it (proven on 2026-09-04 with five
/// menu readings over six seconds, all stale).
///
/// So the app writes the true title onto the live item itself, right after the
/// state changes. A later SwiftUI rebuild reads the same state and writes the
/// same string, so the two never fight.
@MainActor
enum MainMenuTitles {
    /// Retitle the Show/Hide History item wherever it sits in the menu bar.
    /// Matched by both of its readings, because which one it is wearing right
    /// now is the thing being corrected.
    static func retitleHistory(isShown: Bool, in bar: NSMenu? = NSApp.mainMenu) {
        retitle(anyOf: CaptureMenuNames.historyNames,
                to: CaptureMenuNames.history(isShown: isShown), in: bar)
    }

    private static func retitle(anyOf readings: [String], to title: String, in bar: NSMenu?) {
        guard let bar else { return }
        for top in bar.items {
            guard let submenu = top.submenu else { continue }
            for item in submenu.items where readings.contains(item.title) && item.title != title {
                item.title = title
            }
        }
    }
}
