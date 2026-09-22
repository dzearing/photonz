import AppKit
import PhotonzCore
import SwiftUI

// The chip that says what this window is set up for, and swaps it
// (Next, `next-window-modes`; study `docs/design/modes.md` §2 and §3).
//
// It sits at the LEADING end of the window's own title bar, right of the
// traffic lights, which is where a Mac keeps what a window is about and where
// the study drew it: "a quiet chip in the window's status, beside the
// document's name". The editor window is `hiddenTitleBar`, so the name itself
// is not drawn anywhere — the chip is the only thing standing in that space,
// and it is the nearest thing this window has to a status.
//
// It is deliberately NOT a row of tabs up here. Three tabs read as navigating
// between three applications, which is the exact impression this whole
// direction exists to avoid; a popup reads as state. That was ruled on in the
// study before any of this was built.

/// Puts the mode chip in the host window's title bar, at the leading end.
///
/// Put it in a `.background`: it draws nothing itself and takes no space. Built
/// once and left alone, for the reason `TitlebarPanelToggleInstaller` is:
/// handing the title bar a fresh root view on every pass of the editor's body
/// re-measures the accessory, which lays the window out, which runs the
/// editor's body again.
struct TitlebarModeChipInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> InstallerView { InstallerView() }

    func updateNSView(_ view: InstallerView, context: Context) { view.install() }

    static func dismantleNSView(_ view: InstallerView, coordinator: ()) { view.remove() }

    final class InstallerView: NSView {
        private let accessoryView: NSView
        private var accessory: NSTitlebarAccessoryViewController?

        init() {
            let chip = NSHostingView(rootView: TitlebarModeChip())
            // A fixed box, not a self-sizing one, for the reason the panel
            // toggle's is fixed: a leading accessory takes the size of the view
            // it is given, so a view that re-measures itself would shove the
            // title bar about every time the label changed. Wide enough for the
            // longest thing the chip can say ("Everything, edited"), with the
            // chip left-aligned inside it so the rest is simply empty title bar.
            let box = NSView(frame: CGRect(x: 0, y: 0,
                                           width: TitlebarModeChip.boxWidth,
                                           height: TitlebarModeChip.barHeight))
            chip.frame = box.bounds
            chip.autoresizingMask = [.width, .height]
            box.addSubview(chip)
            accessoryView = box
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            install()
        }

        func install() {
            guard let window, accessory == nil else { return }
            let controller = NSTitlebarAccessoryViewController()
            controller.layoutAttribute = .leading
            controller.view = accessoryView
            // Zero on purpose, exactly as the panel toggle's is: full screen
            // takes the title bar away along with its accessories, and the
            // keyboard (⌃1 … ⌃4) and View ▸ Mode are still the way in.
            controller.fullScreenMinHeight = 0
            window.addTitlebarAccessoryViewController(controller)
            accessory = controller
        }

        func remove() {
            guard let controller = accessory else { return }
            if let window = controller.view.window,
               let index = window.titlebarAccessoryViewControllers.firstIndex(of: controller) {
                window.removeTitlebarAccessoryViewController(at: index)
            }
            accessory = nil
        }
    }
}

/// The chip itself: what this window is set up for, and the list that changes
/// it.
struct TitlebarModeChip: View {
    @State private var modes = WindowModeStore.shared
    /// Watched as well as the mode, because the chip says whether you have bent
    /// the mode by hand and that is a fact about the panel's choices.
    @State private var sections = PanelSectionVisibilityStore.shared
    @State private var isOpen = false

    /// The title bar's own height, so the chip is centred in it the way the
    /// traffic lights are.
    static let barHeight: CGFloat = 28
    /// How far the chip sits off the traffic lights.
    static let leadingInset: CGFloat = 10
    /// The whole accessory: room for the widest label, and the gap before it.
    static let boxWidth: CGFloat = 176

