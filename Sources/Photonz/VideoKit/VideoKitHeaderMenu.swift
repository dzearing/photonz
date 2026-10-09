// The plus or the three dots at the end of a dock section's header, which open
// that section's menu (`video.html`, `#efxMenu` and `#propMenu`).

import AppKit
import SwiftUI

extension VideoKit {

    /// A section header's menu: a glyph you click, and the menu that hangs
    /// from it.
    ///
    /// It builds its own AppKit menu for the same reason `Dropdown` does, and
    /// one more: it builds it again only when a row changes. A SwiftUI `Menu`
    /// rebuilt every row of its menu, and the accessibility of every row, each
    /// time anything in the document changed, whether or not the menu did.
    /// Four of them sit on a clip's headers, so every Undo and Redo on a video
    /// paid for four menus nobody had opened (lldb on `undo-redo-cost-walk`,
    /// 2026-10-08: one rebuild of each per press, and handing each its values
    /// behind `.equatable()` did not stop it).
    ///
    /// It stays a pull-down with a blank first row, the shape a SwiftUI menu
    /// has, so a walk reads its rows, and picks one, exactly as before.
    struct HeaderMenu: NSViewRepresentable {
        /// What accessibility calls it, and so what a walk reads it back by.
        let label: String
        /// The SF Symbol on its face: `plus` or `ellipsis`.
        let symbol: String
        /// What resting the pointer on it says. On the button itself: a
        /// SwiftUI `.help` around an AppKit view does not reach it.
        var help: String?
        let choices: [Choice]

        func makeNSView(context: Context) -> HeaderMenuButton {
            let button = HeaderMenuButton(symbol: symbol)
            updateNSView(button, context: context)
            return button
        }

        func updateNSView(_ button: HeaderMenuButton, context: Context) {
            button.show(symbol: symbol, isEnabled: context.environment.isEnabled)
            button.update(label: label, choices: choices)
            if button.toolTip != help { button.toolTip = help }
        }

        func sizeThatFits(_ proposal: ProposedViewSize, nsView button: HeaderMenuButton,
                          context: Context) -> CGSize? {
            button.host.fittingSize
        }
    }

    /// What `HeaderMenu` draws: the glyph a borderless SwiftUI menu drew,
    /// at its size and in its ink, dimmed with the button. That menu took no
    /// notice of a font on its label and drew the symbol at the control's
    /// own 13 points, with 3 points either side, so these are its numbers,
    /// measured off the window on 2026-10-08, and the headers did not move.
    struct HeaderMenuGlyph: View {
        var symbol: String
        var isEnabled = true

        var body: some View {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .padding(.horizontal, 3)
        }
    }

    /// The AppKit half of `HeaderMenu`: a borderless pull-down that draws
    /// nothing of its own and carries the glyph inside it.
    final class HeaderMenuButton: NSPopUpButton {
        let host: NSHostingView<HeaderMenuGlyph>
        private var actions: [@MainActor () -> Void] = []
        /// What the menu was last built from, so an update that changes
        /// nothing in it leaves it alone.
        private var built: [String]?

        init(symbol: String) {
            host = NSHostingView(rootView: HeaderMenuGlyph(symbol: symbol))
            super.init(frame: .zero, pullsDown: true)
            cell = DropdownCell(textCell: "", pullsDown: true)
            isBordered = false
            focusRingType = .default
            host.sizingOptions = [.intrinsicContentSize]
            host.translatesAutoresizingMaskIntoConstraints = true
            host.autoresizingMask = [.width, .height]
            addSubview(host)
            menu = NSMenu()
            menu?.autoenablesItems = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        func show(symbol: String, isEnabled: Bool) {
            if self.isEnabled != isEnabled { self.isEnabled = isEnabled }
            let glyph = HeaderMenuGlyph(symbol: symbol, isEnabled: isEnabled)
            if host.rootView.symbol != glyph.symbol || host.rootView.isEnabled != glyph.isEnabled {
                host.rootView = glyph
            }
        }

        func update(label: String, choices: [Choice]) {
            if accessibilityLabel() != label { setAccessibilityLabel(label) }
            actions = choices.map(\.action)
            let shape = choices.map {
                "\($0.kind)|\($0.title)|\($0.isOn)|\($0.isEnabled)|\($0.help ?? "")|"
                    + "\($0.image.map { ObjectIdentifier($0).hashValue } ?? 0)"
            }
            guard shape != built, let menu else { return }
            built = shape
            menu.removeAllItems()
            // A pull-down's first row is its title and is never shown.
            let title = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            title.isHidden = true
            menu.addItem(title)
            for (index, choice) in choices.enumerated() {
                switch choice.kind {
                case .divider:
                    menu.addItem(.separator())
                case .heading:
                    menu.addItem(.sectionHeader(title: choice.title))
                case .item:
                    let item = NSMenuItem(title: choice.title, action: #selector(pick(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = index
                    item.state = choice.isOn ? .on : .off
                    item.isEnabled = choice.isEnabled
                    item.image = choice.image
                    item.toolTip = choice.help
                    menu.addItem(item)
                }
            }
        }

        @objc private func pick(_ item: NSMenuItem) {
            guard actions.indices.contains(item.tag) else { return }
            actions[item.tag]()
        }

        override var title: String {
            get { "" }
            set { super.title = newValue }
        }

        override func layout() {
            super.layout()
            host.frame = bounds
        }

        /// Every point of the glyph is the button's.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard !isHidden, let superview else { return nil }
            return bounds.contains(convert(point, from: superview)) ? self : nil
        }

        override func draw(_ dirtyRect: NSRect) {}

        /// None: this button draws no bezel, so its frame is its face, and the
        /// glyph ends on the header's edge the way the menu's did.
        override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

        override var focusRingMaskBounds: NSRect { bounds }

        override func drawFocusRingMask() {
            NSBezierPath(roundedRect: bounds.insetBy(dx: -2, dy: -2), xRadius: 4, yRadius: 4).fill()
        }

        /// Hangs the menu from the glyph's left edge, just under it.
        private func openMenu() {
            guard let menu, isEnabled else { return }
            let below = isFlipped ? bounds.maxY + 3 : bounds.minY - 3
            menu.popUp(positioning: nil, at: NSPoint(x: bounds.minX, y: below), in: self)
        }

        override func mouseDown(with event: NSEvent) { openMenu() }

        override func performClick(_ sender: Any?) { openMenu() }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 || event.keyCode == 76 || event.charactersIgnoringModifiers == " " {
                performClick(nil)
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
