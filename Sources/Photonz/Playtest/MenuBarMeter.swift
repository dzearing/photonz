// Counts what happens to the menu bar, so a walk can prove playing a video
// leaves it alone. Probe-only, like the rest of the harness.
#if PHOTONZ_PLAYTEST
import AppKit

/// Every row added to, taken out of or changed in the app's menu bar, counted
/// into `ViewBuildMeter` so `expectBuilds` can claim a ceiling on it.
///
/// This exists because of a flicker a person saw (2026-10-11): while a video
/// played, the menus at the top of the screen flashed as if rows were being
/// taken down and put back, and stopped the moment it paused. A body count
/// alone cannot say the bar changed, since SwiftUI may run a body and find
/// nothing different; these notifications are AppKit telling us a row really
/// did change, which is what the person sees.
@MainActor
final class MenuBarMeter {
    static let shared = MenuBarMeter()
    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true
        let center = NotificationCenter.default
        for name in [NSMenu.didAddItemNotification, NSMenu.didRemoveItemNotification,
                     NSMenu.didChangeItemNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                // AppKit posts these on the main thread, about menus that only
                // ever live there, and `.main` delivers them there too.
                nonisolated(unsafe) let menu = note.object as? NSMenu
                let kind = name
                MainActor.assumeIsolated { MenuBarMeter.shared.saw(kind, in: menu) }
            }
        }
    }

    private func saw(_ name: Notification.Name, in menu: NSMenu?) {
        guard let menu, let bar = NSApp.mainMenu, Self.belongs(menu, to: bar) else { return }
        ViewBuildMeter.shared.built(menu === bar ? .menuBarTitle : .menuBarRow)
        if name != NSMenu.didChangeItemNotification {
            ViewBuildMeter.shared.built(.menuBarRowAddedOrRemoved)
        }
        if menu === bar, name == NSMenu.didAddItemNotification {
            ViewBuildMeter.shared.note("bar now \(bar.items.map(\.title).joined(separator: ","))")
        }
    }

    /// Whether `menu` is the bar itself or hangs anywhere under it. Depth is
    /// capped so a menu that somehow refers to itself cannot spin.
    private static func belongs(_ menu: NSMenu, to bar: NSMenu) -> Bool {
        var current: NSMenu? = menu
        for _ in 0..<8 {
            guard let here = current else { return false }
            if here === bar { return true }
            current = here.supermenu
        }
        return false
    }
}
#endif
