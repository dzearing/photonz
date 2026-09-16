// A menu, written down once and drawn two ways.
//
// The layers list draws its row menu with SwiftUI, because it hangs off a
// SwiftUI row. The canvas cannot: a menu aimed at a POINT has to be built in
// the same event that opens it, and SwiftUI resolves a `.contextMenu`'s
// contents when the view around it updates, not when the menu pops up. Wired
// that way the canvas opened the menu for whatever the PREVIOUS right click had
// been over — right clicking a fresh group and choosing Delete removed one of
// its children and left the group standing (2026-09-16). So the canvas builds
// an ordinary `NSMenu`, there and then.
//
// Two drawings of a menu are two chances for it to disagree with itself, so
// neither surface owns the list. The list is here, as plain values, and each
// surface only turns it into rows.

import AppKit
import SwiftUI

/// The key printed against a row, in both alphabets at once: SwiftUI wants a
/// `KeyEquivalent` and `EventModifiers`, AppKit wants a string and an
/// `NSEvent.ModifierFlags`, and a row that gave them different answers would
/// print one shortcut in the list and another on the picture.
struct MenuShortcut {
    let key: Character
    let modifiers: EventModifiers

    static func command(_ key: Character) -> MenuShortcut {
        MenuShortcut(key: key, modifiers: .command)
    }

    static func commandShift(_ key: Character) -> MenuShortcut {
        MenuShortcut(key: key, modifiers: [.command, .shift])
    }

    static func commandOption(_ key: Character) -> MenuShortcut {
        MenuShortcut(key: key, modifiers: [.command, .option])
    }

    /// ⌘⌫. The character is the one both frameworks draw as ⌫.
    static var commandDelete: MenuShortcut { MenuShortcut(key: "\u{7F}", modifiers: .command) }

    var keyEquivalent: KeyEquivalent { KeyEquivalent(key) }

    var appKitFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }
}

/// One row of a menu, with no opinion about who draws it.
struct MenuRow: Identifiable {
    enum Kind {
        /// A plain command.
        case command
        /// A setting that says what it IS and wears a checkmark, rather than an
        /// action whose name flips under the pointer (`MenuToggleNames`).
        case toggle(isOn: Bool)
        /// A row that opens a list of its own.
        case submenu([MenuRow])
        case separator
    }

    let id = UUID()
    var title: String = ""
    var shortcut: MenuShortcut?
    /// False draws the row greyed. Used only where the reason is visible in the
    /// menu itself; everywhere else a row that cannot act is left OUT, so
    /// nobody has to hunt for why a row is dead.
    var isEnabled: Bool = true
    var isDestructive: Bool = false
    var kind: Kind = .command
    var run: @MainActor () -> Void = {}

    static var separator: MenuRow { MenuRow(kind: .separator) }

    static func command(_ title: String, _ shortcut: MenuShortcut? = nil,
                        enabled: Bool = true, destructive: Bool = false,
                        run: @escaping @MainActor () -> Void) -> MenuRow {
        MenuRow(title: title, shortcut: shortcut, isEnabled: enabled,
                isDestructive: destructive, kind: .command, run: run)
    }

    static func toggle(_ title: String, isOn: Bool,
                       run: @escaping @MainActor () -> Void) -> MenuRow {
        MenuRow(title: title, kind: .toggle(isOn: isOn), run: run)
    }

    static func submenu(_ title: String, _ rows: [MenuRow]) -> MenuRow {
        MenuRow(title: title, kind: .submenu(rows))
    }
}

// MARK: - Drawn by SwiftUI

/// The rows as SwiftUI menu content, for a `.contextMenu` or a `Menu`.
struct MenuRowsView: View {
    let rows: [MenuRow]

    var body: some View {
        ForEach(rows) { row in
            switch row.kind {
            case .separator:
                Divider()
            case .toggle(let isOn):
                Toggle(row.title, isOn: Binding(get: { isOn }, set: { _ in row.run() }))
            case .submenu(let inner):
                Menu(row.title) { MenuRowsView(rows: inner) }
            case .command:
                command(row)
            }
        }
    }

    @ViewBuilder
    private func command(_ row: MenuRow) -> some View {
        let button = Button(row.title, role: row.isDestructive ? .destructive : nil) { row.run() }
            .disabled(!row.isEnabled)
        if let shortcut = row.shortcut {
            button.keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.modifiers)
        } else {
            button
        }
    }
}

// MARK: - Drawn by AppKit

/// An `NSMenuItem` that runs a closure, so a row written once can be pressed
/// from a menu AppKit built.
private final class MenuRowItem: NSMenuItem {
    private let run: @MainActor () -> Void

    init(row: MenuRow) {
        run = row.run
        super.init(title: row.title, action: nil, keyEquivalent: "")
        if let shortcut = row.shortcut {
            keyEquivalent = String(shortcut.key)
            keyEquivalentModifierMask = shortcut.appKitFlags
        }
        if case .toggle(let isOn) = row.kind { state = isOn ? .on : .off }
        isEnabled = row.isEnabled
        target = self
        action = #selector(fire)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }

    @MainActor @objc private func fire() { run() }
}

extension NSMenu {
    /// The rows as a real `NSMenu`, built at the moment it is needed.
    @MainActor static func rows(_ rows: [MenuRow]) -> NSMenu {
        let menu = NSMenu()
        // Off, or AppKit greys every row whose action nothing in the responder
        // chain answers — which is all of them, since each row carries its own.
        menu.autoenablesItems = false
        for row in rows {
            switch row.kind {
            case .separator:
                menu.addItem(.separator())
            case .submenu(let inner):
                let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
                item.submenu = NSMenu.rows(inner)
                menu.addItem(item)
            case .command, .toggle:
                menu.addItem(MenuRowItem(row: row))
            }
        }
        return menu
    }
}
