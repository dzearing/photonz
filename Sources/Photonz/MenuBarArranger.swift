import AppKit
import PhotonzCore

/// Keeps View where a pro Mac editor has it: after the menus for what the
/// document is made of, straight before Window (`MenuBarOrder`).
///
/// SwiftUI puts every `CommandMenu` after its own View menu and offers no way
/// to say otherwise, and it rebuilds the bar as scenes come and go and adds
/// Clip and Sequence the moment a video comes forward, each time after View.
/// So the order is checked after every event the app handles
/// (`NSApplication.didUpdateNotification`) and View moved back when it is out
/// of place. The check reads a dozen titles, so it costs nothing; the move
/// happens only on the pass after SwiftUI touched the bar.
///
/// Next only (`next-a-pro-menu-bar`): with the flag off the bar is exactly
/// what SwiftUI builds.
@MainActor
enum MenuBarArranger {
    private static var observers: [NSObjectProtocol] = []
    private static var barWatch: NSKeyValueObservation?
    private static var pending = false

    static func start() {
        guard observers.isEmpty else { return }
        arrange()
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didUpdateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { arrange() }
        })
        // SwiftUI also rebuilds the bar outside any event (after a context
        // menu closes, measured 2026-09-30 in `pro-menu-bar-walk`), which left
        // View in SwiftUI's place until the next event. So a menu added to the
        // bar, or a whole new bar, is put right on the next turn of the run
        // loop, once SwiftUI has finished its own insertions.
        observers.append(center.addObserver(
            forName: NSMenu.didAddItemNotification, object: nil, queue: .main) { note in
            let isTheBar = (note.object as AnyObject?) === NSApp.mainMenu
            if isTheBar { MainActor.assumeIsolated { arrangeSoon() } }
        })
        barWatch = NSApp.observe(\.mainMenu, options: [.new]) { _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { arrangeSoon() } }
        }
    }

    private static func arrangeSoon() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                pending = false
                arrange()
            }
        }
    }

    static func arrange(_ bar: NSMenu? = NSApp.mainMenu) {
        guard Experiments.shared.proMenuBarEnabled, let bar,
              let move = MenuBarOrder.viewMove(in: bar.items.map(\.title)) else { return }
        let view = bar.items[move.from]
        bar.removeItem(at: move.from)
        bar.insertItem(view, at: move.to)
    }
}