    private var label: String {
        modes.session.chipLabel(with: sections.choices)
    }

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: modes.mode.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 8)
            .padding(.trailing, 7)
            .frame(height: 20)
            // A capsule with a hairline and no fill: quiet furniture that says
            // a state, not a button competing with the traffic lights beside
            // it.
            .background(
                Capsule().strokeBorder(.separator, lineWidth: 1))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .frame(width: Self.boxWidth - Self.leadingInset,
               height: Self.barHeight, alignment: .leading)
        .padding(.leading, Self.leadingInset)
        // Below, always: the chip is at the very top of the window, and a
        // tooltip drawn above it would land off the top of the screen.
        .toolTip(WindowModeCopy.chipTooltip, below: true)
        // One name in every mode, because it is one control in one place: a
        // walk asks for "Mode" and reads what it currently says.
        .playtestControl(WindowModeCopy.chipControl, detail: label)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            WindowModeList(modes: modes, sections: sections) { isOpen = false }
        }
        .onChange(of: isOpen) { _, open in
            if open { escapeWatch.start { isOpen = false } } else { escapeWatch.stop() }
        }
        .onDisappear { escapeWatch.stop() }
    }

    // Escape takes the list down, the way it takes down the Sections list at
    // the foot of the panel, and for the same measured reason: nothing in a
    // popover holds the keyboard, so an Escape would otherwise reach the canvas
    // and clear the selection while the list stayed up.
    @State private var escapeWatch = PanelSectionsEscapeWatch()
}

/// The list the chip opens: every mode, then the two ways out.
struct WindowModeList: View {
    @Bindable var modes: WindowModeStore
    @Bindable var sections: PanelSectionVisibilityStore
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(WindowModeCopy.listTitle)
                .font(.subheadline.weight(.semibold))
            Text(WindowModeCopy.listBlurb)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(WindowModes.swappable) { mode in
                    row(mode)
                }
            }
            Divider()
            // The panic button, first under the line so it is findable when you
            // are annoyed. It is the same act as Use Automatic For All at the
            // foot of the panel, and says so by landing you in Everything.
            action(WindowModeCopy.showEverything,
                   symbol: "arrow.uturn.backward",
                   detail: "hands every folded section back and leaves the mode",
                   enabled: modes.mode.id != WindowModes.everythingID || modes.isBent) {
                modes.showEverything()
            }
            // Only offered on a mode you have actually bent, because only a
            // bent mode has anything to put back.
            if modes.isBent, modes.mode.id != WindowModes.everythingID {
                action(WindowModeCopy.resetMode(modes.mode.title),
                       symbol: "arrow.counterclockwise",
                       detail: "puts this mode back the way it shipped",
                       enabled: true) {
                    modes.resetCurrent()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Wide enough for the longest summary on ONE line: Redline's ran off
        // the end at 286 and read "Measuring a capture, handing over a s…",
        // which is a description that stops before it says anything.
        .frame(width: 324)
    }

    @ViewBuilder private func row(_ mode: WindowMode) -> some View {
        let picked = mode.id == modes.session.modeID
        Button {
            modes.swap(to: mode.id)
            close()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: picked ? "checkmark" : mode.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(picked ? Color.accentColor : .secondary)
                    .frame(width: 14, alignment: .center)
                // Both inks are named rather than left to whatever the button
                // hands down, so the mode's NAME always outranks its one-line
                // description however the window happens to stand. A label
                // colour is a static semantic colour: it says the same thing in
                // both themes and whether or not the window is key, which a
                // hierarchical style inside a plain button does not.
                VStack(alignment: .leading, spacing: 0) {
                    Text(mode.title)
                        .font(.callout)
                        .foregroundStyle(Color(nsColor: .labelColor))
                    Text(mode.summary)
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let number = WindowModes.shortcutNumber(for: mode.id) {
                    Text("⌃\(number)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 3)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .playtestControl(WindowModeCopy.modeControl(mode.title),
                         detail: picked ? "the mode this window is in"
                                        : "swaps the window into \(mode.title)")
    }

    @ViewBuilder private func action(_ title: String, symbol: String, detail: String,
                                     enabled: Bool, run: @escaping () -> Void) -> some View {
        Button {
            run()
            close()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, alignment: .center)
                Text(title).font(.callout).foregroundStyle(Color(nsColor: .labelColor))
                Spacer(minLength: 4)
            }
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .playtestControl(title, detail: detail)
    }
}

/// One word for a mode everywhere it is named: this chip, the View menu's
/// submenu, the tooltip and the name a walk asks for all come out of here, so
/// they cannot drift apart.
enum WindowModeCopy {
    static let chipControl = "Mode"
    static let chipTooltip = "What this window is set up for"
    static let menuTitle = "Mode"
    static let listTitle = "Mode"
    static let listBlurb = "A mode folds the panel down to what one job needs. "
        + "It never touches the document, and everything it folds is one click from coming back."
    static let showEverything = "Show Everything"
    static func resetMode(_ title: String) -> String { "Reset \(title)" }
    static func modeControl(_ title: String) -> String { "\(title) mode" }
}
